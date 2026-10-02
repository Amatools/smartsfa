# SmartSFA - Regras de Negocio de Precificacao e Tributacao (Estado Atual)

## Objetivo

Este documento consolida as regras ja decididas e o comportamento implementado no codigo para:

- tabelas de preco
- calculo de preco final por cliente/produto
- regras de tributacao por NCM/UF

Escopo atual: descricao do estado implementado em codigo e pontos ainda pendentes de integracao.

## Decisoes de produto ja aplicadas

- O produto continua sendo cadastro mestre, incluindo base para tributacao.
- A aba Tributacao do produto foi simplificada para campos base: NCM, CEST e aliquota de IPI base.
- O portal suporta os dois modos comerciais: tabela e politica.
- O motor de tributacao foi iniciado como modulo desacoplado, sem acoplamento obrigatorio ao fluxo de pedido neste momento.

## Entidades e colecoes relevantes

### Tabelas de preco

- Colecao: tabelas_preco
- Modelo: core/models/tabela_preco.dart
- Campos principais:
  - id, tenantId
  - nome
  - scopeType, scopeLabel, scopeIndex
  - origem (manual/system), status
  - linkedEntityId (quando escopo e representada)
  - rowCount, validFrom, validUntil

### Precos base por produto

- Colecao: product_base_prices
- Uso: armazenar preco bruto por produto/tabela/regiao, com status e validade.

### Vinculo cliente -> tabela

- Colecao: customer_price_table_assignments
- Uso: definir qual tabela deve ser usada por cliente e regiao (com prioridade e validade).

### Regras cliente/produto -> politica de desconto

- Colecao: customer_product_rules
- Uso: escolher politica de desconto por cliente + produto.

### Politicas de desconto

- Colecao: discount_policies
- Uso: percentual aplicado sobre preco base selecionado.

### Regras fiscais

- Colecao: tax_rules
- Modelo: core/models/tax_rule.dart
- Campos principais:
  - id, tenantId, status
  - ncm (opcional)
  - ufOrigem, ufDestino (aceita ANY)
  - cstCsosn (opcional)
  - aliquotaIcms, aliquotaIpi, mvaIva, aliquotaSt, aliquotaDifal
  - priority
  - validFrom, validUntil

## Regra implementada: calculo de preco final

Servico: features/precos/services/product_price_calculator_service.dart

Ordem de resolucao:

1. Buscar vinculos ativos do cliente em customer_price_table_assignments.
2. Filtrar por janela de validade.
3. Selecionar vinculo por regiao:
   - primeiro: match exato de regiao
   - fallback: regionId vazio ou isDefault = true
   - desempate: maior prioridade
4. Definir tabela alvo:
   - assignment.priceTableId
   - fallbackPriceTableId (quando informado)
5. Buscar preco base em product_base_prices:
   - match por productId + priceTableId + ativo + validade
   - primeiro: regiao exata
   - fallback: regionId vazio, ALL ou BR
6. Buscar regra customer_product_rule ativa/valida por cliente+produto.
7. Resolver politica de desconto:
   - discountPolicyId da regra
   - fallbackDiscountPolicyId (quando informado)
8. Aplicar desconto percentual da policy ativa.

Formula:

- netPrice = basePrice * (1 - discountPercentage/100)

Retorno atual inclui:

- basePrice, discountPercentage, netPrice
- priceTableId, regionId
- source (fallback ou customer_product_rule)

## Regra implementada: calculo tributario por item

Servico: features/precos/services/product_tax_engine_service.dart

Entradas:

- tenantId, produtoId, tabelaId, clienteUf, quantidade
- ufOrigem (padrao: SP)

Passos:

1. Validar parametros obrigatorios e quantidade > 0.
2. Buscar produto por tenantId + produtoId.
3. Resolver preco base por produto+tabela+UF (com fallback de regiao).
4. Carregar tax_rules e selecionar regra fiscal aplicavel:
   - status ativo
   - validade atual
   - ncm exato quando regra define ncm
   - ufOrigem/ufDestino com match exato ou ANY
   - desempate por maior priority
5. Calcular base:
   - precoBase = basePrice * quantidade
6. Calcular IPI:
   - aliquotaIpi = regra.aliquotaIpi ou produto.aliquotaIpiBase ou 0
   - valorIpi = precoBase * aliquotaIpi/100
7. Calcular ST (quando houver MVA e aliquota ST):
   - baseSt = precoBase * (1 + mvaIva/100)
   - icmsProprio = precoBase * aliquotaIcms/100
   - icmsStCheio = baseSt * aliquotaSt/100
   - valorSt = max(icmsStCheio - icmsProprio, 0)
8. Calcular DIFAL:
   - valorDifal = precoBase * aliquotaDifal/100
9. Consolidar:
   - valorLiquido = precoBase
   - valorTotalItem = valorLiquido + valorIpi + valorSt + valorDifal

## Regras de fallback importantes

- Tabela de preco: fallback para assignment/regiao default quando nao houver match exato.
- Preco base: fallback para regionId vazio, ALL ou BR.
- Regra fiscal: pode cair para regra mais generica (ncm vazio e/or UF ANY), respeitando prioridade.
- IPI: sem regra fiscal, usa aliquotaIpiBase do produto.

## Permissoes no portal (estado atual)

No menu Configuracoes da area comercial:

- Unidades: edicao restrita a owner (seller_solo_workspace e rep_workspace).
- Tributacoes: mesma restricao (owner) para criar/editar/excluir.
- Perfis sem permissao recebem modo somente leitura.

## Limites atuais e proximos passos

- O tax engine ainda nao esta plugado no fluxo de pedido (decisao intencional desta fase).
- Ainda faltam testes unitarios dedicados para cenarios de ST/DIFAL/fallback de regra.
- Integracao com politicas comerciais avancadas (mangas/travas) segue em evolucao separada.

## Fonte da verdade tecnica

Para comportamento efetivo, considerar sempre o codigo como fonte primaria e este documento como consolidacao de leitura:

- features/precos/services/product_price_calculator_service.dart
- features/precos/services/product_tax_engine_service.dart
- core/models/tax_rule.dart
- core/models/tabela_preco.dart
