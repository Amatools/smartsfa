# Estrategia Fiscal Offline - SmartSFA x Sankhya

## Objetivo
Calcular impostos por item no pedido mesmo offline, mantendo compatibilidade com o ERP.

## Diretriz
- Fonte primaria de execucao no app: motor local (ProductTaxEngineService + tax_rules).
- Fonte de referencia oficial online: Sankhya POST /v1/fiscal/impostos/calculo.

## O que ja existe no SaaS (codigo atual)
- Motor fiscal por item implementado no app:
  - IPI, ICMS-ST (MVA/PMC), DIFAL
  - selecao de regra por NCM/CEST/UF/prioridade/validade
- Persistencia de regras fiscais:
  - colecao tax_rules
- Snapshot fiscal por item no pedido:
  - PedidoItemTaxSnapshot

## Lacuna atual
- Nao existe ainda sincronizacao automatica de regras fiscais vindas do Sankhya para tax_rules.

## Cenarios de implementacao

### Cenario A - 100% offline-first com regra local
- Alimentar tax_rules via planilha (importacao portal).
- Vantagem: independencia total de endpoint fiscal no fechamento do pedido offline.
- Risco: desvio em relacao ao ERP se regras nao forem mantidas atualizadas.

### Cenario B - Hibrido (recomendado)
- Offline: calcula com tax_rules locais.
- Online: opcionalmente recalcula no endpoint fiscal do Sankhya antes de transmitir pedido.
- Se diferenca acima de tolerancia: registra divergencia e bloqueia envio automatico.

## Recomendacao pratica para producao
1. Manter o motor local como definitivo para operacao offline.
2. Criar job de reconciliacao online com /v1/fiscal/impostos/calculo.
3. Criar pipeline de atualizacao de tax_rules:
   - fase 1: planilha (rapida e controlavel);
   - fase 2: estudar endpoints adicionais Sankhya para parametrizacao fiscal (se houver no contrato liberado).

## Indicadores de governanca fiscal
- percentual de pedidos com divergencia fiscal local x ERP
- valor medio de divergencia por item
- tempo desde ultima atualizacao de tax_rules
- cobertura de NCM/CEST por representada
