"""
FHIR ingestion. HL7 FHIR is the interop standard US hospitals actually use
to expose this kind of data, so that's the shape we're mimicking here.

One task group per FHIR resource, driven by config/tables.yml - whatever
"resource" is set there names the group. Right now the registry only has
one entry: a simulated Encounter feed, land raw JSON in GCS, then load
into BigQuery. No cardiology filtering happens here on purpose, that's
dbt's job once the data is in the warehouse.

Runs on the local kind cluster (see terraform/local-airflow). With
KubernetesExecutor each task gets its own pod.
"""
from __future__ import annotations

import json
import os
import random
import uuid
from datetime import datetime, timezone
from pathlib import Path

import yaml
from airflow.sdk import dag, get_current_context, task, task_group

TABLES_CONFIG_PATH = Path(__file__).parent / "config" / "tables.yml"

HOSPITAL_NAME = "Riverside General Hospital"
HOSPITAL_STATE = "IL"
ENCOUNTER_CLASSES = ["inpatient", "emergency"]

# mixed specialties on purpose, including cardiology (I-codes) - no
# grouping/labeling here, that split happens downstream in dbt
ICD10_CODES = [
    "I10", "I21", "I50", "I48", "I63",
    "J44", "J18", "J45",
    "E11", "E10", "E66",
    "K35", "K80", "K29",
    "S72", "M54", "S82",
    "A09", "B34", "U07.1",
]


def _fake_encounter(encounter_class: str) -> dict:
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


def _table_config() -> dict:
    # only one entry in the registry today, so just grab it
    return yaml.safe_load(TABLES_CONFIG_PATH.read_text())["tables"][0]


def _gcs_upload(bucket_name: str, blob_path: str, records: list[dict]) -> None:
    from google.cloud import storage

    body = "\n".join(json.dumps(r) for r in records)
    storage.Client().bucket(bucket_name).blob(blob_path).upload_from_string(
        body, content_type="application/json"
    )


def _bq_load(gcs_uri: str, project_id: str, dataset_id: str, table_id: str, write_disposition: str) -> int:
    from google.cloud import bigquery

    dispositions = {
        "append": bigquery.WriteDisposition.WRITE_APPEND,
        "truncate": bigquery.WriteDisposition.WRITE_TRUNCATE,
    }
    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{dataset_id}.{table_id}"

    job = client.load_table_from_uri(
        gcs_uri,
        table_ref,
        job_config=bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=True,
            create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
            write_disposition=dispositions[write_disposition],
        ),
    )
    job.result()
    return client.get_table(table_ref).num_rows


TABLE = _table_config()


@dag(
    dag_id="fhir",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["ingestion", "fhir", "raw"],
)
def fhir():
    @task_group(group_id=TABLE["resource"])
    def resource_group():
        @task
        def extract(n_per_class: int = 20) -> list[dict]:
            records = [_fake_encounter(c) for c in ENCOUNTER_CLASSES for _ in range(n_per_class)]
            print(f"generated {len(records)} records")
            return records

        @task
        def load_to_gcs(records: list[dict]) -> str:
            ctx = get_current_context()
            bucket_name = os.environ["GCS_BUCKET_NAME"]
            blob_path = f"raw/fhir/{TABLE['resource']}/dt={ctx['ds']}/{ctx['ts_nodash']}.jsonl"

            _gcs_upload(bucket_name, blob_path, records)

            gcs_uri = f"gs://{bucket_name}/{blob_path}"
            print(f"uploaded {len(records)} records to {gcs_uri}")
            return gcs_uri

        @task
        def load_to_bigquery(gcs_uri: str) -> None:
            project_id = os.environ["GCP_PROJECT_ID"]
            rows = _bq_load(
                gcs_uri,
                project_id,
                TABLE["dataset"],
                TABLE["name"],
                TABLE["write_disposition"],
            )
            print(f"{project_id}.{TABLE['dataset']}.{TABLE['name']} now has {rows} rows")

        load_to_bigquery(load_to_gcs(extract()))

    resource_group()


fhir()
