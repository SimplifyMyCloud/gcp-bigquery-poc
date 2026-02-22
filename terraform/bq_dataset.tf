resource "google_bigquery_dataset" "cell_network_poc" {
  dataset_id    = var.dataset_id
  friendly_name = "Cell Network POC"
  description   = "POC dataset comparing 15-min vs 60-min partitioning strategies for cell network performance data"
  location      = var.region

  default_table_expiration_ms = var.table_expiration_ms

  labels = {
    environment = "dev"
    purpose     = "poc"
    team        = "simplifymy-cloud"
  }
}
