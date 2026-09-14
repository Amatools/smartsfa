import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_invitation.dart';
import '../../../../shared/domain/date_time_label.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../../shared/presentation/widgets/app_pagination_bar.dart';
import '../../../../shared/presentation/widgets/pagination_slice.dart';
import '../../../auth/services/tenant_invitation_service.dart';
import '../controllers/tenant_invitation_action_controller.dart';

class TenantInvitationsPage extends StatefulWidget {
  const TenantInvitationsPage({super.key, required this.identity});

  final AppIdentity identity;

  @override
  State<TenantInvitationsPage> createState() => _TenantInvitationsPageState();
}

class _TenantInvitationsPageState extends State<TenantInvitationsPage> {
  final TextEditingController _emailController = TextEditingController();
  String _selectedRole = 'vendedor';
  bool _defaultTenant = false;
  int _expirationDays = 7;
  int _currentPage = 0;
  int _pageSize = 10;
  bool _creating = false;
  String? _revokingToken;

  TenantInvitationService get _invitationService =>
      TenantInvitationService(FirebaseFirestore.instance);

  TenantInvitationActionController get _actions =>
      TenantInvitationActionController(_invitationService);

  String get _normalizedRole => widget.identity.role.trim().toLowerCase();

  List<String> _allowedRolesForContext(String workspaceType) {
    if (workspaceType == 'seller_solo_workspace') {
      return const [];
    }

    if (workspaceType == 'rep_workspace') {
      if (_normalizedRole == 'owner') {
        return const ['representante', 'vendedor'];
      }
      if (_normalizedRole == 'representante') {
        return const ['vendedor'];
      }
      return const [];
    }

    if (_normalizedRole == 'owner') {
      return const ['gerente'];
    }
    if (_normalizedRole == 'gerente') {
      return const ['representante'];
    }
    if (_normalizedRole == 'representante') {
      return const ['vendedor'];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _selectedRole = 'vendedor';
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _createInvitation() async {
    final tenantDoc = await FirebaseFirestore.instance
        .collection('tenants')
        .doc(widget.identity.tenantId)
        .get();
    final workspaceType = (tenantDoc.data()?['workspaceType'] ?? 'brand_owner_workspace')
        .toString();
    final allowedRolesForContext = _allowedRolesForContext(workspaceType);

    if (allowedRolesForContext.isEmpty) {
      _showMessage('Seu perfil nao pode enviar convites neste tenant.');
      return;
    }

    if (!allowedRolesForContext.contains(_selectedRole)) {
      _showMessage('Perfil de convite invalido para este tipo de workspace.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    final invitedEmail = _emailController.text.trim().toLowerCase();

    setState(() {
      _creating = true;
    });

    try {
      final invitation = await _actions.createInvitation(
        tenantId: widget.identity.tenantId,
        role: _selectedRole,
        createdByUid: user.uid,
        invitedEmail: invitedEmail,
        defaultTenant: _defaultTenant,
        expirationDays: _expirationDays,
      );

      _emailController.clear();
      _showMessage('Convite criado: ${invitation.token}');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Nao foi possivel criar convite agora.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _revokeInvitation(TenantInvitation invitation) async {
    final tenantDoc = await FirebaseFirestore.instance
        .collection('tenants')
        .doc(widget.identity.tenantId)
        .get();
    final workspaceType = (tenantDoc.data()?['workspaceType'] ?? 'brand_owner_workspace')
        .toString();
    final allowedRolesForContext = _allowedRolesForContext(workspaceType);

    if (allowedRolesForContext.isEmpty) {
      _showMessage('Seu perfil nao pode gerenciar convites neste tenant.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _revokingToken = invitation.token;
    });

    try {
      await _actions.revokeInvitation(
        token: invitation.token,
        revokedByUid: user.uid,
      );
      _showMessage('Convite revogado com sucesso.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Nao foi possivel revogar convite agora.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _revokingToken = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.identity.tenantId)
          .snapshots(),
      builder: (context, tenantSnapshot) {
        final workspaceType =
            (tenantSnapshot.data?.data()?['workspaceType'] ?? 'brand_owner_workspace')
                .toString();
        final allowedRoles = _allowedRolesForContext(workspaceType);
        final canManageInvites = allowedRoles.isNotEmpty;

        if (canManageInvites && !allowedRoles.contains(_selectedRole)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _selectedRole = allowedRoles.first;
            });
          });
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Convites do tenant')),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Envio e gerenciamento de convites do tenant ${widget.identity.tenantName}.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tipo de workspace: $workspaceType',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    if (!canManageInvites)
                      const AppInfoCard(
                        title: 'Acesso restrito',
                        subtitle:
                            'Seu perfil nao tem permissao para enviar convites neste tenant.',
                      )
                    else
                      _CreateInvitationCard(
                        emailController: _emailController,
                        selectedRole: _selectedRole,
                        allowedRoles: allowedRoles,
                        defaultTenant: _defaultTenant,
                        expirationDays: _expirationDays,
                        creating: _creating,
                        onRoleChanged: (value) {
                          setState(() {
                            _selectedRole = value;
                          });
                        },
                        onExpirationChanged: (value) {
                          setState(() {
                            _expirationDays = value;
                          });
                        },
                        onDefaultTenantChanged: (value) {
                          setState(() {
                            _defaultTenant = value;
                          });
                        },
                        onCreate: _createInvitation,
                      ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<TenantInvitation>>(
                      stream: _invitationService.watchInvitationsForTenant(
                        widget.identity.tenantId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const AppInfoCard(
                            title: 'Carregando convites',
                            subtitle: 'Buscando historico de convites do tenant...',
                          );
                        }

                        final invitations = snapshot.data ?? const [];
                        if (invitations.isEmpty) {
                          return const AppInfoCard(
                            title: 'Sem convites emitidos',
                            subtitle: 'Crie um convite para iniciar o onboarding.',
                          );
                        }

                        final page = buildPaginationSlice(
                          source: invitations,
                          requestedPage: _currentPage,
                          pageSize: _pageSize,
                        );

                        if (page.currentPage != _currentPage) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _currentPage = page.currentPage;
                              });
                            }
                          });
                        }

                        return Column(
                          children: [
                            AppPaginationBar(
                              currentPage: page.currentPage,
                              totalPages: page.totalPages,
                              pageSize: _pageSize,
                              startDisplay: page.startDisplay,
                              endDisplay: page.endDisplay,
                              totalItems: page.totalItems,
                              onPageSizeChanged: (value) {
                                setState(() {
                                  _pageSize = value;
                                  _currentPage = 0;
                                });
                              },
                              onPrevious: !page.hasPrevious
                                  ? null
                                  : () {
                                      setState(() {
                                        _currentPage = page.currentPage - 1;
                                      });
                                    },
                              onNext: !page.hasNext
                                  ? null
                                  : () {
                                      setState(() {
                                        _currentPage = page.currentPage + 1;
                                      });
                                    },
                            ),
                            const SizedBox(height: 10),
                            ...page.items.map(
                              (invitation) => _ManagedInvitationCard(
                                invitation: invitation,
                                revoking: _revokingToken == invitation.token,
                                onRevoke: canManageInvites &&
                                        invitation.status ==
                                            TenantInvitationStatus.pending
                                    ? () => _revokeInvitation(invitation)
                                    : null,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateInvitationCard extends StatelessWidget {
  const _CreateInvitationCard({
    required this.emailController,
    required this.selectedRole,
    required this.allowedRoles,
    required this.defaultTenant,
    required this.expirationDays,
    required this.creating,
    required this.onRoleChanged,
    required this.onExpirationChanged,
    required this.onDefaultTenantChanged,
    required this.onCreate,
  });

  final TextEditingController emailController;
  final String selectedRole;
  final List<String> allowedRoles;
  final bool defaultTenant;
  final int expirationDays;
  final bool creating;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<int> onExpirationChanged;
  final ValueChanged<bool> onDefaultTenantChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-mail do convidado',
                hintText: 'representante@empresa.com',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Perfil no tenant',
              ),
              items: allowedRoles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role),
                    ),
                  )
                  .toList(),
              onChanged: creating
                  ? null
                  : (value) {
                      if (value != null) {
                        onRoleChanged(value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: expirationDays,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Expiracao',
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 dia')),
                DropdownMenuItem(value: 3, child: Text('3 dias')),
                DropdownMenuItem(value: 7, child: Text('7 dias')),
                DropdownMenuItem(value: 15, child: Text('15 dias')),
                DropdownMenuItem(value: 30, child: Text('30 dias')),
              ],
              onChanged: creating
                  ? null
                  : (value) {
                      if (value != null) {
                        onExpirationChanged(value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: defaultTenant,
              contentPadding: EdgeInsets.zero,
              title: const Text('Definir como tenant padrao para o convidado'),
              onChanged: creating ? null : onDefaultTenantChanged,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: creating ? null : onCreate,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(creating ? 'Criando...' : 'Criar convite'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagedInvitationCard extends StatelessWidget {
  const _ManagedInvitationCard({
    required this.invitation,
    required this.revoking,
    this.onRevoke,
  });

  final TenantInvitation invitation;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  invitation.invitedEmail ?? 'Convite sem e-mail',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(label: Text(invitation.status.label)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Token: ${invitation.token}'),
            const SizedBox(height: 6),
            Text('Perfil: ${invitation.role}'),
            if (invitation.expiresAt != null) ...[
              const SizedBox(height: 6),
              Text('Expira em: ${formatDateTimeLabel(invitation.expiresAt!)}'),
            ],
            if (invitation.createdAt != null) ...[
              const SizedBox(height: 6),
              Text('Criado em: ${formatDateTimeLabel(invitation.createdAt!)}'),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: revoking ? null : onRevoke,
              icon: const Icon(Icons.block),
              label: Text(revoking ? 'Revogando...' : 'Revogar convite'),
            ),
          ],
        ),
      ),
    );
  }
}
