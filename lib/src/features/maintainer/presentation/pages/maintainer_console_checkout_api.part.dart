part of 'maintainer_console_page.dart';

extension _MaintainerConsoleCheckoutApiPart on _MaintainerConsolePageState {
  Widget _buildCheckoutApiCard(
    BuildContext context,
    MaintainerAccessDecision decision,
  ) {
    final canManage = decision.can(
      MaintainerPermission.manageBillingIntegrations,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API Checkout',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Define quais provedores ficam ativos no checkout (Stripe, Asaas ou ambos) e qual provider preferencial sera usado como fallback do backend.',
                ),
                const SizedBox(height: 12),
                StreamBuilder<MaintainerCheckoutApiConfig>(
                  stream: _billingIntegrationService.watchCheckoutApiConfig(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    if (snapshot.hasError) {
                      return Text(
                        'Falha ao carregar configuracao de API Checkout: ${snapshot.error}',
                      );
                    }

                    final config =
                        snapshot.data ?? MaintainerCheckoutApiConfig.empty;
                    final modeLabel = _checkoutApiModeLabel(config);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            _stripeFieldRow(
                              context,
                              label: 'Modo ativo',
                              value: modeLabel,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Provider preferencial',
                              value: config.preferredProvider,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Atualizado em',
                              value: _formatDateTime(config.updatedAt),
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Atualizado por',
                              value: config.updatedBy.isEmpty
                                  ? '--'
                                  : config.updatedBy,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: canManage
                              ? () => _openCheckoutApiConfigDialog(
                                  existing: config,
                                )
                              : null,
                          icon: const Icon(Icons.tune_outlined),
                          label: const Text('Editar API Checkout'),
                        ),
                        if (!canManage) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Perfil somente leitura para configuracao de integracoes.',
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _checkoutApiModeLabel(MaintainerCheckoutApiConfig config) {
    final stripeEnabled = config.isStripeEnabled;
    final asaasEnabled = config.isAsaasEnabled;
    if (stripeEnabled && asaasEnabled) {
      return 'stripe + asaas';
    }
    if (stripeEnabled) {
      return 'stripe';
    }
    if (asaasEnabled) {
      return 'asaas';
    }
    return 'nenhum';
  }

  Future<void> _openCheckoutApiConfigDialog({
    required MaintainerCheckoutApiConfig existing,
  }) async {
    var stripeEnabled = existing.isStripeEnabled;
    var asaasEnabled = existing.isAsaasEnabled;
    var preferredProvider = existing.preferredProvider.trim().toLowerCase();
    if (preferredProvider.isEmpty) {
      preferredProvider = stripeEnabled ? 'stripe' : 'asaas';
    }
    String? errorText;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final availableProviders = <String>{
              if (stripeEnabled) 'stripe',
              if (asaasEnabled) 'asaas',
            };

            if (!availableProviders.contains(preferredProvider)) {
              preferredProvider = stripeEnabled ? 'stripe' : 'asaas';
            }

            return AlertDialog(
              title: const Text('Configurar API Checkout'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecione quais provedores podem ser usados no checkout.',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Stripe ativo'),
                      value: stripeEnabled,
                      onChanged: saving
                          ? null
                          : (value) {
                              setLocalState(() {
                                stripeEnabled = value == true;
                              });
                            },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Asaas ativo'),
                      value: asaasEnabled,
                      onChanged: saving
                          ? null
                          : (value) {
                              setLocalState(() {
                                asaasEnabled = value == true;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue:
                          availableProviders.contains(preferredProvider)
                          ? preferredProvider
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Provider preferencial',
                        border: OutlineInputBorder(),
                      ),
                      items: availableProviders
                          .map(
                            (provider) => DropdownMenuItem<String>(
                              value: provider,
                              child: Text(provider),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving || availableProviders.isEmpty
                          ? null
                          : (value) {
                              setLocalState(() {
                                preferredProvider = (value ?? '')
                                    .trim()
                                    .toLowerCase();
                              });
                            },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!stripeEnabled && !asaasEnabled) {
                            setLocalState(() {
                              errorText =
                                  'Selecione ao menos um provider ativo.';
                            });
                            return;
                          }

                          setLocalState(() {
                            saving = true;
                            errorText = null;
                          });

                          try {
                            final actorUid =
                                (FirebaseAuth.instance.currentUser?.uid ?? '')
                                    .trim();
                            await _billingIntegrationService
                                .upsertCheckoutApiConfig(
                                  activeProviders: <String>{
                                    if (stripeEnabled) 'stripe',
                                    if (asaasEnabled) 'asaas',
                                  },
                                  preferredProvider: preferredProvider,
                                  actorUid: actorUid,
                                );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setLocalState(() {
                              errorText =
                                  'Falha ao salvar API Checkout: $error';
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API Checkout atualizada.')));
    }
  }
}
