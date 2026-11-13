part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripeCatalogPart on _MaintainerConsolePageState {
  Future<void> _openStripeCatalogImportDialog({
    _StripePlanSection initialSection = _StripePlanSection.individual,
  }) async {
    final catalogFuture = _billingIntegrationService.listStripeCatalog();
    var selectedSection = initialSection;

    final selected = await showDialog<_StripeCatalogImportSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Importar planos da Stripe'),
              content: SizedBox(
                width: 940,
                child: FutureBuilder<MaintainerStripeCatalogSnapshot>(
                  future: catalogFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return SizedBox(
                        height: 180,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'Falha ao consultar catalogo Stripe: ${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final catalog = snapshot.data;
                    if (catalog == null || catalog.products.isEmpty) {
                      return const SizedBox(
                        height: 180,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'Nenhum produto/preco encontrado no ambiente Stripe ativo.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ambiente: ${catalog.activeEnvironment} | Account: ${catalog.stripeAccountId.isEmpty ? '--' : catalog.stripeAccountId}',
                        ),
                        if (catalog.hasMoreProducts)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Ha mais produtos no Stripe do que o limite retornado; refine o catalogo no painel para facilitar importacao.',
                            ),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<_StripePlanSection>(
                          initialValue: selectedSection,
                          decoration: const InputDecoration(
                            labelText: 'Seção destino dos novos mapeamentos',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: _StripePlanSection.individual,
                              child: Text('Conta individual'),
                            ),
                            DropdownMenuItem(
                              value: _StripePlanSection.representacoes,
                              child: Text('Conta representacoes'),
                            ),
                            DropdownMenuItem(
                              value: _StripePlanSection.enterprise,
                              child: Text('Conta enterprise'),
                            ),
                            DropdownMenuItem(
                              value: _StripePlanSection.outros,
                              child: Text('Outros mapeamentos'),
                            ),
                          ],
                          onChanged: (value) {
                            setLocalState(() {
                              selectedSection =
                                  value ?? _StripePlanSection.individual;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 360,
                          child: ListView.separated(
                            itemCount: catalog.products.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 16),
                            itemBuilder: (context, index) {
                              final product = catalog.products[index];
                              final productName = product.productName.isEmpty
                                  ? product.productId
                                  : product.productName;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$productName (${product.productId})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  if (product.productDescription.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        product.productDescription,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  if (product.prices.isEmpty)
                                    const Text('Sem prices ativos neste produto.')
                                  else
                                    ...product.prices.map((price) {
                                      final recurring =
                                          price.recurringInterval.isEmpty
                                              ? 'one_time'
                                              : '${price.recurringInterval} x${price.recurringIntervalCount <= 0 ? 1 : price.recurringIntervalCount}';
                                      final amountLabel =
                                          _formatStripeAmountLabel(
                                            amountInMinorUnit: price.unitAmount,
                                            currency: price.currency,
                                          );
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${price.priceId} | $amountLabel | $recurring',
                                              ),
                                            ),
                                            OutlinedButton(
                                              onPressed: () {
                                                final suggestedSlug =
                                                    _suggestPlanSlugFromStripe(
                                                      productName,
                                                      price.nickname,
                                                    );
                                                Navigator.of(dialogContext).pop(
                                                  _StripeCatalogImportSelection(
                                                    section: selectedSection,
                                                    productId: product.productId,
                                                    productName:
                                                        product.productName,
                                                    priceId: price.priceId,
                                                    lookupKey: price.lookupKey,
                                                    priceNickname:
                                                        price.nickname,
                                                    unitAmount: price.unitAmount,
                                                    currency: price.currency,
                                                    recurringInterval:
                                                        price.recurringInterval,
                                                    recurringIntervalCount: price
                                                        .recurringIntervalCount,
                                                    planDisplayAmount:
                                                        _buildPlanDisplayAmountLabel(
                                                      amountInMinorUnit:
                                                          price.unitAmount,
                                                      currency:
                                                          price.currency,
                                                      recurringInterval: price
                                                          .recurringInterval,
                                                      recurringIntervalCount: price
                                                          .recurringIntervalCount,
                                                    ),
                                                    suggestedSlug: price.lookupKey
                                                            .trim()
                                                            .isNotEmpty
                                                        ? price.lookupKey
                                                        : suggestedSlug,
                                                  ),
                                                );
                                              },
                                              child: const Text('Usar este price'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _openStripePlanMappingDialog(
      initialSection: selected.section,
      initialPlanSlug: selected.suggestedSlug,
      initialPlanDisplayName: selected.productName,
      initialPlanDisplayAmount: selected.planDisplayAmount,
      initialProductId: selected.productId,
      initialProductName: selected.productName,
      initialPriceId: selected.priceId,
      initialPriceNickname: selected.priceNickname,
      initialUnitAmount: selected.unitAmount,
      initialCurrency: selected.currency,
      initialRecurringInterval: selected.recurringInterval,
      initialRecurringIntervalCount: selected.recurringIntervalCount,
    );
  }
}
