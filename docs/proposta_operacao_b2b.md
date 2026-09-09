# SmartSFA - Proposta de Operacao B2B e Regras de Cadastro

## Objetivo

Registrar a proposta funcional e tecnica do produto para orientar implementacao, onboarding de novos usuarios e decisoes futuras sobre cadastros, aprovacao e integracao com ERP.

## Premissas

- O produto e B2B, mesmo quando o representante pessoa fisica vende para lojas com CNPJ.
- A representacao comercial pode ser feita por CPF, enquanto o cliente final pode ser CPF ou CNPJ.
- O tenant existe mesmo quando nao ha ERP; o modo de operacao pode ser manual/self-service.
- Para o primeiro tenant teste, Sankhya e a fonte principal de integracao.

## 1) Produtos

### Regra principal

Cada tenant deve definir apenas uma origem principal de produtos por vez.

As origens permitidas sao:

- ERP
- Excel
- Manual

### Recomendacao pratica

- A origem principal deve ser escolhida no onboarding do tenant.
- O usuario nao deve misturar origens simultaneamente para o mesmo catalogo sem regra clara de precedencia.
- O Excel deve ser usado como mecanismo padrao de carga inicial ou manutencao quando o tenant nao tiver ERP.
- O cadastro manual de produtos deve ficar restrito a tenants pequenos, operacao assistida ou excecoes aprovadas.

### Excel padrao

- O app deve oferecer download de um template padrao.
- O template deve conter colunas obrigatorias, colunas opcionais e exemplos validos.
- A importacao precisa validar campos, tipos, duplicidade, tabela de preco e itens inativos antes de gravar.
- A importacao deve ser idempotente, com chave externa por tenant.

### Recomendacao de dominio

- Produto precisa ter identificador canonico por tenant.
- Deve existir `codigoInterno`, `idExternoERP` e alias/import key quando necessario.
- O sistema deve suportar produto inativo, substituido e em descontinuidade.

## 2) Clientes

### Regra principal

Cliente deve ter uma entidade canonica por tenant e um fluxo separado de pre-cadastro.

### Origem preferencial

- Se houver ERP, o cadastro oficial vem do ERP.
- Se nao houver ERP, o cadastro pode ser feito via pre-cadastro e aprovado pelo tenant.
- O usuario final nao deve criar cliente oficial direto sem regra de permissao.

### Pre-cadastro

- Pre-cadastro nao deve ser tratado como cliente oficial incompleto.
- Pre-cadastro deve existir como entidade de aprovacao ou status separado.
- O pedido pode referenciar pre-cadastro, mas o pedido final deve ser promovido quando o cliente for aprovado.

### Aprovacao recomendada

- Default: aprovacao por owner ou gerente do tenant.
- Bootstrap inicial: o primeiro owner pode se autoaprovar apenas na criacao do tenant.
- Tenant pequeno sem ERP: pode existir autoaprovacao configuravel, mas isso deve ser opt-in e auditado.
- Operacao normal: o usuario que criou o pre-cadastro nao deve ser o unico aprovador.

### Duplicidade e merge

- O sistema deve normalizar CPF/CNPJ antes de comparar registros.
- A chave de deduplicacao principal deve ser o documento normalizado.
- Se o ERP trouxer um cliente que ja existe como pre-cadastro, o sistema deve fazer merge e manter o historico.
- O mesmo cliente pode ter aliases de origem, mas apenas um registro canonico por tenant.

### Recomendacao de dominio

- Cliente precisa suportar status como: `rascunho`, `pendente_aprovacao`, `aprovado`, `sincronizado`, `bloqueado`, `inativo`.
- Cliente precisa suportar multiplos enderecos, contatos e associacao com grupo economico quando existir.

## 3) Pedidos

### Regra principal

Pedido pode nascer ligado a um cliente aprovado ou a um pre-cadastro.

### Comportamento recomendado

- Se o cliente ja estiver aprovado, o pedido segue normalmente.
- Se o cliente estiver pendente, o pedido pode ser salvo em rascunho ou fila provisoria.
- Se o cliente for aprovado depois, o pedido deve ser reconciliado com o cliente canonico.
- Se o ERP criar o cliente depois, o sistema deve atualizar o vinculo sem duplicar pedido.

### Estados uteis

- `rascunho`
- `pendente_cliente`
- `pendente_envio`
- `enviado`
- `erro`
- `cancelado`

## 4) Cenarios sem ERP

Quando o tenant nao tiver ERP, a recomendacao e:

- manter tenant e usuarios normalmente;
- permitir carga inicial por Excel;
- permitir pre-cadastro de clientes com aprovacao por owner/gerente;
- manter produto via Excel ou cadastro manual controlado;
- exigir trilha de auditoria para criacao e aprovacao.

### Nao recomendado por padrao

- liberar tudo sem aprovacao;
- permitir cadastro manual irrestrito para qualquer perfil;
- usar nome como unica chave de deduplicacao.

## 5) Regras de identificacao e deduplicacao

### Clientes

- Normalizar CPF/CNPJ removendo mascaras e validando tamanho.
- Tratar nome fantasia, razao social e apelido como campos auxiliares.
- Usar telefone e email apenas como apoio para matching, nunca como unica chave.

### Produtos

- Usar codigo interno, codigo ERP e eventuais aliases.
- Permitir substituicao e descontinuidade sem apagar historico.

### Merge recomendado

- primeiro documento canonico encontrado vence;
- demais registros viram aliases ou referencias de origem;
- historico e pedidos permanecem associados ao registro canonico.

## 6) Casos comuns que o sistema precisa suportar

- cliente com multiplos enderecos;
- cliente com multiplos contatos;
- matriz e filial;
- grupo economico;
- cliente bloqueado por credito;
- produto inativo ou substituido;
- tabela de preco por cliente, grupo ou campanha;
- pedido offline que depois encontra cadastro oficial no ERP;
- representante CPF vendendo para loja CNPJ;
- visita a novo cliente sem ERP e com aprovacao posterior.

## 7) Decisoes de produto recomendadas

- Produto deve ter origem principal unica por tenant.
- Cliente deve ter pre-cadastro separado de cadastro oficial.
- Aprovação padrao deve ser por owner/gerente, nao pelo criador, exceto bootstrap inicial.
- Deduplicacao deve ser por documento normalizado e chaves externas.
- Importacao por Excel deve usar template padrao versionado.
- ERP deve ser fonte de verdade sempre que existir e estiver ativo.

## 8) Como isso aparece para o usuario novo

### Para o representante

- escolhe tenant e perfil;
- consulta clientes e produtos autorizados;
- cadastra pre-cliente quando necessario;
- cria pedido mesmo em modo offline ou com cliente pendente, conforme politica do tenant.

### Para o usuario novo sem vinculacao previa

- autentica com Google ou provedor autorizado;
- o backend verifica se existe membership em algum tenant;
- se existir convite valido, o app vincula o usuario ao tenant certo;
- se nao existir, o usuario escolhe entre solicitar acesso, entrar por convite ou criar workspace pessoal, se essa opcao estiver ativa.

### Como o sistema escolhe entre tenant A, tenant B ou uso singular

- o tenant nao e escolhido por inferencia de email;
- o tenant e escolhido por membership ativo ou convite valido;
- se houver mais de um membership ativo, o app mostra seletor de tenant;
- se houver zero memberships e o produto permitir, o app oferece workspace pessoal;
- se a politica do produto nao permitir workspace pessoal, o app fica em solicitacao de acesso.

### Para o owner/gerente

- aprova pre-cadastros;
- revisa duplicidades;
- define origem principal de produtos;
- valida cargas de Excel e sincronizacoes ERP.

### Para o admin da plataforma

- acompanha tenants;
- garante isolamento;
- apoia onboarding e governanca;
- nao participa da hierarquia comercial do tenant.

## 9) Proxima evolucao tecnica

1. Refinar o modelo de dominio para incluir status de aprovacao e origem principal.
2. Criar entidades separadas para pre-cadastro, cliente canonico e aliases de integracao.
3. Implementar importador de Excel com template versionado.
4. Definir merge/deduplicacao por documento normalizado e id externo.
5. Ajustar o fluxo de pedidos para aceitar cliente pendente com reconciliação posterior.
6. Formalizar o fluxo de primeira entrada com convite, solicitacao de acesso e workspace pessoal opcional.