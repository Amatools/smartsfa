import 'package:flutter/material.dart';

import '../../../../core/constants/brazil_states.dart';
import '../../../../core/diagnostics/app_diagnostics.dart';
import '../../../../core/diagnostics/error_dialog.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/cliente.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/services/offline_sync_queue.dart';

class ClienteDetailPage extends StatefulWidget {
  const ClienteDetailPage({
    super.key,
    required this.cliente,
    required this.repository,
    required this.identity,
  });

  final Cliente cliente;
  final ClienteRepository repository;
  final AppIdentity identity;

  @override
  State<ClienteDetailPage> createState() => _ClienteDetailPageState();
}

class _ClienteDetailPageState extends State<ClienteDetailPage> {
  static const Color _formChromeColor = Color(0xFFF5F6F8);
  static const Color _formBodyColor = Colors.white;
  static const Color _formBorderColor = Color(0xFFE3E6EA);
  static const Color _formFocusedBorderColor = Color(0xFFD0D6DE);

  late final TextEditingController _nomeController;
  late final TextEditingController _nomeFantasiaController;
  late final TextEditingController _documentoController;
  late final TextEditingController _emailController;
  late final TextEditingController _emailFinanceiroController;
  late final TextEditingController _celularController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _cepController;
  late final TextEditingController _logradouroController;
  late final TextEditingController _numeroController;
  late final TextEditingController _complementoController;
  late final TextEditingController _bairroController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _estadoController;
  late final TextEditingController _paisController;
  late final TextEditingController _inscricaoEstadualController;
  late final TextEditingController _inscricaoMunicipalController;
  late final TextEditingController _observacoesController;

  late String _tipoPessoa;
  late SalePurpose _salePurpose;
  late CustomerTaxProfile _taxProfile;
  late String _taxRegime;
  late bool _isZfmSuframa;
  late Cliente _cliente;
  bool _isEditing = false;
  bool _saving = false;

  /// A cliente created from an ERP integration (e.g. Sankhya) is owned by
  /// that system: the ERP is the source of truth, so the app must never
  /// delete or inactivate it locally.
  bool get _isErpManaged => _cliente.origemCadastro == CustomerOrigin.erp;

  /// Lifecycle actions (excluir/inativar) are destructive and, once a real
  /// tenant is involved, are restricted to the tenant owner (or a platform
  /// admin) — never a gerente/representante/vendedor. In a personal
  /// workspace there is no hierarchy, so the sole user is effectively the
  /// owner.
  bool get _canManageLifecycle {
    if (_isErpManaged) {
      return false;
    }
    if (widget.identity.isPersonalWorkspace) {
      return true;
    }
    const allowedRoles = {'owner', 'platform_admin'};
    return allowedRoles.contains(widget.identity.role.trim().toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    final cliente = widget.cliente;
    _nomeController = TextEditingController(text: cliente.nome);
    _nomeFantasiaController = TextEditingController(text: cliente.nomeFantasia);
    _documentoController = TextEditingController(text: cliente.documento);
    _emailController = TextEditingController(text: cliente.email);
    _emailFinanceiroController = TextEditingController(
      text: cliente.emailFinanceiro,
    );
    _celularController = TextEditingController(text: cliente.celular);
    _telefoneController = TextEditingController(text: cliente.telefone);
    _cepController = TextEditingController(text: cliente.cep);
    _logradouroController = TextEditingController(text: cliente.logradouro);
    _numeroController = TextEditingController(text: cliente.numero);
    _complementoController = TextEditingController(text: cliente.complemento);
    _bairroController = TextEditingController(text: cliente.bairro);
    _cidadeController = TextEditingController(text: cliente.cidade);
    _estadoController = TextEditingController(text: cliente.estado);
    _paisController = TextEditingController(text: cliente.pais);
    _inscricaoEstadualController = TextEditingController(
      text: cliente.inscricaoEstadual,
    );
    _inscricaoMunicipalController = TextEditingController(
      text: cliente.inscricaoMunicipal,
    );
    _observacoesController = TextEditingController(text: cliente.observacoes);
    _tipoPessoa = cliente.tipoPessoa;
    _salePurpose = cliente.salePurpose;
    _taxProfile = cliente.taxProfile;
    _taxRegime = isValidTaxRegimeValue(cliente.taxRegime)
        ? normalizeTaxRegimeValue(cliente.taxRegime)
        : defaultTaxRegime;
    _isZfmSuframa = cliente.isZfmSuframa;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _nomeFantasiaController.dispose();
    _documentoController.dispose();
    _emailController.dispose();
    _emailFinanceiroController.dispose();
    _celularController.dispose();
    _telefoneController.dispose();
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _paisController.dispose();
    _inscricaoEstadualController.dispose();
    _inscricaoMunicipalController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nome = _nomeController.text.trim();
    final documento = _documentoController.text.trim();
    if (nome.isEmpty || documento.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome e documento são obrigatórios.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final updated = _cliente.copyWith(
        nome: nome,
        documento: documento,
        tipoPessoa: _tipoPessoa,
        nomeFantasia: _nomeFantasiaController.text.trim(),
        email: _emailController.text.trim(),
        emailFinanceiro: _emailFinanceiroController.text.trim(),
        canal: _cliente.canal,
        celular: _celularController.text.trim(),
        telefone: _telefoneController.text.trim(),
        cep: _cepController.text.trim(),
        logradouro: _logradouroController.text.trim(),
        numero: _numeroController.text.trim(),
        complemento: _complementoController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        estado: _estadoController.text.trim(),
        pais: _paisController.text.trim(),
        inscricaoEstadual: _inscricaoEstadualController.text.trim(),
        inscricaoMunicipal: _inscricaoMunicipalController.text.trim(),
        salePurpose: _salePurpose,
        taxProfile: _taxProfile,
        taxRegime: _taxRegime,
        isZfmSuframa: _isZfmSuframa,
        observacoes: _observacoesController.text.trim(),
        updatedAt: now,
      );

      await OfflineSyncQueue.enqueue(
        type: 'cliente',
        tenantId: updated.tenantId,
        payload: updated.toMap(),
      );
      await widget.repository.save(updated);
      await OfflineSyncQueue.markSynced(updated.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _cliente = updated;
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro do cliente atualizado.')),
      );
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'cliente.update',
        message: 'Falha ao atualizar cliente ${_cliente.nome}.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      await showAppErrorDialog(
        context,
        title: 'Não foi possível salvar o cliente',
        error: error,
        stackTrace: stackTrace,
        tag: 'cliente.update',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Toggles between "aprovado" (active) and "inativo", used for a soft
  /// deactivation that keeps the record around for history/audit instead of
  /// deleting it outright.
  Future<void> _toggleActive() async {
    final now = DateTime.now();
    final goingInactive = _cliente.status != CustomerStatus.inactive;
    final updated = _cliente.copyWith(
      status: goingInactive ? CustomerStatus.inactive : CustomerStatus.approved,
      updatedAt: now,
    );

    setState(() => _saving = true);

    await OfflineSyncQueue.enqueue(
      type: 'cliente',
      tenantId: updated.tenantId,
      payload: updated.toMap(),
    );
    try {
      await widget.repository.save(updated);
      await OfflineSyncQueue.markSynced(updated.id);
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'cliente.toggle_active',
        message: 'Falha ao sincronizar status de ${_cliente.nome}.',
        error: error,
        stackTrace: stackTrace,
      );
      // keep unsynced locally; a later sync pass will retry.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _cliente = updated;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          goingInactive ? 'Cliente inativado.' : 'Cliente reativado.',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir cliente'),
            content: Text(
              'Tem certeza que deseja excluir "${_cliente.nome}"? Esta ação não pode ser desfeita.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() => _saving = true);

    // Local-first: always drop it from the on-device queue first so it
    // disappears immediately regardless of connectivity, and record a
    // tombstone so the clientes list's live Firestore stream never shows it
    // again just because the best-effort remote delete below hasn't
    // completed yet (or fails).
    await OfflineSyncQueue.markDeleted(
      type: 'cliente',
      tenantId: _cliente.tenantId,
      id: _cliente.id,
    );

    try {
      await widget.repository.delete(
        tenantId: _cliente.tenantId,
        id: _cliente.id,
      );
      await OfflineSyncQueue.clearTombstone(_cliente.id);
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'cliente.delete',
        message:
            'Falha ao excluir cliente ${_cliente.nome} remotamente; tentativa será repetida na próxima sincronização.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  InputDecoration _formInputDecoration() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _formBodyColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _formBorderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _formBorderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _formFocusedBorderColor, width: 1),
      ),
    );
  }

  Widget _buildLabeledField({
    required BuildContext context,
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildSectionContainer({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _formBodyColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _formBorderColor, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveFieldGrid(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final hasTwoColumns = constraints.maxWidth >= 920;
        final itemWidth = hasTwoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final field in fields)
              SizedBox(width: itemWidth, child: field),
          ],
        );
      },
    );
  }

  Widget _buildReadOnlyField(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _formBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlySection(
    BuildContext context,
    String title,
    Map<String, String> fields,
  ) {
    return _buildSectionContainer(
      context: context,
      title: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final hasTwoColumns = constraints.maxWidth >= 900;
          final itemWidth = hasTwoColumns
              ? (constraints.maxWidth - spacing) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final entry in fields.entries)
                SizedBox(
                  width: itemWidth,
                  child: _buildReadOnlyField(context, entry.key, entry.value),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cliente = _cliente;

    return Scaffold(
      appBar: AppBar(
        title: Text(cliente.nome),
        actions: [
          if (!_isEditing)
            IconButton(
              tooltip: 'Editar cadastro',
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (_isEditing)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _isEditing = false),
              child: const Text('Cancelar'),
            ),
          if (!_isEditing && _canManageLifecycle)
            PopupMenuButton<String>(
              enabled: !_saving,
              onSelected: (value) {
                if (value == 'toggle_active') {
                  _toggleActive();
                } else if (value == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_active',
                  child: Text(
                    cliente.status == CustomerStatus.inactive
                        ? 'Reativar cliente'
                        : 'Inativar cliente',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Excluir cliente'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = constraints.maxWidth >= 1460
                ? 1280.0
                : 1160.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _formBodyColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _formBorderColor, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: _formChromeColor,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isEditing
                                      ? 'Editar cadastro do cliente'
                                      : 'Dados do cliente',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Visualização e manutenção do cadastro comercial.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: _isEditing
                                ? Form(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSectionContainer(
                                          context: context,
                                          title: 'Identificação',
                                          child: _buildResponsiveFieldGrid([
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Nome / razão social',
                                              child: TextFormField(
                                                controller: _nomeController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Nome fantasia',
                                              child: TextFormField(
                                                controller:
                                                    _nomeFantasiaController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Tipo de pessoa',
                                              child:
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    initialValue: _tipoPessoa,
                                                    items: const [
                                                      DropdownMenuItem(
                                                        value: 'pj',
                                                        child: Text(
                                                          'Pessoa jurídica',
                                                        ),
                                                      ),
                                                      DropdownMenuItem(
                                                        value: 'pf',
                                                        child: Text(
                                                          'Pessoa física',
                                                        ),
                                                      ),
                                                    ],
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(
                                                          () => _tipoPessoa =
                                                              value,
                                                        );
                                                      }
                                                    },
                                                    decoration:
                                                        _formInputDecoration(),
                                                  ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'CPF / CNPJ',
                                              child: TextFormField(
                                                controller:
                                                    _documentoController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Finalidade da venda',
                                              child:
                                                  DropdownButtonFormField<
                                                    SalePurpose
                                                  >(
                                                    initialValue: _salePurpose,
                                                    items: SalePurpose.values
                                                        .map(
                                                          (item) =>
                                                              DropdownMenuItem<
                                                                SalePurpose
                                                              >(
                                                                value: item,
                                                                child: Text(
                                                                  item.label,
                                                                ),
                                                              ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(
                                                          () => _salePurpose =
                                                              value,
                                                        );
                                                      }
                                                    },
                                                    decoration:
                                                        _formInputDecoration(),
                                                  ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Perfil fiscal do cliente',
                                              child:
                                                  DropdownButtonFormField<
                                                    CustomerTaxProfile
                                                  >(
                                                    initialValue: _taxProfile,
                                                    items: CustomerTaxProfile
                                                        .values
                                                        .map(
                                                          (item) =>
                                                              DropdownMenuItem<
                                                                CustomerTaxProfile
                                                              >(
                                                                value: item,
                                                                child: Text(
                                                                  item.label,
                                                                ),
                                                              ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(
                                                          () => _taxProfile =
                                                              value,
                                                        );
                                                      }
                                                    },
                                                    decoration:
                                                        _formInputDecoration(),
                                                  ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Regime tributário',
                                              child: DropdownButtonFormField<String>(
                                                initialValue: _taxRegime,
                                                items: taxRegimeValues
                                                    .map(
                                                      (item) =>
                                                          DropdownMenuItem<
                                                            String
                                                          >(
                                                            value: item,
                                                            child: Text(
                                                              taxRegimeLabel(
                                                                item,
                                                              ),
                                                            ),
                                                          ),
                                                    )
                                                    .toList(growable: false),
                                                onChanged: (value) {
                                                  if (value != null) {
                                                    setState(
                                                      () => _taxRegime =
                                                          normalizeTaxRegimeValue(
                                                            value,
                                                          ),
                                                    );
                                                  }
                                                },
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Zona Franca / SUFRAMA',
                                              child: Material(
                                                color: Colors.transparent,
                                                child: CheckboxListTile(
                                                  value: _isZfmSuframa,
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  controlAffinity:
                                                      ListTileControlAffinity
                                                          .leading,
                                                  title: const Text(
                                                    'Cliente enquadrado em ZFM-SUFRAMA',
                                                  ),
                                                  onChanged: (value) {
                                                    setState(
                                                      () => _isZfmSuframa =
                                                          value ?? false,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Inscrição estadual',
                                              child: TextFormField(
                                                controller:
                                                    _inscricaoEstadualController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Inscrição municipal',
                                              child: TextFormField(
                                                controller:
                                                    _inscricaoMunicipalController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                          ]),
                                        ),
                                        _buildSectionContainer(
                                          context: context,
                                          title: 'Contato',
                                          child: _buildResponsiveFieldGrid([
                                            _buildLabeledField(
                                              context: context,
                                              label: 'E-mail',
                                              child: TextFormField(
                                                controller: _emailController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'E-mail financeiro',
                                              child: TextFormField(
                                                controller:
                                                    _emailFinanceiroController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Celular',
                                              child: TextFormField(
                                                controller: _celularController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Telefone',
                                              child: TextFormField(
                                                controller: _telefoneController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                          ]),
                                        ),
                                        _buildSectionContainer(
                                          context: context,
                                          title: 'Endereço',
                                          child: _buildResponsiveFieldGrid([
                                            _buildLabeledField(
                                              context: context,
                                              label: 'CEP',
                                              child: TextFormField(
                                                controller: _cepController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Logradouro',
                                              child: TextFormField(
                                                controller:
                                                    _logradouroController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Número',
                                              child: TextFormField(
                                                controller: _numeroController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Complemento',
                                              child: TextFormField(
                                                controller:
                                                    _complementoController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Bairro',
                                              child: TextFormField(
                                                controller: _bairroController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'Cidade',
                                              child: TextFormField(
                                                controller: _cidadeController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'UF',
                                              child:
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    key: ValueKey<String>(
                                                      _estadoController.text,
                                                    ),
                                                    initialValue:
                                                        brazilStateOrNull(
                                                          _estadoController
                                                              .text,
                                                        ),
                                                    items: brazilStates
                                                        .map(
                                                          (uf) =>
                                                              DropdownMenuItem<
                                                                String
                                                              >(
                                                                value: uf,
                                                                child: Text(uf),
                                                              ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                    onChanged: (value) {
                                                      _estadoController.text =
                                                          (value ?? '').trim();
                                                    },
                                                    decoration:
                                                        _formInputDecoration(),
                                                  ),
                                            ),
                                            _buildLabeledField(
                                              context: context,
                                              label: 'País',
                                              child: TextFormField(
                                                controller: _paisController,
                                                decoration:
                                                    _formInputDecoration(),
                                              ),
                                            ),
                                          ]),
                                        ),
                                        _buildSectionContainer(
                                          context: context,
                                          title: 'Cadastro',
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _buildReadOnlyField(
                                                context,
                                                'Canal (origem do cadastro)',
                                                _cliente.canal,
                                              ),
                                              const SizedBox(height: 14),
                                              _buildLabeledField(
                                                context: context,
                                                label: 'Observações',
                                                child: TextFormField(
                                                  controller:
                                                      _observacoesController,
                                                  minLines: 3,
                                                  maxLines: 5,
                                                  decoration:
                                                      _formInputDecoration(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: _saving ? null : _save,
                                            icon: _saving
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.save_outlined,
                                                  ),
                                            label: Text(
                                              _saving
                                                  ? 'Salvando...'
                                                  : 'Salvar alterações',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _StatusChip(
                                            label: cliente.status.label,
                                            color: Colors.blueGrey.shade100,
                                          ),
                                          _StatusChip(
                                            label: cliente.origemCadastro.label,
                                            color: Colors.green.shade100,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      _buildReadOnlySection(
                                        context,
                                        'Identificação',
                                        {
                                          'Nome / razão social': cliente.nome,
                                          'Nome fantasia': cliente.nomeFantasia,
                                          'Tipo de pessoa':
                                              cliente.tipoPessoa == 'pf'
                                              ? 'Pessoa física'
                                              : 'Pessoa jurídica',
                                          'Perfil fiscal':
                                              cliente.taxProfile.label,
                                          'Regime tributário': taxRegimeLabel(
                                            cliente.taxRegime,
                                          ),
                                          'ZFM / SUFRAMA': cliente.isZfmSuframa
                                              ? 'Sim'
                                              : 'Não',
                                          'Finalidade da venda':
                                              cliente.salePurpose.label,
                                          'CPF / CNPJ': cliente.documento,
                                          'Inscrição estadual':
                                              cliente.inscricaoEstadual,
                                          'Inscrição municipal':
                                              cliente.inscricaoMunicipal,
                                        },
                                      ),
                                      _buildReadOnlySection(
                                        context,
                                        'Contato',
                                        {
                                          'E-mail': cliente.email,
                                          'E-mail financeiro':
                                              cliente.emailFinanceiro,
                                          'Celular': cliente.celular,
                                          'Telefone': cliente.telefone,
                                        },
                                      ),
                                      _buildReadOnlySection(
                                        context,
                                        'Endereço',
                                        {
                                          'CEP': cliente.cep,
                                          'Logradouro': cliente.logradouro,
                                          'Número': cliente.numero,
                                          'Complemento': cliente.complemento,
                                          'Bairro': cliente.bairro,
                                          'Cidade': cliente.cidade,
                                          'Estado': cliente.estado,
                                          'País': cliente.pais,
                                        },
                                      ),
                                      _buildReadOnlySection(
                                        context,
                                        'Cadastro',
                                        {
                                          'Canal': cliente.canal,
                                          'Origem do cadastro':
                                              cliente.origemCadastro.label,
                                          'Status': cliente.status.label,
                                          'Observações': cliente.observacoes,
                                          'Criado em': _formatDate(
                                            cliente.createdAt,
                                          ),
                                          'Atualizado em': _formatDate(
                                            cliente.updatedAt,
                                          ),
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return '—';
    }
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
