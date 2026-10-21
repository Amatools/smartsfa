# Instruções de desenvolvimento do projeto SmartSFA

## Regra obrigatória para todas as respostas

1. Após qualquer alteração de código relevante, executar o relançamento do Chrome antes de encerrar a resposta.
2. Usar sempre o máximo de SRP possível.
3. Manter o código desacoplado por camada e responsabilidade.
4. Não misturar UI, regras de negócio e persistência no mesmo componente.
5. Priorizar fluxo local-first/offline-first para o vendedor no campo.
6. Validar com o menor comando de teste/análise relevante.

## Fluxo de trabalho obrigatório

- Sempre que houver mudança em UI, autenticação, tenant, sincronização, fila local ou cadastro, executar:
  - relançamento do Chrome para refletir a alteração, fechando o anterior primeiro para não ter conflito de portas;
  - teste relevante;
  - análise do projeto quando necessário e dos arquivos md de documentação de projeto;
  - atualizar arquivos .MD do desenvolvimento do projeto conforme implementação;

## Execução Flutter no ambiente do usuário

- O usuário sempre executa o app com o comando:
  - `flutter run -d chrome --web-port 43177 --target lib/main.dart`
- Em tarefas de recarga/reconexão, assumir esse padrão de execução e porta.

## Arquitetura esperada

- telas focadas em apresentação e interação;
- serviços para regras e persistência;
- repositories para acesso ao dado;
- fila local para pendências offline;
- aprovação de pré-cadastros na tela de clientes quando o usuário for dono do workspace ou tiver permissão.

## Integração Sankhya (OpenAPI-first)

- Para dúvidas de integração com Sankhya API (rota, método, schema, headers, autenticação, paginação e erros), priorizar sempre o contrato formal OpenAPI antes de qualquer sugestão baseada em texto livre.
- Usar documentação de ajuda/comunidade do Sankhya apenas como apoio de processo funcional e troubleshooting, nunca como fonte principal de contrato técnico de endpoint.
- Quando houver divergência entre documentação textual e OpenAPI, considerar OpenAPI como fonte de verdade do contrato e sinalizar a divergência no resultado.
- Em propostas de implementação, incluir de forma explícita:
  - endpoint e método HTTP;
  - parâmetros obrigatórios e opcionais;
  - headers obrigatórios;
  - payload de request e formato de response esperado;
  - mapeamento de erros e estratégia de retry/timeout.
- Em mudanças de integração, preferir criar/atualizar testes de contrato e exemplos de chamada reais para reduzir regressão silenciosa.
