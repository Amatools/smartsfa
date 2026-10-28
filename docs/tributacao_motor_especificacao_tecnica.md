# Motor de Tributação do SmartSFA — Especificação Técnica Única

> **Status**: fonte técnica única e atual do motor de tributação.
> **Substitui como referência primária**: [tributacao_engine.md](tributacao_engine.md), [pricing_taxation_rules.md](pricing_taxation_rules.md) e [enduser_Regras_de_Tributacao.md](enduser_Regras_de_Tributacao.md), que permanecem no repositório como material histórico/complementar (rascunho de brainstorming, handoff técnico anterior e explicação simplificada para usuário final, respectivamente).
> **Última atualização**: ver histórico do Git para data exata.

---

## 0. Contexto e propósito

O SmartSFA **não emite documento fiscal**. Não gera NF-e, NFS-e, SPED ou qualquer escrituração. Quem formaliza a venda, calcula o imposto "de verdade" e emite o documento fiscal é sempre o **ERP da representada** (Sankhya ou outro).

Isso define o papel exato do motor de tributação do SmartSFA:

> **O motor é um espelho de preço comercial.** Sua função é calcular, no app do vendedor (frequentemente offline, em campo), o **mesmo preço final, centavo a centavo**, que o ERP vai calcular quando o pedido for faturado. Isso permite ao vendedor negociar e fechar pedidos com confiança de que o valor apresentado ao cliente bate com o que será cobrado.

Consequências diretas desse princípio:

1. **Precisão de centavo é requisito funcional, não "nice to have".** Divergência de arredondamento entre motor e ERP gera atrito comercial (cliente vê um preço na proposta e recebe outro na nota).
2. **O motor não precisa (e não deve) tentar substituir o ERP em obrigações acessórias** — não gera CST para XML, não valida regras de SPED Fiscal, não trata contingência de emissão.
3. **Em caso de divergência entre o cálculo do motor e o do ERP após o faturamento, o ERP sempre prevalece.** O motor deve ser corrigido para convergir, nunca o contrário.
4. **O motor deve funcionar com os dados cadastrais que o SmartSFA já tem (ou pode replicar do ERP)**, sem depender de chamadas síncronas ao ERP no momento da venda (app funciona offline em campo).

---

## 1. Escopo e limites

### 1.1 Dentro do escopo

- Venda B2B de **mercadorias tangíveis** (produtos de catálogo) entre uma **representada** (pessoa jurídica vendedora, atuando em nome de uma indústria/distribuidora) e um **cliente** (comprador PJ ou PF), dentro do território nacional.
- Tributos calculados: **ICMS próprio**, **ICMS-ST** (MVA e PMC/pauta), **DIFAL**, **FCP** (normal, ST e DIFAL), **IPI**, **PIS/COFINS** (modelado, ver §1.3), **ISS** (apenas para a extensão de itens tipo serviço, ver §1.3), e estrutura preparada para a **Reforma Tributária** (IBS/CBS/Imposto Seletivo, LC 214/2025).
- Regimes tributários da representada: **Simples Nacional**, **Lucro Presumido**, **Lucro Real** (tratados como "Regime Normal" para fins de cálculo de ICMS/ST, exceto onde explicitamente diferenciado — ver §10).
- Operações: venda para revenda, venda para uso/consumo, venda para industrialização, operações com Zona Franca de Manaus/SUFRAMA.

### 1.2 Fora do escopo

- **Emissão de documento fiscal** (NF-e, NFS-e, CT-e) — isso é 100% responsabilidade do ERP.
- **Geração de SPED/EFD, escrituração contábil ou fiscal.**
- **Comércio exterior** (importação/exportação direta, Drawback, Recof).
- **Devoluções, notas complementares, notas de ajuste.**
- **Segmentos excepcionais com regras tributárias muito específicas**: armas e munições, bebidas alcoólicas, veículos automotores, cigarros, combustíveis (regras monofásicas combinadas de ICMS + PIS/COFINS). Essa exclusão já era adotada em [enduser_Regras_de_Tributacao.md](enduser_Regras_de_Tributacao.md) (item 6) e é mantida aqui como premissa assumida — **validar com o usuário/negócio se algum desses segmentos entrar no catálogo**.

### 1.3 Observação importante sobre PIS/COFINS e ISS

PIS/COFINS e ISS são **modelados na estrutura de dados** (campos existem, ver §4), mas seu comportamento no **preço final de venda B2B de mercadoria para revenda** é, na prática, **neutro**:

- Para o distribuidor que revende, PIS/COFINS normalmente já estão **embutidos no preço de tabela** (regime monofásico ou substituição tributária de contribuição, comum em autopeças, cosméticos, bebidas, etc.) ou a saída é tributada à **alíquota zero/sem destaque** quando o produto já sofreu a tributação concentrada na indústria. Ou seja: **o motor não deve, por padrão, somar um valor adicional de PIS/COFINS ao preço final da revenda B2B.**
- Em cenários de **industrialização** (cliente compra insumo para transformar), o tratamento de PIS/COFINS pode mudar (crédito/débito na cadeia do próprio cliente, não do vendedor) — isso não afeta o preço de venda calculado pelo motor, pois PIS/COFINS do comprador industrial não compõe o preço de venda do vendedor.
- **ISS** só é relevante se o catálogo contiver **itens de serviço** (ex.: instalação, assistência técnica faturada separadamente). Nesse caso, o item é tributado por ISS municipal **em vez de** ICMS/IPI, nunca em conjunto. É modelado como uma extensão por item (`itemType = servico`), não como parte do pipeline padrão de mercadoria.

Portanto, o pipeline de cálculo (§5) trata PIS/COFINS e ISS como **módulos opcionais aplicáveis por perfil/grupo tributário**, desligados por padrão, e não como somatório automático no preço de mercadoria.

---

## 2. Glossário fiscal

| Termo | Definição resumida |
|---|---|
| **ICMS** | Imposto estadual sobre circulação de mercadorias. Calculado "por dentro" (embutido no preço), alíquota varia por UF/NCM. |
| **ICMS-ST (Substituição Tributária)** | Antecipação do ICMS de toda a cadeia (até o consumidor final) cobrada do primeiro elo (indústria/distribuidor). Calculado sobre uma base presumida (MVA) ou uma pauta fiscal (PMC). |
| **MVA (Margem de Valor Agregado) / IVA** | Percentual aplicado sobre o preço de venda para estimar o preço final ao consumidor, usado como base de cálculo do ICMS-ST. Varia por NCM/UF, definido em convênio/protocolo ICMS ou pauta estadual. |
| **PMC (Preço Médio ao Consumidor)** | Alternativa ao MVA: em vez de aplicar um percentual sobre o preço de venda, usa-se uma **pauta fiscal fixa** (preço de tabela sugerido/pesquisado), comum em alguns segmentos (ex.: autopeças, medicamentos). |
| **DIFAL (Diferencial de Alíquota)** | Diferença entre a alíquota interna da UF de destino e a alíquota interestadual, cobrada quando a venda é interestadual e o destino é consumidor final (contribuinte ou não) ou uso/consumo. Desde a EC 87/2015 (plenamente vigente desde 2024, fim da partilha), o DIFAL integral vai para a UF de destino. |
| **FCP (Fundo de Combate à Pobreza)** | Adicional de 1% a 2% sobre a base do ICMS (ou do ICMS-ST/DIFAL), instituído por lei estadual, destinado a fundo específico. Soma-se ao ICMS mas é calculado/destacado separadamente. |
| **IPI** | Imposto federal sobre produtos industrializados, cobrado na saída do estabelecimento industrial/equiparado. Soma-se ao preço final (não é "por dentro" como o ICMS). |
| **PIS/COFINS** | Contribuições federais sobre o faturamento. Podem ser cumulativas, não cumulativas, monofásicas (concentradas na indústria) ou por substituição — ver §1.3. |
| **Monofásico** | Regime em que a tributação de PIS/COFINS (ou ICMS, em combustíveis) é concentrada em um único elo da cadeia (geralmente indústria/importador), com os demais elos saindo a alíquota zero. |
| **ISS** | Imposto municipal sobre serviços, exclusivo para itens de serviço (não concorre com ICMS/IPI no mesmo item). |
| **IBS (Imposto sobre Bens e Serviços)** | Tributo da Reforma Tributária (LC 214/2025) que substituirá gradualmente ICMS e ISS, de competência compartilhada estados/municípios, com transição 2026–2033. |
| **CBS (Contribuição sobre Bens e Serviços)** | Tributo federal da Reforma que substituirá PIS/COFINS. |
| **IS (Imposto Seletivo)** | Novo tributo federal da Reforma, incidente sobre bens/serviços prejudiciais à saúde/meio ambiente ("imposto do pecado"). |
| **CST (Código de Situação Tributária)** | Código que identifica o tratamento tributário do item para contribuintes do Regime Normal (Lucro Presumido/Real). Ver tabela completa em §8. |
| **CSOSN (Código de Situação da Operação no Simples Nacional)** | Equivalente ao CST, usado por optantes do Simples Nacional. Ver §8 e §10. |
| **CFOP (Código Fiscal de Operações e Prestações)** | Código que identifica a natureza da operação (venda interna, interestadual, para uso/consumo, etc.) — relevante para o ERP gerar a nota, não é recalculado pelo motor, mas influencia qual regra da matriz se aplica. |
| **NCM (Nomenclatura Comum do Mercosul)** | Classificação fiscal do produto (8 dígitos), base para determinar alíquotas de IPI, ICMS-ST (via convênio/protocolo) e enquadramento em CEST. |
| **CEST (Código Especificador da Substituição Tributária)** | Código que identifica a mercadoria sujeita a ICMS-ST, complementar ao NCM (define exatamente qual segmento de MVA/pauta se aplica quando o NCM é genérico). |
| **Origem da mercadoria** | Dígito (0 a 8) que indica se o produto é nacional, importado ou nacionalizado — afeta a alíquota interestadual (4% para importados sem similar nacional). Ver §9. |
| **Simples Nacional x Regime Normal** | Regime tributário simplificado (Simples) x regime tradicional (Lucro Presumido/Real) — afeta como o ICMS próprio é destacado e, em alguns estados, reduz a base de MVA/ST. Ver §10. |
| **ZFM/SUFRAMA** | Zona Franca de Manaus e Áreas de Livre Comércio — regime de incentivo fiscal com redução/isenção de ICMS e IPI para operações destinadas a empresas habilitadas na SUFRAMA. |

---

## 3. Cadastros necessários

Tabela campo a campo, distinguindo **o que já existe implementado no código** (✅) do que é **novo/proposto** (🆕) para fechar lacunas desta especificação.

### 3.1 Representada (`tenant_represented_companies`)

| Campo | Status | Observações |
|---|---|---|
| `uf` | ✅ existe (`workspace_profile_service.dart`, validado contra lista de UFs) | UF de origem para fins de cálculo interestadual. |
| `taxRegime` | ✅ existe (`simples_nacional` / `lucro_presumido` / `lucro_real`) | Define se a representada é optante do Simples — afeta destaque de ICMS próprio (§10). |
| `erpOrderTopCodes` | ✅ existe (`setTenantErpOrderTopCodes`, mapa com as 10 chaves de perfil → código TOP do ERP) | Já cobre o mapeamento dos 10 perfis de operação para códigos TOP do Sankhya (ou outro ERP), por representada/tenant. |
| `companyUnits` | ✅ existe | Unidades/filiais da representada (relevante para regra de UF de origem quando há múltiplas filiais). |

Nenhum campo novo identificado como obrigatório nesta camada para o motor funcionar — a representada já tem o essencial (`uf`, `taxRegime`, mapeamento ERP de perfis).

### 3.2 Cliente (`lib/src/core/models/cliente.dart`)

| Campo | Status | Observações |
|---|---|---|
| `estado` | ✅ existe | UF de destino do cliente. |
| `tipoPessoa` | ✅ existe (`'pf'` / `'pj'`, default `'pj'`) | |
| `taxProfile` | ✅ existe (`CustomerTaxProfile`: `contribuinte` / `naoContribuinte`, default `contribuinte`) | Determina se calcula ICMS-ST (comprador contribuinte/revenda) ou DIFAL (uso/consumo ou não contribuinte). |
| `taxRegime` | ✅ existe (mesmo enum de regime da representada, default `simples_nacional` via `defaultTaxRegime`) | Permite modelar o caso em que **o comprador** é optante do Simples Nacional, usado por algumas UFs (ex.: MG, RS) para reduzir o MVA/ST — ver §10. |
| `salePurpose` | ✅ existe (`SalePurpose`: `revenda` / `usoConsumo` / `industrializacao`, default `revenda`) | Finalidade padrão da compra; pode ser ajustada por item/pedido. |
| `isZfmSuframa` | ✅ existe (bool, default `false`) | Indica cliente habilitado na SUFRAMA/ZFM. |

Nenhum campo novo necessário — o modelo de Cliente já cobre todas as dimensões de classificação fiscal do comprador usadas pelos 10 perfis de operação.

### 3.3 Produto (`lib/src/core/models/produto.dart`)

| Campo | Status | Observações |
|---|---|---|
| `ncm` | ✅ existe | Chave primária de busca de regra fiscal. |
| `cest` | ✅ existe (opcional) | Complementa NCM quando o convênio/protocolo exige diferenciação por CEST. |
| `origemMercadoriaCst` | ✅ existe | Dígito 0–8, ver §9. |
| `aliquotaIpiBase` | ✅ existe (`double`) | Alíquota de IPI do produto. |
| `grupoTributarioId` | ✅ existe | FK para `tax_rule_groups`, permite agrupar produtos com a mesma regra fiscal sem repetir NCM. |

🆕 **Lacuna identificada**: não existe hoje no modelo de `Produto` um campo de **tipo de item** (`mercadoria` x `servico`) para acionar a extensão de ISS (§1.3, §4.4). Proposto: campo opcional `itemType` (default `mercadoria`), usado apenas quando o catálogo tiver itens de serviço.

### 3.4 Tenant / configuração global

| Campo | Status | Observações |
|---|---|---|
| `tax_rule_groups` (coleção) | ✅ existe | Grupos tributários, globais ou por representada. |
| `tax_operation_profiles` (coleção) | ✅ existe | 10 perfis nativos + overrides. |
| `tax_rules` (coleção) | ✅ existe | Matriz tributária (regras fiscais). |

---

## 4. Modelo de dados do motor

### 4.1 `tax_rule_groups` (Grupos tributários) — já implementado

Agrupa produtos que compartilham a mesma regra fiscal, evitando duplicar regra por NCM. Campos principais (já em produção): `id`, `nome`, `status`, `prioridade`, `descricao`, escopo (`global` ou `representedCompanyId`), metadados de mapeamento ERP (`externalCode`, `erpProvider`).

### 4.2 `tax_operation_profiles` (Perfis de operação) — já implementado

10 perfis nativos (`TaxOperationProfileKey`), cada um com switches de comportamento:

- `calculateIcmsSt`
- `calculateDifal`
- `includeIpiInIcmsBase`
- `addIpiToTotal`
- `reduceIcmsForZfm`

Mais metadados de escopo (global/representada), prioridade e status. **Sem nenhum campo de ERP/codigo externo** — os 10 perfis sao fixos e nao sabem nada sobre Sankhya ou qualquer outro ERP; a ligacao "TOP do Sankhya X equivale ao perfil nativo Y" e responsabilidade exclusiva do conector ERP (`erpOrderTopCodes`, por tenant, ver §3.1/§14), nunca do perfil em si.

### 4.3 `tax_rules` (Matriz tributária) — já implementado, com extensões propostas

Campos já implementados em `TaxRule` (`lib/src/core/models/tax_rule.dart`): `id`, `tenantId`, `representedCompanyId`, `status`, `ncm`, `cest`, `fiscalException`, `stCalculationType` (`mva`/`pmc`), `stPriceForCalculation`, `stBaseReductionPercent`, `stBaseAmount`, `aliquotaDestino`, `aliquotaCredito`, `grupoFiscalId`, `taxGroupId`, `operationProfileKey`, `ufOrigem`, `ufDestino`, `salePurpose`, `cstCsosn`, `mvaIva`, `aliquotaDifal`, `priority`, `validFrom`/`validUntil`, `syncVersion`, `deletedAt`.

🆕 **Extensões propostas** (campos novos, todos opcionais/retrocompatíveis — não quebram regras já cadastradas):

| Campo novo | Tipo | Finalidade |
|---|---|---|
| `aliquotaFcp` | double? | Percentual de FCP normal (soma à base do ICMS própria da UF destino). |
| `aliquotaFcpSt` | double? | Percentual de FCP-ST (soma ao ICMS-ST). |
| `aliquotaFcpDifal` | double? | Percentual de FCP-DIFAL (soma ao DIFAL, quando aplicável). |
| `aliquotaPisCofins` | double? | Percentual combinado de PIS/COFINS, usado **apenas** quando o grupo tributário/perfil explicitamente ligar esse módulo (default: não soma ao preço, ver §1.3). |
| `aliquotaIss` | double? | Percentual de ISS, usado apenas para itens com `itemType = servico`. |
| `reformaClassificacaoTributaria` (`cClassTrib`) | string? | Código de classificação tributária da Reforma (equivalente ao `CCLASSTRIB` do Sankhya/TGFPEM), referência para IBS/CBS/IS. |
| `reformaAliquotaReferenciaIbs` / `reformaAliquotaReferenciaCbs` | double? | Alíquotas de referência (parametrizáveis por ano-calendário, não cravadas no motor — ver §7). |
| `reformaPercentualReducao` | double? | Percentual de redução de base/alíquota aplicável ao item na Reforma (ex.: cesta básica, categorias com redução de 60%/100%). |

Essas extensões seguem o princípio de §7 (Reforma): **nenhum valor de alíquota de IBS/CBS/IS é fixado nesta especificação** — os campos existem como contêiner para parametrização externa (tabela de calendário de transição) e não como valores "mágicos" no código.

### 4.4 Extensão de item de serviço (ISS) — proposta

Quando `Produto.itemType == servico`: o motor **não** executa o pipeline de ICMS/IPI/ST/DIFAL para aquele item; em vez disso, aplica apenas `aliquotaIss` (buscada na mesma matriz `tax_rules`, com `ufDestino` podendo representar o município quando necessário, ou um campo dedicado de município — a definir conforme necessidade real de catálogo de serviços, hoje não há demanda confirmada).

---

## 5. Pipeline de cálculo

Ordem de execução para um item de pedido, dado o contexto `{representada, cliente, produto, quantidade, preço líquido do item}`:

### Passo 1 — Classificação da operação

`TaxOperationClassifierService.classify()` determina qual dos 10 perfis nativos se aplica, a partir de:
- `salePurpose` (revenda / uso-consumo / industrialização)
- `sameUf` (UF origem representada == UF destino cliente)
- `customerTaxProfile` (contribuinte / não contribuinte)
- `isZonaFrancaSuframa`

✅ **Implementado**: o classificador agora aceita `overrides: List<TaxOperationProfile>` e `representedCompanyId`, priorizando um override ativo escopado à representada, depois um override global (sem representada), e só então caindo no mapa `_nativeDefaults` em memória (ver `TaxOperationClassifierService._resolveOverride`).

### Passo 2 — Busca da regra fiscal (matcher)

✅ **Implementado** (`ProductTaxEngineService._resolveTaxRule`). Busca em `tax_rules` filtrando por `tenantId`/`representedCompanyId`, com cadeia de fallback completa do mais específico para o mais genérico:

1. Produto específico (`TaxRule.produtoId` igual ao produto do item).
2. `grupoTributarioId` do produto.
3. `ncm` do produto.
4. Regra geral por `ufOrigem`/`ufDestino` (sem produto/grupo/NCM) — fallback terminal, sempre existe pelo menos essa opção quando cadastrada.

`cest` e `TaxRule.applicableBuyerTaxRegime` (regime tributário do comprador, ex. Simples Nacional) atuam como critérios de desempate dentro do mesmo nível, não como níveis próprios: entre candidatos do mesmo nível, vence primeiro quem casar o regime do comprador, depois quem casar o CEST, e por fim o maior `priority`. Todos os níveis também filtram por vigência (`validFrom`/`validUntil`) e status ativo.

### Passo 3 — Cálculo dos tributos atuais

Dado `precoBase` (preço líquido do item, após descontos) e a regra/perfil resolvidos:

**a) IPI** (se `perfil.addIpiToTotal == true`):

$$
\text{ValorIPI} = \text{precoBase} \times \frac{\text{aliquotaIpiBase}}{100}
$$

**b) Base do ICMS próprio**:

$$
\text{BaseIcms} = \begin{cases} \text{precoBase} + \text{ValorIPI} & \text{se } \text{perfil.includeIpiInIcmsBase} = \text{true (uso/consumo)} \\ \text{precoBase} & \text{caso contrário (revenda/industrialização)} \end{cases}
$$

Se a regra tiver `stBaseReductionPercent` aplicável também ao ICMS próprio (ver exemplo validado de SP no §16), multiplica-se a base pelo fator de redução antes de aplicar a alíquota.

$$
\text{ValorIcmsProprio} = \text{BaseIcms} \times \frac{\text{aliquotaCredito}}{100}
$$

**c) ICMS-ST** (se `perfil.calculateIcmsSt == true`):

- Método **MVA**:

$$
\text{BaseST} = (\text{precoBase} + \text{ValorIPI}) \times \left(1 + \frac{\text{mvaIva}}{100}\right) \times \frac{\text{stBaseReductionPercent ou } 100}{100}
$$

$$
\text{ValorICMS-ST} = \max\left(0,\ \text{BaseST} \times \frac{\text{aliquotaDestino}}{100} - \text{ValorIcmsProprio}\right)
$$

- Método **PMC/pauta** (`stCalculationType = 'pmc'`): usa `stPriceForCalculation` (preço de pauta) como base fixa em vez de `precoBase × (1 + MVA)`:

$$
\text{BaseST} = \text{stPriceForCalculation} \times \frac{\text{stBaseReductionPercent ou } 100}{100}
$$

(demais passos iguais ao método MVA).

**d) DIFAL** (se `perfil.calculateDifal == true` — uso/consumo interestadual ou não contribuinte interestadual):

$$
\text{ValorDIFAL} = (\text{precoBase} + \text{ValorIPI}) \times \frac{\text{aliquotaDifal}}{100}
$$

onde `aliquotaDifal` já representa a diferença (alíquota interna destino − alíquota interestadual origem), pré-calculada na regra. Desde a plena vigência da EC 87/2015 (2024 em diante), **100% do DIFAL vai para a UF de destino** (fim da partilha gradual 2016–2018 — já não há mais partilha a calcular).

**e) FCP** (🆕, aplicação proposta, soma simples sobre a base correspondente):

$$
\text{ValorFCP} = \text{BaseIcms} \times \frac{\text{aliquotaFcp}}{100}
$$
$$
\text{ValorFCP-ST} = \text{BaseST} \times \frac{\text{aliquotaFcpSt}}{100}
$$
$$
\text{ValorFCP-DIFAL} = (\text{precoBase} + \text{ValorIPI}) \times \frac{\text{aliquotaFcpDifal}}{100}
$$

**f) Desconto ZFM/SUFRAMA** (se `perfil.reduceIcmsForZfm == true`): reduz/zera `ValorIcmsProprio` e `ValorICMS-ST` conforme a regra da UF de destino (regra atual já implementada no engine).

**g) PIS/COFINS e ISS**: desligados por padrão (ver §1.3); somados apenas se o grupo tributário/perfil explicitamente habilitar (`aliquotaPisCofins`/`aliquotaIss` presentes e módulo ativo).

### Passo 4 — Totais do item

$$
\text{PrecoFinalItem} = \text{precoBase} + \text{ValorIPI} + \text{ValorICMS-ST} + \text{ValorDIFAL} + \text{ValorFCP} + \text{ValorFCP-ST} + \text{ValorFCP-DIFAL}
$$

(ICMS próprio **não** soma ao preço final — é "por dentro", já embutido no `precoBase`; ele só é usado como abatimento no cálculo do ST/DIFAL.)

### Passo 5 — Cálculo Reforma Tributária (transição 2026–2033)

Módulo paralelo, parametrizável por ano-calendário (§7). Durante a transição, o preço final deve, na prática, continuar batendo com o regime atual (o "teste" da Reforma é de recolhimento, não de preço ao cliente, até que haja substituição efetiva de tributos) — este passo existe para que o motor já tenha o contêiner de dados pronto quando a regra de negócio da Reforma precisar alterar o preço final em alguma fase da transição.

---

## 6. Regras de arredondamento e ordem das operações

Ponto crítico para bater **centavo a centavo** com o ERP:

1. **Arredondar apenas no final de cada tributo**, nunca em bases intermediárias. Isto é: calcule `BaseST` com precisão total (double), aplique a alíquota, e só então arredonde o `ValorICMS-ST` para 2 casas decimais. Arredondamentos intermediários acumulam erro e divergem do ERP linha a linha.
2. **Arredondamento padrão: meio para cima** (`round half up`, não `round half to even`/bankers rounding), que é o padrão usado pela generalidade dos ERPs fiscais brasileiros (compatível com a Nota Técnica da NF-e, que especifica arredondamento comum de 2 casas decimais).
3. **Ordem de cálculo fixa, sempre a mesma sequência**: IPI → Base ICMS → ICMS próprio → Base ST → ICMS-ST → DIFAL → FCP (normal/ST/DIFAL) → ajuste ZFM → soma final. Calcular fora dessa ordem (ex.: aplicar FCP antes do ICMS-ST) produz valores diferentes.
4. **Preço líquido do item (`precoBase`) já deve estar com desconto aplicado** antes de entrar no pipeline — o motor não lida com desconto percentual dentro da fórmula tributária, trata descontos como uma etapa anterior e já consolidada.
5. **ICMS-ST nunca é negativo**: se `BaseST × aliquotaDestino − ValorIcmsProprio < 0`, o resultado é cravado em `0` (comprador não "ganha crédito" na operação do vendedor).
6. Caso o ERP de uma UF específica use uma regra de arredondamento diferente (ex.: cálculo "por dentro" do DIFAL em certos estados, dividindo por `(1 − aliquotaInterna)`), isso deve ser modelado como uma **flag por UF de destino**, não como exceção embutida no código genérico — evita que uma regra regional vaze para todos os cálculos.

✅ **Implementado**: `TaxRoundingPolicy` (`lib/src/features/precos/services/tax_rounding_policy.dart`) centraliza o arredondamento meio-para-cima (com correção de épsilon `1e-9` para erros de representação binária, ex. `2.675`), usado por todo o pipeline antes de somar o total final.

---

## 7. Reforma Tributária — estrutura parametrizável

A Reforma Tributária (EC 132/2023, regulamentada pela **LC 214/2025**) substitui, ao longo de uma transição de **2026 a 2033**, o ICMS e o ISS pelo **IBS**, e o PIS/COFINS pela **CBS**, além de criar o **Imposto Seletivo (IS)**.

**Decisão de design**: esta especificação **não crava nenhuma alíquota de IBS/CBS/IS**, porque:
- As alíquotas de referência só serão fixadas por resolução do Senado ano a ano durante a transição.
- O cronograma de transição (percentuais de cada tributo "novo" x "antigo" a cada ano) é regra de calendário, não regra fiscal fixa de produto.

Estrutura proposta:

1. **Tabela de calendário de transição** (nova coleção ou documento de configuração, ex. `tax_reform_calendar`), com uma linha por ano, contendo os percentuais de substituição vigentes naquele ano (ex.: "em 2026, CBS/IBS têm caráter de teste, sem impacto de caixa real"; "a partir de 2027, PIS/COFINS são extintos e substituídos por CBS"; etc. — os percentuais exatos devem ser carregados de fonte oficial no momento da implementação, não fixados aqui).
2. **Campos por regra fiscal** (já descritos em §4.3): `reformaClassificacaoTributaria` (cClassTrib), `reformaAliquotaReferenciaIbs`, `reformaAliquotaReferenciaCbs`, `reformaPercentualReducao` — todos nulos/opcionais até a fase de implementação da Reforma começar a exigir cálculo real.
3. **Compatibilidade com o Sankhya**: os campos acima espelham diretamente os campos que já aparecem nas tabelas `TGFICM`/`TGFPEM` do Sankhya (`ALIQADREM`, `CCLASSTRIB`, `CST`, `IVA`, `INDGIBSCBS`) — ver §14.

A implementação efetiva do cálculo da Reforma (passo 5 do pipeline, §5) deve ser adiada até existir necessidade real de negócio (ex.: ano de transição em que o impacto no preço final passa a ser obrigatório) — por ora, a estrutura de dados está pronta para receber essa informação sem exigir migração de schema.

---

## 8. Tabela de referência CST/CSOSN

### 8.1 CST — ICMS (Regime Normal, 2 dígitos somados à Origem)

| CST | Significado | Sinalização para o motor |
|---|---|---|
| 00 | Tributada integralmente | ICMS próprio normal, sem ST, sem redução. |
| 10 | Tributada com cobrança de ICMS-ST | Aciona `calculateIcmsSt`. |
| 20 | Com redução de base de cálculo | Aplica `stBaseReductionPercent` na base do ICMS próprio. |
| 30 | Isenta/não tributada com cobrança de ICMS-ST | ICMS próprio isento, mas ainda calcula ST. |
| 40 | Isenta | Sem ICMS próprio. |
| 41 | Não tributada | Sem ICMS próprio (fora do campo de incidência). |
| 50 | Suspensão | Sem ICMS próprio (suspenso). |
| 51 | Diferimento | ICMS próprio diferido (não destacado nesta etapa). |
| 60 | ICMS cobrado anteriormente por ST | Produto já chega com ST recolhido; motor não recalcula ST. |
| 70 | Com redução de base e cobrança de ICMS-ST | Combina CST 20 + CST 10. |
| 90 | Outras | Caso genérico, regra deve ser explícita na matriz. |

### 8.2 CSOSN — Simples Nacional (4 dígitos)

| CSOSN | Significado | Sinalização para o motor |
|---|---|---|
| 101 | Tributada com permissão de crédito | ICMS próprio conforme alíquota do Simples (não destaca 18%/12% cheio). |
| 102 | Tributada sem permissão de crédito | Idem, sem crédito. |
| 103 | Isenção do ICMS para faixa de receita bruta | Sem ICMS próprio. |
| 201 | Tributada com permissão de crédito e cobrança de ICMS-ST | Aciona ST mesmo sendo Simples. |
| 202/203 | Tributada sem permissão de crédito, com ICMS-ST | Idem. |
| 300 | Imune | Sem ICMS. |
| 400 | Não tributada | Sem ICMS. |
| 500 | ICMS cobrado anteriormente por ST (ou antecipação) | Já veio com ST recolhido. |
| 900 | Outros | Caso genérico. |

**Implicação prática para o motor**: quando a **representada** é Simples Nacional, o ICMS próprio não é "destacado" à alíquota cheia (18%/12%) — ele está embutido no DAS. Isso **não elimina o ICMS-ST**, que continua sendo calculado normalmente sempre que `calculateIcmsSt == true`. O que muda é apenas o abatimento do "ICMS próprio" na fórmula do ST (§10 detalha).

---

## 9. Tabela de Origem da Mercadoria

| Código | Significado | Efeito na alíquota interestadual |
|---|---|---|
| 0 | Nacional (exceto 3, 4, 5 e 8) | Alíquota interestadual padrão (7% ou 12%, conforme UF origem/destino). |
| 1 | Estrangeira – importação direta | **4%** (Resolução Senado 13/2012), quando não houver similar nacional relevante ou conteúdo de importação > 40%. |
| 2 | Estrangeira – adquirida no mercado interno | **4%**, mesma lógica da origem 1. |
| 3 | Nacional, com conteúdo de importação > 40% | **4%**. |
| 4 | Nacional, produção conforme processos produtivos básicos | 7%/12% (tratado como nacional). |
| 5 | Nacional, com conteúdo de importação ≤ 40% | 7%/12% (tratado como nacional). |
| 6 | Estrangeira – importação direta, sem similar nacional | 7%/12% (exceção: não se aplica os 4%, pois não há similar nacional na lista CAMEX). |
| 7 | Estrangeira – adquirida no mercado interno, sem similar nacional | 7%/12% (mesma exceção da origem 6). |
| 8 | Nacional, conteúdo de importação > 70% | **4%**. |

O motor usa `origemMercadoriaCst` do produto para decidir automaticamente entre a alíquota interestadual de **4% (importados)** e **7%/12% (nacionais)** nas operações interestaduais — isso já deve estar refletido na alíquota de origem (`aliquotaCredito`) cadastrada na regra correspondente a cada combinação de UF origem/destino + origem de mercadoria.

---

## 10. Simples Nacional — tratamento especial

Dois pontos distintos, que não devem ser confundidos:

### 10.1 Representada optante do Simples Nacional (`taxRegime` do emitente)

- O ICMS próprio **não é destacado à alíquota cheia** na nota — ele está diluído na alíquota única do DAS (Anexo I ou II, conforme o caso).
- Para fins de **cálculo do ICMS-ST**, no entanto, o abatimento do "ICMS próprio" na fórmula do ST segue regra específica: muitos estados definem uma **alíquota de crédito presumido reduzida** para o Simples (em vez do ICMS cheio da operação), configurável por regra fiscal via o campo `aliquotaCredito` já existente — ou seja, **não é um campo novo**, apenas um valor diferente cadastrado na matriz quando a representada é Simples.
- CSOSN é usado em vez de CST (ver §8.2).

### 10.2 Cliente optante do Simples Nacional (`taxRegime` do comprador)

- Relevante apenas para o **MVA ajustado/reduzido** que algumas UFs concedem quando o comprador final é optante do Simples (ex.: Minas Gerais e Rio Grande do Sul têm, historicamente, protocolos com MVA ajustado para essa hipótese).
- Quando aplicável, a regra fiscal (`tax_rules`) para aquela UF de destino deve ter uma variante com `mvaIva` reduzido, selecionada quando `cliente.taxRegime == 'simples_nacional'`.
- ✅ **Implementado**: `TaxRule.applicableBuyerTaxRegime` (opcional) faz o matcher (§5, Passo 2) exigir e desempatar por `cliente.taxRegime` quando a regra define esse critério; `pedidos_page.dart` já envia `customerTaxRegime: selectedCliente?.taxRegime` para `calcularTotaisItem()`.

---

## 11. Checklist de fechamento de lacunas (com base legal)

| # | Lacuna | Base legal / referência | Status |
|---|---|---|---|
| 1 | FCP (normal/ST/DIFAL) não modelado na matriz | Leis estaduais instituidoras de FCP (ex.: Lei estadual específica de cada UF, autorizadas pela EC 42/2003) | ✅ Implementado (`TaxRule.aliquotaFcp*`, §4.3/§5e) |
| 2 | Fim da partilha do DIFAL (100% para UF destino desde 2024) | EC 87/2015; Convênio ICMS 236/2021 (regulamentação pós-ADI 5469) | ✅ Já é a premissa assumida em §5d |
| 3 | Redução de base aplicada também ao ICMS próprio (não só ao ST) em operações internas | Convênio ICMS 52/91 (exemplo de máquinas e equipamentos) — validado numericamente com planilha SP real (§16) | ✅ Implementado (`TaxRule.stReductionAppliesToIcmsProprio`) |
| 4 | Classificador de perfil não lê overrides dinâmicos de `tax_operation_profiles` | — (gap de implementação, não de legislação) | ✅ Implementado (`classify(overrides:, representedCompanyId:)`) |
| 5 | Matcher da matriz sem fallback terminal "regra geral por UF" | — (gap de implementação) | ✅ Implementado (cadeia produto > grupo > NCM > UF genérica) |
| 6 | PIS/COFINS monofásico não soma ao preço de revenda B2B por padrão | Leis 10.637/2002 e 10.833/2003 (regimes não cumulativos) e leis específicas de monofasia por segmento (ex.: Lei 10.147/2000 para cosméticos/farmacêuticos) | ✅ Premissa documentada em §1.3 |
| 7 | Reforma Tributária sem alíquotas cravadas | LC 214/2025; calendário de transição 2026–2033 definido em lei complementar e resoluções do Senado ano a ano | ✅ Estrutura parametrizável em §7; campos já existem em `TaxRule` (sem cálculo ativo) |
| 8 | MVA ajustado para comprador Simples Nacional não considerado no matcher | Protocolos/convênios ICMS específicos por UF (ex.: variações estaduais de ajuste de MVA) | ✅ Implementado (`TaxRule.applicableBuyerTaxRegime`) |
| 9 | Segmentos excepcionais (armas, bebidas, veículos) fora de escopo | Convênios/leis específicas por segmento (ex.: Convênio 110/2007 para combustíveis) | ⚠️ Assunção a confirmar com negócio (§1.2) |
| 10 | Sincronização ERP para `tax_rule_groups` e `tax_operation_profiles` ainda manual | — (gap de implementação) | ❌ Backlog P1 (§13) |

---

## 12. Estado atual de implementação

Consolidado a partir de [pricing_taxation_rules.md](pricing_taxation_rules.md) e verificação direta do código (atualizado após a implementação do backlog P0/P1 nesta sessão).

### 12.1 Implementado e em produção

- **Portal — 3 submenus**: Matriz tributária (`web_portal_tax_rules_section.dart`), Grupos tributários e Perfis de operação (`web_portal_taxation_section.dart`), com CRUD completo, importação/exportação via planilha, filtros, prioridade.
- **Modelo de dados**: 3 coleções Firestore (`tax_rules`, `tax_rule_groups`, `tax_operation_profiles`) com repositório dedicado (`firestore_tax_rule_repository.dart`, `firestore_tax_operation_profile_repository.dart`), incluindo filtro de documentos legados (`docType=operation_profile`).
- **Pipeline de cálculo**: `ProductTaxEngineService.calcularTotaisItem()` calcula IPI, ICMS próprio (com redução de base opcional), ICMS-ST (MVA e PMC, incluindo IPI na base do MVA), DIFAL, FCP/FCP-ST/FCP-DIFAL e ajuste ZFM, usando os switches do perfil classificado (`TaxOperationClassifierService`) e arredondamento centralizado (`TaxRoundingPolicy`).
- **Matcher completo (P0.1)**: cadeia de fallback produto específico > grupo tributário > NCM > regra geral por UF (fallback terminal), com CEST e `applicableBuyerTaxRegime` como critérios de desempate dentro do mesmo nível, filtro de UF origem/destino e vigência (`ProductTaxEngineService._resolveTaxRule`).
- **Classificador dinâmico (P0.2)**: `TaxOperationClassifierService.classify()` aceita `overrides`/`representedCompanyId` e prioriza override ativo (escopado > global) sobre o mapa nativo em memória.
- **Arredondamento centralizado (P0.3)**: `TaxRoundingPolicy` (meio-para-cima, com correção de épsilon) usado em todos os valores finais do pipeline.
- **FCP (P1.1)**: campos `TaxRule.aliquotaFcp`/`aliquotaFcpSt`/`aliquotaFcpDifal` e cálculo correspondente somado ao total do item.
- **Critério de regime tributário do comprador (P1.2)**: `TaxRule.applicableBuyerTaxRegime`, usado pelo matcher quando a regra o define; `pedidos_page.dart` já envia `cliente.taxRegime`.
- **Campos estruturais da Reforma Tributária (P1.5)**: `reformaClassificacaoTributaria` (CCLASSTRIB), `reformaAliquotaReferenciaIbs`, `reformaAliquotaReferenciaCbs`, `reformaPercentualReducao` já existem em `TaxRule` (somente armazenamento, sem cálculo ativo).
- **Sincronização Sankhya (já em produção)**: `syncSankhyaTaxRulesModule()`/`buildSankhyaTaxRulesSql()` em `functions/index.js`, lendo `TGFICM`/`TGFNCM`/`TGFPRO` via SQL DbExplorer, populando `tax_rules` automaticamente, com métricas de importação/poda.
- **Mapeamento de TOPs do ERP**: as 10 chaves de perfil já têm mapeamento persistido por tenant (`erpOrderTopCodes`), usado no módulo de integração ERP (`enterprise_erp_integration_service.dart`).
- **Segurança Firestore**: `firestore.rules` já cobre `tax_rules`, `tax_rule_groups`, `tax_operation_profiles` e `produtos` (campo `grupo_tributario_id`), com função `canManageTaxRulesWrite(tenantId)`.
- **Testes de regressão (P0.4)**: `product_tax_engine_service_test.dart` cobre a cadeia completa do matcher (tiers 0/1/2/3), o critério de regime do comprador, FCP/FCP-ST/FCP-DIFAL, overrides dinâmicos do classificador e os 3 casos numéricos validados do §16; `tax_rounding_policy_test.dart` cobre o arredondamento meio-para-cima (incluindo o caso `2.675`).
- **Auditoria fiscal por item (P1.4)**: diálogo "Detalhes fiscais" em `pedidos_page.dart` (acionado pelo resumo fiscal de cada item) mostra regra aplicada, nível do matcher (produto/grupo/NCM/UF genérica), critérios de desempate (CEST/regime do comprador), perfil de operação e origem (nativo vs. override) e breakdown de valores.
- **Template/importação de planilha e diálogo manual alinhados ao motor atual**: `web_portal_tax_rules_section.dart` ganhou colunas/campo para `aliquotaFcp`/`aliquotaFcpSt`/`aliquotaFcpDifal`, `applicableBuyerTaxRegime` (dropdown Simples Nacional/Lucro Presumido/Lucro Real) e `stReductionAppliesToIcmsProprio` tanto no template XLSX (download/import/validação) quanto no diálogo de criação/edição manual e no fingerprint de deduplicação — antes esses campos existiam só no modelo/engine e não eram alcançáveis via UI (ficavam sempre nulos/`false` em regras criadas ou editadas pelo portal).

### 12.2 Limitações conhecidas (trabalho futuro)

- Sincronização ERP automática existe para `tax_rules` (via TGFICM/TGFNCM/TGFPRO) e agora também um assistente de busca (não-automático) de `TGFTOP` para apoiar o preenchimento manual de `tax_operation_profiles`/`erpOrderTopCodes`; `tax_rule_groups` permanece manual (sem fonte ERP direta identificada).
- PIS/COFINS/ISS permanecem neutros por padrão (nenhuma mudança nesta sessão, ver §1.3) — ativação por grupo é item P2.
- Campos da Reforma Tributária são apenas estruturais; nenhum cálculo usa esses campos ainda (aguardando necessidade real de negócio, ver §7).

---

## 13. Backlog técnico priorizado

### P0 — Concluído nesta sessão

1. ✅ Matcher em cadeia completo: produto específico > grupo tributário > NCM > CEST > regra geral UF (fallback terminal), mantendo prioridade e vigência.
2. ✅ Classificador dinâmico: `TaxOperationClassifierService` lê overrides de `tax_operation_profiles` (escopado por representada > global > nativo).
3. ✅ Arredondamento centralizado: `TaxRoundingPolicy`, usado por todo o pipeline.
4. ✅ Testes automatizados cobrindo: contribuinte/não contribuinte, ZFM, com/sem grupo tributário, MVA x PMC, redução de base aplicada ao ICMS próprio (caso SP, §16), matcher fallback chain, overrides do classificador, FCP e regime do comprador.

### P1 — Concluído nesta sessão (exceto onde indicado)

1. ✅ Campos de FCP (normal/ST/DIFAL) no modelo `TaxRule` e no pipeline.
2. ✅ Critério `cliente.taxRegime` (Simples do comprador) como desempate no matcher (`TaxRule.applicableBuyerTaxRegime`).
3. ✅ **Assistente de mapeamento implementado** para `tax_operation_profiles`: nova Cloud Function `fetchSankhyaOperationTypes` (`functions/index.js`) consulta `TGFTOP` (deduplicado pelo `DHALTER` mais recente, apenas `ATIVO='S'`) e devolve `CODTIPOPER`/`DESCROPER`/flags ao app; na tela "Integracao ERP" > card "TOPs para criacao de pedido", o botao "Buscar TOPs do Sankhya" carrega a lista e cada um dos 10 campos de TOP ganha um botao de busca (lupa) que abre um diálogo de selecao por codigo/descricao — o usuario escolhe visualmente a TOP equivalente (as descricoes do Sankhya e dos 10 perfis nativos já são semanticamente equivalentes, não é necessário algoritmo de match automático) em vez de digitar o codigo de cabeca. Não é sincronização automática (grava direto) nem grava nada sozinha — é só um assistente de busca/preenchimento; o salvamento continua manual via "Salvar TOPs de pedido" (`erpOrderTopCodes`, já existente). **Requer deploy da nova função** (`functions/index.js`) antes de uso em produção — ainda não implantada nesta sessão.
   - **`tax_rule_groups` ficou fora de escopo**: `TGFPAR` é cadastro de parceiro/cliente, não de produto, então não serve como fonte para agrupamento tributário de produtos; o uso real de `TGFPAR` é inferir o perfil fiscal do cliente (contribuinte/não contribuinte) num futuro ciclo de importação de clientes do Sankhya (feature separada, ainda não construída). `tax_rule_groups` continua manual (CRUD + importação de planilha).
4. ✅ Tela/diálogo de auditoria de decisão tributária: `ProductTaxCalculationResult`/`PedidoItemTaxSnapshot` ganharam `matchedTier`, `matchedByCest`, `matchedByBuyerRegime`, `operationProfileKey`, `operationProfileSource`, `operationProfileOverrideId`; `pedidos_page.dart` exibe um diálogo "Detalhes fiscais" por item (acionado a partir do resumo fiscal da linha) explicando qual regra/nível foi usado, critérios de desempate, perfil de operação (nativo ou override) e o breakdown de valores (IPI/ICMS-ST/DIFAL/FCP/FCP-ST/FCP-DIFAL). Escopo é ponto-no-tempo (sem coleção de log persistida); itens de pedidos salvos antes dessa mudança não têm esses campos (ficam como "Não identificado").
5. ✅ Campos estruturais da Reforma Tributária em `TaxRule` (§4.3/§7), sem ativar cálculo ainda.

### P2 — Baixa prioridade / otimização (não iniciado)

1. Extensão de item de serviço (`itemType`, ISS) — implementar apenas quando houver demanda real de catálogo de serviços.
2. Importação/exportação de perfis de operação por planilha.
3. Catálogo de versões de matriz por vigência (histórico de alíquotas).
4. Otimização de leitura para catálogos grandes (delta por `updatedAt`).
5. Módulo PIS/COFINS/ISS ativável por grupo (hoje neutro por padrão, §1.3).

---

## 14. Integração Sankhya — mapa de dados

> Este mapeamento é referência para trabalho **futuro**, após o motor core (P0 do backlog) estar fechado — não bloqueia a especificação do motor em si.

| Tabela Sankhya | Papel | Status de sincronização |
|---|---|---|
| **TGFICM** | Tabela mestra de regras ICMS/ST/DIFAL/FCP (fonte principal da matriz) | ⚠️ Parcialmente sincronizada (`syncSankhyaTaxRulesModule`): ICMS próprio, ICMS-ST (MVA/pauta), CST/CSOSN, redução de base ST e vigência já vêm do Sankhya. **DIFAL (alíquota) e os 3 campos de FCP (`aliquotaFcp`/`aliquotaFcpSt`/`aliquotaFcpDifal`) NÃO são extraídos** (hardcoded/ausentes no mapeamento atual) — ver auditoria detalhada abaixo. |
| **TGFNCM** | NCM/CEST/IPI de referência | ✅ Já usada no sync atual (join para enriquecer regra). |
| **TGFPRO** | Campos fiscais do produto (`ORIGPROD`, `GRUPOICMS`/`GRUPOICMS2`, `MVAPADRAO`, `CODESPECST`, `TEMICMS`/`TEMIPIVENDA`) | ✅ Já usada no sync atual. |
| **TGFTOP** | Tipos de operação (TOP) com flags de comportamento (`CALCDIFALPART`, `CALCICMS`, `CALCFCPINT`, `CALCFUSTTOP`, etc.) | ✅ Assistente de busca implementado (`fetchSankhyaOperationTypes`) para apoiar o preenchimento manual de `erpOrderTopCodes`/`tax_operation_profiles` — não é sync automático, aguardando deploy. |
| **TGFPAR** | Campos fiscais do parceiro/cliente (`CLASSIFICMS`, `CODTABST`, `TIPPESSOA`, `IDENTINSCESTAD`) — útil para inferir `taxProfile` (contribuinte/não contribuinte) automaticamente | ❌ Fora de escopo de `tax_rule_groups`/`tax_operation_profiles` (é dado de cliente, não de produto); relevante só para um futuro ciclo de importação de clientes do Sankhya. Amostra real já obtida: `CLASSIFICMS` com valores R/C/I/P/null (distribuição real: R=15088, C=512, I=119, P=6, null=1). |
| **TGFPEM** | Parâmetros item-level da Reforma Tributária (`ALIQADREM`, `CCLASSTRIB`, `CST`, `IVA`, `INDGIBSCBS`) | ❌ Relevante apenas quando o módulo de Reforma (§7) for ativado; sem sync hoje. |
| **TGFITE** / **TGFCUSITE** | Valores de custo/contabilização já lançados no faturamento | ⚪ Não é fonte de regra — útil apenas para validação pós-cálculo (QA, comparar o que o motor previu x o que o ERP faturou). |
| **TGFCON** / **TGFDIN** / **TGFVEN** | Contratos, conferência/CT-e, comissão de vendedor | ⚪ Fora do escopo do motor fiscal. |
| **TSIUFS** | Tabela de lookup de UFs | ✅ Já usada no sync atual (join). |

### 14.1 Auditoria de cobertura do sync de `tax_rules` (2026-10-26, atualizado)

Pergunta respondida: **o sync Sankhya atual já é suficiente para cadastrar 100% das regras sem trabalho manual/planilha?** Resposta: **ainda não 100%, mas a maior parte do núcleo ICMS/ST/DIFAL/FCP já é coberta pelo sync**. O SQL de `buildSankhyaTaxRulesSql()` é sofisticado (trata 7 ramos de `TIPRESTRICAO`/`TIPRESTRICAO2` do Sankhya: NCM direto, produto específico, grupo ICMS):

- `aliquotaDifal` — ✅ **resolvido**: calculado como `GREATEST(ALIQINTDEST - ALIQUOTA, 0)` quando UF origem ≠ UF destino, extraído diretamente do Sankhya.
- `aliquotaFcp` / `aliquotaFcpSt` — ✅ **resolvido**: extraídos de `PERCICMSFCPINT`/`PERCICMSFCP`/`PERCSTFCPINT` do Sankhya. `aliquotaFcpDifal` continua sem fonte no Sankhya (manual).
- `stPriceForCalculation` (preço de pauta/PMC) — também hardcoded como `NULL`; quando `stCalculationType = 'pmc'` é detectado (`PAUTAVLRSTFIXO` preenchido), o valor do preço de pauta em si não é propagado para o campo correspondente.
- `applicableBuyerTaxRegime` — o sync não diferencia linhas de `TGFICM` por regime do comprador (ex.: MVA ajustado Simples Nacional); se o Sankhya tiver regras distintas por regime, elas são importadas sem essa marcação, e o critério de desempate do motor (`applicableBuyerTaxRegime`) fica sem efeito nessas regras.
- `stReductionAppliesToIcmsProprio` — não inferido do Sankhya; precisa continuar sendo marcado manualmente caso a caso (ex.: Convênio ICMS 52/91 em SP).
- `produtoId` — quando o Sankhya tem uma exceção fiscal por produto específico (`TIPRESTRICAO`/`TIPRESTRICAO2` = `P`/`1`/`I`/`K`), o sync resolve o NCM daquele produto e grava a regra **no nível de NCM**, não no nível de produto — ou seja, uma exceção pensada para 1 produto específico no Sankhya pode acabar valendo para todos os produtos do mesmo NCM no SmartSFA. Risco real de generalização indevida em catálogos com muitas exceções pontuais.
- Regras removidas/desativadas no Sankhya — ✅ **resolvido**: a poda agora remove qualquer regra `origin:'erp'` global (`representedCompanyId` vazio) cujo id não foi regravado na execução atual do sync (`prunedStaleRuleCount`), em vez de depender apenas da ausência de NCM.
- Escopo por representada: o sync sempre grava `representedCompanyId: null` (regra global); não há diferenciação por representada no sync atual.
- Linhas de exceção por NCM/produto/grupo sem **nenhum** valor fiscal real (todos os campos numéricos zerados/nulos) são descartadas no mapeamento (`mapSankhyaTaxRuleRow`) — no Sankhya elas existem só para fins de CST/CSOSN/CEST, e se importadas como regra por NCM mascarariam com 0% a regra geral por UF (que é quem realmente carrega a alíquota).
- Regra geral por UF (sem NCM) — ✅ **agora importada** (antes era descartada por um filtro que exigia NCM obrigatório); vira o fallback terminal (tier 4) do matcher quando não há grupo/NCM específico.

Conclusão prática: o sync cobre hoje ICMS próprio, ICMS-ST (MVA/pauta), DIFAL, FCP (interno/ST) e a regra geral por UF; falta apenas FCP-DIFAL, preço de pauta (PMC), regime do comprador e o flag de redução do ICMS próprio — itens residuais, normalmente de baixa incidência, que continuam exigindo complemento manual (diálogo ou planilha).

### 14.2 Agrupamento automático de Grupo Tributário (fingerprint fiscal)

Implementado em `functions/index.js` (`syncSankhyaTaxRulesModule`): durante o sync de `tax_rules`, NCMs com **perfil fiscal idêntico** (mesmo conjunto de alíquotas/MVA/redução de base/CST-CSOSN/FCP em todos os pares de UF, após descartar linhas sem valor fiscal real) são automaticamente agrupados em um `tax_rule_groups` com `source: 'erp_sync'`, sem qualquer intervenção manual:

1. Para cada NCM com exceção fiscal (via `TGFICM`), monta-se um vetor ordenado `{ufOrigem, ufDestino, aliquotaDestino, aliquotaCredito, aliquotaDifal, mvaIva, stBaseReductionPercent, stBaseAmount, stCalculationType, cstCsosn, aliquotaFcp, aliquotaFcpSt}` por par de UF.
2. O vetor é serializado e hasheado (SHA-1, truncado) — NCMs com hash idêntico compartilham o mesmo "fingerprint" fiscal.
3. Quando **2 ou mais NCMs** caem no mesmo fingerprint, cria-se (ou atualiza-se, de forma idempotente) um `tax_rule_groups` com `memberNcms`, `fingerprint`, `externalCode`, nome/descrição auto-gerados (preservados se o usuário customizar manualmente, via flag `autoGenerated`) e um único conjunto de `tax_rules` com `taxGroupId` (um por par de UF do grupo, sem NCM/CEST) substituindo as regras individuais por NCM.
4. NCMs com fingerprint único (nenhum outro NCM compartilha o mesmo perfil) continuam com regra individual por NCM (tier 3), sem agrupamento forçado.
5. NCMs sem nenhuma exceção fiscal (só a regra geral por UF se aplica) não recebem grupo — dependem do fallback terminal (tier 4), como já previsto no matcher.
6. `Produto.grupoTributarioId` é propagado automaticamente: (a) para produtos já sincronizados, via `applyTaxGroupsToExistingProducts` ao final do sync de `tax_rules`; (b) para produtos sincronizados depois, via `buildTenantNcmGroupIndex` consultado no início de `syncSankhyaProductsModule`. Funciona independente da ordem/momento dos dois syncs (que são chamadas HTTP separadas).

Importante: o fingerprint usa **exclusivamente valores fiscais já resolvidos pelo próprio SmartSFA** (alíquotas, MVA, CST etc.) — nunca um campo de agrupamento nativo do Sankhya (`CODTRIB`/`GRUPOICMS`), mantendo o desacoplamento ERP já adotado em `tax_operation_profiles`/`erpOrderTopCodes`.

---

## 15. Plano de importação via planilha (ERPs genéricos)

Para representadas cujo ERP não seja o Sankhya (ou que ainda não tenham integração via API), o SmartSFA já suporta **importação de matriz tributária via planilha (XLSX/CSV)** no submenu "Matriz tributária" do portal. As planilhas de referência analisadas nesta especificação (`Catálogo SP.xlsx`, `Catálogo MG.xlsx`) são **exemplos de formato de exportação genérico de ERP**, não exclusivos do Sankhya — ou seja, o template de importação do SmartSFA deve continuar agnóstico de ERP de origem, aceitando qualquer planilha que tenha, no mínimo, as colunas de NCM/CEST, alíquota ICMS interna, alíquota interestadual, MVA/IVA (ou pauta PMC), redução de base e alíquota de IPI — já contempladas no template de importação existente.

Nenhuma mudança de código é necessária nesta frente — o fluxo de importação por planilha já é genérico; esta seção apenas documenta a premissa para evitar acoplamento futuro indevido ao formato específico de um ERP.

---

## 16. Apêndice — exemplos numéricos validados (golden tests)

Casos reais extraídos da planilha **Catálogo SP.xlsx** (operação interna, 9.870 produtos, 35 combinações únicas de parâmetros fiscais), usados para validar a fórmula de ICMS-ST com MVA do §5c.

### Caso 1 — MVA simples, sem redução de base

- NCM `73269090` (abraçadeira em aço inox), IPI = 5%, ICMS = 18%, Redução = 0%, MVA = 179%.

$$
\text{Reflexo ST} = \left[(1 + 0{,}05) \times (1 + 1{,}79) \times 18\%\right] - 18\% = 52{,}731\% - 18\% = \mathbf{34{,}73\%}
$$

Valor da planilha: **34,73%** — ✅ confere (diferença de arredondamento de 0,0010 p.p., irrelevante).

### Caso 2 — MVA simples, outro NCM

- NCM `39269090` (abraçadeira em nylon), IPI = 9,75%, ICMS = 18%, Redução = 0%, MVA = 120%.

$$
\text{Reflexo ST} = \left[(1 + 0{,}0975) \times (1 + 1{,}20) \times 18\%\right] - 18\% = 43{,}461\% - 18\% = \mathbf{25{,}46\%}
$$

Valor da planilha: **25,46%** — ✅ confere.

### Caso 3 — Redução de base aplicada tanto ao ICMS próprio quanto ao ST

- NCM `85044010`, IPI = 5%, ICMS = 18%, **Redução de base = 48,89%** (carga efetiva ≈ 8,80%, Convênio ICMS 52/91), MVA = 78%.

$$
\text{Reflexo ST} = \left[(1 + 0{,}05) \times (1 + 0{,}78) \times 0{,}4889 \times 18\%\right] - (0{,}4889 \times 18\%) = 16{,}4474\% - 8{,}80\% = \mathbf{7{,}6474\%}
$$

Valor da planilha: **7,6498%** (diferença de ~0,0024 p.p., atribuível a arredondamento interno da planilha de origem — a fórmula está validada como corretamente estruturada; pequenas diferenças residuais devem ser investigadas caso a caso ao integrar com um ERP real, não indicam erro de fórmula).

> **Nota sobre a convenção de sinal da redução de base**: a planilha de origem usa a coluna "Redução" como o **fator de retenção já calculado** (ex.: `0,4889`, aplicado diretamente como multiplicador). O campo de produção `TaxRule.stBaseReductionPercent` (alimentado pelo `REDBASEST` do Sankhya via `functions/index.js`) usa a convenção oposta: **percentual a subtrair** da base cheia (ex.: `51,11` ⇒ fator efetivo `1 − 0,5111 = 0,4889`). As duas convenções chegam ao mesmo resultado numérico; o teste de regressão correspondente (`product_tax_engine_service_test.dart`, grupo "golden tests") usa `stBaseReductionPercent: 51.11` para reproduzir este caso 3 com o campo de produção.

**Conclusão de validação**: a fórmula do §5b/§5c (redução de base aplicada tanto na base do ICMS próprio quanto na base do ST, quando a regra assim determina) está matematicamente correta e confirmada contra dados reais de produção de uma representada. Esses 3 casos foram promovidos a **testes de unidade de regressão** (`product_tax_engine_service_test.dart`, grupo "golden tests - validated SP ICMS-ST cases").

---

## 17. Referências

- [tributacao_engine.md](tributacao_engine.md) — transcript original de brainstorming (arquitetura de 3 tabelas, validação numérica bruta).
- [pricing_taxation_rules.md](pricing_taxation_rules.md) — handoff técnico anterior (estado de implementação e backlog, agora consolidado aqui).
- [enduser_Regras_de_Tributacao.md](enduser_Regras_de_Tributacao.md) — explicação simplificada para usuário final.
- Legislação citada: EC 42/2003 (FCP), EC 87/2015 e Convênio ICMS 236/2021 (DIFAL/fim da partilha), Convênio ICMS 52/91 (redução de base, máquinas/equipamentos), Resolução do Senado 13/2012 (alíquota de 4% para importados), Leis 10.637/2002 e 10.833/2003 (PIS/COFINS não cumulativo), LC 214/2025 (Reforma Tributária/IBS-CBS-IS).
