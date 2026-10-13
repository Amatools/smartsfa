# SmartSFA - Checkpoint de Execucao (base 2026-09-09, atualizado em 2026-10-13)

## Onde estamos agora

- Controle de acesso SaaS multi-tenant ativo com Firebase Auth + Firestore.
- Convites, governanca de membership e auditoria operacional ativos.
- Modulos comerciais principais ja operam com repositorios Firestore tenant-scoped.
- Fluxos de importacao/exportacao de planilhas para Produtos, Tabelas de Preco e Tributacao implementados com template e validacao.
- Portal web evoluido para configuracao comercial e tributaria com regras por representada/contexto.

## O que esta real hoje (dados persistidos)

- usuarios
- tenants
- tenant_memberships
- tenant_invitations
- tenant_membership_audit
- solicitacoes_acesso
- clientes
- produtos
- pedidos
- tabelas_preco
- product_base_prices
- customer_price_table_assignments
- tax_rules

## O que ainda e limitacao tecnica relevante

- Listas grandes ainda usam, em geral, leitura completa por tenant (watchAll/fetchAll) sem paginação para UI.
- Nao existe ainda pipeline formal de sincronizacao incremental de catalogo (delta por updatedAt + tombstones) para pre-carga de campo.
- Fila local atual prioriza operacao offline de escrita (clientes/pedidos/pre-cadastro), mas nao consolida cache operacional versionado de catalogos grandes.
- Hot restart web (DWDS) pode falhar intermitentemente, mesmo com analyze limpo.

## Validacao de direcao arquitetural

- Direcao geral esta correta: tenantId em dominio, repositorios por tenant e cache offline nativo do Firestore no mobile.
- Para escala (catalogos extensos + uso offline de campo), ainda falta a camada de sync economica orientada a delta.

## Plano de execucao imediato (proximo ciclo)

1. Definir metadados de sincronizacao por colecao de catalogo (version, updatedAt, deletedAt/tombstone).
2. Implementar endpoint/logica de sync incremental por tenant e modulo (produtos, clientes, tabelas_preco, tax_rules).
3. Introduzir pre-download explicito antes de campo (warmup) com indicador de progresso por modulo.
4. Introduzir paginação para listagens de portal/mobile onde hoje existe leitura completa.
5. Padronizar metricas de custo (leituras por usuario/dia e por sincronizacao) para acompanhar impacto no Firebase.

## Plano de documentacao (reduzir sem criar novos arquivos)

1. Consolidar regras ativas de implementacao em 4 arquivos canonicos:
	- guia_implementacao_saas.md
	- auth_access_model.md
	- pricing_taxation_rules.md
	- web_portal_architecture.md
2. Converter documentos redundantes em versoes resumidas com ponteiro para os canonicos (sem apagar agora).
3. Manter arquivos legais fora da consolidacao tecnica.
4. Na fase seguinte, remover os redundantes apos 1 ciclo de estabilidade.