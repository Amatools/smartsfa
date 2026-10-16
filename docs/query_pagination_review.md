# Revisao periodica de queries e paginacao

## Objetivo

Evitar regressao de custo e performance em telas de catalogo e operacao com grande volume.

## Cadencia recomendada

- dev: semanal
- homolog: quinzenal
- prod: quinzenal

A cadencia tambem e aplicada no app via `AppEnvironmentConfig.queryPaginationReviewCadence`.

## Passo a passo da revisao

1. Abrir dashboard inicial e verificar o card "Custo e performance de sincronizacao (hoje)".
2. Se houver alerta de regressao, priorizar os modulos com mais leitura e fallback full-read.
3. Revisar queries de listagem com foco em:
- filtros por `tenantId`
- uso de cursor/limit/orderBy
- evitacao de `fetchAll` sem necessidade
4. Revisar se telas grandes estao paginadas no cliente e no backend.
5. Registrar revisao no botao "Registrar revisao de queries/paginacao" no dashboard.

## Hotspots atuais para revisao

- `lib/src/features/pedidos/presentation/pages/pedidos_page.dart`
- `lib/src/features/precos/presentation/pages/tabelas_preco_page.dart`
- `lib/src/features/produtos/presentation/widgets/product_catalog_workspace_section.dart`
- `lib/src/core/services/catalog_incremental_sync_service.dart`
- `lib/src/navigation/app_shell.dart`

## Criterios de aprovacao por ciclo

1. `flutter analyze` sem erros.
2. Sem alerta critico no card de custo/performance.
3. Sem fallback full-read repetitivo no dia (valor ideal: 0).
4. Em telas com volume alto, paginação ativa e tamanho de pagina validado.

## Evidencias minimas

- Data da revisao.
- Responsavel.
- Alertas encontrados e acoes tomadas.
- Arquivos alterados (quando houver).
