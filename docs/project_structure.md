# SmartSFA - Estrutura Inicial do Projeto

## Objetivo

Estabelecer uma base evolutiva para o app Flutter com separacao clara entre composicao, navegacao, modelos compartilhados e modulos de negocio.

## Estrutura atual proposta

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
    features/
      auth/
      dashboard/
      clientes/
      produtos/
      pedidos/
      notificacoes/
      tenant_admin/
      platform_admin/
```

## Responsabilidades

- main.dart: bootstrap do app e composicao inicial
- src/core/contracts: interfaces base para entidades tenant-aware
- src/core/repositories: contratos genericos e repositorios por dominio
- src/core/data: implementacoes de armazenamento por ambiente
- src/core/models: tipos compartilhados e entidades de dominio pequenas
- src/navigation: shell, menus e roteamento principal
- src/features: modulos funcionais por contexto de negocio

## Proxima evolucao

1. Mover auth e splash para src/features/auth
2. Mover dashboard para src/features/dashboard
3. Consolidar modelos tenant-aware e contratos de repositorio em src/core
4. Adicionar camada data para storage local e integrações
5. Criar camada domain para regras comerciais e casos de uso
