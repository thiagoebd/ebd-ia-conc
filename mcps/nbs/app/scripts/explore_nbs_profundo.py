#!/usr/bin/env python3
"""explore_nbs_profundo.py — segunda rodada de discover do NBS.

A primeira rodada (explore_nbs.py) extraiu o dicionario. Esta responde as
PERGUNTAS ABERTAS, cruzando o modelo com os indicadores que o BI da EBD ja usa:

  1. Dominios completos (status, tipos, naturezas, divisoes)
  2. Onde vive cada medida do BI (Vl_Atendido, Cobrar, TMO, peca x servico)
  3. Janela real de dados de cada tabela viva
  4. Numeros de sanidade para validar os primeiros indicadores
  5. Estoque de pecas: bloqueado, curva ABC, custo, cobertura

Roda dentro do container do MCP:

    docker cp explore_nbs_profundo.py conc_mcp_nbs:/tmp/
    docker exec conc_mcp_nbs python /tmp/explore_nbs_profundo.py
    docker cp conc_mcp_nbs:/tmp/nbs_discovery2 ./discovery2

Saida em /tmp/nbs_discovery2/RELATORIO.md (+ .jsonl por bloco).
Somente SELECT. Nenhuma consulta escreve.
"""
from __future__ import annotations

import json
import os
import re
from datetime import datetime
from pathlib import Path

import oracledb

OWNER = os.getenv("NBS_OWNER", "NBS")
EMP = os.getenv("NBS_EMPRESA", "1")
SAIDA = Path("/tmp/nbs_discovery2")

# Tabelas do nucleo cujo dicionario completo queremos em maos
NUCLEO = [
    "OS", "OS_SERVICOS", "OS_REQUISICOES", "OS_ORIGINAL", "OS_TIPOS",
    "OS_TIPOS_EMPRESAS", "OS_STATUS", "ANDAMENTO", "OS_AGENDA",
    "OS_TEMPOS_EXECUTADOS", "SERVICOS", "SERVICOS_TECNICOS",
    "VENDAS", "VENDA_ITENS", "VENDA_STATUS", "NATUREZA", "OPERACOES",
    "VEICULOS", "VEICULOS_PROPOSTAS", "PRODUTOS", "PRODUTOS_MODELOS",
    "ITENS", "ITENS_CUSTOS", "ITENS_FORNECEDOR", "ESTOQUE",
    "CLIENTES", "CLIENTE_DIVERSO", "COMPRA", "COMPRAS_ITENS",
    "CONTA_RECEBER", "CONTA_PAGAR", "EMPRESAS", "EMPRESAS_DIVISOES",
    "EMPRESAS_USUARIOS", "EMPRESAS_META", "CENTRO_CUSTO", "SETOR_VENDA",
]

# Dominios: tabelas pequenas cujo conteudo INTEIRO interessa
DOMINIOS = [
    "OS_STATUS", "VENDA_STATUS", "OS_TIPOS", "ANDAMENTO", "OS_MOBILIDADE",
    "SETOR_VENDA", "EMPRESAS_DIVISOES", "EMPRESAS_DEPARTAMENTOS",
    "VEICULOS_CLASSE_VENDA", "OS_MOTIVO_RETORNO", "OS_TIPOS_FABRICA",
    "PRODUTO_SEGMENTO", "CLASSE", "OPERACOES",
]

# Palavras que denunciam a medida do BI que ainda nao mapeamos
PISTAS = {
    "Vl_Atendido": r"VL_ATEND|VALOR_ATEND|VLATEND|TOTAL_ATEND",
    "Cobrar": r"^COBRAR|_COBRAR|COBRANCA_OS",
    "TMO": r"TMO|TEMPO_PADRAO|TEMPO_ESTIMADO|HORAS_VEND|HORAS_TRAB",
    "curva_abc": r"CURVA|ABC|CLASSIF",
    "bloqueado": r"BLOQUEAD|RESERVAD|INDISPON",
    "custo_medio": r"CUSTO_MEDIO|CUSTOMEDIO|PRECO_MEDIO",
    "margem": r"MARGEM|LUCRO|RENTAB",
    "repasse_tradein": r"REPASSE|TRADE|TROCA|AVALIACAO",
}


def conn():
    return oracledb.connect(user=os.environ["NBS_USER"],
                            password=os.environ["NBS_PASSWORD"],
                            dsn=os.environ["NBS_DSN"])


def q(cur, sql, params=None, limite=None):
    cur.execute(sql, params or {})
    cols = [d[0] for d in cur.description]
    linhas = cur.fetchmany(limite) if limite else cur.fetchall()
    out = []
    for l in linhas:
        reg = {}
        for c, v in zip(cols, l):
            if isinstance(v, oracledb.LOB):
                v = "<lob>"
            elif isinstance(v, datetime):
                v = v.isoformat()
            reg[c] = v
        out.append(reg)
    return cols, out


def md_tabela(fh, cols, linhas, limite=40):
    if not linhas:
        fh.write("_(vazio)_\n\n")
        return
    fh.write("| " + " | ".join(cols) + " |\n")
    fh.write("|" + "|".join(["---"] * len(cols)) + "|\n")
    for r in linhas[:limite]:
        fh.write("| " + " | ".join(str(r.get(c, ""))[:60] for c in cols) + " |\n")
    if len(linhas) > limite:
        fh.write(f"\n_... +{len(linhas)-limite} linhas_\n")
    fh.write("\n")


def seguro(fh, titulo, fn):
    fh.write(f"\n### {titulo}\n\n")
    try:
        fn()
    except oracledb.DatabaseError as e:
        fh.write(f"⚠️ `{str(e).splitlines()[0][:150]}`\n\n")


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    c = conn()
    cur = c.cursor()
    rel = (SAIDA / "RELATORIO.md").open("w", encoding="utf-8")
    W = rel.write

    W(f"# Discover profundo — NBS (schema {OWNER}, empresa {EMP})\n\n")
    W(f"Gerado em {datetime.now():%d/%m/%Y %H:%M}. Somente SELECT.\n\n---\n")

    # ---------------------------------------------------------------
    W("\n## 1. Domínios completos\n")
    W("\nValores reais das tabelas de domínio — é o que o agente precisa "
      "para traduzir status e tipo sem adivinhar.\n")
    for t in DOMINIOS:
        def _f(t=t):
            cols, linhas = q(cur, f"SELECT * FROM {OWNER}.{t}", limite=60)
            cols = cols[:8]
            md_tabela(rel, cols, linhas, 60)
        seguro(rel, t, _f)

    # ---------------------------------------------------------------
    W("\n## 2. Onde vivem as medidas do BI\n")
    W("\nBusca por padrão de nome no dicionário inteiro. Resolve as pendências "
      "`Vl_Atendido`, `Cobrar`, TMO, curva ABC, bloqueado, margem.\n")
    for rotulo, padrao in PISTAS.items():
        def _f(rotulo=rotulo, padrao=padrao):
            cols, linhas = q(cur, f"""
                SELECT table_name, column_name, data_type
                  FROM all_tab_columns
                 WHERE owner = :o
                   AND REGEXP_LIKE(column_name, :p)
                   AND table_name NOT LIKE 'FAB\\_%' ESCAPE '\\'
                   AND table_name NOT LIKE 'TMP\\_%' ESCAPE '\\'
                   AND table_name NOT LIKE '%\\_LOG' ESCAPE '\\'
                 ORDER BY table_name, column_name
            """, {"o": OWNER, "p": padrao}, limite=80)
            md_tabela(rel, cols, linhas, 80)
        seguro(rel, f"`{rotulo}`", _f)

    # ---------------------------------------------------------------
    W("\n## 3. Dicionário do núcleo\n")
    W("\nColunas das tabelas que os indicadores usam.\n")
    for t in NUCLEO:
        def _f(t=t):
            cols, linhas = q(cur, """
                SELECT c.column_name, c.data_type, c.nullable, m.comments
                  FROM all_tab_columns c
                  LEFT JOIN all_col_comments m
                         ON m.owner=c.owner AND m.table_name=c.table_name
                        AND m.column_name=c.column_name
                 WHERE c.owner=:o AND c.table_name=:t
                 ORDER BY c.column_id
            """, {"o": OWNER, "t": t})
            md_tabela(rel, cols, linhas, 200)
        seguro(rel, t, _f)

    # ---------------------------------------------------------------
    W("\n## 4. Janela real de dados (onde a operação está viva)\n")
    for t, col in [("OS", "DATA_EMISSAO"), ("VENDAS", "EMISSAO"),
                   ("COMPRA", "DATA_ENTRADA"), ("OS_AGENDA", "DATA_AGENDADA"),
                   ("VEICULOS", "DATA_FATURAMENTO")]:
        def _f(t=t, col=col):
            cols, linhas = q(cur, f"""
                SELECT TO_CHAR({col},'YYYY') AS ANO, COUNT(*) AS QTD,
                       MIN({col}) AS MIN_DT, MAX({col}) AS MAX_DT
                  FROM {OWNER}.{t}
                 WHERE {col} IS NOT NULL
                 GROUP BY TO_CHAR({col},'YYYY')
                 ORDER BY 1 DESC
            """, limite=15)
            md_tabela(rel, cols, linhas, 15)
        seguro(rel, f"{t}.{col}", _f)

    # ---------------------------------------------------------------
    W("\n## 5. Números de sanidade (últimos 6 meses)\n")

    def _fat_natureza():
        cols, linhas = q(cur, f"""
            SELECT TO_CHAR(v.EMISSAO,'YYYY-MM') AS COMPETENCIA,
                   n.NATUREZA_APLICACAO         AS APLICACAO,
                   COUNT(*)                     AS QTD_NOTAS,
                   SUM(v.TOTAL_NOTA)            AS TOTAL_NOTA,
                   SUM(v.TOTAL_PRODUTOS)        AS TOT_PRODUTOS,
                   SUM(v.TOTAL_SERVICOS)        AS TOT_SERVICOS
              FROM {OWNER}.VENDAS v
              JOIN {OWNER}.NATUREZA n ON n.COD_NATUREZA = v.COD_NATUREZA
             WHERE v.COD_EMPRESA = :e
               AND v.STATUS = '0'
               AND v.EMISSAO >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -6)
             GROUP BY TO_CHAR(v.EMISSAO,'YYYY-MM'), n.NATUREZA_APLICACAO
             ORDER BY 1 DESC, 4 DESC
        """, {"e": int(EMP)}, limite=80)
        md_tabela(rel, cols, linhas, 80)
    seguro(rel, "Faturamento por natureza (STATUS='0')", _fat_natureza)

    def _os_status():
        cols, linhas = q(cur, f"""
            SELECT TO_CHAR(o.DATA_EMISSAO,'YYYY-MM') AS COMPETENCIA,
                   o.STATUS_OS, s.DESCRICAO, COUNT(*) AS QTD
              FROM {OWNER}.OS o
              LEFT JOIN {OWNER}.OS_STATUS s ON s.STATUS_OS = o.STATUS_OS
             WHERE o.COD_EMPRESA = :e
               AND o.DATA_EMISSAO >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -6)
             GROUP BY TO_CHAR(o.DATA_EMISSAO,'YYYY-MM'), o.STATUS_OS, s.DESCRICAO
             ORDER BY 1 DESC, 4 DESC
        """, {"e": int(EMP)}, limite=80)
        md_tabela(rel, cols, linhas, 80)
    seguro(rel, "OS por status/mês", _os_status)

    def _os_tipo():
        cols, linhas = q(cur, f"""
            SELECT o.TIPO, t.DESCRICAO, t.GARANTIA, t.INTERNO, COUNT(*) AS QTD
              FROM {OWNER}.OS o
              LEFT JOIN {OWNER}.OS_TIPOS t ON t.TIPO = o.TIPO
             WHERE o.COD_EMPRESA = :e
               AND o.DATA_EMISSAO >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -6)
             GROUP BY o.TIPO, t.DESCRICAO, t.GARANTIA, t.INTERNO
             ORDER BY 5 DESC
        """, {"e": int(EMP)}, limite=40)
        md_tabela(rel, cols, linhas, 40)
    seguro(rel, "OS por tipo (garantia x interna x cliente)", _os_tipo)

    def _veic():
        cols, linhas = q(cur, f"""
            SELECT NOVO_USADO, COUNT(*) AS QTD,
                   SUM(CASE WHEN RESERVADO='S' THEN 1 ELSE 0 END) AS RESERVADOS
              FROM {OWNER}.VEICULOS
             WHERE COD_EMPRESA = :e
             GROUP BY NOVO_USADO ORDER BY 2 DESC
        """, {"e": int(EMP)}, limite=20)
        md_tabela(rel, cols, linhas, 20)
    seguro(rel, "VEICULOS.NOVO_USADO — valores reais", _veic)

    def _divisoes():
        cols, linhas = q(cur, f"""
            SELECT COD_EMPRESA_DIVISAO, DESCRICAO, PRODUTIVO, VEICULOS
              FROM {OWNER}.EMPRESAS_DIVISOES
             WHERE COD_EMPRESA = :e ORDER BY 1
        """, {"e": int(EMP)}, limite=60)
        md_tabela(rel, cols, linhas, 60)
    seguro(rel, "Divisões da empresa (separa departamento)", _divisoes)

    # ---------------------------------------------------------------
    W("\n## 6. Peça x serviço dentro da OS\n")

    def _peca_serv():
        cols, linhas = q(cur, f"""
            SELECT 'SERVICOS' AS ORIGEM, COUNT(*) AS LINHAS,
                   COUNT(DISTINCT NUMERO_OS) AS OS_DISTINTAS
              FROM {OWNER}.OS_SERVICOS WHERE COD_EMPRESA = :e
             UNION ALL
            SELECT 'REQUISICOES', COUNT(*), COUNT(DISTINCT NUMERO_OS)
              FROM {OWNER}.OS_REQUISICOES WHERE COD_EMPRESA = :e
        """, {"e": int(EMP)}, limite=10)
        md_tabela(rel, cols, linhas, 10)
    seguro(rel, "Volume das duas pernas", _peca_serv)

    # ---------------------------------------------------------------
    W("\n## 7. Estoque de peças\n")

    def _est():
        cols, linhas = q(cur, """
            SELECT table_name, column_name, data_type
              FROM all_tab_columns
             WHERE owner=:o AND table_name IN ('ESTOQUE','ITENS','ITENS_CUSTOS')
             ORDER BY table_name, column_id
        """, {"o": OWNER}, limite=200)
        md_tabela(rel, cols, linhas, 200)
    seguro(rel, "Colunas de ESTOQUE / ITENS / ITENS_CUSTOS", _est)

    rel.close()
    cur.close()
    c.close()
    print(f"OK -> {SAIDA}/RELATORIO.md")


if __name__ == "__main__":
    main()
