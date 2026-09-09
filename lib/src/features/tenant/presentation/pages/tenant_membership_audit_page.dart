import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../../shared/presentation/widgets/app_pagination_bar.dart';
import '../../../../shared/presentation/widgets/pagination_slice.dart';
import '../../../auth/services/tenant_membership_service.dart';

class TenantMembershipAuditPage extends StatefulWidget {
  const TenantMembershipAuditPage({
    super.key,
    required this.identity,
  });

  final AppIdentity identity;

  @override
  State<TenantMembershipAuditPage> createState() =>
      _TenantMembershipAuditPageState();
}

class _TenantMembershipAuditPageState extends State<TenantMembershipAuditPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedAction = 'todos';
  int _currentPage = 0;
  int _pageSize = 10;

  TenantMembershipService get _membershipService =>
      TenantMembershipService(FirebaseFirestore.instance);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> entries) {
    final query = _searchController.text.trim().toLowerCase();

    return entries.where((entry) {
      final action = (entry['action'] ?? '').toString().toLowerCase();
      final actorUid = (entry['actorUid'] ?? '').toString().toLowerCase();
      final membershipId = (entry['membershipId'] ?? '').toString().toLowerCase();
      final matchesAction = _selectedAction == 'todos' || action == _selectedAction;
      if (!matchesAction) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return action.contains(query) ||
          actorUid.contains(query) ||
          membershipId.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoria de memberships'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historico de alteracoes criticas no tenant ${widget.identity.tenantName}.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (_) {
                            setState(() {
                              _currentPage = 0;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Buscar por acao, ator ou membershipId',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedAction,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Acao',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(
                              value: 'membership_revoked',
                              child: Text('membership_revoked'),
                            ),
                            DropdownMenuItem(
                              value: 'membership_reactivated',
                              child: Text('membership_reactivated'),
                            ),
                            DropdownMenuItem(
                              value: 'membership_role_changed',
                              child: Text('membership_role_changed'),
                            ),
                            DropdownMenuItem(
                              value: 'tenant_policy_updated',
                              child: Text('tenant_policy_updated'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedAction = value;
                                _currentPage = 0;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _membershipService
                      .watchAuditForTenant(widget.identity.tenantId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppInfoCard(
                        title: 'Carregando auditoria',
                        subtitle: 'Buscando eventos de governanca...',
                      );
                    }

                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return const AppInfoCard(
                        title: 'Sem eventos de auditoria',
                        subtitle:
                            'Eventos aparecem quando houver revogacao, reativacao ou alteracao de papel.',
                      );
                    }

                    final filteredEntries = _applyFilters(entries);
                    if (filteredEntries.isEmpty) {
                      return const AppInfoCard(
                        title: 'Sem resultados',
                        subtitle: 'Ajuste os filtros para localizar eventos.',
                      );
                    }

                    final page = buildPaginationSlice(
                      source: filteredEntries,
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
                        ...page.items.map((entry) => _AuditCard(entry: entry)),
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
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final details = entry['details'];
    final detailsText = details is Map ? details.toString() : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (entry['action'] ?? '-').toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Ator: ${(entry['actorUid'] ?? '-').toString()}'),
            const SizedBox(height: 6),
            Text('Membership: ${(entry['membershipId'] ?? '-').toString()}'),
            const SizedBox(height: 6),
            Text('Quando: ${(entry['createdAt'] ?? '-').toString()}'),
            const SizedBox(height: 6),
            Text('Detalhes: $detailsText'),
          ],
        ),
      ),
    );
  }
}

