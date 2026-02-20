.PHONY: init plan apply generate load benchmark destroy clean fmt help

PROJECT_ID  ?= simplifymycloud-dev
DATASET_ID  ?= cell_network_poc
REGION      ?= us-west1
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

apply: ## Terraform apply (creates BQ dataset + tables)
	cd terraform && terraform apply -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="dataset_id=$(DATASET_ID)"

destroy: ## Terraform destroy (removes all BQ resources)
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

load: ## Load via BQ load job (recommended — data goes to columnar storage immediately)
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode load \
		-skip-sharded

load-all: ## Load all strategies including sharded tables (Strategy D)
	go run ./cmd/loader \
		-project $(PROJECT_ID) \
		-dataset $(DATASET_ID) \
		-input $(DATA_FILE) \
		-mode load

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
