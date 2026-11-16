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
        _buildStripeAddonToggleField(
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
        if (dialogState.isAddonMapping) ...[
          const SizedBox(height: 12),
          _buildStripeOverageMetricField(dialogState),
          const SizedBox(height: 12),
          _buildStripeLinkedBasePlanKeySelectorField(
            dialogState: dialogState,
            setLocalState: setLocalState,
          ),
        ] else ...[
          const SizedBox(height: 12),
          _buildStripeIncludedSeatsField(dialogState),
          const SizedBox(height: 12),
          _buildStripeSeatAddonPlanKeyField(dialogState),
        ],
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
        helperText: dialogState.isAddonMapping
            ? 'Quando aditivo, a sugestao usa o plano base selecionado (ex.: extra_usuario).'
            : null,
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

  Widget _buildStripeAddonToggleField({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    return SwitchListTile.adaptive(
      value: dialogState.isAddonMapping,
      contentPadding: EdgeInsets.zero,
      title: const Text('Este plano e aditivo?'),
      subtitle: Text(
        dialogState.isAddonMapping
            ? 'Aditivo: exige plano base vinculado e usa metrica de excedente.'
            : 'Plano normal/base: pode informar seats inclusos e addon de seats.',
      ),
      onChanged: (value) {
        setLocalState(() {
          dialogState.mappingType = value ? 'overage' : 'base';

          if (dialogState.isAddonMapping &&
              dialogState.overageMetricController.text.trim().isEmpty) {
            dialogState.overageMetricController.text = 'extra_usuario';
          }

          if (dialogState.isAddonMapping &&
              dialogState.linkedBasePlanKeyController.text.trim().isEmpty &&
              dialogState.basePlanOptions.isNotEmpty) {
            dialogState.linkedBasePlanKeyController.text =
                dialogState.basePlanOptions.first.billingPlanKey;
          }

          if (dialogState.isAddonMapping) {
            _maybeApplyAddonPlanSlugSuggestion(
              dialogState,
              linkedBasePlanKey: dialogState.linkedBasePlanKeyController.text,
            );
          }

          if (!dialogState.isAddonMapping) {
            dialogState.linkedBasePlanKeyController.clear();
            dialogState.overageMetricController.clear();
          }
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

  Widget _buildStripeIncludedSeatsField(
    _StripePlanMappingDialogState dialogState,
  ) {
    final isBase = dialogState.mappingType.trim().toLowerCase() == 'base';
    return TextField(
      controller: dialogState.includedSeatsController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Seats incluidos no plano',
        hintText: isBase ? 'Ex.: 1, 2, 3' : 'Opcional para overage',
        helperText: isBase
            ? 'Usado como capacidade base da assinatura no tenant.'
            : 'Normalmente deixe vazio para mapeamentos overage.',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeSeatAddonPlanKeyField(
    _StripePlanMappingDialogState dialogState,
  ) {
    return TextField(
      controller: dialogState.seatAddonPlanKeyController,
      decoration: const InputDecoration(
        labelText: 'billingPlanKey do adicional de seats',
        hintText: 'Ex.: representacoes_extra_usuario',
        helperText: 'No plano base, informe o billingPlanKey do mapeamento overage de usuarios.',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStripeLinkedBasePlanKeySelectorField({
    required _StripePlanMappingDialogState dialogState,
    required StateSetter setLocalState,
  }) {
    final currentBaseKey = dialogState.linkedBasePlanKeyController.text
        .trim()
        .toLowerCase();
    final options = dialogState.basePlanOptions;

    if (options.isEmpty) {
      return TextField(
        controller: dialogState.linkedBasePlanKeyController,
        onChanged: (value) {
          setLocalState(() {
            _maybeApplyAddonPlanSlugSuggestion(
              dialogState,
              linkedBasePlanKey: value,
            );
          });
        },
        decoration: const InputDecoration(
          labelText: 'Plano base vinculado (obrigatorio para aditivo)',
          hintText: 'Ex.: representacoes_base',
          helperText: 'Nenhum plano base encontrado nesta secao. Informe o billingPlanKey manualmente.',
          border: OutlineInputBorder(),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: currentBaseKey.isEmpty ? null : currentBaseKey,
      decoration: const InputDecoration(
        labelText: 'Plano base vinculado (obrigatorio para aditivo)',
        border: OutlineInputBorder(),
        helperText: 'Selecione o plano base ao qual este aditivo pertence para reconciliar quantity de seats extras.',
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.billingPlanKey,
              child: Text(option.displayLabel),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setLocalState(() {
          dialogState.linkedBasePlanKeyController.text = (value ?? '')
              .trim()
              .toLowerCase();
          _maybeApplyAddonPlanSlugSuggestion(
            dialogState,
            linkedBasePlanKey: dialogState.linkedBasePlanKeyController.text,
          );
        });
      },
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
