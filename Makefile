.PHONY: init plan apply generate load benchmark destroy clean fmt help

PROJECT_ID  ?= simplifymycloud-dev
DATASET_ID  ?= cell_network_poc
REGION      ?= us-west1
BUCKET      ?= simplifymycloud-dev-bq-poc-staging
DATA_DIR    := data
DATA_FILE   := $(DATA_DIR)/metrics.ndjson

# ── Terraform ────────────────────────────────────────────────────────────────

init: ## Initialize Terraform
	cd terraform && terraform init

plan: ## Terraform plan
	cd terraform && terraform plan \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="dataset_id=$(DATASET_ID)"

apply: ## Terraform apply (creates BQ dataset + tables + GCS staging bucket)
	cd terraform && terraform apply -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="dataset_id=$(DATASET_ID)"

destroy: ## Terraform destroy (removes all BQ resources + GCS bucket)
	cd terraform && terraform destroy -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="dataset_id=$(DATASET_ID)"

# ── Go Commands ──────────────────────────────────────────────────────────────

generate: ## Generate 365 days × 100 cells (~52M rows, ~1.8 GB per BQ table, ~13 GB NDJSON)
	@mkdir -p $(DATA_DIR)
	go run ./cmd/datagen -output $(DATA_FILE) -days 365 -cells 100

generate-medium: ## Generate 30 days × 200 cells (~8.6M rows) for mid-size testing
	@mkdir -p $(DATA_DIR)
	go run ./cmd/datagen -output $(DATA_FILE) -days 30 -cells 200

generate-small: ## Generate small dataset for quick testing (3 days × 50 cells)
	@mkdir -p $(DATA_DIR)
	go run ./cmd/datagen -output $(DATA_FILE) -days 3 -cells 50

load-bq: ## Generate + load data directly in BQ via SQL (fastest — no upload needed!)
	@echo "=== Generating 52M rows directly in BigQuery ==="
	@echo "--- Strategy A: Truncate ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/01a_truncate_a.sql
	@echo "--- Strategy A: Jan-Apr (~17.3M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/01b_load_a_jan_apr.sql
	@echo "--- Strategy A: May-Aug (~17.7M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/01c_load_a_may_aug.sql
	@echo "--- Strategy A: Sep-Dec (~17.6M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/01d_load_a_sep_dec.sql
	@echo "--- Strategy B: Daily+15min Cluster (copy from A) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/02_load_strategy_b.sql
	@echo "--- Strategy C: Truncate ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/03a_truncate_c.sql
	@echo "--- Strategy C: Mar-Apr (~5M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/03b_load_c_mar_apr.sql
	@echo "--- Strategy C: Apr-May (~5M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/03c_load_c_apr_may.sql
	@echo "--- Strategy C: May-Jun (~5M rows) ---"
	bq query --project_id=$(PROJECT_ID) --use_legacy_sql=false --max_rows=0 < sql/03d_load_c_may_jun.sql
	@echo "=== All strategies loaded! ==="

load: ## Load via GCS staging bucket (recommended — fastest for large datasets)
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode gcs \
		-bucket $(BUCKET) \
		-skip-sharded

load-direct: ## Load via BQ load job direct upload (slower — bottlenecked by upload bandwidth)
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode load \
		-skip-sharded

load-all: ## Load all strategies including sharded tables (Strategy D) via GCS
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode gcs \
		-bucket $(BUCKET)

load-stream: ## Load via streaming insert (data enters buffer — bytes scanned may show 0)
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode stream \
		-skip-sharded

benchmark: ## Run benchmark queries against all strategies (3 runs each)
	go run ./cmd/benchmark \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-runs 3

# ── Utilities ────────────────────────────────────────────────────────────────

fmt: ## Format Go and Terraform code
	go fmt ./...
	cd terraform && terraform fmt

clean: ## Remove generated data files
	rm -rf $(DATA_DIR)

build: ## Build all Go binaries
	go build ./cmd/datagen
	go build ./cmd/loader
	go build ./cmd/benchmark

test: ## Run Go tests
	go test ./...

# ── Full Workflow ────────────────────────────────────────────────────────────

all: init apply generate load benchmark ## Run the full POC workflow (recommended)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
