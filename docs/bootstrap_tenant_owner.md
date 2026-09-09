# Bootstrap de Tenant e Owner

## Objetivo

Criar o primeiro tenant e o primeiro owner no modelo SaaS multi-tenant.

## Variaveis necessarias

- GOOGLE_APPLICATION_CREDENTIALS_JSON: caminho para o JSON da service account
- TENANT_ID: identificador tecnico do tenant
- TENANT_SLUG: slug publico/logico do tenant
- TENANT_NAME: nome fantasia da empresa cliente
- OWNER_EMAIL: email do owner inicial

## Variaveis opcionais

- OWNER_PASSWORD: senha, caso queira criar usuario por email/senha
- OWNER_NAME: nome exibido do owner
- TENANT_OPERATION_MODE: manual | sankhya | custom
- TENANT_ERP_PROVIDER: none | sankhya | custom

## Exemplo PowerShell

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS_JSON = 'G:\caminho\service-account.json'
$env:TENANT_ID = 'amatools'
$env:TENANT_SLUG = 'amatools'
$env:TENANT_NAME = 'Amatools'
$env:OWNER_EMAIL = 'owner@empresa.com'
$env:OWNER_NAME = 'Owner Amatools'
$env:TENANT_OPERATION_MODE = 'manual'
$env:TENANT_ERP_PROVIDER = 'none'
node .\scripts\bootstrap_owner.mjs
```

## O que o script cria

1. Documento em tenants/{tenantId}
2. Documento em usuarios/{uid}
3. Documento em tenant_memberships/{tenantId_uid}
4. Custom claims globais basicas no Auth

## Observacao

Como estamos em fase de desenvolvimento, este bootstrap deve ser usado apenas no projeto dev/prototipo atual.
