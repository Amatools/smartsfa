# SmartSFA - Backlog de Execucao (Asaas Internal Billing Engine)

## Objetivo

Traduzir o plano arquitetural em backlog tecnico executavel, sem quebrar o fluxo Stripe atual.

## Escopo desta execucao

1. Manter Stripe como esta (fluxo nativo atual).
2. Construir, para Asaas, o motor interno de billing no SmartSFA.
3. Entregar base para planos, seats, quote, checkout e governanca operacional.

## Premissas de negocio

1. Preco para Asaas deve ser calculado no backend, nunca no frontend.
2. Seats extras possuem teto de autoatendimento por plano.
3. Acima do teto de seats, fluxo obrigatorio de suporte/comercial.
4. Proration nao entra no MVP (entra em fase futura).

## Premissas tecnicas

1. Contrato unificado de provider permanece: Stripe + Asaas por dispatch.
2. Status canonicos em `tenants/{tenantId}` permanecem a fonte de verdade.
3. Auditoria obrigatoria para alteracao de plano, seats e valor.
4. Regressao Stripe bloqueia rollout.

## Definition of Ready (DoR)

Uma tarefa so pode iniciar quando:

1. Endpoint, colecao e payload esperados estao definidos.
2. Regras de permissao (owner/admin/suporte) estao documentadas.
3. Criterio de aceite e regressao estao definidos.

## Definition of Done (DoD)

Uma tarefa so e concluida quando:

1. Codigo entregue + testes automatizados minimos.
2. `flutter analyze` e check de sintaxe backend sem erros.
3. Auditoria persistida quando aplicavel.
4. Documentacao de contrato atualizada em `docs/access-and-billing`.

## Epicos

## E0 - Fundacao de dominio e contratos

### Objetivo

Criar a base de dados e contratos para suportar preco/seats no dominio interno.

### Tarefas

1. Criar colecao `billing_plan_catalog`.
2. Criar colecao `tenant_billing_contracts`.
3. Criar colecao `tenant_billing_seat_changes`.
4. Criar colecao `billing_quotes`.
5. Criar colecao `billing_provider_refs`.
6. Definir indices necessarios no Firestore.
7. Definir padrao de versionamento de plano (`version`) e imutabilidade de quote.

### Criterios de aceite

1. Schema validado por fixtures de exemplo (base, pro, enterprise).
2. Regras de seguranca inicial para leitura/escrita por papel implementadas.
3. Nao ha impacto em endpoints Stripe existentes.

## E1 - Quote Engine Asaas (MVP sem proration)

### Objetivo

Calcular valor final no backend para Asaas e congelar cotacao antes do checkout.

### Tarefas

1. Implementar endpoint `createBillingQuote`.
2. Calcular total: base + seats extras.
3. Persistir quote com `expiresAt`, `checksum` e `status=open`.
4. Implementar validacao de idempotencia de quote.
5. Implementar expiracao de quote (job ou validacao em runtime).

### Criterios de aceite

1. Frontend nao consegue forcar valor diferente do quote.
2. Quote expirada nao abre checkout.
3. Mudanca de plano/seats apos quote invalida quote antiga.

## E2 - Checkout Asaas orientado por quote

### Objetivo

Usar quote valida para criar checkout Asaas com valor calculado internamente.

### Tarefas

1. Integrar `createBillingCheckoutSession` com `billing_quotes`.
2. Rejeitar criacao de checkout sem quote valida.
3. Persistir referencia de checkout/assinatura em `billing_provider_refs`.
4. Registrar auditoria de tentativa e sucesso/erro.

### Criterios de aceite

1. Todo checkout Asaas aponta para quote usada (`status=used`).
2. Nao existe caminho de checkout Asaas por valor livre.
3. Stripe continua com comportamento atual (nao regressivo).

## E3 - Governanca de seats e limites

### Objetivo

Controlar alteracao de seats com teto self-service por plano.

### Tarefas

1. Implementar endpoint `previewTenantSeatPackChange`.
2. Implementar endpoint `changeTenantSeatPack`.
3. Validar teto `maxSelfServiceExtraSeats`.
4. Persistir trilha em `tenant_billing_seat_changes`.
5. Atualizar entitlement de seats no tenant apos alteracao valida.

### Criterios de aceite

1. Alteracao dentro do teto funciona para owner/admin autorizado.
2. Alteracao acima do teto retorna bloqueio orientando suporte.
3. Trilha de auditoria contem antes/depois, ator e razao.

## E4 - Painel admin (catalogo e operacao)

### Objetivo

Habilitar operacao de planos/seats no painel sem alterar Stripe.

### Tarefas

1. Criar CRUD de plano interno Asaas no painel admin.
2. Exibir parametros de preco e limite de seats por plano.
3. Exibir estado contratado por tenant (`tenant_billing_contracts`).
4. Criar acao assistida de override de seats para suporte/comercial.
5. Exibir historico de alteracoes de seats e quotes.

### Criterios de aceite

1. Alteracao de plano gera nova versao de catalogo sem quebrar contratos antigos.
2. Override exige permissao elevada e deixa trilha obrigatoria.
3. Fluxo Stripe admin atual continua operacional.

## E5 - Reconciliacao, observabilidade e operacao

### Objetivo

Garantir consistencia entre dominio interno e eventos do provider.

### Tarefas

1. Reconciliar assinatura Asaas para status canonico no tenant.
2. Criar monitoramento de divergencia:
   - contrato interno vs provider;
   - entitlement vs contrato.
3. Criar dashboard operacional minimo para falhas de quote/checkout.
4. Definir playbook de suporte para falhas comuns.

### Criterios de aceite

1. Divergencia critica gera alerta operacional.
2. Reprocessamento e idempotencia funcionam sem duplicar efeitos.
3. Nao regressao comprovada para webhooks/fluxos Stripe.

## E6 - Proration (fase evolutiva)

### Objetivo

Adicionar calculo proporcional de cobranca para alteracoes intra-ciclo.

### Tarefas

1. Definir regra de prorata por ciclo e data de corte.
2. Implementar simulacao de impacto financeiro.
3. Implementar liquidacao:
   - cobranca avulsa; ou
   - credito/debito no proximo ciclo.
4. Auditoria detalhada de calculo aplicado.

### Criterios de aceite

1. Resultado de prorata reproduzivel por formula documentada.
2. Ajuste financeiro rastreavel de ponta a ponta.
3. Feature com flag para rollout gradual.

## Planejamento por sprint (sugestao)

## Sprint 0 - Contratos e base de dados

Entrega:

1. E0 completo.
2. Testes de schema e seguranca de colecoes.

Gate:

1. Sem E0 completo, nao iniciar quote engine.

## Sprint 1 - Quote + Checkout Asaas (MVP)

Entrega:

1. E1 completo.
2. E2 completo.

Gate:

1. Checkout Asaas obrigatoriamente acoplado a quote valida.

## Sprint 2 - Seats e limites

Entrega:

1. E3 completo.
2. Ajustes de entitlement por seats.

Gate:

1. Teto de seats aplicado no backend com bloqueio real.

## Sprint 3 - Painel admin

Entrega:

1. E4 completo.
2. Auditoria visivel no painel para operacao.

Gate:

1. Operacao manual com permissao e trilha obrigatorias.

## Sprint 4 - Operacao e hardening

Entrega:

1. E5 completo.
2. Suite de regressao Stripe + Asaas publicada.

Gate:

1. So liberar rollout apos regressao verde.

## Sprint futuro - Proration

Entrega:

1. E6 sob feature flag.

## Matriz minima de testes

## Regressao Stripe (obrigatoria)

1. Checkout Stripe.
2. Portal Stripe.
3. Webhook Stripe (eventos principais).
4. Reconciliacao Stripe.
5. Seat governance existente.

## Funcional Asaas (MVP)

1. Criacao de quote valida.
2. Bloqueio de quote expirada.
3. Checkout Asaas por quote.
4. Alteracao de seats dentro do teto.
5. Bloqueio acima do teto.
6. `stop_renewal` e `cancel_now` preservados.

## Rollout e seguranca

1. Feature flag por provider e por tenant para partes novas.
2. Rollout progressivo por lote de tenants.
3. Plano de rollback:
   - desativar novas rotas Asaas por flag;
   - manter Stripe inalterado;
   - preservar contratos/quotes para analise pos-incidente.

## Riscos principais e mitigacoes

1. Risco: divergencia entre valor calculado e valor cobrado.
   - Mitigacao: quote imutavel + checksum + auditoria.
2. Risco: regressao Stripe durante evolucao Asaas.
   - Mitigacao: adapter isolado + suite regressiva obrigatoria.
3. Risco: escalada manual de suporte sem trilha.
   - Mitigacao: override com permissao elevada e log obrigatorio.
4. Risco: crescimento de complexidade com proration precoce.
   - Mitigacao: proration fora do MVP, com fase dedicada.

## Decisao de inicio

Implementacao deve iniciar por Sprint 0 e Sprint 1.

Proration fica explicitamente fora da primeira entrega.
