"""Resolver NOME, PLACA ou CHASSI para registro no DMS — com o usuário no circuito.

Porte do modulo do EBD.ia, com as entidades do mundo de concessionaria.

O QUE MUDA EM RELACAO AO MERCEARIL

    cliente, vendedor      iguais em natureza (nome por extenso)
    veiculo                NOVO: chave pode ser PLACA, CHASSI ou MODELO
    empresa                equivale a filial
    produto/peca           equivale a produto

A PLACA E UM CASO PROPRIO

Ela vem de tres formas na pratica — foto do carro (o modelo le da imagem),
planilha de frota, ou digitada. E tem dois formatos convivendo:

    ABC1234    (antigo)
    ABC1D23    (Mercosul)

Normalizar e so tirar hifen, espaco e deixar maiusculo — mas NAO da para
converter um formato no outro, entao a busca tenta os dois.

O CHASSI tem 17 caracteres (VIN). No NBS, `CHASSI_RESUMIDO` e a chave de
trabalho e `CHASSI_COMPLETO` e o VIN inteiro — quem manda uma foto da
plaqueta costuma ter o completo; quem tira do sistema tem o resumido.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from app.planilhas import normaliza_texto, tokens

# NBS = Oracle (BMW). DealerNet = MSSQL. O de-para de tabela muda por DMS,
# por isso cada entidade declara em qual ela vive.
ENTIDADES: dict[str, dict] = {
    "cliente": {
        "dms": "nbs",
        "tabela": "CLIENTES",
        "codigo": "COD_CLIENTE",
        "nome": "NOME",
        "busca": ["NOME", "NOME_FANTASIA"],
        "extra": "COD_CLIENTE, SUBSTR(NOME,1,60) AS NOME, CPF_CNPJ AS DOC",
    },
    "veiculo": {
        "dms": "nbs",
        "tabela": "VEICULOS",
        "codigo": "CHASSI_RESUMIDO",
        "nome": "MODELO",
        "busca": ["MODELO", "DESCRICAO"],
        "extra": ("CHASSI_RESUMIDO, CHASSI_COMPLETO, PLACA, "
                  "SUBSTR(MODELO,1,50) AS NOME, NOVO_USADO, COD_PATIO, "
                  "ANO_FABRICACAO, ANO_MODELO"),
        "regra": ("chave pode ser PLACA, CHASSI_RESUMIDO ou CHASSI_COMPLETO; "
                  "NOVO_USADO separa novo de seminovo"),
    },
    "empresa": {
        "dms": "nbs",
        "tabela": "EMPRESAS",
        "codigo": "COD_EMPRESA",
        "nome": "NOME",
        "busca": ["NOME", "RAZAO_SOCIAL"],
        "extra": "COD_EMPRESA, SUBSTR(NOME,1,40) AS NOME",
        "regra": "empresa e a unidade de escopo (equivale a filial no EBD)",
    },
    "peca": {
        "dms": "nbs",
        "tabela": "PRODUTOS",
        "codigo": "COD_PRODUTO",
        "nome": "DESCRICAO",
        "busca": ["DESCRICAO", "REFERENCIA"],
        "extra": "COD_PRODUTO, SUBSTR(DESCRICAO,1,60) AS NOME, REFERENCIA",
    },
    "vendedor": {
        "dms": "nbs",
        "tabela": "VENDEDORES",
        "codigo": "COD_VENDEDOR",
        "nome": "NOME",
        "busca": ["NOME"],
        "extra": "COD_VENDEDOR, SUBSTR(NOME,1,50) AS NOME, COD_EMPRESA",
    },
}

# ─── placa e chassi: chaves com formato proprio ────────────────────────

PLACA_ANTIGA = re.compile(r"^[A-Z]{3}\d{4}$")
PLACA_MERCOSUL = re.compile(r"^[A-Z]{3}\d[A-Z]\d{2}$")


def normaliza_placa(v: str) -> str:
    """'abc-1234' e 'ABC 1D23' viram 'ABC1234' e 'ABC1D23'."""
    t = re.sub(r"[^A-Z0-9]", "", normaliza_texto(v))
    return t if (PLACA_ANTIGA.match(t) or PLACA_MERCOSUL.match(t)) else ""


def e_placa(v: str) -> bool:
    return bool(normaliza_placa(v))


def normaliza_chassi(v: str) -> str:
    """VIN tem 17 caracteres; o resumido do NBS costuma ter menos."""
    t = re.sub(r"[^A-Z0-9]", "", normaliza_texto(v))
    return t if 8 <= len(t) <= 17 else ""


def e_chassi(v: str) -> bool:
    t = normaliza_chassi(v)
    # VIN nao usa I, O nem Q — ajuda a nao confundir com codigo qualquer
    return len(t) == 17 and not set("IOQ") & set(t)


def tipo_da_chave(v: str) -> str:
    """Descobre sozinho o que o usuario mandou."""
    if e_placa(v):
        return "placa"
    if e_chassi(v):
        return "chassi"
    if re.fullmatch(r"\d+", re.sub(r"\D", "", str(v) or "")):
        return "codigo"
    return "nome"


def sql_por_placa(placas: list[str], max_cand: int = 3) -> str:
    """Busca veiculo por placa. Tenta a placa exata e o chassi resumido.

    Devolve TUDO que interessa a pergunta comercial: se o carro esta em
    estoque, se e novo ou usado, em que patio, e quando passou pela loja.
    """
    limpas = [p for p in (normaliza_placa(x) for x in placas) if p]
    if not limpas:
        return ""
    lista = ",".join("'" + p + "'" for p in limpas[:900])
    return f"""
SELECT v.PLACA               AS BUSCADO,
       v.CHASSI_RESUMIDO,
       SUBSTR(v.MODELO,1,50) AS NOME,
       v.NOVO_USADO,
       v.COD_PATIO,
       v.ANO_FABRICACAO,
       v.ANO_MODELO,
       v.COD_EMPRESA
FROM VEICULOS v
WHERE REPLACE(REPLACE(UPPER(v.PLACA),'-',''),' ','') IN ({lista})
""".strip()


@dataclass
class Resolucao:
    resolvido: dict[str, dict] = field(default_factory=dict)
    ambiguo: dict[str, list] = field(default_factory=dict)
    nao_achado: list[str] = field(default_factory=list)

    def resumo(self) -> dict:
        return {
            "resolvidos": len(self.resolvido),
            "ambiguos": len(self.ambiguo),
            "nao_achados": len(self.nao_achado),
            "para_decidir": [
                {"buscado": nome,
                 "candidatos": [
                     {"codigo": c.get(list(c.keys())[0]),
                      "nome": c.get("NOME", "")} for c in cands[:5]
                 ]}
                for nome, cands in list(self.ambiguo.items())[:10]
            ],
            "nao_achados_exemplos": self.nao_achado[:10],
        }


def sql_por_nome(entidade: str, nomes: list[str], max_cand: int = 6) -> str:
    """Candidatos por TOKENS: 'joao silva' casa com 'JOAO PEDRO SILVA'."""
    e = ENTIDADES.get(entidade)
    if not e:
        raise ValueError(f"entidade desconhecida: {entidade}")

    blocos = []
    for nome in nomes[:200]:
        toks = tokens(nome)
        if not toks:
            continue
        condicoes = []
        for campo in e["busca"]:
            partes = [
                f"UPPER(TRANSLATE({campo}, "
                f"'ÁÀÃÂÉÊÍÓÔÕÚÜÇáàãâéêíóôõúüç', "
                f"'AAAAEEIOOOUUCaaaaeeiooouuc')) LIKE '%{t}%'"
                for t in toks
            ]
            condicoes.append("(" + " AND ".join(partes) + ")")
        onde = "(" + " OR ".join(condicoes) + ")"
        if e.get("filtro"):
            onde += f" AND ({e['filtro']})"
        blocos.append(
            f"SELECT '{nome.replace(chr(39), chr(39) * 2)}' AS BUSCADO, "
            f"{e['extra']} FROM {e['tabela']} WHERE {onde} "
            f"AND ROWNUM <= {max_cand}"
        )
    return "\nUNION ALL\n".join(blocos) if blocos else ""


def classifica(nomes: list[str], linhas: list[dict]) -> Resolucao:
    """Um candidato resolve; varios vao ao usuario; nenhum e nao achado."""
    por_nome: dict[str, list] = {}
    for l in linhas:
        buscado = str(l.get("BUSCADO", ""))
        por_nome.setdefault(buscado, []).append(
            {k: v for k, v in l.items() if k != "BUSCADO"})

    r = Resolucao()
    for nome in nomes:
        cands = por_nome.get(nome, [])
        if not cands:
            r.nao_achado.append(nome)
        elif len(cands) == 1:
            r.resolvido[nome] = cands[0]
        else:
            alvo = normaliza_texto(nome)
            exatos = [c for c in cands
                      if normaliza_texto(c.get("NOME", "")) == alvo]
            if len(exatos) == 1:
                r.resolvido[nome] = exatos[0]
            else:
                r.ambiguo[nome] = cands
    return r


def texto_para_o_usuario(entidade: str, r: Resolucao) -> str:
    e = ENTIDADES.get(entidade, {})
    total = len(r.resolvido) + len(r.ambiguo) + len(r.nao_achado)
    linhas = [f"{len(r.resolvido)} de {total} {entidade}(s) resolvidos."]
    if e.get("regra"):
        linhas.append(f"Regra: {e['regra']}.")
    if r.ambiguo:
        linhas.append(f"\n{len(r.ambiguo)} com mais de um candidato — "
                      f"preciso que voce escolha:")
        for nome, cands in list(r.ambiguo.items())[:10]:
            opcoes = " · ".join(f"{list(c.values())[0]} {c.get('NOME','')[:34]}"
                                for c in cands[:4])
            linhas.append(f'  "{nome}" -> {opcoes}')
        if len(r.ambiguo) > 10:
            linhas.append(f"  ... e mais {len(r.ambiguo) - 10}")
    if r.nao_achado:
        linhas.append(f"\n{len(r.nao_achado)} sem candidato: "
                      + ", ".join(f'"{n}"' for n in r.nao_achado[:8]))
    return "\n".join(linhas)
