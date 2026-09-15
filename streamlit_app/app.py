from dotenv import load_dotenv
import streamlit as st

load_dotenv()

st.set_page_config(page_title="AI-Ready Data Pipeline", page_icon="🤖")

st.title("🤖 AI-Ready Data Pipeline")
st.markdown(
    """
This app is the front end for the [AI-Ready Data Pipeline](../README.md)
project: it reads directly from the `ai_metadata` BigQuery dataset produced
by the Airflow + dbt pipeline.

Use the sidebar to navigate:

- **AI Readiness Scorecard** — per-table freshness, metadata and governance
  status, sourced from `ai_readiness_scorecard`.
- **Chat with your data** — ask questions over healthcare encounter notes,
  answered via BigQuery Vector Search + an LLM (RAG), grounded only in
  retrieved context.

Configure `streamlit_app/.env` (see `.env.example`) with your GCP project
and credentials before running.
"""
)
