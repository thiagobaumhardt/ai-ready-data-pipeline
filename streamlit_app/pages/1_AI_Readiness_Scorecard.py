from dotenv import load_dotenv
import plotly.express as px
import streamlit as st

from lib.bigquery import is_configured, query_df, table_exists, table_ref

load_dotenv()

st.set_page_config(page_title="AI Readiness Scorecard", page_icon="📊")
st.title("📊 AI Readiness Scorecard")
st.caption(
    "Per-table AI-readiness: metadata catalog, data contract, freshness SLA "
    "and PHI governance — sourced from `ai_metadata.ai_readiness_scorecard`."
)

if not is_configured():
    st.error(
        "GCP_PROJECT_ID não configurado. Copie `streamlit_app/.env.example` "
        "para `.env` e preencha suas credenciais do GCP antes de continuar."
    )
    st.stop()

scorecard_table = table_ref("BQ_AI_METADATA_DATASET", "BQ_SCORECARD_TABLE")

if not table_exists(scorecard_table):
    st.warning(
        f"Tabela `{scorecard_table}` ainda não existe. Ela é populada pela "
        "etapa de freshness/scorecard do pipeline (ver 'Build order' no "
        "README) — rode o pipeline no Airflow primeiro."
    )
    st.stop()

df = query_df(f"SELECT * FROM `{scorecard_table}` ORDER BY ai_readiness_score DESC")

if df.empty:
    st.info("A tabela existe mas ainda não tem linhas.")
    st.stop()

col1, col2, col3 = st.columns(3)
col1.metric("Tabelas monitoradas", len(df))
col2.metric("Score médio", f"{df['ai_readiness_score'].mean():.0f}/100")
col3.metric("Tabelas frescas", int(df["is_fresh"].sum()) if "is_fresh" in df else "—")

fig = px.bar(
    df,
    x="table_name",
    y="ai_readiness_score",
    color="ai_readiness_score",
    color_continuous_scale="RdYlGn",
    range_color=[0, 100],
    labels={"table_name": "Tabela", "ai_readiness_score": "AI-Readiness Score"},
)
st.plotly_chart(fig, use_container_width=True)

st.dataframe(df, use_container_width=True, hide_index=True)
