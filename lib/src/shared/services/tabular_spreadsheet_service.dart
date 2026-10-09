import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class TabularSpreadsheetResult {
  const TabularSpreadsheetResult({
    required this.ok,
    required this.message,
    required this.rows,
    required this.headers,
  });

  final bool ok;
  final String message;
  final List<Map<String, String>> rows;
  final List<String> headers;
}

class TabularSpreadsheetSheet {
  const TabularSpreadsheetSheet({
    required this.sheetName,
    required this.headers,
    required this.rows,
  });

  final String sheetName;
  final List<String> headers;
  final List<List<String>> rows;
}

class TabularSpreadsheetService {
  const TabularSpreadsheetService._();

  static Uint8List buildXlsx({
    required String sheetName,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet() ?? 'Sheet1';
    if (defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }
    final sheet = workbook[sheetName];
    sheet.appendRow(headers.map((item) => TextCellValue(item)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map((item) => TextCellValue(item)).toList());
    }

    final encoded = workbook.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Nao foi possivel gerar a planilha XLSX.');
    }
    return Uint8List.fromList(encoded);
  }

  static Uint8List buildXlsxWithSheets({
    required List<TabularSpreadsheetSheet> sheets,
  }) {
    if (sheets.isEmpty) {
      throw StateError('Ao menos uma aba deve ser informada para gerar XLSX.');
    }

    final workbook = Excel.createExcel();
    final firstSheet = sheets.first;
    final defaultSheet = workbook.getDefaultSheet() ?? 'Sheet1';
    if (defaultSheet != firstSheet.sheetName) {
      workbook.rename(defaultSheet, firstSheet.sheetName);
    }

    for (final sheet in sheets) {
      final worksheet = workbook[sheet.sheetName];
      worksheet.appendRow(
        sheet.headers.map((item) => TextCellValue(item)).toList(),
      );
      for (final row in sheet.rows) {
        worksheet.appendRow(row.map((item) => TextCellValue(item)).toList());
      }
    }

    final encoded = workbook.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Nao foi possivel gerar a planilha XLSX.');
    }
    return Uint8List.fromList(encoded);
  }

  static TabularSpreadsheetResult parseFile(PlatformFile file) {
    final lowerName = file.name.trim().toLowerCase();
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const TabularSpreadsheetResult(
        ok: false,
        message: 'Arquivo sem conteudo.',
        rows: <Map<String, String>>[],
        headers: <String>[],
      );
    }

    if (lowerName.endsWith('.csv')) {
      return _parseCsv(bytes);
    }
    if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
      return _parseXlsx(bytes);
    }

    return const TabularSpreadsheetResult(
      ok: false,
      message: 'Formato invalido. Use CSV, XLS ou XLSX.',
      rows: <Map<String, String>>[],
      headers: <String>[],
    );
  }

  static TabularSpreadsheetResult _parseCsv(Uint8List bytes) {
    final text = _decodeText(bytes);
    final lines = const LineSplitter()
        .convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);

    if (lines.length < 2) {
      return const TabularSpreadsheetResult(
        ok: false,
        message: 'CSV precisa de cabecalho e ao menos uma linha de dados.',
        rows: <Map<String, String>>[],
        headers: <String>[],
      );
    }

    final separator = _detectCsvSeparator(lines.first);
    final originalHeaders = _splitCsvLine(lines.first, separator)
        .map((value) => value.trim())
        .toList(growable: false);
    final normalizedHeaders = originalHeaders
        .map(normalizeHeader)
        .toList(growable: false);

    final rows = <Map<String, String>>[];
    for (final line in lines.skip(1)) {
      final values = _splitCsvLine(line, separator);
      if (values.every((value) => value.trim().isEmpty)) {
        continue;
      }

      final row = <String, String>{};
      for (var index = 0; index < normalizedHeaders.length; index++) {
        final key = normalizedHeaders[index];
        row[key] = index < values.length ? values[index].trim() : '';
      }
      rows.add(row);
    }

    if (rows.isEmpty) {
      return TabularSpreadsheetResult(
        ok: false,
        message: 'Planilha sem linhas validas para importar.',
        rows: rows,
        headers: normalizedHeaders,
      );
    }

    return TabularSpreadsheetResult(
      ok: true,
      message: 'Arquivo valido com ${rows.length} linha(s).',
      rows: rows,
      headers: normalizedHeaders,
    );
  }

  static TabularSpreadsheetResult _parseXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return const TabularSpreadsheetResult(
        ok: false,
        message: 'Planilha XLSX sem abas.',
        rows: <Map<String, String>>[],
        headers: <String>[],
      );
    }

    final firstTable = workbook.tables.values.first;
    if (firstTable.rows.length < 2) {
      return const TabularSpreadsheetResult(
        ok: false,
        message: 'XLSX precisa de cabecalho e ao menos uma linha de dados.',
        rows: <Map<String, String>>[],
        headers: <String>[],
      );
    }

    final headerRow = firstTable.rows.first;
    final originalHeaders = headerRow
        .map(_cellAsString)
        .map((value) => value.trim())
        .toList(growable: false);
    final normalizedHeaders = originalHeaders
        .map(normalizeHeader)
        .toList(growable: false);

    final rows = <Map<String, String>>[];
    for (final excelRow in firstTable.rows.skip(1)) {
      final rowValues = excelRow.map(_cellAsString).toList(growable: false);
      if (rowValues.every((value) => value.trim().isEmpty)) {
        continue;
      }

      final row = <String, String>{};
      for (var index = 0; index < normalizedHeaders.length; index++) {
        row[normalizedHeaders[index]] =
            index < rowValues.length ? rowValues[index].trim() : '';
      }
      rows.add(row);
    }

    if (rows.isEmpty) {
      return TabularSpreadsheetResult(
        ok: false,
        message: 'Planilha sem linhas validas para importar.',
        rows: rows,
        headers: normalizedHeaders,
      );
    }

    return TabularSpreadsheetResult(
      ok: true,
      message: 'Arquivo valido com ${rows.length} linha(s).',
      rows: rows,
      headers: normalizedHeaders,
    );
  }

  static String normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '_');
  }

  static double? parseDecimal(String raw) {
    var normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    normalized = normalized.replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (normalized.contains(',')) {
      normalized = normalized.replaceAll(',', '.');
    }
    return double.tryParse(normalized);
  }

  static DateTime? parseDate(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final direct = DateTime.tryParse(normalized);
    if (direct != null) {
      return direct;
    }

    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(
      normalized,
    );
    if (match == null) {
      return null;
    }

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) {
      return null;
    }

    return DateTime(year, month, day);
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _detectCsvSeparator(String line) {
    final semicolon = ';'.allMatches(line).length;
    final comma = ','.allMatches(line).length;
    return semicolon > comma ? ';' : ',';
  }

  static List<String> _splitCsvLine(String line, String separator) {
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

  static String _cellAsString(Data? cell) {
    final cellValue = cell?.value;
    if (cellValue == null) {
      return '';
    }

    try {
      final dynamic valueAsDynamic = cellValue;
      final dynamic inner = valueAsDynamic.value;
      if (inner != null) {
        return inner.toString();
      }
    } catch (_) {
      // Falls back to toString below.
    }

    return cellValue.toString();
  }
}