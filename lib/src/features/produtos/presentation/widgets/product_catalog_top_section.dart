import 'package:flutter/material.dart';

class ProductCatalogTopSection extends StatelessWidget {
  const ProductCatalogTopSection({
    super.key,
    required this.creatingNewProduct,
    required this.canCreateOrImportProducts,
    required this.representedCompanyName,
    required this.onImportExcel,
    required this.onDownloadExcelModel,
    required this.onCreateProduct,
  });

  final bool creatingNewProduct;
  final bool canCreateOrImportProducts;
  final String? representedCompanyName;
  final VoidCallback onImportExcel;
  final VoidCallback onDownloadExcelModel;
  final VoidCallback onCreateProduct;

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

    if (creatingNewProduct) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Produtos', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(subtitle),
        const SizedBox(height: 12),
        if (canCreateOrImportProducts)
          _buildHeaderActions()
        else
          Text(
            'Catálogo gerenciado por integração ERP. Edição manual indisponível.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
