output "dataset_id" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.cell_network_poc.dataset_id
}

output "dataset_self_link" {
  description = "BigQuery dataset self link"
  value       = google_bigquery_dataset.cell_network_poc.self_link
}

output "table_hourly_partition" {
  description = "Strategy A: Hourly partitioned table ID"
  value       = google_bigquery_table.metrics_hourly_part.table_id
}

output "table_daily_partition_15min_cluster" {
  description = "Strategy B: Daily partitioned + 15-min clustered table ID"
  value       = google_bigquery_table.metrics_daily_part_15min_cluster.table_id
}

output "table_15min_int_range" {
  description = "Strategy C: Integer-range 15-min partitioned table ID"
  value       = google_bigquery_table.metrics_15min_int_range.table_id
}

output "staging_bucket" {
  description = "GCS staging bucket for BQ load jobs"
  value       = google_storage_bucket.staging.name
}
