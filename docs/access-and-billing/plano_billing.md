# SmartSFA - Plano de Implementacao Billing e Entitlement

## Objetivo

Definir o esquema de billing e de entitlement para controlar uso real do produto e habilitar operacao via painel admin.

Meta final:

- acesso do tenant controlado por estado de assinatura;
- transicoes auditaveis e previsiveis;
- operacao manual assistida no admin sem bypass inseguro;
- base pronta para integrar gateway de cobranca.

## Referencias canonicas

Este plano complementa (nao substitui):

- workspace_access_billing_policy.md
- ../auth_access_model.md
- ../guia_implementacao_saas.md

## Escopo

Dentro do escopo:

- modelo de estado de billing;
- regras de entitlement por estado;
- transicoes manuais e automaticas;
- auditoria de alteracoes;
- operacao de billing no painel admin.

Fora do escopo:

- escolha definitiva de gateway financeiro;
- emissao fiscal detalhada;
- BI financeiro avancado.

## Fonte de verdade

Entidade primaria: tenants/{tenantId}

Campos canonicamente necessarios:

- billingPlanKey
- billingStatus
- billingCycle
- billingCurrentPeriodStartAt
- billingCurrentPeriodEndAt
- billingGracePeriodDays
- billingGraceUntilAt
- billingPastDueSinceAt
- billingSuspendedAt
- billingDelinquencyStage
- billingUpdatedAt

Campos auxiliares em usuarios/{uid} (visao de conta):

- billingAccountState
- billingGraceUntilAt
- billingSuspendedAt
- billingUpdatedAt

## Dados mínimos de billing (Stripe)

### Dados da conta pagadora (tenant)

Obrigatórios para operação B2B:

- razaoSocial
- cnpj
- enderecoFiscal
- emailFinanceiro
- nomeContatoFinanceiro

### Identificadores de integração Stripe

Obrigatórios para reconciliação:

- stripeCustomerId
- stripeSubscriptionId
- stripePriceId
- stripeInvoiceId (quando houver)
- stripePaymentIntentId (quando houver)
- stripeCheckoutSessionId (quando houver)

### Webhooks e idempotência

Obrigatório manter:

- registro de eventId processado
- timestamp de processamento
- status de processamento (success/error/retry)

### Dados que não devem ser armazenados no app

- dados completos de cartão
- CVV
- qualquer segredo de pagamento do cliente

Esses dados devem permanecer exclusivamente na Stripe.

## Maquina de estados

Estados recomendados:

- trial
- active
- past_due
- grace
- suspended
- canceled

Regras base:

1. trial -> active quando contrato/assinatura inicia.
2. active -> past_due quando pagamento falha e vence prazo.
3. past_due -> grace quando politica de tolerancia entra.
4. grace -> suspended quando grace expira sem regularizacao.
5. suspended -> active quando regulariza.
6. qualquer estado -> canceled por encerramento formal.

## Entitlement por estado

### trial

- acesso completo com limites de trial configuraveis.

### active

- acesso completo conforme plano.

### past_due

- acesso com aviso e possivel bloqueio de acoes nao criticas.

### grace

- acesso reduzido, com bloqueio progressivo configuravel.

### suspended

- bloqueio operacional para usuarios finais;
- manter acesso minimo de owner/admin para regularizacao.

### canceled

- sem operacao ativa;
- leitura/exportacao conforme politica de retencao.

## Regras por canal (mobile e web)

### Mobile offline-first

- offline: uso permitido com sessao/caches validos apos autenticacao previa;
- ao voltar online: revalidar billingStatus imediatamente no backend;
- se status inativo: bloquear operacao e redirecionar para regularizacao.

### Web

- usuario sem plano ativo pode acessar telas de billing/checkout;
- usuario sem plano ativo nao pode acessar modulos operacionais do sistema.

### Definicao pratica de plano inativo

Para bloqueio operacional, considerar inativo no minimo:

- suspended
- canceled
- no_plan

Observacao:

- past_due e grace podem operar sob politica de degradacao, conforme risco e estrategia comercial.

## Regras obrigatorias de seguranca

1. Entitlement sempre validado server-side.
2. UI nao pode ser unica barreira de bloqueio.
3. Mudancas de status exigem trilha de auditoria.
4. Acao manual de override deve expirar e ser rastreada.

## Operacoes no painel admin

Acoes minimas:

- alterar billingStatus;
- conceder grace temporario (dias);
- normalizar billing (voltar para active);
- suspender billing;
- visualizar historico de transicoes e ator;
- filtrar por tenant, status e periodo.

Guardrails:

- permissao dedicada para cada acao;
- justificativa obrigatoria nas acoes criticas;
- bloquear auto-aprovacao quando houver conflito de funcao.

## Arquitetura de eventos

Entradas de mudanca de estado:

- webhook do provedor de pagamento;
- rotina de reconciliacao diaria;
- acao manual do admin com justificativa.

Requisitos:

- idempotencia por eventId;
- ordem consistente por tenant;
- retry com dead-letter para falhas.

## Roadmap de implementacao

### Fase A - Fundacao de estado

Entregas:

- consolidar campos de billing no tenant;
- backfill de legados;
- validações de consistencia.

Criterio de pronto:

- todos os tenants com estado valido e timestamp de update.

### Fase B - Entitlement tecnico

Entregas:

- middleware/service de entitlement unificado;
- gates de leitura/escrita por estado;
- mensagens de bloqueio por contexto.

Criterio de pronto:

- transicao de estado reflete no app sem bypass.

### Fase C - Operacao admin

Entregas:

- tela de billing no maintainer;
- comandos manuais com auditoria;
- filtros operacionais.

Criterio de pronto:

- time operacional resolve casos sem script manual.

### Fase D - Integracao financeira

Entregas:

- adapter de gateway com webhooks;
- reconciliacao agendada;
- tratamento de eventos fora de ordem.

Criterio de pronto:

- divergencia entre gateway e tenant abaixo de limite alvo.

## Testes obrigatorios

### Funcionais

- transicao valida de todos os estados;
- bloqueio e desbloqueio de acesso por estado;
- grace period com expiracao.

### Resiliencia

- evento duplicado nao duplica transicao;
- evento atrasado nao regride estado indevidamente;
- erro temporario reprocessa com sucesso.

### Seguranca

- usuario sem permissao nao altera billing;
- trilha de auditoria completa com actorUid e motivo.

## Indicadores operacionais

Minimos sugeridos:

- tenants por billingStatus;
- taxa de conversao trial -> active;
- tempo medio em past_due/grace;
- suspensoes por periodo;
- reativacoes apos suspensao.

## Checklist de go-live

1. Politica de estados aprovada por produto e financeiro.
2. Entitlement server-side habilitado em rotas criticas.
3. Painel admin com permissoes e auditoria ativo.
4. Rotina de reconciliacao em producao.
5. Alertas de anomalia de billing configurados.
6. Runbook de incidentes de cobranca publicado.
