# =============================================================================
# GCS staging bucket for BQ load jobs
#
# NDJSON files are uploaded here first, then BQ loads from GCS over Google's
# internal network — orders of magnitude faster than streaming through the
# BQ API's resumable upload endpoint for files > 1 GB.
# =============================================================================

resource "google_storage_bucket" "staging" {
  name          = var.staging_bucket_name
  project       = var.project_id
  location      = var.region
  force_destroy = true # POC — allow terraform destroy to clean up

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 7 # Auto-delete staging files after 7 days
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose = "bq-poc-staging"
  }
}
