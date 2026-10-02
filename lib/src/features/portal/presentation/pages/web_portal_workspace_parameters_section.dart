part of 'web_portal_page.dart';

class _WorkspaceParametersSection extends StatefulWidget {
  const _WorkspaceParametersSection({required this.activeTenant});

  final TenantEntryOption activeTenant;

  @override
  State<_WorkspaceParametersSection> createState() =>
      _WorkspaceParametersSectionState();
}

class _WorkspaceParametersSectionState
    extends State<_WorkspaceParametersSection> {
  final WorkspaceProfileService _service = WorkspaceProfileService(
    FirebaseFirestore.instance,
  );
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _service.watchWorkspace(widget.activeTenant.tenantId),
      builder: (context, snapshot) {
        final workspaceData = snapshot.data ?? const <String, dynamic>{};
        final workspaceType = widget.activeTenant.workspaceType;
        final planBaseLabel = _planBaseLabelFromWorkspaceType(workspaceType);
        final planTier = _workspacePlanTier(workspaceData);
        final canUseAdvancedPricing = _isFeatureAvailableByPlan(
          workspaceType: workspaceType,
          planTier: planTier,
          featureKey: _featureAdvancedPricing,
        );
        final advancedPricingEnabled =
            _featureFlagEnabled(
              workspaceData,
              _featureAdvancedPricing,
              legacyField: 'advancedPricingEnabled',
            ) &&
            canUseAdvancedPricing;
        final showMinimumPriceForTeamEnabled = _featureFlagEnabled(
          workspaceData,
          'showMinimumPriceForTeamEnabled',
        );
        final allowDiscountApprovalOverrideEnabled = _featureFlagEnabled(
          workspaceData,
          'allowDiscountApprovalOverrideEnabled',
        );

        return Stack(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parametros',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ajustes de comportamento do modulo comercial para este workspace.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Plano: $planBaseLabel',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Chip(
                          label: Text(
                            planTier == _planTierUpgrade
                                ? 'Upgrade ativo'
                                : 'Plano base',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: _planTierBase,
                          label: Text('Base'),
                        ),
                        ButtonSegment<String>(
                          value: _planTierUpgrade,
                          label: Text('Upgrade'),
                        ),
                      ],
                      selected: <String>{planTier},
                      onSelectionChanged: canEditSettings && !_updating
                          ? (values) {
                              if (values.isEmpty) {
                                return;
                              }
                              _setPlanTier(values.first);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este seletor representa o nivel do plano e sera controlado pelo billing no futuro.',
                    ),
                    const SizedBox(height: 14),
                    if (!canEditSettings) ...[
                      _ownerOnlyReadOnlyNotice(
                        context,
                        message: 'Somente o owner pode alterar parametros deste workspace. Este perfil pode apenas consultar.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      value: advancedPricingEnabled,
                      onChanged:
                          canEditSettings && canUseAdvancedPricing && !_updating
                          ? _setAdvancedPricingEnabled
                          : null,
                      title: const Text('Precificacao avancada'),
                      subtitle: Text(
                        canUseAdvancedPricing
                            ? 'Habilita tabelas de preco adicionais para variacoes por estado, regiao, cliente ou campanha.'
                            : 'Disponivel apenas no plano Upgrade.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: showMinimumPriceForTeamEnabled,
                      onChanged: canEditSettings && !_updating
                          ? (value) => _setFeatureFlag(
                              key: 'showMinimumPriceForTeamEnabled',
                              value: value,
                              enabledMessage: 'Exibicao de preco minimo para equipe ativada.',
                              disabledMessage: 'Exibicao de preco minimo para equipe desativada.',
                            )
                          : null,
                      title: const Text('Exibir preco minimo para equipe'),
                      subtitle: const Text(
                        'Placeholder para politica futura. Sem efeito operacional neste momento.',
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: allowDiscountApprovalOverrideEnabled,
                      onChanged: canEditSettings && !_updating
                          ? (value) => _setFeatureFlag(
                              key: 'allowDiscountApprovalOverrideEnabled',
                              value: value,
                              enabledMessage: 'Aprovacao para desconto acima do limite ativada.',
                              disabledMessage: 'Aprovacao para desconto acima do limite desativada.',
                            )
                          : null,
                      title: const Text(
                        'Permitir desconto acima do limite com aprovacao',
                      ),
                      subtitle: const Text(
                        'Placeholder para fluxo futuro de aprovacao comercial.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !canUseAdvancedPricing
                          ? 'Status: bloqueada pelo plano atual. Ative o Upgrade para liberar este recurso.'
                          : advancedPricingEnabled
                          ? 'Status: ativa. O submenu de Tabelas de preço fica disponivel em Produtos.'
                          : 'Status: inativa. O submenu de Tabelas de preço fica oculto.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            if (_updating)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            'S',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 8),
                        const Text('Atualizando parametros...'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _setAdvancedPricingEnabled(bool enabled) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.setAdvancedPricingEnabled(
        tenantId: widget.activeTenant.tenantId,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Precificacao avancada ativada.'
                : 'Precificacao avancada desativada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar parametro: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _setPlanTier(String tier) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.setWorkspacePlanTier(
        tenantId: widget.activeTenant.tenantId,
        tier: tier,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tier == _planTierUpgrade
                ? 'Nivel do plano atualizado para Upgrade.'
                : 'Nivel do plano atualizado para Base.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar nivel do plano: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _setFeatureFlag({
    required String key,
    required bool value,
    required String enabledMessage,
    required String disabledMessage,
  }) async {
    setState(() {
      _updating = true;
    });

    try {
      await _service.updateWorkspaceFeatureFlags(
        tenantId: widget.activeTenant.tenantId,
        flags: {key: value},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? enabledMessage : disabledMessage)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar parametro: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }
}
