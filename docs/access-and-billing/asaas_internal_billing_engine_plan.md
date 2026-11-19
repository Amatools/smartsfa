# SmartSFA - Plano de Billing Interno para Asaas (Sem Quebrar Stripe)

## Status

Documento de decisao pre-implementacao.

Objetivo: alinhar regras e arquitetura antes de iniciar alteracoes de codigo.

Backlog executavel correspondente:

- `asaas_internal_billing_execution_backlog.md`

## Contexto Atual

1. O checkout unificado ja suporta Asaas com sessao real de checkout no backend.
2. O fluxo Stripe atual continua valido e deve permanecer sem regressao.
3. O Asaas nao oferece, no mesmo nivel do Stripe Billing nativo, o conjunto completo de:
   - catalogo nativo de produto/preco no mesmo modelo de assinatura por seat;
   - ajuste automatico de assinatura com seat add-on e consolidacao de cobranca;
   - operacao padronizada de proration equivalente ao fluxo atual Stripe.

Conclusao: para Asaas, parte da inteligencia de billing deve ficar no SmartSFA.

## Decisao de Arquitetura

Modelo dual por provider:

1. Stripe: manter fluxo nativo atual.
2. Asaas: adotar motor interno de billing do SmartSFA para calculo, seats e regras comerciais.

Isso evita quebrar Stripe e permite evoluir Asaas com controle total do dominio de negocio.

## Diferenca de Responsabilidade por Provider

### Stripe (nativo)

1. Produto/preco e assinatura vivem majoritariamente no ecossistema Stripe.
2. Ajustes de assinatura e parte da mecanica de cobranca recorrente sao nativos.
3. SmartSFA faz orquestracao, reconciliacao e entitlement.

### Asaas (controlado pelo SmartSFA)

1. SmartSFA define catalogo comercial e regras de composicao de preco.
2. SmartSFA calcula valor final antes de abrir checkout Asaas.
3. SmartSFA controla seats, limites, aprovacoes e politicas de alteracao.
4. Asaas atua como gateway de cobranca e emissao da recorrencia gerada.

## Requisitos Funcionais para Asaas

1. Criador de planos no painel admin (catalogo interno).
2. Calculo server-side do valor final:
   - assinatura base;
   - seats adicionais;
   - regras de ciclo;
   - possivel ajuste futuro de proration.
3. Limite de seats adicionais por autoatendimento:
   - acima do teto, fluxo obrigatorio de suporte/comercial.
4. Separacao entre cobranca e entitlement:
   - o que foi contratado/pago;
   - o que esta liberado para uso no tenant.
5. Idempotencia obrigatoria para operacoes mutaveis:
   - criar quote;
   - abrir checkout;
   - alterar plano;
   - alterar seats.
6. Mecanismo de consistencia para evitar aplicacao duplicada em cenarios de retry/travamento.

## Robustez Operacional (Owner unico, mas tolerante a falhas)

Premissa: apenas owner altera plano/seats em self-service.

Mesmo assim, ainda existem cenarios reais de concorrencia/inconsistencia:

1. double click no frontend;
2. retry automatico do cliente/proxy;
3. timeout apos efeito parcial no backend;
4. duas abas/sessoes do mesmo owner;
5. webhook atrasado/duplicado/fora de ordem;
6. reconciliacao rodando em paralelo com alteracao manual.

Decisao: tratar mutacoes como operacoes idempotentes com controle de versao.

Controles minimos obrigatorios:

1. `operationId` (ou `idempotencyKey`) em toda mutacao.
2. Journal de operacoes por tenant para deduplicacao e replay de resposta.
3. Atualizacao do contrato com compare-and-set por versao (`contractVersion`).
4. Lock curto por tenant durante aplicacao de mutacao critica (lease com expiracao).
5. Processamento de webhook com dedupe por `provider + eventId` e tolerancia a reordenação.
6. Estado intermediario de reconciliacao para operacao ambigua (`pending_reconcile`).

Regra de ouro:

- nenhuma operacao mutavel deve depender de "executar uma vez" por sorte;
- operacoes devem ser seguras para reexecucao sem efeito financeiro duplicado.

## Colecoes Propostas (Firestore)

### billing_plan_catalog

Catalogo interno de planos (fonte de verdade comercial para Asaas e referencia para Stripe).

Campos recomendados:

- `planKey`
- `displayName`
- `workspaceType`
- `baseAmountCents`
- `currency`
- `cycle` (`month` | `year`)
- `includedSeats`
- `extraSeatUnitAmountCents`
- `maxSelfServiceExtraSeats`
- `supportsSelfService`
- `active`
- `version`

### tenant_billing_contracts

Estado contratado por tenant.

Campos recomendados:

- `tenantId`
- `billingProvider`
- `planKey`
- `status`
- `cycle`
- `baseAmountCents`
- `includedSeats`
- `extraSeatsContracted`
- `extraSeatUnitAmountCents`
- `effectiveFrom`
- `currentPeriodStartAt`
- `currentPeriodEndAt`
- `contractVersion`
- `lastAppliedOperationId`
- `updatedAt`

### tenant_billing_seat_changes

Historico de alteracoes de seats.

Campos recomendados:

- `tenantId`
- `changeType` (`add` | `remove` | `support_override`)
- `previousExtraSeats`
- `newExtraSeats`
- `reason`
- `requestedByUid`
- `approvedByUid`
- `createdAt`
- `operationId`
- `billingImpactType` (`next_cycle` | `immediate_invoice` | `credit_next_cycle`)
- `billingImpactAmountCents`

### billing_quotes

Cotacao fechada e assinada no backend antes do checkout.

Campos recomendados:

- `tenantId`
- `provider`
- `planKey`
- `baseAmountCents`
- `extraSeats`
- `extraSeatUnitAmountCents`
- `totalAmountCents`
- `expiresAt`
- `status` (`open` | `used` | `expired` | `canceled`)
- `checksum`
- `operationId`
- `usedAt`
- `usedByCheckoutId`

### billing_provider_refs

Referencias externas por provider.

Campos recomendados:

- `tenantId`
- `stripeCustomerId`
- `stripeSubscriptionId`
- `asaasCustomerId`
- `asaasSubscriptionId`
- `asaasCheckoutId`
- `lastWebhookEventId`
- `lastWebhookEventAt`
- `lastReconciledAt`

### tenant_billing_operations

Journal de operacoes mutaveis para idempotencia e rastreabilidade.

Campos recomendados:

- `tenantId`
- `operationId`
- `operationType` (`create_quote` | `open_checkout` | `change_seats` | `change_plan` | `cancel`)
- `requestHash`
- `status` (`received` | `applied` | `failed` | `pending_reconcile`)
- `responseSnapshot`
- `errorCode`
- `createdAt`
- `updatedAt`

## Endpoints Alvo (Asaas)

1. `createBillingQuote`
   - calcula e persiste cotacao imutavel de checkout.
2. `createBillingCheckoutSession`
   - usa quote valida para abrir checkout Asaas com valor final calculado.
3. `changeTenantSeatPack`
   - altera seats no dominio interno conforme politicas.
4. `previewTenantSeatPackChange`
   - simula impacto financeiro antes de confirmar.
5. `manageTenantBillingSelfService`
   - manter para `stop_renewal` e `cancel_now` no Asaas.

Observacao: para Stripe, manter endpoints atuais e comportamento vigente.

## Politica de Seats

1. Seats incluidos no plano base.
2. Seats extras por unidade contratada.
3. Teto de autoatendimento por plano (`maxSelfServiceExtraSeats`).
4. Acima do teto:
   - bloquear alteracao self-service;
   - orientar abertura de chamado comercial/suporte.

## Politica de Proration

Fase inicial recomendada:

1. Sem proration automatico no MVP.
2. Mudancas valem no proximo ciclo para reduzir risco operacional.

Fase evolutiva:

1. Proration calculado pelo motor interno.
2. Ajuste por cobranca avulsa ou credito no proximo ciclo.

Regras de desenho para futura fase de proration:

1. Formula versionada e auditavel (mesmo input, mesmo output).
2. Simulacao obrigatoria antes de efetivar mudanca.
3. Registro do calculo aplicado no journal da operacao.
4. Idempotencia do ajuste financeiro para evitar cobranca em duplicidade.

## Dunning, Falhas e Recuperacao

1. Definir ciclo de inadimplencia canonico:
   - `active` -> `past_due` -> `suspended` -> `canceled`.
2. Definir quando entitlement cai para cada transicao de estado.
3. Definir retentativas de cobranca e janelas de tolerancia (grace).
4. Definir tratamento para webhook ausente:
   - reconciliacao ativa corrige estado canonico.
5. Definir tratamento para timeout de mutacao:
   - resposta ao cliente deve refletir `pending_reconcile` quando necessario.
6. Definir estrategia de compensacao em erro parcial:
   - estorno/credito/log de incidente conforme tipo de efeito financeiro.

## Ordem de Eventos e Webhooks

1. Nao assumir ordem de chegada do provider.
2. Persistir todos os eventos relevantes antes de aplicar efeitos.
3. Ignorar evento duplicado pelo mesmo `provider + eventId`.
4. Em conflito de ordem, reconciliar por snapshot atual do provider + contrato interno.

## Painel Admin (escopo minimo)

1. CRUD de plano interno para Asaas.
2. Definicao de preco base, seats incluidos e valor por seat extra.
3. Definicao de teto de autoatendimento por plano.
4. Acao assistida para override de seats acima do teto.
5. Auditoria de alteracoes de preco/plano/seats.

## Guard Rails para Nao Quebrar Stripe

1. Nao alterar contrato existente dos fluxos Stripe ja em producao.
2. Isolar regras novas de Asaas no motor interno e no dispatch por provider.
3. Manter reconciliacao e status canonicos em `tenants/{tenantId}`.
4. Cobrir com testes de regressao os cenarios Stripe existentes.

## Fases de Implementacao Recomendadas

### Fase 0 - Documentacao e contrato

1. Fechar este plano e os contratos de dados/endpoints.

### Fase 1 - Catalogo e quote engine (sem proration)

1. Criar colecoes internas.
2. Criar calculo de quote server-side.
3. Conectar checkout Asaas ao quote.

### Fase 2 - Seats e limites

1. Implementar alteracao de seats com teto self-service.
2. Adicionar fluxo de suporte para excecoes.

### Fase 3 - Proration (opcional)

1. Implementar simulacao e cobranca proporcional.

## Criterios de Pronto Antes de Codar

1. Contrato de colecoes aprovado.
2. Regras de preco e limite de seats aprovadas.
3. Regras de suporte para excecoes aprovadas.
4. Plano de regressao Stripe definido.
5. Plano de rollout por tenant/provider definido.
6. Contrato de idempotencia aprovado (`operationId`, dedupe, replay de resposta).
7. Estrategia de controle de versao/lock por tenant aprovada.
8. Matriz de estados de dunning e impacto em entitlement aprovada.
9. Estrategia de webhook fora de ordem/duplicado aprovada.
10. Playbook de erro parcial e `pending_reconcile` aprovado.
