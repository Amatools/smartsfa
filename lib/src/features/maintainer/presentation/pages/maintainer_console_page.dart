import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../shared/utils/window_open.dart';
import '../../domain/maintainer_access_decision.dart';
import '../../services/maintainer_audit_service.dart';
import '../../services/maintainer_access_service.dart';
import '../../services/maintainer_impersonation_service.dart';
import '../../services/maintainer_overview_service.dart';
import '../../services/maintainer_user_admin_service.dart';

enum _MaintainerConsoleTab { home, clients, users, audit, impersonation }

enum _MaintainerUserScope { clients, platformUsers }

enum _MaintainerUserAction {
  editProfile,
  editPermissionMatrix,
  deleteUser,
  toggleAccount,
  grant7days,
  grant30days,
  normalizeBilling,
  suspendBilling,
}

enum _MaintainerUserSortField {
  user,
  uid,
  tenants,
  account,
  billing,
  graceUntil,
  updatedAt,
}

class MaintainerConsolePage extends StatefulWidget {
  const MaintainerConsolePage({
    super.key,
    this.activeTenant,
    this.membershipRoleOverride,
  });

  final TenantEntryOption? activeTenant;
  final String? membershipRoleOverride;

  @override
  State<MaintainerConsolePage> createState() => _MaintainerConsolePageState();
}

class _MaintainerConsolePageState extends State<MaintainerConsolePage> {
  late final MaintainerAccessService _accessService;
  late final MaintainerAuditService _auditService;
  late final MaintainerImpersonationService _impersonationService;
  late final MaintainerOverviewService _overviewService;
  late final MaintainerUserAdminService _userAdminService;
  late final Stream<List<MaintainerCriticalAuditEntry>> _criticalAuditStream;
  late Future<MaintainerAccessDecision> _accessFuture;
  Future<MaintainerOverviewSnapshot>? _overviewFuture;
  _MaintainerConsoleTab _activeTab = _MaintainerConsoleTab.home;
  String? _selectedTenantId;
  _MaintainerUserSortField _userSortField = _MaintainerUserSortField.user;
  bool _userSortAscending = true;
  int _usersRowsPerPage = 20;
  int _usersPageIndex = 0;
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _auditSearchController = TextEditingController();
    final TextEditingController _impersonationTargetSearchController =
      TextEditingController();
  final TextEditingController _impersonationReasonController =
      TextEditingController();
  final Set<String> _processingUserIds = <String>{};
  String? _impersonationSelectedUid;
  String? _impersonationSelectedMembershipId;
  int _impersonationDurationMinutes = 15;
  bool _impersonationLaunching = false;
  String _impersonationLaunchStatus = '';

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseFirestore.instance;
    _accessService = MaintainerAccessService(firestore);
    _auditService = MaintainerAuditService(firestore);
    _impersonationService = MaintainerImpersonationService();
    _overviewService = MaintainerOverviewService(firestore);
    _userAdminService = MaintainerUserAdminService(firestore);
    _criticalAuditStream =
      _auditService.watchCriticalEvents(limit: 400).asBroadcastStream();
    _reloadAccess();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    _auditSearchController.dispose();
    _impersonationTargetSearchController.dispose();
    _impersonationReasonController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MaintainerConsolePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_resolvedMembershipRole(oldWidget) != _resolvedMembershipRole(widget)) {
      _reloadAccess();
    }
  }

  String _resolvedMembershipRole(MaintainerConsolePage widgetValue) {
    final override = (widgetValue.membershipRoleOverride ?? '').trim();
    if (override.isNotEmpty) {
      return override;
    }
    return (widgetValue.activeTenant?.role ?? '').trim();
  }

  void _reloadAccess() {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    _accessFuture = _accessService.evaluateAccess(
      uid: uid,
      membershipRole: _resolvedMembershipRole(widget),
    );
    _overviewFuture = null;
  }

  void _reloadOverview() {
    setState(() {
      _overviewFuture = _overviewService.loadSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<MaintainerAccessDecision>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final decision = snapshot.data;
        if (decision == null || !decision.granted) {
          return _buildAccessDenied(
            context,
            reason:
                decision?.reason ??
                'Nao foi possivel validar acesso ao painel.',
          );
        }

        final canViewHome = decision.can(MaintainerPermission.viewHome);
        final canViewOverview = decision.can(MaintainerPermission.viewOverview);
        final canViewUsers = decision.can(MaintainerPermission.viewUsers);
          final canViewAudit = canViewUsers;
          final canManageImpersonation = decision.can(
            MaintainerPermission.manageImpersonation,
          );
          final activeTab = canViewUsers
          ? (_activeTab == _MaintainerConsoleTab.impersonation
            ? (canManageImpersonation
              ? _MaintainerConsoleTab.impersonation
              : _MaintainerConsoleTab.home)
            : (_activeTab == _MaintainerConsoleTab.audit
              ? _MaintainerConsoleTab.audit
              : (_activeTab == _MaintainerConsoleTab.users
                ? _MaintainerConsoleTab.users
                : (_activeTab == _MaintainerConsoleTab.clients
                  ? _MaintainerConsoleTab.clients
                  : _MaintainerConsoleTab.home))))
          : _MaintainerConsoleTab.home;

        if (!canViewHome && !canViewUsers) {
          return _buildAccessDenied(
            context,
            reason: 'Conta autenticada sem permissoes efetivas para exibir modulos do painel de mantenedor.',
          );
        }

        _overviewFuture ??= _overviewService.loadSnapshot();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Painel de mantenedor', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Acesso de plataforma validado por papel e cadastro de seguranca.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _buildMainTabs(
              canViewUsers: canViewUsers,
              canManageImpersonation: canManageImpersonation,
            ),
            const SizedBox(height: 16),
            if (activeTab == _MaintainerConsoleTab.home) ...[
              _buildSecurityCard(context, decision),
              if (canViewOverview) ...[
                const SizedBox(height: 16),
                _buildOverviewCard(context),
              ],
              const SizedBox(height: 16),
              _buildRoadmapCard(context),
            ] else if (activeTab == _MaintainerConsoleTab.clients) ...[
              _buildUserAdminCard(
                context,
                decision,
                scope: _MaintainerUserScope.clients,
              ),
            ] else if (activeTab == _MaintainerConsoleTab.users) ...[
              _buildUserAdminCard(
                context,
                decision,
                scope: _MaintainerUserScope.platformUsers,
              ),
            ] else ...[
              if (activeTab == _MaintainerConsoleTab.audit && canViewAudit)
                _buildAuditCard(context),
              if (activeTab == _MaintainerConsoleTab.impersonation &&
                  canManageImpersonation)
                _buildImpersonationCard(context),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMainTabs({
    required bool canViewUsers,
    required bool canManageImpersonation,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Tela inicial'),
          selected: _activeTab == _MaintainerConsoleTab.home,
          onSelected: (_) {
            setState(() {
              _activeTab = _MaintainerConsoleTab.home;
            });
          },
        ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Gestao de cliente'),
            selected: _activeTab == _MaintainerConsoleTab.clients,
            onSelected: (_) {
              setState(() {
                _activeTab = _MaintainerConsoleTab.clients;
              });
            },
          ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Gestao de usuarios'),
            selected: _activeTab == _MaintainerConsoleTab.users,
            onSelected: (_) {
              setState(() {
                _activeTab = _MaintainerConsoleTab.users;
              });
            },
          ),
        if (canViewUsers)
          ChoiceChip(
            label: const Text('Auditoria'),
            selected: _activeTab == _MaintainerConsoleTab.audit,
            onSelected: (_) {
              setState(() {
                _activeTab = _MaintainerConsoleTab.audit;
              });
            },
          ),
        if (canManageImpersonation)
          ChoiceChip(
            label: const Text('Acesso assistido'),
            selected: _activeTab == _MaintainerConsoleTab.impersonation,
            onSelected: (_) {
              setState(() {
                _activeTab = _MaintainerConsoleTab.impersonation;
              });
            },
          ),
      ],
    );
  }

  Widget _buildAccessDenied(BuildContext context, {required String reason}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acesso negado ao painel de mantenedor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(reason),
                const SizedBox(height: 12),
                const Text(
                  'Solicite a um platform_admin a concessao do papel adequado e habilitacao explicita do console.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityCard(
    BuildContext context,
    MaintainerAccessDecision decision,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controle de acesso',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text('Papel efetivo: ${decision.effectiveRole}'),
                const SizedBox(height: 6),
                Text('Validacao: ${decision.reason}'),
                const SizedBox(height: 10),
                const Text('Guard rails ativos:'),
                const SizedBox(height: 6),
                const Text('• Papel de plataforma (observer/operator/admin).'),
                const Text('• Conta ativa em usuarios/{uid}.'),
                const Text('• Chave de habilitacao maintainerConsoleEnabled.'),
                const Text(
                  '• Isolamento de modulo em lib/src/features/maintainer.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Permissoes efetivas: ${_formatPermissions(decision.grantedPermissions)}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Visao geral da plataforma',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Atualizar metricas',
                      onPressed: _reloadOverview,
                      icon: const Icon(Icons.refresh_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<MaintainerOverviewSnapshot>(
                  future: _overviewFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    final data = snapshot.data;
                    if (data == null) {
                      return const Text(
                        'Nao foi possivel carregar as metricas agora.',
                      );
                    }

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _metricTile('Tenants', data.totalTenants),
                        _metricTile('Tenants ativos', data.activeTenants),
                        _metricTile('Memberships', data.totalMemberships),
                        _metricTile(
                          'Memberships ativos',
                          data.activeMemberships,
                        ),
                        _metricTile('Convites pendentes', data.pendingInvites),
                        _metricTile(
                          'Solicitacoes pendentes',
                          data.pendingAccessRequests,
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
  }

  Widget _metricTile(String label, int? value) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8DEE7)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          Text(
            value?.toString() ?? '--',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backlog inicial do console',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                const Text('• Diagnostico por tenant e por conta.'),
                const Text('• Auditoria de acoes criticas com filtros.'),
                const Text('• Acoes administrativas seguras com motivo.'),
                const Text(
                  '• Integracao de eventos de billing e lock de conta.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuditCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auditoria critica',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Eventos criticos do painel admin: CRUD de administradores e alteracoes de status/billing.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _auditSearchController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Buscar por acao, ator, alvo ou detalhes',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<MaintainerCriticalAuditEntry>>(
                  stream: _criticalAuditStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    if (snapshot.hasError) {
                      return Text(
                        'Falha ao carregar auditoria: ${snapshot.error}',
                      );
                    }

                    final entries = _filterCriticalAuditEntries(
                      snapshot.data ?? const <MaintainerCriticalAuditEntry>[],
                    );
                    if (entries.isEmpty) {
                      return const Text(
                        'Sem eventos para os filtros atuais.',
                      );
                    }

                    return SizedBox(
                      height: 520,
                      child: ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final actorText = _actorAuditLabel(entry);
                          final targetText = _targetAuditLabel(entry);
                          final detailsText = entry.details.isEmpty
                              ? '--'
                              : entry.details.toString();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 4,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: entry.actionLabel,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      entry.actionLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: actorText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Ator: $actorText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Tooltip(
                                    message: targetText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Alvo: $targetText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Tooltip(
                                    message: detailsText,
                                    waitDuration: const Duration(
                                      milliseconds: 350,
                                    ),
                                    child: Text(
                                      'Detalhes: $detailsText',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'Quando: ${_formatDateTime(entry.createdAt)}',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImpersonationCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StreamBuilder<List<MaintainerUserTenantMembership>>(
              stream: _userAdminService.watchTenantMemberships(limit: 3000),
              builder: (context, membershipsSnapshot) {
                if (membershipsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const LinearProgressIndicator(minHeight: 2);
                }

                if (membershipsSnapshot.hasError) {
                  return Text(
                    'Falha ao carregar memberships para acesso assistido: ${membershipsSnapshot.error}',
                  );
                }

                final memberships =
                    membershipsSnapshot.data ??
                    const <MaintainerUserTenantMembership>[];
                final membershipsByUid =
                    <String, List<MaintainerUserTenantMembership>>{};
                for (final membership in memberships) {
                  if (!membership.isActiveMembership) {
                    continue;
                  }
                  membershipsByUid
                      .putIfAbsent(
                        membership.uid,
                        () => <MaintainerUserTenantMembership>[],
                      )
                      .add(membership);
                }

                return StreamBuilder<Map<String, String>>(
                  stream: _userAdminService.watchTenantNamesById(limit: 3000),
                  builder: (context, tenantNamesSnapshot) {
                    if (tenantNamesSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    if (tenantNamesSnapshot.hasError) {
                      return Text(
                        'Falha ao carregar nomes de tenants: ${tenantNamesSnapshot.error}',
                      );
                    }

                    final tenantNamesById =
                        tenantNamesSnapshot.data ?? const <String, String>{};

                    return StreamBuilder<List<MaintainerUserAccount>>(
                      stream: _userAdminService.watchUsers(limit: 500),
                      builder: (context, usersSnapshot) {
                        if (usersSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LinearProgressIndicator(minHeight: 2);
                        }

                        if (usersSnapshot.hasError) {
                          return Text(
                            'Falha ao carregar usuarios para acesso assistido: ${usersSnapshot.error}',
                          );
                        }

                        final users =
                            usersSnapshot.data ??
                            const <MaintainerUserAccount>[];
                        final targetUsers = users
                            .where(
                              (user) =>
                                  !_isMaintainerAccount(user) &&
                                  user.activeGlobal &&
                                  (membershipsByUid[user.uid]?.isNotEmpty ??
                                      false),
                            )
                            .toList(growable: false)
                          ..sort((a, b) {
                            final nameOrder = _impersonationUserLabel(
                              a,
                            ).compareTo(_impersonationUserLabel(b));
                            if (nameOrder != 0) {
                              return nameOrder;
                            }
                            return a.uid.compareTo(b.uid);
                          });

                        final searchQuery = _impersonationTargetSearchController
                            .text
                            .trim()
                            .toLowerCase();
                        final filteredUsers = targetUsers
                            .where((user) {
                              if (searchQuery.isEmpty) {
                                return true;
                              }
                              return user.uid.toLowerCase().contains(
                                    searchQuery,
                                  ) ||
                                  user.email.toLowerCase().contains(
                                    searchQuery,
                                  ) ||
                                  user.displayName.toLowerCase().contains(
                                    searchQuery,
                                  );
                            })
                            .toList(growable: false);

                        if (filteredUsers.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Acesso assistido (impersonation segura)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Nenhum usuario cliente elegivel encontrado para o filtro atual.',
                              ),
                            ],
                          );
                        }

                        final selectedUid = filteredUsers.any(
                              (user) => user.uid == _impersonationSelectedUid,
                            )
                            ? _impersonationSelectedUid
                            : filteredUsers.first.uid;
                        final selectedUser = filteredUsers.firstWhere(
                          (user) => user.uid == selectedUid,
                        );

                        final selectedMemberships =
                            membershipsByUid[selectedUser.uid] ??
                            const <MaintainerUserTenantMembership>[];
                        final normalizedMemberships = List<
                            MaintainerUserTenantMembership>.from(
                          selectedMemberships,
                        )..sort((a, b) {
                            final aLabel = _tenantFilterLabel(
                              a.tenantId,
                              tenantNamesById,
                            );
                            final bLabel = _tenantFilterLabel(
                              b.tenantId,
                              tenantNamesById,
                            );
                            final labelOrder = aLabel.compareTo(bLabel);
                            if (labelOrder != 0) {
                              return labelOrder;
                            }
                            return a.membershipId.compareTo(b.membershipId);
                          });

                        final selectedMembershipId = normalizedMemberships.any(
                              (item) =>
                                  item.membershipId ==
                                  _impersonationSelectedMembershipId,
                            )
                            ? _impersonationSelectedMembershipId
                            : (normalizedMemberships.isNotEmpty
                                  ? normalizedMemberships.first.membershipId
                                  : null);

                        if ((_impersonationSelectedUid != selectedUid ||
                                _impersonationSelectedMembershipId !=
                                    selectedMembershipId) &&
                            mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _impersonationSelectedUid = selectedUid;
                              _impersonationSelectedMembershipId =
                                  selectedMembershipId;
                            });
                          });
                        }

                        final selectedMembership = selectedMembershipId == null
                            ? null
                            : normalizedMemberships.firstWhere(
                                (item) =>
                                    item.membershipId == selectedMembershipId,
                              );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Acesso assistido (impersonation segura)',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Crie uma sessao temporaria para reproduzir o contexto do cliente em uma nova janela, com motivo obrigatorio e trilha de auditoria.',
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _impersonationTargetSearchController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Buscar usuario cliente (nome, e-mail ou UID)',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedUid,
                              decoration: const InputDecoration(
                                labelText: 'Usuario cliente',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: filteredUsers
                                  .map(
                                    (user) => DropdownMenuItem<String>(
                                      value: user.uid,
                                      child: Text(
                                        _impersonationUserLabel(user),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _impersonationLaunching
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() {
                                        _impersonationSelectedUid = value;
                                        _impersonationSelectedMembershipId =
                                            null;
                                      });
                                    },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedMembershipId,
                              decoration: const InputDecoration(
                                labelText: 'Workspace/Tenant alvo',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: normalizedMemberships
                                  .map(
                                    (membership) =>
                                        DropdownMenuItem<String>(
                                          value: membership.membershipId,
                                          child: Text(
                                            _tenantFilterLabel(
                                              membership.tenantId,
                                              tenantNamesById,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                  )
                                  .toList(growable: false),
                              onChanged: _impersonationLaunching
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _impersonationSelectedMembershipId =
                                            value;
                                      });
                                    },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _impersonationDurationMinutes,
                              decoration: const InputDecoration(
                                labelText: 'Duracao da sessao',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [10, 15, 30]
                                  .map(
                                    (minutes) => DropdownMenuItem<int>(
                                      value: minutes,
                                      child: Text('$minutes minutos'),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _impersonationLaunching
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() {
                                        _impersonationDurationMinutes = value;
                                      });
                                    },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _impersonationReasonController,
                              minLines: 2,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Motivo (obrigatorio)',
                                hintText:
                                    'Descreva o incidente/suporte que justifica o acesso assistido.',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      _impersonationLaunching ||
                                          selectedMembership == null
                                      ? null
                                        : () => _startImpersonationSession(
                                          selectedUser: selectedUser,
                                          selectedMembership:
                                            selectedMembership,
                                        ),
                                  icon: const Icon(Icons.open_in_new_outlined),
                                  label: Text(
                                    _impersonationLaunching
                                        ? 'Abrindo...'
                                        : 'Iniciar sessao assistida',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _impersonationLaunchStatus,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF576074),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Regras: sessao temporaria, motivo obrigatorio, auditoria completa e bloqueio de reuse apos consumo.',
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _impersonationUserLabel(MaintainerUserAccount user) {
    final name = user.displayName.trim();
    final email = user.email.trim();
    final uid = user.uid.trim();
    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name <$email> [$uid]';
    }
    if (email.isNotEmpty) {
      return '$email [$uid]';
    }
    if (name.isNotEmpty) {
      return '$name [$uid]';
    }
    return uid;
  }

  Future<void> _startImpersonationSession({
    required MaintainerUserAccount selectedUser,
    required MaintainerUserTenantMembership selectedMembership,
  }) async {
    final reason = _impersonationReasonController.text.trim();
    if (reason.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe um motivo com pelo menos 8 caracteres.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _impersonationLaunching = true;
      _impersonationLaunchStatus = 'Criando sessao assistida...';
    });

    try {
      final actorUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      final session = await _impersonationService.createSession(
        targetUid: selectedUser.uid,
        targetTenantId: selectedMembership.tenantId,
        targetMembershipId: selectedMembership.membershipId,
        reason: reason,
        durationMinutes: _impersonationDurationMinutes,
        launchOrigin: kIsWeb ? Uri.base.origin : '',
      );

      if (actorUid.isNotEmpty && session.adminRestoreCustomToken.isNotEmpty) {
        MaintainerImpersonationService.cacheAdminRestoreSession(
          uid: actorUid,
          customToken: session.adminRestoreCustomToken,
        );
      }

      final opened = openUrlInNewTab(session.launchUrl);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: session.launchUrl));
      }

      if (!mounted) {
        return;
      }

      final expiresAtLabel = _formatDateTime(session.expiresAt);
      setState(() {
        _impersonationLaunchStatus = opened
            ? 'Sessao aberta em nova janela. Expira em $expiresAtLabel.'
            : 'Link copiado para a area de transferencia. Expira em $expiresAtLabel.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Sessao assistida iniciada com sucesso.'
                : 'Sessao criada. Link copiado para abrir manualmente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _impersonationLaunchStatus = 'Falha ao iniciar sessao assistida.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao iniciar sessao assistida: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _impersonationLaunching = false;
        });
      }
    }
  }

  List<MaintainerCriticalAuditEntry> _filterCriticalAuditEntries(
    List<MaintainerCriticalAuditEntry> entries,
  ) {
    final query = _auditSearchController.text.trim().toLowerCase();
    final filtered = entries.where((entry) {
      if (query.isEmpty) {
        return true;
      }

      final actor = _actorAuditLabel(entry).toLowerCase();
      final target = _targetAuditLabel(entry).toLowerCase();
      final action = entry.actionLabel.toLowerCase();
      final details = entry.details.toString().toLowerCase();

      return actor.contains(query) ||
          target.contains(query) ||
          action.contains(query) ||
          details.contains(query);
    }).toList(growable: false);

    filtered.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? -1;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? -1;
      return bTime.compareTo(aTime);
    });

    return filtered;
  }

  String _actorAuditLabel(MaintainerCriticalAuditEntry entry) {
    final uid = entry.actorUid.trim().isEmpty ? '--' : entry.actorUid.trim();
    final email = entry.actorEmail.trim();
    final label = entry.actorLabel.trim();
    if (label.isNotEmpty && email.isNotEmpty) {
      return '$label <$email> [$uid]';
    }
    if (label.isNotEmpty) {
      return '$label [$uid]';
    }
    if (email.isNotEmpty) {
      return '$email [$uid]';
    }
    return uid;
  }

  String _targetAuditLabel(MaintainerCriticalAuditEntry entry) {
    final uid = entry.targetUid.trim();
    final email = entry.targetEmail.trim();
    final label = entry.targetLabel.trim();

    if (uid.isEmpty && label.isEmpty && email.isEmpty) {
      return '--';
    }

    if (label.isNotEmpty && email.isNotEmpty && uid.isNotEmpty) {
      return '$label <$email> [$uid]';
    }
    if (label.isNotEmpty && uid.isNotEmpty) {
      return '$label [$uid]';
    }
    if (email.isNotEmpty && uid.isNotEmpty) {
      return '$email [$uid]';
    }
    if (label.isNotEmpty) {
      return label;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return uid;
  }

  Widget _buildUserAdminCard(
    BuildContext context,
    MaintainerAccessDecision decision, {
    required _MaintainerUserScope scope,
  }) {
    final canViewUsers = decision.can(MaintainerPermission.viewUsers);
    final canManageUserStatus = decision.can(
      MaintainerPermission.manageUserStatus,
    );
    final canManageUserBilling = decision.can(
      MaintainerPermission.manageUserBilling,
    );
    final canManageUserCrud = decision.can(MaintainerPermission.manageUserCrud);
    final canManageUserPermissions = decision.can(
      MaintainerPermission.manageUserPermissions,
    );
    final isPlatformUserScope = scope == _MaintainerUserScope.platformUsers;
    final title = isPlatformUserScope
        ? 'Gestao de usuarios'
        : 'Gestao de cliente';
    final description = isPlatformUserScope
        ? 'CRUD e matriz de permissoes para usuarios administrativos da plataforma.'
        : 'Lista operacional de contas de clientes com filtros por tenant e acoes de status/billing.';

    if (!canViewUsers) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Gestao de usuarios indisponivel para esta conta.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Solicite permissao maintainer.view.users no cadastro de seguranca.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (isPlatformUserScope && canManageUserCrud)
                      FilledButton.icon(
                        onPressed: () => _openEditUserDialog(context),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Novo usuario'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(description),
                const SizedBox(height: 12),
                StreamBuilder<List<MaintainerUserTenantMembership>>(
                  stream: _userAdminService.watchTenantMemberships(),
                  builder: (context, membershipsSnapshot) {
                    if (membershipsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }

                    if (membershipsSnapshot.hasError) {
                      return Text(
                        'Falha ao carregar memberships: ${membershipsSnapshot.error}',
                      );
                    }

                    final memberships =
                        membershipsSnapshot.data ??
                        const <MaintainerUserTenantMembership>[];
                    final activeMemberships = memberships
                        .where((membership) => membership.isActiveMembership)
                        .toList(growable: false);

                    final tenantIdsByUid = <String, Set<String>>{};
                    for (final membership in activeMemberships) {
                      tenantIdsByUid
                          .putIfAbsent(membership.uid, () => <String>{})
                          .add(membership.tenantId);
                    }

                    final tenantOptions =
                        activeMemberships
                            .map((membership) => membership.tenantId)
                            .toSet()
                            .toList(growable: false)
                          ..sort();

                    final selectedTenant =
                        tenantOptions.contains(_selectedTenantId)
                        ? _selectedTenantId
                        : null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StreamBuilder<Map<String, String>>(
                          stream: _userAdminService.watchTenantNamesById(),
                          builder: (context, tenantNamesSnapshot) {
                            if (tenantNamesSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const LinearProgressIndicator(
                                minHeight: 2,
                              );
                            }

                            if (tenantNamesSnapshot.hasError) {
                              return Text(
                                'Falha ao carregar nomes de tenants: ${tenantNamesSnapshot.error}',
                              );
                            }

                            final tenantNamesById =
                                tenantNamesSnapshot.data ??
                                const <String, String>{};

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildUserFiltersRow(
                                  tenantOptions,
                                  selectedTenant,
                                  tenantNamesById,
                                ),
                                const SizedBox(height: 12),
                                StreamBuilder<List<MaintainerUserAccount>>(
                                  stream: _userAdminService.watchUsers(),
                                  builder: (context, usersSnapshot) {
                                    if (usersSnapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const LinearProgressIndicator(
                                        minHeight: 2,
                                      );
                                    }

                                    if (usersSnapshot.hasError) {
                                      return Text(
                                        'Falha ao carregar usuarios: ${usersSnapshot.error}',
                                      );
                                    }

                                    final allUsers =
                                        usersSnapshot.data ??
                                        const <MaintainerUserAccount>[];
                                    final scopedUsers = _filterUsersByScope(
                                      allUsers,
                                      scope,
                                    );
                                    final filteredUsers = _filterUsers(
                                      scopedUsers,
                                      tenantIdsByUid,
                                      selectedTenantId: selectedTenant,
                                    );
                                    final sortedUsers = _sortUsers(
                                      filteredUsers,
                                      tenantIdsByUid,
                                      tenantNamesById,
                                    );

                                    if (sortedUsers.isEmpty) {
                                      return const Text(
                                        'Nenhum usuario encontrado com os filtros atuais.',
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Resultados: ${sortedUsers.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const SizedBox(height: 8),
                                        _buildUsersTable(
                                          sortedUsers,
                                          tenantIdsByUid,
                                          tenantNamesById,
                                          showBillingColumns:
                                              !isPlatformUserScope,
                                          canManageUserStatus:
                                              canManageUserStatus,
                                          canManageUserBilling:
                                              !isPlatformUserScope &&
                                              canManageUserBilling,
                                          canManageUserCrud:
                                              isPlatformUserScope &&
                                              canManageUserCrud,
                                          canManageUserPermissions:
                                              isPlatformUserScope &&
                                              canManageUserPermissions,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            );
                          },
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
  }

  Widget _buildUserFiltersRow(
    List<String> tenantOptions,
    String? selectedTenant,
    Map<String, String> tenantNamesById,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final stacked = maxWidth < 860;
        final searchWidth = stacked
            ? maxWidth
            : math.min(340.0, maxWidth * 0.34);
        final tenantWidth = stacked
            ? maxWidth
            : math.max(320.0, maxWidth - searchWidth - 12);
        final selectedTenantLabel =
            (selectedTenant == null || selectedTenant.trim().isEmpty)
            ? 'Todos os tenants'
            : _tenantFilterLabel(selectedTenant, tenantNamesById);
        final dropdownEntries = <DropdownMenuEntry<String>>[
          const DropdownMenuEntry<String>(value: '', label: 'Todos os tenants'),
          for (final tenantId in tenantOptions)
            (() {
              final label = _tenantFilterLabel(tenantId, tenantNamesById);
              return DropdownMenuEntry<String>(
                value: tenantId,
                label: label,
                labelWidget: Tooltip(
                  message: label,
                  waitDuration: const Duration(milliseconds: 350),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            })(),
        ];

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: _userSearchController,
                onChanged: (_) {
                  setState(() {
                    _usersPageIndex = 0;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Buscar por e-mail, nome ou uid',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: tenantWidth,
              child: Tooltip(
                message: selectedTenantLabel,
                waitDuration: const Duration(milliseconds: 350),
                child: DropdownMenu<String>(
                  key: ValueKey<String>(selectedTenant ?? ''),
                  width: tenantWidth,
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  menuHeight: 420,
                  initialSelection: selectedTenant ?? '',
                  label: const Text('Filtrar por tenant (workspace)'),
                  hintText: 'Todos os tenants',
                  dropdownMenuEntries: dropdownEntries,
                  onSelected: (value) {
                    setState(() {
                      final normalized = (value ?? '').trim();
                      _selectedTenantId = normalized.isEmpty
                          ? null
                          : normalized;
                      _usersPageIndex = 0;
                    });
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsersTable(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid,
    Map<String, String> tenantNamesById, {
    required bool showBillingColumns,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    final totalRows = users.length;
    final maxPageIndex = totalRows == 0
        ? 0
        : (totalRows - 1) ~/ _usersRowsPerPage;

    if (_usersPageIndex > maxPageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _usersPageIndex = maxPageIndex;
        });
      });
    }

    final effectivePageIndex = _usersPageIndex > maxPageIndex
        ? maxPageIndex
        : _usersPageIndex;
    final firstRowIndex = effectivePageIndex * _usersRowsPerPage;
    final pageUsers = users
        .skip(firstRowIndex)
        .take(_usersRowsPerPage)
        .toList(growable: false);
    final pageStart = totalRows == 0 ? 0 : firstRowIndex + 1;
    final pageEnd = firstRowIndex + pageUsers.length;
    final canGoPrevious = effectivePageIndex > 0;
    final canGoNext = pageEnd < totalRows;
    final columns = <DataColumn>[
      DataColumn(
        label: const Text('Usuario'),
        onSort: (columnIndex, ascending) =>
            _setUserSort(columnIndex, ascending, _MaintainerUserSortField.user),
      ),
      DataColumn(
        label: const Text('UID'),
        onSort: (columnIndex, ascending) =>
            _setUserSort(columnIndex, ascending, _MaintainerUserSortField.uid),
      ),
      DataColumn(
        label: const Text('Tenants'),
        onSort: (columnIndex, ascending) => _setUserSort(
          columnIndex,
          ascending,
          _MaintainerUserSortField.tenants,
        ),
      ),
      DataColumn(
        label: const Text('Conta'),
        onSort: (columnIndex, ascending) => _setUserSort(
          columnIndex,
          ascending,
          _MaintainerUserSortField.account,
        ),
      ),
      if (showBillingColumns)
        DataColumn(
          label: const Text('Billing'),
          onSort: (columnIndex, ascending) => _setUserSort(
            columnIndex,
            ascending,
            _MaintainerUserSortField.billing,
          ),
        ),
      if (showBillingColumns)
        DataColumn(
          label: const Text('Graca ate'),
          onSort: (columnIndex, ascending) => _setUserSort(
            columnIndex,
            ascending,
            _MaintainerUserSortField.graceUntil,
          ),
        ),
      DataColumn(
        label: const Text('Atualizado'),
        onSort: (columnIndex, ascending) => _setUserSort(
          columnIndex,
          ascending,
          _MaintainerUserSortField.updatedAt,
        ),
      ),
      const DataColumn(label: Text('Acoes')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Linhas por pagina:'),
            DropdownButton<int>(
              value: _usersRowsPerPage,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 20, child: Text('20')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _usersRowsPerPage = value;
                  _usersPageIndex = 0;
                });
              },
            ),
            Text('$pageStart-$pageEnd de $totalRows'),
            IconButton.outlined(
              tooltip: 'Pagina anterior',
              onPressed: canGoPrevious
                  ? () {
                      setState(() {
                        _usersPageIndex = math.max(0, effectivePageIndex - 1);
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton.outlined(
              tooltip: 'Proxima pagina',
              onPressed: canGoNext
                  ? () {
                      setState(() {
                        _usersPageIndex = effectivePageIndex + 1;
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1160),
            child: DataTable(
              sortColumnIndex: _sortColumnIndexForScope(showBillingColumns),
              sortAscending: _userSortAscending,
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 58,
              columnSpacing: 14,
              horizontalMargin: 10,
              columns: columns,
              rows: pageUsers
                  .map(
                    (user) => _buildUserDataRow(
                      user,
                      tenantIdsByUid[user.uid],
                      tenantNamesById,
                      showBillingColumns: showBillingColumns,
                      canManageUserStatus: canManageUserStatus,
                      canManageUserBilling: canManageUserBilling,
                      canManageUserCrud: canManageUserCrud,
                      canManageUserPermissions: canManageUserPermissions,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }

  int? _sortColumnIndexForScope(bool showBillingColumns) {
    switch (_userSortField) {
      case _MaintainerUserSortField.user:
        return 0;
      case _MaintainerUserSortField.uid:
        return 1;
      case _MaintainerUserSortField.tenants:
        return 2;
      case _MaintainerUserSortField.account:
        return 3;
      case _MaintainerUserSortField.billing:
        return showBillingColumns ? 4 : null;
      case _MaintainerUserSortField.graceUntil:
        return showBillingColumns ? 5 : null;
      case _MaintainerUserSortField.updatedAt:
        return showBillingColumns ? 6 : 4;
    }
  }

  void _setUserSort(
    int columnIndex,
    bool ascending,
    _MaintainerUserSortField field,
  ) {
    setState(() {
      _userSortAscending = ascending;
      _userSortField = field;
      _usersPageIndex = 0;
    });
  }

  List<MaintainerUserAccount> _sortUsers(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid,
    Map<String, String> tenantNamesById,
  ) {
    final sorted = List<MaintainerUserAccount>.from(users);

    int compareAccounts(MaintainerUserAccount a, MaintainerUserAccount b) {
      switch (_userSortField) {
        case _MaintainerUserSortField.user:
          final emailOrder = a.email.toLowerCase().compareTo(
            b.email.toLowerCase(),
          );
          if (emailOrder != 0) {
            return emailOrder;
          }
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        case _MaintainerUserSortField.uid:
          return a.uid.compareTo(b.uid);
        case _MaintainerUserSortField.tenants:
          final aTenant = _tenantSortKey(
            tenantIdsByUid[a.uid] ?? const <String>{},
            tenantNamesById,
          );
          final bTenant = _tenantSortKey(
            tenantIdsByUid[b.uid] ?? const <String>{},
            tenantNamesById,
          );
          final tenantOrder = aTenant.compareTo(bTenant);
          if (tenantOrder != 0) {
            return tenantOrder;
          }
          return a.uid.compareTo(b.uid);
        case _MaintainerUserSortField.account:
          final aValue = a.activeGlobal ? 1 : 0;
          final bValue = b.activeGlobal ? 1 : 0;
          return aValue.compareTo(bValue);
        case _MaintainerUserSortField.billing:
          return a.billingAccountState.toLowerCase().compareTo(
            b.billingAccountState.toLowerCase(),
          );
        case _MaintainerUserSortField.graceUntil:
          final aGrace = a.billingGraceUntilAt?.millisecondsSinceEpoch ?? -1;
          final bGrace = b.billingGraceUntilAt?.millisecondsSinceEpoch ?? -1;
          return aGrace.compareTo(bGrace);
        case _MaintainerUserSortField.updatedAt:
          final aUpdated = a.updatedAt?.millisecondsSinceEpoch ?? -1;
          final bUpdated = b.updatedAt?.millisecondsSinceEpoch ?? -1;
          return aUpdated.compareTo(bUpdated);
      }
    }

    sorted.sort((a, b) {
      final order = compareAccounts(a, b);
      if (order == 0) {
        return a.uid.compareTo(b.uid);
      }
      return _userSortAscending ? order : -order;
    });

    return sorted;
  }

  String _tenantSortKey(
    Set<String> tenantIds,
    Map<String, String> tenantNamesById,
  ) {
    if (tenantIds.isEmpty) {
      return '';
    }
    final sorted = tenantIds.toList(growable: false)..sort();
    return sorted
        .map((tenantId) => _tenantFilterLabel(tenantId, tenantNamesById))
        .join('|');
  }

  DataRow _buildUserDataRow(
    MaintainerUserAccount user,
    Set<String>? tenantIds,
    Map<String, String> tenantNamesById, {
    required bool showBillingColumns,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
  }) {
    final processing = _processingUserIds.contains(user.uid);
    final emailLabel = user.email.isEmpty ? '(sem e-mail)' : user.email;
    final nameLabel = user.displayName.isEmpty
        ? '(sem nome)'
        : user.displayName;
    final tenantLabel = _formatTenantSummary(
      tenantIds ?? const <String>{},
      tenantNamesById,
    );
    final accountLabel = user.activeGlobal ? 'Ativa' : 'Inativa';
    final billingLabel = user.billingAccountState.isEmpty
        ? 'active'
        : user.billingAccountState;
    final hasActionPermission =
        canManageUserStatus ||
        canManageUserBilling ||
        canManageUserCrud ||
        canManageUserPermissions;
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isSelfAccount =
        currentUid.isNotEmpty && currentUid == user.uid.trim();
    final actionItems = <PopupMenuEntry<_MaintainerUserAction>>[
      if (canManageUserCrud)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.editProfile,
          child: Text('Editar cadastro'),
        ),
      if (canManageUserPermissions)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.editPermissionMatrix,
          child: Text('Editar matriz de permissoes'),
        ),
      if (canManageUserCrud && !isSelfAccount)
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.deleteUser,
          child: Text('Excluir usuario'),
        ),
      if (canManageUserCrud && isSelfAccount)
        const PopupMenuItem<_MaintainerUserAction>(
          enabled: false,
          child: Text('Excluir usuario (bloqueado para a propria conta)'),
        ),
      if ((canManageUserCrud || canManageUserPermissions) &&
          (canManageUserStatus || canManageUserBilling))
        const PopupMenuDivider(),
      if (canManageUserStatus)
        PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.toggleAccount,
          child: Text(user.activeGlobal ? 'Desativar conta' : 'Ativar conta'),
        ),
      if (canManageUserBilling) ...[
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.grant7days,
          child: Text('Liberar +7 dias'),
        ),
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.grant30days,
          child: Text('Liberar +30 dias'),
        ),
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.normalizeBilling,
          child: Text('Normalizar billing'),
        ),
        const PopupMenuItem<_MaintainerUserAction>(
          value: _MaintainerUserAction.suspendBilling,
          child: Text('Suspender billing'),
        ),
      ],
    ];

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: emailLabel,
                waitDuration: const Duration(milliseconds: 350),
                child: Text(emailLabel, overflow: TextOverflow.ellipsis),
              ),
              Tooltip(
                message: nameLabel,
                waitDuration: const Duration(milliseconds: 350),
                child: Text(
                  nameLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF576074),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Tooltip(
              message: user.uid,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(user.uid, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 220,
            child: Tooltip(
              message: tenantLabel,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(tenantLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        DataCell(Text(accountLabel)),
        if (showBillingColumns) DataCell(Text(billingLabel)),
        if (showBillingColumns)
          DataCell(Text(_formatDateTime(user.billingGraceUntilAt))),
        DataCell(Text(_formatDateTime(user.updatedAt))),
        DataCell(
          !hasActionPermission
              ? const Text('Somente leitura')
              : processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<_MaintainerUserAction>(
                  tooltip: 'Acoes do usuario',
                  onSelected: (action) => _onUserActionSelected(
                    user,
                    action,
                    canManageUserCrud: canManageUserCrud,
                    canManageUserPermissions: canManageUserPermissions,
                    canManageUserStatus: canManageUserStatus,
                    canManageUserBilling: canManageUserBilling,
                  ),
                  itemBuilder: (_) => actionItems,
                  child: const Icon(Icons.more_horiz),
                ),
        ),
      ],
    );
  }

  Future<void> _onUserActionSelected(
    MaintainerUserAccount user,
    _MaintainerUserAction action, {
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
  }) async {
    final actorUid = _currentActorUid();
    final actorEmail = _currentActorEmail();
    final actorLabel = _currentActorLabel();

    switch (action) {
      case _MaintainerUserAction.editProfile:
        if (!canManageUserCrud) {
          return;
        }
        await _openEditUserDialog(context, existing: user);
      case _MaintainerUserAction.editPermissionMatrix:
        if (!canManageUserPermissions) {
          return;
        }
        await _openPermissionMatrixDialog(context, user);
      case _MaintainerUserAction.deleteUser:
        if (!canManageUserCrud) {
          return;
        }
        await _confirmDeleteUser(context, user);
      case _MaintainerUserAction.toggleAccount:
        if (!canManageUserStatus) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: user.activeGlobal
              ? 'Conta desativada.'
              : 'Conta ativada.',
          action: () => _userAdminService.setGlobalActive(
            uid: user.uid,
            active: !user.activeGlobal,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.grant7days:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta liberada por 7 dias.',
          action: () => _userAdminService.grantGracePeriod(
            uid: user.uid,
            duration: const Duration(days: 7),
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.grant30days:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta liberada por 30 dias.',
          action: () => _userAdminService.grantGracePeriod(
            uid: user.uid,
            duration: const Duration(days: 30),
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.normalizeBilling:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Billing normalizado para ativo.',
          action: () => _userAdminService.normalizeBilling(
            uid: user.uid,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.suspendBilling:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta marcada como suspensa.',
          action: () => _userAdminService.suspendBilling(
            uid: user.uid,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
    }
  }

  Future<void> _openEditUserDialog(
    BuildContext context, {
    MaintainerUserAccount? existing,
  }) async {
    final uidController = TextEditingController(text: existing?.uid ?? '');
    final emailController = TextEditingController(text: existing?.email ?? '');
    final displayNameController = TextEditingController(
      text: existing?.displayName ?? '',
    );
    var platformRole = (existing?.platformRole ?? 'none').trim().toLowerCase();
    if (platformRole != 'platform_admin') {
      platformRole = 'none';
    }
    var maintainerRole = (existing?.maintainerRole ?? 'none')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    if (!_maintainerRoleOptions.contains(maintainerRole)) {
      maintainerRole = 'none';
    }
    var activeGlobal = existing?.activeGlobal ?? true;
    var consoleEnabled = existing?.maintainerConsoleEnabled ?? true;
    var mfaRequired = existing?.maintainerMfaRequired ?? false;
    final grantedPermissions = Set<String>.from(
      existing?.maintainerPermissions ?? const <String>{},
    );
    final deniedPermissions = Set<String>.from(
      existing?.maintainerDeniedPermissions ?? const <String>{},
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Novo usuario' : 'Editar cadastro',
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: uidController,
                        enabled: existing == null,
                        decoration: const InputDecoration(
                          labelText: 'UID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome exibicao',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: platformRole,
                        decoration: const InputDecoration(
                          labelText: 'Platform role (regras Firestore)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('none')),
                          DropdownMenuItem(
                            value: 'platform_admin',
                            child: Text('platform_admin'),
                          ),
                        ],
                        onChanged: (value) {
                          setLocalState(() {
                            platformRole = (value ?? 'none').trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: maintainerRole,
                        decoration: const InputDecoration(
                          labelText: 'Role mantenedor (base de permissoes)',
                          border: OutlineInputBorder(),
                        ),
                        items: _maintainerRoleOptions
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setLocalState(() {
                            maintainerRole = (value ?? 'none')
                                .trim()
                                .toLowerCase();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: activeGlobal,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Conta global ativa (ativoGlobal)'),
                        onChanged: (value) {
                          setLocalState(() {
                            activeGlobal = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: consoleEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Console de mantenedor habilitado'),
                        onChanged: (value) {
                          setLocalState(() {
                            consoleEnabled = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: mfaRequired,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Exigir MFA no mantenedor'),
                        onChanged: (value) {
                          setLocalState(() {
                            mfaRequired = value;
                          });
                        },
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final uid = uidController.text.trim();
                          if (uid.isEmpty) {
                            setLocalState(() {
                              errorText = 'UID e obrigatorio.';
                            });
                            return;
                          }

                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          try {
                            await _userAdminService.saveUserProfile(
                              uid: uid,
                              email: emailController.text.trim(),
                              displayName: displayNameController.text.trim(),
                              platformRole: platformRole,
                              maintainerRole: maintainerRole,
                              activeGlobal: activeGlobal,
                              maintainerConsoleEnabled: consoleEnabled,
                              maintainerMfaRequired: mfaRequired,
                              maintainerPermissions: grantedPermissions,
                              maintainerDeniedPermissions: deniedPermissions,
                              isCreate: existing == null,
                              actorUid: _currentActorUid(),
                              actorEmail: _currentActorEmail(),
                              actorLabel: _currentActorLabel(),
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop(true);
                          } catch (error) {
                            setLocalState(() {
                              errorText = 'Falha ao salvar usuario: $error';
                              isSaving = false;
                            });
                          }
                        },
                  child: Text(existing == null ? 'Criar usuario' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    uidController.dispose();
    emailController.dispose();
    displayNameController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Usuario criado/atualizado com sucesso.'
                : 'Cadastro atualizado com sucesso.',
          ),
        ),
      );
    }
  }

  Future<void> _openPermissionMatrixDialog(
    BuildContext context,
    MaintainerUserAccount user,
  ) async {
    final permissions = MaintainerPermission.all.toList(growable: false)
      ..sort();
    final granted = Set<String>.from(user.maintainerPermissions)
      ..retainAll(MaintainerPermission.all);
    final denied = Set<String>.from(user.maintainerDeniedPermissions)
      ..retainAll(MaintainerPermission.all);
    var maintainerRole = user.maintainerRole.trim().toLowerCase().replaceAll(
      ' ',
      '_',
    );
    if (!_maintainerRoleOptions.contains(maintainerRole)) {
      maintainerRole = 'none';
    }
    var consoleEnabled = user.maintainerConsoleEnabled;
    var mfaRequired = user.maintainerMfaRequired;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                'Matriz de permissoes: ${user.displayName.isEmpty ? user.uid : user.displayName}',
              ),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UID: ${user.uid}'),
                      const SizedBox(height: 6),
                      Text('E-mail: ${user.email.isEmpty ? '--' : user.email}'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: maintainerRole,
                        decoration: const InputDecoration(
                          labelText: 'Role mantenedor (base)',
                          border: OutlineInputBorder(),
                        ),
                        items: _maintainerRoleOptions
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setLocalState(() {
                            maintainerRole = (value ?? 'none')
                                .trim()
                                .toLowerCase();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: consoleEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Console habilitado'),
                        onChanged: (value) {
                          setLocalState(() {
                            consoleEnabled = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: mfaRequired,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('MFA obrigatorio'),
                        onChanged: (value) {
                          setLocalState(() {
                            mfaRequired = value;
                          });
                        },
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Matriz de permissoes (Grant / Deny):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      for (final permission in permissions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(_permissionLabel(permission)),
                              ),
                              SizedBox(
                                width: 92,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: granted.contains(permission),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          if (value == true) {
                                            granted.add(permission);
                                            denied.remove(permission);
                                          } else {
                                            granted.remove(permission);
                                          }
                                        });
                                      },
                                    ),
                                    const Text('Grant'),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 92,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: denied.contains(permission),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          if (value == true) {
                                            denied.add(permission);
                                            granted.remove(permission);
                                          } else {
                                            denied.remove(permission);
                                          }
                                        });
                                      },
                                    ),
                                    const Text('Deny'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          try {
                            await _userAdminService.saveUserProfile(
                              uid: user.uid,
                              email: user.email,
                              displayName: user.displayName,
                              platformRole: user.platformRole,
                              maintainerRole: maintainerRole,
                              activeGlobal: user.activeGlobal,
                              maintainerConsoleEnabled: consoleEnabled,
                              maintainerMfaRequired: mfaRequired,
                              maintainerPermissions: granted,
                              maintainerDeniedPermissions: denied,
                              actorUid: _currentActorUid(),
                              actorEmail: _currentActorEmail(),
                              actorLabel: _currentActorLabel(),
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop(true);
                          } catch (error) {
                            setLocalState(() {
                              errorText =
                                  'Falha ao salvar matriz de permissoes: $error';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Salvar matriz'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Matriz de permissoes atualizada.')),
      );
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    MaintainerUserAccount user,
  ) async {
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (currentUid.isNotEmpty && currentUid == user.uid.trim()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Por seguranca, nao e permitido excluir a propria conta administrativa.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir usuario'),
          content: Text(
            'Deseja excluir o cadastro de ${user.displayName.isEmpty ? user.uid : user.displayName} (${user.uid})? Esta acao remove o documento em usuarios/{uid}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _runUserAction(
      user.uid,
      successMessage: 'Usuario excluido com sucesso.',
      action: () => _userAdminService.deleteUser(
        user.uid,
        actorUid: _currentActorUid(),
        actorEmail: _currentActorEmail(),
        actorLabel: _currentActorLabel(),
      ),
    );
  }

  List<MaintainerUserAccount> _filterUsersByScope(
    List<MaintainerUserAccount> users,
    _MaintainerUserScope scope,
  ) {
    final filtered = users
        .where((user) {
          final isMaintainer = _isMaintainerAccount(user);
          if (scope == _MaintainerUserScope.platformUsers) {
            return isMaintainer;
          }
          return !isMaintainer;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final emailOrder = a.email.toLowerCase().compareTo(b.email.toLowerCase());
      if (emailOrder != 0) {
        return emailOrder;
      }
      return a.uid.compareTo(b.uid);
    });

    return filtered;
  }

  bool _isMaintainerAccount(MaintainerUserAccount user) {
    final normalizedMaintainerRole = user.maintainerRole
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    final normalizedPlatformRole = user.platformRole.trim().toLowerCase();
    return normalizedPlatformRole == 'platform_admin' ||
        (normalizedMaintainerRole.isNotEmpty &&
            normalizedMaintainerRole != 'none') ||
        user.maintainerPermissions.isNotEmpty ||
        user.maintainerDeniedPermissions.isNotEmpty;
  }

  String _permissionLabel(String permission) {
    switch (permission) {
      case MaintainerPermission.viewHome:
        return 'Visualizar painel inicial';
      case MaintainerPermission.viewOverview:
        return 'Visualizar visao geral';
      case MaintainerPermission.viewUsers:
        return 'Visualizar gestao de usuarios';
      case MaintainerPermission.manageUserStatus:
        return 'Ativar/Desativar contas';
      case MaintainerPermission.manageUserBilling:
        return 'Ajustar billing';
      case MaintainerPermission.manageUserCrud:
        return 'CRUD de usuarios';
      case MaintainerPermission.manageUserPermissions:
        return 'Editar matriz de permissoes';
      case MaintainerPermission.manageImpersonation:
        return 'Executar acesso assistido (impersonation)';
      default:
        return permission;
    }
  }

  static const List<String> _maintainerRoleOptions = [
    'none',
    'platform_observer',
    'platform_operator',
    'platform_admin',
  ];

  List<MaintainerUserAccount> _filterUsers(
    List<MaintainerUserAccount> users,
    Map<String, Set<String>> tenantIdsByUid, {
    required String? selectedTenantId,
  }) {
    final query = _userSearchController.text.trim().toLowerCase();
    return users
        .where((user) {
          final userTenantIds = tenantIdsByUid[user.uid] ?? const <String>{};
          if (selectedTenantId != null &&
              !userTenantIds.contains(selectedTenantId)) {
            return false;
          }

          final email = user.email.toLowerCase();
          final name = user.displayName.toLowerCase();
          final uid = user.uid.toLowerCase();
          if (query.isEmpty) {
            return true;
          }
          return email.contains(query) ||
              name.contains(query) ||
              uid.contains(query);
        })
        .toList(growable: false);
  }

  String _formatTenantSummary(
    Set<String> tenantIds,
    Map<String, String> tenantNamesById,
  ) {
    if (tenantIds.isEmpty) {
      return '--';
    }

    final sorted = tenantIds.toList(growable: false)..sort();
    final labels = sorted
        .map((tenantId) => _tenantFilterLabel(tenantId, tenantNamesById))
        .toList(growable: false);
    if (labels.length <= 2) {
      return labels.join(', ');
    }
    final remaining = labels.length - 2;
    return '${labels[0]}, ${labels[1]} +$remaining';
  }

  String _tenantFilterLabel(
    String tenantId,
    Map<String, String> tenantNamesById,
  ) {
    final normalizedId = tenantId.trim();
    final name = (tenantNamesById[normalizedId] ?? normalizedId).trim();
    return '$name ($normalizedId)';
  }

  String _formatPermissions(Set<String> permissions) {
    if (permissions.isEmpty) {
      return 'nenhuma';
    }

    final labels = permissions.map(_permissionLabel).toList(growable: false)
      ..sort();

    return labels.join(' | ');
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _currentActorUid() {
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  String _currentActorEmail() {
    return (FirebaseAuth.instance.currentUser?.email ?? '').trim();
  }

  String _currentActorLabel() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty) {
      return email;
    }

    return _currentActorUid();
  }

  Future<void> _runUserAction(
    String uid, {
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    setState(() {
      _processingUserIds.add(uid);
    });

    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar usuario: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingUserIds.remove(uid);
        });
      }
    }
  }
}
