# SmartSFA - Guia de Implementacao SaaS

## Proposito

Este documento e a referencia principal para implementar o SmartSFA de forma correta.

Ele explica:

- como o sistema funciona;
- como o usuario entra pela primeira vez;
- como o tenant e escolhido;
- como clientes, produtos e pedidos devem ser tratados;
- quais regras evitam duplicidade e bagunca de permissao;
- como o app deve se comportar com ou sem ERP.

Se uma nova pessoa ou uma nova IA precisar continuar o projeto, este documento deve ser o ponto de partida.

## Visao geral do produto

O SmartSFA e uma plataforma SaaS multi-tenant para forca de vendas B2B.

Ele precisa suportar:

- varios tenants (empresas clientes) na mesma plataforma;
- varios usuarios por tenant;
- varios perfis por tenant;
- integracao com ERP quando existir;
- operacao manual quando nao existir ERP;
- importacao por Excel;
- pre-cadastro e aprovacao de clientes;
- fluxo comercial offline-first;
- isolamento por tenantId em todo dado de negocio.

## Regras basicas de arquitetura

### 1. Tenant sempre vem antes do usuario comercial

O usuario nao e o centro do sistema.

O centro do sistema e o tenant.

O usuario so tem acesso porque esta vinculado a um tenant por membership.

### 2. O tenant e a unidade de isolamento

Todo dado de negocio deve possuir tenantId.

Isso vale para:

- clientes;
- produtos;
- pedidos;
- listas de importacao;
- solicitacoes de acesso;
- logs de aprovacao;
- configuracoes operacionais.

### 3. O backend e a UI precisam concordar

Nao basta esconder botao na tela.

Se algo for proibido para um perfil ou tenant, o backend tambem precisa bloquear.

### 4. Membership e um vinculo revogavel

O usuario global nao some quando sai de um tenant.

O que muda e o membership daquele tenant:

- pode ser ativado;
- pode ser revogado;
- pode ser reativado;
- pode ser sincronizado com ERP.

Isso permite desligamento, recontratacao, troca de empresa e auditoria sem perder o historico.

## Modelos principais

### Platform Admin

Perfil interno da plataforma.

Esse papel:

- administra o SaaS;
- faz onboarding de tenants;
- faz suporte e governanca;
- nao participa da hierarquia comercial do tenant.

### Tenant

Empresa cliente da plataforma.

Um tenant pode operar:

- com ERP;
- sem ERP;
- com importacao por planilha;
- com cadastro manual controlado.

### Membership

Vinculo entre usuario e tenant.

O membership define:

- role;
- ativo/inativo;
- tenant padrao;
- relacao com owner, gerente, representante e vendedor.

Na UI inicial de governanca do tenant, owner/platform_admin deve conseguir:

- listar memberships do tenant em tempo real;
- revogar membership (offboarding sem deletar usuario global);
- reativar membership quando houver retorno do colaborador.
- alterar papel do membership com regras por perfil.

Toda mudanca critica de membership deve registrar trilha de auditoria com:

- tenantId;
- membershipId;
- acao executada;
- actorUid;
- detalhes da alteracao;
- timestamp.

### Role do tenant

Roles recomendados:

- owner;
- gerente;
- representante;
- vendedor.

## Como um usuario entra pela primeira vez

O usuario nao deve ser colocado em um tenant apenas pelo email.

O fluxo correto e por vinculacao explicita.

### Fontes validas de vinculacao

- convite enviado por um tenant;
- aprovacao manual por owner ou gerente;
- onboarding feito por platform admin;
- workspace pessoal, se o produto permitir esse modo.

### Fluxo de primeira entrada

1. O usuario autentica com Google ou provedor autorizado.
2. O backend procura memberships ativos para o uid.
3. Se existir um membership ativo, o usuario entra naquele tenant.
4. Se existirem varios, o app mostra seletor de tenant.
5. Se nao existir nenhum, o app mostra um fluxo de vinculo.

### Fluxo de vinculo sem membership

O app deve oferecer tres caminhos:

- entrar por convite valido;
- solicitar acesso a um tenant;
- criar workspace pessoal, se essa opcao estiver habilitada.

### Regra para tenants A e B

O mesmo usuario pode existir em varios tenants.

O tenant atual nao e escolhido por inferencia de email.

Ele e escolhido por membership, convite ou selecao do usuario.

### Workspace pessoal

Se o produto permitir uso individual, isso deve ser feito como um tenant pessoal separado.

Nao deve ser tratado como excecao solta dentro do tenant corporativo.

## Fluxo de autenticacao e autorizacao

### Autenticacao

O login pode ser feito com Google.

### Autorizacao

Depois do login, o app consulta o Firestore para descobrir:

- quais memberships o usuario possui;
- quais tenants estao ativos;
- qual e o tenant padrao;
- se ha algum convite ou solicitacao pendente.

### Recomendacao tecnica

- o Firebase Auth identifica a pessoa;
- o Firestore define o que ela pode fazer;
- as rules bloqueiam o que a tela nao deve permitir.

## Produto

### Regra principal

Cada tenant deve ter apenas uma origem principal de produtos por vez.

As origens possiveis sao:

- ERP;
- Excel;
- Manual.

### Regra de negocio

O usuario escolhe a origem principal no onboarding do tenant.

Essa decisao precisa ficar clara e persistida.

### Recomendacao pratica

- ERP deve ser a origem quando o tenant tiver integracao ativa;
- Excel deve ser o caminho padrao para carga inicial e manutencao em tenants sem ERP;
- cadastro manual deve ser restrito a tenants pequenos, excecoes ou operacao assistida.

### Importacao por Excel

O app deve permitir download de um template padrao.

O template deve ser versionado e conter:

- colunas obrigatorias;
- colunas opcionais;
- exemplo de preenchimento;
- regras de validacao.

### Produto precisa suportar

- codigo interno;
- id externo do ERP;
- alias de importacao;
- inativo;
- substituido;
- descontinuado.

## Cliente

### Regra principal

Cliente deve ter cadastro oficial e pre-cadastro separados.

### Cliente oficial

O cadastro oficial vem preferencialmente do ERP quando existir.

Se nao existir ERP, o cadastro pode ser criado a partir de aprovacao interna.

### Pre-cadastro

Pre-cadastro nao e cliente oficial incompleto.

Ele e uma entidade de aprovacao separada.

### Regra de aprovacao recomendada

- default: owner ou gerente aprova;
- bootstrap inicial: o primeiro owner pode se autoaprovar;
- sem ERP: pode haver autoaprovacao apenas se a politica do tenant permitir;
- o criador do pre-cadastro nao deve aprovar sozinho, salvo excecao clara de bootstrap.

### Duplicidade de cliente

Para evitar duplicidade, o sistema deve:

- normalizar CPF/CNPJ;
- comparar documento normalizado como chave principal;
- usar codigo externo do ERP como apoio;
- tratar nome apenas como sinal auxiliar;
- fazer merge quando o ERP trouxer um cliente que ja existe como pre-cadastro.

### Cliente precisa suportar

- status de rascunho;
- pendente_aprovacao;
- aprovado;
- sincronizado;
- bloqueado;
- inativo;
- multiplos enderecos;
- multiplos contatos;
- matriz e filial;
- grupo economico.

## Pedido

### Regra principal

Pedido pode ser criado com cliente aprovado ou com pre-cadastro.

### Comportamento recomendado

- se o cliente estiver aprovado, o pedido segue normalmente;
- se o cliente estiver pendente, o pedido pode ir para rascunho ou fila provisoria;
- quando o cliente for aprovado, o sistema reconcilia o pedido;
- se o ERP importar o cliente depois, o pedido deve continuar ligado ao cliente canonico.

### Status de pedido

- rascunho;
- pendente_cliente;
- pendente_envio;
- enviado;
- erro;
- cancelado.

## Casos sem ERP

Quando o tenant nao tiver ERP, o produto precisa continuar util.

Nesse modo, o tenant deve conseguir:

- cadastrar usuarios;
- importar clientes por Excel;
- importar produtos por Excel;
- aprovar pre-cadastros;
- criar pedidos offline-first;
- operar sem depender de Sankhya.

## Casos com ERP

Quando houver ERP, a regra recomendada e:

- ERP como fonte principal de produto e cliente oficial;
- importacao e sincronizacao como processos controlados;
- cadastro manual restrito;
- pre-cadastro ainda permitido para novos contatos ou visitas externas, com merge posterior.

## Regras de deduplicacao

### Clientes

- normalizar CPF/CNPJ;
- usar documento como chave principal;
- usar telefone e email apenas como apoio;
- manter aliases de origem;
- preservar historico e pedidos no registro canonico.

### Produtos

- usar codigo interno e codigo ERP;
- permitir substituicao e descontinuidade;
- evitar criar o mesmo produto por duas origens sem merge.

## Regras de liberacao por tenant

### O que pode ser bloqueado por tenant

- cadastro manual de produto;
- cadastro manual de cliente oficial;
- aprovacao de pre-cadastro;
- uso sem ERP;
- importacao por Excel;
- selecao de tenant pessoal.

### A regra correta

Essas decisoes devem ser configuracoes do tenant e nao apenas estados visuais.

## Como o sistema deve decidir o contexto

### Se existir um unico membership ativo

Entrar direto no tenant vinculado.

### Se existirem varios memberships

Mostrar seletor de tenant.

### Se nao existir membership

Mostrar solicitação de acesso ou convite.

### Se o produto permitir uso individual

Oferecer workspace pessoal como tenant separado.

## O que uma nova IA deve fazer primeiro

Se uma nova IA continuar este projeto, a ordem recomendada e:

1. Ler este guia.
2. Ler o modelo de acesso.
3. Ler a proposta B2B.
4. Ler o modelo SaaS multi-tenant.
5. Implementar entidades de dominio com status e origem.
6. Implementar regras de aprovacao e membership.
7. Implementar importacao por Excel e sincronizacao ERP.
8. Implementar telas e depois persistencia real.

## Resolvedor de entrada

O app ja deve possuir um servico de resolucao de entrada que decide o caminho do usuario apos o login:

- direto para um tenant;
- seletor de tenant quando houver varios memberships;
- solicitacao de acesso quando nao houver membership;
- workspace pessoal quando a politica do produto permitir.

Esse resolvedor deve consultar:

- usuarios/{uid};
- tenant_memberships;
- tenants;
- solicitacoes_acesso quando necessario.

### Regra de implementacao

Nao espalhar essa logica em varios widgets.

O widget de auth deve apenas exibir o resultado do resolvedor.

## Desligamento e sincronizacao ERP

### Regra principal

Se o owner remover um usuario do tenant, ou o ERP indicar desligamento, o membership deve ser revogado.

### Efeito esperado

- acesso bloqueado imediatamente;
- usuario global preservado;
- historico preservado;
- pedidos ja emitidos permanecem validos e auditaveis;
- reativacao futura pode reutilizar o mesmo uid.

### Regra tecnica

O app nao deve apagar documentos de membership como primeira opcao.

O padrao recomendado e:

- marcar `ativo=false`;
- definir `state=revoked`;
- registrar `revokedByUid` e `revokedReason`;
- opcionalmente armazenar `lastSyncedAt` quando a origem for ERP.

## Convite por token

### Objetivo

Permitir entrada direta no tenant correto sem cadastro manual pelo admin em cada caso.

### Regra de implementacao

- convite fica em `tenant_invitations/{token}`;
- token aceita uma unica vez quando status estiver pending;
- ao aceitar, o app cria/atualiza membership ativo do usuario;
- convite vira accepted e guarda quem aceitou;
- auth gate revalida o acesso logo apos o aceite.

### Aceite em notificacoes

Para reduzir atrito no uso real:

- convites pendentes por e-mail devem aparecer na tela de notificacoes;
- o usuario deve conseguir aceitar ou recusar com um toque;
- ingresso no tenant so acontece apos esse aceite explicito.

### Gestao de convite por owner/admin

Para fechar o ciclo de onboarding de tenant no app:

- somente owner ativo do tenant deve conseguir criar convite para um e-mail;
- no convite devem ser definidos role, defaultTenant e expiracao;
- convites pendentes devem poder ser revogados pelo owner emissor;
- o app deve registrar status do convite (pending, accepted, declined, revoked, expired) e evitar aceite de status invalido;
- envio e gerenciamento devem ficar na area Tenant (ex.: Tenant > Convites), sem misturar com inbox de notificacoes pessoais.

### Beneficio pratico

- reduz atrito no primeiro acesso;
- evita vinculo por inferencia de e-mail;
- preserva governanca por tenant.

## Principios que nao devem ser quebrados

- Nao inferir tenant apenas por email.
- Nao permitir cadastro manual irrestrito por padrao.
- Nao misturar pre-cadastro com cliente oficial.
- Nao deixar regra so na tela.
- Nao criar produto ou cliente duplicado sem estrategia de merge.
- Nao colocar Platform Admin dentro da hierarquia comercial do tenant.

## Resumo executivo

O SmartSFA deve funcionar assim:

- usuario autentica;
- sistema descobre memberships;
- usuario entra no tenant correto ou solicita acesso;
- produtos obedecem uma origem principal por tenant;
- clientes entram como oficial ou pre-cadastro;
- pedidos podem depender de aprovacao de cliente;
- duplicidade e resolvida por documento e chaves externas;
- backend e UI aplicam as mesmas regras.
