from dotenv import load_dotenv
import plotly.express as px
import streamlit as st

from lib.bigquery import is_configured, query_df, table_exists, table_ref

load_dotenv()

st.set_page_config(page_title="AI Readiness Scorecard", page_icon="📊")
st.title("📊 AI Readiness Scorecard")
st.caption(
    "Per-table AI-readiness: metadata catalog, data contract, freshness SLA "
    "and PHI governance, sourced from `ai_metadata.ai_readiness_scorecard`."
)

if not is_configured():
    st.error(
        "GCP_PROJECT_ID not set. Copy `streamlit_app/.env.example` to "
        "`.env` and fill in your GCP credentials before continuing."
    )
    st.stop()

scorecard_table = table_ref("BQ_AI_METADATA_DATASET", "BQ_SCORECARD_TABLE")

if not table_exists(scorecard_table):
    st.warning(
        f"Table `{scorecard_table}` doesn't exist yet. It's populated by "
        "the pipeline's freshness/scorecard step (see 'Build order' in the "
        "README). Run the pipeline in Airflow first."
    )
    st.stop()

df = query_df(f"SELECT * FROM `{scorecard_table}` ORDER BY ai_readiness_score DESC")

if df.empty:
    st.info("The table exists but has no rows yet.")
    st.stop()

col1, col2, col3 = st.columns(3)
col1.metric("Tables monitored", len(df))
col2.metric("Average score", f"{df['ai_readiness_score'].mean():.0f}/100")
col3.metric("Fresh tables", int(df["is_fresh"].sum()) if "is_fresh" in df else "-")

fig = px.bar(
    df,
    x="table_name",
    y="ai_readiness_score",
    color="ai_readiness_score",
    color_continuous_scale="RdYlGn",
    range_color=[0, 100],
    labels={"table_name": "Table", "ai_readiness_score": "AI-Readiness Score"},
)
st.plotly_chart(fig, use_container_width=True)

st.dataframe(df, use_container_width=True, hide_index=True)
