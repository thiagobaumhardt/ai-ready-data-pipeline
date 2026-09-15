"""
Minimal RAG helper: embeds the user question, retrieves the closest chunks
from BigQuery Vector Search (`ai_embeddings`), and asks an LLM to answer
using only that retrieved context.

Requires the ingestion/embedding pipeline to have populated `ai_embeddings`
with the SAME embedding model as EMBEDDING_MODEL below, otherwise cosine
distances are meaningless. Keep them in sync via `embedding_model_version`.
"""
import os

from google.cloud import bigquery
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings

from .bigquery import get_client, table_ref

EMBEDDING_MODEL = "models/text-embedding-004"
CHAT_MODEL = "gemini-1.5-flash"


def embed_query(text: str) -> list[float]:
    embedder = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL)
    return embedder.embed_query(text)


def retrieve_chunks(query_embedding: list[float], top_k: int = 5) -> list[dict]:
    client: bigquery.Client = get_client()
    embeddings_table = table_ref("BQ_AI_METADATA_DATASET", "BQ_EMBEDDINGS_TABLE")

    sql = f"""
        SELECT
          base.chunk_id AS chunk_id,
          base.chunk_text AS chunk_text,
          base.source AS source,
          distance
        FROM VECTOR_SEARCH(
          TABLE `{embeddings_table}`,
          'embedding',
          (SELECT @query_embedding AS embedding),
          top_k => @top_k,
          distance_type => 'COSINE'
        )
        ORDER BY distance ASC
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("query_embedding", "FLOAT64", query_embedding),
            bigquery.ScalarQueryParameter("top_k", "INT64", top_k),
        ]
    )
    rows = client.query(sql, job_config=job_config).result()
    return [dict(row) for row in rows]


def answer_with_context(question: str, chunks: list[dict]) -> str:
    if not os.environ.get("GOOGLE_API_KEY"):
        return (
            "GOOGLE_API_KEY not set. Define it in streamlit_app's .env to "
            "enable the LLM answer. The retrieved chunks are listed below "
            "regardless."
        )

    context = "\n\n".join(f"[{c['source']}] {c['chunk_text']}" for c in chunks)
    llm = ChatGoogleGenerativeAI(model=CHAT_MODEL, temperature=0)
    prompt = (
        "Answer the user's question using ONLY the context below, drawn "
        "from hospital encounters. If the context isn't sufficient, say "
        "there isn't enough data.\n\n"
        f"Context:\n{context}\n\n"
        f"Question: {question}"
    )
    return llm.invoke(prompt).content
