import 'package:flutter/material.dart';

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
  late String _canal;
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
    _emailFinanceiroController =
        TextEditingController(text: cliente.emailFinanceiro);
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
    _inscricaoEstadualController =
        TextEditingController(text: cliente.inscricaoEstadual);
    _inscricaoMunicipalController =
        TextEditingController(text: cliente.inscricaoMunicipal);
    _observacoesController = TextEditingController(text: cliente.observacoes);
    _tipoPessoa = cliente.tipoPessoa;
    _canal = cliente.canal;
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
        canal: _canal,
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
    final confirmed = await showDialog<bool>(
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
      await widget.repository.delete(tenantId: _cliente.tenantId, id: _cliente.id);
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

  Widget _buildReadOnlySection(String title, Map<String, String> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...fields.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        entry.value.isEmpty ? '—' : entry.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection(String title, List<Widget> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...fields,
            ],
          ),
        ),
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
              onPressed: _saving ? null : () => setState(() => _isEditing = false),
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
          if (!_isEditing && _isErpManaged)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Tooltip(
                message:
                    'Gerenciado pelo ERP: exclusão/inativação devem ser feitas no sistema de origem.',
                child: Icon(Icons.lock_outline),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _isEditing
              ? Form(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormSection(
                        'Identificação',
                        [
                          TextFormField(
                            controller: _nomeController,
                            decoration: const InputDecoration(labelText: 'Nome / razão social'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nomeFantasiaController,
                            decoration: const InputDecoration(labelText: 'Nome fantasia'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _tipoPessoa,
                            items: const [
                              DropdownMenuItem(value: 'pj', child: Text('Pessoa jurídica')),
                              DropdownMenuItem(value: 'pf', child: Text('Pessoa física')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _tipoPessoa = value);
                              }
                            },
                            decoration: const InputDecoration(labelText: 'Tipo de pessoa'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _documentoController,
                            decoration: const InputDecoration(labelText: 'CPF / CNPJ'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _inscricaoEstadualController,
                            decoration: const InputDecoration(labelText: 'Inscrição estadual'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _inscricaoMunicipalController,
                            decoration: const InputDecoration(labelText: 'Inscrição municipal'),
                          ),
                        ],
                      ),
                      _buildFormSection(
                        'Contato',
                        [
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(labelText: 'E-mail'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailFinanceiroController,
                            decoration: const InputDecoration(labelText: 'E-mail financeiro'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _celularController,
                            decoration: const InputDecoration(labelText: 'Celular'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _telefoneController,
                            decoration: const InputDecoration(labelText: 'Telefone'),
                          ),
                        ],
                      ),
                      _buildFormSection(
                        'Endereço',
                        [
                          TextFormField(
                            controller: _cepController,
                            decoration: const InputDecoration(labelText: 'CEP'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _logradouroController,
                            decoration: const InputDecoration(labelText: 'Logradouro'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _numeroController,
                            decoration: const InputDecoration(labelText: 'Número'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _complementoController,
                            decoration: const InputDecoration(labelText: 'Complemento'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _bairroController,
                            decoration: const InputDecoration(labelText: 'Bairro'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cidadeController,
                            decoration: const InputDecoration(labelText: 'Cidade'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _estadoController,
                            decoration: const InputDecoration(labelText: 'Estado'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _paisController,
                            decoration: const InputDecoration(labelText: 'País'),
                          ),
                        ],
                      ),
                      _buildFormSection(
                        'Cadastro',
                        [
                          DropdownButtonFormField<String>(
                            initialValue: _canal,
                            items: const [
                              DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                              DropdownMenuItem(value: 'representante', child: Text('Representante')),
                              DropdownMenuItem(value: 'erp', child: Text('ERP')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _canal = value);
                              }
                            },
                            decoration: const InputDecoration(labelText: 'Canal'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _observacoesController,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(labelText: 'Observações'),
                          ),
                        ],
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Salvando...' : 'Salvar alterações'),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 20),
                    _buildReadOnlySection('Identificação', {
                      'Nome / razão social': cliente.nome,
                      'Nome fantasia': cliente.nomeFantasia,
                      'Tipo de pessoa': cliente.tipoPessoa == 'pf'
                          ? 'Pessoa física'
                          : 'Pessoa jurídica',
                      'CPF / CNPJ': cliente.documento,
                      'Inscrição estadual': cliente.inscricaoEstadual,
                      'Inscrição municipal': cliente.inscricaoMunicipal,
                    }),
                    _buildReadOnlySection('Contato', {
                      'E-mail': cliente.email,
                      'E-mail financeiro': cliente.emailFinanceiro,
                      'Celular': cliente.celular,
                      'Telefone': cliente.telefone,
                    }),
                    _buildReadOnlySection('Endereço', {
                      'CEP': cliente.cep,
                      'Logradouro': cliente.logradouro,
                      'Número': cliente.numero,
                      'Complemento': cliente.complemento,
                      'Bairro': cliente.bairro,
                      'Cidade': cliente.cidade,
                      'Estado': cliente.estado,
                      'País': cliente.pais,
                    }),
                    _buildReadOnlySection('Cadastro', {
                      'Canal': cliente.canal,
                      'Origem do cadastro': cliente.origemCadastro.label,
                      'Status': cliente.status.label,
                      'Observações': cliente.observacoes,
                      'Criado em': _formatDate(cliente.createdAt),
                      'Atualizado em': _formatDate(cliente.updatedAt),
                    }),
                  ],
                ),
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
