import 'package:flutter/material.dart';

import 'header_card.dart';

class ProductCatalogTopSection extends StatelessWidget {
  const ProductCatalogTopSection({
    super.key,
    required this.creatingNewProduct,
    required this.canCreateOrImportProducts,
    required this.availableBrands,
    required this.effectiveBrandFilter,
    required this.showEnterpriseSyncSwitchCard,
    required this.erpSyncEnabled,
    required this.erpSyncChangeEnabled,
    required this.showErpManagedInfoCard,
    required this.onImportExcel,
    required this.onCreateProduct,
    required this.onBrandFilterChanged,
    required this.onErpSyncChanged,
  });

  final bool creatingNewProduct;
  final bool canCreateOrImportProducts;
  final List<String> availableBrands;
  final String effectiveBrandFilter;
  final bool showEnterpriseSyncSwitchCard;
  final bool erpSyncEnabled;
  final bool erpSyncChangeEnabled;
  final bool showErpManagedInfoCard;
  final VoidCallback onImportExcel;
  final VoidCallback onCreateProduct;
  final ValueChanged<String> onBrandFilterChanged;
  final ValueChanged<bool> onErpSyncChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!creatingNewProduct)
          HeaderCard(
            title: 'Produtos',
            subtitle:
                'Cadastro de atributos fisicos e fiscais do produto. Precos e politicas comerciais ficam em modulos dedicados.',
            actions: [
              if (canCreateOrImportProducts) ...[
                OutlinedButton.icon(
                  onPressed: onImportExcel,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Importar Excel'),
                ),
                FilledButton.icon(
                  onPressed: onCreateProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Novo produto'),
                ),
              ],
            ],
          ),
        if (availableBrands.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined),
                  const SizedBox(width: 12),
                  const Text('Marca'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: effectiveBrandFilter,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: <String>['todas', ...availableBrands]
                          .map(
                            (brand) => DropdownMenuItem<String>(
                              value: brand,
                              child: Text(
                                brand == 'todas' ? 'Todas as marcas' : brand,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        onBrandFilterChanged(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (showEnterpriseSyncSwitchCard) ...[
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Sincronizar produtos do ERP'),
              subtitle: const Text(
                'Quando ativado, o ERP vira fonte da verdade e o cadastro manual/importacao de produtos fica bloqueado.',
              ),
              value: erpSyncEnabled,
              onChanged: erpSyncChangeEnabled ? onErpSyncChanged : null,
            ),
          ),
        ],
        if (showErpManagedInfoCard) ...[
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.sync_lock_outlined),
              title: Text('Produtos gerenciados pela integração ERP'),
              subtitle: Text(
                'Neste contexto, a criação manual e a importação por arquivo ficam ocultas para preservar o ERP como fonte única.',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
