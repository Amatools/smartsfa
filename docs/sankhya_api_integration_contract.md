# SmartSFA - Contrato de Integracao Sankhya API (OpenAPI-first)

## Objetivo

Definir um padrao unico para qualquer implementacao de integracao com Sankhya API no SmartSFA.

A regra principal e: contrato tecnico vem de OpenAPI; documentacao de ajuda/comunidade vem como apoio funcional.

## Fonte de verdade por tipo de informacao

1. Contrato de endpoint (rota, metodo, params, body, response, codigos de erro): OpenAPI oficial Sankhya.
2. Fluxo de negocio e troubleshooting: base de ajuda/comunidade Sankhya.
3. Decisoes internas de arquitetura do app: documentos deste repositorio.

## Estrutura recomendada no projeto

- Pasta para contratos de API:
  - `docs/sankhya-api/openapi/`
- Pasta para exemplos de chamadas:
  - `docs/sankhya-api/examples/`
- Guia operacional (este arquivo):
  - `docs/sankhya_api_integration_contract.md`

## Politica de implementacao

Para cada nova integracao Sankhya, registrar no PR ou na tarefa:

1. Endpoint e metodo HTTP.
2. Requisitos de autenticacao.
3. Headers obrigatorios.
4. Parametros de path/query obrigatorios e opcionais.
5. Schema minimo de request.
6. Schema minimo de response usado pelo app.
7. Matriz de erros esperados e comportamento de fallback.

## Checklist tecnico (obrigatorio)

1. Validar endpoint no contrato OpenAPI antes de codar.
2. Confirmar payload minimo que atende a regra de negocio do app.
3. Definir timeout, retry e tratamento para 429/5xx.
4. Registrar mapping de erros para mensagens de negocio no app.
5. Adicionar teste de contrato (ou teste de integracao minimo) para o endpoint.

## Regra para o Copilot no projeto

Quando a pergunta for sobre integracao Sankhya API:

1. Priorizar contrato OpenAPI.
2. So depois usar ajuda/comunidade para contexto de processo.
3. Explicitar no resultado de onde veio cada informacao (contrato x apoio).

## Coexistencia MCP (ajuda + contrato)

- O workspace pode operar com dois servidores MCP distintos:
  - Sankhya Ajuda: base de conhecimento para contexto funcional e troubleshooting.
  - Sankhya OpenAPI: fonte de contrato tecnico dos endpoints.
- A presenca dos dois servidores nao muda a prioridade: contrato tecnico sempre deve vir do OpenAPI.

## Modelo de especificacao por endpoint (template)

Use este bloco para documentar cada endpoint integrado:

```md
### [NOME LOGICO DO ENDPOINT]

- Metodo: GET|POST|PUT|DELETE
- Path: /vX/...
- Auth: [tipo]
- Headers obrigatorios:
  - Header-A: ...
- Query params:
  - campoX (obrigatorio|opcional): tipo, regra
- Path params:
  - id (obrigatorio): tipo, regra
- Request body:
  - campoA: tipo, obrigatoriedade
- Response usada pelo app:
  - campoR: tipo, uso no SmartSFA
- Erros esperados:
  - 400: ...
  - 401/403: ...
  - 404: ...
  - 429/5xx: estrategia de retry
- Observacoes:
  - incompatibilidades conhecidas
  - limites de pagina
```

## Observacoes operacionais

- O MCP de ajuda Sankhya ja configurado no ambiente e excelente para conhecimento funcional, porem nao substitui OpenAPI para contrato tecnico de integracao.
- Sempre que atualizar a versao da API no portal Sankhya, revisar contratos usados pelo SmartSFA.
