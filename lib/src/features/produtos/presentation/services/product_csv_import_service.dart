import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';

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
  });

  final AppIdentity identity;
  final ProdutoRepository repository;

  ProductImportValidation validateFile(PlatformFile file) {
    final fileName = file.name.trim().toLowerCase();
    if (!fileName.endsWith('.csv')) {
      return const ProductImportValidation(
        ok: false,
        message: 'Somente CSV e suportado neste momento para produtos.',
        rows: [],
      );
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const ProductImportValidation(
        ok: false,
        message: 'Arquivo CSV sem conteudo.',
        rows: [],
      );
    }

    final text = _decodeImportFile(bytes);
    final lines = const LineSplitter()
        .convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);

    if (lines.length < 2) {
      return const ProductImportValidation(
        ok: false,
        message: 'CSV precisa de cabecalho e ao menos uma linha de dados.',
        rows: [],
      );
    }

    final separator = _detectCsvSeparator(lines.first);
    final headers = _splitCsvLine(lines.first, separator)
        .map(_normalizeHeader)
        .toList(growable: false);

    final hasDescricao = headers.contains('descricao') || headers.contains('nome');

    if (!hasDescricao) {
      return const ProductImportValidation(
        ok: false,
        message: 'Cabecalho invalido. Obrigatorio: descricao.',
        rows: [],
      );
    }

    final parsedRows = <Map<String, String>>[];
    for (final line in lines.skip(1)) {
      final values = _splitCsvLine(line, separator);
      if (values.every((item) => item.trim().isEmpty)) {
        continue;
      }

      final row = <String, String>{};
      for (var index = 0; index < headers.length; index++) {
        row[headers[index]] = index < values.length ? values[index].trim() : '';
      }
      parsedRows.add(row);
    }

    if (parsedRows.isEmpty) {
      return const ProductImportValidation(
        ok: false,
        message: 'CSV sem linhas validas para importar.',
        rows: [],
      );
    }

    return ProductImportValidation(
      ok: true,
      message: 'CSV valido com ${parsedRows.length} linha(s) para importacao.',
      rows: parsedRows,
    );
  }

  Future<int> importRows(List<Map<String, String>> rows) async {
    var imported = 0;
    for (final row in rows) {
      final now = DateTime.now().toUtc();
      final descricao = _readRowValue(row, const ['descricao', 'nome']);
      if (descricao.isEmpty) {
        continue;
      }

      final status = ProductStatus.fromValue(
        _readRowValue(row, const ['status']),
      );
      final produto = Produto(
        id: 'prd_${now.microsecondsSinceEpoch}_$imported',
        tenantId: identity.tenantId,
        codigoInterno: 'AUTO',
        descricao: descricao,
        origemCadastro: ProductSource.excel,
        status: status,
        descricaoResumida: _readRowValue(row, const ['descricaoresumida', 'descricao_resumida']),
        descricaoLonga: _readRowValue(row, const ['descricaolonga', 'descricao_longa']),
        codigoFabricante: _readRowValue(row, const ['codigofabricante', 'codigo_fabricante']),
        sku: _readRowValue(row, const ['sku', 'skucomercial', 'sku_comercial']),
        ean: _readRowValue(row, const ['ean', 'gtin']),
        marca: _readRowValue(row, const ['marca']),
        categoria: _readRowValue(row, const ['categoria']),
        subcategoria: _readRowValue(row, const ['subcategoria', 'sub_categoria']),
        bitola: _readRowValue(row, const ['bitola', 'medida']),
        bitolaUnidade: _readRowValue(row, const ['bitolaunidade', 'bitola_unidade', 'unidadebitola', 'unidade_bitola']),
        unidade: _readRowValue(row, const ['unidade']),
        multiploVenda: _readDoubleFromRow(row, const ['multiplovenda', 'multiplo_venda']),
        quantidadeMinima: _readDoubleFromRow(row, const ['quantidademinima', 'quantidade_minima']),
        ncm: _readRowValue(row, const ['ncm']),
        cfop: _readRowValue(row, const ['cfop']),
        aliquotaIcms: _readDoubleFromRow(row, const ['aliquotaicms', 'aliquota_icms']),
        aliquotaPis: _readDoubleFromRow(row, const ['aliquotapis', 'aliquota_pis']),
        aliquotaCofins: _readDoubleFromRow(row, const ['aliquotacofins', 'aliquota_cofins']),
        pesoKg: _readDoubleFromRow(row, const ['pesokg', 'peso_kg']),
        comprimentoMm: _readDoubleFromRow(row, const ['comprimentomm', 'comprimento_mm']),
        larguraMm: _readDoubleFromRow(row, const ['larguramm', 'largura_mm']),
        alturaMm: _readDoubleFromRow(row, const ['alturamm', 'altura_mm']),
        erpProductId: _readRowValue(row, const ['erpproductid', 'erp_product_id']),
        erpSyncId: _readRowValue(row, const ['erpsyncid', 'erp_sync_id']),
        tabelaPrecoVersao: _readRowValue(row, const ['tabelaprecoversao', 'tabela_preco_versao']),
        estoqueVersao: _readRowValue(row, const ['estoqueversao', 'estoque_versao']),
        createdAt: now,
        updatedAt: now,
      );

      await repository.save(produto);
      imported++;
    }

    return imported;
  }

  String _decodeImportFile(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll(' ', '').replaceAll('-', '_');
  }

  String _detectCsvSeparator(String headerLine) {
    final semicolon = ';'.allMatches(headerLine).length;
    final comma = ','.allMatches(headerLine).length;
    return semicolon > comma ? ';' : ',';
  }

  List<String> _splitCsvLine(String line, String separator) {
    final result = <String>[];
    final separatorCode = separator.codeUnitAt(0);
    final buffer = StringBuffer();
    var insideQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final charCode = line.codeUnitAt(i);
      final char = line[i];

      if (char == '"') {
        if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
          continue;
        }
        insideQuotes = !insideQuotes;
        continue;
      }

      if (!insideQuotes && charCode == separatorCode) {
        result.add(buffer.toString());
        buffer.clear();
        continue;
      }

      buffer.writeCharCode(charCode);
    }

    result.add(buffer.toString());
    return result;
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
    return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(value.replaceAll(',', '.'));
  }
}
