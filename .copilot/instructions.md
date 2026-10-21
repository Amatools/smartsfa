# Instruções de desenvolvimento do projeto SmartSFA

## Regras obrigatórias para todas as respostas e iterações

1. Após qualquer alteração de código relevante, executar o relançamento do Chrome antes de concluir a resposta.
2. Sempre validar o comportamento com o menor comando útil de teste/análise relevante.
3. Manter o máximo de SRP possível em todas as mudanças:
   - separar responsabilidades por camada;
   - evitar lógica de UI e persistência misturada;
   - extrair serviços/validators/repositories quando a regra sair do componente;
   - manter componentes focados na apresentação e em fluxo de interação.
4. Priorizar local-first e offline-first para o fluxo de vendedores e força de vendas.
5. Preservar o conceito de multitenancy e workspace pessoal sem conflitar acesso.

## Fluxo de validação solicitado

- Depois da edição de qualquer arquivo de código que afete a UI, autenticação, tenant, sincronização ou cadastro, executar:
  - relançamento do Chrome para refletir a alteração;
  - teste relevante, preferencialmente unitário ou de integração mínima;
  - análise do projeto quando necessário.

## Observação de arquitetura

- Componentes de tela não devem salvar dados diretamente sem serviço dedicado.
- Persistência local, fila de sincronização e regras de negócio devem estar isoladas.
- Regras de acesso, tenant e permissão devem ser tratadas fora do widget.

## Regra de trabalho

- Quando o app estiver em ambiente sem internet, o comportamento esperado é salvar localmente e sincronizar depois.
- Quando o app estiver online, o fluxo deve tentar persistir no backend e apenas cair para fila local em caso de falha real.

## Integracao Sankhya API (OpenAPI-first)

- Em qualquer tarefa de integracao com Sankhya API, tratar o contrato OpenAPI oficial como fonte primaria de verdade tecnica.
- Para definicao de endpoint, metodo, headers, parametros, payload e codigos de erro, validar primeiro no OpenAPI antes de propor ou alterar implementacoes.
- Usar base de ajuda/comunidade Sankhya apenas como apoio funcional e troubleshooting, nunca como contrato tecnico principal.
- Em caso de divergencia entre documentacao textual e contrato OpenAPI, seguir o OpenAPI e registrar a divergencia no resultado.
- Sempre que sugerir implementacao de integracao, explicitar:
  - endpoint e metodo HTTP;
  - parametros obrigatorios e opcionais;
  - headers obrigatorios;
  - schema de request e response usado no app;
  - tratamento de erros e estrategia de timeout/retry.
