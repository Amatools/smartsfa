import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
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
    } catch (error) {
      _showMessage(error is StateError
          ? error.message.toString()
          : 'Nao foi possivel sair deste tenant agora.');
    } finally {
      if (mounted) {
        setState(() {
          _leavingTenant = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedRole = widget.identity.role.trim().toLowerCase();
    final canSelfLeaveTenant =
        !widget.identity.isPersonalWorkspace && normalizedRole != 'owner';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
          ],
        ),
      ),
    );
  }
}
