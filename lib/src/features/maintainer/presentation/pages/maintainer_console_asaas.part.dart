part of 'maintainer_console_page.dart';

extension _MaintainerConsoleAsaasPart on _MaintainerConsolePageState {
  Widget _buildAsaasIntegrationCard(
    BuildContext context,
    MaintainerAccessDecision decision,
  ) {
    final canManage = decision.can(
      MaintainerPermission.manageBillingIntegrations,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Integracao Asaas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Configura metadados nao sensiveis do Asaas para preparar o backend multi-provider. Chaves/token devem permanecer somente no backend/Secret Manager.',
                ),
                const SizedBox(height: 12),
                StreamBuilder<MaintainerAsaasIntegrationConfig>(
                  stream: _billingIntegrationService.watchAsaasConfig(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    if (snapshot.hasError) {
                      return Text(
                        'Falha ao carregar configuracao Asaas: ${snapshot.error}',
                      );
                    }

                    final config =
                        snapshot.data ?? MaintainerAsaasIntegrationConfig.empty;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            _stripeFieldRow(
                              context,
                              label: 'Ambiente ativo',
                              value: config.activeEnvironment,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Wallet ID ativo',
                              value: config.activeWalletId.isEmpty
                                  ? '--'
                                  : config.activeWalletId,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Wallet ID (sandbox)',
                              value: config.walletIdSandbox.isEmpty
                                  ? '--'
                                  : config.walletIdSandbox,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Wallet ID (producao)',
                              value: config.walletIdProduction.isEmpty
                                  ? '--'
                                  : config.walletIdProduction,
                            ),
                            _stripeFieldRow(
                              context,
                              label: 'Webhook endpoint',
                              value: config.webhookEndpoint.isEmpty
                                  ? '--'
                                  : config.webhookEndpoint,
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
                              ? () => _openAsaasConfigDialog(existing: config)
                              : null,
                          icon: const Icon(Icons.tune_outlined),
                          label: const Text('Editar configuracao Asaas'),
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

  Future<void> _openAsaasConfigDialog({
    required MaintainerAsaasIntegrationConfig existing,
  }) async {
    final walletIdSandboxController = TextEditingController(
      text: existing.walletIdSandbox,
    );
    final walletIdProductionController = TextEditingController(
      text: existing.walletIdProduction,
    );
    final webhookEndpointController = TextEditingController(
      text: existing.webhookEndpoint,
    );
    var activeEnvironment = existing.activeEnvironment;
    if (activeEnvironment != 'production') {
      activeEnvironment = 'sandbox';
    }

    String? errorText;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Configurar Integracao Asaas'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: activeEnvironment,
                      decoration: const InputDecoration(
                        labelText: 'Ambiente ativo',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'sandbox',
                          child: Text('sandbox'),
                        ),
                        DropdownMenuItem(
                          value: 'production',
                          child: Text('production'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) {
                              setLocalState(() {
                                activeEnvironment = (value ?? 'sandbox')
                                    .trim()
                                    .toLowerCase();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: walletIdSandboxController,
                      decoration: const InputDecoration(
                        labelText: 'Wallet ID (sandbox)',
                        hintText: 'Ex.: 14f4b3f1-9a2f-4f0e-9c12-abcdef123456',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: walletIdProductionController,
                      decoration: const InputDecoration(
                        labelText: 'Wallet ID (producao)',
                        hintText: 'Ex.: 62a9de08-35da-45ec-a2ef-abcdef654321',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: webhookEndpointController,
                      decoration: const InputDecoration(
                        labelText: 'Webhook endpoint (publico)',
                        hintText: 'https://.../handleAsaasWebhook',
                        border: OutlineInputBorder(),
                      ),
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
                          setLocalState(() {
                            saving = true;
                            errorText = null;
                          });

                          try {
                            final actorUid =
                                (FirebaseAuth.instance.currentUser?.uid ?? '')
                                    .trim();
                            await _billingIntegrationService.upsertAsaasConfig(
                              activeEnvironment: activeEnvironment,
                              walletIdSandbox: walletIdSandboxController.text,
                              walletIdProduction:
                                  walletIdProductionController.text,
                              webhookEndpoint: webhookEndpointController.text,
                              actorUid: actorUid,
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setLocalState(() {
                              errorText =
                                  'Falha ao salvar configuracao Asaas: $error';
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

    walletIdSandboxController.dispose();
    walletIdProductionController.dispose();
    webhookEndpointController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao Asaas atualizada.')),
      );
    }
  }
}
