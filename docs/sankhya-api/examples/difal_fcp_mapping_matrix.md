# Matriz de Mapeamento DIFAL/FCP (Sankhya -> SFA)

## Objetivo
Definir o contrato de dados para evoluir o motor tributario do SFA com DIFAL/FCP,
separando:
- campos operacionais imediatos (tax_rules);
- campos de metadado para reconciliacao e evolucao.

## Fontes usadas
- Help Sankhya (MCP):
  - Guia de Configuracao do DIFAL (ID 34454524325143)
  - ICMS DIFAL (Venda Interestadual - Nao contribuinte) (ID 37999785619991)
  - Nota Tecnica 2015.003 (ID 360044600414)
- Dicionario de dados local:
  - docs/sankhya-refefence/TGFICM.txt
  - docs/sankhya-refefence/TGFDIN.txt
- Query de extracao:
  - docs/sankhya-api/examples/tributacao_query_template.sql

## Contrato principal (tax_rules)
| Campo SFA | Origem Sankhya | Alias SQL | Status | Observacao |
|---|---|---|---|---|
| status | constante | STATUS | pronto | "active" por padrao |
| ncm | TGFICM + TGFNCM + TGFPRO | NCM | pronto | prioriza restricao NCM; fallback produto |
| cest | TGFPRO.CODESPECST | CEST | pronto | usado para match mais especifico |
| ufOrigem | TGFICM.UFORIG -> TSIUFS.UF | UFORIGEM | pronto | fallback ANY |
| ufDestino | TGFICM.UFDEST -> TSIUFS.UF | UFDESTINO | pronto | fallback ANY |
| stCalculationType | TGFICM.PAUTAVLRSTFIXO | TIPOST | pronto | pmc quando pauta preenchida; senao mva |
| stPriceForCalculation | nao definido no Sankhya para regra base | PRECOPARACALCULOST | pronto | nulo (opcional no SFA) |
| stBaseReductionPercent | TGFICM.REDBASEST | REDUCAOBASEICMSST | pronto | normalizado para 0 quando vazio |
| stBaseAmount | TGFICM.PAUTAVLRSTFIXO | BASECALCULOICMSST | pronto | normalizado para 0 quando vazio |
| aliquotaDestino | TGFICM.ALIQSUBTRIB/ALIQINTDEST/ALIQUOTA | ALIQUOTADESTINO | pronto | cadeia de fallback textual segura |
| aliquotaCredito | TGFICM.ALIQUOTA/ALIQINTDEST | ALIQUOTACREDITO | pronto | cadeia de fallback textual segura |
| aliquotaDifal | derivada | ALIQUOTADIFAL | pronto (placeholder) | atualmente nulo para evitar erro de conversao no executeQuery |
| cstCsosn | TGFICM.CSOSN | CST_CSOSN | pronto | opcional |
| mvaIva | TGFICM.MVAORIGINAL/MVASIMPLIFICADO | MVA | pronto | cadeia de fallback textual segura |
| fiscalException | TGFICM (campos de regra) | EXCECAOFISCAL | pronto | rastreio tecnico da regra origem |
| validFrom | TGFICM.DTINICIOVIGENCIA | VIGENCIAINICIAL | pronto | data vigencia inicial |
| validUntil | TGFICM.DTFIMVIGENCIA | VIGENCIAFINAL | pronto | data vigencia final |
| priority | TGFICM.SEQUENCIA + especificidade | PRIORIDADE | pronto | desempate consistente no SFA |

## Contrato estendido DIFAL/FCP (metadados)
| Campo SQL | Origem Sankhya | Uso no SFA |
|---|---|---|
| TIPOCALCULODIFAL | TGFICM.TIPCALCDIFAL | governanca da formula aplicada |
| PERCENTUALFCP | TGFICM.PERCICMSFCP | referencia FCP por regra |
| PERCENTUALFCPINTERNO | TGFICM.PERCICMSFCPINT | referencia FCP interno |
| FORMULAFCPDIFAL | TGFICM.FORMCALFCPDIFAL | auditoria de formula FCP no ERP |
| FORMULADIFAL | TGFICM.CODFORMCALCDIFAL | auditoria de formula DIFAL |
| FORMULABASEDIFAL | TGFICM.CODFORMBASDIFAL | auditoria da base DIFAL |
| REPASSEDIFALFCP | TGFICM.REPDIFALFCP | indica repasse no contexto nao contribuinte |
| GRUPOFISCALID | TGFICM.CODTRIB | apoio para agrupamento fiscal |
| CODTAB | TGFICM.CODTAB | rastreabilidade da tabela de aliquota |
| SEQUENCIA | TGFICM.SEQUENCIA | rastreabilidade da linha origem |
| IDALIQ | TGFICM.IDALIQ | chave tecnica da aliquota no ERP |

## Nota importante sobre ALIQUOTADIFAL
O endpoint DbExplorerSP.executeQuery no ambiente atual retornou ORA-01722 quando tentamos
forcar calculo numerico no SQL para ALIQUOTADIFAL (conversoes com TO_NUMBER em campos com
conteudo misto).

Decisao segura atual:
- manter ALIQUOTADIFAL no contrato principal (coluna existe);
- retornar nulo nesta fase de extracao;
- usar metadados DIFAL/FCP para reconciliacao;
- calcular/validar DIFAL online via endpoint oficial POST /v1/fiscal/impostos/calculo.

## Evidencia de execucao da consulta atual
- Arquivo de retorno: docs/sankhya-api/examples/sankhya_tributacao_execute_query_2026-10-21T15-22-42-552Z.json
- Status: 200
- Linhas: 2228
- Colunas: 29
- Inclui: ALIQUOTADIFAL, TIPOCALCULODIFAL, PERCENTUALFCP

## Proximo passo recomendado
1. Implementar parser de carga para ignorar colunas estendidas no importador atual e persisti-las em snapshot tecnico.
2. Criar prova de reconciliacao online no endpoint /v1/fiscal/impostos/calculo para 1 produto real.
3. Com payload real validado, decidir se ALIQUOTADIFAL continua derivado no SFA ou passa a vir do ERP por fluxo online.
