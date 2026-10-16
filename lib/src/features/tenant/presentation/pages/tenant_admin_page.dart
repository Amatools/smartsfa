import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_membership.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../../shared/presentation/widgets/app_pagination_bar.dart';
import '../../../../shared/presentation/widgets/pagination_slice.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../domain/tenant_membership_filter.dart';
import '../../domain/tenant_admin_permissions.dart';
import '../controllers/tenant_admin_action_controller.dart';
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
      widget.membershipService ??
      TenantMembershipService(FirebaseFirestore.instance);

  TenantAdminActionController get _actions =>
      TenantAdminActionController(_membershipService);

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

  bool get _allowManagerSendInvites =>
      _policy?['allowManagerSendInvites'] ?? false;

  bool get _allowRepresentativeSendInvites =>
      _policy?['allowRepresentativeSendInvites'] ?? false;

  bool get _canOpenInvitationsPage {
    if (_actorRole == 'owner' || _actorRole == 'platform_admin') {
      return true;
    }

    if (_actorRole == 'gerente') {
      return _allowManagerSendInvites;
    }

    if (_actorRole == 'representante') {
      return _allowRepresentativeSendInvites;
    }

    return false;
  }

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
    try {
      final policy = await _membershipService.loadGovernancePolicy(
        widget.identity.tenantId,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _policy = policy;
      });
    } catch (_) {
      // Best effort: keep default policy values when backend is unavailable.
    }
  }

  Future<void> _savePolicy({
    required bool allowManagerDisableRepresentative,
    required bool allowRepresentativeDisableSeller,
    required bool allowManagerSendInvites,
    required bool allowRepresentativeSendInvites,
  }) async {
    final actorUid = _actorUid;
    if (_actorRole != 'owner' || actorUid == null || actorUid.isEmpty) {
      _showMessage('Somente owner pode alterar políticas deste tenant.');
      return;
    }

    setState(() {
      _savingPolicy = true;
    });

    try {
      final updatedPolicy = await _actions.savePolicy(
        tenantId: widget.identity.tenantId,
        allowManagerDisableRepresentative: allowManagerDisableRepresentative,
        allowRepresentativeDisableSeller: allowRepresentativeDisableSeller,
        allowManagerSendInvites: allowManagerSendInvites,
        allowRepresentativeSendInvites: allowRepresentativeSendInvites,
        updatedByUid: actorUid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _policy = updatedPolicy;
      });
      _showMessage('Política de governança atualizada.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Não foi possível atualizar a política agora.',
      );
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
      _showMessage('Sessão expirada. Faça login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _actions.revokeMembership(
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Membership revogado com sucesso.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Não foi possível revogar o membership.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingMembershipId = null;
        });
      }
    }
  }

  Future<void> _deactivate(TenantMembership membership) async {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      _showMessage('Sessão expirada. Faça login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _actions.deactivateMembership(
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Membership inativado com sucesso.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : error is FirebaseException
            ? 'Não foi possível inativar o membership (${error.code}).'
            : 'Não foi possível inativar o membership.',
      );
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
      _showMessage('Sessão expirada. Faça login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _actions.reactivateMembership(
        membershipId: membership.membershipId,
        actorUid: actorUid,
      );
      _showMessage('Membership reativado com sucesso.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Não foi possível reativar o membership.',
      );
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
      _showMessage('Sessão expirada. Faça login novamente.');
      return;
    }

    setState(() {
      _processingMembershipId = membership.membershipId;
    });

    try {
      await _actions.changeRole(
        membershipId: membership.membershipId,
        newRole: newRole,
        actorUid: actorUid,
      );
      _showMessage('Papel atualizado para $newRole.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Não foi possível alterar o papel.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingMembershipId = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _availableRoleTargets(TenantMembership membership) {
    final actorUid = _actorUid;
    if (actorUid == null || actorUid.isEmpty) {
      return const [];
    }

    return _permissions.availableRoleTargets(membership, actorUid: actorUid);
  }

  List<TenantMembership> _applyFilters(List<TenantMembership> memberships) {
    return TenantMembershipFilter.apply(
      memberships: memberships,
      query: _searchController.text,
      selectedRole: _selectedRoleFilter,
      selectedStatus: _selectedStatusFilter,
    );
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
              'Configurações do workspace',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Gerencie membros ativos e revogados do workspace ${widget.identity.tenantName}.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (!_canOpenTenantArea)
              const AppInfoCard(
                title: 'Acesso restrito',
                subtitle: 'Somente owner, gerente, representante e platform admin acessam esta area.',
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Política de governança do tenant',
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
                                  allowManagerSendInvites:
                                      _allowManagerSendInvites,
                                  allowRepresentativeSendInvites:
                                      _allowRepresentativeSendInvites,
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
                                  allowManagerSendInvites:
                                      _allowManagerSendInvites,
                                  allowRepresentativeSendInvites:
                                      _allowRepresentativeSendInvites,
                                );
                              },
                      ),
                      SwitchListTile(
                        value: _allowManagerSendInvites,
                        title: const Text('Gerente pode enviar convites'),
                        subtitle: const Text(
                          'Quando ligado, gerente pode convidar representante.',
                        ),
                        contentPadding: EdgeInsets.zero,
                        onChanged: _savingPolicy || _actorRole != 'owner'
                            ? null
                            : (value) {
                                _savePolicy(
                                  allowManagerDisableRepresentative:
                                      _allowManagerDisableRepresentative,
                                  allowRepresentativeDisableSeller:
                                      _allowRepresentativeDisableSeller,
                                  allowManagerSendInvites: value,
                                  allowRepresentativeSendInvites:
                                      _allowRepresentativeSendInvites,
                                );
                              },
                      ),
                      SwitchListTile(
                        value: _allowRepresentativeSendInvites,
                        title: const Text('Representante pode enviar convites'),
                        subtitle: const Text(
                          'Quando ligado, representante pode convidar vendedor.',
                        ),
                        contentPadding: EdgeInsets.zero,
                        onChanged: _savingPolicy || _actorRole != 'owner'
                            ? null
                            : (value) {
                                _savePolicy(
                                  allowManagerDisableRepresentative:
                                      _allowManagerDisableRepresentative,
                                  allowRepresentativeDisableSeller:
                                      _allowRepresentativeDisableSeller,
                                  allowManagerSendInvites:
                                      _allowManagerSendInvites,
                                  allowRepresentativeSendInvites: value,
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
                    if (_canOpenInvitationsPage)
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
                        'Envio de convites bloqueado para seu perfil. O owner pode liberar isso na política do tenant.',
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
            StreamBuilder<List<TenantMembership>>(
              stream: _membershipService.watchMembershipsForTenant(
                widget.identity.tenantId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final isPermissionDenied =
                      error is FirebaseException &&
                      error.code == 'permission-denied';
                  if (isPermissionDenied) {
                    return const AppInfoCard(
                      title: 'Sem permissão para memberships',
                      subtitle: 'Seu perfil atual não possui acesso para listar memberships deste tenant.',
                    );
                  }

                  return AppInfoCard(
                    title: 'Falha ao carregar memberships',
                    subtitle: '$error',
                  );
                }

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
                    subtitle: 'Ajuste busca, papel ou status para visualizar os memberships.',
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
                    _HierarchyMembershipList(
                      memberships: page.items,
                      tenantId: widget.identity.tenantId,
                      tenantName: widget.identity.tenantName,
                      actorUid: _actorUid,
                      permissions: _permissions,
                      processingMembershipId: _processingMembershipId,
                      availableRoleTargetsBuilder: _availableRoleTargets,
                      onDeactivate: _deactivate,
                      onRevoke: _revoke,
                      onReactivate: _reactivate,
                      onChangeRole: _changeRole,
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

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    IconData? icon,
    String? hintText,
  }) {
    final colors = Theme.of(context).colorScheme;

    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.35),
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: border(colors.outlineVariant.withValues(alpha: 0.45)),
      focusedBorder: border(colors.primary.withValues(alpha: 0.75), width: 1.4),
      errorBorder: border(colors.error.withValues(alpha: 0.75)),
      focusedErrorBorder: border(colors.error, width: 1.4),
    );
  }

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
              decoration: _fieldDecoration(
                context,
                label: 'Buscar membro',
                hintText: 'nome, e-mail, uid, workspace ou papel',
                icon: Icons.search,
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
                    decoration: _fieldDecoration(context, label: 'Papel'),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'owner', child: Text('owner')),
                      DropdownMenuItem(
                        value: 'gerente',
                        child: Text('gerente'),
                      ),
                      DropdownMenuItem(
                        value: 'representante',
                        child: Text('representante'),
                      ),
                      DropdownMenuItem(
                        value: 'vendedor',
                        child: Text('vendedor'),
                      ),
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
                    decoration: _fieldDecoration(context, label: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'ativo', child: Text('Ativo')),
                      DropdownMenuItem(
                        value: 'revogado',
                        child: Text('Revogado'),
                      ),
                      DropdownMenuItem(
                        value: 'inativo',
                        child: Text('Inativo'),
                      ),
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

class _HierarchyMembershipList extends StatefulWidget {
  const _HierarchyMembershipList({
    required this.memberships,
    required this.tenantId,
    required this.tenantName,
    required this.actorUid,
    required this.permissions,
    required this.processingMembershipId,
    required this.availableRoleTargetsBuilder,
    required this.onDeactivate,
    required this.onRevoke,
    required this.onReactivate,
    required this.onChangeRole,
  });

  final List<TenantMembership> memberships;
  final String tenantId;
  final String tenantName;
  final String? actorUid;
  final TenantAdminPermissions permissions;
  final String? processingMembershipId;
  final List<String> Function(TenantMembership membership)
  availableRoleTargetsBuilder;
  final Future<void> Function(TenantMembership membership) onDeactivate;
  final Future<void> Function(TenantMembership membership) onRevoke;
  final Future<void> Function(TenantMembership membership) onReactivate;
  final Future<void> Function(TenantMembership membership, String newRole)
  onChangeRole;

  @override
  State<_HierarchyMembershipList> createState() => _HierarchyMembershipListState();
}

class _HierarchyMembershipListState extends State<_HierarchyMembershipList> {
  final Set<String> _expandedNodeKeys = <String>{};
  bool _workspaceExpanded = true;
  bool _initializedExpansion = false;

  String _displayName(TenantMembership membership) {
    final userName = (membership.userName ?? '').trim();
    if (userName.isNotEmpty) {
      return userName;
    }

    final userEmail = (membership.userEmail ?? '').trim();
    if (userEmail.isNotEmpty) {
      final prefix = userEmail.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix;
      }
    }

    final role = membership.role.trim();
    if (role.isNotEmpty) {
      return role;
    }

    return membership.uid;
  }

  List<_HierarchyNode> _buildNodes() {
    final active = widget.memberships
        .where((item) => item.isActive)
        .toList(growable: false);
    final nodes = <_HierarchyNode>[];

    final owners = active
        .where((membership) => membership.role.trim().toLowerCase() == 'owner')
        .toList(growable: false)
      ..sort(
        (a, b) => _displayName(a).toLowerCase().compareTo(
          _displayName(b).toLowerCase(),
        ),
      );

    for (final owner in owners) {
      final ownerNodeKey = owner.membershipId;
      nodes.add(
        _HierarchyNode(
          membership: owner,
          level: 0,
          nodeKey: ownerNodeKey,
          parentNodeKey: null,
        ),
      );

      final managers = active
          .where(
            (membership) =>
                membership.role.trim().toLowerCase() == 'gerente' &&
                membership.ownerId == owner.uid &&
                membership.uid != owner.uid,
          )
          .toList(growable: false)
        ..sort(
          (a, b) => _displayName(a).toLowerCase().compareTo(
            _displayName(b).toLowerCase(),
          ),
        );

      if (managers.isNotEmpty) {
        for (final manager in managers) {
          final managerNodeKey = manager.membershipId;
          nodes.add(
            _HierarchyNode(
              membership: manager,
              level: 1,
              nodeKey: managerNodeKey,
              parentNodeKey: ownerNodeKey,
            ),
          );

          final reps = active
              .where(
                (membership) =>
                    membership.role.trim().toLowerCase() == 'representante' &&
                    membership.ownerId == owner.uid &&
                    membership.uid != owner.uid &&
                    membership.gerenteId == manager.uid,
              )
              .toList(growable: false)
            ..sort(
              (a, b) => _displayName(a).toLowerCase().compareTo(
                _displayName(b).toLowerCase(),
              ),
            );

          for (final rep in reps) {
            final repNodeKey = rep.membershipId;
            nodes.add(
              _HierarchyNode(
                membership: rep,
                level: 2,
                nodeKey: repNodeKey,
                parentNodeKey: managerNodeKey,
              ),
            );

            final sellers = active
                .where(
                  (membership) =>
                      membership.role.trim().toLowerCase() == 'vendedor' &&
                      membership.ownerId == owner.uid &&
                      membership.uid != owner.uid &&
                      membership.representanteId == rep.uid,
                )
                .toList(growable: false)
              ..sort(
                (a, b) => _displayName(a).toLowerCase().compareTo(
                  _displayName(b).toLowerCase(),
                ),
              );

            for (final seller in sellers) {
              nodes.add(
                _HierarchyNode(
                  membership: seller,
                  level: 3,
                  nodeKey: seller.membershipId,
                  parentNodeKey: repNodeKey,
                ),
              );
            }
          }
        }
      }

      final ownerReps = active
          .where(
            (membership) =>
                membership.role.trim().toLowerCase() == 'representante' &&
                membership.ownerId == owner.uid &&
                membership.uid != owner.uid &&
                membership.gerenteId == owner.uid,
          )
          .toList(growable: false)
        ..sort(
          (a, b) => _displayName(a).toLowerCase().compareTo(
            _displayName(b).toLowerCase(),
          ),
        );

      for (final rep in ownerReps) {
        final repNodeKey = rep.membershipId;
        nodes.add(
          _HierarchyNode(
            membership: rep,
            level: 1,
            nodeKey: repNodeKey,
            parentNodeKey: ownerNodeKey,
          ),
        );

        final sellers = active
            .where(
              (membership) =>
                  membership.role.trim().toLowerCase() == 'vendedor' &&
                  membership.ownerId == owner.uid &&
                  membership.uid != owner.uid &&
                  membership.representanteId == rep.uid,
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _displayName(a).toLowerCase().compareTo(
              _displayName(b).toLowerCase(),
            ),
          );

        for (final seller in sellers) {
          nodes.add(
            _HierarchyNode(
              membership: seller,
              level: 2,
              nodeKey: seller.membershipId,
              parentNodeKey: repNodeKey,
            ),
          );
        }
      }
    }

    final covered = nodes.map((node) => node.membership.uid).toSet();
    final orphans = active
        .where((membership) => !covered.contains(membership.uid))
        .toList(growable: false)
      ..sort(
        (a, b) => _displayName(a).toLowerCase().compareTo(
          _displayName(b).toLowerCase(),
        ),
      );

    for (final orphan in orphans) {
      nodes.add(
        _HierarchyNode(
          membership: orphan,
          level: 0,
          orphan: true,
          nodeKey: orphan.membershipId,
          parentNodeKey: null,
        ),
      );
    }

    final inactive = widget.memberships
        .where((item) => !item.isActive)
        .toList(growable: false)
      ..sort(
        (a, b) => _displayName(a).toLowerCase().compareTo(
          _displayName(b).toLowerCase(),
        ),
      );

    for (final item in inactive) {
      nodes.add(
        _HierarchyNode(
          membership: item,
          level: 0,
          inactive: true,
          nodeKey: item.membershipId,
          parentNodeKey: null,
        ),
      );
    }

    return nodes;
  }

  bool _isVisible(_HierarchyNode node) {
    if (!_workspaceExpanded) {
      return false;
    }

    var parentKey = node.parentNodeKey;
    while (parentKey != null) {
      if (!_expandedNodeKeys.contains(parentKey)) {
        return false;
      }
      final parentNode = _lastTree.firstWhere(
        (item) => item.nodeKey == parentKey,
        orElse: () => const _HierarchyNode.missing(),
      );
      parentKey = parentNode.parentNodeKey;
    }

    return true;
  }

  bool _hasChildren(_HierarchyNode node, List<_HierarchyNode> allNodes) {
    return allNodes.any((item) => item.parentNodeKey == node.nodeKey);
  }

  List<_HierarchyNode> _lastTree = const [];

  String _roleLabel(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'owner') {
      return 'Owner';
    }
    if (normalized == 'gerente') {
      return 'Gerente';
    }
    if (normalized == 'representante') {
      return 'Representante';
    }
    if (normalized == 'vendedor') {
      return 'Vendedor';
    }
    return role;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _buildNodes();
    _lastTree = nodes;

    if (!_initializedExpansion) {
      for (final node in nodes) {
        if (_hasChildren(node, nodes)) {
          _expandedNodeKeys.add(node.nodeKey);
        }
      }
      _initializedExpansion = true;
    }

    final visibleNodes = nodes.where(_isVisible).toList(growable: false);

    final activeCount = widget.memberships.where((item) => item.isActive).length;
    final inactiveCount = widget.memberships.length - activeCount;

    return Card(
      key: const Key('hierarchy_membership_list'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const Key('workspace_group_header'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _workspaceExpanded = !_workspaceExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Row(
                  children: [
                    Icon(
                      _workspaceExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Workspace: ${widget.tenantName} (${widget.tenantId})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      'Ativos: $activeCount  |  Inativos: $inactiveCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!_workspaceExpanded)
              Text(
                'Lista recolhida. Toque no workspace para expandir.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Pessoa / Hierarquia',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Perfil',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Ações',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              ...visibleNodes.map((node) {
                final membership = node.membership;
                final processing =
                    widget.processingMembershipId == membership.membershipId;
                final availableRoles =
                    widget.availableRoleTargetsBuilder(membership);
                final canChangeRole =
                    !processing &&
                    availableRoles.isNotEmpty &&
                    widget.actorUid != null;
                final canRevoke =
                    membership.isActive &&
                    widget.actorUid != null &&
                    widget.permissions.canRevoke(
                      membership,
                      actorUid: widget.actorUid!,
                    );
                final canDeactivate =
                    membership.isActive &&
                    widget.actorUid != null &&
                    widget.permissions.canDeactivate(
                      membership,
                      actorUid: widget.actorUid!,
                    );
                final canReactivate =
                    !membership.isActive &&
                    widget.actorUid != null &&
                    widget.permissions.canReactivate(
                      membership,
                      actorUid: widget.actorUid!,
                    );

                final displayName = _displayName(membership);
                final userEmail = (membership.userEmail ?? '').trim();
                final orphanLabel = node.orphan
                    ? ' [inconsistência hierárquica]'
                    : '';
                final inactiveLabel = node.inactive ? ' [inativo]' : '';
                final hasChildren = _hasChildren(node, nodes);
                final expanded = _expandedNodeKeys.contains(node.nodeKey);
                final indent = node.level * 18.0;

                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(width: indent),
                                  if (hasChildren)
                                    InkWell(
                                      key: Key('toggle_${node.nodeKey}'),
                                      onTap: () {
                                        setState(() {
                                          if (expanded) {
                                            _expandedNodeKeys.remove(node.nodeKey);
                                          } else {
                                            _expandedNodeKeys.add(node.nodeKey);
                                          }
                                        });
                                      },
                                      child: Icon(
                                        expanded
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_right,
                                        size: 18,
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 18),
                                  Expanded(
                                    child: Text(
                                      '$displayName (${membership.uid})$orphanLabel$inactiveLabel',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              if (userEmail.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.only(left: indent + 18),
                                  child: Text(
                                    userEmail,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _roleLabel(membership.role),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Chip(
                                label: Text(
                                  membership.isActive
                                      ? 'Ativo'
                                      : membership.state.label,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              if (membership.defaultTenant)
                                const Chip(
                                  label: Text('Padrão'),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                key: Key('deactivate_${membership.membershipId}'),
                                onPressed: processing || !canDeactivate
                                    ? null
                                    : () => widget.onDeactivate(membership),
                                icon: const Icon(Icons.pause_circle_outline),
                                label: Text(
                                  processing ? 'Processando...' : 'Inativar',
                                ),
                              ),
                              OutlinedButton.icon(
                                key: Key('revoke_${membership.membershipId}'),
                                onPressed: processing || !canRevoke
                                    ? null
                                    : () => widget.onRevoke(membership),
                                icon: const Icon(Icons.block),
                                label: Text(
                                  processing ? 'Processando...' : 'Revogar',
                                ),
                              ),
                              FilledButton.tonalIcon(
                                key: Key('reactivate_${membership.membershipId}'),
                                onPressed: processing || !canReactivate
                                    ? null
                                    : () => widget.onReactivate(membership),
                                icon: const Icon(Icons.refresh),
                                label: Text(
                                  processing ? 'Processando...' : 'Reativar',
                                ),
                              ),
                              PopupMenuButton<String>(
                                enabled: canChangeRole,
                                onSelected: (newRole) =>
                                    widget.onChangeRole(membership, newRole),
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
                                child: AbsorbPointer(
                                  child: OutlinedButton.icon(
                                    key: Key('change_role_${membership.membershipId}'),
                                    onPressed: canChangeRole ? () {} : null,
                                    icon: const Icon(
                                      Icons.manage_accounts_outlined,
                                    ),
                                    label: const Text('Alterar papel'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _HierarchyNode {
  const _HierarchyNode.missing()
    : membership = const TenantMembership(
        membershipId: '',
        tenantId: '',
        uid: '',
        role: '',
        ativo: false,
        defaultTenant: false,
        ownerId: '',
        gerenteId: '',
        representanteId: '',
        vendedorId: '',
      ),
      level = 0,
      orphan = false,
      inactive = false,
      nodeKey = '',
      parentNodeKey = null;

  const _HierarchyNode({
    required this.membership,
    required this.level,
    required this.nodeKey,
    required this.parentNodeKey,
    this.orphan = false,
    this.inactive = false,
  });

  final TenantMembership membership;
  final int level;
  final String nodeKey;
  final String? parentNodeKey;
  final bool orphan;
  final bool inactive;
}
