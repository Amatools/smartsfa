part of 'web_portal_page.dart';

Future<void> _openWorkspaceProfileEditor(
  BuildContext context,
  TenantEntryOption activeTenant,
  Map<String, dynamic> workspaceData,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _WorkspaceProfileEditorDialog(
      activeTenant: activeTenant,
      workspaceData: workspaceData,
    ),
  );

  if (result != true || !context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Dados do workspace atualizados com sucesso.'),
    ),
  );
}

bool _canEditWorkspaceProfile({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'brand_owner_workspace') {
    return normalizedRole == 'owner';
  }

  if (normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  return normalizedRole == 'vendedor';
}

bool _canEditRepresentedModuleSettings({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'seller_solo_workspace' ||
      normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  if (normalizedWorkspaceType == 'brand_owner_workspace') {
    return normalizedRole == 'owner';
  }

  return false;
}

Widget _ownerOnlyReadOnlyNotice(
  BuildContext context, {
  required String message,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

bool _featureFlagEnabled(
  Map<String, dynamic> workspaceData,
  String key, {
  String? legacyField,
}) {
  final flags = workspaceData['featureFlags'];
  if (flags is Map) {
    final raw = flags[key];
    if (raw is bool) {
      return raw;
    }
  }

  if (legacyField != null) {
    return workspaceData[legacyField] == true;
  }

  return false;
}

String _workspacePlanTier(Map<String, dynamic> workspaceData) {
  final raw = (workspaceData['planTier'] ?? '').toString().trim().toLowerCase();
  if (raw == _planTierUpgrade) {
    return _planTierUpgrade;
  }
  return _planTierBase;
}

bool _isFeatureAvailableByPlan({
  required String workspaceType,
  required String planTier,
  required String featureKey,
}) {
  final byWorkspace = _workspacePlanFeatureMatrix[workspaceType.trim()];
  if (byWorkspace == null) {
    return false;
  }
  final byTier = byWorkspace[planTier.trim().toLowerCase()];
  if (byTier == null) {
    return false;
  }
  return byTier.contains(featureKey);
}

String _planBaseLabelFromWorkspaceType(String workspaceType) {
  switch (workspaceType.trim()) {
    case 'seller_solo_workspace':
      return 'Individual';
    case 'rep_workspace':
      return 'Representações';
    case 'brand_owner_workspace':
      return 'Enterprise';
    default:
      return 'Plano desconhecido';
  }
}

bool _canManageRepresentedCompanies({
  required String role,
  required String workspaceType,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedWorkspaceType = workspaceType.trim();

  if (normalizedWorkspaceType == 'brand_owner_workspace') {
    return false;
  }

  if (normalizedWorkspaceType == 'seller_solo_workspace') {
    return normalizedRole == 'owner' ||
        normalizedRole == 'gerente' ||
        normalizedRole == 'representante' ||
        normalizedRole == 'vendedor';
  }

  if (normalizedWorkspaceType == 'rep_workspace') {
    return normalizedRole == 'owner';
  }

  return false;
}

List<_WorkspaceInfoItem> _buildWorkspaceInfoItems({
  required TenantEntryOption activeTenant,
  required AccountContractLock accountContractLock,
  required Map<String, dynamic> workspaceData,
}) {
  final items = <_WorkspaceInfoItem>[
    _WorkspaceInfoItem(
      label: 'Tipo de conta',
      value: _accountContractLockLabel(accountContractLock),
    ),
    _WorkspaceInfoItem(
      label: 'Workspace',
      value: _workspaceTypeLabel(activeTenant.workspaceType),
    ),
    _WorkspaceInfoItem(
      label: 'Seu acesso atual',
      value: _roleLabel(
        activeTenant.role,
        activeTenant.workspaceType,
        activeTenant.tenantName,
      ),
    ),
    _WorkspaceInfoItem(
      label: 'Identificador interno',
      value: activeTenant.tenantId,
    ),
  ];

  void addEditable(String label, String key) {
    items.add(
      _WorkspaceInfoItem(
        label: label,
        value: (workspaceData[key] ?? '').toString(),
      ),
    );
  }

  void addReadonly(String label, String value) {
    items.add(_WorkspaceInfoItem(label: label, value: value));
  }

  if (activeTenant.workspaceType == 'brand_owner_workspace') {
    addReadonly(
      'Razão social',
      (workspaceData['razaoSocial'] ?? '').toString(),
    );
    addReadonly('CNPJ', (workspaceData['cnpj'] ?? '').toString());
    addEditable('Nome exibido no SaaS', 'nomeFantasia');
    addEditable('Responsável principal', 'contatoResponsavel');
    addEditable('Telefone comercial', 'telefoneComercial');
    addEditable('E-mail comercial', 'emailComercial');
    addReadonly(
      'Regime tributário',
      _taxRegimeLabel(workspaceData['taxRegime']),
    );
    addEditable('Website', 'website');
    addEditable('Logradouro', 'logradouro');
    addEditable('Número', 'numero');
    addEditable('Complemento', 'complemento');
    addEditable('Bairro', 'bairro');
    addEditable('CEP', 'cep');
    addEditable('Cidade', 'cidade');
    addEditable('UF', 'uf');
    return items;
  }

  if (activeTenant.workspaceType == 'rep_workspace') {
    addReadonly(
      'Documento informado no cadastro',
      (workspaceData['representedCompanyDocument'] ?? '').toString(),
    );
    addEditable('Nome exibido no SaaS', 'nomeFantasia');
    addEditable('Responsável principal', 'contatoResponsavel');
    addEditable('Telefone comercial', 'telefoneComercial');
    addEditable('E-mail comercial', 'emailComercial');
    addEditable('Região de atuação', 'regiaoAtuacao');
    addEditable('Marcas representadas', 'marcasRepresentadas');
    addEditable('Cidade', 'cidade');
    addEditable('UF', 'uf');
    return items;
  }

  addEditable('Nome exibido no SaaS', 'nomeFantasia');
  addEditable('Nome profissional', 'contatoResponsavel');
  addEditable('Telefone', 'telefoneComercial');
  addEditable('E-mail de contato', 'emailComercial');
  addEditable('Segmento', 'segmento');
  addEditable('Cidade', 'cidade');
  addEditable('UF', 'uf');
  return items;
}

class _WorkspaceInfoItem {
  const _WorkspaceInfoItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _WorkspaceInfoGrid extends StatelessWidget {
  const _WorkspaceInfoGrid({required this.items});

  final List<_WorkspaceInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        final rows = <List<_WorkspaceInfoItem>>[];

        for (var index = 0; index < items.length; index += columns) {
          final end = (index + columns) > items.length
              ? items.length
              : (index + columns);
          rows.add(items.sublist(index, end));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < row.length; index++) ...[
                        Expanded(child: _WorkspaceInfoText(item: row[index])),
                        if (index < row.length - 1) const SizedBox(width: 24),
                      ],
                      if (row.length < columns)
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _WorkspaceInfoText extends StatelessWidget {
  const _WorkspaceInfoText({required this.item});

  final _WorkspaceInfoItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          item.value.isEmpty ? 'Não informado' : item.value,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _WorkspaceProfileEditorDialog extends StatefulWidget {
  const _WorkspaceProfileEditorDialog({
    required this.activeTenant,
    required this.workspaceData,
  });

  final TenantEntryOption activeTenant;
  final Map<String, dynamic> workspaceData;

  @override
  State<_WorkspaceProfileEditorDialog> createState() =>
      _WorkspaceProfileEditorDialogState();
}

class _WorkspaceProfileEditorDialogState
    extends State<_WorkspaceProfileEditorDialog> {
  late final TextEditingController _nomeFantasiaController;
  late final TextEditingController _contatoResponsavelController;
  late final TextEditingController _telefoneComercialController;
  late final TextEditingController _emailComercialController;
  late final TextEditingController _websiteController;
  late final TextEditingController _segmentoController;
  late final TextEditingController _regiaoAtuacaoController;
  late final TextEditingController _marcasRepresentadasController;
  late final TextEditingController _logradouroController;
  late final TextEditingController _numeroController;
  late final TextEditingController _complementoController;
  late final TextEditingController _bairroController;
  late final TextEditingController _cepController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _ufController;
  late String _taxRegime;
  bool _saving = false;
  bool _buscandoCep = false;

  @override
  void initState() {
    super.initState();
    final data = widget.workspaceData;
    _nomeFantasiaController = TextEditingController(
      text: (data['nomeFantasia'] ?? '').toString(),
    );
    _contatoResponsavelController = TextEditingController(
      text: (data['contatoResponsavel'] ?? '').toString(),
    );
    _telefoneComercialController = TextEditingController(
      text: (data['telefoneComercial'] ?? '').toString(),
    );
    _emailComercialController = TextEditingController(
      text: (data['emailComercial'] ?? '').toString(),
    );
    _websiteController = TextEditingController(
      text: (data['website'] ?? '').toString(),
    );
    _segmentoController = TextEditingController(
      text: (data['segmento'] ?? '').toString(),
    );
    _regiaoAtuacaoController = TextEditingController(
      text: (data['regiaoAtuacao'] ?? '').toString(),
    );
    _marcasRepresentadasController = TextEditingController(
      text: (data['marcasRepresentadas'] ?? '').toString(),
    );
    _logradouroController = TextEditingController(
      text: (data['logradouro'] ?? '').toString(),
    );
    _numeroController = TextEditingController(
      text: (data['numero'] ?? '').toString(),
    );
    _complementoController = TextEditingController(
      text: (data['complemento'] ?? '').toString(),
    );
    _bairroController = TextEditingController(
      text: (data['bairro'] ?? '').toString(),
    );
    _cepController = TextEditingController(
      text: (data['cep'] ?? '').toString(),
    );
    _cidadeController = TextEditingController(
      text: (data['cidade'] ?? '').toString(),
    );
    _ufController = TextEditingController(text: (data['uf'] ?? '').toString());
    _taxRegime = _normalizeTaxRegimeValue(data['taxRegime']);
    if (_taxRegime.isEmpty) {
      _taxRegime = _defaultTaxRegime;
    }
  }

  @override
  void dispose() {
    _nomeFantasiaController.dispose();
    _contatoResponsavelController.dispose();
    _telefoneComercialController.dispose();
    _emailComercialController.dispose();
    _websiteController.dispose();
    _segmentoController.dispose();
    _regiaoAtuacaoController.dispose();
    _marcasRepresentadasController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cepController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnterprise =
        widget.activeTenant.workspaceType == 'brand_owner_workspace';
    final isRep = widget.activeTenant.workspaceType == 'rep_workspace';
    const dialogChromeColor = Color(0xFFF5F6F8);
    const dialogBodyColor = Colors.white;
    const dialogBorderColor = Color(0xFFE3E6EA);
    const dialogFocusedBorderColor = Color(0xFFD0D6DE);

    InputDecoration dialogInputDecoration() {
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: dialogBodyColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dialogBorderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dialogBorderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: dialogFocusedBorderColor,
            width: 1,
          ),
        ),
      );
    }

    Widget field(
      TextEditingController controller,
      String label, {
      TextInputType? keyboardType,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: dialogInputDecoration(),
          ),
        ],
      );
    }

    Widget ufField() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UF', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_ufController.text),
            initialValue: brazilStateOrNull(_ufController.text),
            isExpanded: true,
            decoration: dialogInputDecoration(),
            items: brazilStates
                .map(
                  (uf) => DropdownMenuItem<String>(value: uf, child: Text(uf)),
                )
                .toList(growable: false),
            onChanged: (value) {
              _ufController.text = (value ?? '').trim();
            },
          ),
        ],
      );
    }

    Widget taxRegimeField() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Regime tributário',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_taxRegime),
            initialValue: _taxRegime,
            isExpanded: true,
            decoration: dialogInputDecoration(),
            items: _taxRegimeOptions
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(_taxRegimeLabel(value)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              setState(() {
                final normalized = _normalizeTaxRegimeValue(value);
                _taxRegime = normalized.isEmpty
                    ? _defaultTaxRegime
                    : normalized;
              });
            },
          ),
        ],
      );
    }

    final maxDialogHeight = MediaQuery.sizeOf(context).height - 36;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxDialogHeight),
        child: Container(
          decoration: BoxDecoration(
            color: dialogBodyColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dialogBorderColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: dialogChromeColor,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Text(
                  'Editar dados do workspace',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: Container(
                  color: dialogBodyColor,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        field(_nomeFantasiaController, 'Nome exibido no SaaS'),
                        const SizedBox(height: 12),
                        field(
                          _contatoResponsavelController,
                          'Responsável principal',
                        ),
                        const SizedBox(height: 12),
                        field(
                          _telefoneComercialController,
                          'Telefone comercial',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        field(
                          _emailComercialController,
                          'E-mail comercial',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        if (isEnterprise) ...[
                          const SizedBox(height: 12),
                          taxRegimeField(),
                          const SizedBox(height: 12),
                          field(_websiteController, 'Website'),
                          const SizedBox(height: 12),
                          field(_logradouroController, 'Logradouro'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: field(_numeroController, 'Número'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: field(
                                  _complementoController,
                                  'Complemento',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          field(_bairroController, 'Bairro'),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: field(
                                  _cepController,
                                  'CEP',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 48,
                                child: FilledButton.tonalIcon(
                                  onPressed: _saving || _buscandoCep
                                      ? null
                                      : _buscarCep,
                                  icon: _buscandoCep
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search_outlined),
                                  label: Text(
                                    _buscandoCep ? 'Buscando...' : 'Buscar CEP',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: field(_cidadeController, 'Cidade'),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: 100, child: ufField()),
                            ],
                          ),
                        ] else if (isRep) ...[
                          const SizedBox(height: 12),
                          field(_regiaoAtuacaoController, 'Região de atuação'),
                          const SizedBox(height: 12),
                          field(
                            _marcasRepresentadasController,
                            'Marcas representadas',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: field(_cidadeController, 'Cidade'),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: 100, child: ufField()),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          field(_segmentoController, 'Segmento'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: field(_cidadeController, 'Cidade'),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: 100, child: ufField()),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                color: dialogChromeColor,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Salvando...' : 'Salvar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    try {
      await WorkspaceProfileService(FirebaseFirestore.instance)
          .updateWorkspaceProfile(
            tenantId: widget.activeTenant.tenantId,
            workspaceType: widget.activeTenant.workspaceType,
            values: {
              'nomeFantasia': _nomeFantasiaController.text,
              'contatoResponsavel': _contatoResponsavelController.text,
              'telefoneComercial': _telefoneComercialController.text,
              'emailComercial': _emailComercialController.text,
              'website': _websiteController.text,
              'segmento': _segmentoController.text,
              'regiaoAtuacao': _regiaoAtuacaoController.text,
              'marcasRepresentadas': _marcasRepresentadasController.text,
              'logradouro': _logradouroController.text,
              'numero': _numeroController.text,
              'complemento': _complementoController.text,
              'bairro': _bairroController.text,
              'cep': _cepController.text,
              'cidade': _cidadeController.text,
              'uf': _ufController.text.toUpperCase(),
              'taxRegime': _taxRegime,
            },
          );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar dados do workspace: $error')),
      );
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _buscarCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um CEP válido com 8 dígitos.')),
      );
      return;
    }

    setState(() {
      _buscandoCep = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      );

      if (response.statusCode != 200) {
        throw Exception('cep_error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }

      _logradouroController.text = (data['street'] ?? '').toString();
      _bairroController.text = (data['neighborhood'] ?? '').toString();
      _cidadeController.text = (data['city'] ?? '').toString();
      final state = (data['state'] ?? '').toString().trim().toUpperCase();
      _ufController.text = brazilStateOrNull(state) ?? '';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Endereço preenchido automaticamente pelo CEP.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível buscar esse CEP no momento.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _buscandoCep = false;
        });
      }
    }
  }
}
