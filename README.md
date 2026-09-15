# AI-Ready Data Pipeline

An end-to-end data platform that turns raw healthcare encounter data into
**AI-ready data**: fresh, semantically documented, versioned, and governed
so an LLM agent or analytics tool can safely consume it and hand real
decisions back to the business. The pipeline itself is domain-agnostic —
healthcare encounters (with cardiology as the running example) are used to
prove it out end to end.

## Pitch

Healthcare organizations want to ship AI products (clinical decision
support, operational copilots, patient-risk chatbots) fast, but the data
feeding those products often lacks reliable freshness, clear semantic
meaning, and proper governance — leading to wrong decisions, duplicated
work, and regulatory risk. This pipeline automates the three layers that
are usually missing: **semantic metadata**, **versioned embeddings**, and
**freshness SLAs**, with **PHI-aware governance** built in from ingestion.

## Business problem it solves

1. **Decisions based on stale data** — an AI agent answers a question
   about a patient's clinical history without knowing whether the
   underlying encounter data is current, and clinical/ops teams trust an
   answer that looked fresh but wasn't.
2. **Data with no explicit business meaning** — an agent generates wrong
   SQL because it doesn't understand what `ejection_fraction` or
   `procedure_code` really represents; data scientists lose hours asking
   clinicians what a column means.
3. **Rework and slow AI delivery** — every new AI use case (risk scoring,
   readmission prediction, clinical summarization) reinvents
   chunking/embedding/validation from scratch, turning data readiness
   into the bottleneck.
4. **Sensitive data exposure without governance** — protected health
   information (PHI) from clinical encounters can leak into an LLM
   prompt with no control, and there is no audit trail answering "what
   patient data was exposed to which agent."

## Architecture

```
Healthcare encounter source (EHR export / synthetic dataset / FHIR API)
        │
        ▼
  [Airflow DAG — ingestion]
        │
        ▼
   GCS (raw) ──▶ BigQuery (staging)
        │
        ▼
  [dbt Core] ── models raw → staging → mart + schema/quality tests
        │
        ▼
  [PySpark on Dataproc Serverless] ── chunking clinical notes at volume
        │
        ▼
  [LLM API (Gemini/Claude) + LangChain] ── generates:
        • semantic descriptions of tables/columns (catalog)
        • chunk embeddings for clinical notes
        • anomaly classification (schema drift, outlier vitals/labs)
        │
        ▼
  BigQuery Vector Search ── stores versioned embeddings
        │
        ▼
  Contract layer (Pydantic) ── validates schema exposed for AI consumption
        │
        ▼
  Governance layer ── PHI masking/anonymization before any prompt + audit log
        │
        ▼
  Streamlit ── "AI-readiness score" dashboard + RAG chat over the data
```

## Tech stack

| Layer | Technology | Role |
|---|---|---|
| Orchestration | Apache Airflow 3, `KubernetesExecutor` (kind locally / GKE in prod, installed via Helm) | Orchestrates ingestion → transformation → validation → embedding → catalog — never does the heavy work itself |
| Task execution | `KubernetesExecutor` pods (kind locally / GKE Autopilot in prod); `KubernetesPodOperator` for tasks needing a custom image | Each task runs as an isolated pod with its own resources |
| Data modeling | dbt Core | Models raw → staging → mart layers in BigQuery; schema/quality tests |
| Language | Python 3.11+ (TaskFlow API) | Custom Airflow operators, API calls, agent logic, Pydantic validation |
| Distributed processing | PySpark on Dataproc Serverless | Chunking clinical notes at volume |
| LLM / AI | Gemini API or Claude API | Semantic descriptions, anomaly classification, embedding generation |
| Vector database | BigQuery Vector Search | Stores versioned embeddings, native to GCP |
| LLM orchestration | LangChain | Prompt templates, output parsing, chunking/embedding logic |
| Warehouse | BigQuery | Processed data warehouse |
| Storage | Google Cloud Storage | Raw/staging storage layer |
| Data contracts | Pydantic | Validates schema exposed for AI consumption |
| Data quality | dbt tests | Nulls, duplicates, freshness |
| Catalog | Custom BigQuery table (MVP) | Semantic metadata catalog |
| Front end | Streamlit | AI-readiness scorecard + RAG chat over healthcare encounter data |
| IaC | Terraform | Provisions GCS, BigQuery, service auth |
| Containerization | Docker Compose | Local execution of Airflow |

> Why Streamlit over a BI tool: at a company running on GCP, the realistic
> choice for the scorecard alone would be **Looker Studio** (free, native
> to BigQuery) or **Looker** (paid, enterprise). Neither has a chat
> interface for RAG over your data — Streamlit lets this project show both
> the dashboard *and* a working chat/agent experience in one Python app.

## BigQuery datasets

**`raw_data`** — `raw_encounters`, `raw_diagnoses`, `raw_procedures`,
`raw_clinical_notes`: exactly as received from the source. Not AI-ready —
landing zone only.

**`analytics`** — `stg_*` / `fct_encounters` / `dim_patient` /
`dim_provider`: clean, typed data passing dbt tests. Partially AI-ready —
quality is fine, but no semantic metadata yet.

**`ai_metadata`**:
- `ai_catalog` — `table_name`, `column_name`, `semantic_description`
  (LLM-generated), `business_type`, `sensitivity` (PHI/not),
  `generated_at`. Gives an agent business-language meaning before it
  generates SQL.
- `ai_embeddings` — `chunk_id`, `chunk_text`, `embedding` (VECTOR),
  `source`, `timestamp`, `embedding_model_version`, `confidence`.
  Queried via BigQuery Vector Search by the RAG/agent over clinical notes.
- `ai_freshness_sla` — `table_name`, `last_updated`, `expected_sla`,
  `status` (fresh/stale), `snapshot_id`. The agent checks this before
  trusting an answer.
- `ai_readiness_scorecard` — `table_name`, `ai_readiness_score` (0-100),
  `has_metadata`, `has_contract`, `is_fresh`, `phi_handled`. Consolidated
  summary feeding the Streamlit scorecard.

**Consumption flow for an agent/RAG:**
1. Query `ai_catalog` to understand the schema in clinical/business language.
2. Query `ai_freshness_sla` to confirm the data isn't stale.
3. Query `ai_embeddings` via BigQuery Vector Search for semantic search
   over clinical notes.
4. Assemble the final answer, after governance masking is applied.

## AI-readiness layers implemented

1. **Structure for embeddings and vector search** — consistent, versioned
   chunking of clinical notes; per-chunk metadata (source, timestamp,
   author, confidence); re-embedding pipeline when the embedding model
   version changes.
2. **Semantic layer and metadata** — catalog with LLM-generated semantic
   descriptions, data contracts validated by Pydantic, clear data lineage.
3. **Freshness and versioning** — explicit freshness SLA per table,
   stale-data flagging, dataset snapshots for reproducibility.
4. **Governance and privacy for AI** — automatic PHI masking/anonymization
   before any prompt, row-level security respected even when an agent
   queries the data, audit log of what data was exposed to which
   agent/prompt.

## Getting started (fork & run)

### Quick start (one command)

Once you've forked/cloned the repo and completed the prerequisites below,
a single script provisions the GCP data-lake bucket via Terraform, builds
and starts Airflow, and installs dbt dependencies:

```bash
./setup.sh
```

It's idempotent — safe to re-run. It stops early with a clear message if
`terraform/terraform.tfvars` or `terraform/keys/*.json` are missing (see
step 3 below). Use the manual steps if you want to understand or run each
layer independently.

### 1. Fork and clone

1. Click **Fork** on the GitHub repository page to create your own copy
   under your account.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/<your-github-user>/ai_dataengineering.git
   cd ai_dataengineering
   ```
3. (Optional) Add the original repo as `upstream` to pull future updates:
   ```bash
   git remote add upstream https://github.com/<original-owner>/ai_dataengineering.git
   git fetch upstream
   ```

### 2. Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/), **running**,
  before you `terraform apply` in `terraform/local-airflow` — that config
  creates a local Kubernetes cluster with [kind](https://kind.sigs.k8s.io/)
  and talks to the Docker daemon to do it. You do **not** need to install the
  `kind` CLI yourself: the Terraform provider (`tehcyx/kind`) manages the
  cluster directly through Docker. `terraform init` doesn't need Docker
  running, only `terraform apply`/`destroy` do.
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- A GCP project with billing enabled and the Storage API allowed
- A GCP service account with the `roles/storage.admin` role (or narrower,
  scoped to the target bucket), with a downloaded JSON key
- Python 3.11+ and [dbt Core](https://docs.getdbt.com/docs/core/installation)
  (once the dbt project is added)

### 3. Configure GCP credentials (Terraform)

1. Place your own service account JSON key at `terraform/keys/` — this
   folder is gitignored, never commit it.
2. Copy the example variables file and adjust it to your project:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Set `project_id`, `credentials_file` (path to your key) and
   `bucket_name` (must be globally unique in GCS) to your own values.
   `terraform.tfvars` is gitignored, so your values stay local.
3. Initialize and apply:
   ```bash
   terraform init
   terraform plan    # review what will be created
   terraform apply   # creates the data-lake bucket
   ```

### 4. Run Airflow 3 locally (on a kind cluster)

Airflow runs fully inside a local Kubernetes cluster ([kind](https://kind.sigs.k8s.io/)),
provisioned and installed by Terraform (`kind` provider + the official
`apache-airflow/airflow` Helm chart) with `KubernetesExecutor` — every task
runs as its own isolated pod, the same model used in production on GKE:

```bash
cd terraform/local-airflow
terraform init
terraform apply   # creates the kind cluster and installs Airflow via Helm
```
Open the UI at `http://localhost:8080`. Credentials default to
`admin` / `admin` (see `variables.tf` — override `admin_username` /
`admin_password` in a `terraform.tfvars` if you want something else):
```bash
terraform output admin_username
terraform output -raw admin_password
```
DAGs live in `terraform/local-airflow/dags/` and are mounted straight into
the cluster's nodes (`extra_mounts` in the `kind_cluster` resource) — edit a
file there and it shows up in the UI without redeploying.

When you're done, tear the cluster down to free memory:
```bash
terraform destroy
```

> **Note on resources**: the full stack (Airflow + Postgres inside kind)
> needs ~2GB RAM. If Docker Desktop's VM has little headroom (check `docker
> info --format '{{.MemTotal}}'`), avoid running other memory-hungry
> workloads at the same time — a starved VM can make health checks flap or
> the Docker daemon itself become unresponsive.

### 5. dbt (once added)

```bash
cd dbt
dbt deps
dbt build   # runs models + tests against BigQuery
```

### 6. Streamlit app (scorecard + chat)

```bash
cd streamlit_app
python -m venv .venv && source .venv/Scripts/activate   # Windows Git Bash; use bin/activate on macOS/Linux
pip install -r requirements.txt
cp .env.example .env   # fill in GCP_PROJECT_ID, GOOGLE_APPLICATION_CREDENTIALS, GOOGLE_API_KEY
streamlit run app.py
```
Open `http://localhost:8501`. Both pages check for required config/tables
first and show a clear message instead of a stack trace if the pipeline
hasn't populated `ai_metadata` yet.

## Repository structure

```
ai_dataengineering/
├── setup.sh                  # one-command bootstrap: terraform (GCP) -> terraform (Airflow) -> dbt
├── dbt/                      # dbt Core project: staging → mart models + tests
├── terraform/                 # IaC
│   ├── keys/                 #  GCP service account key (gitignored)
│   ├── modules/
│   │   ├── auth/             #  validates credentials, feeds the google provider
│   │   └── gcs_bucket/       #  provisions the data-lake GCS bucket
│   └── local-airflow/        #  Airflow 3 running on a local kind cluster
│       ├── main.tf           #    kind_cluster + helm_release (apache-airflow/airflow chart)
│       └── dags/              #    fhir_ingestion.py — simulated FHIR Encounter ingestion
├── spark_jobs/                # PySpark chunking jobs (Dataproc Serverless)
├── contracts/                  # Pydantic schemas exposed for AI consumption
├── governance/                 # PHI masking/anonymization rules
├── streamlit_app/              # AI-readiness scorecard + RAG chat front end
│   ├── app.py                 #  home page
│   ├── pages/                  #  1_AI_Readiness_Scorecard.py, 2_Chat_with_your_data.py
│   └── lib/                    #  BigQuery client + RAG helpers
└── README.md
```

## Current status

- [x] Terraform: `auth` module (GCP service-account authentication) and
      `gcs_bucket` module (provisions the `data-lake` bucket)
- [x] Airflow 3 running on a local `kind` cluster (Terraform + Helm chart),
      `KubernetesExecutor` — every task runs as its own isolated pod,
      mirroring how it'd run on GKE in production
- [x] `fhir_ingestion` DAG: simulates a FHIR API `Encounter` call (inpatient
      + emergency encounters, ICD-10-CM codes across specialties) so
      downstream steps can filter cardiology encounters
- [x] One-command bootstrap (`setup.sh`): Terraform apply (GCP) → Terraform
      apply (Airflow on kind) → dbt deps
- [x] Streamlit app: AI-readiness scorecard page + RAG chat page (both fail
      gracefully with setup instructions until the pipeline populates
      `ai_metadata`)
- [ ] dbt models (raw → staging → mart) for healthcare encounters
- [ ] `fhir_ingestion` writing to GCS/BigQuery (currently returns synthetic
      data via XCom only)
- [ ] LLM-generated semantic catalog (`ai_catalog`)
- [ ] Chunking + embeddings pipeline (`ai_embeddings`)
- [ ] Pydantic data contracts
- [ ] Freshness SLA checks (`ai_freshness_sla`)
- [ ] PHI masking/governance layer

## Build order (MVP → full)

1. Simple ingestion (Airflow + GCS + BigQuery) with one healthcare
   encounters source.
2. dbt: raw → staging → mart modeling + basic tests.
3. Python task calling an LLM to generate semantic descriptions for each
   table/column → written to `ai_catalog`.
4. Chunking task (plain Python first; Spark only if volume justifies it)
   + embeddings via LangChain → BigQuery Vector Search.
5. Pydantic contract validating schema before exposing the data.
6. Freshness/staleness task flagging each table.
7. Basic PHI masking layer before any prompt.
8. Streamlit dashboard with AI-readiness score + RAG chat.

> Note: cataloging data with semantic metadata already exists as a
> product category (Atlan, OpenMetadata, DataHub, Monte Carlo). The goal
> of this project is to demonstrate deep understanding of the AI-readiness
> problem end to end, not to compete with those tools.
