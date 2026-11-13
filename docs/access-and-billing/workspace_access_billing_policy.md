# SmartSFA - Politica Central de Workspace, Acesso e Billing

## Objetivo

Centralizar em um unico documento as regras de:

- tipos de workspace;
- criacao de workspace por login;
- comportamento de accountContractLock;
- entrada por convite;
- status atual de billing/plano.

Este arquivo e a fonte de verdade para decisoes de produto e implementacao nesse tema.

## Escopo dos documentos de referencia

Para o tema acesso + billing, os 3 arquivos oficiais sao:

- workspace_access_billing_policy.md: politica central e regras gerais.
- plano_login_acesso.md: plano executavel de autenticacao/autorizacao.
- plano_billing.md: plano executavel de billing/entitlement.

Regra de governanca:

- este arquivo define o contrato macro;
- os dois planos detalham execucao, fases e criterios de pronto;
- em caso de conflito, atualizar os 3 em conjunto no mesmo PR.

## Tipos oficiais de workspace

| workspaceType | Uso principal | Convites | Papel inicial recomendado |
| --- | --- | --- | --- |
| seller_solo_workspace | uso individual, base privada | nao | vendedor |
| rep_workspace | escritorio de representacao, equipe comercial | sim (representante e vendedor) | owner |
| brand_owner_workspace | tenant oficial da marca, cadeia completa | sim (hierarquia completa) | owner |

Regras estruturais:

- mesmo nome/CNPJ pode existir em workspaces diferentes sem vinculo automatico;
- CNPJ em seller_solo_workspace e rep_workspace e informativo;
- vinculo juridico de CNPJ contratante e exclusivo de brand_owner_workspace.

## Regras de conta por login

### accountContractLock

- flexible: permite operar em contextos Individual, Representacoes e convites, respeitando as demais regras.
- enterprise_only: restringe o login ao contexto enterprise e convites compativeis.

### Criacao de workspace Empresa

Regra oficial:

- criar workspace Empresa (brand_owner_workspace) so e permitido quando o login ainda nao possui nenhum workspace ativo.
- se o login ja possui workspace ativo, a opcao Empresa nao deve aparecer na UI.
- para entrar em outro enterprise existente, o caminho correto e convite.

### Limite de workspace Individual

Regra oficial:

- maximo de 1 workspace Individual por login.

## Matriz de permissoes de onboarding/adicao

| Condicao do login | Criar Individual | Criar Representacoes | Criar Empresa | Entrar por convite |
| --- | --- | --- | --- | --- |
| Sem workspace ativo + flexible | sim | sim | sim | sim |
| Com workspace ativo + flexible | sim (se ainda nao tiver Individual) | sim | nao | sim |
| Sem workspace ativo + enterprise_only | nao | nao | sim | sim |
| Com workspace ativo + enterprise_only | nao | nao | nao | sim |

Observacoes:

- convite pode ser recusado por regra de lock quando o tenant de destino nao for compativel;
- regras de UI e backend devem ser equivalentes (nao apenas esconder botao).

## Arquitetura unica (Web + Android + iOS)

Regra de produto e engenharia:

- a arquitetura funcional e a mesma para todos os clientes (web, Android e iOS);
- regras de acesso, hierarquia e billing sao centralizadas em servicos compartilhados e Firestore rules;
- diferencas por plataforma devem existir somente na apresentacao (view/ux), nunca na regra de negocio.

Consequencia pratica:

- qualquer mudanca de hierarquia, convite ou billing precisa refletir no backend/rules e ficar valida para todas as plataformas no mesmo contrato.

## Politica de acesso por plano (online e offline)

### Mobile offline-first

- o usuario pode continuar operando offline com sessao valida e cache local apos um login valido anterior;
- ao recuperar conectividade, o app deve revalidar imediatamente entitlement e status de billing no backend;
- se o plano estiver inativo no momento da revalidacao online, o app deve bloquear uso operacional.

### Definicao de plano inativo

Considerar inativo (bloqueio operacional) quando billingStatus for, no minimo:

- suspended
- canceled
- no_plan

### Web sem plano ativo

- no web, usuario sem plano ativo pode acessar fluxo de billing/checkout para regularizacao;
- rotas operacionais do sistema (modulos de negocio) devem permanecer bloqueadas enquanto o plano estiver inativo.

### Regra de implementacao

- bloqueio sempre validado server-side;
- UI apenas reflete o estado de entitlement;
- toda mudanca de estado deve ficar auditada.

## Decisao operacional atual (2026-11)

### Controle de billing por papel

- billing e sempre atrelado ao workspace (tenant), nao ao usuario isolado;
- o owner do workspace e o responsavel por contratar/alterar plano e manter pagamento;
- usuarios convidados no tenant nao devem alterar plano;
- no maximo, convidados podem visualizar resumo de plano/status em modo leitura.

### Papel platform_admin

- manter `platform_admin` como papel de contingencia (break-glass) para suporte operacional;
- uso diario de billing no portal do cliente permanece no owner do tenant;
- permissao de `platform_admin` pode evoluir no futuro sem quebrar o modelo atual de ownership.

## Fluxo esperado no produto

### Primeiro acesso

Se nao houver membership ativo:

1. entrar com convite;
2. solicitar acesso;
3. criar workspace dentro da matriz acima.

### Adicionar workspace com login ja ativo

O seletor de workspace deve oferecer:

- troca de workspace ativo;
- acao Adicionar workspace;
- opcao de entrar por convite.

A opcao de criar Empresa nao aparece quando o login ja possui workspace ativo.

## Estado de implementacao (2026-10)

Implementado:

- seletor mobile com Adicionar workspace e caminho para convite;
- seletor web com Adicionar workspace;
- bloqueio de criacao Empresa na UI quando ja existe workspace ativo;
- bloqueio no servico para impedir criacao Empresa quando ja existe workspace ativo;
- limite de 1 workspace Individual por login;
- restricoes de accountContractLock enterprise_only para criacao/aceite nao compativeis.

Pontos de codigo relacionados:

- auth gate mobile e menu de troca/adicao: lib/src/features/auth/presentation/pages/firebase_auth_gate_page.dart
- onboarding/criacao/join: lib/src/features/auth/presentation/pages/pending_access_page.dart
- regras de criacao de workspace: lib/src/features/auth/services/solo_workspace_service.dart
- regras de aceite de convite: lib/src/features/auth/services/tenant_invitation_service.dart
- seletor de workspace web: lib/src/features/portal/presentation/pages/web_portal_shell_ui_sections.dart
- acao web para abrir onboarding de adicao: lib/src/features/portal/presentation/pages/web_portal_shell_state_section.dart

## Billing e plano (status)

Situacao atual:

- ainda nao existe motor completo de billing (assinatura, ciclo, cobranca e conciliacao);
- existe base de parametrizacao por workspace (planTier e feature flags) para controle funcional;
- o controle financeiro real ainda nao e a fonte de verdade das permissoes.

### Campos canônicos de billing

Fonte de verdade operacional recomendada: tenant (workspace). Usuario guarda apenas estado de conta global.

Em tenants/{tenantId}:

- planTier
- billingScope
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

Em usuarios/{uid}:

- billingAccountState
- billingGraceUntilAt
- billingSuspendedAt
- billingUpdatedAt

Status de implementacao atual:

- novos workspaces passam a ser criados com seed desses campos;
- existe script de backfill para preencher tenants/usuarios legados sem quebrar cadastros;
- a logica de bloqueio financeiro fino (ex.: grace e suspensao por atraso) ainda sera conectada ao motor de billing completo.

Direcao recomendada:

1. definir fonte de verdade de billing por workspace (ou por conta, com regra explicita);
2. vincular mudancas de plano a transicoes auditaveis de feature flags;
3. manter esta politica como contrato entre Produto, UX e Backend.

## Provedores de login e ciclo de cadastro

Direcao de produto atual:

- login Google como caminho preferencial;
- login por email/senha pode existir como opcao secundaria, sob governanca de seguranca.

Com login Google:

- nao ha etapa propria de confirmacao de email dentro do app;
- ainda existe onboarding de acesso (convite, solicitacao ou criacao permitida);
- criar conta autenticada nao implica acesso automatico a tenant.

LGPD e dados sensiveis:

- preferir login federado reduz superficie de tratamento de credenciais no produto;
- mesmo com login federado, dados pessoais de perfil e auditoria devem seguir base legal e minimizacao.

## Dados mínimos indispensáveis (LGPD + operação SaaS)

Esta seção define o mínimo de dados a coletar e manter para operar o SmartSFA com segurança jurídica e técnica.

### 1. Identificação do usuário operacional (obrigatório)

Em usuarios/{uid}:

- uid
- email
- displayName (ou nome de exibição)
- authProvider (google.com, password, etc.)
- createdAt
- updatedAt

Finalidade:

- autenticação, suporte, rastreabilidade e segurança da conta.

### 2. Vínculo de acesso (obrigatório)

Em tenant_memberships:

- membershipId
- tenantId
- uid
- role
- state
- ativo

Finalidade:

- autorização por tenant e segregação de acesso.

### 3. Evidências de consentimento e auditoria (obrigatório)

Coleções/eventos de auditoria:

- versão de termos/política aceita
- timestamp de aceite
- actorUid
- ação
- contexto mínimo (tenant, membership, sessão)

Finalidade:

- conformidade, resposta a incidentes e trilha de governança.

### 4. Dados mínimos de billing B2B (obrigatório para cobrança)

Por tenant (conta pagadora):

- razão social
- CNPJ
- endereço fiscal
- e-mail financeiro
- contato financeiro (nome)

Finalidade:

- contratação, faturamento e comunicação financeira.

### 5. Identificadores Stripe (obrigatório para integração)

Por tenant:

- stripeCustomerId
- stripeSubscriptionId
- stripePriceId
- stripeDefaultPaymentMethodId (quando aplicável)
- billingStatus e períodos (início/fim)
- último webhook processado + tabela de idempotência por eventId

Finalidade:

- sincronização de assinatura, cobrança e prevenção de duplicidade.

### 6. Dados que NÃO devem ser padrão global

- CPF de todos os usuários operacionais
- data de nascimento de todos os usuários operacionais
- dados de cartão fora da Stripe

Somente coletar CPF/data de nascimento quando houver necessidade legal/fiscal explícita para o caso de uso.

## Bases legais LGPD (referência operacional)

Matriz recomendada para o cenário SaaS B2B:

- autenticação e controle de acesso: execução de contrato.
- auditoria de segurança e trilha administrativa: legítimo interesse e prevenção à fraude.
- cobrança, faturamento e dados fiscais do tenant: execução de contrato e obrigação legal/regulatória.
- suporte e resposta a incidentes: legítimo interesse e execução de contrato.

Observação:

- a definição final deve ser validada com jurídico e DPO, incluindo política de retenção e descarte.

## Decisão de onboarding com login Google

Com login Google como método preferencial:

- não é necessário fluxo próprio de confirmação de e-mail;
- primeiro login cria/atualiza perfil mínimo de conta;
- autenticação concluída não implica acesso automático ao tenant;
- acesso depende de membership ativa (convite/solicitação/criação permitida).
