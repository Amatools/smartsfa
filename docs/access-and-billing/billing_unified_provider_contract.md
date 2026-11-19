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

## Garantias de Robustez (Camada Comum)

As garantias abaixo sao obrigatorias para Stripe e Asaas, independentemente do adapter:

1. Idempotencia de mutacoes por `operationId` (ou `idempotencyKey`).
2. Journal de mutacoes por tenant para dedupe e replay de resposta.
3. Controle de concorrencia por versao de contrato (`contractVersion`).
4. Lock curto por tenant (lease com expiracao) para mutacoes criticas.
5. Suporte a estado intermediario `pending_reconcile` para erro parcial.
6. Dedupe de webhook por `provider + eventId`.
7. Tolerancia a webhook fora de ordem com reconcile por snapshot atual.

Esses controles existem mesmo quando apenas owner altera plano/seats,
porque retries, timeout, double-click e multiplas sessoes podem gerar
efeito duplicado sem essas protecoes.

## Fluxo de Dispatch

1. Resolver provider do tenant (ou hint explicito)
2. Carregar runtime do provider
3. Verificar idempotencia (`operationId`) e lock/versionamento
4. Executar operacao no contrato comum
5. Persistir estado canonico em `tenants/{tenantId}`
6. Registrar journal/auditoria da mutacao
7. Executar regras comuns (seat governance, reconciliacao)

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
6. Em mutacoes ambiguas (timeout apos efeito parcial), retornar/registrar
   `pending_reconcile` e convergir por reconciliacao ativa.

## Contratos de Dados Minimos (Billing Engine)

Colecoes minimas esperadas na camada comum:

1. `tenant_billing_contracts`
   - `contractVersion`
   - `lastAppliedOperationId`
2. `tenant_billing_operations`
   - `operationId`
   - `operationType`
   - `requestHash`
   - `status` (`received` | `applied` | `failed` | `pending_reconcile`)
3. `billing_provider_refs`
   - `lastWebhookEventId`
   - `lastWebhookEventAt`
   - `lastReconciledAt`

Objetivo: garantir rastreabilidade e convergencia de estado,
sem depender de ordem perfeita de eventos do provider.

## Regras de Melhor Pratica

- Fonte de verdade de acesso sempre no backend canonico (`tenants` + memberships)
- Provider e apenas meio de cobranca, nao de autorizacao
- Nenhuma decisao de acesso no frontend
- Auditoria obrigatoria para acoes manuais e reconciliacao
- Fallback explicito para provider nao implementado

## Proximo Passo Tecnico

Adicionar endpoints agnosticos para novos clientes internos:

- `createBillingQuote`
- `createBillingCheckoutSession`
- `createBillingPortalSession`
- `previewTenantSeatPackChange`
- `changeTenantSeatPack`
- `handleBillingWebhook`
- `reconcileTenantBilling`

Mantendo os endpoints Stripe atuais durante a transicao.
