from dotenv import load_dotenv
import streamlit as st

from lib.bigquery import is_configured, table_exists, table_ref
from lib.rag import answer_with_context, embed_query, retrieve_chunks

load_dotenv()

st.set_page_config(page_title="Chat with your data", page_icon="💬")
st.title("💬 Chat with your data")
st.caption(
    "RAG over `ai_metadata.ai_embeddings` (BigQuery Vector Search). Answers "
    "are grounded only in retrieved chunks — no free-form generation."
)

if not is_configured():
    st.error(
        "GCP_PROJECT_ID não configurado. Copie `streamlit_app/.env.example` "
        "para `.env` e preencha suas credenciais do GCP antes de continuar."
    )
    st.stop()

embeddings_table = table_ref("BQ_AI_METADATA_DATASET", "BQ_EMBEDDINGS_TABLE")

if not table_exists(embeddings_table):
    st.warning(
        f"Tabela `{embeddings_table}` ainda não existe. Ela é populada pela "
        "etapa de chunking + embeddings do pipeline (ver 'Build order' no "
        "README) — rode o pipeline no Airflow primeiro."
    )
    st.stop()

if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

question = st.chat_input("Pergunte algo sobre os atendimentos...")

if question:
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner("Buscando contexto relevante..."):
            query_embedding = embed_query(question)
            chunks = retrieve_chunks(query_embedding, top_k=5)

        if not chunks:
            answer = "Nenhum trecho relevante encontrado para essa pergunta."
        else:
            answer = answer_with_context(question, chunks)

        st.markdown(answer)

        if chunks:
            with st.expander(f"Contexto recuperado ({len(chunks)} trechos)"):
                for c in chunks:
                    st.markdown(f"**{c['source']}** (distância: {c['distance']:.4f})")
                    st.text(c["chunk_text"])

    st.session_state.messages.append({"role": "assistant", "content": answer})
