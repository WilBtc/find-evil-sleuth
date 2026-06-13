-- DFIR knowledge base: a pgvector corpus of incident-handling/forensics reference
-- knowledge that specialists consult for technique and artifact grounding.
-- Content is operator-provided and ingested locally (never committed to the repo).
CREATE TABLE IF NOT EXISTS dfir_knowledge (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source     text NOT NULL,
    chunk      text NOT NULL,
    embedding  vector(1536),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dfir_knowledge_embedding_idx
    ON dfir_knowledge USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
