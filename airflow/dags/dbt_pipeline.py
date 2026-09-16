"""
Runs the dbt project (staging -> intermediate -> marts) daily at 7am.

Orchestration only, same as fhir_ingestion.py - the actual dbt project
lives in dbt/, mounted read-only into this task's pod. Runs in the
official dbt-bigquery image rather than the Airflow image, since dbt
itself isn't installed there.
"""
from __future__ import annotations

import os
from datetime import datetime

from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.sdk import dag, task
from kubernetes.client import models as k8s

DBT_PROJECT_PATH = "/opt/dbt"
GCP_KEY_PATH = "/opt/airflow/gcp/key.json"


@dag(
    dag_id="dbt",
    schedule="0 7 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["dbt", "transformation"],
)
def dbt():
    @task
    def gcp_project_id() -> str:
        # read here, not at module level: only the worker pod running this
        # task has GCP_PROJECT_ID set, the dag-processor doesn't
        return os.environ["GCP_PROJECT_ID"]

    KubernetesPodOperator(
        task_id="build",
        name="dbt-build",
        namespace="airflow",
        image="ghcr.io/dbt-labs/dbt-bigquery:1.9.latest",
        cmds=["dbt"],
        arguments=["build", "--project-dir", DBT_PROJECT_PATH, "--profiles-dir", DBT_PROJECT_PATH],
        env_vars={
            "GCP_PROJECT_ID": gcp_project_id(),
            "GOOGLE_APPLICATION_CREDENTIALS": GCP_KEY_PATH,
        },
        volumes=[
            k8s.V1Volume(
                name="dbt-project",
                host_path=k8s.V1HostPathVolumeSource(path=DBT_PROJECT_PATH, type="Directory"),
            ),
            k8s.V1Volume(
                name="gcp-credentials",
                host_path=k8s.V1HostPathVolumeSource(path=GCP_KEY_PATH, type="File"),
            ),
        ],
        volume_mounts=[
            k8s.V1VolumeMount(name="dbt-project", mount_path=DBT_PROJECT_PATH),
            k8s.V1VolumeMount(name="gcp-credentials", mount_path=GCP_KEY_PATH, read_only=True),
        ],
        in_cluster=True,
        get_logs=True,
        on_finish_action="delete_pod",
    )


dbt()
