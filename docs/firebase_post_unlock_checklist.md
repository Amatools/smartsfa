# Checklist pos-desbloqueio do Firebase

Use este checklist quando a conta Google/Firebase voltar a permitir acesso administrativo ao projeto `smart-sfa`.

## 1. Refazer autenticacao do CLI

```powershell
firebase login
```

## 2. Confirmar o projeto ativo

```powershell
firebase projects:list
firebase use smart-sfa
```

## 3. Validar se o estado remoto continua integro

Verificar manualmente:

- testar login no app com `empresa@smartsfa.com.br`
- abrir a aba Conta e conferir se a Amatools continua no contexto `Empresa`
- conferir se `Conta BrandOp` continua visivel para essa conta

## 4. Republicar as regras pendentes

A ultima alteracao do contexto `Representacoes` ficou dependente de acesso administrativo valido.

```powershell
firebase deploy --only firestore:rules
```

## 5. Reexecutar o script oficial da conta enterprise

```powershell
cd G:\smartsfa\scripts\bootstrap_owner
node provision_enterprise_account.mjs
```

## 6. Reexecutar o script oficial dos contextos de teste

```powershell
cd G:\smartsfa\scripts\bootstrap_owner
node provision_workspace_contexts_v2.mjs
```

## 7. Validar os cenarios no app

Esperado:

- `empresa@smartsfa.com.br` deve ficar apenas em `Empresa`
- `owner@smartsfa.com.br`, `gerente@smartsfa.com.br`, `representante@smartsfa.com.br`, `vendedor@smartsfa.com.br` devem ficar em `Representacoes`
- `roberto.solo@smartsfa.com.br` deve ficar em `Individual`

## 8. Conferir a hierarquia esperada em Representacoes

Esperado:

- `owner` cria e gerencia `gerente`
- `gerente` cria e gerencia `representante`
- `representante` cria e gerencia `vendedor`

## 9. Conferir o contexto visual no portal

Esperado:

- `Conta MultiOp` e `Conta BrandOp`
- `Workspace` com rotulos `Individual`, `Representacoes`, `Empresa`
- `Seu acesso atual` contextualizado corretamente

## 10. Criar redundancia administrativa

Depois do desbloqueio:

- adicionar outra conta administradora no projeto Firebase
- gerar uma service account tecnica para automacoes e scripts

## Observacao

Enquanto a conta estiver bloqueada:

- o que ja esta no Firebase nao deve sumir
- a evolucao local do app pode continuar normalmente
- quando o acesso voltar, este checklist fecha a parte remota pendente
