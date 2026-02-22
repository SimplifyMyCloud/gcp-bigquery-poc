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

### Data Scale

- **Strategies A & B**: Full year of data (2025-01-01 to 2025-12-31), 52,560,000 rows, ~2.1 GB per table
- **Strategy C**: Limited to 104 days (2025-03-15 to 2025-06-27) due to partition cap, ~15,000,000 rows, ~714 MB

### Bytes Scanned (lower = cheaper, better pruning)

| Query | A: Hourly Partition | B: Daily+15min Cluster | C: Int-Range 15min | Winner |
|-------|--------------------|-----------------------|-------------------|--------|
| Point (15-min window, 1 cell) | **0.24 MB** | 5.77 MB | 0.07 MB | C (but A is excellent) |
| Range (1h, all cells, 15-min agg) | **0.24 MB** | 5.77 MB | 0.29 MB | A |
| 24h regional aggregation | 5.77 MB | 5.77 MB | 6.87 MB | A = B (tie) |
| Full table scan (year/104d) | 2,104.75 MB | 2,104.75 MB | 713.97 MB* | N/A* |

*Strategy C scans less on the full scan only because it holds 104 days vs 365 days. Per-day scan cost is comparable.

### Wall Time (ms, averaged over 3 runs)

| Query | A: Hourly | B: Daily+Cluster | C: Int-Range |
|-------|-----------|-------------------|--------------|
| Point query | 923 | 572 | 515 |
| Range 15-min agg | 710 | 606 | 577 |
| Region agg 24h | 697 | 562 | 621 |
| Full table scan | 2,720 | 1,593 | 1,979 |

### Slot Milliseconds (compute cost)

| Query | A: Hourly | B: Daily+Cluster | C: Int-Range |
|-------|-----------|-------------------|--------------|
| Point query | 15 | 36 | 19 |
| Range 15-min agg | 41 | 81 | 137 |
| Region agg 24h | 351 | 57 | 704 |
| Full table scan | 1,601,344 | 68,507 | 1,375,203 |

### Analysis

**Strategy A (Hourly + Clustering) provides the best bytes-scanned efficiency for narrow queries.** For a 15-minute point query, it scans only 0.24 MB — just 4× more than Strategy C's 0.07 MB but with no partition limit constraints. The hourly partition prunes to one hour, then clustering on `timestamp` narrows further to the relevant blocks.

**Strategy B (Daily + Clustering) consistently scans one full day (5.77 MB) regardless of query width.** This is expected: daily partitions can't prune below a day. For sub-day queries this is 24× more than Strategy A. However, Strategy B shows dramatically lower slot-ms on the full scan (68K vs 1.6M), suggesting better parallelization characteristics.

**Strategy C (Int-Range 15min) achieves the tightest pruning** (0.07 MB for a point query) but the 104-day retention limit is a dealbreaker for production. The slight bytes-scanned advantage over Strategy A (0.07 vs 0.24 MB) saves fractions of a cent per query — not worth the operational complexity and retention limits.

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

1. **Primary recommendation — Strategy A (Hourly Partition + Clustering)**: Best overall choice for retention up to 12 months. Scans only 0.24 MB for a 15-minute point query (vs 5.77 MB for daily partitions). Simplest schema and queries. Cluster on `timestamp, cell_id, region_id`.

2. **If retention > 12 months — Strategy B (Daily Partition + 15-min Bucket Clustering)**: Add a `quarter_hour_bucket` column (0/15/30/45) and cluster on it. Supports decades of retention. Scans a full day per query (5.77 MB) — acceptable for most reporting workloads, and shows excellent slot efficiency on wide scans.

3. **Do not use true 15-minute partitioning (Strategy C)**: The 0.07 MB point-query advantage over Strategy A's 0.24 MB saves less than $0.001 per query. The tradeoff — only 104 days of retention, operational complexity, manual range planning — makes this unsuitable for any production telecom workload.

4. **Do not use sharded tables (Strategy D)**: Legacy anti-pattern. Creates thousands of tables, breaks BQ's optimizer, and provides no meaningful advantage over partitioning + clustering.

### Cost Comparison (on-demand pricing at $6.25/TB scanned)

| Query Pattern | Strategy A Cost | Strategy B Cost | Savings |
|--------------|----------------|----------------|---------|
| 15-min point query | $0.0000015 | $0.0000361 | A is 24× cheaper |
| 1h range aggregation | $0.0000015 | $0.0000361 | A is 24× cheaper |
| 24h regional report | $0.0000361 | $0.0000361 | Equal |
| Full year scan | $0.0132 | $0.0132 | Equal |

At any realistic query volume, the cost difference between A and B is negligible. Choose based on retention requirements.

---

## POC Environment

- **GCP Project**: simplifymycloud-dev
- **Region**: us-west1 (Oregon)
- **Dataset**: cell_network_poc
- **Data**: Synthetic cell network metrics (100 towers, 3 regions, 1-minute measurement resolution)
- **IaC**: Terraform
- **Code**: Go (data generation, loading, benchmarking)
