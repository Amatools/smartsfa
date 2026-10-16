# SmartSFA - Especificacao Fechada de Hierarquia Comercial (Backlog Tecnico)

## Objetivo

Definir a especificacao oficial para hierarquia comercial em workspaces com equipe e transformar isso em backlog tecnico executavel.

Este documento e a referencia principal de desenvolvimento para esse tema.

## Escopo

Aplica-se a:

- `rep_workspace`
- `brand_owner_workspace`

Nao se aplica a:

- `seller_solo_workspace` (uso individual sem equipe)

## Decisoes de produto (congeladas)

1. Em workspace individual, nao existe equipe compartilhada no mesmo tenant.
2. Em workspaces com equipe, a cadeia logica obrigatoria e:
- Owner > Gerente > Representante > Vendedor
3. O owner pode operar sozinho e vender com seu proprio usuario.
4. Para garantir cadeia completa desde o dia 1, o owner nasce com cadeia primaria auto-preenchida:
- ownerId = ownerUid
- gerenteId = ownerUid
- representanteId = ownerUid
- vendedorId = ownerUid
5. Quando novos gerentes/representantes entram, o owner pode editar a arvore e realocar carteiras.
6. Relatorios devem suportar os dois modelos:
- snapshot historico para numeros oficiais
- hierarquia atual para gestao comercial
7. Prioridade atual do produto:
- hierarquia atual para operacao e gestao (sem abrir mao do snapshot em pedidos)

## Conceitos canonicos

### Papel (permissao)

Controla o que o usuario pode fazer no sistema.

Exemplos: `owner`, `gerente`, `representante`, `vendedor`.

### Vinculo hierarquico (carteira)

Controla em qual cadeia comercial o usuario atua.

Importante: papel e carteira nao sao a mesma coisa.

## Regras obrigatorias de hierarquia

1. Todo usuario comercial ativo em workspace com equipe deve pertencer a uma cadeia completa.
2. Todo vendedor deve ter `ownerId`, `gerenteId` e `representanteId` validos.
3. Cadeias incompletas sao proibidas em runtime.
4. Em ausencia de gerente/representante reais, o owner cobre niveis faltantes (cadeia primaria).
5. Realocacao de vendedor entre representantes deve preservar historico e auditoria.

## Modelo de dados (alvo)

### 1) tenant_memberships

Fonte de verdade de identidade + papel no tenant.

Campos relevantes:

- `tenantId`
- `uid`
- `role`
- `ativo`
- `ownerId`
- `gerenteId`
- `representanteId`
- `vendedorId`
- `updatedAt`

Regras:

- Owner inicial do tenant deve ter todos os IDs iguais ao proprio UID.
- Membros convidados devem ser gravados com cadeia completa valida.

### 2) tenant_hierarchy_movements (novo)

Auditoria de mudanca de carteira/hierarquia.

Caminho sugerido:

- `tenant_hierarchy_movements/{movementId}`

Campos:

- `movementId`
- `tenantId`
- `subjectUid` (usuario movido)
- `subjectRole`
- `fromOwnerId`
- `fromGerenteId`
- `fromRepresentanteId`
- `fromVendedorId`
- `toOwnerId`
- `toGerenteId`
- `toRepresentanteId`
- `toVendedorId`
- `reason`
- `actorUid`
- `createdAt`

### 3) pedidos com snapshot historico

Todo pedido deve carregar snapshot da cadeia no momento da criacao.

Campos minimos no pedido:

- `ownerId`
- `gerenteId`
- `representanteId`
- `vendedorId`
- `hierarchySnapshotVersion` (opcional, recomendado)

## Regras de negocio por operacao

### Criacao do owner inicial

1. Criar membership owner ativo.
2. Preencher cadeia primaria owner->owner->owner->owner.
3. Garantir que o owner possa operar como vendedor imediatamente.

### Convite de vendedor sem gerente/representante real

1. Permitir convite normalmente.
2. Ao aceitar, criar vendedor com:
- `ownerId = ownerUid`
- `gerenteId = ownerUid`
- `representanteId = ownerUid`
- `vendedorId = vendedorUid`

### Entrada de novo representante

1. Criar membership do representante com cadeia valida.
2. Permitir owner mover vendedores da carteira primaria para esse representante.
3. Registrar movement em `tenant_hierarchy_movements`.

### Entrada de novo gerente

1. Criar membership do gerente.
2. Permitir owner realocar representantes (e seus vendedores) para esse gerente.
3. Registrar movement com auditoria completa.

### Edicao manual da hierarquia pelo owner

1. Sempre validar cadeia completa antes de salvar.
2. Bloquear atribuicoes ciclicas/invalidas.
3. Registrar movimento com actor, motivo e timestamp.

## Visibilidade e relatorios

### Visao operacional (hierarquia atual)

- Vendedor: apenas sua carteira.
- Representante: seus vendedores atuais.
- Gerente: seus representantes e vendedores deles.
- Owner: tudo.

### Visao oficial (snapshot historico)

- Pedido contabiliza para a cadeia registrada no momento da venda.
- Reorganizacoes futuras nao reescrevem historico do pedido.

## API/servicos internos esperados

1. `HierarchyAssignmentService`
- validar cadeia completa
- montar cadeia default do owner
- aplicar realocacao segura

2. `HierarchyMovementAuditService`
- persistir eventos de movimento
- consultar trilha por tenant/usuario

3. `HierarchyReportScopeService`
- resolver escopo atual por perfil
- resolver escopo historico por snapshot

## Backlog tecnico executavel

### Fase 1 - Fundacao de dados e validacao

- [ ] Garantir cadeia primaria owner->owner->owner->owner no bootstrap.
- [ ] Validar cadeia completa no create/update de membership em fluxo com equipe.
- [ ] Bloquear salvamento de cadeia incompleta.
- [ ] Criar colecao `tenant_hierarchy_movements` com rules e indices.

### Levantamento de status atual da Fase 1 (2026-10-15)

1. Cadeia primaria owner->owner->owner->owner no bootstrap
- Status: pendente.
- Evidencia tecnica:
	- bootstrap owner usa `_roleScope(...)` em `solo_workspace_service.dart`, e owner nasce com `ownerId=uid` e demais niveis vazios.
	- rules de self-service bootstrap tambem aceitam owner com `gerenteId`, `representanteId` e `vendedorId` vazios.

2. Validar cadeia completa no create/update de membership em fluxo com equipe
- Status: parcial (validacao existe, mas segue modelo antigo com niveis vazios em varios casos).
- Evidencia tecnica:
	- rules possuem validadores de membership (`validRepMembershipHierarchy` e `validEnterpriseMembershipHierarchy`), porem permitem campos vazios por papel.
	- aceite de convite em `tenant_invitation_service.dart` ainda monta alguns niveis com `''` em cenarios de owner/representante.

3. Bloquear salvamento de cadeia incompleta
- Status: pendente segundo novo contrato de produto.
- Evidencia tecnica:
	- regras atuais aceitam cadeia com niveis vazios em rep/enterprise para determinados papeis.

4. Criar colecao `tenant_hierarchy_movements` com rules e indices
- Status: nao iniciado.
- Evidencia tecnica:
	- sem match especifico em `firestore.rules`.
	- sem indices em `firestore.indexes.json`.

### Ordem recomendada de implementacao (proxima execucao)

1. Ajustar bootstrap owner para cadeia primaria completa (owner em todos os niveis).
2. Ajustar aceite de convite para preencher cadeia completa conforme regra de fallback do owner.
3. Endurecer Firestore rules para novo contrato (cadeia completa obrigatoria em workspaces com equipe).
4. Criar `tenant_hierarchy_movements` + rules + indices + auditoria de servico.

### Fase 2 - Governanca de hierarquia no portal

- [ ] Tela de arvore hierarquica para owner.
- [ ] Acao de mover vendedor entre representantes.
- [ ] Acao de mover representante entre gerentes.
- [ ] Confirmacao com motivo obrigatorio.
- [ ] Registro automatico em auditoria de movimentos.

### Fase 3 - Relatorios por nivel

- [ ] Escopo atual por perfil (owner/gerente/representante/vendedor).
- [ ] Escopo historico por snapshot em pedidos.
- [ ] Toggle de relatorio: Atual vs Historico.
- [ ] Validar somatorios e evitar dupla contagem.

### Fase 4 - Hardening

- [ ] Testes de rules para leitura/escrita por nivel.
- [ ] Testes de integracao de realocacao.
- [ ] Testes de regressao de relatorios apos mudanca de carteira.
- [ ] Telemetria de mudancas de hierarquia por tenant.

## Criterios de aceite

1. Owner sozinho consegue operar sem criar niveis intermediarios manualmente.
2. Convite de vendedor funciona mesmo sem gerente/representante real (owner cobre niveis).
3. Owner consegue reorganizar carteiras sem perder historico oficial.
4. Relatorio atual reflete cadeia atual.
5. Relatorio historico reflete snapshot do pedido.
6. Toda mudanca relevante gera auditoria consultavel.

## Dependencias

- `docs/workspace_access_billing_policy.md`
- `docs/auth_access_model.md`
- `docs/guia_implementacao_saas.md`

## Fora de escopo imediato

- Backoffice financeiro/billing completo.
- Comissionamento detalhado multinivel.
- Simulador avancado de redistribuicao com otimização.
