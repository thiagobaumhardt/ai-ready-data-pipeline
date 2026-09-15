import os

import pandas as pd
import streamlit as st
from google.cloud import bigquery
from google.cloud.exceptions import NotFound


def is_configured() -> bool:
    return bool(os.environ.get("GCP_PROJECT_ID"))


@st.cache_resource
def get_client() -> bigquery.Client:
    project_id = os.environ["GCP_PROJECT_ID"]
    return bigquery.Client(project=project_id)


def table_ref(dataset_env: str, table_env: str) -> str:
    client = get_client()
    dataset = os.environ.get(dataset_env, "ai_metadata")
    table = os.environ[table_env]
    return f"{client.project}.{dataset}.{table}"


def table_exists(full_table_id: str) -> bool:
    client = get_client()
    try:
        client.get_table(full_table_id)
        return True
    except NotFound:
        return False


@st.cache_data(ttl=300)
def query_df(sql: str) -> pd.DataFrame:
    client = get_client()
    return client.query(sql).to_dataframe()
