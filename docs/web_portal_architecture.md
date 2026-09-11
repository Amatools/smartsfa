# SmartSFA - Arquitetura do Portal Web

## Objetivo

O portal web do SmartSFA existe para concentrar configuracao pesada, governanca e parametrizacao do negocio.

Ele complementa o app mobile operacional, nao o substitui.

## Regra de precificacao adotada

O portal precisa suportar dois modos ao mesmo tempo, porque o mercado do cliente pode variar muito:

- modo tabela: tabelas de preço por cliente, grupo, regiao, canal ou campanha;
- modo politica: regras sobre o preco bruto, com descontos, acrescimos, promocao e travas.

No caso da Amatools, a visao principal e por politica comercial:

- existe um preco bruto alto como base;
- politicas derivam tabelas teoricas por desconto (ex.: 88%, 88,5%, 89%);
- politicas podem limitar as casas de desconto de manga disponiveis;
- o vendedor aplica a regra, mas o sistema deve poder travar e orientar.

Em outros clientes, o modo tabela pode ser o principal:

- tabela de preco por regiao;
- tabela por tipo de cliente;
- tabela vinculada diretamente ao cliente.

Na pratica, a primeira entrega da area de tabelas de preço deve deixar claro se a planilha fica:

- sem vinculo direto;
- vinculada a cliente;
- vinculada a regiao.

Isso permite atender tanto operacoes com tabela unica quanto clientes que trabalham com variacao por regional ou carteira.

O modulo de precificacao deve aceitar os dois modos sem forcar um unico modelo de operacao.

## Papel do portal web

O portal web deve ser usado para:

- configuracao de tenant;
- politicas de preco;
- tabelas de preco;
- regras por marca, segmento, cliente e produto;
- tags e segmentacao de cliente;
- limites de desconto e acrescimo;
- governanca de memberships e convites;
- auditoria;
- parametrizacao de integracao com ERP;
- configuracoes de billing/plano por tenant.

## Papel do app mobile

O app mobile deve ser usado para:

- orcamentos;
- pedidos;
- consulta rapida;
- dashboards operacionais;
- aprovacao pontual;
- uso em campo.

## Diretriz de produto

O sistema deve ser tratado como um unico produto com dois pontos de entrada:

1. app operacional;
2. portal web administrativo.

Ambos compartilham o mesmo nucleo de dominio:

- tenants;
- usuarios;
- memberships;
- regras de permissao;
- regras de pricing;
- dados de cliente/produto/pedido;
- auditoria.

## Contextos de workspace

O portal deve respeitar 3 contextos de tenant:

- seller_solo_workspace: base privada sem interligacao de equipe.
- rep_workspace: base de representacao com relacao representante -> vendedores.
- brand_owner_workspace: base oficial da marca com cadeia completa owner > gerente > representante > vendedor.

Mesmo quando a empresa representada tiver o mesmo nome (ex.: Amatools), cada contexto acima permanece em base separada quando o tenantId for diferente.

## Estrutura recomendada

### Frontends

- mobile app Flutter: experiencia simplificada para vendas e operacao;
- web portal Flutter: experiencia densa, tabular e configuravel;
- paginas publicas: landing, privacidade, termos e autenticacao.

### Nucleo compartilhado

- regras de dominio;
- modelos de tenant e membership;
- pricing engine;
- validacoes;
- repositorios/servicos;
- policies e audit trail.

### Backend gerenciado

- Firebase Auth;
- Firestore;
- Firebase Hosting;
- Cloud Functions ou Cloud Run para integracoes e automacoes;
- Cloud Scheduler para tarefas agendadas;
- Pub/Sub ou filas quando necessario.

## Estrategia de deploy

### Fase inicial

- usar Firebase Hosting para publicar o portal web;
- manter o app mobile no mesmo codigo base;
- manter o portal web dentro do mesmo dominio do produto, se possivel.

### Fase de escala

- mover processamento pesado para Cloud Run/Functions;
- manter o portal web como interface de configuracao;
- evitar VPS no inicio;
- usar servicos gerenciados sempre que possivel.

## Separacao de telas

### No app mobile

- dashboard resumido;
- pedidos;
- orcamentos;
- clientes;
- consulta operacional;
- notificacoes de rotina.

### No portal web

- painel de regras de preco;
- politica comercial;
- tabela de preco;
- segmentos e tags;
- convites e memberships;
- auditoria;
- configuracao de ERP;
- planos e billing;
- templates de importacao;
- configuracoes do tenant.

## Motor de precificacao

O motor de precificacao deve ser um modulo proprio.

Ele nao deve ficar espalhado em telas isoladas.

Deve suportar, no minimo:

- preco base bruto do produto;
- tabelas de preco derivadas;
- regras por marca;
- regras por segmento;
- regras por cliente ou grupo;
- regras por tag;
- limites maximos de desconto;
- limites maximos de acrescimo;
- travas por role;
- excecoes por politica;
- logs de decisao de preco.

## Cadastro de produto

O cadastro de produto deve ser tratado como cadastro mestre completo.

A listagem deve ser resumida, mas ao abrir o item o sistema deve mostrar o registro inteiro em abas, no minimo:

- informacoes gerais;
- valores e impostos;
- estoque e integracao.

No cadastro do produto, os campos de valor bruto e fiscal nao devem ser tratados como uma tela separada de precificacao. Eles pertencem ao produto e servem como base para o calculo de preco e para a integracao ERP.

## ERP e integracao

Para ERP, o portal web deve permitir configuracao assistida pelo tenant quando isso for permitido pelo produto.

O sistema precisa suportar:

- conexoes por tenant;
- parametros por conector;
- credenciais/segredos em backend seguro;
- mapeamento de campos;
- politicas de sincronizacao;
- status de integracao;
- logs e diagnostico.

## Princípio de UX

- o mobile deve ser simples e rapido;
- o web deve ser detalhado e parametrico;
- o mesmo dado deve ser acessivel por ambos, mas editado onde fizer mais sentido.

## Roadmap recomendado

1. consolidar o fluxo de onboarding e membership;
2. manter o app operacional no Flutter atual;
3. criar o portal web administrativo com a mesma base;
4. implementar o pricing engine como modulo compartilhado;
5. adicionar integracao ERP parametrizavel;
6. evoluir billing/plano por tenant.
