# SmartSFA - Estrutura Atual do Projeto

## Objetivo

Estabelecer uma base evolutiva para o app Flutter com separacao clara entre composicao, navegacao, modelos compartilhados e modulos de negocio.
Tambem definir governanca de documentacao para reduzir redundancia.

## Estrutura atual

```text
lib/
  main.dart
  firebase_options.dart
  src/
    README.md
    core/
      contracts/
      repositories/
      data/
        in_memory/
      models/
        app_identity.dart
        cliente.dart
        pedido.dart
        produto.dart
    navigation/
      app_shell.dart
    shared/
    features/
      auth/
      clientes/
      produtos/
      pedidos/
      precos/
      portal/
      notificacoes/
      tenant/
```

## Responsabilidades

- main.dart: bootstrap do app e composicao inicial
- src/core/contracts: interfaces base para entidades tenant-aware
- src/core/repositories: contratos genericos e repositorios por dominio
- src/core/data: implementacoes de armazenamento por ambiente
- src/core/models: tipos compartilhados e entidades de dominio pequenas
- src/navigation: shell, menus e roteamento principal
- src/shared: utilitarios e widgets compartilhados
- src/features: modulos funcionais por contexto de negocio

## Estado de persistencia e offline

- Repositorios principais ja estao em Firestore tenant-scoped (clientes, produtos, pedidos, precos e tributacao).
- Cache offline nativo do Firestore esta habilitado no mobile.
- Operacao offline de escrita usa fila local para sincronizacao posterior.
- Sincronizacao incremental formal para catalogos ja existe (clientes, produtos, tabelas_preco e tax_rules) com cursor local por tenant/modulo.
- Exclusao em catalogos principais usa tombstone (deletedAt) para propagacao de delta.

## Mapa de documentacao canonica (reduzir docs)

Arquivos canonicos tecnicos:

1. guia_implementacao_saas.md
2. auth_access_model.md
3. pricing_taxation_rules.md
4. web_portal_architecture.md

Arquivos que devem virar resumo/ponteiro (sem apagar agora):

1. architecture_transition.md
2. saas_model_v2.md
3. proposta_operacao_b2b.md
4. status_checkpoint_2026-09-09.md

Arquivos operacionais e legais (manter separados):

1. firebase/*
2. legal/*

## Proxima evolucao

1. Fechar rollout de indices tenantId + syncVersion para evitar fallback de leitura completa no incremental.
2. Adicionar paginacao nas listagens que hoje usam leitura completa por tenant.
3. Introduzir pre-download de catalogos antes de saida para campo, com feedback por modulo.
4. Expandir o mesmo padrao incremental para pedidos.
5. Expandir cobertura de testes para custo de leitura, fallback offline e conflitos de sync.
