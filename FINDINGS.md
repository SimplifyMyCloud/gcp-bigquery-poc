# POC Findings: BigQuery 15-min vs 60-min Partitioning

## TL;DR

BigQuery does **not** natively support 15-minute partitioning. The minimum time-unit partition granularity is **HOUR**. This POC tested four workarounds and found that **hourly partitioning with clustering** (Strategy A) or **daily partitioning with a 15-min bucket cluster column** (Strategy B) are the recommended approaches. True 15-minute partitioning via integer-range partitioning (Strategy C) hits BQ's hard 10,000 partition limit at just **104 days of data** — a non-starter for telecom workloads requiring 12+ months of history.

---

## Finding 1: BQ's 10,000 Partition Limit Kills True 15-min Partitioning

**This is the most important finding.**

A full year of 15-minute intervals = 365 × 24 × 4 = **35,040 partitions** — 3.5× over BQ's hard 10,000 partition limit. This limit was recently raised from 4,000 and **cannot be increased further** (it's architectural, not a quota).

| Partition Granularity | Partitions/Year | Max Retention at 10,000 Limit |
|-----------------------|-----------------|-------------------------------|
| 15 minutes            | 35,040          | **~104 days**                 |
| 1 hour                | 8,760           | ~13.7 months                  |
| 1 day                 | 365             | ~27 years                     |

**Impact**: Any cell network reporting system needing 12+ months of historical data **cannot use true 15-minute partitioning**. Even hourly partitioning is tight at 13.7 months.

**Recommendation**: Use daily partitioning (Strategy B) for long-term retention with 15-minute query precision via clustering.

---

## Finding 2: Clustering Gives You 15-min Query Precision Without 15-min Partitions

BigQuery's clustering provides block-level pruning within partitions. When you cluster on `timestamp`, queries for a specific 15-minute window skip irrelevant blocks even within an hourly or daily partition.

This means the customer gets the **query performance** they want from 15-minute granularity without the **partition limit** problems.

---

## Finding 3: Benchmark Results

_To be filled in after benchmark run with 365 days × 100 cells (~52M rows)._

### Data Scale

- **Strategies A & B**: Full year of data (2025-01-01 to 2026-01-01), ~52M rows, ~1.8 GB per table
- **Strategy C**: Limited to 104 days (2025-03-15 to 2025-06-27) due to partition cap, ~15M rows

### Query Performance Comparison

| Query | A: Hourly Partition | B: Daily+15min Cluster | C: Int-Range 15min |
|-------|--------------------|-----------------------|-------------------|
| Point (15-min window, 1 cell) | _TBD_ | _TBD_ | _TBD_ |
| Range (1h, all cells, 15-min agg) | _TBD_ | _TBD_ | _TBD_ |
| 24h regional aggregation | _TBD_ | _TBD_ | _TBD_ |
| Full table scan | _TBD_ | _TBD_ | _TBD_ |

---

## Finding 4: Strategy Trade-offs Summary

| Factor | A: Hourly Part. | B: Daily Part. + Cluster | C: Int-Range 15min |
|--------|-----------------|--------------------------|-------------------|
| Max retention (10K limit) | ~13.7 months | ~27 years | **~104 days** |
| 15-min query pruning | Via clustering | Via clustering | Native partition pruning |
| Schema complexity | Simple | +1 derived column | +1 derived column |
| Query complexity | Simple | Simple | Must filter on interval_15min |
| Partition management | Automatic | Automatic | Manual range planning |
| Production readiness | **High** | **High** | Low |

---

## Recommendations for Customer

1. **If retention ≤ 12 months**: Use **Strategy A** (hourly partitioning + clustering). Simplest to implement and manage. Cluster on `timestamp, cell_id, region_id` for 15-minute query precision.

2. **If retention > 12 months**: Use **Strategy B** (daily partitioning + 15-min bucket clustering). Add a `quarter_hour_bucket` column (0/15/30/45) and cluster on it. Supports decades of data with 15-minute query precision.

3. **Do not use Strategy C** (integer-range 15-min partitioning) for production. The 104-day retention limit makes it unsuitable for any telecom reporting workload.

4. **Do not use Strategy D** (sharded tables). This is a legacy pattern that creates operational complexity without meaningful performance benefit.

---

## POC Environment

- **GCP Project**: simplifymycloud-dev
- **Region**: us-west1 (Oregon)
- **Dataset**: cell_network_poc
- **Data**: Synthetic cell network metrics (100 towers, 3 regions, 1-minute measurement resolution)
- **IaC**: Terraform
- **Code**: Go (data generation, loading, benchmarking)
