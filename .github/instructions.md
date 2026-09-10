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

## Arquitetura esperada

- telas focadas em apresentação e interação;
- serviços para regras e persistência;
- repositories para acesso ao dado;
- fila local para pendências offline;
- aprovação de pré-cadastros na tela de clientes quando o usuário for dono do workspace ou tiver permissão.
