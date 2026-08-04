-- 003_acl_users.sql — ACL como dado em runtime (Portal Etapa 0).
-- Estrutura IDENTICA a do EBD.ia; muda so o seed.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS acl_users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email        text UNIQUE NOT NULL,
  oid          text,
  nome         text,
  role         text    NOT NULL DEFAULT 'admin'  CHECK (role IN ('admin','gerente','supervisor')),
  scope_kind   text    NOT NULL DEFAULT 'brasil' CHECK (scope_kind IN ('brasil','regional','filiais','filial')),
  scope_value  jsonb   NOT NULL DEFAULT '[]'::jsonb,
  filiais      jsonb   NOT NULL DEFAULT '"*"'::jsonb,
  super_admin  boolean NOT NULL DEFAULT false,
  active       boolean NOT NULL DEFAULT true,
  created_by   text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_acl_users_email_lower ON acl_users (lower(email));

CREATE TABLE IF NOT EXISTS acl_audit (
  id bigserial PRIMARY KEY, actor_email text, action text NOT NULL,
  target_email text, before jsonb, after jsonb, at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO acl_users (email, nome, role, scope_kind, filiais, super_admin, created_by) VALUES
  ('thiago.parreira@ebdgrupo.com.br','Thiago Parreira','admin','brasil','"*"', true,  'seed'),
  ('smoraes@ebdgrupo.com.br',        'S. Moraes',      'admin','brasil','"*"', false, 'seed'),
  ('rosana.cesario@ebdgrupo.com.br', 'Rosana Cesario', 'admin','brasil','"*"', false, 'seed')
ON CONFLICT (email) DO NOTHING;
