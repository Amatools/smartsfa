part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePart on _MaintainerConsolePageState {
  Widget _buildStripeIntegrationCard(BuildContext context) {
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
                  'Integracao Stripe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Configura apenas metadados nao sensiveis e mapeamento de planos. Chaves e webhook secrets permanecem exclusivamente no backend/Secret Manager.',
                ),
                const SizedBox(height: 12),
                _buildStripeConfigurationSection(context),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  'Mapeamento billingPlanKey -> Stripe price',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cadastre os planos dentro da seção da conta para manter o catálogo organizado por tipo de workspace.',
                ),
                const SizedBox(height: 10),
                _buildStripeMappingsSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stripeFieldRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildStripeConfigurationSection(BuildContext context) {
    return StreamBuilder<MaintainerStripeIntegrationConfig>(
      stream: _billingIntegrationService.watchStripeConfig(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        if (snapshot.hasError) {
          return Text(
            'Falha ao carregar configuracao Stripe: ${snapshot.error}',
          );
        }

        final config = snapshot.data ?? MaintainerStripeIntegrationConfig.empty;
        final webhookEventsLabel = config.webhookEvents.isEmpty
            ? '--'
            : config.webhookEvents.join(', ');
        final suggestedWebhookEndpoint = _defaultStripeWebhookEndpointUrl();

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
                  label: 'Account ID (test)',
                  value: config.accountIdTest.isEmpty
                      ? '--'
                      : config.accountIdTest,
                ),
                _stripeFieldRow(
                  context,
                  label: 'Account ID (live)',
                  value: config.accountIdLive.isEmpty
                      ? '--'
                      : config.accountIdLive,
                ),
                _stripeFieldRow(
                  context,
                  label: 'Webhook endpoint (test)',
                  value: config.webhookEndpointTest.isEmpty
                      ? suggestedWebhookEndpoint
                      : config.webhookEndpointTest,
                ),
                _stripeFieldRow(
                  context,
                  label: 'Webhook endpoint (live)',
                  value: config.webhookEndpointLive.isEmpty
                      ? suggestedWebhookEndpoint
                      : config.webhookEndpointLive,
                ),
                _stripeFieldRow(
                  context,
                  label: 'Eventos inscritos',
                  value: webhookEventsLabel,
                ),
                _stripeFieldRow(
                  context,
                  label: 'Atualizado em',
                  value: _formatDateTime(config.updatedAt),
                ),
                _stripeFieldRow(
                  context,
                  label: 'Atualizado por',
                  value: config.updatedBy.isEmpty ? '--' : config.updatedBy,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _openStripeConfigDialog(existing: config),
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('Editar configuracao'),
                ),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Gerenciar segredos (backend)'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStripeMappingsSection(BuildContext context) {
    return StreamBuilder<List<MaintainerStripePlanMapping>>(
      stream: _billingIntegrationService.watchStripePlanMappings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (snapshot.hasError) {
          return Text(
            'Falha ao carregar mapeamentos: ${snapshot.error}',
          );
        }

        final mappings = snapshot.data ?? const <MaintainerStripePlanMapping>[];
        final grouped =
            <_StripePlanSection, List<MaintainerStripePlanMapping>>{};
        for (final mapping in mappings) {
          final section = _stripePlanSectionFromPlanKey(mapping.billingPlanKey);
          grouped
              .putIfAbsent(section, () => <MaintainerStripePlanMapping>[])
              .add(mapping);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStripePlanSection(
              context,
              section: _StripePlanSection.individual,
              mappings:
                  grouped[_StripePlanSection.individual] ??
                  const <MaintainerStripePlanMapping>[],
            ),
            const SizedBox(height: 12),
            _buildStripePlanSection(
              context,
              section: _StripePlanSection.representacoes,
              mappings:
                  grouped[_StripePlanSection.representacoes] ??
                  const <MaintainerStripePlanMapping>[],
            ),
            const SizedBox(height: 12),
            _buildStripePlanSection(
              context,
              section: _StripePlanSection.enterprise,
              mappings:
                  grouped[_StripePlanSection.enterprise] ??
                  const <MaintainerStripePlanMapping>[],
            ),
            if ((grouped[_StripePlanSection.outros] ??
                    const <MaintainerStripePlanMapping>[])
                .isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStripePlanSection(
                context,
                section: _StripePlanSection.outros,
                mappings:
                    grouped[_StripePlanSection.outros] ??
                    const <MaintainerStripePlanMapping>[],
              ),
            ],
          ],
        );
      },
    );
  }
}
