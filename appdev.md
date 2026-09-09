# SmartSFA - Plano de Execucao (Checklist)

Este arquivo e o board oficial de acompanhamento do projeto.
Regra de uso: cada item entregue deve ser marcado com [x] e manter evidencias curtas na secao "Log de Execucao".

## Direcao do produto

- [x] Direcao aprovada: plataforma SaaS multi-tenant
- [x] Primeiro tenant real: Amatools
- [x] Integracao Sankhya: adaptador inicial, nao dependencia obrigatoria do produto
- [x] Operacao sem ERP: suportada por carga manual de usuarios, clientes, produtos e tabelas
- [x] Hierarquia da empresa cliente: Tenant > Owner > Gerente > Representante > Vendedor
- [x] Papel acima do Owner: Platform Admin interno do produto, fora da hierarquia comercial do tenant
- [x] Firebase atual classificado como ambiente dev/prototipo
- [x] Login real pode ser adiado sem bloquear desenvolvimento do produto
- [x] Documento central de implementacao criado para guiar uma nova IA ou novo dev
- [x] Resolver de entrada por tenant/membership iniciado no codigo
- [x] Fluxo de convite por token iniciado no codigo (aceite + criacao de membership)
- [x] Convites pendentes exibidos em notificacoes com aceite no app
- [x] Owner/Admin pode criar e revogar convites na tela de notificacoes
- [x] Revalidacao de acesso apos aceite de convite no app shell
- [x] Modulo Tenant com gestao de memberships (listar, revogar, reativar)
- [x] Filtro e busca de memberships por uid, papel e status no modulo Tenant
- [x] Regra de autorizacao fina por papel na tela Tenant (owner/platform admin)
- [x] Testes de widget da tela Tenant para revogar/reativar e restricao de owner
- [x] Alteracao de papel (role) de membership com governanca por perfil
- [x] Trilha de auditoria para revogacao, reativacao e alteracao de papel
- [x] Convites movidos para modulo Tenant (tela dedicada) com envio/gestao owner-only
- [x] Notificacoes focada apenas em convite recebido (aceitar ou recusar)
- [x] Tela de auditoria de memberships com filtros basicos
- [x] Modo pessoal definido como preferencia da conta do usuario (nao governado por owner do tenant)
- [x] Politica do tenant restrita a governanca organizacional (ex.: gerente->representante, representante->vendedor)

## Diretrizes de fluxo (multi-tenant + pessoal)

- [x] Modo pessoal deve continuar acessivel ao usuario fora de qualquer tenant, quando habilitado na propria conta
- [x] Owner pode desligar membership de vendedor no tenant sem bloquear o acesso pessoal da conta
- [x] Tela Tenant nao controla habilitacao de modo pessoal; controle individual fica na aba Conta
- [x] Usuario com multiplos memberships escolhe o contexto de entrada (tenant A, tenant B ou pessoal)
- [ ] Definir oficialmente se criacao de tenant sera self-service (qualquer conta elegivel) ou assistida (somente platform admin)
- [ ] Definir se representante sem membership de tenant pode existir como "workspace pessoal com equipe" (recomendado: nao)

## 0) Validacao de ambiente (hoje)

- [x] Flutter instalado e operacional
- [x] Projeto analisa sem erros (flutter analyze)
- [x] Build debug Android concluido (APK gerado)
- [x] Execucao em navegador Chrome concluida (flutter run -d chrome)
- [x] Tasks locais ajustadas para este workspace

## Tasks de execucao (Markdown)

Use esta secao como checklist operacional do dia a dia.

- [x] Validar ferramentas: flutter --version
- [x] Validar saude do projeto: flutter analyze
- [x] Validar build debug: flutter build apk --debug
- [x] Validar run web: flutter run -d chrome
- [x] Login Firebase CLI na conta correta: firebase login
- [x] Confirmar projetos da conta: firebase projects:list
- [x] Configurar FlutterFire no projeto atual: flutterfire configure --platforms=android,ios,web
- [x] Publicar regras Firestore: firebase deploy --only firestore:rules
- [ ] Criar primeiro owner via script local

## Setup Firebase Auth (Console)

- [ ] Firebase Console > Authentication > Sign-in method > habilitar Google
- [ ] Definir e-mail de suporte do projeto no provider Google
- [ ] Authentication > Settings > Authorized domains (confirmar localhost)
- [x] Preparar pagina inicial e documentos legais (landing, privacidade, termos)
- [x] Publicar paginas legais no Firebase Hosting
- [ ] Firestore: criar/validar usuario Owner inicial (ativo=true, role=owner)
- [ ] Testar login no Chrome com conta autorizada
- [ ] Testar login no Chrome com conta nao autorizada (deve cair em solicitacao)

## Estrategia temporaria de autenticacao

- [x] Adiar login real de producao ate identidade do produto ficar definida
- [x] Criar modo mock/dev auth para liberar desenvolvimento das telas e fluxos
- [x] Simular perfis: platform_admin, owner, gerente, representante, vendedor
- [x] Permitir troca de perfil em ambiente dev para validar fluxos e permissoes visuais

## Decisoes em aberto

- [ ] Regra de preco x10: pendente de validacao com tabela oficial do Sankhya
- [ ] Definir formula final de preco base (temporaria, por tabela, por cliente ou por campanha)
- [ ] Definir se o onboarding do tenant sera manual assistido ou self-service
- [ ] Definir quando habilitar billing/assinatura por tenant
- [ ] Definir politica final de origem unica de produtos por tenant (ERP, Excel ou Manual)
- [ ] Definir fluxo canonico de pre-cadastro de clientes e merge com ERP
- [ ] Definir regra de aprovacao padrao para pre-cadastro em tenants sem ERP
- [ ] Definir fluxo de primeira entrada: convite, solicitacao de acesso ou workspace pessoal

## 1) Requisitos mandatarios de UI responsiva

- [ ] Proibir tamanhos fixos de largura/altura em telas principais
- [ ] Garantir uso de SafeArea em todas as paginas de fluxo
- [ ] Garantir uso de SingleChildScrollView em formularios extensos
- [ ] Garantir uso de Expanded/Flexible em composicoes de linhas e colunas
- [ ] Criar checklist de revisao visual para telas pequenas e medias

## 2) Arquitetura inicial do app (SRP + Offline-First)

- [x] Definir padrao inicial incremental rumo a Clean Architecture
- [x] Criar estrutura base de pastas por modulo
- [x] Separar presentation inicial em arquivos menores e desacoplados
- [ ] Separar camadas: presentation, domain, data, infra, shared
- [ ] Definir padrao de estado para telas (ex: Riverpod/Bloc)
- [x] Definir contrato de repositorios com prioridade local-first
- [ ] Definir tenantId como campo obrigatorio em dados de dominio e acesso
- [ ] Separar contexto de plataforma do contexto de tenant no app e no backend
- [x] Entregar tela inicial de governanca de memberships por tenant

## 3) Dados locais (Isar)

- [ ] Entidade Cliente local com flags: permite_88, permite_885, permite_89
- [ ] Entidade Produto local com preco_base (regra final pendente), estoque e data_versao_preco
- [ ] Entidade FilaPedido com status: pendente_envio, enviado
- [ ] Incluir campos Sankhya no item/fila: AD_DESCLIDER, AD_MANGA1..AD_MANGA4
- [ ] Criar DAOs/repositorios locais para leitura e escrita offline
- [x] Criar implementacao in-memory inicial para Cliente, Produto e Pedido

## 4) Regra comercial (calculo local por item)

- [ ] Implementar preco base com estrategia configuravel (regra x10 pendente de confirmacao)
- [ ] Implementar permissao de desconto lider por cliente
- [ ] Implementar travas de mangas por lider
- [ ] Implementar limites maximos por manga
- [ ] Implementar redutor de comissao quando manga3 > 0 ou manga4 > 0
- [ ] Cobrir com testes unitarios de calculo

## 5) Integracao Firebase (Auth + Firestore)

- [x] Refatorar modelagem para tenantId + plataforma multi-tenant
- [x] Separar Platform Admin de Owner do tenant
- [x] Definir colecao tenants e membership de usuarios por tenant
- [x] Refatorar colecao usuarios com hierarquia: Tenant > Owner > Gerente > Representante > Vendedor
- [x] Refatorar clientes e pedidos com tenantId + vinculos de arvore de acesso
- [x] Refatorar regras Firestore para tenant scope + subordinacao
- [x] Refatorar bootstrap seguro para primeiro tenant e primeiro Owner
- [ ] Refatorar estrategia de claims/perfis no Authentication
- [x] Formalizar vinculo de primeiro acesso por membership e convite, nao por email

## 6) Integracao Sankhya (REST)

- [ ] Definir cliente HTTP com interceptadores e tratamento de erros
- [ ] Definir endpoints de carga inicial (clientes, produtos, politicas)
- [ ] Definir payload de envio de pedidos com campos customizados
- [ ] Criar mapeadores DTO <-> Dominio <-> Local DB
- [ ] Criar estrategia de retry com idempotencia no envio
- [ ] Definir contrato abstrato de ERP provider para suportar outros ERPs no futuro

## 6.1) Operacao sem ERP (manual/self-service)

- [ ] Cadastro manual do tenant sem integracao externa
- [ ] Cadastro manual de usuarios e vinculos hierarquicos
- [ ] Importacao manual de clientes via planilha/CSV
- [ ] Importacao manual de produtos e tabelas de preco via planilha/CSV
- [ ] Configuracao manual de politicas comerciais por tenant
- [ ] Definir template padrao de importacao de produtos por Excel
- [ ] Definir template padrao de importacao de clientes por Excel
- [ ] Definir aprovacao de pre-cadastro por owner/gerente quando nao houver ERP

## 7) Politica de sincronizacao inteligente

- [ ] Sincronizacao pesada diaria de estoque (manha)
- [ ] Endpoint delta apenas estoque (sincronizacao leve)
- [ ] Checagem de versao de preco (timestamp/hash) antes de baixar tabela
- [ ] Bloqueio de uso quando versao de preco divergir
- [ ] Worker de fila para envio automatico ao detectar conectividade

## 8) Notificacoes

- [ ] Configurar Firebase Cloud Messaging (Android/iOS/Web)
- [ ] Persistir notificacoes em area interna (In-App Notifications)
- [ ] Exibir alertas de politica comercial, promocoes e avisos
- [ ] Suportar link externo com validacao de URL segura

## 9) Seguranca e governanca

- [ ] Segregar ambientes: dev, homolog, prod
- [ ] Proteger segredos via .env e CI/CD (nunca hardcode)
- [ ] Auditoria basica de acoes criticas (login, sync, envio pedido)
- [ ] Revisao de regras Firestore com testes de autorizacao
- [ ] Politica de backup/retencao e observabilidade

## 10) Entregaveis tecnicos esperados

- [x] Desenho de estrutura de pastas
- [ ] Atualizacao de pubspec.yaml com dependencias necessarias
- [ ] Implementacao do modulo de calculo comercial (state management)
- [x] Conjunto minimo inicial de testes unitarios do ciclo de convite

## Roadmap por sprint

- [ ] Sprint 1: Fundacao SaaS multi-tenant (tenants, memberships, roles, rules, bootstrap)
- [ ] Sprint 2: Base do app + login + onboarding de acesso + modo manual
- [ ] Sprint 3: Dados locais + modulo de calculo + operacao comercial offline
- [ ] Sprint 4: Integracao Sankhya + fila + sync inteligente
- [ ] Sprint 5: Notificacoes + hardening + testes finais

## Log de Execucao

- 2026-09-09: Ambiente validado, run no Chrome funcionando, build debug Android ok.
- 2026-09-09: Tasks do workspace ajustadas para evitar conflitos de terminal.
- 2026-09-09: Regra de preco x10 movida para decisao pendente no backlog.
- 2026-09-09: Priorizacao alterada para iniciar por acessos e hierarquia.
- 2026-09-09: Criados docs/firebase/acesso_hierarquia.md, firestore.rules e scripts/bootstrap_owner/create_owner.js.
- 2026-09-09: FlutterFire CLI instalada localmente (dart pub global activate flutterfire_cli).
- 2026-09-09: Firebase CLI autenticada com aureo@amatools.com.br.
- 2026-09-09: FlutterFire configure concluido para android, ios e web (projeto smartsfa-f20a0).
- 2026-09-09: Fluxo inicial de login Google + solicitacao de liberacao interna implementado em lib/main.dart.
- 2026-09-09: Regras Firestore reforcadas com usuario ativo e solicitacoes_acesso.
- 2026-09-09: Regras publicadas com sucesso em smartsfa-f20a0 (firestore deploy).
- 2026-09-09: Criados templates legais em docs/legal para uso no Branding OAuth.
- 2026-09-09: Paginas legais publicadas em https://smartsfa-f20a0.web.app.
- 2026-09-09: Direcao do produto alterada para plataforma SaaS multi-tenant com modo manual sem ERP.
- 2026-09-09: Firebase atual mantido como ambiente dev/prototipo e login real movido para etapa posterior.
- 2026-09-09: Documento de transicao criado em docs/architecture_transition.md.
- 2026-09-09: Modo mock/dev auth implementado como padrao temporario no app para liberar desenvolvimento sem OAuth real.
- 2026-09-09: Estrutura base em lib/src criada com shell responsivo e navegacao por perfil.
- 2026-09-09: Documentados SaaS model v2 e estrutura inicial do projeto.
- 2026-09-09: Firestore Rules refatoradas e publicadas para modelo multi-tenant com tenants e tenant_memberships.
- 2026-09-09: Script bootstrap_owner.mjs atualizado para criar tenant + usuario global + membership owner.
- 2026-09-09: Fluxo de autenticacao extraido para src/features/auth e caminho real adaptado ao modelo multi-tenant.
- 2026-09-09: Criados modelos de dominio tenant-aware para Cliente, Produto e Pedido, com contratos de repositorio genéricos.
- 2026-09-09: Implementacao in-memory inicial criada para os repositorios de Cliente, Produto e Pedido.
- 2026-09-09: Registrada proposta de operacao B2B em docs/proposta_operacao_b2b.md com regras de origem unica, pre-cadastro e merge com ERP.
- 2026-09-09: Documentado fluxo de primeira entrada por membership, convite, solicitacao de acesso ou workspace pessoal.
- 2026-09-09: Criado guia central de implementacao em docs/guia_implementacao_saas.md.
- 2026-09-09: Iniciado resolvedor de entrada por membership/tenant no fluxo de auth do app.
- 2026-09-09: Iniciado fluxo de convite por token com aceite na tela de pending access e criacao de membership.
- 2026-09-09: Tela de notificacoes integrada com convites pendentes e aceite explicito de ingresso no tenant.
- 2026-09-09: Adicionado painel owner/admin em notificacoes para criar e revogar convites com expiracao e perfil.
- 2026-09-09: Aceite de convite em notificacoes agora dispara revalidacao de acesso no auth gate.
- 2026-09-09: Criados testes de ciclo de convite (aceite valido, expirado, e-mail divergente e revogado) com FakeFirestore.
- 2026-09-09: Modulo Tenant saiu de placeholder e ganhou tela real com stream de memberships + acoes de revogacao e reativacao.
- 2026-09-09: Criados testes do TenantMembershipService para ciclo revoke/reactivate e filtro por tenant.
- 2026-09-09: Tela Tenant recebeu busca/filtros (uid, papel, status) para operacao com maior volume de usuarios.
- 2026-09-09: Regras de permissao da UI reforcadas: owner nao gerencia owner/platform_admin nem o proprio vinculo; platform_admin com permissao total.
- 2026-09-09: Cobertura de widget adicionada para fluxo de revogacao/reativacao e guard rails de permissao na tela Tenant.
- 2026-09-09: TenantMembershipService ganhou operacao changeRole com validacao de papeis permitidos.
- 2026-09-09: Alteracoes criticas de membership passaram a gravar auditoria em tenant_membership_audit.
- 2026-09-09: Fluxo de convites refatorado: envio e gerenciamento sairam de Notificacoes e foram para Tenant > Convites.
- 2026-09-09: Regra reforcada no service: somente owner ativo do tenant pode criar ou revogar convite.
- 2026-09-09: Notificacoes agora exibe apenas convites pendentes para o usuario, com opcoes de aceitar ou recusar.
- 2026-09-09: Entregue tela Tenant > Auditoria de memberships com busca por ator, acao e membershipId.

