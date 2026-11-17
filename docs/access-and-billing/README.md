# Acesso e Billing - Índice Consolidado

Este diretório concentra os documentos oficiais de autenticação, autorização, billing e entitlement do SmartSFA.

## Ordem de leitura recomendada

1. workspace_access_billing_policy.md
2. plano_login_acesso.md
3. plano_billing.md
4. account_workspace_deletion_policy.md
5. stripe_integration_blueprint.md
6. stripe_firestore_functions_contract.md
7. billing_unified_provider_contract.md
8. asaas_internal_billing_engine_plan.md
9. asaas_internal_billing_execution_backlog.md
10. stripe_configuracao_comandos.md
11. asaas_configuracao_comandos.md
12. asaas_webhooks_configuracao_detalhada.md

## Papel de cada documento

### workspace_access_billing_policy.md

Contrato macro de produto e engenharia para:

- tipos de workspace;
- regras gerais de acesso;
- política online/offline;
- política de provedores de login;
- dados mínimos obrigatórios (LGPD + Stripe).

### plano_login_acesso.md

Plano executável de autenticação/autorização:

- fluxos de login cliente/admin;
- governança por membership;
- requisitos de suporte assistido;
- fases e critérios de pronto.

### plano_billing.md

Plano executável de billing/entitlement:

- máquina de estados;
- bloqueios por status;
- integração Stripe;
- operação admin e auditoria.

### account_workspace_deletion_policy.md

Politica operacional de encerramento/exclusao:

- exclusao de conta de usuario (self-service/admin);
- encerramento e exclusao definitiva de workspace;
- guard rails de confirmacao, reautenticacao e auditoria;
- janela de seguranca, idempotencia e retencao legal.

### stripe_integration_blueprint.md

Blueprint operacional de Stripe do zero:

- dados e IDs que precisam ser levantados no Stripe;
- desenho de tela no painel maintainer para configuração;
- padrões de segurança para segredos/chaves/webhooks;
- sequência de implementação backend + reconciliação.

### stripe_firestore_functions_contract.md

Contrato técnico da implementação Stripe:

- estrutura exata das coleções Firestore de integração;
- contrato dos endpoints/functions (checkout, webhook, reconciliação);
- regras obrigatórias de segurança, idempotência e auditoria.

### billing_unified_provider_contract.md

Contrato de arquitetura para multi-provider de cobrança:

- define camada única de cobrança para Stripe/Asaas;
- padroniza `billingProvider` no tenant e dispatch por provider;
- mantém regras comuns (acesso, auditoria e seat governance) fora do provider.

### asaas_internal_billing_engine_plan.md

Plano de decisao pre-implementacao para Asaas:

- consolida que Stripe segue no fluxo nativo atual;
- define que Asaas exige motor interno de billing para preco, seats e limites;
- propõe colecoes, endpoints e fases para evolucao sem quebrar Stripe.

### asaas_internal_billing_execution_backlog.md

Backlog tecnico executavel para implementar o motor interno Asaas:

- epicos e tarefas por dominio;
- ordem de entrega por sprint;
- criterios de aceite e gates de regressao Stripe;
- riscos operacionais e mitigacoes.

### stripe_configuracao_comandos.md

Guia operacional por comandos com placeholders para configuração segura:

- cadastro de segredos Stripe no Secret Manager;
- deploy das functions de billing;
- configuração do webhook e eventos;
- cadastro de planos por seção (individual, representações, enterprise).

### asaas_configuracao_comandos.md

Guia operacional por comandos para a preparacao da integracao Asaas:

- cadastro de segredos Asaas no Secret Manager;
- configuracao de webhook por ambiente;
- preenchimento dos metadados no Maintainer e selecao de provider no API Checkout.

### asaas_webhooks_configuracao_detalhada.md

Guia detalhado de Webhook Asaas para operacao segura:

- payload de criacao do webhook (sandbox e producao);
- lista de eventos obrigatorios e opcionais por contexto;
- validacao de autenticacao, idempotencia e ordem de entrega;
- diferenca entre Split de pagamento e pagamento com mais de um metodo.

## Decisões consolidadas (resumo)

1. Login Google é preferencial; e-mail/senha é secundário.
2. Login concluído não implica acesso ao tenant sem membership ativa.
3. Mobile pode operar offline com sessão válida; ao voltar online, deve revalidar plano.
4. Sem plano ativo, web pode abrir checkout/billing, mas não módulos operacionais.
5. Entitlement e bloqueios devem ser validados no backend.
6. CPF e data de nascimento não são coleta padrão global.
7. Modelo comercial v1: 5 planos base (Individual Base/Pro, Representações Base/Pro, Enterprise Custom) + política de excedentes.

## Checklist de início de implementação

1. Validar estrutura de dados obrigatória em tenants, usuários e memberships.
2. Implantar serviço de entitlement único para web/mobile.
3. Garantir gates server-side para módulos operacionais.
4. Implementar fluxo de checkout/billing liberado mesmo sem plano ativo (web).
5. Estruturar logs de auditoria e idempotência de webhooks Stripe.
6. Executar testes de regressão com cenários online/offline.
