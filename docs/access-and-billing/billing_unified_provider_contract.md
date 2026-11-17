# Contrato Unico de Cobranca (Stripe + Asaas Ready)

## Objetivo

Padronizar o backend para operar com um unico contrato de cobranca,
independente do provedor. O sistema deve suportar:

- Stripe apenas
- Asaas apenas
- Stripe e Asaas em paralelo (por tenant)

Sem duplicar regras de acesso, governanca de assentos e auditoria.

## Decisao de Arquitetura

O backend passa a usar uma camada de roteamento por `billingProvider`.

Provider inicial implementado:

- `stripe`

Provider planejado:

- `asaas` (retorno controlado `provider_not_implemented` ate implementacao)

## Diferenca de Modelo por Provider

### Stripe

- manter fluxo atual com capacidades nativas do ecossistema Stripe para assinatura;
- SmartSFA segue com orquestracao, reconciliacao e entitlement.

### Asaas

- adotar motor interno de billing no SmartSFA para catalogo comercial, calculo de preco,
  seats adicionais, limites e politica de alteracao;
- Asaas atua como gateway de cobranca, com valor final calculado no backend do SmartSFA.

Documento de detalhamento obrigatorio antes da implementacao:

- `asaas_internal_billing_engine_plan.md`

## Campo Canonico no Tenant

Documento: `tenants/{tenantId}`

Novo campo canonico:

- `billingProvider`: `stripe` | `asaas`

Regras:

- quando vazio, fallback para `stripe`
- checkout e eventos Stripe passam a persistir `billingProvider: stripe`

## Contrato Interno de Provider

Operacoes do contrato (backend):

1. `loadRuntime`
2. `processWebhookEvent`
3. `reconcileTenantState`
4. `applyManualBillingAction`

Observacao:

- regras de acesso ao tenant, trilha de auditoria e seat governance
  continuam fora do provider (camada comum)

## Fluxo de Dispatch

1. Resolver provider do tenant (ou hint explicito)
2. Carregar runtime do provider
3. Executar operacao no contrato comum
4. Persistir estado canonico em `tenants/{tenantId}`
5. Executar regras comuns (seat governance, auditoria)

## Endpoints Atuais e Compatibilidade

Endpoints Stripe legados permanecem ativos para compatibilidade.

Internamente, agora usam dispatch por provider nos pontos criticos:

- reconciliacao de tenant
- processamento de webhook
- acoes manuais de billing no maintainer

## Padrao para Implementar Asaas

Quando iniciar Asaas:

1. Implementar adapter Asaas no mesmo contrato interno.
2. Garantir traducao para status canonicos:
   - `active`, `trial`, `past_due`, `suspended`, `canceled`, `no_plan`
3. Traduzir periodo atual para:
   - `billingCurrentPeriodStartAt`
   - `billingCurrentPeriodEndAt`
4. Persistir ids de referencia Asaas em campos proprios
   (sem sobrescrever ids Stripe existentes).
5. Manter idempotencia de webhook por provider + eventId.

## Regras de Melhor Pratica

- Fonte de verdade de acesso sempre no backend canonico (`tenants` + memberships)
- Provider e apenas meio de cobranca, nao de autorizacao
- Nenhuma decisao de acesso no frontend
- Auditoria obrigatoria para acoes manuais e reconciliacao
- Fallback explicito para provider nao implementado

## Proximo Passo Tecnico

Adicionar endpoints agnosticos para novos clientes internos:

- `createBillingCheckoutSession`
- `createBillingPortalSession`
- `handleBillingWebhook`
- `reconcileTenantBilling`

Mantendo os endpoints Stripe atuais durante a transicao.
