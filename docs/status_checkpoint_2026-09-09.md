# SmartSFA - Checkpoint de Execucao (2026-09-09)

## Onde paramos

- Controle de acesso SaaS multi-tenant implementado com Firebase Auth + Firestore.
- Convites com aceite explicito do usuario implementados.
- Governanca de memberships implementada (revogar, reativar, trocar papel).
- Auditoria de acoes criticas de membership implementada.
- Politicas de governanca por tenant implementadas.
- Modo pessoal mantido como capacidade da conta, independente de owner do tenant.

## O que esta real hoje (dados persistidos)

- usuarios
- tenants
- tenant_memberships
- tenant_invitations
- tenant_membership_audit
- solicitacoes_acesso

## O que ainda esta mock hoje

- Clientes: lista alimentada por `DemoWorkspace` + `InMemoryClienteRepository`.
- Produtos: lista alimentada por `DemoWorkspace` + `InMemoryProdutoRepository`.
- Pedidos: lista alimentada por `DemoWorkspace` + `InMemoryPedidoRepository`.
- Auth mock esta ativo por default em `main.dart` via `USE_MOCK_AUTH`.

## Tela x estado funcional

- Tenant > Convites: owner cria/revoga convites.
- Avisos/Notificacoes: usuario aceita/recusa convites recebidos.
- Tenant > Administracao: memberships + politicas + navegacao para auditoria.
- Conta: saida voluntaria do tenant (nao-owner).

## Proximo passo recomendado

1. Migrar Clientes para provider real tenant-aware (Firestore inicial).
2. Introduzir seletor de data source por ambiente para modulo comercial.
3. Repetir migracao em Produtos.
4. Repetir migracao em Pedidos.
5. Validar com analyze + testes + hot reload a cada lote.