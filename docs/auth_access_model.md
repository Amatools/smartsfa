# SmartSFA - Modelo de Login e Acesso

## Decisao adotada

- Login no app: Google (Firebase Authentication).
- Login oficial ja habilitado e em uso no projeto smart-sfa.
- Autorizacao de uso: interna por tenant via documentos em Firestore.
- Vinculo com Sankhya: opcional e controlado internamente (nao automatico no cliente).
- Direcao oficial: plataforma SaaS multi-tenant.
- Operacao sem ERP: suportada por cadastro/importacao manual.
- Operacao offline-first: apos primeiro login valido, a sessao e o cache local permitem continuar operando sem internet.

Esse modelo permite:

- Ter varias empresas usando a mesma plataforma com isolamento logico.
- Ter mais de um usuario no mesmo parceiro/cadastro do Sankhya.
- Bloquear qualquer conta Google nao liberada internamente.
- Manter historico e governanca de quem autorizou cada acesso.

## Fluxo de acesso

1. Usuario entra com Google.
2. App consulta memberships do usuario para descobrir a quais tenants ele pertence.
3. Se nao houver membership ativo, app mostra tela de solicitacao e grava solicitacoes_acesso/{uid} com status pendente.
4. Owner do tenant (ou operador de plataforma com permissao explicita) aprova internamente e cria/atualiza os vinculos do usuario.
5. App libera fluxo somente quando houver membership ativo no tenant selecionado.

## Como o app reconhece o tenant na primeira entrada

A melhor pratica nao e descobrir o tenant apenas pelo email. O tenant deve ser definido por vinculacao explicita.

### Fontes validas de vinculacao

- convite gerado pelo tenant com token unico;
- aprovacao manual do owner ou gerente;
- cadastro inicial feito pelo platform admin no onboarding do tenant;
- auto-vinculo somente em workspace pessoal ou tenant singular criado pelo proprio usuario, quando a politica do produto permitir.

### Regra de decisao na primeira entrada

1. O usuario autentica com Google.
2. O backend verifica se existe membership ativo para o uid.
3. Se existir apenas um tenant ativo, o app entra direto nele.
4. Se existirem varios tenants ativos, o app mostra seletor de tenant.
5. Se nao existir nenhum membership ativo, o app mostra uma tela de vinculo com tres caminhos:
	- entrar por convite;
	- solicitar acesso a um tenant;
	- criar workspace solo (self-service) para entrar como owner do proprio tenant.

Regra de uso recomendada:

- Solo: criar workspace solo e operar como owner.
- Team/Enterprise: entrar por convite do owner do tenant.
- Solicitacao de acesso: manter para fluxo assistido quando nao houver convite imediato.

### Sobre tenant A e tenant B

- o mesmo email pode existir em varios tenants;
- a selecao do tenant nao e inferida automaticamente pelo email;
- o tenant atual precisa ficar gravado na sessao do usuario como `defaultTenant`, quando houver mais de uma opcao.

### Workspace pessoal ou uso singular

Quando o produto permitir uso individual sem empresa, a melhor pratica e criar um tenant pessoal separado, nao misturar esse caso com tenant corporativo.

Esse tenant pessoal deve ter:

- um owner unico;
- sem hierarquia comercial completa, se o produto nao precisar;
- regras simplificadas de produto e cliente;
- possibilidade de migrar depois para um tenant corporativo, se necessario.

Regra de produto recomendada:

- vendedor solo nao deve existir como "vendedor sem superior".
- vendedor solo entra como owner do proprio tenant solo.
- quando convidar equipe, o mesmo tenant evolui para modelo team sem migracao de conta.

## Niveis recomendados de papel

### Nivel da plataforma (SaaS)

- platform_observer (recomendado): leitura global, saude da plataforma, suporte de diagnostico, sem alteracao estrutural.
- platform_operator (opcional): operacao assistida sob processo interno (onboarding, manutencao, correcao pontual).
- platform_admin (break-glass): acesso maximo para incidentes criticos, uso restrito e auditado.

Break-glass significa conta/papel de emergencia para situacoes como:

- indisponibilidade operacional que impede o owner de agir;
- incidente de seguranca com necessidade de contencao imediata;
- corrupcao/inconsistencia de vinculos que bloqueia faturamento ou operacao critica.

Nao deve ser o caminho padrao de suporte diario.

### Nivel do tenant (empresa cliente)

- owner: dono administrativo da empresa dentro da plataforma
- gerente
- representante
- vendedor

Hierarquia final:

- Plataforma (observer/operator/admin)
- Tenant
- Owner
- Gerente
- Representante
- Vendedor

Melhor pratica:

- Tenant nao e um usuario, e uma entidade organizacional.
- Owner e o topo da hierarquia comercial/administrativa da empresa cliente.
- Papel de plataforma nao substitui ownership do tenant, exceto em procedimento de suporte formal.

## Modelos de conta e monetizacao (direcao)

### Plano Solo

- usuario individual sem equipe;
- tenant solo com owner unico;
- sem integracao ERP obrigatoria;
- sincronizacao essencial e foco em baixo custo.

### Plano Team (sem ERP)

- escritorio de representacao/equipe comercial;
- owner paga a assinatura e convidados nao pagam individualmente;
- convites obrigatorios para entrada de gerente/representante/vendedor;
- dependencia maior de sincronizacao para visao de equipe.

### Plano Enterprise (com ERP)

- empresa cliente com integracao Sankhya (ou outro ERP);
- owner paga a assinatura corporativa;
- convidados entram por convite no tenant;
- Firestore segue como camada de colaboracao, acesso, offline e estado operacional.

## Estrutura recomendada (Firestore)

### tenants/{tenantId}

Campos:

- tenantId: string
- nomeFantasia: string
- razaoSocial: string?
- slug: string
- ativo: bool
- modoOperacao: manual | sankhya | outro_erp
- erpProvider: sankhya | none | custom
- branding: map
- createdAt: timestamp
- updatedAt: timestamp

### usuarios/{uid}

Campos:

- uid: string
- email: string
- displayName: string
- platformRole: platform_admin | none
- sankhyaPartnerIds: array<string>
- defaultTenantId: string? (sinal de conveniencia, nao e membership)
- lastSelectedTenantId: string? (sinal de conveniencia, nao e membership)
- activeMembershipCount: number? (sinal de conveniencia, nao e membership)
- createdAt: timestamp
- updatedAt: timestamp

Observacao:

- dados de hierarquia do tenant nao devem ficar soltos no documento raiz do usuario;
- o correto e modelar o vinculo do usuario com cada tenant separadamente.
- campos como defaultTenantId e lastSelectedTenantId sao apenas caches de UX;
- a fonte de verdade continua sendo tenant_memberships.

### tenant_memberships/{tenantId_uid}

Campos:

- membershipId: string
- tenantId: string
- uid: string
- role: owner | gerente | representante | vendedor
- ativo: bool
- ownerId: string
- gerenteId: string
- representanteId: string
- vendedorId: string
- defaultTenant: bool
- state: active | inactive | revoked
- revokedByUid: string?
- revokedReason: string?
- revokedAt: timestamp?
- lastSyncedAt: timestamp?
- createdAt: timestamp
- updatedAt: timestamp

Regras de preenchimento:

- owner: ownerId = uid; gerenteId = ''; representanteId = ''; vendedorId = ''
- gerente: ownerId = ownerUid; gerenteId = uid; representanteId = ''; vendedorId = ''
- representante: ownerId = ownerUid; gerenteId = gerenteUid; representanteId = uid; vendedorId = ''
- vendedor: ownerId = ownerUid; gerenteId = gerenteUid; representanteId = representanteUid; vendedorId = uid

### solicitacoes_acesso/{uid}

Campos:

- uid: string
- email: string
- displayName: string
- tenantSlugOuConvite: string?
- status: pendente | aprovado | rejeitado
- createdAt: timestamp
- updatedAt: timestamp
- reviewedBy: string?
- motivo: string?

### tenant_invitations/{token}

Campos sugeridos:

- token: string
- tenantId: string
- role: owner | gerente | representante | vendedor
- invitedEmail: string?
- defaultTenant: bool
- status: pending | accepted | expired | revoked
- expiresAt: timestamp?
- acceptedByUid: string?
- acceptedAt: timestamp?
- createdByUid: string?
- createdAt: timestamp?
- updatedAt: timestamp?

Regra de aceite:

- o usuario autenticado informa token;
- o sistema valida status e expiração;
- se invitedEmail existir, o e-mail autenticado deve bater;
- em caso valido, cria/atualiza tenant_memberships/{tenantId_uid};
- marca convite como accepted;
- revalida o acesso no app sem exigir logout manual.

Aceite obrigatorio:

- convite pendente nao vincula usuario automaticamente;
- o usuario precisa aceitar explicitamente para ingressar no tenant;
- o aceite pode ocorrer por token na tela de acesso pendente ou por notificacao interna.

Governanca de convite:

- somente owner ativo do tenant pode emitir convite com e-mail, role e expiracao;
- somente owner ativo do tenant pode revogar convite enquanto estiver pendente;
- convite revogado nao pode mais ser aceito;
- convite tambem pode ser recusado pelo usuario convidado (status declined);
- apos aceite valido, o app revalida os memberships para refletir acesso imediatamente.

Escopo de telas:

- tela Notificacoes: apenas inbox de convites recebidos pelo usuario (aceitar/recusar);
- tela Tenant > Convites: envio e gerenciamento de convites do tenant.

### clientes/{id} e pedidos/{id}

Campos minimos de escopo:

- tenantId: string
- ownerId: string
- gerenteId: string
- representanteId: string
- vendedorId: string

Esses campos definem o que cada perfil pode ler/escrever via rules.

## Modo manual sem ERP

Para o produto ser util mesmo sem integracao, o tenant deve conseguir operar com:

- cadastro manual de usuarios;
- importacao CSV de clientes;
- importacao CSV de produtos;
- cadastro manual de politicas comerciais e tabelas de preco;
- uso do app sem dependencia de Sankhya.

Isso faz parte da estrategia do produto e nao deve ser tratado como modo secundario.

## Sobre parceiro Sankhya e multiplos usuarios

Quando houver mais de um login para o mesmo parceiro Sankhya:

- manter sankhyaPartnerIds em usuarios/{uid};
- opcionalmente criar parceiro_usuarios/{partnerId_uid} para auditoria e historico.

### Desligamento e revogacao

Se o owner revogar o acesso de um usuario, ou o ERP indicar desligamento:

- o membership daquele tenant deve ser desativado/revogado;
- o usuario global nao precisa ser apagado;
- o historico deve permanecer preservado;
- uma futura reativacao pode apenas restaurar o membership.

Recomendacao pratica:

- usar state/revokedAt/revokedReason para auditoria;
- usar ativo=false para bloquear imediatamente o acesso;
- manter o vínculo como revogável, nao como exclusao fisica obrigatoria.

O app nao deve confiar em flags vindas diretamente do cliente para role.
A atribuicao de role e hierarquia deve ser somente por aprovacao interna do tenant.

## Integracao com Sankhya (segura)

- Se no futuro for auto-provisionar usuario a partir de parceiro Sankhya, use Cloud Functions.
- Cloud Functions valida token do usuario, consulta Sankhya e grava Firestore com conta de servico.
- Cliente Flutter apenas dispara a solicitacao e exibe status.

## Recomendacao arquitetural final

- Produto: Smart SFA como plataforma SaaS.
- Primeiro caso real: Amatools como tenant inicial.
- Integracao Sankhya: primeiro adaptador ERP.
- Operacao manual: obrigatoria no MVP para reduzir dependencia de integracoes.
- Isolamento: sempre por tenantId, nunca apenas por role.
