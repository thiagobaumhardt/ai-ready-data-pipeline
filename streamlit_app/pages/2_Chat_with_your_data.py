from dotenv import load_dotenv
import streamlit as st

from lib.bigquery import is_configured, table_exists, table_ref
from lib.rag import answer_with_context, embed_query, retrieve_chunks

load_dotenv()

st.set_page_config(page_title="Chat with your data", page_icon="💬")
st.title("💬 Chat with your data")
st.caption(
    "RAG over `ai_metadata.ai_embeddings` (BigQuery Vector Search). Answers "
    "are grounded only in retrieved chunks, no free-form generation."
)

if not is_configured():
    st.error(
        "GCP_PROJECT_ID not set. Copy `streamlit_app/.env.example` to "
        "`.env` and fill in your GCP credentials before continuing."
    )
    st.stop()

embeddings_table = table_ref("BQ_AI_METADATA_DATASET", "BQ_EMBEDDINGS_TABLE")

if not table_exists(embeddings_table):
    st.warning(
        f"Table `{embeddings_table}` doesn't exist yet. It's populated by "
        "the pipeline's chunking + embeddings step (see 'Build order' in "
        "the README). Run the pipeline in Airflow first."
    )
    st.stop()

if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

question = st.chat_input("Ask something about the encounters...")

if question:
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner("Searching for relevant context..."):
            query_embedding = embed_query(question)
            chunks = retrieve_chunks(query_embedding, top_k=5)

        if not chunks:
            answer = "No relevant chunks found for this question."
        else:
            answer = answer_with_context(question, chunks)

        st.markdown(answer)

        if chunks:
            with st.expander(f"Retrieved context ({len(chunks)} chunks)"):
                for c in chunks:
                    st.markdown(f"**{c['source']}** (distance: {c['distance']:.4f})")
                    st.text(c["chunk_text"])

    st.session_state.messages.append({"role": "assistant", "content": answer})
