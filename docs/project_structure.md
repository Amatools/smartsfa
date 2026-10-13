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
- Ainda falta sincronizacao incremental formal para catalogos grandes.

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

1. Implementar sincronizacao incremental para catalogos grandes (delta por updatedAt/version + tombstones).
2. Adicionar paginação nas listagens que hoje usam leitura completa por tenant.
3. Introduzir pre-download de catalogos antes de saida para campo, com feedback por modulo.
4. Consolidar documentos redundantes no conjunto canonico e reduzir manutencao paralela.
5. Expandir cobertura de testes para custo de leitura, fallback offline e conflitos de sync.
