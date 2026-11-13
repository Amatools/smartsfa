part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlansPart on _MaintainerConsolePageState {
  Widget _buildStripePlanSection(
    BuildContext context, {
    required _StripePlanSection section,
    required List<MaintainerStripePlanMapping> mappings,
  }) {
    final title = _stripePlanSectionLabel(section);
    final description = _stripePlanSectionDescription(section);
    final canCreateFromSection = section != _StripePlanSection.outros;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DEE7)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openStripeCatalogImportDialog(
                      initialSection: canCreateFromSection
                          ? section
                          : _StripePlanSection.outros,
                    ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Importar da Stripe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canCreateFromSection
                        ? () => _openStripePlanMappingDialog(
                            initialSection: section,
                          )
                        : _openStripePlanMappingDialog,
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('Cadastrar plano'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mappings.isEmpty)
            const Text('Nenhum plano cadastrado nesta seção.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 12,
                columnSpacing: 20,
                headingRowHeight: 44,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 56,
                columns: const [
                  DataColumn(label: Text('Nome do plano')),
                  DataColumn(label: Text('Valor')),
                  DataColumn(label: Text('Acoes')),
                  DataColumn(label: Text('Plan key')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Stripe product')),
                  DataColumn(label: Text('Stripe price')),
                  DataColumn(label: Text('Metrica excedente')),
                  DataColumn(label: Text('Ativo')),
                  DataColumn(label: Text('Atualizado')),
                ],
                rows: mappings
                    .map(
                      (mapping) => DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 140,
                              child: Text(
                                mapping.planDisplayName.isEmpty
                                    ? mapping.billingPlanKey
                                    : mapping.planDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 160,
                              child: Text(
                                mapping.planDisplayAmount.isEmpty
                                    ? '--'
                                    : mapping.planDisplayAmount,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 96,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: mapping.active
                                        ? 'Ocultar para novas contratações'
                                        : 'Reativar para novas contratações',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints.tightFor(
                                        width: 34,
                                        height: 34,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        mapping.active
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleStripePlanMapping(
                                        mapping,
                                        active: !mapping.active,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Excluir plano',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints.tightFor(
                                        width: 34,
                                        height: 34,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Color(0xFFB3261E),
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _confirmDeleteStripePlanMapping(mapping),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: Text(
                                mapping.billingPlanKey,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 70,
                              child: Text(
                                mapping.mappingType,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 170,
                              child: Text(
                                mapping.stripeProductId.isEmpty
                                    ? '--'
                                    : mapping.stripeProductId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 170,
                              child: Text(
                                mapping.stripePriceId.isEmpty
                                    ? '--'
                                    : mapping.stripePriceId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: Text(
                                mapping.overageMetric.isEmpty
                                    ? '--'
                                    : mapping.overageMetric,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(mapping.active ? 'sim' : 'nao')),
                          DataCell(
                            SizedBox(
                              width: 96,
                              child: Text(
                                _formatDateTime(mapping.updatedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteStripePlanMapping(
    MaintainerStripePlanMapping mapping,
  ) async {
    final planName = mapping.planDisplayName.trim().isEmpty
        ? mapping.billingPlanKey
        : mapping.planDisplayName.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir plano da lista'),
          content: Text(
            'Deseja excluir o mapeamento "$planName"?\n\n'
            'Plan key: ${mapping.billingPlanKey}\n\n'
            'Essa acao remove o plano da lista de mapeamentos.\n'
            'Se o plano estiver em uso por algum tenant, a exclusao sera bloqueada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
              ),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _billingIntegrationService.deletePlanMapping(
        mappingId: mapping.mappingId,
        actorUid: _currentActorUid(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano removido da lista.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir plano: $error')),
      );
    }
  }

  Future<void> _toggleStripePlanMapping(
    MaintainerStripePlanMapping mapping, {
    required bool active,
  }) async {
    final actionLabel = active ? 'reativar' : 'ocultar';
    try {
      await _billingIntegrationService.setPlanMappingActive(
        mappingId: mapping.mappingId,
        active: active,
        actorUid: _currentActorUid(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'Plano reativado para novas contratações.'
                : 'Plano ocultado para novas contratações.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao $actionLabel plano: $error')),
      );
    }
  }
}
