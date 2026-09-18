import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/repositories/produto_repository.dart';
import '../services/product_csv_import_service.dart';

Future<void> openProductImportSheet(
  BuildContext context, {
  required AppIdentity identity,
  required ProdutoRepository repository,
}) async {
  final importService = ProductCsvImportService(
    identity: identity,
    repository: repository,
  );
  PlatformFile? selectedFile;
  ProductImportValidation? validation;
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
              allowedExtensions: const ['csv'],
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

          void validate() {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione um CSV primeiro.')),
              );
              return;
            }
            setSheetState(() {
              validation = importService.validateFile(file);
            });
          }

          Future<void> importProducts() async {
            final file = selectedFile;
            if (file == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecione um CSV para importar.')),
              );
              return;
            }

            final report = validation ?? importService.validateFile(file);
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
              final imported = await importService.importRows(report.rows);

              if (!context.mounted) {
                return;
              }

              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$imported produto(s) importado(s) com sucesso.')),
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
                    'Importar produtos por CSV',
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cabecalho obrigatorio: descricao. O codigo interno e gerado automaticamente.',
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
                        label: const Text('Selecionar CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: importing ? null : validate,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Validar estrutura'),
                      ),
                      FilledButton.icon(
                        onPressed: importing ? null : importProducts,
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
