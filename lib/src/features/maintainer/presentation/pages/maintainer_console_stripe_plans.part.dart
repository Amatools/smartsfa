part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlansPart on _MaintainerConsolePageState {
  DataCell _buildStripePlanTextCell(
    String rawValue, {
    double? width,
    bool ellipsis = true,
  }) {
    final value = rawValue.trim().isEmpty ? '--' : rawValue.trim();
    final cellText = Tooltip(
      message: value,
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
      ),
    );

    if (width == null) {
      return DataCell(cellText);
    }

    return DataCell(
      SizedBox(
        width: width,
        child: cellText,
      ),
    );
  }

  Widget _buildStripePlanSection(
    BuildContext context, {
    required _StripePlanSection section,
    required List<MaintainerStripePlanMapping> mappings,
    required List<MaintainerStripePlanMapping> availableMappings,
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
                      existingSectionMappings: mappings,
                    ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Importar da Stripe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canCreateFromSection
                        ? () => _openStripePlanMappingDialog(
                            initialSection: section,
                            availableMappings: availableMappings,
                          )
                        : () => _openStripePlanMappingDialog(
                            availableMappings: availableMappings,
                          ),
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
            Scrollbar(
              child: SingleChildScrollView(
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
                    DataColumn(label: Text('Seats base')),
                    DataColumn(label: Text('Addon seats')),
                    DataColumn(label: Text('Stripe product')),
                    DataColumn(label: Text('Stripe price')),
                    DataColumn(label: Text('Metrica excedente')),
                    DataColumn(label: Text('Plano base vinculado')),
                    DataColumn(label: Text('Ativo')),
                    DataColumn(label: Text('Atualizado')),
                  ],
                  rows: mappings
                      .map(
                        (mapping) => DataRow(
                          cells: [
                            _buildStripePlanTextCell(
                              mapping.planDisplayName.isEmpty
                                  ? mapping.billingPlanKey
                                  : mapping.planDisplayName,
                              width: 180,
                            ),
                            _buildStripePlanTextCell(
                              mapping.planDisplayAmount,
                              width: 180,
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
                                        constraints:
                                            const BoxConstraints.tightFor(
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
                                        onPressed:
                                            () => _toggleStripePlanMapping(
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
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 34,
                                              height: 34,
                                            ),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Color(0xFFB3261E),
                                          size: 20,
                                        ),
                                        onPressed:
                                            () =>
                                                _confirmDeleteStripePlanMapping(
                                                  mapping,
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _buildStripePlanTextCell(
                              mapping.billingPlanKey,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.mappingType,
                              width: 90,
                            ),
                            _buildStripePlanTextCell(
                              '${mapping.includedSeats}',
                              width: 96,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.seatAddonPlanKey,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.stripeProductId,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.stripePriceId,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.overageMetric,
                              width: 170,
                            ),
                            _buildStripePlanTextCell(
                              mapping.linkedBasePlanKey,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              mapping.active ? 'sim' : 'nao',
                              width: 70,
                              ellipsis: false,
                            ),
                            _buildStripePlanTextCell(
                              _formatDateTime(mapping.updatedAt),
                              width: 120,
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Plano removido da lista.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao excluir plano: $error')));
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
