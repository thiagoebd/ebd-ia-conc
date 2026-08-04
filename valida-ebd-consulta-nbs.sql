-- ============================================================
-- Validacao do usuario EBD_CONSULTA no NBS (bmw.grupoebd.ebdbr.com.br)
-- Rodar CONECTADO COMO ELE, antes de liberar o MCP.
-- ============================================================

-- 1. Privilegios de sistema. Esperado: praticamente so CREATE SESSION.
--    Qualquer coisa com ANY (SELECT ANY TABLE, UPDATE ANY TABLE) e alarme.
SELECT * FROM session_privs ORDER BY privilege;

-- 2. Privilegios de objeto diferentes de SELECT.
--    Esperado: ZERO LINHAS. Se voltar INSERT/UPDATE/DELETE/EXECUTE,
--    o usuario nao e de consulta.
SELECT owner, table_name, privilege, grantable
  FROM all_tab_privs
 WHERE grantee = USER
   AND privilege <> 'SELECT'
 ORDER BY owner, table_name;

-- 3. Roles herdadas. Nao pode ter DBA, RESOURCE nem role custom com escrita.
SELECT granted_role, admin_option, default_role FROM user_role_privs;

-- 4. Cobertura de leitura: quais schemas do NBS ele enxerga.
--    Se o schema principal do NBS nao aparecer, faltam GRANT SELECT.
SELECT owner, COUNT(*) AS tabelas
  FROM all_tables
 GROUP BY owner
 ORDER BY tabelas DESC;

-- 5. Sanidade da conexao e do fuso (o MCP loga em America/Sao_Paulo).
SELECT USER AS usuario,
       SYS_CONTEXT('USERENV','DB_NAME')     AS db,
       SYS_CONTEXT('USERENV','SERVICE_NAME') AS servico,
       SYSDATE                               AS data_banco,
       DBTIMEZONE                            AS tz_banco
  FROM DUAL;

-- 6. Primeiro reconhecimento do modelo NBS (insumo do discover).
--    Tabelas com mais volume aparente, por schema.
SELECT owner, table_name, num_rows, last_analyzed
  FROM all_tables
 WHERE num_rows > 0
 ORDER BY num_rows DESC
 FETCH FIRST 50 ROWS ONLY;
