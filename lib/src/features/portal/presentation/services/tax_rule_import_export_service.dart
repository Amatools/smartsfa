import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/constants/brazil_states.dart';
import '../../../../core/data/firestore/firestore_tax_rule_repository.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tax_rule.dart';
import '../../../../shared/services/tabular_spreadsheet_service.dart';
import 'tax_rule_formatting_utils.dart';

/// Resultado da validacao estrutural de uma planilha de importacao de
/// regras de tributacao, antes de gravar qualquer dado no Firestore.
class TaxRuleImportValidation {
  const TaxRuleImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

/// Resultado agregado de uma importacao de planilha de regras de tributacao.
class TaxRuleImportResult {
  const TaxRuleImportResult({
    required this.imported,
    required this.skipped,
    required this.skippedNoChange,
  });

  final int imported;
  final int skipped;
  final int skippedNoChange;
}

/// Concentra a logica de negocio de exportacao (modelo XLSX), validacao e
/// importacao em massa de regras de tributacao (`TaxRule`) via planilha.
///
/// Extraido de `_TaxRulesSectionState`
/// (`web_portal_tax_rules_section.dart`) para isolar regras de
/// parsing/normalizacao/deduplicacao por fingerprint da camada de
/// apresentacao (SRP) — ver `docs/tributacao_motor_especificacao_tecnica.md`.
/// A camada de UI continua responsavel por: disparar o download do arquivo
/// gerado, exibir o modal de importacao e tratar mensagens de erro/sucesso.
class TaxRuleImportExportService {
  const TaxRuleImportExportService._();

  /// Monta os bytes do XLSX de modelo/exportacao: uma aba `Tributacao` com
  /// os dados atuais (ou uma linha de exemplo, se nao houver regra alguma)
  /// e uma aba `Instrucoes` com o significado de cada coluna.
  static Uint8List buildTemplateBytes(List<TaxRule> existingRules) {
    final rows = existingRules
        .map(
          (rule) => <String>[
            rule.status,
            withFallback(rule.ncm, ''),
            withFallback(rule.cest, ''),
            withFallback(rule.ufOrigem, 'ANY'),
            withFallback(rule.ufDestino, ''),
            withFallback(rule.taxGroupId, ''),
            withFallback(rule.stCalculationType, 'mva'),
            rule.stPriceForCalculation?.toString() ?? '',
            rule.stBaseReductionPercent?.toString() ?? '',
            rule.stBaseAmount?.toString() ?? '',
            rule.aliquotaDestino?.toString() ?? '',
            rule.aliquotaCredito?.toString() ?? '',
            rule.aliquotaDifal?.toString() ?? '',
            withFallback(rule.cstCsosn, ''),
            rule.mvaIva?.toString() ?? '',
            rule.aliquotaFcp?.toString() ?? '',
            rule.aliquotaFcpSt?.toString() ?? '',
            rule.aliquotaFcpDifal?.toString() ?? '',
            _buyerTaxRegimeLabelForExport(rule.applicableBuyerTaxRegime),
            rule.stReductionAppliesToIcmsProprio ? 'Sim' : 'Nao',
            rule.reformaAliquotaIbsEstadual?.toString() ?? '',
            rule.reformaAliquotaIbsMunicipal?.toString() ?? '',
            rule.reformaPercentualReducaoIbs?.toString() ?? '',
            rule.reformaAliquotaReferenciaCbs?.toString() ?? '',
            rule.reformaPercentualReducaoCbs?.toString() ?? '',
            rule.reformaAliquotaReferenciaIs?.toString() ?? '',
            withFallback(rule.fiscalException, ''),
            rule.validFrom?.toIso8601String().substring(0, 10) ?? '',
            rule.validUntil?.toIso8601String().substring(0, 10) ?? '',
            rule.priority.toString(),
          ],
        )
        .toList(growable: false);

    final templateRows = rows.isEmpty
        ? const <List<String>>[
            <String>[
              'active',
              '0000.00.00',
              '00.000.00',
              'ANY',
              'SP',
              '',
              'mva',
              '100.00',
              '0',
              '',
              '18',
              '12',
              '2',
              '060',
              '40',
              '',
              '',
              '',
              '',
              'Nao',
              '',
              '',
              '',
              '',
              '',
              '',
              'REGRA EXEMPLO',
              '',
              '',
              '1',
            ],
          ]
        : rows;

    return TabularSpreadsheetService.buildXlsxWithSheets(
      sheets: <TabularSpreadsheetSheet>[
        TabularSpreadsheetSheet(
          sheetName: 'Tributacao',
          headers: const <String>[
            'Status',
            'NCM',
            'CEST',
            'UF origem',
            'UF destino',
            'Grupo tributario',
            'Tipo ST',
            'Preco para calculo ST',
            'Reducao base ICMS ST',
            'Base calculo ICMS ST',
            'Aliquota destino',
            'Aliquota credito',
            'Aliquota DIFAL',
            'CST/CSOSN',
            'MVA',
            'Aliquota FCP',
            'Aliquota FCP ST',
            'Aliquota FCP DIFAL',
            'Regime tributario comprador',
            'Reducao aplica ICMS proprio',
            'Aliquota IBS estadual',
            'Aliquota IBS municipal',
            'Percentual reducao IBS',
            'Aliquota referencia CBS',
            'Percentual reducao CBS',
            'Aliquota referencia IS (seletivo)',
            'Excecao fiscal',
            'Vigencia inicial',
            'Vigencia final',
            'Prioridade',
          ],
          rows: templateRows,
        ),
        const TabularSpreadsheetSheet(
          sheetName: 'Instrucoes',
          headers: <String>['Campo', 'Obrigatorio', 'Regra'],
          rows: <List<String>>[
            <String>[
              'NCM',
              'Sim',
              'Obrigatorio. Deve ter 8 digitos no formato 0000.00.00.',
            ],
            <String>[
              'CEST',
              'Opcional',
              'Quando informado, deve ter 7 digitos no formato 00.000.00.',
            ],
            <String>[
              'Status',
              'Nao',
              'Use active ou inactive. Vazio assume active.',
            ],
            <String>[
              'UF origem',
              'Opcional',
              'Use sigla UF (SP, RJ, MG...) ou ANY. Vazio usa ANY.',
            ],
            <String>['UF destino', 'Sim', 'Use sigla UF (SP, RJ, MG...).'],
            <String>[
              'Grupo tributario',
              'Opcional',
              'ID do grupo cadastrado no modulo Grupos tributarios.',
            ],
            <String>['Tipo ST', 'Sim', 'Aceito apenas MVA ou PMC.'],
            <String>[
              'Preco para calculo ST',
              'Opcional',
              'Numerico. Usado como preco base de referencia no calculo.',
            ],
            <String>['MVA', 'Condicional', 'Obrigatorio quando Tipo ST = MVA.'],
            <String>[
              'Reducao base ICMS ST',
              'Condicional',
              'Obrigatorio quando Tipo ST = MVA.',
            ],
            <String>[
              'Base calculo ICMS ST',
              'Condicional',
              'Obrigatorio quando Tipo ST = PMC.',
            ],
            <String>[
              'Aliquota destino',
              'Sim',
              'Percentual numerico. Ex.: 18 ou 18,5',
            ],
            <String>[
              'Aliquota credito',
              'Sim',
              'Percentual numerico. Ex.: 12 ou 12,0',
            ],
            <String>[
              'Aliquota DIFAL',
              'Opcional',
              'Percentual numerico. Ex.: 2 ou 2,5',
            ],
            <String>['CST/CSOSN', 'Opcional', 'Codigo fiscal da regra.'],
            <String>[
              'Aliquota FCP',
              'Opcional',
              'Percentual numerico do FCP sobre o ICMS proprio. Ex.: 2',
            ],
            <String>[
              'Aliquota FCP ST',
              'Opcional',
              'Percentual numerico do FCP embutido no ICMS-ST. Ex.: 2',
            ],
            <String>[
              'Aliquota FCP DIFAL',
              'Opcional',
              'Percentual numerico do FCP sobre o DIFAL. Ex.: 2',
            ],
            <String>[
              'Regime tributario comprador',
              'Opcional',
              'Use Simples Nacional, Lucro Presumido ou Lucro Real para restringir a regra a esse regime do cliente. Vazio aplica a qualquer regime.',
            ],
            <String>[
              'Reducao aplica ICMS proprio',
              'Opcional',
              'Use Sim ou Nao. Vazio assume Nao. Define se a reducao de base do ICMS-ST tambem reduz a base do ICMS proprio.',
            ],
            <String>[
              'Aliquota IBS estadual',
              'Opcional',
              'Percentual numerico da parcela estadual do IBS (substituta do ICMS). Ex.: 9. Nao altera o preco final nesta fase.',
            ],
            <String>[
              'Aliquota IBS municipal',
              'Opcional',
              'Percentual numerico da parcela municipal do IBS (substituta do ISS). Ex.: 9. Nao altera o preco final nesta fase.',
            ],
            <String>[
              'Percentual reducao IBS',
              'Opcional',
              'Percentual de reducao de aliquota do IBS aplicavel ao item (ex.: cesta basica). Ex.: 60.',
            ],
            <String>[
              'Aliquota referencia CBS',
              'Opcional',
              'Percentual numerico de referencia do CBS para esta regra. Ex.: 9. Nao altera o preco final nesta fase.',
            ],
            <String>[
              'Percentual reducao CBS',
              'Opcional',
              'Percentual de reducao de aliquota do CBS aplicavel ao item (ex.: cesta basica). Ex.: 60.',
            ],
            <String>[
              'Aliquota referencia IS (seletivo)',
              'Opcional',
              'Percentual numerico de referencia do Imposto Seletivo, quando aplicavel ao produto (ex.: bebidas, cigarros). Nao altera o preco final nesta fase. A lei nao preve reducao para o Imposto Seletivo.',
            ],
            <String>[
              'Excecao fiscal',
              'Opcional',
              'Texto livre para observacoes da regra.',
            ],
            <String>[
              'Vigencia inicial',
              'Opcional',
              'Data no formato AAAA-MM-DD ou DD/MM/AAAA.',
            ],
            <String>[
              'Vigencia final',
              'Opcional',
              'Data no formato AAAA-MM-DD ou DD/MM/AAAA.',
            ],
            <String>[
              'Prioridade',
              'Opcional',
              'Inteiro. Se vazio, o sistema gera automaticamente.',
            ],
          ],
        ),
      ],
    );
  }

  /// Valida a estrutura/consistencia de um arquivo de planilha antes de
  /// permitir a importacao (cabecalho obrigatorio, NCM, UF destino, tipo ST,
  /// aliquotas condicionais por tipo e regime tributario do comprador).
  static TaxRuleImportValidation validateImportFile(PlatformFile file) {
    final parsed = TabularSpreadsheetService.parseFile(file);
    if (!parsed.ok) {
      return TaxRuleImportValidation(
        ok: false,
        message: parsed.message,
        rows: const <Map<String, String>>[],
      );
    }

    final headers = parsed.headers;
    final hasUfDestino =
        headers.contains('ufdestino') || headers.contains('uf_destino');
    if (!hasUfDestino) {
      return const TaxRuleImportValidation(
        ok: false,
        message: 'Cabecalho invalido. Campo obrigatorio: UF destino.',
        rows: <Map<String, String>>[],
      );
    }

    if (parsed.rows.isEmpty) {
      return const TaxRuleImportValidation(
        ok: false,
        message: 'Planilha sem linhas validas para importacao.',
        rows: <Map<String, String>>[],
      );
    }

    final missingUfDestinoLines = <int>[];
    final invalidNcmLines = <int>[];
    final invalidTypeLines = <int>[];
    final missingAliquotasLines = <int>[];
    final invalidByTypeLines = <int>[];
    final invalidBuyerRegimeLines = <int>[];

    for (var index = 0; index < parsed.rows.length; index++) {
      final row = parsed.rows[index];
      final line = index + 2;

      final ufDestino = normalizeUfForStorage(
        _readTaxCell(row, const <String>[
          'ufdestino',
          'uf_destino',
          'uf destino',
        ]),
      );
      final rawNcm = normalizeNcmDigits(
        _readTaxCell(row, const <String>['ncm']),
      );
      if (ufDestino.isEmpty) {
        missingUfDestinoLines.add(line);
      }
      if (rawNcm.isEmpty || !isValidNcmDigits(rawNcm)) {
        invalidNcmLines.add(line);
      }

      final stTypeRaw = _readTaxCell(row, const <String>[
        'stcalculationtype',
        'st_calculation_type',
        'tipost',
        'tipo st',
      ]);
      final stType = _parseStTypeForImport(stTypeRaw);
      if (stType == null) {
        invalidTypeLines.add(line);
        continue;
      }

      final aliquotaDestino = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotadestino',
          'aliquota_destino',
          'aliquotast',
        ]),
      );
      final aliquotaCredito = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotacredito',
          'aliquota_credito',
          'aliquotaicms',
        ]),
      );
      if (aliquotaDestino == null || aliquotaCredito == null) {
        missingAliquotasLines.add(line);
      }

      final stBaseReductionPercent = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbasereductionpercent',
          'st_base_reduction_percent',
          'reducaobaseicmsst',
          'reducao base icms st',
        ]),
      );
      final stBaseAmount = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbaseamount',
          'st_base_amount',
          'basecalculoicmsst',
          'base calculo icms st',
        ]),
      );
      final mvaIva = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>['mvaiva', 'stmvapercent', 'mva']),
      );

      final hasRequiredByType = stType == 'mva'
          ? (mvaIva != null && stBaseReductionPercent != null)
          : stBaseAmount != null;
      if (!hasRequiredByType) {
        invalidByTypeLines.add(line);
      }

      final buyerRegimeRaw = _readTaxCell(row, const <String>[
        'applicablebuyertaxregime',
        'applicable_buyer_tax_regime',
        'regimetributariocomprador',
        'regime tributario comprador',
      ]);
      final (_, buyerRegimeValid) = _normalizeBuyerTaxRegimeForImport(
        buyerRegimeRaw,
      );
      if (!buyerRegimeValid) {
        invalidBuyerRegimeLines.add(line);
      }
    }

    if (missingUfDestinoLines.isNotEmpty ||
        invalidNcmLines.isNotEmpty ||
        invalidTypeLines.isNotEmpty ||
        missingAliquotasLines.isNotEmpty ||
        invalidByTypeLines.isNotEmpty ||
        invalidBuyerRegimeLines.isNotEmpty) {
      String sample(List<int> lines) {
        final values = lines.take(10).join(', ');
        return '$values${lines.length > 10 ? ' ...' : ''}';
      }

      final parts = <String>[];
      if (missingUfDestinoLines.isNotEmpty) {
        parts.add('UF destino ausente: ${sample(missingUfDestinoLines)}');
      }
      if (invalidNcmLines.isNotEmpty) {
        parts.add('NCM obrigatório/inválido: ${sample(invalidNcmLines)}');
      }
      if (invalidTypeLines.isNotEmpty) {
        parts.add('Tipo ST invalido: ${sample(invalidTypeLines)}');
      }
      if (missingAliquotasLines.isNotEmpty) {
        parts.add(
          'Aliquota destino/credito obrigatoria: ${sample(missingAliquotasLines)}',
        );
      }
      if (invalidByTypeLines.isNotEmpty) {
        parts.add(
          'Campos condicionais MVA/PMC invalidos: ${sample(invalidByTypeLines)}',
        );
      }
      if (invalidBuyerRegimeLines.isNotEmpty) {
        parts.add(
          'Regime tributario comprador invalido: ${sample(invalidBuyerRegimeLines)}',
        );
      }

      return TaxRuleImportValidation(
        ok: false,
        message: 'Inconsistencias na planilha (${parts.join(' | ')}).',
        rows: parsed.rows,
      );
    }

    return TaxRuleImportValidation(
      ok: true,
      message: 'Arquivo valido com ${parsed.rows.length} linha(s).',
      rows: parsed.rows,
    );
  }

  /// Importa as linhas ja validadas (`validateImportFile(...).rows`) para o
  /// Firestore, no escopo do tenant/representada informados. Pula linhas
  /// invalidas e linhas cujo fingerprint fiscal nao mudou em relacao a
  /// regra existente de mesmo id (evita regravacao/duplicacao desnecessaria).
  static Future<TaxRuleImportResult> importRows({
    required List<Map<String, String>> rows,
    required FirestoreTaxRuleRepository repository,
    required String tenantId,
    required String representedCompanyId,
  }) async {
    final existingRules = await repository.fetchAll(tenantId: tenantId);
    final scopedExistingRules = existingRules
        .where(
          (rule) =>
              (rule.representedCompanyId ?? '').trim() ==
              representedCompanyId,
        )
        .toList(growable: false);
    final existingById = <String, TaxRule>{
      for (final item in scopedExistingRules) item.id: item,
    };
    final existingFingerprints = <String>{
      for (final item in scopedExistingRules) taxRuleFingerprint(item),
    };
    var maxPriority = 0;
    for (final rule in scopedExistingRules) {
      if (rule.priority > maxPriority) {
        maxPriority = rule.priority;
      }
    }

    var imported = 0;
    var skipped = 0;
    var skippedNoChange = 0;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final rawNcm = normalizeNcmDigits(
        _readTaxCell(row, const <String>['ncm']),
      );
      final rawCest = normalizeCestDigits(
        _readTaxCell(row, const <String>['cest']),
      );
      final ufDestino = normalizeUfForStorage(
        _readTaxCell(row, const <String>[
          'ufdestino',
          'uf_destino',
          'uf destino',
        ]),
      );

      final hasUfDestinoHeader =
          row.containsKey('ufdestino') || row.containsKey('uf_destino');
      if (hasUfDestinoHeader && ufDestino.isEmpty) {
        skipped++;
        continue;
      }
      if (rawNcm.isEmpty) {
        skipped++;
        continue;
      }
      if (rawNcm.isNotEmpty && !isValidNcmDigits(rawNcm)) {
        skipped++;
        continue;
      }
      if (rawCest.isNotEmpty && !isValidCestDigits(rawCest)) {
        skipped++;
        continue;
      }

      final now = DateTime.now().toUtc();
      final sourceId = _readTaxCell(row, const <String>[
        'id',
        'ruleid',
        'rule_id',
        'id regra',
        'regraid',
        'codigo regra',
      ]);
      final id = sourceId.isEmpty
          ? FirebaseFirestore.instance.collection('tax_rules').doc().id
          : sourceId;
      final existing = existingById[id];

      final aliquotaDestino = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotadestino',
          'aliquota_destino',
          'aliquotast',
        ]),
      );
      final aliquotaCredito = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotacredito',
          'aliquota_credito',
          'aliquotaicms',
        ]),
      );

      final stTypeRaw = _readTaxCell(row, const <String>[
        'stcalculationtype',
        'st_calculation_type',
        'tipost',
        'tipo st',
      ]);
      final stType = _parseStTypeForImport(stTypeRaw);
      if (stType == null) {
        skipped++;
        continue;
      }

      final stPriceForCalculation = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stpriceforcalculation',
          'st_price_for_calculation',
          'precoparacalculost',
          'preco para calculo st',
        ]),
      );
      final stBaseReductionPercent = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbasereductionpercent',
          'st_base_reduction_percent',
          'reducaobaseicmsst',
          'reducao base icms st',
        ]),
      );
      final stBaseAmount = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'stbaseamount',
          'st_base_amount',
          'basecalculoicmsst',
          'base calculo icms st',
        ]),
      );
      final mvaIva = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>['mvaiva', 'stmvapercent', 'mva']),
      );

      final hasRequiredByType = stType == 'mva'
          ? (mvaIva != null && stBaseReductionPercent != null)
          : stBaseAmount != null;
      if (!hasRequiredByType ||
          aliquotaDestino == null ||
          aliquotaCredito == null) {
        skipped++;
        continue;
      }

      final importedPriority = int.tryParse(
        _readTaxCell(row, const <String>['priority', 'prioridade']).trim(),
      );
      final priority =
          importedPriority ?? existing?.priority ?? (maxPriority + imported + 1);

      final aliquotaFcp = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>['aliquotafcp', 'aliquota_fcp']),
      );
      final aliquotaFcpSt = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotafcpst',
          'aliquota_fcp_st',
          'aliquota fcp st',
        ]),
      );
      final aliquotaFcpDifal = TabularSpreadsheetService.parseDecimal(
        _readTaxCell(row, const <String>[
          'aliquotafcpdifal',
          'aliquota_fcp_difal',
          'aliquota fcp difal',
        ]),
      );
      final (buyerRegime, _) = _normalizeBuyerTaxRegimeForImport(
        _readTaxCell(row, const <String>[
          'applicablebuyertaxregime',
          'applicable_buyer_tax_regime',
          'regimetributariocomprador',
          'regime tributario comprador',
        ]),
      );
      final reductionAppliesToIcmsProprio = _parseSimNaoForImport(
        _readTaxCell(row, const <String>[
          'streductionappliestoicmsproprio',
          'st_reduction_applies_to_icms_proprio',
          'reducaoaplicaicmsproprio',
          'reducao aplica icms proprio',
        ]),
      );

      final entity = TaxRule(
        id: id,
        tenantId: tenantId,
        representedCompanyId: representedCompanyId,
        status: _normalizeTaxStatus(
          _readTaxCell(row, const <String>['status']),
        ),
        ncm: rawNcm.isEmpty ? null : formatNcmMasked(rawNcm),
        cest: rawCest.isEmpty ? null : formatCestMasked(rawCest),
        fiscalException: nullableTrimmed(
          _readTaxCell(row, const <String>[
            'fiscalexception',
            'fiscal_exception',
            'excecaofiscal',
            'excecao fiscal',
          ]),
        ),
        stCalculationType: stType,
        stPriceForCalculation: stPriceForCalculation,
        stBaseReductionPercent: stBaseReductionPercent,
        stBaseAmount: stBaseAmount,
        aliquotaDestino: aliquotaDestino,
        aliquotaCredito: aliquotaCredito,
        grupoFiscalId: nullableTrimmed(
          _readTaxCell(row, const <String>['grupofiscalid', 'grupo_fiscal_id']),
        ),
        taxGroupId: nullableTrimmed(
          _readTaxCell(row, const <String>[
            'taxgroupid',
            'tax_group_id',
            'grupotributarioid',
            'grupo_tributario_id',
            'grupo tributario',
            'grupo tributario id',
          ]),
        ),
        operationProfileKey: null,
        ufOrigem: _normalizeUfOrigem(
          _readTaxCell(row, const <String>[
            'uforigem',
            'uf_origem',
            'uf origem',
          ]),
          fallback: existing?.ufOrigem,
        ),
        ufDestino: normalizeUfForStorage(
          _readTaxCell(row, const <String>[
            'ufdestino',
            'uf_destino',
            'uf destino',
          ]),
        ),
        salePurpose: null,
        cstCsosn: nullableTrimmed(
          _readTaxCell(row, const <String>['cstcsosn', 'cst/csosn']),
        ),
        aliquotaIcms: aliquotaCredito,
        mvaIva: mvaIva,
        aliquotaSt: aliquotaDestino,
        aliquotaDifal: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotadifal',
            'aliquota_difal',
            'aliquota difal',
          ]),
        ),
        aliquotaFcp: aliquotaFcp,
        aliquotaFcpSt: aliquotaFcpSt,
        aliquotaFcpDifal: aliquotaFcpDifal,
        applicableBuyerTaxRegime: buyerRegime,
        stReductionAppliesToIcmsProprio: reductionAppliesToIcmsProprio,
        reformaAliquotaIbsEstadual: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotaibsestadual',
            'aliquota_ibs_estadual',
            'reformaaliquotaibsestadual',
          ]),
        ),
        reformaAliquotaIbsMunicipal: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotaibsmunicipal',
            'aliquota_ibs_municipal',
            'reformaaliquotaibsmunicipal',
          ]),
        ),
        reformaPercentualReducaoIbs: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'percentualreducaoibs',
            'percentual_reducao_ibs',
            'reformapercentualreducaoibs',
          ]),
        ),
        reformaAliquotaReferenciaCbs: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotareferenciacbs',
            'aliquota_referencia_cbs',
            'reformaaliquotareferenciacbs',
          ]),
        ),
        reformaPercentualReducaoCbs: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'percentualreducaocbs',
            'percentual_reducao_cbs',
            'reformapercentualreducaocbs',
          ]),
        ),
        reformaAliquotaReferenciaIs: TabularSpreadsheetService.parseDecimal(
          _readTaxCell(row, const <String>[
            'aliquotareferenciais',
            'aliquota_referencia_is',
            'reformaaliquotareferenciais',
          ]),
        ),
        priority: priority,
        validFrom: toUtcStartOfDay(
          TabularSpreadsheetService.parseDate(
            _readTaxCell(row, const <String>['validfrom', 'vigenciainicial']),
          ),
        ),
        validUntil: toUtcEndOfDay(
          TabularSpreadsheetService.parseDate(
            _readTaxCell(row, const <String>['validuntil', 'vigenciafinal']),
          ),
        ),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      final previousFingerprint =
          existing == null ? null : taxRuleFingerprint(existing);
      if (previousFingerprint != null) {
        existingFingerprints.remove(previousFingerprint);
      }
      final nextFingerprint = taxRuleFingerprint(entity);
      if (existingFingerprints.contains(nextFingerprint)) {
        skipped++;
        skippedNoChange++;
        if (previousFingerprint != null) {
          existingFingerprints.add(previousFingerprint);
        }
        continue;
      }

      if (previousFingerprint == nextFingerprint) {
        skipped++;
        skippedNoChange++;
        existingFingerprints.add(nextFingerprint);
        continue;
      }

      await repository.save(entity);
      imported++;
      existingById[id] = entity;
      existingFingerprints.add(nextFingerprint);
    }

    return TaxRuleImportResult(
      imported: imported,
      skipped: skipped,
      skippedNoChange: skippedNoChange,
    );
  }

  static String? _parseStTypeForImport(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'mva') {
      return 'mva';
    }
    if (normalized == 'pmc') {
      return 'pmc';
    }
    return null;
  }

  static String _readTaxCell(Map<String, String> row, List<String> aliases) {
    for (final alias in aliases) {
      final key = TabularSpreadsheetService.normalizeHeader(alias);
      final value = row[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _normalizeTaxStatus(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'inactive' ||
        normalized == 'inativo' ||
        normalized == 'desativado') {
      return 'inactive';
    }
    return 'active';
  }

  static String _buyerTaxRegimeLabelForExport(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return '';
    }
    return taxRegimeLabel(normalized);
  }

  /// Retorna `(valor normalizado, valido)`. Vazio e sempre valido (sem restricao).
  static (String?, bool) _normalizeBuyerTaxRegimeForImport(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return (null, true);
    }
    if (isValidTaxRegimeValue(normalized)) {
      return (normalizeTaxRegimeValue(normalized), true);
    }
    if (normalized.contains('simples')) {
      return ('simples_nacional', true);
    }
    if (normalized.contains('presumido')) {
      return ('lucro_presumido', true);
    }
    if (normalized.contains('real')) {
      return ('lucro_real', true);
    }
    return (null, false);
  }

  static bool _parseSimNaoForImport(String raw) {
    final normalized = raw.trim().toLowerCase();
    return normalized == 'sim' ||
        normalized == 's' ||
        normalized == 'yes' ||
        normalized == 'true' ||
        normalized == '1';
  }

  static String _normalizeUfOrigem(String raw, {String? fallback}) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) {
      final fallbackValue = (fallback ?? '').trim().toUpperCase();
      return fallbackValue.isEmpty ? 'ANY' : fallbackValue;
    }

    if (normalized == 'ANY' ||
        normalized == 'TODOS' ||
        normalized == 'TODAS') {
      return 'ANY';
    }

    if (isBrazilState(normalized)) {
      return normalized;
    }

    return 'ANY';
  }
}
