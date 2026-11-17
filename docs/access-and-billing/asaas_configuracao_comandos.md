# Asaas - Guia de Configuracao por Comandos (Sandbox e Producao)

Este guia prepara a integracao Asaas no SmartSFA sem expor segredos no app.

Regra principal:

- tudo que for segredo (api key, webhook token) deve ficar no Secret Manager das Cloud Functions;
- Firestore/Maintainer guarda apenas metadados nao sensiveis.

## O que e [firebase_project_id]

- [firebase_project_id] e o ID do projeto Firebase/GCP onde as resources estao publicadas.
- Neste workspace, o valor atual e: [smart-sfa].

## 1) Pre-requisitos

Voce precisa ter em maos:

- [firebase_project_id]
- [asaas_wallet_id_sandbox]
- [asaas_wallet_id_production]
- [asaas_api_key_sandbox]
- [asaas_api_key_production]
- [asaas_webhook_token_sandbox]
- [asaas_webhook_token_production]

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

Sugestao de nomes de segredos para Asaas:

- ASAAS_API_KEY_SANDBOX
- ASAAS_API_KEY_PRODUCTION
- ASAAS_WEBHOOK_TOKEN_SANDBOX
- ASAAS_WEBHOOK_TOKEN_PRODUCTION

### 3.1 Ambiente sandbox

```powershell
firebase functions:secrets:set ASAAS_API_KEY_SANDBOX --project [firebase_project_id]
firebase functions:secrets:set ASAAS_WEBHOOK_TOKEN_SANDBOX --project [firebase_project_id]
```

Quando pedir valor:

- ASAAS_API_KEY_SANDBOX -> [asaas_api_key_sandbox]
- ASAAS_WEBHOOK_TOKEN_SANDBOX -> [asaas_webhook_token_sandbox]

### 3.2 Ambiente producao

```powershell
firebase functions:secrets:set ASAAS_API_KEY_PRODUCTION --project [firebase_project_id]
firebase functions:secrets:set ASAAS_WEBHOOK_TOKEN_PRODUCTION --project [firebase_project_id]
```

Quando pedir valor:

- ASAAS_API_KEY_PRODUCTION -> [asaas_api_key_production]
- ASAAS_WEBHOOK_TOKEN_PRODUCTION -> [asaas_webhook_token_production]

## 4) Deploy das funcoes Asaas (quando o adapter estiver ativo)

Assim que as funcoes Asaas forem publicadas no backend, use:

```powershell
firebase deploy --project [firebase_project_id] --only functions:handleAsaasWebhook,functions:reconcileAsaasTenant
```

Observacao:

- se o backend usar endpoints unificados de billing, adicione os nomes reais das funcoes do projeto no comando acima.

## 5) Configurar webhook no Asaas (Dashboard)

No painel do Asaas, para sandbox e producao:

1. Cadastrar endpoint de webhook.
2. URL do endpoint:
   - [https://us-central1-[firebase_project_id].cloudfunctions.net/handleAsaasWebhook]
3. Definir eventos de cobranca/assinatura relevantes.
4. Configurar token de autenticacao do webhook e salvar no Secret Manager (passo 3).

## 6) Configuracao no Maintainer (sem segredos)

Tela: Maintainer > Integracao Asaas

Preencher:

- Ambiente ativo: [sandbox] ou [production]
- Wallet ID (sandbox): [asaas_wallet_id_sandbox]
- Wallet ID (producao): [asaas_wallet_id_production]
- Webhook endpoint: URL publica da function

## 7) Configuracao da API Checkout

Tela: Maintainer > API Checkout

Selecionar modo ativo:

- stripe
- asaas
- stripe + asaas

Definir provider preferencial:

- stripe ou asaas

## 8) Teste fim a fim (apos adapter Asaas)

1. Habilitar Asaas no API Checkout.
2. Abrir checkout no portal do tenant.
3. Concluir cobranca de teste no Asaas.
4. Verificar atualizacao em tenants/{tenantId}:
   - billingProvider
   - billingStatus
   - billingCurrentPeriodStartAt
   - billingCurrentPeriodEndAt

## 9) Checklist de seguranca

- Nao salvar api keys/tokens do Asaas em Firestore.
- Nao commitar segredos em codigo/repositorio.
- Rotacionar segredos periodicamente.
- Se algum segredo for exposto em chat/email, rotacionar imediatamente.
