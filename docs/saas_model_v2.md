# SmartSFA - SaaS Multi-tenant V2

## Objetivo

Consolidar a arquitetura do produto como plataforma SaaS multi-tenant, com uso manual ou integrado a ERP.

## Entidades principais

### tenants/{tenantId}

- tenantId
- slug
- nomeFantasia
- razaoSocial
- ativo
- onboardingStatus
- operationMode: manual | sankhya | custom
- erpProvider: none | sankhya | custom
- createdAt
- updatedAt

### usuarios/{uid}

- uid
- email
- displayName
- platformRole: platform_admin | none
- ativoGlobal
- createdAt
- updatedAt

### tenant_memberships/{membershipId}

Sugestao de chave: {tenantId}_{uid}

- membershipId
- tenantId
- uid
- role: owner | gerente | representante | vendedor
- ativo
- defaultTenant
- ownerId
- gerenteId
- representanteId
- vendedorId
- createdAt
- updatedAt

### clientes/{clienteId}

- tenantId
- ownerId
- gerenteId
- representanteId
- vendedorId
- nome
- documento
- origemCadastro: manual | erp
- createdAt
- updatedAt

### produtos/{produtoId}

- tenantId
- codigoInterno
- descricao
- origemCadastro: manual | erp
- tabelaPrecoVersao
- estoqueVersao
- createdAt
- updatedAt

### pedidos/{pedidoId}

- tenantId
- ownerId
- gerenteId
- representanteId
- vendedorId
- origemPedido: manual | sync
- statusFila: pendente_envio | enviado | erro
- createdAt
- updatedAt

## Regras de isolamento

1. Todo documento de negocio deve possuir tenantId.
2. Nenhuma leitura ou escrita deve ocorrer fora do tenant selecionado.
3. Hierarquia comercial sempre e avaliada dentro do tenant.
4. platform_admin fica fora da hierarquia comercial.

## Modo sem ERP

O tenant pode operar apenas com:

- importacao CSV de clientes
- importacao CSV de produtos
- definicao manual de tabelas
- cadastro manual de usuarios
- pedidos offline-first

## Modo com ERP

A mesma estrutura suporta adaptadores como:

- Sankhya
- Tiny
- Bling
- Provider customizado

## Fases tecnicas

1. Refatorar Firestore Rules para tenantId e memberships.
2. Refatorar bootstrap para criar tenant e owner.
3. Ajustar app para selecionar tenant e perfil a partir da membership.
4. Implementar modo manual primeiro e integracao ERP depois.
