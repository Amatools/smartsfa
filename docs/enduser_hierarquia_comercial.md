# SmartSFA - Como Funciona a Hierarquia Comercial

## Para quem e este guia

Este guia foi feito para clientes do SmartSFA entenderem, em linguagem simples, como funciona a hierarquia de usuarios e a visao de resultados no sistema.

## Resumo rapido

No SmartSFA, voce pode operar de tres jeitos:

1. Individual (sem equipe)
2. Representacoes (com equipe)
3. Empresa / Enterprise (com equipe e foco corporativo)

Quando existe equipe, o SmartSFA usa a hierarquia:

- Owner > Gerente > Representante > Vendedor

## Plano individual

No plano individual:

- o tenant e de uso pessoal;
- nao existe equipe compartilhando a mesma operacao;
- voce trabalha sozinho, com acesso apenas ao seu proprio contexto.

## Plano com equipe (Representacoes e Empresa)

Quando sua operacao tem equipe:

- existe owner, gerente, representante e vendedor;
- cada nivel enxerga dados do seu proprio escopo;
- o owner pode reorganizar a estrutura quando precisar.

## Modo Empresa (Enterprise)

No modo Empresa (workspace enterprise):

- o tenant representa a propria empresa contratante;
- a conta que cria esse workspace fica dedicada ao contexto enterprise;
- essa conta nao pode criar outros tipos de workspace depois;
- para entrar em outro tenant enterprise, o caminho correto e convite.

### Regra importante sobre convidados no Enterprise

No enterprise, os convidados entram como membros da equipe (gerente, representante ou vendedor), sem virar owner.

Na pratica:

- o owner do enterprise e o dono do tenant da empresa;
- convidados podem participar do enterprise por convite;
- convidados podem continuar tendo outros workspaces no SmartSFA, desde que nao sejam owner de um workspace enterprise.

Isso permite que sua empresa mantenha ownership claro do tenant enterprise, sem bloquear operacoes de usuarios convidados em outros contextos quando permitido.

## Posso comecar sozinho no plano com equipe?

Sim.

Esse e um ponto importante do SmartSFA:

- voce nao precisa cadastrar todo mundo no primeiro dia;
- o owner pode iniciar a operacao sozinho;
- depois, conforme sua equipe cresce, voce inclui novos usuarios e reorganiza as carteiras.

## Como a hierarquia fica completa desde o inicio

Para nao travar seu onboarding, o SmartSFA cria uma base inicial valida de hierarquia para o owner.

Assim, voce pode iniciar a operacao e completar a equipe aos poucos, sem bloquear o uso do sistema.

## Exemplo pratico: adicionando vendedor antes de gerente/representante

Imagine que voce e owner e quer convidar um vendedor agora, mas ainda nao criou gerente e representante.

O que acontece:

1. O vendedor entra normalmente.
2. Ele entra abaixo da cadeia atual do owner.
3. Depois, quando voce criar um representante, pode mover esse vendedor para a nova carteira.

Resultado:

- operacao sem bloqueio;
- estrutura organizada;
- flexibilidade para crescer.

## O owner pode editar a hierarquia?

Sim.

O owner pode:

- mover vendedores entre representantes;
- reorganizar representantes entre gerentes;
- ajustar a estrutura conforme o negocio evolui.

Essas mudancas sao registradas com auditoria interna.

## O que cada nivel enxerga

### Vendedor

- suas vendas e seus indicadores.

### Representante

- seus proprios dados;
- resultados de todos os vendedores da sua carteira.

### Gerente

- seus proprios dados;
- resultados dos representantes da sua carteira;
- resultados dos vendedores desses representantes.

### Owner

- visao completa do tenant.

## Relatorios: por que existem duas visoes

O SmartSFA trabalha com duas formas de leitura:

1. Hierarquia atual (gestao do dia a dia)
2. Snapshot historico (numeros oficiais no momento da venda)

### Hierarquia atual

Mostra como sua equipe esta organizada hoje.

Use para:

- acompanhamento comercial;
- gestao de carteira;
- operacao diaria.

### Snapshot historico

Guarda em cada pedido quem era o owner/gerente/representante/vendedor no momento da venda.

Use para:

- historico oficial;
- auditoria;
- fechamento de resultados sem distorcer periodos passados.

## Qual visao e mais importante no momento?

As duas visoes sao complementares:

- hierarquia atual para acompanhar a operacao diaria;
- snapshot historico para manter consistencia de auditoria e fechamento de resultados.

## Beneficios para sua empresa

- Comeco rapido sem travar por estrutura incompleta.
- Crescimento da equipe sem quebrar o processo.
- Reorganizacao de carteiras com controle.
- Visibilidade por nivel hierarquico.
- Base pronta para relatorios robustos.

## Perguntas frequentes

### Preciso cadastrar toda a hierarquia antes de vender?

Nao. O owner pode comecar sozinho e evoluir a estrutura depois.

### Se eu mover um vendedor de carteira, perco historico?

Nao. O historico de pedidos continua preservado para analise oficial.

### O vendedor ve dados de outros vendedores?

Nao. Cada vendedor ve apenas seu proprio escopo.

### O owner pode ver tudo?

Sim. O owner tem visao completa do tenant.
