# SmartSFA - Pricing and Taxation Rules (handoff de continuidade)

## 1) Objetivo deste documento

Este arquivo e a base de continuidade do modulo de tributacao/precificacao.
Use este documento como entrada principal quando abrir uma nova conversa no VS Code.

Ele descreve:
- decisoes arquiteturais fixas
- estado implementado no codigo
- backlog faltante, em ordem recomendada
- regras de acoplamento com Sankhya

## 2) Decisoes arquiteturais fixas (nao negociar sem decisao explicita)

1. O dominio de tributacao do SmartSFA e nativo do produto.
2. O acoplamento com ERP deve ser unilateral no modulo do ERP (Sankhya), nao no core de tributacao.
3. Tributacao no portal e dividida em 3 frentes:
   - Matriz tributaria (regras fiscais)
   - Grupos tributarios
   - Perfis de operacao (10 tipos nativos)
4. Produto tem campo `grupo_tributario_id` para classificar mercadorias.
5. Escopo multi-tenant permanece com heranca global + representada.

## 3) Projeto e ambiente

- Projeto Firebase oficial: `smart-sfa`
- Nao usar mais referencias ao projeto Firebase antigo.
- Regras Firestore de tributacao ja publicadas no projeto `smart-sfa`.

## 4) Estado implementado no codigo

## 4.1 Portal de Tributacoes

Arquivo principal de navegacao da area:
- `lib/src/features/portal/presentation/pages/web_portal_taxation_section.dart`

Submenus ativos:
- `Matriz tributaria` -> `_TaxRulesSection`
- `Grupos tributarios` -> `_TaxRuleGroupsSection`
- `Perfis de operacao` -> `_TaxOperationProfilesSection`

Entrada da funcionalidade no portal:
- `lib/src/features/portal/presentation/pages/web_portal_catalog_sections.dart`
- `lib/src/features/portal/presentation/pages/web_portal_tenant_module_area_section.dart`

### 4.1.1 Matriz tributaria (implementado)

Arquivo:
- `lib/src/features/portal/presentation/pages/web_portal_tax_rules_section.dart`

Capacidades implementadas:
- CRUD completo de regras fiscais
- filtros por NCM, CEST e UF destino
- ordenacao por prioridade com mover para cima/baixo
- importacao via planilha (XLSX/CSV) com validacao forte
- exportacao de template com instrucoes
- limpeza de regras sem NCM (acao assistida)
- suporte a `salePurpose` e tipo de ST (`mva`/`pmc`)
- suporte inicial a campos normalizados na regra:
   - `operationProfileKey`
   - `taxGroupId`
   - exibicao desses campos em chips na lista da matriz

Nomes de tela para o usuario (matriz):
- `Perfil de operacao` (aceita nome de negocio do perfil ou chave tecnica)
- `Grupo tributario` (ID do grupo cadastrado no modulo Grupos tributarios)

Persistencia:
- colecao `tax_rules`
- repositorio: `lib/src/core/data/firestore/firestore_tax_rule_repository.dart`

Observacao importante:
- O repositorio foi ajustado para ignorar documentos com `docType=operation_profile` caso existam registros legados.

### 4.1.2 Grupos tributarios (implementado)

Arquivo:
- `lib/src/features/portal/presentation/pages/web_portal_taxation_section.dart`

Capacidades implementadas:
- CRUD manual
- escopo global ou representada
- prioridade, status, descricao
- metadados de mapeamento ERP (`externalCode`, `erpProvider`)
- importacao de planilha com idempotencia por fingerprint (escopo + nome normalizado)
- download de template
- placeholder de sincronizacao ERP (dialog informativo)

Persistencia:
- colecao `tax_rule_groups`

### 4.1.3 Perfis de operacao (implementado - fase 1)

Arquivo:
- `lib/src/features/portal/presentation/pages/web_portal_taxation_section.dart`

Capacidades implementadas:
- seed idempotente dos 10 perfis nativos
- botao "Reaplicar 10 perfis"
- edicao por perfil:
  - ativo/inativo
  - prioridade
  - switches fiscais
  - provider ERP e codigo externo
- escopo global/representada

Persistencia atual:
- colecao `tax_operation_profiles` (dedicada)

10 perfis nativos canonicos:
- `revenda_same_uf`
- `revenda_interstate`
- `uso_consumo_contribuinte_same_uf`
- `uso_consumo_contribuinte_interstate`
- `uso_consumo_nao_contribuinte_same_uf`
- `uso_consumo_nao_contribuinte_interstate`
- `industrializacao_same_uf`
- `industrializacao_interstate`
- `zfm_industrializacao`
- `zfm_comercializacao_revenda`

## 4.2 Produto e grupo tributario

Modelo:
- `lib/src/core/models/produto.dart`

Campo implementado:
- `grupoTributarioId` <-> `grupo_tributario_id`

Editor de produto:
- dropdown de grupo tributario antes de NCM na aba fiscal
- arquivo UI: `lib/src/features/produtos/presentation/widgets/product_editor_tabs_sections.dart`
- catalogo de grupos: `lib/src/features/produtos/presentation/services/product_tax_group_catalog_service.dart`

Importacao de produtos:
- aceita `grupoTributarioId` e aliases equivalentes
- arquivo: `lib/src/features/produtos/presentation/services/product_csv_import_service.dart`

## 4.3 Engine de calculo tributario atual (fase de transicao)

Arquivo:
- `lib/src/features/precos/services/product_tax_engine_service.dart`
- `lib/src/features/precos/services/tax_operation_classifier_service.dart`

Status:
- classificador nativo dos 10 perfis implementado no dominio
- calculo de ST/DIFAL/IPI/ZFM agora segue switches do perfil classificado
- calcula IPI, ST, DIFAL e ajuste ZFM
- usa NCM/CEST/UF origem-destino e janela de vigencia
- retorna `operationProfileKey` no resultado do calculo

Limitacao atual:
- o classificador ainda usa default nativo em memoria; falta leitura dinamica de overrides da colecao `tax_operation_profiles`
- o matcher ainda prioriza NCM/CEST/UF/finalidade; falta cadeia completa Produto > Grupo > NCM > regra geral UF

## 4.4 Seguranca Firestore

Arquivo:
- `firestore.rules`

Colecoes cobertas com controle de escrita tributaria:
- `tax_rules`
- `tax_rule_groups`
- `tax_operation_profiles`
- `produtos` (aceita opcional `grupo_tributario_id` string)

Controle de escrita usa funcao:
- `canManageTaxRulesWrite(tenantId)`

## 4.5 Integracao Sankhya (estado atual)

- Existem 10 campos de TOP no modulo de integracao ERP.
- Mapeamento atual esta em:
  - `lib/src/features/enterprise/erp_integration/domain/models/enterprise_erp_integration_data.dart`
  - `lib/src/features/enterprise/erp_integration/services/enterprise_erp_integration_service.dart`
  - `lib/src/features/auth/services/workspace_profile_service.dart`

Decisao de acoplamento (importante):
- O modulo Sankhya deve consumir os perfis de operacao do core para resolver TOP.
- O core de tributacao nao deve depender de contratos internos do Sankhya.

## 5) O que falta implementar (backlog recomendado)

## 5.1 Prioridade alta (proximo ciclo)

1. Tax matcher da matriz com fallback em cadeia
   - Produto especifico > Grupo tributario > NCM > regra geral UF
   - manter prioridade e vigencia

2. Adaptar `ProductTaxEngineService` para usar:
   - `tax_operation_profiles` (switches por perfil, carregados da base)
   - `tax_rule_groups` + `grupo_tributario_id` no matcher
   - `tax_rules` como matriz final

3. Testes unitarios dedicados do novo fluxo
   - cenarios com contribuinte/nao contribuinte
   - cenarios ZFM
   - cenarios com e sem grupo tributario

## 5.2 Prioridade media

1. Sincronizacao ERP real para `tax_rule_groups`
2. Sincronizacao ERP ou assistente de mapeamento para `tax_operation_profiles`
3. Tela de auditoria de decisao tributaria (explicar por que regra/perfil foi escolhido)

## 5.3 Prioridade baixa

1. Importacao/exportacao de perfis de operacao por planilha
2. Catalogo de versoes de matriz por vigencia
3. Otimizacao de leituras para catalogos grandes (delta por `updatedAt`)

## 6) Estrategia de implementacao sugerida para proxima conversa

Sequencia sugerida para continuar sem regressao:

1. Criar servico `TaxRuleMatcherService` (dominio puro)
2. Conectar `TaxOperationClassifierService` aos overrides de `tax_operation_profiles`
3. Integrar matcher + classifier no `ProductTaxEngineService`
4. Ajustar testes existentes + criar novos testes de regressao
5. So depois acoplar modulo Sankhya para resolver TOP a partir de `profileKey`

## 7) Definicao de pronto da nova fase do motor

O novo motor e considerado pronto quando:

1. Para um item de pedido, o sistema gera o `profileKey` nativo corretamente.
2. O match da regra fiscal segue cadeia de fallback definida.
3. Os switches do perfil afetam o calculo final (ST, DIFAL, IPI base/total, ZFM).
4. O resultado do calculo retorna trilha de decisao (perfil + regra + justificativa).
5. Testes cobrindo os cenarios principais passam localmente.

## 8) Riscos e cuidados

1. Nao misturar novamente documentos de perfis com `tax_rules`.
2. Manter idempotencia em importacoes por fingerprint/chave estavel.
3. Evitar fallback silencioso que esconda erro de cadastro obrigatorio.
4. Preservar regras de permissao owner/read-only no portal.

## 9) Comandos uteis de validacao

- `flutter analyze`
- `flutter test test/features/precos/services/product_tax_engine_service_test.dart`
- `flutter test test/features/precos/services/tax_operation_classifier_service_test.dart`
- hot reload via DTD apos ajustes de UI

## 10) Fonte primaria de verdade

Mesmo com este documento, o codigo e a fonte final.
Sempre validar comportamento pelos arquivos abaixo:

- `lib/src/features/portal/presentation/pages/web_portal_taxation_section.dart`
- `lib/src/features/portal/presentation/pages/web_portal_tax_rules_section.dart`
- `lib/src/core/data/firestore/firestore_tax_rule_repository.dart`
- `lib/src/features/precos/services/tax_operation_classifier_service.dart`
- `lib/src/core/models/produto.dart`
- `lib/src/features/produtos/presentation/widgets/product_editor_tabs_sections.dart`
- `lib/src/features/precos/services/product_tax_engine_service.dart`
- `firestore.rules`
