# SmartSFA - Estado Atual, Transicao e Estado Alvo

## 1. Estado atual do projeto

O projeto atual deve ser tratado como ambiente de desenvolvimento/prototipo.

### Infraestrutura atual

- Projeto Firebase atual: smartsfa-f20a0
- Conta dona do projeto atual: conta ligada ao contexto Amatools
- Uso correto neste momento: desenvolvimento, prova de conceito e validacao de arquitetura
- Uso incorreto neste momento: considerar esse projeto como ambiente definitivo de producao do SaaS

### O que ja foi feito

- Projeto Flutter criado e validado
- Execucao web em Chrome funcionando
- Build Android debug funcionando
- Firebase configurado para Android, iOS e Web
- Firestore Rules iniciais publicadas
- Splash screen inicial criada
- Fluxo inicial de autenticacao/autorizacao montado no app
- Paginas temporarias de home, privacidade e termos publicadas no Firebase Hosting

### O que isso significa

A base tecnica esta boa para continuar desenvolvendo, mas a identidade do produto e a conta definitiva de ownership da plataforma ainda nao foram separadas da Amatools.

## 2. Decisao arquitetural tomada

A direcao oficial do produto sera:

- Plataforma SaaS multi-tenant
- Primeiro tenant real: Amatools
- Primeiro adaptador ERP: Sankhya
- Operacao sem ERP: obrigatoria no MVP

## 3. Como deve ficar no estado alvo

### Ownership da plataforma

O produto precisa ter identidade propria:

- conta Google/Workspace do produto ou dos socios do produto
- projeto Firebase proprio do SmartSFA
- dominio proprio do produto
- Branding e OAuth vinculados ao dominio do produto
- ambientes separados: dev, hml e prod

### Estrutura recomendada de ambientes

- smartsfa-dev
- smartsfa-hml
- smartsfa-prod

### Modelo multi-tenant

Cada empresa cliente nao deve ter um Firebase proprio por padrao.
O padrao recomendado e um unico backend do SaaS por ambiente, com isolamento logico por tenantId.

## 4. Hierarquia recomendada

### Nivel da plataforma

- platform_admin

### Nivel do tenant

- tenant
- owner
- gerente
- representante
- vendedor

Observacoes:

- tenant nao e pessoa; e a empresa/conta cliente
- owner e o administrador principal daquela empresa
- platform_admin nao participa da arvore comercial do tenant

## 5. Como fica a operacao com e sem ERP

### Com ERP

- usar adaptadores de integracao
- Sankhya entra como primeiro provider
- cadastro, sync e envio de pedidos podem ser automatizados

### Sem ERP

O sistema continua util e comercializavel com:

- cadastro manual da empresa
- cadastro manual dos usuarios
- importacao CSV de clientes
- importacao CSV de produtos
- upload manual de tabela de preco
- regras comerciais locais
- operacao de pedidos offline

Esse modo nao deve ser tratado como gambiarra. Ele e parte do produto.

## 6. O que manter agora

Devemos manter:

- o projeto Flutter atual
- a base Firebase atual como ambiente dev/prototipo
- a modelagem em evolucao
- o fluxo de telas e UX
- a fundacao de seguranca

## 7. O que deve mudar depois

Quando a identidade do produto estiver definida, devemos migrar para:

- conta dona neutra do produto
- dominio proprio do produto
- projetos Firebase definitivos por ambiente
- OAuth Branding vinculado ao dominio proprio
- regras e colecoes ja refatoradas para tenantId

## 8. Precisamos do login real agora?

Nao. O desenvolvimento do produto nao precisa parar por falta do login real.

Podemos seguir de duas formas:

### Opcao recomendada agora

Usar autenticacao mockada ou modo dev local para:

- navegar nas telas
- testar perfis e permissoes visuais
- desenvolver fluxo comercial
- construir dados locais offline-first
- implementar calculos e sync local

### Quando o login real passa a ser obrigatorio

- validacao de auth no navegador com Google
- aprovacao de usuarios reais
- regras Firestore em ambiente compartilhado
- onboarding real de tenant
- testes de ponta a ponta de producao

## 9. Decisao pratica para continuar o projeto

Recomendacao:

- curto prazo: mockar o login e continuar o produto
- medio prazo: refatorar Firestore para multi-tenant
- depois: criar infraestrutura definitiva do SmartSFA
- so entao: fechar branding, dominio e login real final

## 10. Proxima etapa tecnica correta

1. Refatorar modelagem para tenants e tenant_memberships
2. Criar modo dev/mock auth no app
3. Continuar UI, offline-first e regra comercial sem depender de Google login
4. Reativar login real quando o dominio/branding definitivo estiver pronto
