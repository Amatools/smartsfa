import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tabela_preco.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../core/repositories/tabela_preco_repository.dart';

class TabelasPrecoPage extends StatelessWidget {
  const TabelasPrecoPage({
    super.key,
    required this.identity,
    required this.activeTenant,
    required this.repository,
    this.activeRepresentedCompanyName,
  });

  final AppIdentity identity;
  final TenantEntryOption activeTenant;
  final TabelaPrecoRepository repository;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final policy = _PriceTablePolicy.fromContext(
      workspaceType: activeTenant.workspaceType,
      role: identity.role,
    );
    final representedName = activeRepresentedCompanyName?.trim() ?? '';
    final representedLabel = representedName.isEmpty
        ? 'sem representada selecionada'
        : 'representada $representedName';

    return StreamBuilder<List<TabelaPreco>>(
      stream: repository.watchAll(tenantId: identity.tenantId),
      initialData: const [],
      builder: (context, snapshot) {
        final tabelas = snapshot.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tabelas de preco', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Cadastro de tabelas por tenant para $representedLabel.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'As tabelas sao separadas do modulo de produtos, mas podem compartilhar codigo interno e regras por cliente/regiao.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: policy.canManage
                              ? () => _openImportSheet(
                                    context,
                                    identity: identity,
                                    repository: repository,
                                  )
                              : null,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Importar planilha'),
                        ),
                        OutlinedButton.icon(
                          onPressed: policy.canManage
                              ? () => _openCreateTableDialog(
                                    context,
                                    identity: identity,
                                    repository: repository,
                                  )
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Nova tabela'),
                        ),
                      ],
                    ),
                    if (!policy.canManage) ...[
                      const SizedBox(height: 12),
                      const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.info_outline),
                        title: Text('Somente owner/gerente podem alterar tabelas no workspace enterprise.'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (tabelas.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('Nenhuma tabela cadastrada'),
                  subtitle: Text('Use importacao de planilha ou cadastro manual para iniciar.'),
                ),
              )
            else
              ...tabelas.map((tabela) => _PriceTableCard(tabela: tabela)),
          ],
        );
      },
    );
  }
}

class _PriceTablePolicy {
  const _PriceTablePolicy({required this.workspaceType, required this.role});

  final String workspaceType;
  final String role;

  static _PriceTablePolicy fromContext({
    required String workspaceType,
    required String role,
  }) {
    return _PriceTablePolicy(
      workspaceType: workspaceType.trim(),
      role: role.trim().toLowerCase(),
    );
  }

  bool get canManage {
    if (role == 'platform_admin') {
      return true;
    }

    if (workspaceType == 'brand_owner_workspace') {
      return role == 'owner' || role == 'gerente';
    }

    if (workspaceType == 'rep_workspace') {
      return role == 'owner' ||
          role == 'gerente' ||
          role == 'representante' ||
          role == 'vendedor';
    }

    if (workspaceType == 'seller_solo_workspace') {
      return role == 'vendedor';
    }

    return false;
  }
}

class _PriceTableCard extends StatelessWidget {
  const _PriceTableCard({required this.tabela});

  final TabelaPreco tabela;

  @override
  Widget build(BuildContext context) {
    final scopeLabel = tabela.scopeLabel.trim().isEmpty ? 'Sem vinculo' : tabela.scopeLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.price_change_outlined),
          title: Text(tabela.nome),
          subtitle: Text(
            '${_scopeLabel(tabela.scopeType)} · $scopeLabel\n'
            'Origem: ${tabela.origem} · Status: ${tabela.status}'
            '${tabela.rowCount != null ? ' · Itens: ${tabela.rowCount}' : ''}',
          ),
          isThreeLine: true,
          trailing: Text(_formatDate(tabela.updatedAt)),
        ),
      ),
    );
  }
}

Future<void> _openCreateTableDialog(
  BuildContext context, {
  required AppIdentity identity,
  required TabelaPrecoRepository repository,
}) async {
  final nameController = TextEditingController();
  final scopeValueController = TextEditingController();
  var scopeType = 'general';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Informe um nome para a tabela.')),
              );
              return;
            }

            final scopeValue = scopeValueController.text.trim();
            final now = DateTime.now().toUtc();
            final id = 'pt_${now.microsecondsSinceEpoch}';
            final tabela = TabelaPreco(
              id: id,
              tenantId: identity.tenantId,
              nome: name,
              scopeType: scopeType,
              scopeLabel: scopeValue,
              scopeIndex: _buildScopeIndex(scopeType, scopeValue),
              origem: 'manual',
              status: 'ativo',
              linkedEntityId: scopeValue,
              createdAt: now,
              updatedAt: now,
            );

            await repository.save(tabela);
            if (!context.mounted) {
              return;
            }
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tabela criada com sucesso.')),
            );
          }

          return AlertDialog(
            title: const Text('Nova tabela de preco'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da tabela',
                      hintText: 'Ex.: Varejo SP 2026',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: scopeType,
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('Sem vinculo')),
                      DropdownMenuItem(value: 'client', child: Text('Por cliente')),
                      DropdownMenuItem(value: 'region', child: Text('Por regiao')),
                      DropdownMenuItem(value: 'channel', child: Text('Por canal')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        scopeType = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Escopo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: scopeValueController,
                    decoration: InputDecoration(
                      labelText: 'Vinculo (opcional)',
                      hintText: _scopeHint(scopeType),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: save,
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _openImportSheet(
  BuildContext context, {
  required AppIdentity identity,
  required TabelaPrecoRepository repository,
}) async {
  var scopeType = 'general';
  final scopeValueController = TextEditingController();
  PlatformFile? selectedFile;
  _PriceImportValidation? validation;
  var importing = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickFile() async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['xlsx', 'xls', 'csv'],
              allowMultiple: false,
              withData: true,
            );

            final file = result?.files.isNotEmpty == true ? result!.files.first : null;
            if (file == null) {
              return;
            }

            setSheetState(() {
              selectedFile = file;
              validation = null;
            });
          }

          Future<void> validate() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione uma planilha primeiro.')),
              );
              return;
            }

            final report = _validatePriceSheet(file);
            setSheetState(() {
              validation = report;
            });
          }

          Future<void> importFile() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione uma planilha para importar.')),
              );
              return;
            }

            final report = validation ?? _validatePriceSheet(file);
            if (!report.ok) {
              setSheetState(() {
                validation = report;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(report.message)),
              );
              return;
            }

            setSheetState(() {
              importing = true;
            });

            try {
              final now = DateTime.now().toUtc();
              final scopeValue = scopeValueController.text.trim();
              final tabela = TabelaPreco(
                id: 'pt_${now.microsecondsSinceEpoch}',
                tenantId: identity.tenantId,
                nome: _buildImportedName(file.name, scopeType),
                scopeType: scopeType,
                scopeLabel: scopeValue,
                scopeIndex: _buildScopeIndex(scopeType, scopeValue),
                origem: 'excel',
                status: 'ativo',
                linkedEntityId: scopeValue,
                fileName: file.name,
                rowCount: report.rows,
                createdAt: now,
                updatedAt: now,
              );

              await repository.save(tabela);
              if (!context.mounted) {
                return;
              }

              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Tabela importada: ${tabela.nome}.')),
              );
            } finally {
              if (context.mounted) {
                setSheetState(() {
                  importing = false;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Importar tabela de preco',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CSV e validado localmente por cabecalho (codigoInterno, preco). Arquivos XLS/XLSX sao aceitos e registrados para processamento no backend.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: scopeType,
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('Sem vinculo')),
                      DropdownMenuItem(value: 'client', child: Text('Por cliente')),
                      DropdownMenuItem(value: 'region', child: Text('Por regiao')),
                      DropdownMenuItem(value: 'channel', child: Text('Por canal')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setSheetState(() {
                        scopeType = value;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Escopo da tabela'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: scopeValueController,
                    decoration: InputDecoration(
                      labelText: 'Vinculo (opcional)',
                      hintText: _scopeHint(scopeType),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedFile != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(selectedFile!.name),
                      subtitle: Text('${(selectedFile!.size / 1024).toStringAsFixed(1)} KB'),
                    ),
                  if (validation != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        validation!.ok ? Icons.verified_outlined : Icons.error_outline,
                        color: validation!.ok ? Colors.green : Colors.red,
                      ),
                      title: Text(validation!.ok ? 'Validacao concluida' : 'Validacao com erro'),
                      subtitle: Text(validation!.message),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: importing ? null : pickFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Selecionar planilha'),
                      ),
                      OutlinedButton.icon(
                        onPressed: importing ? null : validate,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Validar estrutura'),
                      ),
                      FilledButton.icon(
                        onPressed: importing ? null : importFile,
                        icon: const Icon(Icons.playlist_add_check_circle_outlined),
                        label: Text(importing ? 'Importando...' : 'Importar agora'),
                      ),
                      TextButton(
                        onPressed: importing ? null : () => Navigator.of(sheetContext).pop(),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _PriceImportValidation {
  const _PriceImportValidation({
    required this.ok,
    required this.message,
    required this.rows,
  });

  final bool ok;
  final String message;
  final int rows;
}

_PriceImportValidation _validatePriceSheet(PlatformFile file) {
  final fileName = file.name.trim().toLowerCase();
  if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
    return const _PriceImportValidation(
      ok: true,
      message: 'Arquivo Excel aceito. Parse detalhado sera feito no backend de importacao.',
      rows: 0,
    );
  }

  if (!fileName.endsWith('.csv')) {
    return const _PriceImportValidation(
      ok: false,
      message: 'Formato invalido. Use CSV, XLS ou XLSX.',
      rows: 0,
    );
  }

  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return const _PriceImportValidation(
      ok: false,
      message: 'Arquivo CSV sem conteudo.',
      rows: 0,
    );
  }

  final text = _decodeFile(bytes);
  final lines = const LineSplitter()
      .convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);

  if (lines.length < 2) {
    return const _PriceImportValidation(
      ok: false,
      message: 'CSV precisa de cabecalho e ao menos uma linha de dados.',
      rows: 0,
    );
  }

  final separator = _detectSeparator(lines.first);
  final header = _splitCsvLine(lines.first, separator)
      .map((value) => value.trim().toLowerCase())
      .toList(growable: false);

  final hasCodigo = header.contains('codigointerno') ||
      header.contains('codigo_interno') ||
      header.contains('codigo') ||
      header.contains('sku');
  final hasPreco = header.contains('preco') ||
      header.contains('valor') ||
      header.contains('valor_bruto');

  if (!hasCodigo || !hasPreco) {
    return const _PriceImportValidation(
      ok: false,
      message: 'Cabecalho invalido. Campos obrigatorios: codigoInterno e preco.',
      rows: 0,
    );
  }

  return _PriceImportValidation(
    ok: true,
    message: 'CSV valido com ${lines.length - 1} linhas de preco.',
    rows: lines.length - 1,
  );
}

String _decodeFile(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String _scopeLabel(String scopeType) {
  switch (scopeType) {
    case 'client':
      return 'Cliente';
    case 'region':
      return 'Regiao';
    case 'channel':
      return 'Canal';
    default:
      return 'Geral';
  }
}

String _scopeHint(String scopeType) {
  switch (scopeType) {
    case 'client':
      return 'Ex.: cliente_123';
    case 'region':
      return 'Ex.: SP, SUL, NORDESTE';
    case 'channel':
      return 'Ex.: atacado';
    default:
      return 'Opcional para tabela geral';
  }
}

String _buildImportedName(String fileName, String scopeType) {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  return 'Import $stamp (${_scopeLabel(scopeType)}) - $fileName';
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '-';
  }

  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

List<String> _buildScopeIndex(String scopeType, String rawScopeValue) {
  final cleaned = rawScopeValue.trim().toLowerCase();
  if (cleaned.isEmpty) {
    return [scopeType];
  }

  final separators = RegExp('[,;|/]');
  final tokens = cleaned
      .split(separators)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  return [scopeType, ...tokens];
}

String _detectSeparator(String line) {
  final semicolon = ';'.allMatches(line).length;
  final comma = ','.allMatches(line).length;
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