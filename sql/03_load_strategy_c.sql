-- Strategy C: Integer-Range 15-min Partition
-- Copies from Strategy A, adds interval_15min, filtered to 104-day window
-- (Mar 15 – Jun 27) due to BQ's 10,000 partition limit.
-- Expected: ~15M rows (104 days × 100 cells × 1440 min/day)

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
