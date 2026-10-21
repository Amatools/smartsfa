import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/models/cliente.dart';
import '../../../../core/models/cliente_pre_cadastro.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/diagnostics/app_diagnostics.dart';
import '../../../../core/diagnostics/error_dialog.dart';
import '../../../../core/constants/brazil_states.dart';
import '../../../../core/repositories/cliente_pre_cadastro_repository.dart';
import '../../../../core/repositories/cliente_repository.dart';
import '../../../../core/services/offline_sync_queue.dart';
import '../../../../core/services/pre_cadastro_save_service.dart';

class ClientePreCadastroPage extends StatefulWidget {
  const ClientePreCadastroPage({
    super.key,
    required this.tenantId,
    required this.requestedByUid,
    required this.repository,
    this.clienteRepository,
  });

  final String tenantId;
  final String requestedByUid;
  final ClientePreCadastroRepository repository;
  final ClienteRepository? clienteRepository;

  @override
  State<ClientePreCadastroPage> createState() => _ClientePreCadastroPageState();
}

class _ClientePreCadastroPageState extends State<ClientePreCadastroPage> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _documentoController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailFinanceiroController = TextEditingController();
  final _celularController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cepController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _paisController = TextEditingController(text: 'Brasil');
  final _inscricaoEstadualController = TextEditingController();
  final _inscricaoMunicipalController = TextEditingController();
  final _observacoesController = TextEditingController();

  String _tipoPessoa = 'pj';
  SalePurpose _salePurpose = SalePurpose.revenda;
  CustomerTaxProfile _taxProfile = CustomerTaxProfile.contribuinte;
  bool _isZfmSuframa = false;
  final String _canal = 'vendedor';
  bool _saving = false;
  bool _buscandoCep = false;

  String? _normalizeUfForDropdown(String? rawValue) {
    return brazilStateOrNull(rawValue);
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _normalizeDocumento(String value) {
    final onlyDigits = _digitsOnly(value);
    if (onlyDigits.isNotEmpty) {
      return onlyDigits;
    }
    return value.trim().toLowerCase();
  }

  bool _isValidEmailBasic(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return true;
    }
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  bool _isValidCpfDigits(String value) {
    if (value.length != 11) {
      return false;
    }
    if (RegExp(r'^(\d)\1{10}$').hasMatch(value)) {
      return false;
    }

    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(value[i]) * (10 - i);
    }
    var remainder = sum % 11;
    final digit1 = remainder < 2 ? 0 : 11 - remainder;
    if (digit1 != int.parse(value[9])) {
      return false;
    }

    sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += int.parse(value[i]) * (11 - i);
    }
    remainder = sum % 11;
    final digit2 = remainder < 2 ? 0 : 11 - remainder;
    return digit2 == int.parse(value[10]);
  }

  bool _isValidCnpjDigits(String value) {
    if (value.length != 14) {
      return false;
    }
    if (RegExp(r'^(\d)\1{13}$').hasMatch(value)) {
      return false;
    }

    const weightsFirst = <int>[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const weightsSecond = <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(value[i]) * weightsFirst[i];
    }
    var remainder = sum % 11;
    final digit1 = remainder < 2 ? 0 : 11 - remainder;
    if (digit1 != int.parse(value[12])) {
      return false;
    }

    sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(value[i]) * weightsSecond[i];
    }
    remainder = sum % 11;
    final digit2 = remainder < 2 ? 0 : 11 - remainder;
    return digit2 == int.parse(value[13]);
  }

  String _formatCpfCnpjMasked(String? rawValue) {
    final digits = _digitsOnly(rawValue ?? '');
    final limited = digits.length > 14 ? digits.substring(0, 14) : digits;

    if (limited.length <= 11) {
      final buffer = StringBuffer();
      for (var i = 0; i < limited.length; i++) {
        if (i == 3 || i == 6) {
          buffer.write('.');
        }
        if (i == 9) {
          buffer.write('-');
        }
        buffer.write(limited[i]);
      }
      return buffer.toString();
    }

    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 2 || i == 5) {
        buffer.write('.');
      }
      if (i == 8) {
        buffer.write('/');
      }
      if (i == 12) {
        buffer.write('-');
      }
      buffer.write(limited[i]);
    }
    return buffer.toString();
  }

  String _formatCepMasked(String? rawValue) {
    final digits = _digitsOnly(rawValue ?? '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    if (limited.length <= 5) {
      return limited;
    }
    return '${limited.substring(0, 5)}-${limited.substring(5)}';
  }

  String _formatPhoneMasked(String? rawValue) {
    final digits = _digitsOnly(rawValue ?? '');
    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;

    if (limited.isEmpty) {
      return '';
    }

    if (limited.length <= 2) {
      return '(${limited.substring(0, limited.length)}';
    }

    final ddd = limited.substring(0, 2);
    final rest = limited.substring(2);
    if (rest.isEmpty) {
      return '($ddd) ';
    }

    if (limited.length <= 10) {
      if (rest.length <= 4) {
        return '($ddd) $rest';
      }
      return '($ddd) ${rest.substring(0, 4)}-${rest.substring(4)}';
    }

    if (rest.length <= 5) {
      return '($ddd) $rest';
    }
    return '($ddd) ${rest.substring(0, 5)}-${rest.substring(5)}';
  }

  Future<bool> _hasDocumentoDuplicado(String documento) async {
    final normalizedDocumento = _normalizeDocumento(documento);
    if (normalizedDocumento.isEmpty) {
      return false;
    }

    var remote = const <ClientePreCadastro>[];
    try {
      remote = await widget.repository.fetchAll(tenantId: widget.tenantId);
    } catch (error, stackTrace) {
      // Remote check is best-effort only: a network/permission failure here
      // must never block a local-first save. Fall back to local-only check.
      AppDiagnostics.log(
        tag: 'pre_cadastro.duplicate_check',
        message: 'Falha ao consultar duplicidade remota de pré-cadastro.',
        error: error,
        stackTrace: stackTrace,
      );
      remote = const <ClientePreCadastro>[];
    }

    final deletedIds = await OfflineSyncQueue.readDeletedIds(
      type: 'cliente_pre_cadastro',
    );
    remote = remote.where((item) => !deletedIds.contains(item.id)).toList();

    final queued = await OfflineSyncQueue.readQueuedPreCadastros(
      tenantId: widget.tenantId,
      includePersonalWorkspace: widget.tenantId.startsWith('personal_'),
    );

    final all = <ClientePreCadastro>[...queued, ...remote];
    return all.any(
      (item) => _normalizeDocumento(item.documento) == normalizedDocumento,
    );
  }

  /// A pre-cadastro only makes sense for a customer that isn't an official
  /// cliente yet. Without this check, a stale/duplicate pre-cadastro can be
  /// created for a documento that already has an approved cliente record
  /// (e.g. after the original pre-cadastro was cleaned up), leaving the same
  /// customer visible both as "pré-cadastro" and as "cliente" at once.
  Future<bool> _hasClienteOficialComDocumento(String documento) async {
    final normalizedDocumento = _normalizeDocumento(documento);
    if (normalizedDocumento.isEmpty || widget.clienteRepository == null) {
      return false;
    }

    var remote = const <Cliente>[];
    try {
      remote = await widget.clienteRepository!.fetchAll(
        tenantId: widget.tenantId,
      );
    } catch (error, stackTrace) {
      // Remote check is best-effort only, same rationale as the pre-cadastro
      // duplicate check above.
      AppDiagnostics.log(
        tag: 'pre_cadastro.duplicate_check_cliente',
        message: 'Falha ao consultar clientes oficiais para verificação de duplicidade.',
        error: error,
        stackTrace: stackTrace,
      );
      remote = const <Cliente>[];
    }

    final deletedIds = await OfflineSyncQueue.readDeletedIds(type: 'cliente');
    remote = remote.where((item) => !deletedIds.contains(item.id)).toList();

    final local = await OfflineSyncQueue.readLocalClientes(
      tenantId: widget.tenantId,
      includePersonalWorkspace: widget.tenantId.startsWith('personal_'),
    );

    final all = <Cliente>[...local.map((record) => record.entity), ...remote];
    return all.any(
      (item) => _normalizeDocumento(item.documento) == normalizedDocumento,
    );
  }

  Future<bool> _resolveIsOffline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 3),
      );
      return connectivity.contains(ConnectivityResult.none);
    } catch (_) {
      // If we cannot determine connectivity within a bounded time (plugin
      // failure, hang, missing channel, etc.), assume offline so the save
      // always falls back to the local queue instead of getting stuck.
      return true;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _documentoController.dispose();
    _nomeFantasiaController.dispose();
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

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final nome = _nomeController.text.trim();
    final documento = _documentoController.text.trim();
    final email = _emailController.text.trim();
    final emailFinanceiro = _emailFinanceiroController.text.trim();
    final celular = _celularController.text.trim();

    if (nome.isEmpty ||
        documento.isEmpty ||
        (email.isEmpty && celular.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha nome, documento e pelo menos email ou celular.',
          ),
        ),
      );
      return;
    }

    final hasDocumentoDuplicado = await _hasDocumentoDuplicado(documento);
    if (hasDocumentoDuplicado) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ja existe um pre-cadastro com este documento neste workspace.',
          ),
        ),
      );
      return;
    }

    final hasClienteOficial = await _hasClienteOficialComDocumento(documento);
    if (hasClienteOficial) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ja existe um cliente oficial cadastrado com este documento.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now();
    final entity = ClientePreCadastro(
      id: 'pre-${now.microsecondsSinceEpoch}',
      tenantId: widget.tenantId,
      nome: nome,
      documento: documento,
      tipoPessoa: _tipoPessoa,
      nomeFantasia: _nomeFantasiaController.text.trim(),
      email: email,
      emailFinanceiro: emailFinanceiro,
      canal: _canal,
      celular: celular,
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
      isZfmSuframa: _isZfmSuframa,
      observacoes: _observacoesController.text.trim(),
      origemCadastro: CustomerOrigin.manual,
      status: PreRegistrationStatus.pending,
      requestedByUid: widget.requestedByUid,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final isOffline = await _resolveIsOffline();
      final result = await PreCadastroSaveService.saveOrQueue(
        entity: entity,
        repository: widget.repository,
        tenantId: widget.tenantId,
        isOffline: isOffline,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (result.savedLocalOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvo no dispositivo Local (off-line)')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pré-cadastro enviado para aprovação.')),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      await showAppErrorDialog(
        context,
        title: 'Não foi possível salvar o pré-cadastro',
        error: error,
        stackTrace: stackTrace,
        tag: 'pre_cadastro.submit',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _buscarCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um CEP valido com 8 digitos.')),
      );
      return;
    }

    setState(() => _buscandoCep = true);

    try {
      final response = await http.get(
        Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      );

      if (response.statusCode != 200) {
        throw Exception('cep_error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;

      _logradouroController.text = (data['street'] ?? '').toString();
      _bairroController.text = (data['neighborhood'] ?? '').toString();
      _cidadeController.text = (data['city'] ?? '').toString();
      final state = (data['state'] ?? '').toString().trim().toUpperCase();
      _estadoController.text = brazilStateOrNull(state) ?? '';
      _paisController.text = 'Brasil';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Endereco preenchido automaticamente pelo CEP.'),
        ),
      );
    } catch (error, stackTrace) {
      AppDiagnostics.log(
        tag: 'pre_cadastro.cep_lookup',
        message: 'Falha ao consultar CEP.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel buscar esse CEP no momento.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _buscandoCep = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const formChromeColor = Color(0xFFF5F6F8);
    const formBodyColor = Colors.white;
    const formBorderColor = Color(0xFFE3E6EA);
    const formFocusedBorderColor = Color(0xFFD0D6DE);

    InputDecoration formInputDecoration() {
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: formBodyColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: formBorderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: formBorderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: formFocusedBorderColor, width: 1),
        ),
      );
    }

    Widget sectionTitle(String text) {
      return Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      );
    }

    Widget labeledField({required String label, required Widget child}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          child,
        ],
      );
    }

    Widget textField({
      required TextEditingController controller,
      required String label,
      TextInputType? keyboardType,
      FormFieldValidator<String>? validator,
      List<TextInputFormatter>? inputFormatters,
      int maxLines = 1,
      bool alignLabelWithHint = false,
    }) {
      return labeledField(
        label: label,
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          decoration: formInputDecoration().copyWith(
            alignLabelWithHint: alignLabelWithHint,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Novo pré-cadastro')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: formBodyColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: formBorderColor, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      color: formChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cadastro de parceiro / cliente',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pré-cadastro inicial para orçamento e conversão posterior.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: formBodyColor,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sectionTitle('Dados principais'),
                            const SizedBox(height: 10),
                            labeledField(
                              label: 'Tipo de pessoa',
                              child: DropdownButtonFormField<String>(
                                initialValue: _tipoPessoa,
                                isExpanded: true,
                                decoration: formInputDecoration(),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'pj',
                                    child: Text('Pessoa juridica'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pf',
                                    child: Text('Pessoa fisica'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _tipoPessoa = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            labeledField(
                              label: 'Finalidade da venda',
                              child: DropdownButtonFormField<SalePurpose>(
                                initialValue: _salePurpose,
                                isExpanded: true,
                                decoration: formInputDecoration(),
                                items: SalePurpose.values
                                    .map(
                                      (item) => DropdownMenuItem<SalePurpose>(
                                        value: item,
                                        child: Text(item.label),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _salePurpose = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            labeledField(
                              label: 'Perfil fiscal do cliente',
                              child:
                                  DropdownButtonFormField<CustomerTaxProfile>(
                                    initialValue: _taxProfile,
                                    isExpanded: true,
                                    decoration: formInputDecoration(),
                                    items: CustomerTaxProfile.values
                                        .map(
                                          (item) =>
                                              DropdownMenuItem<CustomerTaxProfile>(
                                                value: item,
                                                child: Text(item.label),
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _taxProfile = value);
                                      }
                                    },
                                  ),
                            ),
                            const SizedBox(height: 8),
                            labeledField(
                              label: 'Zona Franca / SUFRAMA',
                              child: CheckboxListTile(
                                value: _isZfmSuframa,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Cliente enquadrado em ZFM-SUFRAMA',
                                ),
                                onChanged: (value) {
                                  setState(
                                    () => _isZfmSuframa = value ?? false,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Canal: $_canal',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            textField(
                              controller: _nomeController,
                              label: 'Nome / razao social *',
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Informe o nome ou a razao social.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _nomeFantasiaController,
                              label: 'Nome fantasia',
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _documentoController,
                              label: 'CPF / CNPJ *',
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                                _CpfCnpjInputFormatter(_formatCpfCnpjMasked),
                              ],
                              validator: (value) {
                                final digits = _digitsOnly(value ?? '');
                                if (digits.isEmpty) {
                                  return 'Informe o documento.';
                                }

                                if (_tipoPessoa == 'pf') {
                                  if (!_isValidCpfDigits(digits)) {
                                    return 'CPF inválido.';
                                  }
                                } else {
                                  if (!_isValidCnpjDigits(digits)) {
                                    return 'CNPJ inválido.';
                                  }
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            sectionTitle('Contato'),
                            const SizedBox(height: 10),
                            textField(
                              controller: _emailController,
                              label: 'E-mail',
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (_isValidEmailBasic(value ?? '')) {
                                  return null;
                                }
                                return 'E-mail inválido.';
                              },
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _emailFinanceiroController,
                              label: 'E-mail financeiro',
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (_isValidEmailBasic(value ?? '')) {
                                  return null;
                                }
                                return 'E-mail financeiro inválido.';
                              },
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _celularController,
                              label: 'Celular',
                              keyboardType: TextInputType.phone,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                                _PhoneInputFormatter(_formatPhoneMasked),
                              ],
                              validator: (value) {
                                final digits = _digitsOnly(value ?? '');
                                if (digits.isEmpty) {
                                  return null;
                                }
                                if (digits.length < 10 || digits.length > 11) {
                                  return 'Celular deve ter DDD + número.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _telefoneController,
                              label: 'Telefone',
                              keyboardType: TextInputType.phone,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                                _PhoneInputFormatter(_formatPhoneMasked),
                              ],
                              validator: (value) {
                                final digits = _digitsOnly(value ?? '');
                                if (digits.isEmpty) {
                                  return null;
                                }
                                if (digits.length < 10 || digits.length > 11) {
                                  return 'Telefone deve ter DDD + número.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            sectionTitle('Endereco'),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: textField(
                                    controller: _cepController,
                                    label: 'CEP',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                      _CepInputFormatter(_formatCepMasked),
                                    ],
                                    validator: (value) {
                                      final digits = _digitsOnly(value ?? '');
                                      if (digits.isEmpty) {
                                        return null;
                                      }
                                      if (digits.length != 8) {
                                        return 'CEP deve ter 8 dígitos.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  height: 48,
                                  child: FilledButton.tonalIcon(
                                    onPressed: _buscandoCep ? null : _buscarCep,
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
                                      _buscandoCep
                                          ? 'Buscando...'
                                          : 'Buscar CEP',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: textField(
                                    controller: _logradouroController,
                                    label: 'Logradouro',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 120,
                                  child: textField(
                                    controller: _numeroController,
                                    label: 'Numero',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _complementoController,
                              label: 'Complemento',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: textField(
                                    controller: _bairroController,
                                    label: 'Bairro',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: textField(
                                    controller: _cidadeController,
                                    label: 'Cidade',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: labeledField(
                                    label: 'UF',
                                    child: DropdownButtonFormField<String>(
                                      key: ValueKey<String>(
                                        _estadoController.text,
                                      ),
                                      initialValue: _normalizeUfForDropdown(
                                        _estadoController.text,
                                      ),
                                      isExpanded: true,
                                      decoration: formInputDecoration(),
                                      items: brazilStates
                                          .map(
                                            (uf) => DropdownMenuItem<String>(
                                              value: uf,
                                              child: Text(uf),
                                            ),
                                          )
                                          .toList(growable: false),
                                      validator: (value) {
                                        if ((value ?? '').trim().isEmpty) {
                                          return 'Selecione a UF.';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        _estadoController.text = (value ?? '')
                                            .trim();
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: textField(
                                    controller: _paisController,
                                    label: 'Pais',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            sectionTitle('Documentacao fiscal'),
                            const SizedBox(height: 10),
                            textField(
                              controller: _inscricaoEstadualController,
                              label: 'Inscricao estadual',
                            ),
                            const SizedBox(height: 12),
                            textField(
                              controller: _inscricaoMunicipalController,
                              label: 'Inscricao municipal',
                            ),
                            const SizedBox(height: 18),
                            sectionTitle('Observacoes'),
                            const SizedBox(height: 10),
                            textField(
                              controller: _observacoesController,
                              label: 'Anotacoes internas',
                              maxLines: 3,
                              alignLabelWithHint: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: formChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Salvando...' : 'Salvar pré-cadastro',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CpfCnpjInputFormatter extends TextInputFormatter {
  _CpfCnpjInputFormatter(this._mask);

  final String Function(String?) _mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = _mask(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _CepInputFormatter extends TextInputFormatter {
  _CepInputFormatter(this._mask);

  final String Function(String?) _mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = _mask(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  _PhoneInputFormatter(this._mask);

  final String Function(String?) _mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = _mask(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
