part of 'maintainer_console_page.dart';

extension _MaintainerConsoleStripePlanMappingDialogUiPart
    on _MaintainerConsolePageState {
  Widget _buildStripePlanMappingDialogContent({
    required BuildContext context,
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStripePlanSectionField(
          dialogState: dialogState,
          setLocalState: setLocalState,
        ),
        const SizedBox(height: 12),
        _buildStripePlanSlugField(
          dialogState: dialogState,
          setLocalState: setLocalState,
        ),
        if (dialogState.selectedSection != _StripePlanSection.outros) ...[
          const SizedBox(height: 8),
          Text(
            'billingPlanKey final: ${_buildBillingPlanKey(dialogState.selectedSection, dialogState.planSlugController.text)}',
          ),
        ],
        const SizedBox(height: 12),
        _buildStripePlanDisplayNameField(dialogState),
        const SizedBox(height: 12),
        _buildStripePlanDisplayAmountField(dialogState),
        const SizedBox(height: 12),
        _buildStripeMappingTypeField(
          dialogState: dialogState,
          setLocalState: setLocalState,
        ),
        const SizedBox(height: 12),
        _buildStripeProductIdField(dialogState),
        const SizedBox(height: 12),
        _buildStripePriceIdField(dialogState),
        const SizedBox(height: 12),
        _buildStripeCreateCatalogSection(
          context: context,
          dialogState: dialogState,
          setLocalState: setLocalState,
        ),
        const SizedBox(height: 12),
        _buildStripeOverageMetricField(dialogState),
        const SizedBox(height: 12),
        _buildStripeActiveSwitch(
          dialogState: dialogState,
          setLocalState: setLocalState,
        ),
        _buildStripeDialogErrorText(dialogState),
      ],
    );
  }

  Widget _buildStripePlanSectionField({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return DropdownButtonFormField<_StripePlanSection>(
      initialValue: dialogState.selectedSection,
      decoration: const InputDecoration(
        labelText: 'Seção de plano',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: false,
        contentPadding: EdgeInsets.fromLTRB(12, 18, 12, 12),
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
          dialogState.selectedSection = value ?? _StripePlanSection.individual;
        });
      },
    );
  }

  Widget _buildStripePlanSlugField({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return TextField(
      controller: dialogState.planSlugController,
      onChanged: (_) => setLocalState(() {}),
      decoration: InputDecoration(
        labelText: dialogState.selectedSection == _StripePlanSection.outros
            ? 'billingPlanKey completo'
            : 'Identificador do plano (sem prefixo)',
        hintText: dialogState.selectedSection == _StripePlanSection.outros
            ? 'ex.: extra_orders_pack_1000'
            : 'ex.: base | pro | custom',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripePlanDisplayNameField(
    _StripePlanMappingDialogState dialogState,
  ) {
    return TextField(
      controller: dialogState.planDisplayNameController,
      decoration: const InputDecoration(
        labelText: 'Nome do plano (exibição)',
        hintText: 'Ex.: Starter, Pro, Enterprise',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripePlanDisplayAmountField(
    _StripePlanMappingDialogState dialogState,
  ) {
    return TextField(
      controller: dialogState.planDisplayAmountController,
      decoration: const InputDecoration(
        labelText: 'Valor do plano (exibição)',
        hintText: 'Ex.: R\$ 50.00 / month x1',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeMappingTypeField({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: dialogState.mappingType,
      decoration: const InputDecoration(
        labelText: 'Tipo',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'base', child: Text('base')),
        DropdownMenuItem(value: 'overage', child: Text('overage')),
      ],
      onChanged: (value) {
        setLocalState(() {
          dialogState.mappingType = (value ?? 'base').trim();
        });
      },
    );
  }

  Widget _buildStripeProductIdField(_StripePlanMappingDialogState dialogState) {
    return TextField(
      controller: dialogState.productIdController,
      decoration: const InputDecoration(
        labelText: 'Stripe Product ID',
        hintText: 'prod_...',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripePriceIdField(_StripePlanMappingDialogState dialogState) {
    return TextField(
      controller: dialogState.priceIdController,
      decoration: const InputDecoration(
        labelText: 'Stripe Price ID',
        hintText: 'price_...',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeOverageMetricField(
    _StripePlanMappingDialogState dialogState,
  ) {
    return TextField(
      controller: dialogState.overageMetricController,
      decoration: const InputDecoration(
        labelText: 'Métrica de excedente (opcional)',
        hintText: 'extra_representada | extra_usuario',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeActiveSwitch({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return SwitchListTile.adaptive(
      value: dialogState.active,
      contentPadding: EdgeInsets.zero,
      title: const Text('Mapeamento ativo'),
      onChanged: (value) {
        setLocalState(() {
          dialogState.active = value;
        });
      },
    );
  }

  Widget _buildStripeDialogErrorText(
    _StripePlanMappingDialogState dialogState,
  ) {
    if (dialogState.errorText == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        dialogState.errorText!,
        style: const TextStyle(color: Color(0xFFB3261E)),
      ),
    );
  }
}
