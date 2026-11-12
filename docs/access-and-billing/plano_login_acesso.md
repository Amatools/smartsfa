# SmartSFA - Plano de Implementacao Login e Acesso

## Objetivo

Definir o plano executavel para fechar autenticacao, autorizacao e governanca de acesso do produto.

Meta final:

- login previsivel para cliente e admin;
- controle por membership como fonte de verdade;
- bloqueio de uso indevido por tenant e por papel;
- operacao segura via painel admin com auditoria completa.

## Referencias canonicas

Este plano complementa (nao substitui):

- ../auth_access_model.md
- workspace_access_billing_policy.md
- ../guia_implementacao_saas.md
- ../web_portal_architecture.md

## Escopo

Dentro do escopo:

- login cliente e login admin separados por entrada de URL/modo;
- selecao e troca de workspace por membership ativo;
- aceite de convite e solicitacao de acesso;
- governanca de permissao por papel e override no painel admin;
- auditoria de acoes criticas;
- suporte assistido (impersonation) com sessao temporaria e rastreavel.

Fora do escopo:

- cobranca financeira (vai para plano_billing.md);
- novas features de negocio fora do controle de acesso;
- redesign visual amplo sem impacto funcional.

## Principios

1. Membership e a fonte de verdade de acesso.
2. Regras de backend e regras de UI devem ser equivalentes.
3. Nenhuma inferencia de acesso por email ou CNPJ.
4. Toda acao critica gera trilha de auditoria.
5. Fluxo assistido sempre com prazo curto e one-time.

## Modelo de entidades

Entidades principais:

- usuarios/{uid}
- tenants/{tenantId}
- tenant_memberships/{membershipId ou tenantId_uid}
- tenant_invitations/{token}
- solicitacoes_acesso/{uid}
- platform_user_admin_profiles/{uid}
- platform_admin_audit/{docId}
- platform_impersonation_sessions/{sessionId}

## Matriz de estado de acesso

Estados de membership:

- pending
- active
- inactive
- revoked

Regra geral:

- somente active + ativo=true habilita entrada no workspace.

## Fluxos obrigatorios

### 1. Login cliente

1. Usuario autentica.
2. App resolve memberships ativas.
3. Se houver 1 ativa, entra direto.
4. Se houver varias, exibe seletor.
5. Se nao houver, envia para pending access.

### 2. Login admin

1. Entrada admin detectada por host/path/fragment/query.
2. Usuario autentica.
3. Sistema valida role de plataforma e flags de console.
4. Libera painel ou retorna acesso negado.

### 3. Convite

1. Usuario informa token.
2. Sistema valida status/expiracao/email.
3. Cria ou atualiza membership.
4. Marca convite como accepted.
5. Atualiza acesso sem exigir logout.

### 4. Solicitacao de acesso

1. Usuario sem membership gera solicitacao.
2. Owner/admin aprova ou rejeita.
3. Em aprovacao, membership ativa e usuario entra no fluxo.

### 5. Acesso assistido (suporte)

1. Admin seleciona usuario + tenant + membership + motivo.
2. Backend cria sessao one-time com expiracao curta.
3. Janela assistida consome sessao e recebe custom token.
4. Auditoria registra criacao e consumo.
5. Sessao nao pode ser reutilizada.

## Politica de acesso offline/online

### Mobile

1. Offline: permitir uso com sessao local valida e cache local.
2. Online novamente: revalidar imediatamente membership + entitlement de billing.
3. Se plano inativo: bloquear uso operacional e redirecionar para regularizacao.

### Web

1. Se plano inativo: bloquear modulos operacionais.
2. Manter acesso ao fluxo de billing/checkout e telas de regularizacao.
3. Exibir motivo de bloqueio com orientacao objetiva de reativacao.

## Provedores de login e onboarding

Direcao atual:

- Google como metodo preferencial;
- email/senha como opcao secundaria (se mantida habilitada).

Com Google login:

1. Primeiro login cria/atualiza perfil minimo em usuarios/{uid}.
2. Nao ha etapa de confirmacao de email dentro do app.
3. Usuario ainda precisa entrar no fluxo de acesso (convite, solicitacao ou criacao permitida).
4. Sem membership ativa, o usuario nao entra em modulo operacional.

Controles complementares recomendados:

- aceite de termos/politicas na primeira entrada;
- registro de consentimento e timestamp;
- trilha de auditoria para alteracoes de acesso.

## Dados mínimos para implementação de acesso

### Perfil de conta (obrigatório)

Persistir no mínimo:

- uid
- email
- displayName
- authProvider
- createdAt / updatedAt

### Autorização por tenant (obrigatório)

Persistir no mínimo:

- membershipId
- tenantId
- uid
- role
- state
- ativo

### Consentimento e evidências (obrigatório)

Registrar no mínimo:

- versão de termos/políticas aceitas
- timestamp de aceite
- actorUid
- evento de acesso relevante (login, bloqueio, troca de estado)

### Dados pessoais sensíveis (restrição)

Não coletar por padrão no ciclo de login:

- CPF
- data de nascimento

Exceção:

- somente quando houver necessidade legal/fiscal específica e base legal definida.

## Controles no painel admin

Minimo obrigatorio:

- listar usuarios e memberships;
- alterar papel/estado de membership;
- bloquear auto-exclusao da propria conta admin;
- editar matriz de permissao por grants/denies;
- iniciar acesso assistido com motivo e duracao;
- visualizar auditoria critica com filtros.

## Roadmap de implementacao

### Fase A - Estabilizacao de login

Entregas:

- separar rotas cliente/admin e fallback consistente;
- garantir que sair da janela assistida nao execute signOut global;
- fechar mensagens de erro de autenticacao por contexto.

Criterio de pronto:

- nenhum logout inesperado entre abas no fluxo nominal.

### Fase B - Hardening de autorizacao

Entregas:

- validar acesso sempre por membership ativa;
- revisar todos os pontos de entrada de tenant no app;
- bloquear operacoes fora do tenant ativo.

Criterio de pronto:

- acesso cruzado entre tenants deve falhar em UI e backend.

### Fase C - Governanca admin

Entregas:

- finalizar matriz de permissao de maintainer;
- aplicar guardrails por permissao em cada acao critica;
- consolidar auditoria admin-only.

Criterio de pronto:

- cada acao critica exige permissao explicita e deixa trilha.

### Fase D - Operacao assistida segura

Entregas:

- sessoes temporarias one-time com expiracao;
- erro transacional sem consumir sessao em falha interna;
- bloqueio de self-impersonation.

Criterio de pronto:

- reuso de link sempre bloqueado e auditado.

## Testes obrigatorios

### Funcionais

- login cliente com 0, 1 e N memberships;
- login admin autorizado e nao autorizado;
- convite valido, expirado e revogado;
- solicitacao de acesso e aprovacao;
- acesso assistido com sucesso e com expiracao.

### Seguranca

- tentativa de leitura/escrita fora do tenant;
- tentativa de elevar papel sem permissao;
- tentativa de consumir sessao assistida duas vezes;
- tentativa de admin apagar propria conta.

### Regressao

- web + android com o mesmo contrato de acesso;
- sem quebra de sessoes normais de cliente.

## Telemetria e auditoria

Eventos minimos:

- auth_login_success
- auth_login_denied
- membership_state_changed
- invitation_accepted
- maintainer_permission_changed
- impersonation_session_started
- impersonation_session_consumed

## Checklist de go-live

1. Regras Firestore publicadas e testadas.
2. Funcoes de acesso assistido publicadas e validadas.
3. Permissoes IAM para custom token conferidas.
4. Auditoria admin-only funcionando.
5. Testes de regressao web/mobile concluido.
6. Runbook de suporte publicado.
