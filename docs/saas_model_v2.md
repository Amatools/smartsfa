# SmartSFA - SaaS Multi-tenant V2 (resumo)

## Objetivo

Este arquivo foi reduzido para evitar duplicacao de manutencao.

Ele permanece como referencia rapida da decisao de produto:

- SmartSFA opera como SaaS multi-tenant.
- Isolamento por tenantId e obrigatorio em todos os dados de negocio.
- Membership define acesso, nunca inferencia por email/CNPJ.
- O produto suporta modo manual e modo com ERP.

## Fontes canonicas atuais

Para implementacao e regras completas, usar:

1. guia_implementacao_saas.md
2. auth_access_model.md
3. pricing_taxation_rules.md
4. web_portal_architecture.md

## Regras que continuam validas

1. Todo documento de negocio deve possuir tenantId.
2. Leitura/escrita fora do tenant selecionado deve ser bloqueada.
3. Workspace types oficiais: seller_solo_workspace, rep_workspace, brand_owner_workspace.
4. Modo sem ERP nao e fallback fraco; e parte oficial do produto.
5. Para catalogos grandes, evoluir para sincronizacao incremental (delta) e paginação de leitura.
