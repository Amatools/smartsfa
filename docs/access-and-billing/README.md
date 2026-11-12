# Acesso e Billing - Índice Consolidado

Este diretório concentra os documentos oficiais de autenticação, autorização, billing e entitlement do SmartSFA.

## Ordem de leitura recomendada

1. workspace_access_billing_policy.md
2. plano_login_acesso.md
3. plano_billing.md

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

## Decisões consolidadas (resumo)

1. Login Google é preferencial; e-mail/senha é secundário.
2. Login concluído não implica acesso ao tenant sem membership ativa.
3. Mobile pode operar offline com sessão válida; ao voltar online, deve revalidar plano.
4. Sem plano ativo, web pode abrir checkout/billing, mas não módulos operacionais.
5. Entitlement e bloqueios devem ser validados no backend.
6. CPF e data de nascimento não são coleta padrão global.

## Checklist de início de implementação

1. Validar estrutura de dados obrigatória em tenants, usuários e memberships.
2. Implantar serviço de entitlement único para web/mobile.
3. Garantir gates server-side para módulos operacionais.
4. Implementar fluxo de checkout/billing liberado mesmo sem plano ativo (web).
5. Estruturar logs de auditoria e idempotência de webhooks Stripe.
6. Executar testes de regressão com cenários online/offline.
