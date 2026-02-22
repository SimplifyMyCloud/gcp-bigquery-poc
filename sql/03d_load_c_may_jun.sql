-- Strategy C Chunk 3: May 24 – Jun 27 (35 days × 96 partitions/day = 3,360)
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
WHERE timestamp >= TIMESTAMP '2025-05-24 00:00:00 UTC'
  AND timestamp < TIMESTAMP '2025-06-27 00:00:00 UTC';
