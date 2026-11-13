# Politica de Exclusao de Conta e Workspace

Status: proposta executavel para producao
Escopo: conta de usuario, encerramento de workspace e exclusao definitiva de workspace
Relacionados: workspace_access_billing_policy.md, plano_login_acesso.md, plano_billing.md

## Objetivo

Definir um fluxo seguro para:

1. exclusao de conta de usuario;
2. encerramento de workspace por owner;
3. exclusao definitiva de workspace com governanca, auditoria e compliance.

A proposta equilibra:

1. direito do titular de encerrar/excluir;
2. obrigacoes de retencao legal e rastreabilidade;
3. seguranca operacional (evitar exclusao acidental/maliciosa).

## Principios

1. Acao destrutiva deve ser explicita, dificil de executar por engano e auditavel.
2. Encerramento e exclusao definitiva sao acoes diferentes.
3. Excluir nao significa necessariamente apagar 100% de todos os registros se houver obrigacao legal de retencao.
4. Owner pode solicitar encerramento/exclusao do proprio workspace.
5. Platform admin pode executar break-glass com motivo obrigatorio.

## Taxonomia de acoes

### 1) Desativar conta (reversivel)

Efeito:

1. bloqueia login e uso de modulos;
2. preserva dados e historico;
3. pode ser revertida por admin.

Uso recomendado:

1. bloqueio operacional;
2. saida de colaborador;
3. investigacao de incidente.

### 2) Excluir conta de usuario (permanente, escopo usuario)

Efeito:

1. remove dados pessoais da conta;
2. anonimiza referencias historicas quando necessario;
3. preserva somente o minimo legal/auditoria.

Pre-condicoes:

1. se for owner unico de algum tenant, deve transferir ownership antes;
2. reautenticacao recente + MFA quando habilitado;
3. confirmacao digitada.

### 3) Encerrar workspace (reversivel por janela)

Efeito:

1. muda estado do workspace para encerramento pendente;
2. bloqueia modulos operacionais para usuarios do tenant;
3. mantem acesso restrito para faturamento/exportacao/compliance;
4. cancela ou pausa billing conforme politica Stripe.

Caracteristica:

1. possui janela de seguranca (ex.: 7 ou 30 dias) para desfazer.

### 4) Excluir workspace definitivamente (irreversivel apos janela)

Efeito:

1. purge/anonimizacao de dados operacionais do tenant;
2. remocao de memberships ativas;
3. finalizacao de integracoes (Stripe, ERP, webhooks, tokens);
4. preservacao minima de evidencias legais/auditoria.

Caracteristica:

1. executa por job assinado e auditado, nao como delete direto em clique unico.

## UX proposta na tela admin

## Secao Conta do Usuario

Acoes:

1. Desativar conta
2. Excluir conta (permanente)

Guard rails obrigatorios para Excluir conta:

1. modal de impacto com checklist;
2. campo de confirmacao textual exigindo frase exata: EXCLUIR CONTA;
3. reautenticacao (senha atual ou prompt provider) valida nos ultimos 5 minutos;
4. motivo obrigatorio para trilha de auditoria;
5. aviso claro de irreversibilidade.

## Secao Workspace (Billing/Governanca)

Acoes:

1. Encerrar workspace
2. Excluir workspace definitivamente

Guard rails obrigatorios para Excluir workspace:

1. exibicao de resumo de impacto antes do submit (usuarios, clientes, pedidos, produtos, regras fiscais, arquivos);
2. campo de confirmacao textual com frase contextual: DELETAR WORKSPACE <tenantId>;
3. motivo obrigatorio + checkbox de ciencia;
4. reautenticacao forte;
5. quando actor for platform admin, marcar acao como break-glass no log.

## Fluxo operacional recomendado

## Estado atual de implementacao (2026-11-13)

Situacao atual no produto:

1. os botoes de acoes destrutivas (cliente e admin) ja registram solicitacoes em workspace_deletion_requests;
2. as solicitacoes entram com status requested;
3. ainda nao existe executor completo de delecao que processe purge/desvinculacao fim-a-fim automaticamente.

Implicacao:

1. hoje o fluxo esta em modo solicitacao/auditoria;
2. a exclusao definitiva e o cleanup completo de vinculos dependem da etapa de execucao backend (pendente).

Nota sobre selecao de workspace:

1. a UI de selecao tende a nao exibir tenant inexistente;
2. mesmo assim, sem executor de cleanup, podem restar documentos orfaos (ex.: memberships e referencias antigas), o que e considerado risco operacional.

## Fase A: Solicitacao

1. usuario owner ou platform admin abre solicitacao;
2. sistema valida permissoes e pre-condicoes;
3. grava request em colecao dedicada com status requested.

## Fase B: Quarentena

1. status vai para scheduled;
2. define deletionScheduledAt e deletionEffectiveAt;
3. bloqueia operacao do workspace;
4. permite cancelamento ate deletionEffectiveAt.

## Fase C: Execucao

1. job backend executa purge por lotes (idempotente);
2. registra progresso e erros por etapa;
3. ao concluir, marca status completed com timestamp.

Checklist obrigatorio anti-orfao na Fase C (ordem recomendada):

1. marcar tenant com estado de ciclo de vida (closure_scheduled/deletion_scheduled) antes do purge final;
2. revogar todas as tenant_memberships do tenant (ativo=false, state=revoked);
3. limpar referencias de tenant padrao/ultimo tenant em usuarios afetados (defaultTenantId/lastSelectedTenantId);
4. revogar/encerrar convites e acessos pendentes ligados ao tenant;
5. encerrar billing e reconciliar Stripe;
6. executar purge de dados operacionais por lotes;
7. manter somente trilha minima legal e auditoria.

Resultado esperado do checklist:

1. nenhum usuario deve permanecer com vinculo ativo para tenant removido;
2. nenhum workspace removido deve reaparecer em seletores;
3. nenhuma referencia de tenant inexistente deve ficar em campos de navegacao padrao de usuario.

## Fase D: Pos-execucao

1. remove acessos ativos e tokens remanescentes;
2. confirma cancelamento/encerramento Stripe;
3. mantem somente trilha minima legal e de auditoria.

## Matriz de permissao

1. owner ativo do tenant: pode solicitar encerramento/exclusao do proprio workspace.
2. manager/representante/vendedor: nao pode excluir workspace.
3. platform_admin: pode executar encerramento/exclusao de qualquer tenant em modo break-glass.
4. deletar conta de terceiro: apenas platform_admin com permissao explicita.

## Regras de retencao e compliance

1. Dados fiscais/contabeis obrigatorios por lei: manter pelo prazo legal aplicavel.
2. Dados pessoais nao obrigatorios: anonimizar ou remover.
3. Logs de seguranca e auditoria: manter com minimizacao de PII.
4. Sempre registrar base legal e motivo da retencao.

Observacao:

1. O prazo exato de retencao deve ser validado com juridico/contabil antes de automatizar purge total.

## Contrato tecnico minimo

## Campos em tenants (sugestao)

1. workspaceLifecycleStatus: active | closure_requested | closure_scheduled | deletion_scheduled | deleted
2. deletionRequestedAt
3. deletionRequestedByUid
4. deletionReason
5. deletionEffectiveAt
6. deletionCanceledAt
7. deletionCompletedAt
8. deletionBreakGlass (bool)

## Colecao de requests (sugestao)

Path sugerido:

1. workspace_deletion_requests/{requestId}

Campos minimos:

1. tenantId
2. actionType: close_workspace | delete_workspace | delete_user_account
3. status: requested | scheduled | canceled | running | completed | failed
4. requestedByUid
5. requestedByEmail
6. approvalPolicyVersion
7. reason
8. confirmationPhraseHash
9. scheduledFor
10. executedAt
11. executionReport

## Auditoria obrigatoria

Todas as fases devem escrever em platform_admin_audit (ou equivalente), com:

1. actorUid
2. actorEmail
3. actorRole
4. targetTenantId/targetUid
5. action
6. reason
7. breakGlass (bool)
8. requestId correlacionado
9. createdAt
10. detalhes da mudanca de estado

## Integracao billing (Stripe)

Antes da exclusao definitiva do workspace:

1. cancelar subscription ativa ou pausar cobranca conforme politica vigente;
2. reconciliar estado local x Stripe;
3. registrar ids relevantes (customer/subscription/invoice) no report de execucao;
4. impedir exclusao sem resultado deterministico da etapa de billing (ou marcar como failed com retry controlado).

## Falhas e idempotencia

1. Toda etapa destrutiva deve ser idempotente.
2. Reexecucao nao pode recriar dados nem duplicar efeito financeiro.
3. Falhas parciais devem manter status failed com causa e ponteiro para retry.
4. Endpoint de execucao deve exigir requestId e expectedStatus para evitar corrida.

## Textos de confirmacao (sugestao)

## Excluir conta (self-service)

Frase exigida:

1. EXCLUIR CONTA

Mensagem:

1. Esta acao e permanente e pode remover seus dados pessoais. Registros obrigatorios por lei podem ser mantidos anonimizados.

## Excluir workspace

Frase exigida:

1. DELETAR WORKSPACE <tenantId>

Mensagem:

1. Esta acao encerra definitivamente o workspace e pode remover dados operacionais de toda a equipe. Apos o prazo de seguranca, nao sera possivel desfazer.

## Criterios de pronto (DoD)

1. Fluxo completo com confirmacao digitada e reautenticacao forte.
2. Janela de seguranca implementada e cancelavel.
3. Jobs de execucao idempotentes com retry.
4. Auditoria completa em todas as transicoes.
5. Integracao Stripe com reconciliacao obrigatoria.
6. Testes de regressao cobrindo:
   - owner com e sem pendencias;
   - owner unico sem transferencia (deve bloquear);
   - platform_admin break-glass;
   - cancelamento dentro da janela;
   - falha parcial e retry;
   - execucao final concluida.

## Decisao recomendada para SmartSFA (agora)

1. Adicionar na UI admin os botoes Encerrar workspace e Excluir workspace definitivamente.
2. Manter Excluir conta de usuario com uso restrito e guard rails fortes.
3. Implementar primeiro o fluxo de encerramento + janela de seguranca.
4. Habilitar exclusao definitiva apos observabilidade e dry-run validado em homolog.
