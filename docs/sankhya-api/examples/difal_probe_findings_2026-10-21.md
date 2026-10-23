# Diagnostico DIFAL - 2026-10-21

## Contexto
Validacao tecnica da hipotese de que os valores de DIFAL estariam na TGFCUSITE.

## Evidencias executadas
- Probe comparativo de tabelas:
  - docs/sankhya-api/examples/sankhya_difal_table_probe_2026-10-21T15-33-01-820Z.json
- Probe de elegibilidade e partilha por ano:
  - docs/sankhya-api/examples/sankhya_sql_file_probe_2026-10-21T15-37-59-960Z.json

## Resultado principal
1. TGFCUSITE
- Existe e possui dados (25.057 linhas no ambiente).
- Dicionario local nao apresenta campos classicos de DIFAL.
- Nao se mostrou fonte primaria para BASEDIFAL/VLRDIFALDEST/VLRDIFALREM.

2. TGFDIN
- Contem os campos corretos de DIFAL/FCP:
  - BASEDIFAL
  - VLRDIFALDEST
  - VLRDIFALREM
  - PERCPARTDIFAL
  - TIPCALCDIFAL
  - PERCFCP
  - VLRFCP
- No ambiente atual, os valores estao zerados:
  - LINHAS_BASEDIFAL = 0
  - LINHAS_VLRDIFALDEST = 0
  - LINHAS_VLRDIFALREM = 0
  - LINHAS_PERCPARTDIFAL = 0
  - LINHAS_TIPCALCDIFAL = TOTAL_LINHAS

3. Regra de partilha historica (confirmacao)
- 2016: 40% destino
- 2017: 60% destino
- 2018: 80% destino
- 2019+: 100% destino

No recorte de 24 meses do ambiente:
- Faixa encontrada: somente 2019+
- Partilha esperada: 100
- Itens com PERCPARTDIFAL informado: 0

## Conclusao tecnica
- O problema atual nao e falta de campo no banco.
- O problema atual e de aplicacao de cenario/cadastro fiscal para que o DIFAL seja calculado e gravado.
- Portanto, a observacao "talvez nao venha por cadastro incompleto" esta consistente com os dados.

## Implicacao para o SFA
- A consulta do SFA pode manter os campos de DIFAL no contrato.
- Durante rollout, os valores podem vir nulos/zero sem erro estrutural.
- A ativacao efetiva vira quando as condicoes fiscais no Sankhya estiverem completas e usadas em notas elegiveis.
