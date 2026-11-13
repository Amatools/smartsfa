# SmartSFA - Blueprint de Integracao Stripe (Zero to One)

## Objetivo

Definir o desenho tecnico e operacional para integrar Stripe do zero com:

- checkout e assinatura por tenant;
- reconciliacao por webhook com idempotencia;
- configuracao segura via painel de mantenedor;
- protecao de chaves e trilha de auditoria.

Este documento complementa:

- workspace_access_billing_policy.md
- plano_billing.md
- stripe_firestore_functions_contract.md

## Arquitetura alvo (resumo)

1. Frontend (web/app) solicita checkout no backend.
2. Backend cria/garante customer Stripe do tenant.
3. Backend cria Checkout Session Stripe com metadados do tenant.
4. Stripe processa pagamento/assinatura.
5. Webhook Stripe atualiza estado canonico em tenants/{tenantId}.
6. Entitlement server-side libera/bloqueia recursos com base em billingStatus + billingPlanKey.

## O que voce precisa obter no Stripe

Separar tudo por ambiente: test e live.

### 1. Credenciais e IDs de conta

- Stripe account id (formato acct_...).
- Secret key de API por ambiente (sk_test_..., sk_live_...).
- Publishable key por ambiente (pk_test_..., pk_live_...) se houver uso futuro de Elements.

### 2. Webhooks

- endpoint de webhook por ambiente (URL publica do backend).
- signing secret por endpoint (whsec_...).
- lista de eventos assinados habilitados.

### 3. Catalogo comercial

Para cada plano base/excedente:

- product id (prod_...).
- price id (price_...).
- moeda, recorrencia e intervalo.
- estrategia de excedente (flat ou metered).

### 4. Configuracoes operacionais

- configuracao de Customer Portal (se usado).
- metodos de pagamento habilitados por pais/conta.
- configuracao fiscal (tax behavior) quando aplicavel.

## Eventos Stripe obrigatorios

Eventos minimos para manter billing consistente:

- checkout.session.completed
- customer.subscription.created
- customer.subscription.updated
- customer.subscription.deleted
- invoice.finalized
- invoice.paid
- invoice.payment_failed

Eventos recomendados:

- invoice.upcoming
- customer.subscription.trial_will_end

## Mapeamento de eventos -> estado interno

| Evento Stripe | Atualizacao principal no tenant |
| --- | --- |
| checkout.session.completed | grava stripeCheckoutSessionId, stripeCustomerId e prepara assinatura |
| customer.subscription.created | billingStatus=active (ou trial), stripeSubscriptionId, stripePriceId |
| customer.subscription.updated | sincroniza plano, periodo, status e itens |
| customer.subscription.deleted | billingStatus=canceled e timestamps |
| invoice.paid | normaliza para active e limpa delinquency |
| invoice.payment_failed | billingStatus=past_due e define billingPastDueSinceAt |

Observacao:

- grace e suspended continuam sendo estados de negocio do SmartSFA, acionados por politica interna e reconciliacao.

## Modelo de dados recomendado

### Tenant (fonte de verdade funcional)

Em tenants/{tenantId}, manter ao menos:

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

### Configuracao global de billing

Colecao sugerida:

- billing_integrations/stripe

Campos nao sensiveis sugeridos:

- activeEnvironment: test | live
- accountIdTest
- accountIdLive
- webhookEndpointTest
- webhookEndpointLive
- webhookEvents: []
- updatedAt
- updatedBy

Nao salvar no Firestore:

- sk_test/sk_live
- whsec

### Segredos

Usar Secret Manager com nomes por ambiente:

- stripe_sk_test
- stripe_sk_live
- stripe_whsec_test
- stripe_whsec_live

## Tela no painel admin (maintenance)

Sugestao de secao: Billing > Integracoes > Stripe

### Aba 1 - Ambiente

Campos:

- ambiente ativo: test/live
- account id test
- account id live
- status da conexao por ambiente
- ultimo health-check

Acoes:

- validar conexao
- alternar ambiente ativo (com confirmacao)

### Aba 2 - Segredos

Campos (entrada mascarada, nunca exibindo valor completo):

- secret key test
- secret key live
- webhook secret test
- webhook secret live

Acoes:

- gravar segredo no Secret Manager
- rotacionar segredo
- testar assinatura de webhook

Regras:

- UI nao le segredo de volta.
- apos salvar, apenas exibir fingerprint/parcial e data de rotacao.

### Aba 3 - Mapeamento de planos e prices

Grid obrigatoria:

- billingPlanKey interno
- stripeProductId
- stripePriceId
- tipo: base | excedente
- metrica de excedente (quando houver)
- ativo

Acoes:

- adicionar mapeamento
- desativar mapeamento
- validar duplicidade de priceId

### Aba 4 - Webhooks

Campos:

- URL configurada
- eventos inscritos
- ultimo evento recebido
- ultimo erro
- total de retries

Acoes:

- reenfileirar evento
- reconciliar tenant manualmente
- abrir log detalhado por eventId

### Aba 5 - Operacao por tenant

Campos de leitura:

- tenantId
- stripeCustomerId
- stripeSubscriptionId
- stripePriceId
- billingStatus
- periodo atual

Acoes controladas:

- criar customer faltante
- criar checkout session manual
- sincronizar assinatura agora
- aplicar grace temporario

## Permissoes recomendadas (RBAC)

Permissoes dedicadas no maintainer:

- billing.stripe.view_config
- billing.stripe.manage_config
- billing.stripe.rotate_secrets
- billing.stripe.manage_webhooks
- billing.stripe.reconcile
- billing.stripe.tenant_override

Guardrails:

- acoes criticas exigem motivo obrigatorio.
- dual control para troca de ambiente live.
- auditoria com before/after em toda alteracao de config.

## Seguranca (obrigatorio)

1. Chaves Stripe apenas no backend e Secret Manager.
2. Nunca trafegar sk_* para cliente web/mobile.
3. Verificar assinatura de webhook em todas as chamadas.
4. Idempotencia por eventId (webhook) e idem-key (chamadas de escrita Stripe).
5. Segregar test/live com segredos e endpoints distintos.
6. Rotacao periodica de chaves e webhook secrets.
7. Limitar IAM da service account de billing ao minimo necessario.

## Endpoints backend sugeridos

Endpoints server-side:

- POST /billing/stripe/create-checkout-session
- POST /billing/stripe/create-portal-session
- POST /billing/stripe/webhook
- POST /billing/stripe/reconcile-tenant
- POST /billing/stripe/reconcile-all

Contrato minimo de create-checkout-session:

Entrada:

- tenantId
- billingPlanKey
- successUrl
- cancelUrl

Saida:

- checkoutUrl
- checkoutSessionId

## Idempotencia e auditoria

### Webhook idempotency store

Colecao sugerida:

- billing_webhook_events/{eventId}

Campos:

- provider: stripe
- eventId
- type
- receivedAt
- processedAt
- processingStatus: success|error|retry
- tenantId
- errorMessage

### Auditoria admin

Colecao sugerida:

- platform_admin_audit

Campos:

- actorUid
- action
- scope
- targetId
- reason
- before
- after
- createdAt

## Sequencia de implementacao (ordem recomendada)

1. Criar configuracao global Stripe (somente campos nao sensiveis).
2. Implementar gravacao/rotacao de segredos em Secret Manager.
3. Implementar create-checkout-session no backend com metadados de tenant.
4. Implementar webhook assinado + idempotencia + atualizacao de tenant.
5. Implementar reconciliacao manual por tenant no painel maintainer.
6. Implementar reconciliacao agendada diaria e alertas de divergencia.
7. Liberar Customer Portal (opcional) apos estabilidade do ciclo principal.

## Checklist rapido para voce levantar no Stripe agora

1. account id de test e live.
2. sk_test e sk_live.
3. whsec de test e live.
4. product/price ids de todos os 5 planos base.
5. product/price ids dos excedentes (representada extra, usuario extra, storage, pacote de pedidos).
6. lista final de eventos de webhook habilitados.
7. configuracao de metodos de pagamento permitidos para sua operacao B2B.
