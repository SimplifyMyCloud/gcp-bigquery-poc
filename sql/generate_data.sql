-- =============================================================================
-- Generate synthetic cell network data directly in BigQuery
-- No file uploads needed — all data is generated server-side.
--
-- This creates ~52.56M rows (365 days × 100 cells × 1440 min/day)
-- with realistic time-of-day load patterns and per-cell characteristics.
--
-- Usage: Run each section separately or as a script via bq CLI.
-- =============================================================================

-- ─── Strategy A: Hourly Partition ───────────────────────────────────────────

TRUNCATE TABLE `simplifymycloud-dev.cell_network_poc.metrics_hourly_part`;

INSERT INTO `simplifymycloud-dev.cell_network_poc.metrics_hourly_part`
  (timestamp, cell_id, site_id, region_id,
   signal_strength_dbm, latency_ms, jitter_ms,
   throughput_mbps, packet_loss_pct, connected_users)
WITH
  -- Generate 1-minute timestamps for 365 days
  timestamps AS (
    SELECT ts
    FROM UNNEST(
      GENERATE_TIMESTAMP_ARRAY(
        TIMESTAMP '2025-01-01 00:00:00 UTC',
        TIMESTAMP '2025-12-31 23:59:00 UTC',
        INTERVAL 1 MINUTE
      )
    ) AS ts
  ),
  -- Generate 100 cell towers with deterministic per-cell characteristics
  cells AS (
    SELECT
      cell_num,
      FORMAT('CELL_%03d', cell_num) AS cell_id,
      FORMAT('SITE_%02d', DIV(cell_num - 1, 5) + 1) AS site_id,
      CASE MOD(cell_num - 1, 3)
        WHEN 0 THEN 'us-west'
        WHEN 1 THEN 'us-central'
        ELSE 'us-east'
      END AS region_id,
      -- Per-cell base characteristics (deterministic from cell_num)
      -70.0 + MOD(ABS(FARM_FINGERPRINT(CAST(cell_num AS STRING))), 3000) / 100.0 AS base_signal,
      10.0 + MOD(ABS(FARM_FINGERPRINT(CONCAT('lat_', CAST(cell_num AS STRING)))), 3000) / 100.0 AS base_latency,
      50.0 + MOD(ABS(FARM_FINGERPRINT(CONCAT('tp_', CAST(cell_num AS STRING)))), 15000) / 100.0 AS base_throughput,
      20 + MOD(ABS(FARM_FINGERPRINT(CONCAT('usr_', CAST(cell_num AS STRING)))), 180) AS base_users
    FROM UNNEST(GENERATE_ARRAY(1, 100)) AS cell_num
  ),
  -- Cross join: every minute × every cell
  raw_data AS (
    SELECT
      t.ts AS timestamp,
      c.cell_id,
      c.site_id,
      c.region_id,
      c.base_signal,
      c.base_latency,
      c.base_throughput,
      c.base_users,
      -- Time-of-day load factor
      CASE
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 0 AND 5 THEN 0.3
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 6 AND 8 THEN 0.8
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 9 AND 11 THEN 1.5
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 12 AND 13 THEN 1.2
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 14 AND 17 THEN 1.8
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 18 AND 20 THEN 1.4
        ELSE 0.6
      END AS load_factor,
      -- Per-row randomness (deterministic from timestamp + cell)
      FARM_FINGERPRINT(CONCAT(CAST(t.ts AS STRING), c.cell_id)) AS row_hash
    FROM timestamps t
    CROSS JOIN cells c
  )
SELECT
  timestamp,
  cell_id,
  site_id,
  region_id,
  -- Signal strength: base + noise, clamped to [-120, -30]
  ROUND(GREATEST(-120.0, LEAST(-30.0,
    base_signal + (MOD(ABS(row_hash), 1000) - 500) / 100.0
  )), 2) AS signal_strength_dbm,
  -- Latency: base × load_factor + noise, clamped to [1, 500]
  ROUND(GREATEST(1.0, LEAST(500.0,
    base_latency * load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 7)), 400) - 200) / 1000.0)
  )), 2) AS latency_ms,
  -- Jitter: ~10% of latency + noise
  ROUND(GREATEST(0.1, LEAST(100.0,
    base_latency * load_factor * 0.1 * (1.0 + MOD(ABS(DIV(row_hash, 13)), 200) / 200.0)
  )), 2) AS jitter_ms,
  -- Throughput: base / load_factor + noise
  ROUND(GREATEST(1.0, LEAST(1000.0,
    base_throughput / load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 17)), 300) - 150) / 1000.0)
  )), 2) AS throughput_mbps,
  -- Packet loss: higher under load
  ROUND(GREATEST(0.0, LEAST(15.0,
    0.5 * load_factor * (1.0 + MOD(ABS(DIV(row_hash, 23)), 200) / 200.0)
  )), 3) AS packet_loss_pct,
  -- Connected users: base × load_factor + noise
  GREATEST(1, CAST(ROUND(
    base_users * load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 29)), 200) - 100) / 1000.0)
  ) AS INT64)) AS connected_users
FROM raw_data;


-- ─── Strategy B: Daily Partition + 15-min Cluster ───────────────────────────

TRUNCATE TABLE `simplifymycloud-dev.cell_network_poc.metrics_daily_part_15min_cluster`;

INSERT INTO `simplifymycloud-dev.cell_network_poc.metrics_daily_part_15min_cluster`
  (timestamp, cell_id, site_id, region_id,
   signal_strength_dbm, latency_ms, jitter_ms,
   throughput_mbps, packet_loss_pct, connected_users,
   quarter_hour_bucket)
SELECT
  timestamp, cell_id, site_id, region_id,
  signal_strength_dbm, latency_ms, jitter_ms,
  throughput_mbps, packet_loss_pct, connected_users,
  CAST(DIV(EXTRACT(MINUTE FROM timestamp), 15) * 15 AS INT64) AS quarter_hour_bucket
FROM `simplifymycloud-dev.cell_network_poc.metrics_hourly_part`;


-- ─── Strategy C: Integer-Range 15-min Partition ─────────────────────────────
-- Only loads ~104 days (Mar 15 – Jun 27) due to BQ 10,000 partition limit.

TRUNCATE TABLE `simplifymycloud-dev.cell_network_poc.metrics_15min_int_range`;

INSERT INTO `simplifymycloud-dev.cell_network_poc.metrics_15min_int_range`
  (timestamp, cell_id, site_id, region_id,
   signal_strength_dbm, latency_ms, jitter_ms,
   throughput_mbps, packet_loss_pct, connected_users,
   interval_15min)
SELECT
  timestamp, cell_id, site_id, region_id,
  signal_strength_dbm, latency_ms, jitter_ms,
  throughput_mbps, packet_loss_pct, connected_users,
  CAST(DIV(UNIX_SECONDS(timestamp), 900) AS INT64) AS interval_15min
FROM `simplifymycloud-dev.cell_network_poc.metrics_hourly_part`
WHERE timestamp >= TIMESTAMP '2025-03-15 00:00:00 UTC'
  AND timestamp < TIMESTAMP '2025-06-27 00:00:00 UTC';
