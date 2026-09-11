"""Anexos no Dealer.ia — imagem de veiculo e planilha de frota.

Porte do EBD.ia (11/09/2026). O que MUDA aqui e o dominio: a foto costuma
ser de um CARRO, e a chave pode ser PLACA ou CHASSI — formatos com regra
propria, diferentes de codigo de produto.
"""
from pathlib import Path

from conftest import PLANILHA_MATCH as _pm

RAIZ = Path(__file__).resolve().parents[1]

ENTIDADES = _pm.ENTIDADES
e_chassi, e_placa = _pm.e_chassi, _pm.e_placa
normaliza_chassi, normaliza_placa = _pm.normaliza_chassi, _pm.normaliza_placa
sql_por_placa, tipo_da_chave = _pm.sql_por_placa, _pm.tipo_da_chave


def _fonte(rel: str) -> str:
    return (RAIZ / rel).read_text(encoding="utf-8", errors="replace")


# ─── placa: os dois formatos convivem ───

def test_placa_antiga_e_mercosul():
    assert normaliza_placa("abc-1234") == "ABC1234"
    assert normaliza_placa("ABC 1D23") == "ABC1D23"


def test_o_que_nao_e_placa():
    for v in ("123", "nao e placa", "", "ABCD1234"):
        assert not e_placa(v), v


def test_chassi_tem_17_e_nao_usa_IOQ():
    assert e_chassi("9BWZZZ377VT004251")
    assert not e_chassi("9BWZZZ377VT00425I")   # tem I
    assert not e_chassi("123")


def test_agente_descobre_o_tipo_da_chave():
    """O usuario manda foto, planilha ou digita — sem dizer o que e."""
    assert tipo_da_chave("ABC1D23") == "placa"
    assert tipo_da_chave("9BWZZZ377VT004251") == "chassi"
    assert tipo_da_chave("12345") == "codigo"
    assert tipo_da_chave("Joao Silva") == "nome"


# ─── a pergunta comercial por tras da foto ───

def test_sql_da_placa_responde_as_perguntas_do_negocio():
    """'esse carro passou por aqui?' -> estoque, novo/usado, patio."""
    sql = sql_por_placa(["ABC-1234"])
    for campo in ("PLACA", "CHASSI_RESUMIDO", "NOVO_USADO", "COD_PATIO",
                  "COD_EMPRESA"):
        assert campo in sql, campo


def test_sql_da_placa_normaliza_o_que_esta_no_banco():
    """A placa no DMS pode estar com hifen."""
    sql = sql_por_placa(["ABC1234"])
    assert "REPLACE" in sql


def test_entidades_do_mundo_concessionaria():
    assert set(ENTIDADES) == {"cliente", "veiculo", "empresa", "peca",
                              "vendedor"}
    assert ENTIDADES["veiculo"]["tabela"] == "VEICULOS"
    assert ENTIDADES["empresa"]["codigo"] == "COD_EMPRESA"


# ─── integracao ───

def test_agente_registra_as_ferramentas():
    s = _fonte("core/app/agent.py")
    assert "PLANILHA_TOOLS" in s and "_run_planilha" in s


def test_agente_aceita_imagem_e_planilha():
    s = _fonte("core/app/agent.py")
    assert "monta_conteudo" in s
    assert s.count("planilha_ctx") >= 3


def test_rota_aceita_os_anexos():
    s = _fonte("gateway/app/routes/chat.py")
    for campo in ("imagens", "planilha_b64", "planilha_nome"):
        assert campo in s, campo


def test_rota_grava_antes_de_chamar_o_agente():
    s = _fonte("gateway/app/routes/chat.py")
    assert s.index("_grava_pl") < s.index("planilha_ctx=_pl_ctx")


def test_tabela_planilhas_cascateia_com_a_conversa():
    s = _fonte("gateway/app/db.py")
    i = s.index("CREATE TABLE IF NOT EXISTS planilhas")
    assert "REFERENCES conversations(id) ON DELETE CASCADE" in s[i:i + 700]


def test_front_envia_e_mostra_os_anexos():
    s = _fonte("frontend/src/App.tsx")
    assert "planilha_b64: pl ? pl.b64" in s
    assert "msg-anexo" in s
    assert "onPaste" in s


def test_claude_md_tem_a_regra_de_foto_de_veiculo():
    """Foto de carro esconde pergunta comercial: estoque, novo/usado, O.S."""
    s = _fonte("docs/CLAUDE.md")
    assert "PLACA" in s and "NOVO_USADO" in s
    assert "nunca afirme" in s.lower() or "NUNCA afirme" in s


def test_send_limpa_os_anexos_depois_de_capturar():
    """A limpeza caiu no openThread na primeira versao: a miniatura ficava
    presa no composer e dava a impressao de que nada foi enviado."""
    s = _fonte("frontend/src/App.tsx")
    i = s.index("async function send(")
    bloco = s[i:i + 700]
    assert "setAnexos([])" in bloco, "o send nao limpa os anexos"
    assert bloco.index("const imgs = anexos") < bloco.index("setAnexos([])"), \
        "tem que capturar em imgs ANTES de limpar o estado"


def test_projeto_roda_so_no_deepseek():
    """O fallback do _client_for era settings.claude_model: qualquer chamada
    sem modelo explicito ia para o Claude e voltava 401 invalid x-api-key.
    Nao ha chave Claude nesta conta."""
    s = _fonte("core/app/agent.py")
    i = s.index("def _client_for")
    bloco = s[i:i + 900]
    assert "settings.deepseek_model" in bloco
    # so pode citar claude_model no comentario que explica o bug
    for linha in bloco.splitlines():
        if "settings.claude_model" in linha:
            assert "O fallback era" in linha, f"uso ativo: {linha.strip()}"


def test_prompt_nao_anuncia_claude():
    s = _fonte("core/app/system_prompt.py")
    assert "settings.claude_model" not in s
