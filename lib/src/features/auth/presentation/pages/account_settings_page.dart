import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/diagnostics/error_dialog.dart';
import '../../../../core/models/app_identity.dart';
import '../../../diagnostics/presentation/pages/diagnostics_page.dart';
import '../../services/tenant_membership_service.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.identity,
    this.onAccessUpdated,
  });

  final AppIdentity identity;
  final VoidCallback? onAccessUpdated;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _leavingTenant = false;
  bool _updatingDisplayName = false;

  TenantMembershipService get _membershipService =>
      TenantMembershipService(FirebaseFirestore.instance);

  Future<void> _leaveCurrentTenant() async {
    final user = FirebaseAuth.instance.currentUser;
    final membershipId = widget.identity.membershipId;
    if (user == null || membershipId == null || membershipId.isEmpty) {
      _showMessage('Nao foi possivel identificar o vinculo atual do tenant.');
      return;
    }

    if (widget.identity.isPersonalWorkspace) {
      _showMessage('Voce ja esta no modo pessoal.');
      return;
    }

    setState(() {
      _leavingTenant = true;
    });

    try {
      await _membershipService.leaveTenant(
        membershipId: membershipId,
        actorUid: user.uid,
      );

      if (!mounted) {
        return;
      }

      _showMessage('Saida do tenant concluida. Revalidando acesso...');
      widget.onAccessUpdated?.call();
    } catch (error, stackTrace) {
      if (error is StateError) {
        _showMessage(error.message.toString());
      } else if (mounted) {
        await showAppErrorDialog(
          context,
          title: 'Não foi possível sair deste tenant',
          error: error,
          stackTrace: stackTrace,
          tag: 'account.leave_tenant',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _leavingTenant = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    String currentName = (user.displayName ?? '').trim();
    if (currentName.isEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      currentName =
          (userData['displayName'] ?? userData['name'] ?? userData['nome'] ?? '')
              .toString()
              .trim();
    }

    if (!mounted) {
      return;
    }

    final selectedName = await showDialog<String>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(initialName: currentName),
    );

    if (selectedName == null) {
      return;
    }
    if (selectedName.isEmpty) {
      _showMessage('Informe um nome para salvar.');
      return;
    }

    setState(() {
      _updatingDisplayName = true;
    });

    try {
      await user.updateDisplayName(selectedName);
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': selectedName,
        'name': selectedName,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      _showMessage('Nome atualizado com sucesso.');
      setState(() {});
    } catch (_) {
      _showMessage('Nao foi possivel atualizar o nome agora.');
    } finally {
      if (mounted) {
        setState(() {
          _updatingDisplayName = false;
        });
      }
    }
  }

  String _workspaceTypeLabel(String workspaceType) {
    switch (workspaceType.trim()) {
      case 'seller_solo_workspace':
        return 'Individual';
      case 'rep_workspace':
        return 'Representacoes';
      case 'brand_owner_workspace':
        return 'Enterprise';
      default:
        return workspaceType.trim().isEmpty ? '-' : workspaceType.trim();
    }
  }

  String _accountContractLockLabel(String rawValue) {
    switch (rawValue.trim()) {
      case 'enterprise_only':
        return 'Conta BrandOp';
      case 'flexible':
        return 'Conta MultiOp';
      default:
        return 'Conta MultiOp';
    }
  }

  String _billingTierLabel(Map<String, dynamic> tenantData) {
    final planTier = (tenantData['planTier'] ?? '').toString().trim();
    if (planTier.toLowerCase() == 'upgrade') {
      return 'Upgrade';
    }

    final explicitPlan = (tenantData['plan'] ?? '').toString().trim();
    if (explicitPlan.isNotEmpty) {
      return explicitPlan;
    }

    return 'Base';
  }

  Widget _buildWorkspaceAndBillingCard() {
    final tenantId = widget.identity.tenantId.trim();
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    if (tenantId.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sem tenant ativo para exibir dados de workspace.'),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .snapshots(),
      builder: (context, tenantSnapshot) {
        final tenantData =
            tenantSnapshot.data?.data() ?? const <String, dynamic>{};
        final workspaceType = (tenantData['workspaceType'] ?? '')
            .toString()
            .trim();
        final workspaceName =
            (tenantData['nomeFantasia'] ?? widget.identity.tenantName)
                .toString()
                .trim();
        final contact = (tenantData['contatoResponsavel'] ?? '')
            .toString()
            .trim();
        final email = (tenantData['emailComercial'] ?? '').toString().trim();
        final city = (tenantData['cidade'] ?? '').toString().trim();
        final uf = (tenantData['uf'] ?? '').toString().trim().toUpperCase();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid.isEmpty
              ? null
              : FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .snapshots(),
          builder: (context, userSnapshot) {
            final userData =
                userSnapshot.data?.data() ?? const <String, dynamic>{};
            final accountContractLock = _accountContractLockLabel(
              (userData['accountContractLock'] ?? '').toString(),
            );

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dados do workspace',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nome: ${workspaceName.isEmpty ? '-' : workspaceName}',
                    ),
                    const SizedBox(height: 4),
                    Text('Identificador: $tenantId'),
                    const SizedBox(height: 4),
                    Text('Tipo: ${_workspaceTypeLabel(workspaceType)}'),
                    const SizedBox(height: 4),
                    Text('Perfil atual: ${widget.identity.role}'),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Responsavel: $contact'),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('E-mail comercial: $email'),
                    ],
                    if (city.isNotEmpty || uf.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Cidade/UF: ${city.isEmpty ? '-' : city}${uf.isEmpty ? '' : '/$uf'}',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Billing e conta',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tipo de conta: ${_workspaceTypeLabel(workspaceType)}',
                    ),
                    const SizedBox(height: 4),
                    Text('Modelo contratual: $accountContractLock'),
                    const SizedBox(height: 4),
                    Text('Billing (plano): ${_billingTierLabel(tenantData)}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedRole = widget.identity.role.trim().toLowerCase();
    final canSelfLeaveTenant =
        !widget.identity.isPersonalWorkspace && normalizedRole != 'owner';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Minha conta',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie seu perfil de uso pessoal e seu vinculo com o tenant atual.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modo pessoal',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sempre ativo para sua conta. Se voce ficar sem tenant ativo, o app abre no workspace pessoal automaticamente.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identificacao da conta',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nome atual: ${FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty == true ? FirebaseAuth.instance.currentUser!.displayName!.trim() : '-'}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Email: ${FirebaseAuth.instance.currentUser?.email?.trim().isNotEmpty == true ? FirebaseAuth.instance.currentUser!.email!.trim() : '-'}',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _updatingDisplayName ? null : _editDisplayName,
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(
                        _updatingDisplayName
                            ? 'Salvando nome...'
                            : 'Editar nome de exibicao',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildWorkspaceAndBillingCard(),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vinculo atual com tenant',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Tenant: ${widget.identity.tenantName}'),
                    const SizedBox(height: 6),
                    Text('Perfil: ${widget.identity.role}'),
                    const SizedBox(height: 10),
                    if (canSelfLeaveTenant)
                      OutlinedButton.icon(
                        onPressed: _leavingTenant ? null : _leaveCurrentTenant,
                        icon: const Icon(Icons.logout),
                        label: Text(
                          _leavingTenant
                              ? 'Saindo do tenant...'
                              : 'Sair deste tenant',
                        ),
                      )
                    else
                      const Text(
                        'Este perfil nao possui autoatendimento para sair do tenant.',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diagnóstico',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Consulte e copie os detalhes técnicos dos últimos erros e falhas de sincronização registrados nesta sessão.',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DiagnosticsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Ver diagnóstico'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditDisplayNameDialog> createState() =>
      _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atualizar nome de exibicao'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Nome',
          hintText: 'Como seu nome deve aparecer no sistema',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
