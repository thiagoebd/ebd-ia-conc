#!/usr/bin/env python3
"""explore_dealernet.py — discover completo do DealerNet Workflow (SQL Server).

Equivalente ao explore_nbs.py, adaptado ao T-SQL e ao modelo do DealerNet.
Extrai o dicionario inteiro + responde as perguntas de arquitetura:
escopo de empresa, entidades nucleo, familias de tabela, volumetria real.

CUIDADO: esta base tem tabela com 800 MILHOES de linhas. Todas as consultas
aqui sao de METADADO (sys.*, INFORMATION_SCHEMA) ou usam contagem de particao
(sys.partitions), que nao varre dado. Nenhuma faz SELECT em tabela de negocio.

Uso (container descartavel, nada instalado no host):

    docker run --rm -i -v "$PWD":/w -w /w \
      -e DN_HOST -e DN_USER -e DN_PASS -e DN_BASE \
      python:3.12-slim bash -lc \
      "pip install -q pymssql 2>/dev/null; python explore_dealernet.py"

    docker cp ... ou simplesmente: os arquivos saem em ./dealernet_discovery/
"""
from __future__ import annotations

import json
import os
from collections import Counter, defaultdict
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import pymssql

HOST = os.getenv("DN_HOST", "clussp06wfw.grupoebd.ebdbr.com.br")
PORTA = int(os.getenv("DN_PORT", "1433"))
USER = os.getenv("DN_USER", "EBD_CONSULTA")
SENHA = os.getenv("DN_PASS", "")
BASE = os.getenv("DN_BASE", "GrupoEBD_DealernetWF")
SAIDA = Path(os.getenv("DN_OUT", "dealernet_discovery"))

# Prefixos/sufixos que sao RUIDO para pergunta de gestao
RUIDO_PREFIXO = ("WF", "Std", "Monitor", "Audit", "Log", "Temp", "TMP", "Bkp", "BKP")
RUIDO_SUFIXO = ("Historico", "_BKP", "_old", "_Copia", "Bkp", "Log")


def _norm(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (bytes, bytearray)):
        return "<bin>"
    return v


def conectar():
    if not SENHA:
        raise SystemExit("Defina DN_PASS no ambiente.")
    return pymssql.connect(server=HOST, port=PORTA, user=USER,
                           password=SENHA, database=BASE, login_timeout=10)


def dump(cur, sql, arquivo):
    """Executa e grava JSONL. Retorna (colunas, linhas)."""
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    linhas = cur.fetchall()
    with (SAIDA / arquivo).open("w", encoding="utf-8") as fh:
        for l in linhas:
            fh.write(json.dumps({c: _norm(v) for c, v in zip(cols, l)},
                                ensure_ascii=False, default=str) + "\n")
    print(f"  {arquivo}: {len(linhas)} linhas")
    return cols, linhas


def md(fh, cols, linhas, limite=50):
    if not linhas:
        fh.write("_(vazio)_\n\n")
        return
    fh.write("| " + " | ".join(str(c) for c in cols) + " |\n")
    fh.write("|" + "|".join(["---"] * len(cols)) + "|\n")
    for r in linhas[:limite]:
        fh.write("| " + " | ".join(str(_norm(x))[:55] for x in r) + " |\n")
    if len(linhas) > limite:
        fh.write(f"\n_... +{len(linhas)-limite} linhas_\n")
    fh.write("\n")


def familia(nome: str) -> str:
    """Agrupa tabelas por raiz: NotaFiscalItemTributo -> NotaFiscal."""
    import re
    m = re.match(r"^([A-Z][a-z]+(?:[A-Z][a-z]+)?)", nome)
    return m.group(1) if m else nome[:12]


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    c = conectar()
    cur = c.cursor()
    rel = (SAIDA / "RELATORIO.md").open("w", encoding="utf-8")
    W = rel.write

    W(f"# Discover DealerNet Workflow — {BASE}\n\n")
    W(f"Servidor `{HOST}:{PORTA}` · gerado em {datetime.now():%d/%m/%Y %H:%M}\n\n")
    W("> DealerNet Workflow: DMS do ecossistema automotivo, homologado por VW, GM "
      "e outras montadoras. Cobre veiculos, pecas, oficina, CRM, financeiro e "
      "contabil numa base unica.\n\n---\n")

    # =============================================================
    print("[1/8] dicionario de tabelas e colunas")
    W("\n## 1. Panorama\n\n")

    cols, tabs = dump(cur, """
        SELECT s.name AS SCHEMA_NAME, t.name AS TABELA, p.rows AS LINHAS,
               t.create_date, t.modify_date
          FROM sys.tables t
          JOIN sys.schemas s ON s.schema_id = t.schema_id
          JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
         ORDER BY p.rows DESC
    """, "tabelas.jsonl")

    dump(cur, """
        SELECT c.TABLE_NAME, c.ORDINAL_POSITION, c.COLUMN_NAME, c.DATA_TYPE,
               c.CHARACTER_MAXIMUM_LENGTH, c.NUMERIC_PRECISION, c.NUMERIC_SCALE,
               c.IS_NULLABLE, c.COLUMN_DEFAULT
          FROM INFORMATION_SCHEMA.COLUMNS c
         ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION
    """, "colunas.jsonl")

    dump(cur, """
        SELECT fk.name AS FK, OBJECT_NAME(fk.parent_object_id) AS TABELA,
               COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS COLUNA,
               OBJECT_NAME(fk.referenced_object_id) AS REF_TABELA,
               COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS REF_COLUNA,
               fkc.constraint_column_id AS POSICAO
          FROM sys.foreign_keys fk
          JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
         ORDER BY TABELA, FK, POSICAO
    """, "fks.jsonl")

    dump(cur, """
        SELECT OBJECT_NAME(i.object_id) AS TABELA, i.name AS PK,
               COL_NAME(ic.object_id, ic.column_id) AS COLUNA, ic.key_ordinal AS POSICAO
          FROM sys.indexes i
          JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
         WHERE i.is_primary_key = 1
         ORDER BY TABELA, ic.key_ordinal
    """, "pks.jsonl")

    dump(cur, """
        SELECT name AS VIEW_NAME, OBJECT_DEFINITION(object_id) AS TEXTO
          FROM sys.views ORDER BY name
    """, "views.jsonl")

    # =============================================================
    print("[2/8] escopo de empresa")
    W("\n## 2. Escopo — a pergunta que define a arquitetura\n\n")
    W("O NBS é multi-empresa por coluna (`COD_EMPRESA` na PK). "
      "Aqui a pergunta é a mesma: escopo de conexão ou de coluna?\n")

    def bloco(titulo, sql, limite=40):
        W(f"\n### {titulo}\n\n")
        try:
            cur.execute(sql)
            cs = [d[0] for d in cur.description]
            md(rel, cs, cur.fetchall(), limite)
        except Exception as e:
            W(f"⚠️ `{str(e)[:160]}`\n\n")

    bloco("Empresas cadastradas", """
        SELECT TOP 60 * FROM Empresa
    """, 60)

    bloco("Onde `Empresa_Codigo` aparece (top 60 tabelas por volume)", """
        SELECT TOP 60 c.TABLE_NAME, p.rows AS LINHAS
          FROM INFORMATION_SCHEMA.COLUMNS c
          JOIN sys.tables t ON t.name = c.TABLE_NAME
          JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
         WHERE c.COLUMN_NAME = 'Empresa_Codigo'
         ORDER BY p.rows DESC
    """, 60)

    bloco("Colunas candidatas a escopo", """
        SELECT TOP 40 COLUMN_NAME, COUNT(*) AS TABELAS
          FROM INFORMATION_SCHEMA.COLUMNS
         WHERE COLUMN_NAME LIKE '%Empresa%' OR COLUMN_NAME LIKE '%Filial%'
            OR COLUMN_NAME LIKE '%concession%' OR COLUMN_NAME LIKE '%Loja%'
            OR COLUMN_NAME LIKE '%Marca%'
         GROUP BY COLUMN_NAME ORDER BY 2 DESC
    """)

    bloco("Marcas / bandeiras", "SELECT TOP 40 * FROM Marca")
    bloco("Empresa x Marca", "SELECT TOP 60 * FROM EmpresaMarca")
    bloco("Departamentos", "SELECT TOP 40 * FROM Departamento")

    # =============================================================
    print("[3/8] nucleo do modelo")
    W("\n## 3. Núcleo do modelo (centralidade por FK)\n\n")
    W("No NBS, `EMPRESAS` com 492 FKs revelou o escopo. Mesmo método aqui.\n")

    bloco("Top 50 tabelas mais referenciadas", """
        SELECT TOP 50 OBJECT_NAME(fk.referenced_object_id) AS TABELA,
               COUNT(*) AS FKS_APONTANDO,
               MAX(p.rows) AS LINHAS
          FROM sys.foreign_keys fk
          JOIN sys.partitions p ON p.object_id = fk.referenced_object_id
                               AND p.index_id IN (0,1)
         GROUP BY fk.referenced_object_id
         ORDER BY COUNT(*) DESC
    """, 50)

    # =============================================================
    print("[4/8] familias de tabela")
    W("\n## 4. Famílias de tabela\n\n")
    fam_qtd = Counter()
    fam_linhas = Counter()
    for r in tabs:
        nome, linhas = r[1], r[2] or 0
        f = familia(nome)
        fam_qtd[f] += 1
        fam_linhas[f] += linhas
    W("| família | tabelas | linhas somadas |\n|---|---|---|\n")
    for f, q in fam_qtd.most_common(45):
        W(f"| {f} | {q} | {fam_linhas[f]:,} |\n")

    # =============================================================
    print("[5/8] ruido vs negocio")
    W("\n## 5. Ruído vs. negócio\n\n")
    ruido, negocio = [], []
    for r in tabs:
        nome, linhas = r[1], r[2] or 0
        eh_ruido = (nome.startswith(RUIDO_PREFIXO) or nome.endswith(RUIDO_SUFIXO))
        (ruido if eh_ruido else negocio).append((nome, linhas))
    W(f"- Tabelas de **ruído** (WF*, *Historico, Monitor*, Audit*, Log*, Std*, "
      f"backup): **{len(ruido)}** somando {sum(l for _, l in ruido):,} linhas\n")
    W(f"- Tabelas de **negócio**: **{len(negocio)}** somando "
      f"{sum(l for _, l in negocio):,} linhas\n\n")
    W("### 40 maiores tabelas de NEGÓCIO\n\n| tabela | linhas |\n|---|---|\n")
    for nome, l in sorted(negocio, key=lambda x: -x[1])[:40]:
        W(f"| {nome} | {l:,} |\n")

    # =============================================================
    print("[6/8] entidades de interesse")
    W("\n## 6. Entidades que interessam ao agente\n\n")
    ALVOS = ["Empresa", "Pessoa", "Veiculo", "ModeloVeiculo", "FamiliaVeiculo",
             "Produto", "ProdutoEstoque", "NotaFiscal", "NotaFiscalItem",
             "OS", "OSItem", "OficinaServico", "OficinaProduto", "TMO",
             "Titulo", "TituloMov", "Lancamento", "ContaGerencial",
             "MovimentoEstoque", "NaturezaOperacao", "Usuario", "Marca",
             "Departamento", "Estoque", "Campanha", "Atendimento", "Proposta"]
    for t in ALVOS:
        W(f"\n### {t}\n\n")
        try:
            cur.execute("""
                SELECT c.COLUMN_NAME, c.DATA_TYPE, c.IS_NULLABLE
                  FROM INFORMATION_SCHEMA.COLUMNS c
                 WHERE c.TABLE_NAME = %s ORDER BY c.ORDINAL_POSITION
            """, (t,))
            linhas = cur.fetchall()
            if not linhas:
                W("_(tabela não existe com esse nome)_\n\n")
                continue
            cur.execute("""SELECT p.rows FROM sys.tables t
                           JOIN sys.partitions p ON p.object_id=t.object_id
                            AND p.index_id IN (0,1) WHERE t.name=%s""", (t,))
            n = cur.fetchone()
            W(f"**{n[0]:,} linhas** · {len(linhas)} colunas\n\n")
            md(rel, ["COLUNA", "TIPO", "NULL"], linhas, 120)
        except Exception as e:
            W(f"⚠️ `{str(e)[:140]}`\n\n")

    # =============================================================
    print("[7/8] janela de dados")
    W("\n## 7. Janela real de dados\n\n")
    W("Confirma até onde a operação está viva (no NBS, tabelas de estatística "
      "tinham dado de 2014-2020 e enganaram o agente).\n")
    for tab, col in [("NotaFiscal", "NotaFiscal_Data"), ("OS", "OS_DataAbertura"),
                     ("Titulo", "Titulo_DataEmissao"),
                     ("MovimentoEstoque", "MovimentoEstoque_Data"),
                     ("Lancamento", "Lancamento_Data")]:
        W(f"\n### {tab}.{col}\n\n")
        try:
            cur.execute(f"""
                SELECT YEAR({col}) AS ANO, COUNT(*) AS QTD
                  FROM {tab} WHERE {col} >= '2023-01-01'
                 GROUP BY YEAR({col}) ORDER BY 1 DESC
            """)
            md(rel, ["ANO", "QTD"], cur.fetchall(), 10)
        except Exception as e:
            W(f"⚠️ `{str(e)[:140]}`\n\n")

    # =============================================================
    print("[8/8] grafo de FK + resumo")
    fks = [json.loads(l) for l in (SAIDA / "fks.jsonl").read_text(encoding="utf-8").splitlines()]
    entrada = Counter()
    filhas = defaultdict(set)
    for k in fks:
        entrada[k["REF_TABELA"]] += 1
        filhas[k["REF_TABELA"]].add(k["TABELA"])
    with (SAIDA / "grafo_fk.md").open("w", encoding="utf-8") as fh:
        fh.write(f"# Grafo de FKs — {BASE}\n")
        for t, q in entrada.most_common():
            fh.write(f"\n## {t} ({q} FKs, {len(filhas[t])} tabelas filhas)\n\n")
            fh.write(", ".join(sorted(filhas[t])[:50]))
            if len(filhas[t]) > 50:
                fh.write(f" ... (+{len(filhas[t])-50})")
            fh.write("\n")

    W("\n---\n\n## Resumo\n\n")
    W(f"- Tabelas: **{len(tabs)}** · Colunas: ver `colunas.jsonl`\n")
    W(f"- FKs: **{len(fks)}** · tabelas referenciadas: **{len(entrada)}**\n")
    W(f"- Ruído: {len(ruido)} tabelas · Negócio: {len(negocio)} tabelas\n")
    W(f"- Maior tabela: **{tabs[0][1]}** com {tabs[0][2]:,} linhas\n")

    rel.close()
    cur.close()
    c.close()
    print(f"\nOK -> {SAIDA}/RELATORIO.md")


if __name__ == "__main__":
    main()
