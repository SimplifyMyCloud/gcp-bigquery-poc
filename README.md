# BigQuery 15-min vs 60-min Partitioning POC

## Background

A telecom customer requested 15-minute partition intervals on BigQuery for their cell network performance reporting, instead of the default 60-minute (hourly) intervals. The belief was that finer partition granularity would improve query performance and reduce costs for sub-hourly reporting windows.

This POC was built to test that assumption, identify the actual constraints, and guide the customer toward best practices.

## Key Discovery

**BigQuery does not support sub-hourly time-unit partitioning.** The minimum native granularity is HOUR. Attempting to achieve true 15-minute partitioning via integer-range partitioning hits BQ's hard 10,000 partition limit at just **104 days of data** — a non-starter for telecom workloads requiring 12+ months of history.

However, **BQ's clustering feature provides 15-minute query precision without 15-minute partitions**, making the customer's original requirement achievable through a different mechanism.

## What We Tested

We built and benchmarked three partitioning strategies (plus one legacy approach) against 52.5 million rows of synthetic cell network data spanning a full year, 100 cell towers across 3 regions.

| ID | Strategy | Approach |
|----|----------|----------|
| A | Hourly Partition + Clustering | Hourly time-unit partitions, cluster on `timestamp, cell_id, region_id` |
| B | Daily Partition + 15-min Bucket | Daily partitions with derived `quarter_hour_bucket` column for clustering |
| C | Integer-Range 15-min Partition | True 15-min partitions via `interval_15min = UNIX_SECONDS(ts)/900` |
| D | Sharded Tables | One table per 15-min window (legacy anti-pattern, not benchmarked at scale) |

## Results

Bytes scanned per query (lower = cheaper):

| Query | A: Hourly+Cluster | B: Daily+Cluster | C: Int-Range 15min |
|-------|-------------------|-------------------|-------------------|
| Point (15-min window, 1 cell) | **0.24 MB** | 5.77 MB | 0.07 MB |
| Range (1h, all cells) | **0.24 MB** | 5.77 MB | 0.29 MB |
| 24h regional aggregation | 5.77 MB | 5.77 MB | 6.87 MB |
| Full scan (year/104d) | 2,104.75 MB | 2,104.75 MB | 713.97 MB* |

*Strategy C holds only 104 days due to partition limit. Per-day cost is comparable.

## Recommendations

1. **Use Strategy A (Hourly Partition + Clustering)** for retention up to 12 months. Scans 0.24 MB for a 15-minute point query — excellent pruning with zero partition limit concerns. Simplest schema and queries.

2. **Use Strategy B (Daily Partition + Clustering)** if retention exceeds 12 months. Supports decades of data. Scans a full day per query (5.77 MB) — acceptable for most reporting workloads.

3. **Do not use true 15-minute partitioning (Strategy C)** in production. The 0.07 MB advantage over Strategy A saves less than $0.001 per query. The 104-day retention ceiling makes it unsuitable for telecom.

4. **Do not use sharded tables (Strategy D)**. Legacy anti-pattern that creates thousands of tables and breaks BQ's optimizer.

## Best Practices for BigQuery Partitioning

Based on what this POC uncovered:

- **Partition for retention management, cluster for query pruning.** Partitions define the coarsest data boundaries; clustering provides fine-grained block-level pruning within those boundaries. They serve different purposes.
- **Always cluster on your most common filter columns.** Put the highest-cardinality filter first (often `timestamp`), followed by the next most selective columns (`cell_id`, `region_id`).
- **Keep partitions below the 10,000 limit with headroom.** Hourly partitions give ~13.7 months; daily gives ~27 years. Plan for your retention requirement plus growth.
- **Disable query cache when benchmarking.** BQ caches results by default — repeated queries report 0 bytes scanned unless you set `DisableQueryCache = true`.
- **Use DML partition limits wisely.** A single INSERT/UPDATE/DELETE can only touch 4,000 partitions. For bulk loads into hourly-partitioned tables, chunk your data by time range.
- **Generate test data server-side when possible.** For large datasets, use `GENERATE_TIMESTAMP_ARRAY` with `CROSS JOIN` to create data directly in BQ — avoids upload bottlenecks entirely.

Full benchmark data and analysis: [FINDINGS.md](FINDINGS.md)

## Prerequisites

- GCP project `simplifymycloud-dev` with BigQuery and Cloud Storage APIs enabled
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- Go 1.22+
- Terraform 1.5+

## Quick Start

```bash
make init          # terraform init
make apply         # create BQ dataset, tables, and GCS staging bucket

# Option 1: Generate data directly in BQ (recommended — no upload needed)
make load-bq       # generates 52M rows server-side via SQL

# Option 2: Generate locally and upload via GCS
make generate      # generate ~52M rows as 14 GB NDJSON file
make load          # upload to GCS staging bucket → BQ load job

# Run the benchmark
make benchmark     # run queries 3× each, print comparison table
```

## Benchmark Queries

1. **Point query** — Single cell in a 15-min window
2. **Range aggregation** — All cells in 1h window, grouped by 15-min buckets
3. **24h regional aggregation** — Avg metrics per region per 15-min bucket over 24h
4. **Wide scan** — Full year scan grouped by hour with percentile latencies

Reports wall time, bytes scanned, bytes billed, and slot milliseconds.

## Data Schema

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | TIMESTAMP | 1-minute resolution measurement time |
| `cell_id` | STRING | Cell tower ID (CELL_001–CELL_100) |
| `site_id` | STRING | Site ID (SITE_01–SITE_20) |
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
make destroy    # tear down all BQ resources and GCS bucket
make clean      # remove local data files
```

## Project Structure

```
├── terraform/          # IaC: BQ dataset, tables, GCS staging bucket
├── cmd/
│   ├── datagen/        # Synthetic data generator (local NDJSON)
│   ├── loader/         # BQ data loader (GCS, direct, streaming modes)
│   └── benchmark/      # Query benchmark runner
├── sql/                # SQL-based data generation (server-side in BQ)
├── internal/
│   ├── model/          # Go data model
│   └── queries/        # Parameterized benchmark queries
├── data/               # Generated NDJSON (gitignored)
├── FINDINGS.md         # Full benchmark results and analysis
├── Makefile
└── README.md
```

## POC Environment

- **GCP Project**: simplifymycloud-dev
- **Region**: us-west1 (Oregon)
- **Dataset**: cell_network_poc
- **IaC**: Terraform
- **Code**: Go + SQL
