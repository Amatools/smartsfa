# Stripe - Guia de Configuracao por Comandos (Teste e Producao)

Este guia e para configurar a integracao Stripe no SmartSFA sem expor segredos no app.

Regra principal:

- tudo que for segredo (sk_*, whsec_*) deve ficar no Secret Manager das Cloud Functions;
- Firestore/Maintainer guarda apenas metadados nao sensiveis.

## O que e [firebase_project_id]

- [firebase_project_id] e o ID do projeto Firebase/GCP onde as resources estao publicadas.
- Neste workspace, o valor atual e: [smart-sfa].
- Onde foi confirmado: arquivo .firebaserc (projects.default) e firebase.json (flutter projectId).

## 1) Pre-requisitos

Voce precisa ter em maos:

- [firebase_project_id]
- [stripe_account_id_test]
- [stripe_account_id_live]
- [stripe_secret_key_test] (sk_test_...)
- [stripe_secret_key_live] (sk_live_...)
- [stripe_webhook_secret_test] (whsec_...)
- [stripe_webhook_secret_live] (whsec_...)

### Onde encontrar o account id (acct_...)

Opcoes praticas:

1. Stripe Dashboard:

   - clique no icone de engrenagem (Settings)
   - abra Business settings > Account details
   - copie o campo Account ID (formato acct_...)
2. Via API Stripe (com sk):

   - chamar GET /v1/account
   - usar o campo id da resposta
3. No SmartSFA (apos deploy da function listStripeCatalog):

   - Maintainer > Billing Stripe > Importar da Stripe
   - o dialog mostra "Account: acct_..." do ambiente ativo

## 2) Login e selecao de projeto

Execute:

```powershell
firebase login
firebase use [firebase_project_id]
```

Exemplo neste projeto:

```powershell
firebase use smart-sfa
```

## 3) Cadastrar segredos no Secret Manager

Importante:

- como as functions Stripe estao vinculadas aos segredos por nome, o deploy exige que todos eles existam com pelo menos 1 versao;
- se voce ainda nao tem credenciais de live, pode cadastrar valores placeholder temporarios para STRIPE_SK_LIVE e STRIPE_WHSEC_LIVE.

### 3.1 Ambiente de teste

Execute cada comando e, quando o terminal pedir o valor, cole o segredo correspondente:

```powershell
firebase functions:secrets:set STRIPE_SK_TEST --project [firebase_project_id]
firebase functions:secrets:set STRIPE_WHSEC_TEST --project [firebase_project_id]
```

Quando pedir valor:

- STRIPE_SK_TEST -> [stripe_secret_key_test]
- STRIPE_WHSEC_TEST -> [stripe_webhook_secret_test]

### 3.2 Ambiente de producao

```powershell
firebase functions:secrets:set STRIPE_SK_LIVE --project [firebase_project_id]
firebase functions:secrets:set STRIPE_WHSEC_LIVE --project [firebase_project_id]
```

Quando pedir valor:

- STRIPE_SK_LIVE -> [stripe_secret_key_live]
- STRIPE_WHSEC_LIVE -> [stripe_webhook_secret_live]

Se ainda nao tiver live pronto, use placeholder temporario:

- [placeholder_live_secret]

## 4) (Opcional) Definir ambiente padrao por segredo

Use apenas se quiser forcar ambiente por variavel de runtime.

```powershell
firebase functions:secrets:set STRIPE_ACTIVE_ENVIRONMENT --project [firebase_project_id]
```

Quando pedir valor:

- [test] ou [live]

Observacao:

- o sistema tambem le activeEnvironment do documento Firestore billing_integrations/stripe.

## 5) Deploy das funcoes Stripe

```powershell
firebase deploy --project [firebase_project_id] --only functions:createStripeCheckoutSession,functions:createStripePortalSession,functions:handleStripeWebhook,functions:reconcileStripeTenant,functions:reconcileAllStripeTenants
```

## 6) Configurar webhook no Stripe (Dashboard)

No Stripe Dashboard, em Test mode e depois em Live mode:

1. Developers > Webhooks > Add endpoint.
2. URL do endpoint:
   - [https://us-central1-[firebase_project_id].cloudfunctions.net/handleStripeWebhook]
3. Eventos obrigatorios:
   - checkout.session.completed
   - customer.subscription.created
   - customer.subscription.updated
   - customer.subscription.deleted
   - invoice.finalized
   - invoice.paid
   - invoice.payment_failed
4. Copiar Signing secret (whsec_...) e salvar no Secret Manager (passo 3).

## 7) Configuracao no Maintainer (sem segredos)

Tela: Maintainer > Billing Stripe

Preencher:

- Ambiente ativo: [test] ou [live]
- Account ID (test): [stripe_account_id_test]
- Account ID (live): [stripe_account_id_live]
- Webhook endpoint (test): [webhook_endpoint_test]
- Webhook endpoint (live): [webhook_endpoint_live]
- Eventos inscritos: 1 evento por linha

## 8) Cadastro de planos (agora separado por secao)

Na mesma tela Billing Stripe, use os blocos:

- Planos - Conta individual
- Planos - Conta representacoes
- Planos - Conta enterprise

Em cada bloco, clique em "Cadastrar plano".

Campos:

- Secao de plano
- Identificador do plano (sem prefixo)
- Tipo: base ou overage
- Stripe Product ID: [stripe_product_id]
- Stripe Price ID: [stripe_price_id]
- Metrica de excedente (se overage)

Exemplos de billingPlanKey gerado:

- individual + base -> individual_base
- individual + pro -> individual_pro
- representacoes + base -> representacoes_base
- representacoes + pro -> representacoes_pro
- enterprise + custom -> enterprise_custom

## 9) Teste fim a fim

1. No portal do tenant, clicar "Abrir checkout".
2. Concluir assinatura de teste no Stripe.
3. Verificar atualizacao em tenants/{tenantId}:
   - stripeCustomerId
   - stripeSubscriptionId
   - stripePriceId
   - billingStatus
4. Clicar "Abrir portal Stripe" e validar acesso ao Customer Portal.

## 10) Comandos uteis de operacao

### Reconciliar um tenant

```powershell
# via app/admin (recomendado) ou chamada autenticada da function reconcileStripeTenant
```

### Reconciliar em lote

```powershell
# via app/admin (recomendado) ou chamada autenticada da function reconcileAllStripeTenants
```

## 11) Checklist de seguranca

- Nao salvar sk_* ou whsec_* em Firestore.
- Nao commitar segredos em codigo/repositorio.
- Rotacionar segredos periodicamente.
- Se algum segredo foi exposto em chat/email, rotacionar imediatamente.


## 12) Metadados para Planos


* billingPlanKey

Exemplos:

* individual_base
* individual_pro
* representacoes_base
* representacoes_pro
* enterprise_custom
