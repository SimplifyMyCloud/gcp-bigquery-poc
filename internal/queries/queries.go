// Package queries defines the benchmark queries for comparing partitioning strategies.
package queries

import "fmt"

// BenchmarkQuery represents a named query to run against a table strategy.
type BenchmarkQuery struct {
	Name        string
	Description string
	// SQLTemplate takes the fully-qualified table reference and returns SQL.
	SQLTemplate func(tableRef string) string
}

// PointQuery returns metrics for a single cell in a specific 15-min window.
func PointQuery(startTime, endTime, cellID string) BenchmarkQuery {
	return BenchmarkQuery{
		Name:        "point_query",
		Description: fmt.Sprintf("Single cell (%s) in 15-min window", cellID),
		SQLTemplate: func(tableRef string) string {
			return fmt.Sprintf(`SELECT
  timestamp,
  cell_id,
  signal_strength_dbm,
  latency_ms,
  throughput_mbps,
  packet_loss_pct,
  connected_users
FROM %s
WHERE timestamp >= TIMESTAMP('%s')
  AND timestamp < TIMESTAMP('%s')
  AND cell_id = '%s'
ORDER BY timestamp`, tableRef, startTime, endTime, cellID)
		},
	}
}

// RangeQuery15MinBuckets returns all cells in a 1-hour window, aggregated to 15-min buckets.
func RangeQuery15MinBuckets(startTime, endTime string) BenchmarkQuery {
	return BenchmarkQuery{
		Name:        "range_query_15min",
		Description: "All cells in 1-hour window, 15-min aggregations",
		SQLTemplate: func(tableRef string) string {
			return fmt.Sprintf(`SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE) AS period_start,
  cell_id,
  AVG(signal_strength_dbm) AS avg_signal,
  AVG(latency_ms) AS avg_latency,
  AVG(throughput_mbps) AS avg_throughput,
  SUM(connected_users) AS total_users
FROM %s
WHERE timestamp >= TIMESTAMP('%s')
  AND timestamp < TIMESTAMP('%s')
GROUP BY
  TIMESTAMP_TRUNC(timestamp, MINUTE),
  cell_id
ORDER BY period_start, cell_id`, tableRef, startTime, endTime)
		},
	}
}

// AggregationQuery computes average signal per region per 15-min bucket over 24 hours.
func AggregationQuery(startTime, endTime string) BenchmarkQuery {
	return BenchmarkQuery{
		Name:        "aggregation_24h",
		Description: "Avg signal per region per 15-min bucket over 24h",
		SQLTemplate: func(tableRef string) string {
			return fmt.Sprintf(`SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE) AS bucket,
  region_id,
  COUNT(*) AS measurement_count,
  AVG(signal_strength_dbm) AS avg_signal,
  AVG(latency_ms) AS avg_latency,
  AVG(throughput_mbps) AS avg_throughput,
  AVG(packet_loss_pct) AS avg_packet_loss
FROM %s
WHERE timestamp >= TIMESTAMP('%s')
  AND timestamp < TIMESTAMP('%s')
GROUP BY bucket, region_id
ORDER BY bucket, region_id`, tableRef, startTime, endTime)
		},
	}
}

// WideScanQuery scans all data over the full date range grouped by hour.
func WideScanQuery(startTime, endTime string) BenchmarkQuery {
	return BenchmarkQuery{
		Name:        "wide_scan",
		Description: "Full 3-day scan grouped by hour",
		SQLTemplate: func(tableRef string) string {
			return fmt.Sprintf(`SELECT
  TIMESTAMP_TRUNC(timestamp, HOUR) AS hour_bucket,
  region_id,
  COUNT(*) AS measurement_count,
  AVG(signal_strength_dbm) AS avg_signal,
  APPROX_QUANTILES(latency_ms, 100)[OFFSET(50)] AS median_latency,
  APPROX_QUANTILES(latency_ms, 100)[OFFSET(95)] AS p95_latency,
  AVG(throughput_mbps) AS avg_throughput,
  SUM(connected_users) AS total_users
FROM %s
WHERE timestamp >= TIMESTAMP('%s')
  AND timestamp < TIMESTAMP('%s')
GROUP BY hour_bucket, region_id
ORDER BY hour_bucket, region_id`, tableRef, startTime, endTime)
		},
	}
}

// StrategyC variants that filter on the integer partition column for fair comparison.

// PointQueryIntRange is the Strategy C variant that also filters on interval_15min.
func PointQueryIntRange(startTime, endTime, cellID string, intervalStart, intervalEnd int64) BenchmarkQuery {
	return BenchmarkQuery{
		Name:        "point_query",
		Description: fmt.Sprintf("Single cell (%s) in 15-min window (int-range)", cellID),
		SQLTemplate: func(tableRef string) string {
			return fmt.Sprintf(`SELECT
  timestamp,
  cell_id,
  signal_strength_dbm,
  latency_ms,
  throughput_mbps,
  packet_loss_pct,
  connected_users
FROM %s
WHERE interval_15min >= %d
  AND interval_15min < %d
  AND timestamp >= TIMESTAMP('%s')
  AND timestamp < TIMESTAMP('%s')
  AND cell_id = '%s'
ORDER BY timestamp`, tableRef, intervalStart, intervalEnd, startTime, endTime, cellID)
		},
	}
}
