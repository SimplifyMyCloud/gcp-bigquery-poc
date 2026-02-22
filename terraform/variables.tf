variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "simplifymycloud-dev"
}

variable "region" {
  description = "GCP region for BigQuery dataset"
  type        = string
  default     = "us-west1"
}

variable "dataset_id" {
  description = "BigQuery dataset ID"
  type        = string
  default     = "cell_network_poc"
}

variable "table_expiration_ms" {
  description = "Default table expiration in milliseconds (30 days)"
  type        = number
  default     = 2592000000 # 30 days
}

variable "staging_bucket_name" {
  description = "GCS bucket for staging NDJSON before BQ load jobs"
  type        = string
  default     = "simplifymycloud-dev-bq-poc-staging"
}
