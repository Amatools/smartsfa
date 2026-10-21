# Sankhya API - OpenAPI no SmartSFA

Este diretorio concentra o material tecnico de contrato para integracoes com a Sankhya API.

## Estrutura

- `openapi/`: arquivo(s) oficial(is) da especificacao OpenAPI em uso.
- `examples/`: exemplos de chamadas HTTP reais usadas no projeto.

## Fluxo recomendado

1. Obter a especificacao OpenAPI oficial no portal de developer Sankhya.
2. Salvar o arquivo em `openapi/` com nome versionado, por exemplo:
   - `sankhya-openapi-v1.2.0.yaml`
3. Registrar no PR quais endpoints novos/alterados passaram a ser usados no app.
4. Atualizar exemplos em `examples/` quando houver mudanca de payload/headers.
5. Validar implementacoes do app contra o contrato antes de merge.

## Convencoes

- Nao alterar manualmente o arquivo oficial da spec sem registrar origem da mudanca.
- Preferir adicionar nova versao da spec em vez de sobrescrever sem historico.
- Qualquer duvida de contrato tecnico deve ser resolvida pelo OpenAPI, nao por texto de artigo.

## Checklist de revisao

1. Endpoint/metodo conferem com OpenAPI.
2. Headers obrigatorios foram enviados.
3. Campos obrigatorios do request foram mapeados.
4. Tratamento de 4xx/5xx implementado.
5. Timeout/retry definidos para chamadas remotas.
