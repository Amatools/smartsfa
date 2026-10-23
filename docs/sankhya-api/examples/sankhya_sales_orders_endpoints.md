# Sankhya Sales Orders Endpoints (Pre-configuracao SmartSFA)

Fonte: contrato OpenAPI Sankhya (catalogo MCP de endpoints)
Ambientes:
- Produção: https://api.sankhya.com.br
- Sandbox: https://api.sandbox.sankhya.com.br

## Endpoints liberados para SmartSFA

### 1) Incluir pedido
- Metodo: POST
- Path: /v1/vendas/pedidos
- Uso SmartSFA: criacao de pedido no ERP (push do pedido aprovado/local->erp)
- Escopo esperado: write:vendas/pedidos

### 2) Atualizar pedido
- Metodo: PUT
- Path: /v1/vendas/pedidos/{codigoPedido}
- Uso SmartSFA: ajuste de itens/cabecalho no ERP enquanto pedido ainda elegivel
- Escopo esperado: write:vendas/pedidos

### 3) Cancelar pedido
- Metodo: POST
- Path: /v1/vendas/pedidos/{codigoPedido}/cancela
- Uso SmartSFA: cancelamento logico no ERP com motivo
- Escopo esperado: write:vendas/pedidos + read:vendas/pedidos

### 4) Consultar pedidos
- Metodo: GET
- Path: /v1/vendas/pedidos
- Uso SmartSFA: conciliacao de status entre ERP e SaaS
- Escopo esperado: read:vendas/pedidos

## Endpoint fiscal encontrado para calculo de impostos

### 5) Calcular impostos em vendas
- Metodo: POST
- Path: /v1/fiscal/impostos/calculo
- Uso SmartSFA: referencia de calculo fiscal oficial no ERP para validacao e reconciliacao

## Observacao arquitetural (offline-first)

Para o SmartSFA operar offline com previsibilidade:
- manter motor local de impostos no SaaS (tax_rules em Firestore + cache local);
- usar /v1/fiscal/impostos/calculo como validacao server-side quando online;
- registrar divergencias entre calculo local x ERP para ajuste de regra.

## Proximo passo sugerido

1. Criar modulo de sincronizacao fiscal (tax_rules) separado do modulo de pedidos.
2. Definir payload minimo do /v1/fiscal/impostos/calculo em um exemplo controlado por tenant.
3. Implementar reconciliacao: se divergencia > tolerancia, gravar alerta fiscal no pedido.
