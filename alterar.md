1. Auditoria obrigatória por ação crítica.
   Linha do tempo por usuário com antes/depois, ator, motivo e IP/dispositivo.
2. Impersonation segura (suporte assistido).
   Entrar como cliente por tempo curto com banner forte e trilha de auditoria.
3. Estados de billing mais explícitos.
   Máquina de estados com regras de transição, bloqueios automáticos e reativação guiada.
4. Gestão de planos e limites.
   Seats, storage, APIs, módulos habilitados, e consumo em tempo real por tenant.
5. Fila de operações e reprocessamento.
   Jobs administrativos com status, retry, dead-letter e botão de replay.
6. Alertas operacionais.
   Tenants sem owner ativo, expirações próximas, picos de erro e ações recomendadas.
7. Permissões granulares no próprio painel de mantenedor.
   RBAC de plataforma (admin/operator/readonly) por feature, não só papel global.
8. Centro de suporte por tenant.
   Resumo único: usuários, memberships, billing, integrações e últimos eventos.



**Próximos passos recomendados para continuar Asaas (ordem prática):**

1. Normalizar contrato de resposta (backend + frontend) para campos provider-agnostic, mantendo fallback de leitura para campos antigos.
2. Desacoplar catálogo de planos de Stripe no caminho Asaas (ou criar catálogo interno único, como previsto no plano).
3. Implementar seat addons para Asaas (ou bloquear explicitamente na UI quando provider for Asaas, com mensagem de produto).
4. Unificar webhook/reconcile em endpoints canônicos de billing (mantendo wrappers legados para compatibilidade).
5. Atualizar documentação que ficou defasada (há docs ainda dizendo que Asaas estava “planned”):
   [billing_unified_provider_contract.md**:20**](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/1b6a188127/resources/app/out/vs/code/electron-browser/workbench/workbench.html)
