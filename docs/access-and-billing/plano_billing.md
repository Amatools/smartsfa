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

## Diretriz de operacao administrativa (2026-11)

- painel admin deve ter uma visao dedicada de billing por workspace, separada da gestao geral de clientes;
- essa visao precisa listar o owner pagador vinculado ao workspace;
- a ordem de navegacao recomendada no painel admin e exibir `Gestao de Billing` antes de `Gestao de cliente`;
- objetivo: separar governanca de cobranca (tenant-level) da governanca de cadastro de usuarios.

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

## Catalogo de planos base (v1)

Escopo comercial inicial aprovado para evolucao:

- 5 planos base + excedentes.
- 2 tiers para Individual (Base/Pro).
- 2 tiers para Representacoes (Base/Pro).
- 1 plano Enterprise Custom (contrato sob medida).

### Planos base

| Plano | Valor mensal | Limites principais | Fotos de produto | Sincronizacao |
| --- | ---: | --- | --- | --- |
| Individual Base | R$ 69 | 1 empresa, 1 usuario, ate 2.000 SKUs, ate 800 pedidos/mes | nao | 6h + manual |
| Individual Pro | R$ 129 | 1 empresa, ate 3 usuarios, ate 8.000 SKUs, ate 3.000 pedidos/mes | sim | 2h + manual |
| Representacoes Base | R$ 199 | ate 3 representadas, ate 4 usuarios, ate 12.000 SKUs, ate 5.000 pedidos/mes | nao | 2h + manual |
| Representacoes Pro | R$ 399 | ate 12 representadas, ate 10 usuarios, ate 50.000 SKUs, ate 20.000 pedidos/mes | sim | 30min + manual |
| Enterprise Custom | a partir de R$ 1.490 | sob contrato (multiempresa, alto volume, governanca) | sim | sob contrato |

Notas de governanca:

- Representacoes Base: limite duro de 3 representadas e upload de fotos bloqueado.
- Representacoes Pro: upload de fotos habilitado e limite inicial de 12 representadas.
- Enterprise Custom: cobranca por boleto, fluxo fiscal/nota fiscal sob contrato e SLA formal.

### Politica de excedentes (v1)

Excedentes iniciais para protecao de margem:

- representada extra (acima do limite do plano): R$ 24 / representada / mes.
- usuario extra: R$ 19 / usuario / mes.
- armazenamento extra de imagens: R$ 7 / GB / mes.
- pedidos extras: pacote de 1.000 pedidos por R$ 39.

Regras obrigatorias:

1. Plano sem foto: upload bloqueado em qualquer cenario.
2. Plano com foto: ao estourar armazenamento, bloquear apenas novos uploads (sem bloquear operacao de vendas).
3. Excedente recorrente por 2 ciclos deve abrir recomendacao de upgrade no billing.
4. Ultrapassagem critica no ciclo corrente pode gerar cobranca de excedente sem bloqueio imediato de operacao.

## Entitlement por plano (capacidades)

Chaves de capacidade recomendadas para resolver billing no backend sem regra espalhada em UI:

- maxRepresentedCompanies
- canUploadProductImages
- maxUsers
- maxSkus
- maxOrdersPerMonth
- maxImageStorageGb
- syncIntervalMinutes

Diretriz:

- todo gate funcional deve ler entitlement server-side com base em billingPlanKey + status.
- UI apenas exibe limites e bloqueios, sem ser a fonte de verdade.

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

### Configuracao Stripe no painel admin (desenho inicial)

Objetivo:

- permitir operacao segura da integracao Stripe sem depender de script manual.

Acoes minimas no painel admin:

1. configurar credenciais por ambiente (sandbox/producao) via secret manager.
2. mapear produtos e prices Stripe para billingPlanKey interno.
3. configurar modo de cobranca por plano (cartao recorrente, boleto faturado, contrato custom).
4. registrar e validar webhook endpoint por ambiente.
5. visualizar status da conexao (ok/erro, ultimo webhook, ultima reconciliacao).
6. executar reconciliacao manual por tenant em caso de divergencia.

Campos operacionais por tenant (quando aplicavel):

- stripeCustomerId
- stripeSubscriptionId
- stripePriceId
- stripeCheckoutSessionId
- billingPlanKey
- billingStatus
- billingCurrentPeriodStartAt
- billingCurrentPeriodEndAt

Permissoes e seguranca:

- apenas papel admin/maintainer com permissao explicita de billing pode alterar configuracao Stripe.
- toda mudanca deve registrar actorUid, motivo, antes/depois e timestamp.
- valores sensiveis nunca devem ser persistidos em colecoes de app; usar Secret Manager.

Fluxo recomendado (alto nivel):

1. admin configura mapeamento de plans <-> prices no painel.
2. checkout cria sessao Stripe com metadados tenantId + billingPlanKey.
3. webhook atualiza tenant (estado/ciclo) com idempotencia por eventId.
4. rotina diaria de reconciliacao corrige divergencias gateway x Firestore.

Detalhamento completo da integracao:

- stripe_integration_blueprint.md

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

### Fase E - Stripe end-to-end

Entregas:

- configuracao de ambiente/segredos no maintainer com Secret Manager;
- mapeamento de billingPlanKey para product/price por ambiente;
- endpoints de checkout e webhook com assinatura e idempotencia;
- reconciliacao manual por tenant e reconciliacao diaria automatizada;
- trilha de auditoria para mudancas de configuracao e overrides.

Criterio de pronto:

- onboarding de tenant em Stripe sem script manual;
- webhooks processados com idempotencia e sem regressao de estado;
- configuracao de credenciais rotacionavel sem downtime funcional.

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
