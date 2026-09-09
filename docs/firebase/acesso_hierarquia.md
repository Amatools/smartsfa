# SmartSFA - Firebase (Acesso e Hierarquia)

## Objetivo
Definir um modelo de dados que permita aplicar seguranca estrita para a hierarquia:
Owner > Gerente > Representante > Vendedor.

## Convencoes gerais
- IDs dos documentos de usuarios em usuarios/{uid} devem ser iguais ao Firebase Auth UID.
- Todo documento de negocio deve carregar os IDs de escopo: ownerId, gerenteId, representanteId, vendedorId.
- Isso permite filtrar e validar acesso sem servidor proprio.

## 1) Colecao usuarios
Caminho: usuarios/{uid}

Campos sugeridos:
- uid: string (igual ao ID do documento)
- role: string (owner | gerente | representante | vendedor)
- nome: string
- email: string
- ativo: bool
- ownerId: string
- gerenteId: string|null
- representanteId: string|null
- createdAt: timestamp
- updatedAt: timestamp

Regras de preenchimento:
- Owner:
  - role = owner
  - ownerId = uid
  - gerenteId = null
  - representanteId = null
- Gerente:
  - role = gerente
  - ownerId = uid do owner
  - gerenteId = uid do proprio gerente
  - representanteId = null
- Representante:
  - role = representante
  - ownerId = uid do owner
  - gerenteId = uid do gerente responsavel
  - representanteId = uid do proprio representante
- Vendedor:
  - role = vendedor
  - ownerId = uid do owner
  - gerenteId = uid do gerente da arvore
  - representanteId = uid do representante responsavel

## 2) Colecao clientes
Caminho: clientes/{clienteId}

Campos sugeridos:
- clienteId: string
- razaoSocial: string
- cnpj: string
- ativo: bool
- permite_88: bool
- permite_885: bool
- permite_89: bool
- ownerId: string
- gerenteId: string
- representanteId: string
- vendedorId: string
- createdAt: timestamp
- updatedAt: timestamp

Observacao:
- Cada cliente deve pertencer a um unico vendedor no campo vendedorId.
- O restante da arvore deve ser redundante no documento para enforcement de regras.

## 3) Colecao pedidos
Caminho: pedidos/{pedidoId}

Campos sugeridos:
- pedidoId: string
- clienteId: string
- vendedorId: string
- representanteId: string
- gerenteId: string
- ownerId: string
- status: string (pendente_envio | enviado)
- itens: array
- totalBruto: number
- totalLiquido: number
- AD_DESCLIDER: number
- AD_MANGA1: number
- AD_MANGA2: number
- AD_MANGA3: number
- AD_MANGA4: number
- createdAt: timestamp
- updatedAt: timestamp

## Regras de visibilidade esperadas
- Owner: ve tudo.
- Gerente: ve a propria ficha e dados cujo gerenteId == seu uid.
- Representante: ve a propria ficha e dados cujo representanteId == seu uid.
- Vendedor: ve a propria ficha e dados cujo vendedorId == seu uid.
- Nenhum perfil ve pares de mesmo nivel fora da propria arvore.

## Observacao importante
Para impedir escalacao de privilegio por escrita indevida:
- usuarios deve ser gerenciado apenas por Owner (ou por backend admin, futuramente).
- em clientes/pedidos, validar que os campos de escopo batem com o usuario autenticado.
