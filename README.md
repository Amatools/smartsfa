# SmartSFA

SmartSFA e um app Flutter para operacao comercial B2B em modelo SaaS multi-tenant.

## Status rapido

- Controle de acesso multi-tenant: implementado com Firebase Auth + Firestore.
- Governanca de memberships (revogar, reativar, trocar papel, auditoria): implementada.
- Convites: owner-only em Tenant > Convites.
- Notificacoes: apenas aceite/recusa de convite recebido.
- Clientes, Produtos e Pedidos: ainda operando com repositorios in-memory (mock local).

## Estrutura principal

- `lib/src/features/auth`: fluxo de autenticacao e resolucao de entrada por membership.
- `lib/src/features/tenant`: administracao de tenant, convites e auditoria.
- `lib/src/features/notificacoes`: inbox de convites para aceite/recusa.
- `lib/src/features/clientes`, `lib/src/features/produtos`, `lib/src/features/pedidos`: telas com dados mock locais.

## Como executar

1. `flutter pub get`
2. `flutter analyze`
3. `flutter run -d chrome`

Por padrao o projeto inicia com login local de desenvolvimento para acelerar validacao de fluxos sem depender de Google Cloud:

- flag: `AUTH_MODE=local` (default no build atual)

Modos disponiveis:

- `AUTH_MODE=local`: login local por e-mail/senha de desenvolvimento (tenta Firebase anonimo + Firestore; se nao conseguir, entra em fallback mock automaticamente)
- `AUTH_MODE=profile_mock`: acesso por selecao de tenant/perfil (modo antigo)
- `AUTH_MODE=firebase`: login real via Firebase Auth (Google)

## Guias do projeto

- `appdev.md`: board de execucao e proximas etapas.
- `docs/guia_implementacao_saas.md`: referencia principal de arquitetura e regras.
- `docs/auth_access_model.md`: modelo de login/autorizacao.
