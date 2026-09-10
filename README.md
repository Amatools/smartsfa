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

O login e exclusivamente via Firebase Auth (Google ou e-mail/senha cadastrados no projeto). Nao ha mais modos mock/local de desenvolvimento: a conta precisa existir no Firebase para liberar o app. Apos o primeiro login bem-sucedido, a sessao fica persistida localmente e o app continua funcionando offline (Firestore com persistencia habilitada) ate que seja necessario reautenticar.

## Guias do projeto

- `appdev.md`: board de execucao e proximas etapas.
- `docs/guia_implementacao_saas.md`: referencia principal de arquitetura e regras.
- `docs/auth_access_model.md`: modelo de login/autorizacao.
