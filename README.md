# AI-Ready Data Pipeline

An end-to-end data platform that turns raw healthcare encounter data into
**AI-ready data**: fresh, semantically documented, versioned, and governed
so an LLM agent or analytics tool can safely consume it and hand real
decisions back to the business. The pipeline itself is domain-agnostic; it's
just proven out here with healthcare encounters, using cardiology as the
running example.

## Pitch

Healthcare organizations want to ship AI products (clinical decision
support, operational copilots, patient-risk chatbots) fast, but the data
feeding those products often lacks reliable freshness, clear semantic
meaning, and proper governance, which leads to wrong decisions, duplicated
work, and regulatory risk. This pipeline automates the three layers that
are usually missing: **semantic metadata**, **versioned embeddings**, and
**freshness SLAs**, with **PHI-aware governance** built in from ingestion.

## Business problem it solves

1. **Decisions based on stale data.** An AI agent answers a question about
   a patient's clinical history without knowing whether the underlying
   encounter data is current, so clinical and ops teams end up trusting
   an answer that looked fresh but wasn't.
2. **Data with no explicit business meaning.** An agent generates wrong
   SQL because it doesn't understand what `ejection_fraction` or
   `procedure_code` really represents, and data scientists lose hours
   asking clinicians what a column means.
3. **Rework and slow AI delivery.** Every new AI use case (risk scoring,
   readmission prediction, clinical summarization) reinvents
   chunking/embedding/validation from scratch, so data readiness ends up
   being the bottleneck.
4. **Sensitive data exposure without governance.** Protected health
   information (PHI) from clinical encounters can leak into an LLM
   prompt with no control, and there's no audit trail to answer "what
   patient data was exposed to which agent."

## Architecture

```
Healthcare encounter source (EHR export / synthetic dataset / FHIR API)
        │
        ▼
  [Airflow DAG: ingestion]
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
| Orchestration | Apache Airflow 3, `KubernetesExecutor` (kind locally / GKE in prod, installed via Helm) | Orchestrates ingestion → transformation → validation → embedding → catalog; never does the heavy work itself |
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
> interface for RAG over your data, and Streamlit lets this project show both
> the dashboard *and* a working chat/agent experience in one Python app.

## BigQuery datasets

**`raw_data`**: `raw_encounters`, `raw_diagnoses`, `raw_procedures`,
`raw_clinical_notes`, exactly as received from the source. Not AI-ready
yet, it's landing zone only.

**`analytics`**: `stg_*` / `fct_encounters` / `dim_patient` /
`dim_provider`, clean, typed data passing dbt tests. Partially AI-ready:
quality is fine, but there's no semantic metadata yet.

**`ai_metadata`**:
- `ai_catalog`: `table_name`, `column_name`, `semantic_description`
  (LLM-generated), `business_type`, `sensitivity` (PHI/not),
  `generated_at`. Gives an agent business-language meaning before it
  generates SQL.
- `ai_embeddings`: `chunk_id`, `chunk_text`, `embedding` (VECTOR),
  `source`, `timestamp`, `embedding_model_version`, `confidence`.
  Queried via BigQuery Vector Search by the RAG/agent over clinical notes.
- `ai_freshness_sla`: `table_name`, `last_updated`, `expected_sla`,
  `status` (fresh/stale), `snapshot_id`. The agent checks this before
  trusting an answer.
- `ai_readiness_scorecard`: `table_name`, `ai_readiness_score` (0-100),
  `has_metadata`, `has_contract`, `is_fresh`, `phi_handled`. Consolidated
  summary feeding the Streamlit scorecard.

**Consumption flow for an agent/RAG:**
1. Query `ai_catalog` to understand the schema in clinical/business language.
2. Query `ai_freshness_sla` to confirm the data isn't stale.
3. Query `ai_embeddings` via BigQuery Vector Search for semantic search
   over clinical notes.
4. Assemble the final answer, after governance masking is applied.

## AI-readiness layers implemented

1. **Structure for embeddings and vector search.** Consistent, versioned
   chunking of clinical notes, per-chunk metadata (source, timestamp,
   author, confidence), and a re-embedding pipeline for when the
   embedding model version changes.
2. **Semantic layer and metadata.** A catalog with LLM-generated semantic
   descriptions, data contracts validated by Pydantic, and clear data
   lineage.
3. **Freshness and versioning.** An explicit freshness SLA per table,
   stale-data flagging, and dataset snapshots for reproducibility.
4. **Governance and privacy for AI.** Automatic PHI masking and
   anonymization before any prompt, row-level security respected even
   when an agent queries the data, and an audit log of what data was
   exposed to which agent or prompt.

## Getting started (fork & run)

**Prerequisites**: Docker Desktop running, Terraform >= 1.5, the
[gcloud CLI](https://cloud.google.com/sdk/docs/install), Python 3.11+,
a GCP project with an active billing account (Storage + BigQuery APIs on),
and a service account JSON key. The service account needs **no roles
granted upfront** - Terraform bootstraps the bucket and dataset with your
own (already-privileged) gcloud login, then grants the service account
only the narrow, resource-scoped roles it actually uses.

```bash
# 1. Fork on GitHub, then clone your fork
git clone https://github.com/<your-github-user>/ai_dataengineering.git
cd ai_dataengineering

# 2. GCP auth: service account key for Terraform/Airflow, your own login for IAM grants
#    (key goes in terraform/keys/, gitignored)
gcloud auth application-default login

# 3. GCP infra: data-lake bucket + raw_data BigQuery dataset + IAM grants
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set project_id, credentials_file, bucket_name
terraform init && terraform apply

# 4. Airflow on a local kind cluster (KubernetesExecutor, installed via Helm)
cd local-airflow
cp terraform.tfvars.example terraform.tfvars   # set gcs_bucket_name, gcp_project_id, gcp_credentials_file
terraform init && terraform apply
# UI: http://localhost:8080  |  terraform output admin_username / -raw admin_password
# trigger the fhir DAG: lands data in GCS, then loads it into raw_data.raw_encounters
cd ../..

# 5. dbt (staging -> intermediate -> mart, once the fhir DAG has run at least once)
#    Runs on its own daily at 7am via the "dbt" Airflow DAG (KubernetesPodOperator,
#    official dbt-bigquery image). To run it by hand instead:
cd dbt
python -m venv .venv && source .venv/Scripts/activate   # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
export GCP_PROJECT_ID=your-gcp-project-id
export GOOGLE_APPLICATION_CREDENTIALS=../terraform/keys/your-service-account-key.json
dbt build --profiles-dir .
cd ..

# 6. Streamlit app
cd streamlit_app
python -m venv .venv && source .venv/Scripts/activate   # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in GCP_PROJECT_ID, GOOGLE_APPLICATION_CREDENTIALS, GOOGLE_API_KEY
streamlit run app.py   # http://localhost:8501
```

Steps 3-4 can also run as `./setup.sh` once your `terraform.tfvars` files
and service account key are in place.

Notes:
- Step 3 needs your own `gcloud` login (step 2), not the service account:
  the service account is deliberately never allowed to grant IAM to
  itself. See the comments in `terraform/main.tf` for why.
- `kind` (the local Kubernetes tool step 4 uses) doesn't need to be
  installed separately; the Terraform provider drives Docker directly.
- Tear down the Airflow cluster with `terraform destroy` in
  `terraform/local-airflow` when you're done, it frees ~2GB of RAM.

## Repository structure

```
ai_dataengineering/
├── setup.sh                  # one-command bootstrap: terraform (GCP) -> terraform (Airflow) -> dbt
├── airflow/                  # Orchestration only (not infra, no business logic)
│   └── dags/
│       ├── fhir_ingestion.py  #  "fhir" DAG: encounters task group -> raw GCS -> BigQuery
│       └── dbt_pipeline.py    #  "dbt" DAG: runs dbt build daily at 7am
├── ingestion/                  # Orchestrator-agnostic ingestion code (zero Airflow imports)
│   ├── fhir/encounters.py      #  what to extract and how to shape it
│   └── config/tables.yml       #  table registry: dataset + write_disposition per table
├── dbt/                       # dbt Core project: staging -> intermediate -> mart + tests
│   └── models/
│       ├── staging/            #  stg_encounters (typed, no business logic)
│       ├── intermediate/       #  int_encounters_classified (cardiology split lives here)
│       └── marts/               #  fct_encounters (consumption-ready)
├── terraform/                 # IaC only
│   ├── keys/                 #  GCP service account key (gitignored)
│   ├── modules/
│   │   ├── auth/               #  validates credentials, feeds the google provider
│   │   ├── gcs_bucket/         #  provisions the data-lake GCS bucket
│   │   └── bigquery_dataset/   #  provisions a BigQuery dataset (raw_data, analytics)
│   └── local-airflow/        #  Airflow 3 running on a local kind cluster
│       └── main.tf           #    kind_cluster + helm_release (apache-airflow/airflow chart),
│                              #    mounts dags/, ingestion/ and dbt/ into the cluster
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

- [x] Terraform: `auth` module (GCP service-account authentication),
      `gcs_bucket` module (provisions the `data-lake` bucket), and
      `bigquery_dataset` module (provisions `raw_data` and `analytics`)
- [x] Airflow 3 running on a local `kind` cluster (Terraform + Helm chart),
      `KubernetesExecutor`. Every task runs as its own isolated pod,
      mirroring how it'd run on GKE in production
- [x] `fhir` DAG, `encounters` task group: simulates a FHIR API `Encounter`
      call (inpatient + emergency, ICD-10-CM codes across several
      specialties, no filtering at ingestion time), lands the raw records
      as newline-delimited JSON in GCS via `GCSHook`, then loads them into
      `raw_data.raw_encounters` in BigQuery via `GCSToBigQueryOperator`.
      Orchestration (`airflow/dags/`) is fully decoupled from the
      ingestion logic (`ingestion/`, zero Airflow imports, table registry
      in `ingestion/config/tables.yml`) - swapping orchestrators later
      wouldn't touch the ingestion code
- [x] `dbt` DAG: runs `dbt build` daily at 7am via `KubernetesPodOperator`,
      in the official `dbt-bigquery` image rather than the Airflow image
- [x] IAM for the ingestion service account scoped to exactly what it uses
      (bucket-level `storage.objectAdmin`, dataset-level
      `bigquery.dataEditor` on `raw_data` and `analytics`, project-level
      `bigquery.jobUser`), with every grant applied via a human/admin
      identity, not the service account itself
- [x] dbt: `stg_encounters` (typed) → `int_encounters_classified`
      (cardiology split via `icd10_code`) → `fct_encounters`
      (consumption-ready), with schema tests (`unique`, `not_null`,
      `accepted_values`) and a source freshness check on `raw_encounters`
- [x] One-command bootstrap (`setup.sh`): Terraform apply (GCP) → Terraform
      apply (Airflow on kind) → dbt deps
- [x] Streamlit app: AI-readiness scorecard page + RAG chat page (both fail
      gracefully with setup instructions until the pipeline populates
      `ai_metadata`)
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
