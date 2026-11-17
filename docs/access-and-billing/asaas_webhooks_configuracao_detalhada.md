# Asaas - Webhooks (Configuracao Detalhada)

Este documento consolida exatamente o que precisa ser habilitado no Asaas para o SmartSFA.

Escopo:

- configuracao do webhook por ambiente (sandbox e producao);
- lista fechada de eventos recomendados;
- seguranca (token, header e idempotencia);
- observacao de readiness do backend atual.

## 1) Endpoints e ambientes

Criar 2 webhooks separados no Asaas:

1. Sandbox
2. Producao

URL do endpoint (SmartSFA):

- https://us-central1-smart-sfa.cloudfunctions.net/handleAsaasWebhook

Observacao:

- manter token diferente para sandbox e producao.

## 2) Campos obrigatorios ao criar webhook

No POST /v3/webhooks (ou pelo Dashboard), configurar:

- name: identificacao clara do ambiente (ex.: SmartSFA Sandbox / SmartSFA Producao)
- url: endpoint publico da function
- email: email monitorado pelo time
- enabled: true
- interrupted: false
- apiVersion: 3
- sendType: SEQUENTIALLY
- authToken: token forte (minimo recomendado: 32+ caracteres)
- events: lista de eventos deste documento

Recomendacao de sendType:

- usar SEQUENTIALLY para preservar ordem de eventos em transicoes de billing.

## 3) Autenticacao do webhook

Quando o Asaas chamar seu endpoint, ele envia o token no header:

- asaas-access-token

Importante:

- nao usar a API Key do Asaas como authToken de webhook;
- validar o header antes de processar o payload.

## 4) Eventos a habilitar (lista fechada recomendada)

### 4.1 Checkout

- CHECKOUT_CREATED
- CHECKOUT_PAID
- CHECKOUT_CANCELED
- CHECKOUT_EXPIRED

### 4.2 Assinatura (ciclo de vida)

- SUBSCRIPTION_CREATED
- SUBSCRIPTION_UPDATED
- SUBSCRIPTION_INACTIVATED
- SUBSCRIPTION_DELETED

### 4.3 Cobranca e pagamento

- PAYMENT_CREATED
- PAYMENT_UPDATED
- PAYMENT_CONFIRMED
- PAYMENT_RECEIVED
- PAYMENT_OVERDUE
- PAYMENT_DELETED
- PAYMENT_RESTORED
- PAYMENT_CREDIT_CARD_CAPTURE_REFUSED

### 4.4 Estorno e chargeback

- PAYMENT_REFUNDED
- PAYMENT_PARTIALLY_REFUNDED
- PAYMENT_REFUND_IN_PROGRESS
- PAYMENT_REFUND_DENIED
- PAYMENT_RECEIVED_IN_CASH_UNDONE
- PAYMENT_CHARGEBACK_REQUESTED
- PAYMENT_CHARGEBACK_DISPUTE
- PAYMENT_AWAITING_CHARGEBACK_REVERSAL

### 4.5 Nota fiscal (NFS-e)

- INVOICE_CREATED
- INVOICE_UPDATED
- INVOICE_SYNCHRONIZED
- INVOICE_AUTHORIZED
- INVOICE_PROCESSING_CANCELLATION
- INVOICE_CANCELED
- INVOICE_CANCELLATION_DENIED
- INVOICE_ERROR

Observacao fiscal:

- para trilha legal/auditoria, manter monitoramento dos campos invoice.id, invoice.status,
  invoice.number, invoice.validationCode, invoice.pdfUrl e invoice.xmlUrl.

## 5) Eventos opcionais (habilitar se usar Split)

### 5.1 Split em cobranca

- PAYMENT_SPLIT_CANCELLED
- PAYMENT_SPLIT_DIVERGENCE_BLOCK
- PAYMENT_SPLIT_DIVERGENCE_BLOCK_FINISHED
- PAYMENT_SPLIT_DONE

### 5.2 Split em assinatura

- SUBSCRIPTION_SPLIT_DISABLED
- SUBSCRIPTION_SPLIT_DIVERGENCE_BLOCK
- SUBSCRIPTION_SPLIT_DIVERGENCE_BLOCK_FINISHED

## 6) Segredos obrigatorios no backend

No Firebase Secret Manager, manter:

- ASAAS_API_KEY_SANDBOX
- ASAAS_API_KEY_PRODUCTION
- ASAAS_WEBHOOK_TOKEN_SANDBOX
- ASAAS_WEBHOOK_TOKEN_PRODUCTION

Regra:

- nunca salvar API Key ou token de webhook no Firestore.

## 7) Idempotencia e processamento

Webhooks do Asaas seguem modelo at least once:

- o mesmo evento pode chegar mais de uma vez;
- usar id do evento para deduplicacao;
- responder HTTP 200 apenas apos persistir o evento;
- processar efeitos de negocio de forma assincrona.

## 8) Exemplo de payload para criacao do webhook

Exemplo pratico (ajuste nome, email, token e eventos conforme ambiente):

{
  "name": "SmartSFA Producao",
  "url": "https://us-central1-smart-sfa.cloudfunctions.net/handleAsaasWebhook",
  "email": "billing-alerts@empresa.com",
  "enabled": true,
  "interrupted": false,
  "apiVersion": 3,
  "authToken": "defina-um-token-forte-com-mais-de-32-caracteres",
  "sendType": "SEQUENTIALLY",
  "events": [
    "CHECKOUT_CREATED",
    "CHECKOUT_PAID",
    "CHECKOUT_CANCELED",
    "CHECKOUT_EXPIRED",
    "SUBSCRIPTION_CREATED",
    "SUBSCRIPTION_UPDATED",
    "SUBSCRIPTION_INACTIVATED",
    "SUBSCRIPTION_DELETED",
    "PAYMENT_CREATED",
    "PAYMENT_UPDATED",
    "PAYMENT_CONFIRMED",
    "PAYMENT_RECEIVED",
    "PAYMENT_OVERDUE",
    "PAYMENT_DELETED",
    "PAYMENT_RESTORED",
    "PAYMENT_CREDIT_CARD_CAPTURE_REFUSED",
    "PAYMENT_REFUNDED",
    "PAYMENT_PARTIALLY_REFUNDED",
    "PAYMENT_REFUND_IN_PROGRESS",
    "PAYMENT_REFUND_DENIED",
    "PAYMENT_RECEIVED_IN_CASH_UNDONE",
    "PAYMENT_CHARGEBACK_REQUESTED",
    "PAYMENT_CHARGEBACK_DISPUTE",
    "PAYMENT_AWAITING_CHARGEBACK_REVERSAL",
    "INVOICE_CREATED",
    "INVOICE_UPDATED",
    "INVOICE_SYNCHRONIZED",
    "INVOICE_AUTHORIZED",
    "INVOICE_PROCESSING_CANCELLATION",
    "INVOICE_CANCELED",
    "INVOICE_CANCELLATION_DENIED",
    "INVOICE_ERROR"
  ]
}

## 9) Diferenca importante: Split x 2 cartoes

Split no Asaas nao e pagar com mais de um metodo de pagamento.

Split significa dividir a liquidacao da cobranca entre carteiras/contas recebedoras diferentes,
por exemplo:

- 85% para carteira do tenant;
- 15% para carteira da plataforma.

Ja pagar com dois cartoes para a mesma cobranca e outra capacidade (multi-instrumento)
e nao e o significado de Split nos eventos acima.

## 10) Estado atual do SmartSFA (backend)

Estado atual:

1. Endpoint de webhook Asaas publicado: handleAsaasWebhook.
2. Validacao de token por ambiente (sandbox/producao) habilitada.
3. Idempotencia por billing_webhook_events habilitada.
4. Mapeamento de eventos de cobranca/assinatura e NFS-e habilitado.
5. Reconciliacao manual por tenant habilitada: reconcileAsaasTenant.

Checklist de validacao final em producao:

1. Confirmar entrega de eventos com tenant real (externalReference preenchido).
2. Confirmar atualizacao dos campos billingStatus/billingPlanKey/billingCurrentPeriod*.
3. Confirmar persistencia dos dados fiscais de NFS-e (status/numero/xml/pdf).
4. Monitorar duplicates e retries no billing_webhook_events.