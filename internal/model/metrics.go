// Package model defines the data structures for cell network performance metrics.
package model

import "time"

// CellMetric represents a single measurement from a cell tower.
type CellMetric struct {
	Timestamp        time.Time `json:"timestamp" bigquery:"timestamp"`
	CellID           string    `json:"cell_id" bigquery:"cell_id"`
	SiteID           string    `json:"site_id" bigquery:"site_id"`
	RegionID         string    `json:"region_id" bigquery:"region_id"`
	SignalStrengthDBM float64  `json:"signal_strength_dbm" bigquery:"signal_strength_dbm"`
	LatencyMs        float64   `json:"latency_ms" bigquery:"latency_ms"`
	JitterMs         float64   `json:"jitter_ms" bigquery:"jitter_ms"`
	ThroughputMbps   float64   `json:"throughput_mbps" bigquery:"throughput_mbps"`
	PacketLossPct    float64   `json:"packet_loss_pct" bigquery:"packet_loss_pct"`
	ConnectedUsers   int64     `json:"connected_users" bigquery:"connected_users"`
}

// CellMetricWithDerived extends CellMetric with derived columns needed
// for partitioning strategies B and C.
type CellMetricWithDerived struct {
	CellMetric

	// QuarterHourBucket is the 15-minute bucket within the hour (0, 15, 30, 45).
	// Used by Strategy B (daily partition + 15-min cluster).
	QuarterHourBucket int64 `json:"quarter_hour_bucket" bigquery:"quarter_hour_bucket"`

	// Interval15Min is UNIX_SECONDS(timestamp) / 900.
	// Used by Strategy C (integer-range partition).
	Interval15Min int64 `json:"interval_15min" bigquery:"interval_15min"`
}

// DeriveFields computes the derived columns from the base metric's timestamp.
func (m *CellMetric) DeriveFields() CellMetricWithDerived {
	minute := m.Timestamp.Minute()
	quarterHour := int64((minute / 15) * 15)
	interval15 := m.Timestamp.Unix() / 900

	return CellMetricWithDerived{
		CellMetric:        *m,
		QuarterHourBucket: quarterHour,
		Interval15Min:     interval15,
	}
}

// CellSite defines a cell tower for data generation.
type CellSite struct {
	CellID   string
	SiteID   string
	RegionID string
}
