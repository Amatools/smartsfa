# SmartSFA - Contrato Firestore + Cloud Functions (Stripe)

## Objetivo

Definir contrato tecnico objetivo para:

- estrutura de dados no Firestore para integracao Stripe;
- contratos de endpoints/functions para checkout, webhook e reconciliacao;
- requisitos de seguranca e idempotencia.

Este documento deve ser usado como base de implementacao backend.

## 1) Estrutura Firestore

### 1.1 billing_integrations/stripe

Documento unico global com metadados nao sensiveis.

Colecao/documento:

- billing_integrations/stripe

Campos:

- activeEnvironment: test | live
- accountIdTest: string
- accountIdLive: string
- webhookEndpointTest: string
- webhookEndpointLive: string
- webhookEvents: string[]
- updatedBy: string (uid)
- updatedAt: string (ISO 8601)

Observacao:

- segredos (sk_*, whsec_*) nao entram no Firestore.

### 1.2 billing_integrations/stripe/plan_mappings/{mappingId}

Mapeamento entre plano interno e catalogo Stripe.

Campos:

- billingPlanKey: string
- stripeProductId: string
- stripePriceId: string
- mappingType: base | overage
- overageMetric: string (opcional)
- active: bool
- updatedBy: string (uid)
- updatedAt: string (ISO 8601)

Exemplos de overageMetric:

- extra_representada
- extra_usuario
- extra_storage_gb
- extra_orders_pack_1000

### 1.3 billing_webhook_events/{eventId}

Store de idempotencia e trilha de processamento de webhook.

Campos:

- provider: stripe
- eventId: string
- type: string
- tenantId: string
- receivedAt: string (ISO 8601)
- processedAt: string (ISO 8601)
- processingStatus: success | error | retry
- errorMessage: string
- payloadHash: string (opcional)

### 1.4 tenants/{tenantId} (billing canonico)

Campos mantidos/sincronizados pela camada billing:

- billingPlanKey
- billingStatus
- billingCycle
- billingCurrentPeriodStartAt
- billingCurrentPeriodEndAt
- billingGraceUntilAt
- billingPastDueSinceAt
- billingSuspendedAt
- stripeCustomerId
- stripeSubscriptionId
- stripePriceId
- stripeCheckoutSessionId
- billingUpdatedAt

## 2) Contrato de Cloud Functions / API

Base sugerida: HTTPS (onRequest) com autenticacao por Firebase ID token.

## 2.1 POST /billing/stripe/create-checkout-session

Finalidade:

- iniciar checkout de assinatura para um tenant.

Entrada (JSON):

- tenantId: string
- billingPlanKey: string
- successUrl: string
- cancelUrl: string

Saida (200):

- checkoutUrl: string
- checkoutSessionId: string
- stripeCustomerId: string

Erros esperados:

- 400 invalid_payload
- 401 unauthenticated
- 403 forbidden
- 404 plan_mapping_not_found
- 409 invalid_billing_state
- 500 internal_error

## 2.2 POST /billing/stripe/create-portal-session

Finalidade:

- abrir Stripe Customer Portal para tenant existente.

Entrada:

- tenantId: string
- returnUrl: string

Saida:

- portalUrl: string

Erros:

- 404 stripe_customer_missing
- 409 integration_not_ready

## 2.3 POST /billing/stripe/webhook

Finalidade:

- receber eventos Stripe assinados.

Entrada:

- corpo bruto do webhook Stripe
- header Stripe-Signature

Saida:

- 200 { received: true }

Regras:

- validar assinatura com whsec do ambiente ativo;
- idempotencia por eventId em billing_webhook_events;
- processar apenas eventos da allowlist;
- registrar status success/error/retry.

## 2.4 POST /billing/stripe/reconcile-tenant

Finalidade:

- reconciliar estado de um tenant com Stripe sob demanda de maintainer.

Entrada:

- tenantId: string
- reason: string

Saida:

- tenantId: string
- stripeSubscriptionId: string
- previousBillingStatus: string
- currentBillingStatus: string
- updatedAt: string

Permissao:

- apenas maintainer com permissao billing.stripe.reconcile.

## 2.5 POST /billing/stripe/reconcile-all

Finalidade:

- executar reconciliacao em lote (uso operacional interno).

Entrada:

- dryRun: bool (opcional)
- limit: number (opcional)

Saida:

- totalProcessed: number
- totalUpdated: number
- totalFailed: number

Permissao:

- somente backend/cron autenticado (nao expor para cliente comum).

## 3) Seguranca obrigatoria

1. Chaves Stripe no Secret Manager, nunca em Firestore/UI.
2. Verificacao de assinatura em 100% dos webhooks.
3. Idempotencia por eventId em billing_webhook_events.
4. Segregacao total test/live (segredos, endpoint, mapeamentos e logs).
5. Auditoria de acoes admin em platform_admin_audit.
6. Menor privilegio IAM para service account de billing.

## 4) Metadados Stripe recomendados

Em Checkout Session / Subscription metadata:

- tenantId
- billingPlanKey
- initiatedByUid
- source: smartsfa_web_portal

Objetivo:

- facilitar reconciliação e forense operacional.

## 5) Ordem de entrega recomendada

1. Persistencia de billing_integrations/stripe + plan_mappings.
2. Endpoint create-checkout-session.
3. Webhook assinado com idempotencia.
4. Reconcile por tenant.
5. Reconcile em lote por scheduler.
6. Customer Portal (opcional).
