"""
Raw encounter ingestion from a FHIR API.

Simulates a call to the Encounter endpoint of a FHIR API (HL7 FHIR is the
real interoperability standard US hospitals use to expose this kind of
data) for a fictional US hospital, and lands the raw, untouched records in
GCS (the "raw" landing zone). No specialty or diagnosis filtering happens
here on purpose: this task only extracts and lands raw data. Once it's
loaded into BigQuery, dbt is where cardiology (and any other specialty)
gets identified and modeled.

Runs inside the kind cluster (Airflow installed via Helm, see
terraform/local-airflow). With KubernetesExecutor, each run of the
"encounters" task comes up as its own isolated Pod in the cluster.
"""
from __future__ import annotations

import json
import os
import random
import uuid
from datetime import datetime, timezone

from airflow.sdk import dag, get_current_context, task

HOSPITAL_NAME = "Riverside General Hospital"
HOSPITAL_STATE = "IL"

ENCOUNTER_CLASSES = ["inpatient", "emergency"]

# Flat pool of real ICD-10-CM codes spanning several specialties (including
# cardiology). Intentionally not grouped or labeled by specialty here.
ICD10_CODES = [
    "I10", "I21", "I50", "I48", "I63",  # circulatory system
    "J44", "J18", "J45",                # respiratory system
    "E11", "E10", "E66",                # endocrine / metabolic
    "K35", "K80", "K29",                # digestive system
    "S72", "M54", "S82",                # musculoskeletal / injury
    "A09", "B34", "U07.1",              # infectious disease
]


def _simulate_fhir_encounter_request(encounter_class: str) -> dict:
    """Simulates a call to a FHIR API Encounter endpoint and returns one raw encounter."""
    return {
        "encounter_id": str(uuid.uuid4()),
        "encounter_class": encounter_class,
        "icd10_code": random.choice(ICD10_CODES),
        "patient_age": random.randint(0, 100),
        "patient_sex": random.choice(["M", "F"]),
        "hospital_name": HOSPITAL_NAME,
        "hospital_state": HOSPITAL_STATE,
        "charge_amount_usd": round(random.uniform(150.0, 25000.0), 2),
        "encounter_datetime": datetime.now(timezone.utc).isoformat(),
    }


def _upload_raw_encounters_to_gcs(bucket_name: str, blob_path: str, records: list[dict]) -> None:
    """Uploads the raw records to GCS as newline-delimited JSON (one record per line)."""
    from google.cloud import storage

    body = "\n".join(json.dumps(record) for record in records)

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_path)
    blob.upload_from_string(body, content_type="application/json")


def _load_gcs_to_bigquery(gcs_uri: str, project_id: str, dataset_id: str, table_id: str) -> int:
    """Loads a newline-delimited JSON file from GCS into a BigQuery table, creating it on first run."""
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{dataset_id}.{table_id}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=True,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )

    load_job = client.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    load_job.result()

    return client.get_table(table_ref).num_rows


@dag(
    dag_id="fhir_ingestion",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["ingestion", "fhir", "encounters", "raw"],
)
def fhir_ingestion():
    @task
    def encounters(n_per_class: int = 20) -> str:
        context = get_current_context()
        run_date = context["ds"]
        run_ts = context["ts_nodash"]

        records = [
            _simulate_fhir_encounter_request(encounter_class)
            for encounter_class in ENCOUNTER_CLASSES
            for _ in range(n_per_class)
        ]

        bucket_name = os.environ["GCS_BUCKET_NAME"]
        blob_path = f"raw/fhir_encounters/dt={run_date}/encounters_{run_ts}.jsonl"

        _upload_raw_encounters_to_gcs(bucket_name, blob_path, records)

        gcs_uri = f"gs://{bucket_name}/{blob_path}"
        print(f"Uploaded {len(records)} raw encounters to {gcs_uri}")
        return gcs_uri

    @task
    def load_to_bigquery(gcs_uri: str) -> None:
        project_id = os.environ["GCP_PROJECT_ID"]
        dataset_id = os.environ.get("BQ_RAW_DATASET", "raw_data")
        table_id = "raw_encounters"

        total_rows = _load_gcs_to_bigquery(gcs_uri, project_id, dataset_id, table_id)
        print(f"Loaded {gcs_uri} into {project_id}.{dataset_id}.{table_id} ({total_rows} rows total)")

    load_to_bigquery(encounters())


fhir_ingestion()
