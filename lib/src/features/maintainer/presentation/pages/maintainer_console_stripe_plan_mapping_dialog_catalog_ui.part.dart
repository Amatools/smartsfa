part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlanMappingDialogCatalogUiPart
    on _MaintainerConsolePageState {
  Widget _buildStripeCreateCatalogSection({
    required BuildContext context,
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStripeCreateCatalogHeader(context),
          const SizedBox(height: 10),
          _buildStripeCreateCatalogAmountCurrencyRow(
            dialogState: dialogState,
            setLocalState: setLocalState,
          ),
          const SizedBox(height: 8),
          _buildStripeCreateCatalogRecurringRow(
            dialogState: dialogState,
            setLocalState: setLocalState,
          ),
          const SizedBox(height: 8),
          _buildStripeCreateCatalogLookupKeyField(dialogState),
          const SizedBox(height: 8),
          _buildStripeCreateCatalogActionButton(
            dialogState: dialogState,
            setLocalState: setLocalState,
          ),
          if (dialogState.stripeCreateStatus.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildStripeCreateCatalogStatusText(context, dialogState),
          ],
        ],
      ),
    );
  }

  Widget _buildStripeCreateCatalogHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Criar Product/Price no Stripe',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Use este fluxo para gerar os IDs no Stripe automaticamente e preencher os campos abaixo. Lookup key e uma chave de busca do Price no Stripe (nao e metadata).',
        ),
      ],
    );
  }

  Widget _buildStripeCreateCatalogAmountCurrencyRow({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: dialogState.createAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor',
              hintText: 'Ex.: 59.90',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<String>(
            initialValue: dialogState.createCurrency,
            decoration: const InputDecoration(
              labelText: 'Moeda',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'brl', child: Text('BRL')),
              DropdownMenuItem(value: 'usd', child: Text('USD')),
              DropdownMenuItem(value: 'eur', child: Text('EUR')),
            ],
            onChanged: (value) {
              setLocalState(() {
                dialogState.createCurrency = (value ?? 'brl')
                    .trim()
                    .toLowerCase();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStripeCreateCatalogRecurringRow({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: dialogState.createRecurringInterval,
            decoration: const InputDecoration(
              labelText: 'Intervalo recorrente',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'month', child: Text('month')),
              DropdownMenuItem(value: 'year', child: Text('year')),
              DropdownMenuItem(value: 'week', child: Text('week')),
              DropdownMenuItem(value: 'day', child: Text('day')),
            ],
            onChanged: (value) {
              setLocalState(() {
                dialogState.createRecurringInterval = (value ?? 'month')
                    .trim()
                    .toLowerCase();
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: TextField(
            controller: dialogState.createIntervalCountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Interval count',
              hintText: '1',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStripeCreateCatalogLookupKeyField(
    _StripePlanMappingDialogState dialogState,
  ) {
    return TextField(
      controller: dialogState.createLookupKeyController,
      decoration: const InputDecoration(
        labelText: 'Lookup key (opcional)',
        hintText: 'Se vazio, gera automaticamente no padrao smartsfa_*',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeCreateCatalogActionButton({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: dialogState.isSaving || dialogState.isCreatingInStripe
            ? null
            : () => _createStripeCatalogArtifactsFromDialog(
                dialogState: dialogState,
                setLocalState: setLocalState,
              ),
        icon: dialogState.isCreatingInStripe
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_fix_high),
        label: Text(
          dialogState.isCreatingInStripe
              ? 'Criando...'
              : 'Criar no Stripe e preencher IDs',
        ),
      ),
    );
  }

  Widget _buildStripeCreateCatalogStatusText(
    BuildContext context,
    _StripePlanMappingDialogState dialogState,
  ) {
    return Text(
      dialogState.stripeCreateStatus,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: const Color(0xFF15603C)),
    );
  }
}
