import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../../../../shared/services/tabular_spreadsheet_service.dart';

class ProductImportValidation {
  const ProductImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
}

class ProductCsvImportService {
  const ProductCsvImportService({
    required this.identity,
    required this.repository,
    this.representedCompanyId,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;
  final String? representedCompanyId;

  static const List<String> templateHeaders = <String>[
    'codigoInterno',
    'nome',
    'status',
    'descricaoLonga',
    'codigoProduto',
    'ean',
    'marca',
    'categoria',
    'subcategoria',
    'unidadePadrao',
    'vendaEmMultiplosDe',
    'moeda',
    'precoTabela',
    'precoMinimo',
    'bitola',
    'unidadeMedida',
    'quantidadeMinima',
    'ncm',
    'cest',
    'origemMercadoriaCst',
    'aliquotaIpiBase',
    'pesoKg',
    'comprimentoMm',
    'larguraMm',
    'alturaMm',
  ];

  Uint8List buildTemplateBytes() {
    return TabularSpreadsheetService.buildXlsxWithSheets(
      sheets: <TabularSpreadsheetSheet>[
        TabularSpreadsheetSheet(
          sheetName: 'Produtos',
          headers: templateHeaders,
          rows: const <List<String>>[
            <String>[
              '',
              'Produto exemplo',
              'ativo',
              'Descricao detalhada do produto',
              'COD-001',
              '7890000000001',
              'Marca X',
              'Ferramentas',
              'Brocas',
              'UN',
              '1',
              'BRL',
              '10.90',
              '9.50',
              '10',
              'mm',
              '1',
              '0000.00.00',
              '00.000.00',
              '0',
              '0',
              '0.15',
              '100',
              '50',
              '20',
            ],
          ],
        ),
        const TabularSpreadsheetSheet(
          sheetName: 'Instrucoes',
          headers: <String>['Coluna', 'Obrigatorio', 'Observacao'],
          rows: <List<String>>[
            <String>[
              'codigoInterno',
              'Nao',
              'Se vazio, o sistema gera automaticamente. Se preenchido e existir, o produto e atualizado por este codigo.',
            ],
            <String>[
              'nome',
              'Sim',
              'Nome do produto (equivalente ao campo Nome na UI).',
            ],
            <String>[
              'status',
              'Nao',
              'Use: ativo, inativo, substituido ou descontinuado. Vazio assume ativo.',
            ],
            <String>['descricaoLonga', 'Nao', 'Descricao detalhada.'],
            <String>[
              'codigoProduto',
              'Nao',
              'Equivale ao campo Codigo da UI (armazenado internamente como codigoFabricante).',
            ],
            <String>['ean', 'Nao', 'EAN/GTIN.'],
            <String>[
              'marca',
              'Nao',
              'Texto livre (preferencialmente uma marca ja usada no sistema).',
            ],
            <String>[
              'categoria',
              'Nao',
              'Se informada, a categoria deve existir previamente no cadastro de Categorias do sistema.',
            ],
            <String>[
              'subcategoria',
              'Nao',
              'Se informada, a subcategoria deve existir para a categoria escolhida.',
            ],
            <String>[
              'unidadePadrao',
              'Nao',
              'Unidade padrao de venda (ex.: UN).',
            ],
            <String>[
              'vendaEmMultiplosDe',
              'Nao',
              'Numero decimal. Ex.: 1, 2, 5.',
            ],
            <String>['moeda', 'Nao', 'Codigo da moeda (ex.: BRL).'],
            <String>[
              'precoTabela',
              'Sim',
              'Preco de tabela/base. Numero decimal (aceita virgula).',
            ],
            <String>[
              'precoMinimo',
              'Nao',
              'Preco minimo. Numero decimal (aceita virgula).',
            ],
            <String>['bitola', 'Nao', 'Valor da medida/bitola.'],
            <String>[
              'unidadeMedida',
              'Nao',
              'Unidade da bitola (ex.: mm, cm, pol).',
            ],
            <String>[
              'quantidadeMinima',
              'Nao',
              'Quantidade minima. Numero decimal (aceita virgula).',
            ],
            <String>['ncm', 'Nao', 'Formato recomendado: 0000.00.00.'],
            <String>['cest', 'Nao', 'Formato recomendado: 00.000.00.'],
            <String>[
              'origemMercadoriaCst',
              'Nao',
              'Origem da mercadoria no padrão CST (0 a 8).',
            ],
            <String>[
              'aliquotaIpiBase',
              'Nao',
              'Aliquota de IPI base. Numero decimal.',
            ],
            <String>['pesoKg', 'Nao', 'Peso em kg. Numero decimal.'],
            <String>[
              'comprimentoMm',
              'Nao',
              'Comprimento em mm. Numero decimal.',
            ],
            <String>['larguraMm', 'Nao', 'Largura em mm. Numero decimal.'],
            <String>['alturaMm', 'Nao', 'Altura em mm. Numero decimal.'],
          ],
        ),
      ],
    );
  }

  ProductImportValidation validateFile(PlatformFile file) {
    final parsed = TabularSpreadsheetService.parseFile(file);
    if (!parsed.ok) {
      return ProductImportValidation(
        ok: false,
        message: parsed.message,
        rows: const <Map<String, String>>[],
      );
    }

    final headers = parsed.headers;
    final hasDescricao =
        headers.contains('descricao') || headers.contains('nome');
    if (!hasDescricao) {
      return const ProductImportValidation(
        ok: false,
        message: 'Cabecalho invalido. Obrigatorio: nome.',
        rows: <Map<String, String>>[],
      );
    }

    final hasPrecoTabela =
        headers.contains('precotabela') ||
        headers.contains('preco_tabela') ||
        headers.contains('valorbruto') ||
        headers.contains('valor_bruto') ||
        headers.contains('preco');
    if (!hasPrecoTabela) {
      return const ProductImportValidation(
        ok: false,
        message: 'Cabecalho invalido. Obrigatorio: precoTabela.',
        rows: <Map<String, String>>[],
      );
    }

    if (parsed.rows.isEmpty) {
      return const ProductImportValidation(
        ok: false,
        message: 'Planilha sem linhas validas para importacao.',
        rows: <Map<String, String>>[],
      );
    }

    final invalidPriceLines = <int>[];
    for (var index = 0; index < parsed.rows.length; index++) {
      final row = parsed.rows[index];
      final hasAnyValue = row.values.any((value) => value.trim().isNotEmpty);
      if (!hasAnyValue) {
        continue;
      }

      final hasPrice =
          _readDoubleFromRow(row, const <String>[
            'precotabela',
            'preco_tabela',
            'valorbruto',
            'valor_bruto',
            'preco',
          ]) !=
          null;

      if (!hasPrice) {
        invalidPriceLines.add(index + 2);
      }
    }

    if (invalidPriceLines.isNotEmpty) {
      final sample = invalidPriceLines.take(10).join(', ');
      return ProductImportValidation(
        ok: false,
        message:
            'Preco de tabela e obrigatorio. Linhas sem valor: $sample${invalidPriceLines.length > 10 ? ' ...' : ''}.',
        rows: const <Map<String, String>>[],
      );
    }

    return ProductImportValidation(
      ok: true,
      message: 'Arquivo valido com ${parsed.rows.length} linha(s).',
      rows: parsed.rows,
    );
  }

  Future<int> importRows(List<Map<String, String>> rows) async {
    final selectedRepresentedCompanyId = (representedCompanyId ?? '').trim();
    final existingProducts = await repository.fetchAll(
      tenantId: identity.tenantId,
    );
    final existingByCode = <String, Produto>{};
    for (final product in existingProducts) {
      final productScope = (product.representedCompanyId ?? '').trim();
      if (productScope != selectedRepresentedCompanyId) {
        continue;
      }
      final normalizedCode = product.codigoInterno.trim().toLowerCase();
      if (normalizedCode.isEmpty) {
        continue;
      }
      existingByCode[normalizedCode] = product;
    }

    var imported = 0;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final now = DateTime.now().toUtc();

      final rawCode = _readRowValue(row, const <String>[
        'codigointerno',
        'codigo_interno',
        'idinterno',
      ]);
      final normalizedCode = rawCode.trim().toLowerCase();
      final existing = normalizedCode.isEmpty
          ? null
          : existingByCode[normalizedCode];

      final descricao = _readRowValue(row, const <String>['descricao', 'nome']);
      final effectiveDescricao = descricao.isEmpty
          ? (existing?.descricao ?? '')
          : descricao;
      if (effectiveDescricao.isEmpty) {
        continue;
      }

      final status = _parseStatus(
        _readRowValue(row, const <String>['status']),
        fallback: existing?.status ?? ProductStatus.active,
      );

      final effectiveCode = rawCode.trim().isNotEmpty
          ? rawCode.trim()
          : ((existing?.codigoInterno.trim().isNotEmpty ?? false)
                ? existing!.codigoInterno.trim()
                : 'AUTO_${now.microsecondsSinceEpoch}_$index');

      final produto = Produto(
        id: existing?.id ?? 'prd_${now.microsecondsSinceEpoch}_$index',
        tenantId: identity.tenantId,
        representedCompanyId: selectedRepresentedCompanyId,
        codigoInterno: effectiveCode,
        descricao: effectiveDescricao,
        origemCadastro: ProductSource.excel,
        status: status,
        descricaoResumida: _pickString(row, const <String>[
          'descricaoresumida',
          'descricao_resumida',
        ], existing?.descricaoResumida),
        descricaoLonga: _pickString(row, const <String>[
          'descricaolonga',
          'descricao_longa',
        ], existing?.descricaoLonga),
        codigoFabricante: _pickString(row, const <String>[
          'codigoproduto',
          'codigo_produto',
          'codigofabricante',
          'codigo_fabricante',
        ], existing?.codigoFabricante),
        sku: _pickString(row, const <String>[
          'sku',
          'skucomercial',
          'sku_comercial',
        ], existing?.sku),
        ean: _pickString(row, const <String>['ean', 'gtin'], existing?.ean),
        marca: _pickString(row, const <String>['marca'], existing?.marca),
        categoria: _pickString(row, const <String>[
          'categoria',
        ], existing?.categoria),
        subcategoria: _pickString(row, const <String>[
          'subcategoria',
          'sub_categoria',
        ], existing?.subcategoria),
        colecao: _pickString(row, const <String>['colecao'], existing?.colecao),
        bitola: _pickString(row, const <String>[
          'bitola',
          'medida',
        ], existing?.bitola),
        bitolaUnidade: _pickString(row, const <String>[
          'unidadedemedida',
          'unidade_medida',
          'bitolaunidade',
          'bitola_unidade',
          'unidadebitola',
          'unidade_bitola',
        ], existing?.bitolaUnidade),
        unidade: _pickString(row, const <String>['unidade'], existing?.unidade),
        moeda: _pickString(row, const <String>['moeda'], existing?.moeda),
        multiploVenda: _pickDouble(row, const <String>[
          'vendaemmultiplosde',
          'venda_em_multiplos_de',
          'multiplovenda',
          'multiplo_venda',
        ], existing?.multiploVenda),
        quantidadeMinima: _pickDouble(row, const <String>[
          'quantidademinima',
          'quantidade_minima',
        ], existing?.quantidadeMinima),
        ncm: _pickString(row, const <String>['ncm'], existing?.ncm),
        cest: _pickString(row, const <String>['cest'], existing?.cest),
        origemMercadoriaCst: _pickOrigemMercadoriaCst(
          row,
          existing?.origemMercadoriaCst,
        ),
        aliquotaIpiBase: _pickDouble(row, const <String>[
          'aliquotaipibase',
          'aliquota_ipi_base',
          'aliquotaipi',
          'aliquota_ipi',
          'ipi',
        ], existing?.aliquotaIpiBase),
        pesoKg: _pickDouble(row, const <String>[
          'pesokg',
          'peso_kg',
        ], existing?.pesoKg),
        comprimentoMm: _pickDouble(row, const <String>[
          'comprimentomm',
          'comprimento_mm',
        ], existing?.comprimentoMm),
        larguraMm: _pickDouble(row, const <String>[
          'larguramm',
          'largura_mm',
        ], existing?.larguraMm),
        alturaMm: _pickDouble(row, const <String>[
          'alturamm',
          'altura_mm',
        ], existing?.alturaMm),
        valorBruto: _readDoubleFromRow(row, const <String>[
          'precotabela',
          'preco_tabela',
          'valorbruto',
          'valor_bruto',
          'preco',
        ]),
        precoMinimo: _pickDouble(row, const <String>[
          'precominimo',
          'preco_minimo',
        ], existing?.precoMinimo),
        percentualComissao: _pickDouble(row, const <String>[
          'percentualcomissao',
          'percentual_comissao',
        ], existing?.percentualComissao),
        erpProductId: _pickString(row, const <String>[
          'erpproductid',
          'erp_product_id',
        ], existing?.erpProductId),
        erpSyncId: _pickString(row, const <String>[
          'erpsyncid',
          'erp_sync_id',
        ], existing?.erpSyncId),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await repository.save(produto);
      existingByCode[effectiveCode.toLowerCase()] = produto;
      imported++;
    }

    return imported;
  }

  ProductStatus _parseStatus(String raw, {required ProductStatus fallback}) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return fallback;
    }

    if (normalized == 'active' || normalized == 'ativo') {
      return ProductStatus.active;
    }
    if (normalized == 'inactive' || normalized == 'inativo') {
      return ProductStatus.inactive;
    }
    if (normalized == 'replaced' || normalized == 'substituido') {
      return ProductStatus.replaced;
    }
    if (normalized == 'discontinued' || normalized == 'descontinuado') {
      return ProductStatus.discontinued;
    }

    for (final candidate in ProductStatus.values) {
      if (candidate.value == normalized ||
          candidate.label.toLowerCase() == normalized) {
        return candidate;
      }
    }

    return fallback;
  }

  String? _pickString(
    Map<String, String> row,
    List<String> aliases,
    String? fallback,
  ) {
    final incoming = _readRowValue(row, aliases).trim();
    if (incoming.isNotEmpty) {
      return incoming;
    }

    final normalizedFallback = (fallback ?? '').trim();
    return normalizedFallback.isEmpty ? null : normalizedFallback;
  }

  double? _pickDouble(
    Map<String, String> row,
    List<String> aliases,
    double? fallback,
  ) {
    final incoming = _readDoubleFromRow(row, aliases);
    return incoming ?? fallback;
  }

  String? _pickOrigemMercadoriaCst(Map<String, String> row, String? fallback) {
    final incoming = _readRowValue(row, const <String>[
      'origemmercadoriacst',
      'origem_mercadoria_cst',
      'origemmercadoria',
      'origem_mercadoria',
      'origemproduto',
      'origem_produto',
      'cstorigem',
      'cst_origem',
      'origprod',
    ]).trim();

    if (incoming.isEmpty) {
      return _normalizeOrigemMercadoriaCstValue(fallback);
    }

    final normalized = _normalizeOrigemMercadoriaCstValue(incoming);
    return normalized ?? _normalizeOrigemMercadoriaCstValue(fallback);
  }

  String? _normalizeOrigemMercadoriaCstValue(Object? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > 8) {
      return null;
    }

    return parsed.toString();
  }

  String _normalizeHeader(String value) {
    return TabularSpreadsheetService.normalizeHeader(value);
  }

  String _readRowValue(Map<String, String> row, List<String> aliases) {
    for (final alias in aliases) {
      final normalizedAlias = _normalizeHeader(alias);
      final value = row[normalizedAlias]?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  double? _readDoubleFromRow(Map<String, String> row, List<String> aliases) {
    final value = _readRowValue(row, aliases);
    if (value.isEmpty) {
      return null;
    }
    return TabularSpreadsheetService.parseDecimal(value);
  }
}

class ProductSpreadsheetImportService extends ProductCsvImportService {
  const ProductSpreadsheetImportService({
    required super.identity,
    required super.repository,
    super.representedCompanyId,
  });
}
