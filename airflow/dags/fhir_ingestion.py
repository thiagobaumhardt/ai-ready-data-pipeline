"""
FHIR ingestion. HL7 FHIR is the interop standard US hospitals actually use
to expose this kind of data, so that's the shape we're mimicking here.

Orchestration only lives in this file - task/operator wiring and
dependencies. The encounter-generation logic is in fhir_encounters.py.

Runs on the local kind cluster (see terraform/local-airflow). With
KubernetesExecutor each task gets its own pod. load_to_bigquery uses the
google provider's own GCSToBigQueryOperator instead of hand-rolled client
code.
"""
from __future__ import annotations

import os
from datetime import datetime

from airflow.providers.google.cloud.hooks.gcs import GCSHook
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator
from airflow.sdk import dag, get_current_context, task, task_group

from ingestion.fhir.encounters import WRITE_DISPOSITIONS, generate_encounters, table_config, to_ndjson

TABLE = table_config()


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
            records = generate_encounters(n_per_class)
            print(f"generated {len(records)} records")
            return records

        @task
        def load_to_gcs(records: list[dict]) -> dict:
            ctx = get_current_context()
            bucket_name = os.environ["GCS_BUCKET_NAME"]
            object_name = f"raw/fhir/{TABLE['resource']}/dt={ctx['ds']}/{ctx['ts_nodash']}.jsonl"

            GCSHook().upload(
                bucket_name=bucket_name,
                object_name=object_name,
                data=to_ndjson(records),
                mime_type="application/json",
            )

            print(f"uploaded {len(records)} records to gs://{bucket_name}/{object_name}")
            return {
                "bucket": bucket_name,
                "object": object_name,
                "destination_table": f"{os.environ['GCP_PROJECT_ID']}.{TABLE['dataset']}.{TABLE['name']}",
            }

        gcs = load_to_gcs(extract())

        GCSToBigQueryOperator(
            task_id="load_to_bigquery",
            bucket=gcs["bucket"],
            source_objects=[gcs["object"]],
            destination_project_dataset_table=gcs["destination_table"],
            source_format="NEWLINE_DELIMITED_JSON",
            autodetect=True,
            create_disposition="CREATE_IF_NEEDED",
            write_disposition=WRITE_DISPOSITIONS[TABLE["write_disposition"]],
        )

    resource_group()


fhir()
