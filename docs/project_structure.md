# SmartSFA - Estrutura Atual do Projeto

## Objetivo

Estabelecer uma base evolutiva para o app Flutter com separacao clara entre composicao, navegacao, modelos compartilhados e modulos de negocio.

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

## Proxima evolucao

1. Conectar Clientes/Produtos/Pedidos a provider real tenant-aware (Firestore inicial)
2. Introduzir selecao clara de data source (mock vs real) por ambiente
3. Evoluir armazenamento local para offline-first com Isar
4. Manter regras de acesso apenas em services/domain e evitar regra de negocio na UI
5. Expandir cobertura de testes de repositorios e fluxos de entrada multi-tenant
