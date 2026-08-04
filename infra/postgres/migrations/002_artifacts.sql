-- 002_artifacts.sql — tabela de artefatos (xlsx/pdf/pptx/chart/route_map).
-- Criada aqui porque no EBD.ia ela existia so no banco, sem DDL versionado.
CREATE TABLE IF NOT EXISTS artifacts (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_oid        text        NOT NULL,
    conversation_id uuid        REFERENCES conversations(id) ON DELETE CASCADE,
    kind            text        NOT NULL CHECK (kind IN ('xlsx','pdf','pptx','chart','route_map')),
    filename        text        NOT NULL,
    title           text,
    file_path       text        NOT NULL,
    size_bytes      bigint,
    metadata        jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_artifacts_user_created ON artifacts (user_oid, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_artifacts_conv ON artifacts (conversation_id);
