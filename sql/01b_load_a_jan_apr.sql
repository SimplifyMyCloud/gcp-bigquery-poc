-- Strategy A Chunk 1: Jan–Apr (120 days × 24h = 2,880 partitions)
INSERT INTO `simplifymycloud-dev.cell_network_poc.metrics_hourly_part`
  (timestamp, cell_id, site_id, region_id,
   signal_strength_dbm, latency_ms, jitter_ms,
   throughput_mbps, packet_loss_pct, connected_users)
WITH
  timestamps AS (
    SELECT ts FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
      TIMESTAMP '2025-01-01 00:00:00 UTC',
      TIMESTAMP '2025-04-30 23:59:00 UTC',
      INTERVAL 1 MINUTE
    )) AS ts
  ),
  cells AS (
    SELECT cell_num,
      FORMAT('CELL_%03d', cell_num) AS cell_id,
      FORMAT('SITE_%02d', DIV(cell_num - 1, 5) + 1) AS site_id,
      CASE MOD(cell_num - 1, 3) WHEN 0 THEN 'us-west' WHEN 1 THEN 'us-central' ELSE 'us-east' END AS region_id,
      -70.0 + MOD(ABS(FARM_FINGERPRINT(CAST(cell_num AS STRING))), 3000) / 100.0 AS base_signal,
      10.0 + MOD(ABS(FARM_FINGERPRINT(CONCAT('lat_', CAST(cell_num AS STRING)))), 3000) / 100.0 AS base_latency,
      50.0 + MOD(ABS(FARM_FINGERPRINT(CONCAT('tp_', CAST(cell_num AS STRING)))), 15000) / 100.0 AS base_throughput,
      20 + MOD(ABS(FARM_FINGERPRINT(CONCAT('usr_', CAST(cell_num AS STRING)))), 180) AS base_users
    FROM UNNEST(GENERATE_ARRAY(1, 100)) AS cell_num
  ),
  raw_data AS (
    SELECT t.ts AS timestamp, c.*,
      CASE
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 0 AND 5 THEN 0.3
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 6 AND 8 THEN 0.8
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 9 AND 11 THEN 1.5
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 12 AND 13 THEN 1.2
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 14 AND 17 THEN 1.8
        WHEN EXTRACT(HOUR FROM t.ts) BETWEEN 18 AND 20 THEN 1.4
        ELSE 0.6
      END AS load_factor,
      FARM_FINGERPRINT(CONCAT(CAST(t.ts AS STRING), c.cell_id)) AS row_hash
    FROM timestamps t CROSS JOIN cells c
  )
SELECT timestamp, cell_id, site_id, region_id,
  ROUND(GREATEST(-120.0, LEAST(-30.0, base_signal + (MOD(ABS(row_hash), 1000) - 500) / 100.0)), 2),
  ROUND(GREATEST(1.0, LEAST(500.0, base_latency * load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 7)), 400) - 200) / 1000.0))), 2),
  ROUND(GREATEST(0.1, LEAST(100.0, base_latency * load_factor * 0.1 * (1.0 + MOD(ABS(DIV(row_hash, 13)), 200) / 200.0))), 2),
  ROUND(GREATEST(1.0, LEAST(1000.0, base_throughput / load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 17)), 300) - 150) / 1000.0))), 2),
  ROUND(GREATEST(0.0, LEAST(15.0, 0.5 * load_factor * (1.0 + MOD(ABS(DIV(row_hash, 23)), 200) / 200.0))), 3),
  GREATEST(1, CAST(ROUND(base_users * load_factor * (1.0 + (MOD(ABS(DIV(row_hash, 29)), 200) - 100) / 1000.0)) AS INT64))
FROM raw_data;
