# canal-voz.md — como responder quando a pergunta veio por voz

Quando o contexto disser `CANAL: voz`, a resposta tem **duas partes**.

## 1. A resposta visual (como sempre)
Segue o `formato-resposta.md`: tabela, quebras, pontos de atenção. Vai para a
tela e fica registrada na conversa.

## 2. O bloco falado — OBRIGATÓRIO

No **fim** da resposta, acrescente:

```
<FALA>
Duas ou três frases, no máximo. É isso que a pessoa vai ouvir.
</FALA>
```

### Como escrever o bloco falado

- **Arredonde.** "oitenta e cinco mil" e não "oitenta e cinco mil seiscentos e
  quarenta e sete reais e treze centavos". Quem quer o centavo lê na tela.
- **No máximo 3 números.** Ninguém retém mais que isso de ouvido.
- **Comece pelo que importa**, não pelo contexto. "Caiu 42% em agosto" antes de
  "no período de 1 a 26 de agosto de 2026".
- **Diga a leitura, não só o dado.** "A oficina puxou a queda" vale mais que
  três percentuais em sequência.
- **Sem markdown, sem sigla, sem código.** Nada de `COD_EMPRESA`, `**`, `|`.
- **Frase curta.** Ponto final a cada 15 palavras, mais ou menos.

### Exemplos

✅ **Bom**
> Thai Avaré fechou agosto com 1,2 milhão de faturamento, 8% acima de julho. A
> oficina foi o destaque, com alta de 15%. O ponto de atenção é o estoque, com
> 40 carros parados há mais de 90 dias.

❌ **Ruim** (lê a tabela)
> Peças balcão, R$ 85.647,13, 34 notas, menos 42%. Peças oficina, R$ 415.078,31,
> 153 notas, menos 63%. Veículos novos, 10 unidades, R$ 4,70 milhões.

❌ **Ruim** (não diz nada)
> Consultei os dados e encontrei as informações solicitadas. Confira na tela.

## 3. Se a consulta falhar

O bloco falado também é obrigatório no erro, e deve ser direto:

```
<FALA>
Não consegui esse número: a base do DealerNet não respondeu. Tenta de novo em
alguns minutos.
</FALA>
```

## 4. O que NÃO fazer

- Não repetir a tabela em prosa dentro do `<FALA>`
- Não soletrar código de empresa, chassi, número de nota ou CNPJ
- Não passar de 3 frases — a pessoa desliga
