Estrutura atual do app

- core/: modelos, contratos, repositorios e implementacoes de dados
- navigation/: shell e navegacao principal
- shared/: utilitarios e widgets compartilhados
- features/: modulos funcionais por contexto de negocio

Modulos atuais em features:

- auth
- clientes
- produtos
- pedidos
- notificacoes
- tenant

Observacao de status:

- auth + tenant + notificacoes (convites): com dados reais em Firebase/Firestore
- clientes + produtos + pedidos: ainda em repositorios in-memory (mock)
