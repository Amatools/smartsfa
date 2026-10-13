# SmartSFA - Proposta de Operacao B2B (resumo consolidado)

## Objetivo

Este documento foi reduzido para diminuir duplicacao e manutencao paralela.

Ele preserva apenas os principios de negocio mais estaveis.

## Principios ativos

1. Produto e B2B multi-tenant, com isolamento por tenantId.
2. Produto, cliente e pedido precisam operar com e sem ERP.
3. Cliente oficial e pre-cadastro devem permanecer entidades separadas.
4. Importacao por planilha e fluxo oficial do produto (nao excecao).
5. Deduplicacao deve usar documento normalizado e chaves externas.

## Fontes canonicas para implementacao

1. guia_implementacao_saas.md
2. auth_access_model.md
3. pricing_taxation_rules.md
4. web_portal_architecture.md

## Direcao de proxima fase

1. Sincronizacao incremental para catalogos extensos (produtos, clientes, tabelas e tributacao).
2. Paginacao em listagens para reduzir leituras completas.
3. Pre-download por modulo antes de uso em campo.