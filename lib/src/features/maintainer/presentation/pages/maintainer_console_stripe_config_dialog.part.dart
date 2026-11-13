part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripeConfigDialogPart
    on _MaintainerConsolePageState {
  Future<void> _openStripeConfigDialog({
    required MaintainerStripeIntegrationConfig existing,
  }) async {
    var activeEnvironment = existing.activeEnvironment == 'live'
        ? 'live'
        : 'test';
    final defaultWebhookBaseUrl = _defaultStripeWebhookBaseUrl();
    final accountIdTestController = TextEditingController(
      text: existing.accountIdTest,
    );
    final accountIdLiveController = TextEditingController(
      text: existing.accountIdLive,
    );
    final webhookTestController = TextEditingController(
      text: existing.webhookEndpointTest.isEmpty
          ? defaultWebhookBaseUrl
          : existing.webhookEndpointTest,
    );
    final webhookLiveController = TextEditingController(
      text: existing.webhookEndpointLive.isEmpty
          ? defaultWebhookBaseUrl
          : existing.webhookEndpointLive,
    );
    final webhookEventsController = TextEditingController(
      text: (existing.webhookEvents.isEmpty
              ? _MaintainerConsolePageState._defaultStripeWebhookEvents
              : existing.webhookEvents)
          .join('\n'),
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Configurar integração Stripe'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
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
                          DropdownMenuItem(value: 'test', child: Text('test')),
                          DropdownMenuItem(value: 'live', child: Text('live')),
                        ],
                        onChanged: (value) {
                          setLocalState(() {
                            activeEnvironment = (value ?? 'test').trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: accountIdTestController,
                        decoration: const InputDecoration(
                          labelText: 'Stripe account ID (test)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: accountIdLiveController,
                        decoration: const InputDecoration(
                          labelText: 'Stripe account ID (live)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Base sugerida para Cloud Functions: $defaultWebhookBaseUrl',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webhookTestController,
                        decoration: const InputDecoration(
                          labelText: 'Webhook endpoint (test)',
                          hintText:
                              'URL completa ou somente sufixo (ex.: handleStripeWebhook)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webhookLiveController,
                        decoration: const InputDecoration(
                          labelText: 'Webhook endpoint (live)',
                          hintText:
                              'URL completa ou somente sufixo (ex.: handleStripeWebhook)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webhookEventsController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Eventos de webhook (1 por linha)',
                          hintText:
                              'checkout.session.completed\ncustomer.subscription.updated\ninvoice.paid',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            setLocalState(() {
                              webhookEventsController.text =
                                  _MaintainerConsolePageState._defaultStripeWebhookEvents.join('\n');
                            });
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Restaurar padrao'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Padrao recomendado ja vem preenchido; voce pode alterar antes de salvar.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Segredos (sk_*, whsec_*) nao sao salvos aqui. Devem ser gerenciados apenas no backend/Secret Manager.',
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          try {
                            await _billingIntegrationService.upsertStripeConfig(
                              activeEnvironment: activeEnvironment,
                              accountIdTest: accountIdTestController.text,
                              accountIdLive: accountIdLiveController.text,
                              webhookEndpointTest: _normalizeWebhookEndpointInput(
                                rawInput: webhookTestController.text,
                                defaultBaseUrl: defaultWebhookBaseUrl,
                              ),
                              webhookEndpointLive: _normalizeWebhookEndpointInput(
                                rawInput: webhookLiveController.text,
                                defaultBaseUrl: defaultWebhookBaseUrl,
                              ),
                              webhookEvents: _parseWebhookEvents(
                                webhookEventsController.text,
                              ),
                              actorUid: _currentActorUid(),
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop(true);
                          } catch (error) {
                            setLocalState(() {
                              errorText =
                                  'Falha ao salvar configuracao Stripe: $error';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Salvar configuração'),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeTextEditingControllersSafely([
      accountIdTestController,
      accountIdLiveController,
      webhookTestController,
      webhookLiveController,
      webhookEventsController,
    ]);

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração Stripe atualizada.')),
      );
    }
  }
}
