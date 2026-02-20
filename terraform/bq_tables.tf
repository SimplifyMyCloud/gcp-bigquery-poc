# =============================================================================
# Common schema fields used across all table strategies
# =============================================================================
locals {
  # Base schema fields present in every table
  base_schema = [
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Measurement timestamp (1-minute resolution)"
    },
    {
      name        = "cell_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique cell tower identifier (e.g. CELL_001)"
    },
    {
      name        = "site_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Cell site identifier (e.g. SITE_01)"
    },
    {
      name        = "region_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Geographic region (e.g. us-west, us-central, us-east)"
    },
    {
      name        = "signal_strength_dbm"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Signal strength in dBm (typical range: -120 to -50)"
    },
    {
      name        = "latency_ms"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Round-trip latency in milliseconds"
    },
    {
      name        = "jitter_ms"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Jitter in milliseconds"
    },
    {
      name        = "throughput_mbps"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Throughput in Mbps"
    },
    {
      name        = "packet_loss_pct"
      type        = "FLOAT64"
      mode        = "REQUIRED"
      description = "Packet loss percentage (0-100)"
    },
    {
      name        = "connected_users"
      type        = "INT64"
      mode        = "REQUIRED"
      description = "Number of connected users on this cell"
    },
  ]

  # Additional derived fields for strategy B (daily + 15-min cluster)
  quarter_hour_field = [
    {
      name        = "quarter_hour_bucket"
      type        = "INT64"
      mode        = "REQUIRED"
      description = "15-minute bucket within the hour (0, 15, 30, 45)"
    },
  ]

  # Additional derived fields for strategy C (integer-range partition)
  interval_15min_field = [
    {
      name        = "interval_15min"
      type        = "INT64"
      mode        = "REQUIRED"
      description = "15-minute interval ID: UNIX_SECONDS(timestamp) / 900"
    },
  ]
}

# =============================================================================
# Strategy A: Hourly Partition + Clustering
#
# The simplest and most commonly recommended approach.
# Partitions by hour, clusters within each hour by timestamp and cell_id.
# Queries for 15-min windows benefit from cluster pruning within the hour.
# =============================================================================
resource "google_bigquery_table" "metrics_hourly_part" {
  dataset_id          = google_bigquery_dataset.cell_network_poc.dataset_id
  table_id            = "metrics_hourly_part"
  deletion_protection = false
  description         = "Strategy A: Hourly time-unit partitioning with clustering on timestamp + cell_id"

  schema = jsonencode(local.base_schema)

  time_partitioning {
    type  = "HOUR"
    field = "timestamp"
  }

  # Cluster on timestamp first so 15-min window queries benefit from
  # block-level pruning within the hourly partition.
  clustering = ["timestamp", "cell_id", "region_id"]

  labels = {
    strategy = "a-hourly-partition"
  }
}

# =============================================================================
# Strategy B: Daily Partition + 15-min Bucket Clustering
#
# Partitions by day for longer retention (fewer partitions consumed).
# Adds a derived quarter_hour_bucket column (0, 15, 30, 45) and clusters on it.
# Good for historical analysis where data retention > 1 year is needed.
# =============================================================================
resource "google_bigquery_table" "metrics_daily_part_15min_cluster" {
  dataset_id          = google_bigquery_dataset.cell_network_poc.dataset_id
  table_id            = "metrics_daily_part_15min_cluster"
  deletion_protection = false
  description         = "Strategy B: Daily time-unit partitioning with clustering on quarter_hour_bucket + cell_id"

  schema = jsonencode(concat(local.base_schema, local.quarter_hour_field))

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["quarter_hour_bucket", "cell_id", "region_id"]

  labels = {
    strategy = "b-daily-part-15min-cluster"
  }
}

# =============================================================================
# Strategy C: Integer-Range Partition on 15-min Intervals
#
# Creates actual 15-minute partitions using integer range partitioning.
# The interval_15min column = UNIX_SECONDS(timestamp) / 900.
#
# KEY FINDING: A full year at 15-min granularity = 35,040 partitions, which
# exceeds BQ's 10,000 partition limit. This strategy can only hold ~104 days
# of data (10,000 × 15 min). We load only the middle 104 days of the year
# (Mar 15 – Jun 27) to stay within limits. This is a real-world constraint
# that the customer needs to understand.
# =============================================================================
resource "google_bigquery_table" "metrics_15min_int_range" {
  dataset_id          = google_bigquery_dataset.cell_network_poc.dataset_id
  table_id            = "metrics_15min_int_range"
  deletion_protection = false
  description = join(" ", [
    "Strategy C: Integer-range partitioning on 15-minute intervals.",
    "LIMITED TO ~104 DAYS due to BQ 10,000 partition cap.",
    "Contains data from 2025-03-15 to 2025-06-27 only.",
  ])

  schema = jsonencode(concat(local.base_schema, local.interval_15min_field))

  range_partitioning {
    field = "interval_15min"
    range {
      # 2025-03-15 00:00:00Z = Unix 1742169600 / 900 = 1935744
      # 1935744 + 9999 = 1945743 → ~2025-06-27
      # This demonstrates the 10,000 partition limit: only ~104 days fit.
      start    = 1935744
      end      = 1945744 # 10,000 partitions exactly
      interval = 1       # Each integer = one 15-min window
    }
  }

  clustering = ["cell_id", "region_id"]

  labels = {
    strategy = "c-int-range-15min"
  }
}

# =============================================================================
# Strategy D: Sharded Tables (legacy pattern)
#
# NOT created in Terraform — the Go loader dynamically creates per-15-min
# tables named: metrics_sharded_15min_YYYYMMDD_HHMM
# This strategy is included for comparison but is generally NOT recommended.
# =============================================================================
