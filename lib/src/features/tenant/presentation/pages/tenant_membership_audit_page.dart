import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../../shared/presentation/widgets/app_pagination_bar.dart';
import '../../../../shared/presentation/widgets/pagination_slice.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../domain/tenant_membership_audit_filter.dart';

class TenantMembershipAuditPage extends StatefulWidget {
  const TenantMembershipAuditPage({super.key, required this.identity});

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

  InputDecoration _fieldDecoration({
    required BuildContext context,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoria de memberships')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Histórico de alterações críticas no tenant ${widget.identity.tenantName}.',
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
                          decoration: _fieldDecoration(
                            context: context,
                            label: 'Buscar por ação, ator ou membershipId',
                            icon: Icons.search,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedAction,
                          isExpanded: true,
                          decoration: _fieldDecoration(
                            context: context,
                            label: 'Ação',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'todos',
                              child: Text('Todos'),
                            ),
                            ...const [
                              'membership_revoked',
                              'membership_reactivated',
                              'membership_deactivated',
                              'membership_role_changed',
                              'tenant_policy_updated',
                            ].map(
                              (action) => DropdownMenuItem(
                                value: action,
                                child: Text(
                                  TenantMembershipAuditFilter.actionLabel(
                                    action,
                                  ),
                                ),
                              ),
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
                  stream: _membershipService.watchAuditForTenant(
                    widget.identity.tenantId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return AppInfoCard(
                        title: 'Falha ao carregar auditoria',
                        subtitle: '${snapshot.error}',
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppInfoCard(
                        title: 'Carregando auditoria',
                        subtitle: 'Buscando eventos de governança...',
                      );
                    }

                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return const AppInfoCard(
                        title: 'Sem eventos de auditoria',
                        subtitle: 'Eventos aparecem quando houver inativação, revogação, reativação ou alteração de papel.',
                      );
                    }

                    final filteredEntries = TenantMembershipAuditFilter.apply(
                      entries: entries,
                      query: _searchController.text,
                      selectedAction: _selectedAction,
                    );
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
    final action = (entry['action'] ?? '-').toString();
    final actionLabel = TenantMembershipAuditFilter.actionLabel(action);
    final actorUid = (entry['actorUid'] ?? '-').toString();
    final actorLabel = (entry['actorLabel'] ?? '').toString().trim();
    final actorText = actorLabel.isEmpty || actorLabel == actorUid
        ? actorUid
        : '$actorLabel ($actorUid)';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              actionLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Ator: $actorText'),
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
