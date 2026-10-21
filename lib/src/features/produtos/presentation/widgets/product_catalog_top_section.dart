import 'package:flutter/material.dart';

import 'header_card.dart';

class ProductCatalogTopSection extends StatelessWidget {
  const ProductCatalogTopSection({
    super.key,
    required this.creatingNewProduct,
    required this.canCreateOrImportProducts,
    required this.representedCompanyName,
    required this.showEnterpriseSyncSwitchCard,
    required this.erpSyncEnabled,
    required this.erpSyncChangeEnabled,
    required this.onImportExcel,
    required this.onDownloadExcelModel,
    required this.onCreateProduct,
    required this.onErpSyncChanged,
  });

  final bool creatingNewProduct;
  final bool canCreateOrImportProducts;
  final String? representedCompanyName;
  final bool showEnterpriseSyncSwitchCard;
  final bool erpSyncEnabled;
  final bool erpSyncChangeEnabled;
  final VoidCallback onImportExcel;
  final VoidCallback onDownloadExcelModel;
  final VoidCallback onCreateProduct;
  final ValueChanged<bool> onErpSyncChanged;

  Widget _buildHeaderActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        final rightActions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onDownloadExcelModel,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Baixar modelo XLSX'),
            ),
            OutlinedButton.icon(
              onPressed: onImportExcel,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Importar Excel'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: onCreateProduct,
                icon: const Icon(Icons.add),
                label: const Text('Novo produto'),
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: rightActions),
            ],
          );
        }

        return Row(
          children: [
            FilledButton.icon(
              onPressed: onCreateProduct,
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            ),
            const Spacer(),
            rightActions,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final representedName = (representedCompanyName ?? '').trim();
    final subtitle = representedName.isEmpty
        ? 'Cadastro de Produtos da Empresa'
        : 'Cadastro de Produtos da $representedName';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!creatingNewProduct)
          HeaderCard(
            title: 'Produtos',
            subtitle: subtitle,
            actions: [
              if (canCreateOrImportProducts) ...[_buildHeaderActions()],
            ],
          ),
        if (showEnterpriseSyncSwitchCard) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.sync_lock_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Sincronizar Produtos do ERP',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Quando ativado desativa o cadastro manual e sincroniza produtos do ERP.',
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: erpSyncEnabled,
                    onChanged: erpSyncChangeEnabled ? onErpSyncChanged : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
