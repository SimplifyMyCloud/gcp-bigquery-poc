-- Strategy B: Daily Partition + 15-min Cluster
-- Copies from Strategy A and adds the quarter_hour_bucket derived column.

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
