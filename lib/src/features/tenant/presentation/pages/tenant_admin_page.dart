import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_membership.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../../shared/presentation/widgets/app_pagination_bar.dart';
import '../../../../shared/presentation/widgets/pagination_slice.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../domain/tenant_admin_permissions.dart';
import 'tenant_invitations_page.dart';
import 'tenant_membership_audit_page.dart';

class TenantAdminPage extends StatefulWidget {
  const TenantAdminPage({
    super.key,
    required this.identity,
    this.membershipService,
    this.currentUserUid,
  });

  final AppIdentity identity;
  final TenantMembershipService? membershipService;
  final String? currentUserUid;

  @override
  State<TenantAdminPage> createState() => _TenantAdminPageState();
}

class _TenantAdminPageState extends State<TenantAdminPage> {
  String? _processingMembershipId;
  final TextEditingController _searchController = TextEditingController();
  String _selectedRoleFilter = 'todos';
  String _selectedStatusFilter = 'todos';
  int _currentPage = 0;
  int _pageSize = 10;
  Map<String, bool>? _policy;
  bool _savingPolicy = false;

  TenantMembershipService get _membershipService =>
      widget.membershipService ?? TenantMembershipService(FirebaseFirestore.instance);

  String? get _actorUid =>
      widget.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;

  String get _actorRole => widget.identity.role.trim().toLowerCase();

  bool get _canOpenTenantArea {
    return _actorRole == 'owner' ||
        _actorRole == 'platform_admin' ||
        _actorRole == 'gerente' ||
        _actorRole == 'representante';
  }

  bool get _allowManagerDisableRepresentative =>
      _policy?['allowManagerDisableRepresentative'] ?? false;

  bool get _allowRepresentativeDisableSeller =>
      _policy?['allowRepresentativeDisableSeller'] ?? true;

  TenantAdminPermissions get _permissions => TenantAdminPermissions(
        actorRole: _actorRole,
        allowManagerDisableRepresentative: _allowManagerDisableRepresentative,
        allowRepresentativeDisableSeller: _allowRepresentativeDisableSeller,
      );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    if (widget.identity.isMock) {
      return;
    }

    final policy = await _membershipService.loadGovernancePolicy(
      widget.identity.tenantId,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _policy = policy;
    });
  }

  Future<void> _savePolicy({
    required bool allowManagerDisableRepresentative,
    required bool allowRepresentativeDisableSeller,
  }) async {
    final actorUid = _actorUid;
    if (_actorRole != 'owner' || actorUid == null || actorUid.isEmpty) {
      _showMessage('Somente owner pode alterar politicas deste tenant.');
      return;
    }

    setState(() {
      _savingPolicy = true;
    });

    try {
      await _membershipService.updateGovernancePolicy(
        tenantId: widget.identity.tenantId,
        allowManagerDisableRepresentative: allowManagerDisableRepresentative,
        allowRepresentativeDisableSeller: allowRepresentativeDisableSeller,
        allowPersonalWorkspace: true,
        updatedByUid: actorUid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _policy = {
          'allowManagerDisableRepresentative':
              allowManagerDisableRepresentative,
          'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
        };
      });
      _showMessage('Politica de governanca atualizada.');
    } catch (error) {
      _showMessage(error is StateError
          ? error.message.toString()
          : 'Nao foi possivel atualizar a politica agora.');
    } finally {
      if (mounted) {
        setState(() {
          _savingPolicy = false;
        });
      }
    }
  }

  Future<void> _revoke(TenantMembership membership) async {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _membershipService.revokeMembershipByActor(
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Membership revogado com sucesso.');
    } catch (error) {
      _showMessage(error is StateError
          ? error.message.toString()
          : 'Nao foi possivel revogar o membership.');
    } finally {
      if (mounted) {
        setState(() {
          _processingMembershipId = null;
        });
      }
    }
  }

  Future<void> _reactivate(TenantMembership membership) async {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _membershipService.reactivateMembershipByActor(
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Membership reativado com sucesso.');
    } catch (error) {
      _showMessage(error is StateError
          ? error.message.toString()
          : 'Nao foi possivel reativar o membership.');
    } finally {
      if (mounted) {
        setState(() {
          _processingMembershipId = null;
        });
      }
    }
  }

  Future<void> _changeRole(TenantMembership membership, String newRole) async {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _membershipService.changeRoleByActor(
        membershipId: membership.membershipId,
        newRole: newRole,
        actorUid: actorUid,
      );
      _showMessage('Papel atualizado para $newRole.');
    } catch (error) {
      _showMessage(error is StateError
          ? error.message.toString()
          : 'Nao foi possivel alterar o papel.');
    } finally {
      if (mounted) {
        setState(() {
          _processingMembershipId = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<String> _availableRoleTargets(TenantMembership membership) {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      return const [];
    }

    return _permissions.availableRoleTargets(
      membership,
      actorUid: actorUid,
    );
  }

  List<TenantMembership> _applyFilters(List<TenantMembership> memberships) {
    final query = _searchController.text.trim().toLowerCase();

    return memberships.where((membership) {
      final role = membership.role.trim().toLowerCase();
      final status = membership.isActive
          ? 'ativo'
          : membership.state == TenantMembershipState.revoked
              ? 'revogado'
              : 'inativo';
      final matchesRole =
          _selectedRoleFilter == 'todos' || role == _selectedRoleFilter;
      final matchesStatus =
          _selectedStatusFilter == 'todos' || status == _selectedStatusFilter;

      if (!matchesRole || !matchesStatus) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return membership.uid.toLowerCase().contains(query) ||
          membership.membershipId.toLowerCase().contains(query) ||
          role.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Administracao do tenant',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie membros ativos e revogados do tenant ${widget.identity.tenantName}.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (!_canOpenTenantArea)
              const AppInfoCard(
                title: 'Acesso restrito',
                subtitle:
                    'Somente owner, gerente, representante e platform admin acessam esta area.',
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Politica de governanca do tenant',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _allowManagerDisableRepresentative,
                        title: const Text(
                          'Gerente pode desligar representante',
                        ),
                        contentPadding: EdgeInsets.zero,
                        onChanged: _savingPolicy || _actorRole != 'owner'
                            ? null
                            : (value) {
                                _savePolicy(
                                  allowManagerDisableRepresentative: value,
                                  allowRepresentativeDisableSeller:
                                      _allowRepresentativeDisableSeller,
                                );
                              },
                      ),
                      SwitchListTile(
                        value: _allowRepresentativeDisableSeller,
                        title: const Text(
                          'Representante pode desligar vendedor',
                        ),
                        contentPadding: EdgeInsets.zero,
                        onChanged: _savingPolicy || _actorRole != 'owner'
                            ? null
                            : (value) {
                                _savePolicy(
                                  allowManagerDisableRepresentative:
                                      _allowManagerDisableRepresentative,
                                  allowRepresentativeDisableSeller: value,
                                );
                              },
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
                    const Text(
                      'Convites de acesso ficam em uma tela dedicada dentro de Tenant.',
                    ),
                    const SizedBox(height: 10),
                    if (_actorRole == 'owner')
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TenantInvitationsPage(
                                identity: widget.identity,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.mail_outline),
                        label: const Text('Abrir convites'),
                      )
                    else
                      Text(
                        'Somente owner pode enviar e gerenciar convites.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TenantMembershipAuditPage(
                              identity: widget.identity,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Ver auditoria de memberships'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _MembershipFilters(
              searchController: _searchController,
              selectedRoleFilter: _selectedRoleFilter,
              selectedStatusFilter: _selectedStatusFilter,
              onSearchChanged: (_) {
                setState(() {
                  _currentPage = 0;
                });
              },
              onRoleChanged: (value) {
                setState(() {
                  _selectedRoleFilter = value;
                  _currentPage = 0;
                });
              },
              onStatusChanged: (value) {
                setState(() {
                  _selectedStatusFilter = value;
                  _currentPage = 0;
                });
              },
            ),
            const SizedBox(height: 12),
            if (widget.identity.isMock)
              const AppInfoCard(
                title: 'Modo mock',
                subtitle:
                    'A administracao real de memberships usa Firestore e Firebase Auth.',
              )
            else
              StreamBuilder<List<TenantMembership>>(
                stream: _membershipService
                    .watchMembershipsForTenant(widget.identity.tenantId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppInfoCard(
                      title: 'Carregando memberships',
                      subtitle: 'Buscando membros vinculados ao tenant...',
                    );
                  }

                  final memberships = snapshot.data ?? const [];
                  if (memberships.isEmpty) {
                    return const AppInfoCard(
                      title: 'Sem memberships',
                      subtitle: 'Nenhum usuario vinculado ao tenant no momento.',
                    );
                  }

                  final filteredMemberships = _applyFilters(memberships);
                  if (filteredMemberships.isEmpty) {
                    return const AppInfoCard(
                      title: 'Sem resultados para o filtro atual',
                      subtitle:
                          'Ajuste busca, papel ou status para visualizar os memberships.',
                    );
                  }

                  final page = buildPaginationSlice(
                    source: filteredMemberships,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        (membership) => _MembershipCard(
                          membership: membership,
                          processing:
                              _processingMembershipId == membership.membershipId,
                          availableRoles: _availableRoleTargets(membership),
                          onRevoke: membership.isActive &&
                                  (_actorUid != null &&
                                      _permissions.canRevoke(
                                        membership,
                                        actorUid: _actorUid!,
                                      ))
                              ? () => _revoke(membership)
                              : null,
                          onReactivate: membership.isActive ||
                                  _actorUid == null ||
                                  !_permissions.canReactivate(
                                    membership,
                                    actorUid: _actorUid!,
                                  )
                              ? null
                              : () => _reactivate(membership),
                          onChangeRole: (newRole) =>
                              _changeRole(membership, newRole),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MembershipFilters extends StatelessWidget {
  const _MembershipFilters({
    required this.searchController,
    required this.selectedRoleFilter,
    required this.selectedStatusFilter,
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String selectedRoleFilter;
  final String selectedStatusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Buscar membro',
                hintText: 'uid, membershipId ou papel',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedRoleFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Papel',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'owner', child: Text('owner')),
                      DropdownMenuItem(value: 'gerente', child: Text('gerente')),
                      DropdownMenuItem(
                        value: 'representante',
                        child: Text('representante'),
                      ),
                      DropdownMenuItem(value: 'vendedor', child: Text('vendedor')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onRoleChanged(value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedStatusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Status',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'ativo', child: Text('Ativo')),
                      DropdownMenuItem(value: 'revogado', child: Text('Revogado')),
                      DropdownMenuItem(value: 'inativo', child: Text('Inativo')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onStatusChanged(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.membership,
    required this.processing,
    required this.availableRoles,
    this.onRevoke,
    this.onReactivate,
    this.onChangeRole,
  });

  final TenantMembership membership;
  final bool processing;
  final List<String> availableRoles;
  final VoidCallback? onRevoke;
  final VoidCallback? onReactivate;
  final ValueChanged<String>? onChangeRole;

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
                  membership.uid,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(
                  label: Text(
                    membership.isActive ? 'Ativo' : membership.state.label,
                  ),
                ),
                if (membership.defaultTenant)
                  const Chip(label: Text('Tenant padrao')),
              ],
            ),
            const SizedBox(height: 8),
            Text('Perfil: ${membership.role}'),
            const SizedBox(height: 6),
            Text('Membership: ${membership.membershipId}'),
            if (membership.revokedByUid != null &&
                membership.revokedByUid!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Revogado por: ${membership.revokedByUid}'),
            ],
            if (membership.revokedReason != null &&
                membership.revokedReason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Motivo: ${membership.revokedReason}'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('revoke_${membership.membershipId}'),
                  onPressed: processing ? null : onRevoke,
                  icon: const Icon(Icons.block),
                  label: Text(processing ? 'Processando...' : 'Revogar'),
                ),
                FilledButton.tonalIcon(
                  key: Key('reactivate_${membership.membershipId}'),
                  onPressed: processing ? null : onReactivate,
                  icon: const Icon(Icons.refresh),
                  label: Text(processing ? 'Processando...' : 'Reativar'),
                ),
                PopupMenuButton<String>(
                  enabled: !processing && availableRoles.isNotEmpty,
                  onSelected: onChangeRole,
                  itemBuilder: (context) => availableRoles
                      .map(
                        (role) => PopupMenuItem<String>(
                          key: Key(
                            'change_role_${membership.membershipId}_$role',
                          ),
                          value: role,
                          child: Text('Alterar para $role'),
                        ),
                      )
                      .toList(),
                  child: OutlinedButton.icon(
                    key: Key('change_role_${membership.membershipId}'),
                    onPressed: null,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Alterar papel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

