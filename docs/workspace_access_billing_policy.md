# SmartSFA - Politica Central de Workspace, Acesso e Billing

## Objetivo

Centralizar em um unico documento as regras de:

- tipos de workspace;
- criacao de workspace por login;
- comportamento de accountContractLock;
- entrada por convite;
- status atual de billing/plano.

Este arquivo e a fonte de verdade para decisoes de produto e implementacao nesse tema.

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
