import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/models/pedido.dart';
import 'pedido_format_utils.dart';

class PedidoPdfHeaderContext {
  const PedidoPdfHeaderContext({
    required this.contractingCompanyName,
    this.represented,
    required this.customer,
    required this.sellerName,
    this.userLogoDataUrl,
    this.transportadora,
    this.observacoes,
  });

  final String contractingCompanyName;
  final PedidoPdfRepresentedData? represented;
  final PedidoPdfCustomerData customer;
  final String sellerName;
  final String? userLogoDataUrl;
  final String? transportadora;
  final String? observacoes;
}

class PedidoPdfRepresentedData {
  const PedidoPdfRepresentedData({required this.name, this.phone, this.email});

  final String name;
  final String? phone;
  final String? email;
}

class PedidoPdfCustomerData {
  const PedidoPdfCustomerData({
    this.cliente,
    this.nomeFantasia,
    this.cnpj,
    this.ie,
    this.endereco,
    this.bairro,
    this.cep,
    this.cidade,
    this.estado,
    this.telefone,
    this.email,
  });

  final String? cliente;
  final String? nomeFantasia;
  final String? cnpj;
  final String? ie;
  final String? endereco;
  final String? bairro;
  final String? cep;
  final String? cidade;
  final String? estado;
  final String? telefone;
  final String? email;
}

class PedidoPdfService {
  const PedidoPdfService();

  Future<void> openOrderPdfWithDefaultApp({
    required Pedido pedido,
    required PedidoPdfHeaderContext headerContext,
  }) async {
    final file = await saveOrderPdfToTempFile(
      pedido: pedido,
      headerContext: headerContext,
    );
    await openPdfFile(file);
  }

  Future<void> openPdfFile(File file) async {
    final openResult = await OpenFilex.open(file.path, type: 'application/pdf');

    if (openResult.type != ResultType.done) {
      final message = openResult.message.trim();
      throw StateError(
        message.isEmpty
            ? 'Nao foi possivel abrir o PDF no aplicativo padrao do dispositivo.'
            : message,
      );
    }
  }

  Future<File> saveOrderPdfToTempFile({
    required Pedido pedido,
    required PedidoPdfHeaderContext headerContext,
  }) async {
    final bytes = await buildPdfBytes(
      pedido: pedido,
      headerContext: headerContext,
    );
    final tempDirectory = await getTemporaryDirectory();
    final file = File('${tempDirectory.path}/${_buildFileName(pedido)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> savePdfFileToDevice({
    required File sourceFile,
    required Pedido pedido,
  }) async {
    final directory =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final outputDirectory = Directory('${directory.path}/pedidos_pdf');
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final outputFile = File('${outputDirectory.path}/${_buildFileName(pedido)}');
    await outputFile.writeAsBytes(await sourceFile.readAsBytes(), flush: true);
    return outputFile;
  }

  Future<File> savePdfFileToDirectory({
    required File sourceFile,
    required Pedido pedido,
    required String targetDirectoryPath,
  }) async {
    final normalizedTargetDirectoryPath = targetDirectoryPath.trim();
    if (normalizedTargetDirectoryPath.isEmpty) {
      throw StateError('Pasta de destino invalida para salvar o PDF.');
    }

    final outputDirectory = Directory(normalizedTargetDirectoryPath);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final outputFile = File('${outputDirectory.path}/${_buildFileName(pedido)}');
    await outputFile.writeAsBytes(await sourceFile.readAsBytes(), flush: true);
    return outputFile;
  }

  Future<Uint8List> buildPdfBytes({
    required Pedido pedido,
    required PedidoPdfHeaderContext headerContext,
  }) async {
    final pdf = pw.Document();
    final generatedAt = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          final represented = headerContext.represented;
          return [
            _buildSectionContainer(
              child: _buildLetterheadHeader(
                pedido: pedido,
                headerContext: headerContext,
              ),
            ),
            if (represented != null) pw.SizedBox(height: 10),
            if (represented != null)
              _buildSectionContainer(
                title: 'Representada',
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSingleInfoRow(
                      label: 'Representada',
                      value: _safe(represented.name, '-'),
                    ),
                    pw.SizedBox(height: 4),
                    _buildTwoColumnInfoRow(
                      leftLabel: 'Telefone',
                      leftValue: _safe(represented.phone, '-'),
                      rightLabel: 'E-mail',
                      rightValue: _safe(represented.email, '-'),
                    ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
            _buildSectionContainer(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildTwoColumnInfoRow(
                    leftLabel: 'Cliente',
                    leftValue: _safe(headerContext.customer.cliente, '-'),
                    rightLabel: 'Nome fantasia',
                    rightValue: _safe(headerContext.customer.nomeFantasia, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildTwoColumnInfoRow(
                    leftLabel: 'CNPJ',
                    leftValue: _safe(headerContext.customer.cnpj, '-'),
                    rightLabel: 'IE',
                    rightValue: _safe(headerContext.customer.ie, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildSingleInfoRow(
                    label: 'Endereco',
                    value: _safe(headerContext.customer.endereco, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildTwoColumnInfoRow(
                    leftLabel: 'Bairro',
                    leftValue: _safe(headerContext.customer.bairro, '-'),
                    rightLabel: 'CEP',
                    rightValue: _safe(headerContext.customer.cep, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildTwoColumnInfoRow(
                    leftLabel: 'Cidade',
                    leftValue: _safe(headerContext.customer.cidade, '-'),
                    rightLabel: 'Estado',
                    rightValue: _safe(headerContext.customer.estado, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildTwoColumnInfoRow(
                    leftLabel: 'Telefone',
                    leftValue: _safe(headerContext.customer.telefone, '-'),
                    rightLabel: 'Email',
                    rightValue: _safe(headerContext.customer.email, '-'),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Itens',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (pedido.itens.isEmpty)
              pw.Text('Nenhum item informado.')
            else
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                columnWidths: const <int, pw.TableColumnWidth>{
                  0: pw.FixedColumnWidth(24),
                  1: pw.FixedColumnWidth(72),
                  2: pw.FlexColumnWidth(3.6),
                  3: pw.FixedColumnWidth(36),
                  4: pw.FlexColumnWidth(1.4),
                  5: pw.FlexColumnWidth(1.4),
                  6: pw.FlexColumnWidth(1.7),
                  7: pw.FlexColumnWidth(1.7),
                },
                cellAlignments: const <int, pw.Alignment>{
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: const <String>[
                  '#',
                  'Codigo',
                  'Descricao produto',
                  'Qtde.',
                  'Preco liquido',
                  'IPI',
                  'ICMS-ST',
                  'Subtotal',
                ],
                data: pedido.itens
                    .asMap()
                    .entries
                    .map(
                      (entry) => <String>[
                        '${entry.key + 1}',
                        entry.value.productCode.trim().isEmpty
                            ? '-'
                            : entry.value.productCode,
                        entry.value.productName.trim().isEmpty
                            ? '-'
                            : entry.value.productName,
                        _formatItemQuantity(entry.value.quantity),
                        'R\$ ${PedidoFormatUtils.formatMoneyBr(entry.value.unitPrice)}',
                        _formatTaxValueWithPercent(
                          value: entry.value.taxSnapshot?.valorIpi,
                          percent: entry.value.taxSnapshot?.aliquotaIpiPercent,
                        ),
                        _formatTaxValueWithPercent(
                          value: entry.value.taxSnapshot?.valorSt,
                          percent:
                              entry.value.taxSnapshot?.aliquotaDestinoPercent,
                        ),
                        'R\$ ${PedidoFormatUtils.formatMoneyBr(_resolveItemSubtotal(entry.value))}',
                      ],
                    )
                    .toList(growable: false),
              ),
            pw.SizedBox(height: 8),
            _buildSectionContainer(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildTotalSummaryColumn(
                    label: 'Quantidade total de itens',
                    value: _formatTotalItensAsInteger(pedido.totalItens),
                  ),
                  pw.SizedBox(width: 8),
                  _buildTotalSummaryColumn(
                    label: 'Total liquido',
                    value:
                        'R\$ ${PedidoFormatUtils.formatMoneyBr(_resolveTotalLiquidoSemImpostos(pedido))}',
                  ),
                  pw.SizedBox(width: 8),
                  _buildTotalSummaryColumn(
                    label: 'Total bruto',
                    value:
                        'R\$ ${PedidoFormatUtils.formatMoneyBr(pedido.totalBruto)}',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildTwoColumnInfoRow(
                    leftLabel: 'Condicao de pagamento',
                    leftValue: _safe(pedido.formaPagamento, '-'),
                    rightLabel: 'Data de emissao',
                    rightValue: _formatDateTime(generatedAt),
                  ),
                  pw.SizedBox(height: 4),
                  _buildSingleInfoRow(
                    label: 'Vendedor',
                    value: _safe(headerContext.sellerName, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildSingleInfoRow(
                    label: 'Transportadora',
                    value: _safe(headerContext.transportadora, '-'),
                  ),
                  pw.SizedBox(height: 4),
                  _buildSingleInfoRow(
                    label: 'Observacoes',
                    value: _safe(headerContext.observacoes, '-'),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildSectionContainer({String? title, required pw.Widget child}) {
    final normalizedTitle = (title ?? '').trim();
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (normalizedTitle.isNotEmpty)
            pw.Text(
              normalizedTitle,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          if (normalizedTitle.isNotEmpty) pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  pw.Widget _buildLetterheadHeader({
    required Pedido pedido,
    required PedidoPdfHeaderContext headerContext,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Pedido ${PedidoFormatUtils.pedidoDisplayNumber(pedido.id)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                _safe(headerContext.contractingCompanyName, '-'),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        _buildLetterheadLogo(headerContext.userLogoDataUrl),
      ],
    );
  }

  pw.Widget _buildLetterheadLogo(String? userLogoDataUrl) {
    final logoBytes = _decodeLogoBytes(userLogoDataUrl);
    final logoImage = logoBytes == null
        ? null
        : pw.MemoryImage(Uint8List.fromList(logoBytes));

    return pw.Container(
      width: 128,
      height: 56,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
      ),
      child: logoImage != null
          ? pw.Image(logoImage, fit: pw.BoxFit.contain)
          : pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'SMART SFA',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Proposta comercial',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
    );
  }

  Uint8List? _decodeLogoBytes(String? rawValue) {
    final value = (rawValue ?? '').trim();
    if (value.isEmpty) {
      return null;
    }

    try {
      final base64Part = value.startsWith('data:image')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      final bytes = base64Decode(base64Part);
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  pw.Widget _buildSingleInfoRow({
    required String label,
    required String value,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 76,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    );
  }

  pw.Widget _buildTwoColumnInfoRow({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _buildSingleInfoRow(label: leftLabel, value: leftValue),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildSingleInfoRow(label: rightLabel, value: rightValue),
        ),
      ],
    );
  }

  pw.Widget _buildTotalSummaryColumn({
    required String label,
    required String value,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              label,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFileName(Pedido pedido) {
    final customerName = _normalizeFileSegment(
      _safe(pedido.clienteReferencia?.nomeSnapshot, 'cliente'),
      fallback: 'cliente',
    );
    final orderNumber = _normalizeFileSegment(
      PedidoFormatUtils.pedidoDisplayNumber(pedido.id),
      fallback: 'pedido',
    );
    final now = DateTime.now();
    final timestamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '${now.millisecond.toString().padLeft(3, '0')}';
    return '${customerName}_${orderNumber}_$timestamp.pdf';
  }

  String _normalizeFileSegment(String value, {required String fallback}) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  String _formatTaxValueWithPercent({
    required double? value,
    required double? percent,
  }) {
    if (value == null && percent == null) {
      return '-';
    }
    final formattedValue = PedidoFormatUtils.formatMoneyBr(value ?? 0);
    final formattedPercent = percent == null
        ? '-'
        : PedidoFormatUtils.formatPercent(percent);
    return 'R\$ $formattedValue ($formattedPercent)';
  }

  String _formatItemQuantity(double value) {
    final hasFraction = (value % 1).abs() > 0.00001;
    if (hasFraction) {
      return value.toStringAsFixed(2).replaceAll('.', ',');
    }
    return value.toStringAsFixed(0);
  }

  double _resolveItemSubtotal(PedidoItem item) {
    final taxSnapshot = item.taxSnapshot;
    if (taxSnapshot?.valorTotalItem != null) {
      return taxSnapshot!.valorTotalItem!;
    }

    final baseTotal = item.quantity * item.unitPrice;
    final ipi = taxSnapshot?.valorIpi ?? 0;
    final st = taxSnapshot?.valorSt ?? 0;
    return baseTotal + ipi + st;
  }

  double _resolveTotalLiquidoSemImpostos(Pedido pedido) {
    var total = 0.0;
    for (final item in pedido.itens) {
      total += item.unitPrice * item.quantity;
    }
    return PedidoFormatUtils.roundCurrency(total);
  }

  String _formatTotalItensAsInteger(double value) {
    return value.toStringAsFixed(0);
  }

  String _safe(String? value, String fallback) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
