# BigQuery 15-min vs 60-min Partitioning POC

Proof-of-concept comparing partitioning strategies for cell network performance data in BigQuery. The customer wants 15-minute partition intervals, but **BigQuery's minimum native time-unit partition granularity is HOUR**. This POC builds and benchmarks four alternative strategies.

## Strategies Compared

| ID | Strategy | Table | How It Works |
|----|----------|-------|-------------|
| A | Hourly Partition + Clustering | `metrics_hourly_part` | Native hourly partitions, cluster on `cell_id`, `region_id`. Queries for 15-min windows leverage cluster pruning within the hour partition. |
| B | Daily Partition + 15-min Bucket Cluster | `metrics_daily_part_15min_cluster` | Daily partitions with a derived `quarter_hour_bucket` column (0/15/30/45) used for clustering. Good for long retention. |
| C | Integer-Range 15-min Partition | `metrics_15min_int_range` | True 15-min partitions via integer range on `interval_15min = UNIX_SECONDS(ts)/900`. Most granular pruning but more complex. |
| D | Sharded Tables | `metrics_sharded_15min_*` | One table per 15-min window (legacy pattern). Included for comparison — **not recommended**. |

## Prerequisites

- GCP project `simplifymycloud-dev` with BigQuery API enabled
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- Go 1.22+
- Terraform 1.5+

## Quick Start

```bash
# Full workflow: init → apply → generate data → load → benchmark
make all

# Or step by step:
make init        # terraform init
make plan        # terraform plan (review changes)
make apply       # create BQ dataset + tables in us-west1
make generate    # generate ~216K rows of synthetic cell data (3 days × 50 cells × 1-min resolution)
make load        # load data into all 4 strategies
make benchmark   # run benchmark queries and print comparison
```

## Benchmark Queries

1. **Point query** — Single cell in a 15-min window
2. **Range aggregation** — All cells in 1-hour window, grouped by 15-min buckets
3. **24h regional aggregation** — Avg metrics per region per 15-min bucket over 24 hours
4. **Wide scan** — Full 3-day scan grouped by hour with percentile latencies

The benchmark reports wall time, bytes scanned, bytes billed, and slot milliseconds for each strategy/query combination.

## Data Schema

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | TIMESTAMP | 1-minute resolution measurement time |
| `cell_id` | STRING | Cell tower ID (CELL_001–CELL_050) |
| `site_id` | STRING | Site ID (SITE_01–SITE_10) |
| `region_id` | STRING | Region (us-west, us-central, us-east) |
| `signal_strength_dbm` | FLOAT64 | Signal strength (-120 to -30 dBm) |
| `latency_ms` | FLOAT64 | Round-trip latency |
| `jitter_ms` | FLOAT64 | Jitter |
| `throughput_mbps` | FLOAT64 | Throughput |
| `packet_loss_pct` | FLOAT64 | Packet loss percentage |
| `connected_users` | INT64 | Connected users |

Derived fields (strategy-specific): `quarter_hour_bucket` (B), `interval_15min` (C).

## Cleanup

```bash
make destroy    # tear down all BQ resources
make clean      # remove local data files
```

## Project Structure

```
├── terraform/          # IaC: BQ dataset + table definitions
├── cmd/
│   ├── datagen/        # Synthetic data generator
│   ├── loader/         # BQ data loader (all 4 strategies)
│   └── benchmark/      # Query benchmark runner
├── internal/
│   ├── model/          # Go data model
│   └── queries/        # Parameterized benchmark queries
├── data/               # Generated NDJSON (gitignored)
├── Makefile
└── README.md
```
