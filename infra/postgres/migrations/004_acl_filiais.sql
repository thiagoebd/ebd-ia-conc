-- 004_acl_filiais.sql — fonte unica da estrutura de escopo.
-- Estrutura IDENTICA a do EBD.ia (tabela, CHECK de coerencia e view).
-- SEED: so a BMW (unica base ligada hoje). Concessionaria nova = INSERT aqui,
-- nao mexe em codigo.
CREATE TABLE IF NOT EXISTS acl_filiais (
  codigo      text PRIMARY KEY,
  nome        text NOT NULL,
  tipo        text NOT NULL CHECK (tipo IN ('filial','deposito')),
  filial_mae  text REFERENCES acl_filiais(codigo),
  regional    text,
  ativa       boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT acl_filiais_coerencia CHECK (
    (tipo = 'filial'   AND regional IS NOT NULL AND filial_mae IS NULL) OR
    (tipo = 'deposito' AND regional IS NULL     AND filial_mae IS NOT NULL)
  )
);

INSERT INTO acl_filiais (codigo, nome, tipo, regional) VALUES
  ('01','BMW','filial','BMW')
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE VIEW acl_filiais_resolvido AS
SELECT f.codigo, f.nome, f.tipo, f.filial_mae, f.ativa,
       COALESCE(f.regional, m.regional) AS regional
FROM acl_filiais f
LEFT JOIN acl_filiais m ON m.codigo = f.filial_mae;
