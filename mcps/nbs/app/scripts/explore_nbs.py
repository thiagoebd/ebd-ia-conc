#!/usr/bin/env python3
"""explore_nbs.py — discover completo do schema NBS (Oracle).

Espelha o papel do explore_winthor.py do EBD.ia, mas generico: o modelo do NBS
e desconhecido, entao em vez de ir direto nas tabelas que interessam, extrai o
DICIONARIO INTEIRO e deixa a analise para depois.

Roda DENTRO do container do MCP (tem oracledb e as credenciais no ambiente):

    docker cp explore_nbs.py conc_mcp_nbs:/tmp/
    docker exec conc_mcp_nbs python /tmp/explore_nbs.py
    docker cp conc_mcp_nbs:/tmp/nbs_discovery ./discovery

Gera em /tmp/nbs_discovery:
    00_resumo.md          panorama: contagens, prefixos, maiores tabelas
    tabelas.jsonl         uma linha por tabela (nome, num_rows, comentario)
    colunas.jsonl         uma linha por coluna (tipo, nullable, default, comentario)
    chaves.jsonl          PK, UK e FK (com tabela/coluna referenciada)
    indices.jsonl         indices e suas colunas
    views.jsonl           views do schema (nome + texto)
    grafo_fk.md           tabelas ordenadas por quantas FKs apontam para elas
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import oracledb

OWNER = os.getenv("NBS_OWNER", "NBS")
SAIDA = Path(os.getenv("NBS_DISCOVERY_DIR", "/tmp/nbs_discovery"))


def conectar() -> oracledb.Connection:
    return oracledb.connect(
        user=os.environ["NBS_USER"],
        password=os.environ["NBS_PASSWORD"],
        dsn=os.environ["NBS_DSN"],
    )


def dump(cur, sql: str, params: dict, arquivo: str) -> int:
    """Executa e grava uma linha JSON por registro. Retorna a contagem."""
    cur.execute(sql, params)
    cols = [d[0].lower() for d in cur.description]
    n = 0
    destino = SAIDA / arquivo
    with destino.open("w", encoding="utf-8") as fh:
        while True:
            lote = cur.fetchmany(5000)
            if not lote:
                break
            for linha in lote:
                reg = {}
                for c, v in zip(cols, linha):
                    if isinstance(v, oracledb.LOB):
                        v = v.read()
                    elif isinstance(v, datetime):
                        v = v.isoformat()
                    reg[c] = v
                fh.write(json.dumps(reg, ensure_ascii=False, default=str) + "\n")
                n += 1
    print(f"  {arquivo}: {n} linhas")
    return n


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    con = conectar()
    cur = con.cursor()
    p = {"owner": OWNER}
    print(f"Discover do schema {OWNER} -> {SAIDA}")

    n_tab = dump(cur, """
        SELECT t.table_name, t.num_rows, t.last_analyzed, t.partitioned,
               t.temporary, c.comments
          FROM all_tables t
          LEFT JOIN all_tab_comments c
                 ON c.owner = t.owner AND c.table_name = t.table_name
         WHERE t.owner = :owner
         ORDER BY t.table_name
    """, p, "tabelas.jsonl")

    n_col = dump(cur, """
        SELECT c.table_name, c.column_id, c.column_name, c.data_type,
               c.data_length, c.data_precision, c.data_scale, c.nullable,
               c.data_default, m.comments
          FROM all_tab_columns c
          LEFT JOIN all_col_comments m
                 ON m.owner = c.owner
                AND m.table_name = c.table_name
                AND m.column_name = c.column_name
         WHERE c.owner = :owner
         ORDER BY c.table_name, c.column_id
    """, p, "colunas.jsonl")

    n_key = dump(cur, """
        SELECT ac.constraint_name, ac.constraint_type, ac.table_name,
               acc.column_name, acc.position,
               ac.r_constraint_name, ac.delete_rule, ac.status,
               rc.table_name  AS ref_table,
               rcc.column_name AS ref_column
          FROM all_constraints ac
          JOIN all_cons_columns acc
            ON acc.owner = ac.owner AND acc.constraint_name = ac.constraint_name
          LEFT JOIN all_constraints rc
            ON rc.owner = ac.r_owner AND rc.constraint_name = ac.r_constraint_name
          LEFT JOIN all_cons_columns rcc
            ON rcc.owner = rc.owner
           AND rcc.constraint_name = rc.constraint_name
           AND rcc.position = acc.position
         WHERE ac.owner = :owner
           AND ac.constraint_type IN ('P','U','R')
         ORDER BY ac.table_name, ac.constraint_type, ac.constraint_name, acc.position
    """, p, "chaves.jsonl")

    dump(cur, """
        SELECT i.index_name, i.table_name, i.uniqueness, i.index_type,
               ic.column_name, ic.column_position
          FROM all_indexes i
          JOIN all_ind_columns ic
            ON ic.index_owner = i.owner AND ic.index_name = i.index_name
         WHERE i.owner = :owner
         ORDER BY i.table_name, i.index_name, ic.column_position
    """, p, "indices.jsonl")

    dump(cur, """
        SELECT view_name, text_length, text
          FROM all_views
         WHERE owner = :owner
         ORDER BY view_name
    """, p, "views.jsonl")

    # ---------- analise ----------
    tabelas = [json.loads(l) for l in (SAIDA / "tabelas.jsonl").read_text(encoding="utf-8").splitlines()]
    chaves = [json.loads(l) for l in (SAIDA / "chaves.jsonl").read_text(encoding="utf-8").splitlines()]

    prefixos = Counter(t["table_name"][:4] for t in tabelas)
    com_stats = [t for t in tabelas if t.get("num_rows")]
    maiores = sorted(com_stats, key=lambda t: t["num_rows"], reverse=True)[:60]
    com_coment = sum(1 for t in tabelas if t.get("comments"))

    # quantas FKs apontam para cada tabela = centralidade no modelo
    entrada = Counter()
    for k in chaves:
        if k["constraint_type"] == "R" and k.get("ref_table"):
            entrada[k["ref_table"]] += 1

    with (SAIDA / "00_resumo.md").open("w", encoding="utf-8") as fh:
        fh.write(f"# Discover NBS — schema {OWNER}\n\n")
        fh.write(f"Gerado em {datetime.now():%d/%m/%Y %H:%M}\n\n")
        fh.write(f"- Tabelas: **{n_tab}** (com estatistica: {len(com_stats)}, "
                 f"com comentario: {com_coment})\n")
        fh.write(f"- Colunas: **{n_col}**\n")
        fh.write(f"- Registros de chave (PK/UK/FK): **{n_key}**\n")
        fh.write(f"- Tabelas referenciadas por FK: **{len(entrada)}**\n\n")

        fh.write("## Prefixos de nome (4 letras, >=20 tabelas)\n\n| prefixo | tabelas |\n|---|---|\n")
        for pref, qtd in prefixos.most_common():
            if qtd >= 20:
                fh.write(f"| {pref} | {qtd} |\n")

        fh.write("\n## 60 maiores por num_rows\n\n| tabela | num_rows | comentario |\n|---|---|---|\n")
        for t in maiores:
            fh.write(f"| {t['table_name']} | {t['num_rows']} | {(t.get('comments') or '')[:60]} |\n")

        fh.write("\n## 60 mais referenciadas por FK (nucleo do modelo)\n\n| tabela | FKs apontando |\n|---|---|\n")
        for tab, qtd in entrada.most_common(60):
            fh.write(f"| {tab} | {qtd} |\n")

    with (SAIDA / "grafo_fk.md").open("w", encoding="utf-8") as fh:
        fh.write(f"# Grafo de FKs — schema {OWNER}\n\n")
        origem = defaultdict(set)
        for k in chaves:
            if k["constraint_type"] == "R" and k.get("ref_table"):
                origem[k["ref_table"]].add(k["table_name"])
        for tab, qtd in entrada.most_common():
            filhas = sorted(origem[tab])
            fh.write(f"\n## {tab} ({qtd} FKs, {len(filhas)} tabelas filhas)\n\n")
            fh.write(", ".join(filhas[:40]))
            if len(filhas) > 40:
                fh.write(f" ... (+{len(filhas)-40})")
            fh.write("\n")

    cur.close()
    con.close()
    print(f"\nOK. Veja {SAIDA}/00_resumo.md")


if __name__ == "__main__":
    try:
        main()
    except oracledb.DatabaseError as e:
        print("ERRO Oracle:", e, file=sys.stderr)
        sys.exit(1)
