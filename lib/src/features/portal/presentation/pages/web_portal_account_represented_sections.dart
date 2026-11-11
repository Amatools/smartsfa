part of 'web_portal_page.dart';

class _PortalLandingSection extends StatefulWidget {
  const _PortalLandingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  State<_PortalLandingSection> createState() => _PortalLandingSectionState();
}

class _PortalLandingSectionState extends State<_PortalLandingSection> {
  final AppShellDashboardSalesService _salesService =
      const AppShellDashboardSalesService();
  late final FirestorePedidoRepository _pedidoRepository;
  late Stream<List<Pedido>> _pedidosStream;

  @override
  void initState() {
    super.initState();
    _pedidoRepository = FirestorePedidoRepository(FirebaseFirestore.instance);
    _pedidosStream = _buildPedidosStream();
  }

  @override
  void didUpdateWidget(covariant _PortalLandingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTenant.tenantId.trim() !=
        widget.activeTenant.tenantId.trim()) {
      _pedidosStream = _buildPedidosStream();
    }
  }

  Stream<List<Pedido>> _buildPedidosStream() {
    return _pedidoRepository.watchAll(tenantId: widget.activeTenant.tenantId);
  }

  Widget _buildSalesChartCard(
    BuildContext context,
    AppShellDashboardSalesSummary summary,
  ) {
    final data = summary.dailySales;
    final maxValue = data.fold<double>(0, (current, point) {
      if (point.total > current) {
        return point.total;
      }
      return current;
    });
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    final spots = <FlSpot>[];
    for (var index = 0; index < data.length; index++) {
      spots.add(FlSpot(index.toDouble(), data[index].total));
    }

    final lineColor = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grafico diario de vendas (30 dias)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              summary.hasSalesData
                  ? 'Vendas enviadas dentro do seu escopo de acesso.'
                  : 'Sem vendas enviadas no periodo para exibir no grafico.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: data.isEmpty ? 1 : (data.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor),
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                      right: BorderSide.none,
                      top: BorderSide.none,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 72,
                        getTitlesWidget: (value, _) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              WebPortalDashboardFormatService.formatCompactCurrencyBr(
                                value,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 5,
                        getTitlesWidget: (value, _) {
                          final index = value.round();
                          if (index < 0 || index >= data.length) {
                            return const SizedBox.shrink();
                          }

                          final isEdge = index == 0 || index == data.length - 1;
                          final isInterval = index % 5 == 0;
                          if (!isEdge && !isInterval) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              WebPortalDashboardFormatService.formatDayDdMm(
                                data[index].day,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: lineColor,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            lineColor.withValues(alpha: 0.26),
                            lineColor.withValues(alpha: 0.04),
                          ],
                        ),
                      ),
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

  Widget _buildSalesKpiCard(
    BuildContext context,
    AppShellDashboardSalesSummary summary,
  ) {
    final trendPositive = summary.last7DaysTotal >= summary.previous7DaysTotal;
    final trendColor = trendPositive ? Colors.green : Colors.red;
    final trendIcon = trendPositive ? Icons.trending_up : Icons.trending_down;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendido no mes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              WebPortalDashboardFormatService.formatCurrencyBr(
                summary.monthTotal,
              ),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 12),
            _PortalSalesInfoRow(
              label: 'Pedidos enviados',
              value: summary.monthOrders.toString(),
            ),
            const SizedBox(height: 8),
            _PortalSalesInfoRow(
              label: 'Ticket medio',
              value: WebPortalDashboardFormatService.formatCurrencyBr(
                summary.monthAverageTicket,
              ),
            ),
            const SizedBox(height: 8),
            _PortalSalesInfoRow(
              label: 'Ultimos 7 dias',
              value: WebPortalDashboardFormatService.formatCurrencyBr(
                summary.last7DaysTotal,
              ),
            ),
            const SizedBox(height: 8),
            _PortalSalesInfoRow(
              label: '7 dias anteriores',
              value: WebPortalDashboardFormatService.formatCurrencyBr(
                summary.previous7DaysTotal,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(trendIcon, color: trendColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  WebPortalDashboardFormatService.formatDeltaPercent(
                    current: summary.last7DaysTotal,
                    baseline: summary.previous7DaysTotal,
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: trendColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCustomersCard(
    BuildContext context,
    AppShellDashboardSalesSummary summary,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top clientes no mes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (summary.topCustomers.isEmpty)
              Text(
                'Sem clientes com pedidos enviados no mes.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...summary.topCustomers.asMap().entries.map((entry) {
                final row = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PortalSalesInfoRow(
                    label:
                        '${entry.key + 1}. ${row.label} (${row.orders} pedido(s))',
                    value: WebPortalDashboardFormatService.formatCurrencyBr(
                      row.total,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCommercialSummary(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1280;

    return StreamBuilder<List<Pedido>>(
      stream: _pedidosStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nao foi possivel carregar o resumo comercial: ${snapshot.error}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.red),
              ),
            ),
          );
        }

        final summary = _salesService.build(pedidos: snapshot.data ?? const []);
        final chartCard = _buildSalesChartCard(context, summary);
        final sideCards = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSalesKpiCard(context, summary),
            const SizedBox(height: 12),
            _buildTopCustomersCard(context, summary),
          ],
        );

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [chartCard, const SizedBox(height: 12), sideCards],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: chartCard),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: sideCards),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1100;

    final modules = [
      _PortalModule(
        title: 'Tabelas de preço',
        subtitle: 'Regras por marca, segmento, cliente, produto e tags.',
        icon: Icons.price_change_outlined,
      ),
      _PortalModule(
        title: 'Políticas comerciais',
        subtitle: 'Limites, excecoes, descontos, acrescimos e travas.',
        icon: Icons.policy_outlined,
      ),
      _PortalModule(
        title: 'Configurações',
        subtitle: 'Parâmetros, categorias, unidades, mídia e períodos.',
        icon: Icons.settings_outlined,
      ),
      _PortalModule(
        title: 'ERP e integrações',
        subtitle: 'Parâmetros de conector, mapeamento e status.',
        icon: Icons.integration_instructions_outlined,
      ),
      _PortalModule(
        title: 'Convites e memberships',
        subtitle: 'Onboarding, aprovações e auditoria de acesso.',
        icon: Icons.badge_outlined,
      ),
      _PortalModule(
        title: 'Auditoria',
        subtitle: 'Eventos críticos, trilha de mudanças e suporte.',
        icon: Icons.fact_check_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visão geral da conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A conta SaaS controla a visão global; cada tenant navega isoladamente em seu próprio contexto.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SummaryCard(
              title: 'Workspace em uso',
              value: widget.activeTenant.tenantName,
            ),
            _SummaryCard(
              title: 'Seu acesso atual',
              value: _roleLabel(
                widget.activeTenant.role,
                widget.activeTenant.workspaceType,
                widget.activeTenant.tenantName,
              ),
            ),
            _SummaryCard(
              title: 'Workspace atual',
              value: _workspaceTypeLabel(widget.activeTenant.workspaceType),
            ),
            const _SummaryCard(title: 'Canal de acesso', value: 'Portal web'),
          ],
        ),
        const SizedBox(height: 24),
        _buildCommercialSummary(context),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: isWide ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isWide ? 1.8 : 2.6,
          children: modules
              .map((module) => _PortalModuleCard(module: module))
              .toList(),
        ),
      ],
    );
  }
}

class _PortalSalesInfoRow extends StatelessWidget {
  const _PortalSalesInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _BillingSection extends StatelessWidget {
  const _BillingSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Billing',
      subtitle: 'Conta SaaS e faturamento do tenant ativo.',
      items: [
        'Plano atual do tenant: ${activeTenant.tenantName}',
        'Histórico de upgrade e downgrade',
        'Limites por plano e uso',
        'Cobrança por tenant, não por login',
      ],
    );
  }
}

const int _userLogoMaxWidthPx = 240;
const int _userLogoMaxHeightPx = 96;

WorkspaceProfileService _workspaceProfileService() {
  return WorkspaceProfileService(FirebaseFirestore.instance);
}

Future<void> _runWorkspaceProfileMutation(
  BuildContext context, {
  required Future<void> Function(WorkspaceProfileService service) action,
  required String successMessage,
  required String failurePrefix,
}) async {
  try {
    await action(_workspaceProfileService());
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$failurePrefix: $error')));
  }
}

Future<void> _upsertRepresentedCompanyFromEditor(
  BuildContext context, {
  required String tenantId,
  required List<_RepresentedCompany> allCompanies,
  _RepresentedCompany? initialCompany,
  required String successMessage,
  required String failurePrefix,
}) async {
  final payload = await _openRepresentedCompanyEditor(
    context,
    initial: initialCompany,
    allCompanies: allCompanies,
  );
  if (payload == null || !context.mounted) {
    return;
  }

  await _runWorkspaceProfileMutation(
    context,
    action: (service) {
      return service.upsertRepresentedCompany(
        tenantId: tenantId,
        companyId: initialCompany?.id,
        values: payload,
      );
    },
    successMessage: successMessage,
    failurePrefix: failurePrefix,
  );
}

Future<void> _editRepresentedCompanyForTenant(
  BuildContext context, {
  required String tenantId,
  required _RepresentedCompany company,
  required List<_RepresentedCompany> allCompanies,
}) async {
  await _upsertRepresentedCompanyFromEditor(
    context,
    tenantId: tenantId,
    allCompanies: allCompanies,
    initialCompany: company,
    successMessage: 'Representada atualizada com sucesso.',
    failurePrefix: 'Falha ao atualizar representada',
  );
}

Future<bool> _confirmDeleteRepresentedCompany(
  BuildContext context,
  _RepresentedCompany company,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir representada'),
      content: Text(
        'Deseja excluir ${_representedCompanyDisplayName(company)}?',
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
    ),
  );

  return confirmed == true && context.mounted;
}

String _readUserLogoDataUrl(Map<String, dynamic> data) {
  final logoDataUrl = (data['logoDataUrl'] ?? '').toString().trim();
  if (logoDataUrl.isNotEmpty) {
    return logoDataUrl;
  }
  return (data['logoUrl'] ?? '').toString().trim();
}

Future<void> _uploadCurrentUserLogoForPdf(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sessao expirada. Faca login novamente.')),
    );
    return;
  }

  try {
    final logoDataUrl = await _pickAndResizeLogoDataUrl(
      maxWidth: _userLogoMaxWidthPx,
      maxHeight: _userLogoMaxHeightPx,
    );
    if (logoDataUrl == null || logoDataUrl.trim().isEmpty) {
      return;
    }

    var storedWidth = 0;
    var storedHeight = 0;
    final bytes = _decodeDataUrlImageBytes(logoDataUrl);
    if (bytes != null) {
      final decoded = image_lib.decodeImage(bytes);
      if (decoded != null) {
        storedWidth = decoded.width;
        storedHeight = decoded.height;
      }
    }

    await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email ?? '',
      'logoDataUrl': logoDataUrl,
      'logoMeta': {
        'maxWidthPx': _userLogoMaxWidthPx,
        'maxHeightPx': _userLogoMaxHeightPx,
        'storedWidthPx': storedWidth,
        'storedHeightPx': storedHeight,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Logo salvo com sucesso.')));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Falha ao salvar logo: $error')));
  }
}

Future<void> _removeCurrentUserLogoForPdf(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sessao expirada. Faca login novamente.')),
    );
    return;
  }

  try {
    await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
      'logoDataUrl': FieldValue.delete(),
      'logoMeta': FieldValue.delete(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Logo removido.')));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Falha ao remover logo: $error')));
  }
}

Widget _buildPortalUserLogoCard(BuildContext context) {
  final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  final textTheme = Theme.of(context).textTheme;

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
              Text('Logo da Empresa', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Dimensões 240x96 - imagens maiores serão redimensionadas.',
              ),
              const SizedBox(height: 14),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: uid.isEmpty
                    ? null
                    : FirebaseFirestore.instance
                          .collection('usuarios')
                          .doc(uid)
                          .snapshots(),
                builder: (context, snapshot) {
                  final data =
                      snapshot.data?.data() ?? const <String, dynamic>{};
                  final logoValue = _readUserLogoDataUrl(data);
                  final logoBytes = _decodeDataUrlImageBytes(logoValue);
                  final hasLogo = logoBytes != null || logoValue.isNotEmpty;

                  final imageWidget = logoBytes != null
                      ? Image.memory(
                          logoBytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                      : (logoValue.startsWith('http://') ||
                            logoValue.startsWith('https://'))
                      ? Image.network(
                          logoValue,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        )
                      : const Center(
                          child: Text(
                            'Sem logo',
                            style: TextStyle(fontSize: 11),
                          ),
                        );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 128,
                        height: 56,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.white,
                        ),
                        child: imageWidget,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Formatos suportados: JPEG, PNG, GIF e WEBP.',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: uid.isEmpty
                                ? null
                                : () => _uploadCurrentUserLogoForPdf(context),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Enviar logo'),
                          ),
                          if (hasLogo)
                            TextButton.icon(
                              onPressed: uid.isEmpty
                                  ? null
                                  : () => _removeCurrentUserLogoForPdf(context),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remover logo'),
                            ),
                        ],
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

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.activeTenant,
    required this.accountContractLock,
    required this.upgradingWorkspace,
    required this.onUpgradeToRep,
  });

  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;
  final bool upgradingWorkspace;
  final VoidCallback onUpgradeToRep;

  static const List<String> _enterpriseOnlyWorkspaceRules = [
    'Esta Conta BrandOp controla apenas a propria empresa contratante.',
    'Não é permitido criar outras empresas ou operações paralelas neste login.',
    'Mudanças de plano/tipo devem ocorrer por migração controlada, sem criar novo workspace.',
  ];

  static const List<String> _flexibleWorkspaceRules = [
    'Esta conta está vinculada ao tipo de workspace atual para fins de billing e governança.',
    'O contexto Individual não adiciona usuários e não abre cadeia de representações.',
    'Para mudar de Individual para Representações (ou outro plano), o caminho e upgrade de plano.',
    'Não criamos workspace paralelo por esta tela para evitar divergência de billing.',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canEditWorkspaceProfile = _canEditWorkspaceProfile(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conta', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Configurações globais da sua conta e gestão de empresas no mesmo lugar.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: StreamBuilder<Map<String, dynamic>?>(
              stream: _workspaceProfileService().watchWorkspace(
                activeTenant.tenantId,
              ),
              builder: (context, snapshot) {
                final workspaceData =
                    snapshot.data ?? const <String, dynamic>{};

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dados do workspace',
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Informações base da conta e do workspace em uso.',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (canEditWorkspaceProfile)
                              Tooltip(
                                message: 'Editar dados do workspace',
                                child: IconButton.outlined(
                                  onPressed: () => _openWorkspaceProfileEditor(
                                    context,
                                    activeTenant,
                                    workspaceData,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _WorkspaceInfoGrid(
                          items: _buildWorkspaceInfoItems(
                            activeTenant: activeTenant,
                            accountContractLock: accountContractLock,
                            workspaceData: workspaceData,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildPortalUserLogoCard(context),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gestão de workspaces', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    ..._buildWorkspaceManagementRules(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildWorkspaceManagementRules() {
    final enterpriseOnly =
        accountContractLock == AccountContractLock.enterpriseOnly;
    final rules = enterpriseOnly
        ? _enterpriseOnlyWorkspaceRules
        : _flexibleWorkspaceRules;

    final widgets = <Widget>[];
    for (var index = 0; index < rules.length; index++) {
      widgets.add(_workspaceManagementBullet(rules[index]));
      if (index < rules.length - 1) {
        widgets.add(const SizedBox(height: 6));
      }
    }

    if (!enterpriseOnly &&
        activeTenant.workspaceType == 'seller_solo_workspace') {
      widgets.add(const SizedBox(height: 16));
      widgets.add(
        FilledButton.icon(
          onPressed: upgradingWorkspace ? null : onUpgradeToRep,
          icon: const Icon(Icons.upgrade_outlined),
          label: Text(
            upgradingWorkspace
                ? 'Aplicando upgrade...'
                : 'Upgrade para Representações',
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _workspaceManagementBullet(String message) {
    return Text('• $message');
  }
}

class _RepresentedCompaniesSection extends StatelessWidget {
  const _RepresentedCompaniesSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  static const List<String> _unsupportedRepresentedCompaniesLines = [
    'Disponivel apenas para workspaces Individual e Representações.',
    'No contexto Empresa (BrandOp), esta conta administra apenas a empresa contratante.',
  ];

  static const List<String> _emptyRepresentedCompaniesLines = [
    'Nenhuma representada cadastrada ainda.',
    'Use esta lista para manter as empresas que você representa neste workspace.',
  ];

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final supportsRepresentedCompanies =
        activeTenant.workspaceType == 'seller_solo_workspace' ||
        activeTenant.workspaceType == 'rep_workspace';
    final canManageRepresentedCompanies = _canManageRepresentedCompanies(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Representadas', style: textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Cadastro e gestao das empresas representadas no workspace atual.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: _workspaceProfileService().watchWorkspace(
                  activeTenant.tenantId,
                ),
                builder: (context, workspaceSnapshot) {
                  const headerColor = Color(0xFFF5F6F8);
                  const bodyColor = Colors.white;
                  const rowDividerColor = Color(0xFFE6E9EE);

                  final workspaceData =
                      workspaceSnapshot.data ?? const <String, dynamic>{};
                  final favoriteRepresentedCompanyId =
                      (workspaceData['favoriteRepresentedCompanyId'] ?? '')
                          .toString()
                          .trim();

                  return StreamBuilder<List<Map<String, Object?>>>(
                    stream: _workspaceProfileService()
                        .watchRepresentedCompanies(activeTenant.tenantId),
                    builder: (context, snapshot) {
                      final representedCompanies =
                          _representedCompaniesFromStorage(
                            snapshot.data ?? const <Map<String, Object?>>[],
                          );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            color: headerColor,
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Empresas representadas',
                                    style: textTheme.titleMedium,
                                  ),
                                ),
                                if (supportsRepresentedCompanies &&
                                    canManageRepresentedCompanies)
                                  FilledButton.icon(
                                    onPressed: () => _createRepresentedCompany(
                                      context,
                                      activeTenant,
                                      allCompanies: representedCompanies,
                                    ),
                                    icon: const Icon(
                                      Icons.add_business_outlined,
                                    ),
                                    label: const Text('Adicionar'),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            color: bodyColor,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: _buildRepresentedCompaniesBody(
                              context,
                              representedCompanies: representedCompanies,
                              activeTenant: activeTenant,
                              favoriteRepresentedCompanyId:
                                  favoriteRepresentedCompanyId,
                              supportsRepresentedCompanies:
                                  supportsRepresentedCompanies,
                              canManageRepresentedCompanies:
                                  canManageRepresentedCompanies,
                              rowDividerColor: rowDividerColor,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRepresentedCompaniesBody(
    BuildContext context, {
    required List<_RepresentedCompany> representedCompanies,
    required TenantEntryOption activeTenant,
    required String favoriteRepresentedCompanyId,
    required bool supportsRepresentedCompanies,
    required bool canManageRepresentedCompanies,
    required Color rowDividerColor,
  }) {
    if (!supportsRepresentedCompanies) {
      return _buildInformativeMessageLines(
        _unsupportedRepresentedCompaniesLines,
      );
    }

    if (representedCompanies.isEmpty) {
      return _buildInformativeMessageLines(_emptyRepresentedCompaniesLines);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < representedCompanies.length; index++) ...[
          if (index > 0) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: rowDividerColor),
            const SizedBox(height: 14),
          ],
          Builder(
            builder: (context) {
              final company = representedCompanies[index];
              return _buildRepresentedCompanyRow(
                context,
                company: company,
                allCompanies: representedCompanies,
                activeTenant: activeTenant,
                favoriteRepresentedCompanyId: favoriteRepresentedCompanyId,
                supportsRepresentedCompanies: supportsRepresentedCompanies,
                canManageRepresentedCompanies: canManageRepresentedCompanies,
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildInformativeMessageLines(List<String> lines) {
    final children = <Widget>[];
    for (var index = 0; index < lines.length; index++) {
      children.add(Text(lines[index]));
      if (index < lines.length - 1) {
        children.add(const SizedBox(height: 6));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildRepresentedCompanyRow(
    BuildContext context, {
    required _RepresentedCompany company,
    required List<_RepresentedCompany> allCompanies,
    required TenantEntryOption activeTenant,
    required String favoriteRepresentedCompanyId,
    required bool supportsRepresentedCompanies,
    required bool canManageRepresentedCompanies,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildRepresentedCompanyInfo(
            context,
            company: company,
            allCompanies: allCompanies,
          ),
        ),
        if (supportsRepresentedCompanies && canManageRepresentedCompanies)
          ..._buildRepresentedCompanyActions(
            context,
            company: company,
            allCompanies: allCompanies,
            activeTenant: activeTenant,
            favoriteRepresentedCompanyId: favoriteRepresentedCompanyId,
          ),
      ],
    );
  }

  Widget _buildRepresentedCompanyInfo(
    BuildContext context, {
    required _RepresentedCompany company,
    required List<_RepresentedCompany> allCompanies,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _representedCompanyDisplayName(
            company,
            fallback: 'Sem nome fantasia',
          ),
          style: textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text('CNPJ: ${company.cnpj.isEmpty ? 'Não informado' : company.cnpj}'),
        if (company.logradouro.isNotEmpty || company.numero.isNotEmpty)
          Text('Endereço: ${_formatAddressLine(company)}'),
        Text('CEP: ${company.cep.isEmpty ? 'Não informado' : company.cep}'),
        Text('Cidade/UF: ${_formatCityUfLine(company)}'),
        Text(
          _companyRelationshipSummary(
            company: company,
            allCompanies: allCompanies,
          ),
        ),
        if (company.segmento.isNotEmpty) Text('Segmento: ${company.segmento}'),
        Text('Regime tributário: ${_taxRegimeLabel(company.taxRegime)}'),
      ],
    );
  }

  List<Widget> _buildRepresentedCompanyActions(
    BuildContext context, {
    required _RepresentedCompany company,
    required List<_RepresentedCompany> allCompanies,
    required TenantEntryOption activeTenant,
    required String favoriteRepresentedCompanyId,
  }) {
    final isFavorite = company.id == favoriteRepresentedCompanyId;

    return [
      _buildRepresentedCompanyActionButton(
        message: isFavorite ? 'Representada favorita' : 'Definir como favorita',
        onPressed: isFavorite
            ? null
            : () => _setFavoriteRepresentedCompany(
                context,
                activeTenant,
                company,
              ),
        icon: isFavorite ? Icons.star : Icons.star_outline,
      ),
      const SizedBox(width: 8),
      _buildRepresentedCompanyActionButton(
        message: 'Editar',
        onPressed: () => _editRepresentedCompany(
          context,
          activeTenant,
          company,
          allCompanies: allCompanies,
        ),
        icon: Icons.edit_outlined,
      ),
      const SizedBox(width: 8),
      _buildRepresentedCompanyActionButton(
        message: 'Excluir',
        onPressed: () =>
            _deleteRepresentedCompany(context, activeTenant, company),
        icon: Icons.delete_outline,
      ),
    ];
  }

  Widget _buildRepresentedCompanyActionButton({
    required String message,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    return Tooltip(
      message: message,
      child: IconButton.outlined(onPressed: onPressed, icon: Icon(icon)),
    );
  }

  String _formatAddressLine(_RepresentedCompany company) {
    final street = company.logradouro.isEmpty
        ? 'Não informado'
        : company.logradouro;
    final number = company.numero.isEmpty ? '' : ', ${company.numero}';
    return '$street$number';
  }

  String _formatCityUfLine(_RepresentedCompany company) {
    return _cityUfLabel(city: company.cidade, uf: company.uf);
  }

  Future<void> _createRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    await _upsertRepresentedCompanyFromEditor(
      context,
      tenantId: activeTenant.tenantId,
      allCompanies: allCompanies,
      successMessage: 'Representada cadastrada com sucesso.',
      failurePrefix: 'Falha ao cadastrar representada',
    );
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    await _editRepresentedCompanyForTenant(
      context,
      tenantId: activeTenant.tenantId,
      company: company,
      allCompanies: allCompanies,
    );
  }

  Future<void> _deleteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    if (!await _confirmDeleteRepresentedCompany(context, company)) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    await _runWorkspaceProfileMutation(
      context,
      action: (service) {
        return service.deleteRepresentedCompany(
          tenantId: activeTenant.tenantId,
          companyId: company.id,
        );
      },
      successMessage: 'Representada excluida com sucesso.',
      failurePrefix: 'Falha ao excluir representada',
    );
  }

  Future<void> _setFavoriteRepresentedCompany(
    BuildContext context,
    TenantEntryOption activeTenant,
    _RepresentedCompany company,
  ) async {
    await _runWorkspaceProfileMutation(
      context,
      action: (service) {
        return service.setFavoriteRepresentedCompany(
          tenantId: activeTenant.tenantId,
          companyId: company.id,
        );
      },
      successMessage:
          'Representada favorita: ${_representedCompanyDisplayName(company, fallback: company.id)}',
      failurePrefix: 'Falha ao atualizar favorita',
    );
  }
}

abstract class _ClientesTenantSection extends StatelessWidget {
  const _ClientesTenantSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _buildClientesPageForTenant(activeTenant);
  }
}

class _PartnersSection extends _ClientesTenantSection {
  const _PartnersSection({
    required super.activeTenant,
    super.activeRepresentedCompanyName,
  });
}

class _CustomersSection extends _ClientesTenantSection {
  const _CustomersSection({
    required super.activeTenant,
    super.activeRepresentedCompanyName,
  });
}

Widget _buildClientesPageForTenant(TenantEntryOption activeTenant) {
  final identity = _portalIdentityForTenant(activeTenant);

  return ClientesPage(
    identity: identity,
    repository: FirestoreClienteRepository(FirebaseFirestore.instance),
    preCadastroRepository: FirestoreClientePreCadastroRepository(
      FirebaseFirestore.instance,
    ),
  );
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Tarefas',
      subtitle: 'Planejamento de visitas, follow-ups e rotas de campo por prioridade.',
      items: const [
        'Agenda semanal por vendedor',
        'Alertas de tarefas vencidas',
        'Roteiro de visitas e checkpoints',
      ],
    );
  }
}

class _TenantWorkspaceHubSection extends StatelessWidget {
  const _TenantWorkspaceHubSection({
    required this.activeTenant,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    return _SimpleCardSection(
      title: 'Menu da representada',
      subtitle: 'Use os menus horizontais para acessar detalhes, produtos, promoções, destaques, políticas e configurações da empresa ativa.',
      items: const [
        'Detalhes',
        'Produtos',
        'Promoções',
        'Destaques',
        'Políticas comerciais',
        'Configurações',
      ],
    );
  }
}

class _RepresentedDetailsSection extends StatelessWidget {
  const _RepresentedDetailsSection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  static const String _detailsCardTitle = 'Informações de cadastro';
  static const List<String> _selectionRequiredItems = [
    'Razão social e nome fantasia',
    'CNPJ, contato e endereço',
    'Segmento e status',
  ];
  static const List<String> _notFoundItems = [
    'Valide a representada ativa no topo',
    'Atualize a lista de representadas',
  ];

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: activeTenant.role,
      workspaceType: activeTenant.workspaceType,
    );
    final selectedId = (selectedRepresentedCompanyId ?? '').trim();
    if (selectedId.isEmpty) {
      return _buildDetailsInfoCard(
        subtitle: 'Selecione uma representada no topo para editar os detalhes.',
        items: _selectionRequiredItems,
      );
    }

    return StreamBuilder<List<Map<String, Object?>>>(
      stream: _workspaceProfileService().watchRepresentedCompanies(
        activeTenant.tenantId,
      ),
      builder: (context, snapshot) {
        final representedCompanies = _representedCompaniesFromStorage(
          snapshot.data ?? const <Map<String, Object?>>[],
        );

        final selected = _findCompanyById(
          allCompanies: representedCompanies,
          companyId: selectedId,
        );

        if (selected == null) {
          return _buildDetailsInfoCard(
            subtitle:
                'A representada selecionada não foi encontrada na base atual.',
            items: _notFoundItems,
          );
        }

        final selectedCompany = selected;
        final displayName = selectedCompany.nomeFantasia.isEmpty
            ? (activeRepresentedCompanyName ?? selectedCompany.id)
            : selectedCompany.nomeFantasia;
        final cityUf = _cityUfLabel(
          city: selectedCompany.cidade,
          uf: selectedCompany.uf,
        );

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: _buildDetailsHeader(
                  context,
                  selectedCompany: selectedCompany,
                  displayName: displayName,
                  canEditSettings: canEditSettings,
                  representedCompanies: representedCompanies,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (!canEditSettings) ...[
                      _ownerOnlyReadOnlyNotice(
                        context,
                        message: 'Apenas o owner pode alterar os dados da representada. Este perfil pode apenas consultar.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    _profileTwoColumnSection(
                      context,
                      leftTitle: 'Contato',
                      leftRows: _buildContatoRows(selectedCompany),
                      rightTitle: 'Cadastro',
                      rightRows: _buildCadastroRows(selectedCompany),
                    ),
                    const SizedBox(height: 14),
                    Divider(color: Theme.of(context).dividerColor),
                    const SizedBox(height: 14),
                    _profileTwoColumnSection(
                      context,
                      leftTitle: 'Endereço',
                      leftRows: _buildEnderecoRows(selectedCompany, cityUf),
                      rightTitle: 'Comercial',
                      rightRows: _buildComercialRows(
                        selectedCompany,
                        representedCompanies,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailsInfoCard({
    required String subtitle,
    required List<String> items,
  }) {
    return _SimpleCardSection(
      title: _detailsCardTitle,
      subtitle: subtitle,
      items: items,
    );
  }

  Widget _buildDetailsHeader(
    BuildContext context, {
    required _RepresentedCompany selectedCompany,
    required String displayName,
    required bool canEditSettings,
    required List<_RepresentedCompany> representedCompanies,
  }) {
    final cnpjLabel = selectedCompany.cnpj.trim().isEmpty
        ? 'CNPJ não cadastrado'
        : selectedCompany.cnpj;

    return Row(
      children: [
        _RepresentedCompanyAvatar(company: selectedCompany, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(cnpjLabel, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: canEditSettings
              ? () => _editRepresentedCompany(
                  context,
                  selectedCompany,
                  allCompanies: representedCompanies,
                )
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(canEditSettings ? 'Alterar' : 'Somente leitura'),
        ),
      ],
    );
  }

  List<Widget> _buildContatoRows(_RepresentedCompany selectedCompany) {
    return [
      _profileRow(
        Icons.call_outlined,
        selectedCompany.telefone,
        'Telefone não cadastrado',
      ),
      _profileRow(
        Icons.mail_outline,
        selectedCompany.email,
        'E-mail não cadastrado',
      ),
      _profileRow(
        Icons.badge_outlined,
        selectedCompany.contato,
        'Contato não cadastrado',
      ),
    ];
  }

  List<Widget> _buildCadastroRows(_RepresentedCompany selectedCompany) {
    return _buildLabelValueRows([
      MapEntry('Razão social', selectedCompany.razaoSocial),
      MapEntry('Nome fantasia', selectedCompany.nomeFantasia),
      MapEntry('CNPJ', selectedCompany.cnpj),
    ]);
  }

  List<Widget> _buildEnderecoRows(
    _RepresentedCompany selectedCompany,
    String cityUf,
  ) {
    return _buildLabelValueRows([
      MapEntry('CEP', selectedCompany.cep),
      MapEntry('Logradouro', selectedCompany.logradouro),
      MapEntry('Número', selectedCompany.numero),
      MapEntry('Cidade/UF', cityUf),
    ]);
  }

  List<Widget> _buildComercialRows(
    _RepresentedCompany selectedCompany,
    List<_RepresentedCompany> representedCompanies,
  ) {
    return _buildLabelValueRows([
      MapEntry('Segmento', selectedCompany.segmento),
      MapEntry('Regime tributário', _taxRegimeLabel(selectedCompany.taxRegime)),
      MapEntry(
        'Relação empresarial',
        _companyRelationshipSummary(
          company: selectedCompany,
          allCompanies: representedCompanies,
        ),
      ),
      MapEntry('Status', selectedCompany.ativo ? 'Ativa' : 'Inativa'),
    ]);
  }

  List<Widget> _buildLabelValueRows(List<MapEntry<String, String>> entries) {
    final rows = <Widget>[];
    for (final entry in entries) {
      rows.add(_profileLabelValue(entry.key, entry.value));
    }
    return rows;
  }

  _RepresentedCompany? _findCompanyById({
    required List<_RepresentedCompany> allCompanies,
    required String companyId,
  }) {
    for (final company in allCompanies) {
      if (company.id == companyId) {
        return company;
      }
    }
    return null;
  }

  Widget _profileTwoColumnSection(
    BuildContext context, {
    required String leftTitle,
    required List<Widget> leftRows,
    required String rightTitle,
    required List<Widget> rightRows,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _profileBlock(context, title: leftTitle, rows: leftRows),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _profileBlock(context, title: rightTitle, rows: rightRows),
        ),
      ],
    );
  }

  Widget _profileBlock(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _profileRow(IconData icon, String value, String fallback) {
    final output = value.trim().isEmpty ? fallback : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(output)),
        ],
      ),
    );
  }

  Widget _profileLabelValue(String label, String value) {
    final output = value.trim().isEmpty ? 'Não cadastrado' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(output),
        ],
      ),
    );
  }

  Future<void> _editRepresentedCompany(
    BuildContext context,
    _RepresentedCompany company, {
    required List<_RepresentedCompany> allCompanies,
  }) async {
    await _editRepresentedCompanyForTenant(
      context,
      tenantId: activeTenant.tenantId,
      company: company,
      allCompanies: allCompanies,
    );
  }
}

String _companyRelationshipSummary({
  required _RepresentedCompany company,
  required List<_RepresentedCompany> allCompanies,
}) {
  final parentId = company.parentCompanyId.trim();
  if (parentId.isNotEmpty) {
    final parentName = _representedCompanyNameById(
      companyId: parentId,
      allCompanies: allCompanies,
    );
    return 'Filial vinculada à matriz: $parentName';
  }

  var branchCount = 0;
  for (final candidate in allCompanies) {
    if (candidate.parentCompanyId.trim() == company.id) {
      branchCount++;
    }
  }

  if (branchCount > 0) {
    return 'Matriz com $branchCount filial(is) vinculada(s)';
  }

  return 'Empresa sem vínculo de matriz/filial';
}

String _representedCompanyNameById({
  required String companyId,
  required List<_RepresentedCompany> allCompanies,
}) {
  for (final company in allCompanies) {
    if (company.id != companyId) {
      continue;
    }
    final display = company.nomeFantasia.trim();
    return display.isEmpty ? company.id : display;
  }
  return companyId;
}

String _representedCompanyDisplayName(
  _RepresentedCompany company, {
  String fallback = 'esta representada',
}) {
  final displayName = company.nomeFantasia.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  return fallback;
}

String _cityUfLabel({required String city, required String uf}) {
  final cityValue = city.trim();
  final ufValue = uf.trim();
  if (cityValue.isEmpty) {
    return 'Não informado';
  }
  return '$cityValue${ufValue.isEmpty ? '' : '/$ufValue'}';
}

class _RepresentedCompany {
  const _RepresentedCompany({
    required this.id,
    required this.nomeFantasia,
    required this.razaoSocial,
    required this.cnpj,
    required this.cep,
    required this.logradouro,
    required this.numero,
    required this.logoUrl,
    required this.contato,
    required this.telefone,
    required this.email,
    required this.cidade,
    required this.uf,
    required this.segmento,
    required this.taxRegime,
    required this.ativo,
    required this.parentCompanyId,
  });

  final String id;
  final String nomeFantasia;
  final String razaoSocial;
  final String cnpj;
  final String cep;
  final String logradouro;
  final String numero;
  final String logoUrl;
  final String contato;
  final String telefone;
  final String email;
  final String cidade;
  final String uf;
  final String segmento;
  final String taxRegime;
  final bool ativo;
  final String parentCompanyId;
}

List<_RepresentedCompany> _representedCompaniesFromStorage(
  List<Map<String, Object?>> storedCompanies,
) {
  final result = <_RepresentedCompany>[];

  for (final rawCompany in storedCompanies) {
    final company = _representedCompanyFromMap(rawCompany);
    if (company != null) {
      result.add(company);
    }
  }

  result.sort(
    (a, b) =>
        a.nomeFantasia.toLowerCase().compareTo(b.nomeFantasia.toLowerCase()),
  );
  return result;
}

_RepresentedCompany? _representedCompanyFromMap(Map<String, Object?> map) {
  final id = (map['companyId'] ?? map['id'] ?? '').toString().trim();
  if (id.isEmpty) {
    return null;
  }

  final nomeFantasia = (map['nomeFantasia'] ?? '').toString();
  final cidade = (map['cidade'] ?? '').toString();
  final uf = (map['uf'] ?? '').toString().toUpperCase();

  return _RepresentedCompany(
    id: id,
    nomeFantasia: nomeFantasia,
    razaoSocial: (map['razaoSocial'] ?? '').toString(),
    cnpj: (map['cnpj'] ?? '').toString(),
    cep: (map['cep'] ?? '').toString(),
    logradouro: (map['logradouro'] ?? '').toString(),
    numero: (map['numero'] ?? '').toString(),
    logoUrl: (map['logoUrl'] ?? '').toString(),
    contato: (map['contato'] ?? '').toString(),
    telefone: (map['telefone'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    cidade: cidade,
    uf: uf,
    segmento: (map['segmento'] ?? '').toString(),
    taxRegime: _normalizeTaxRegimeValue(map['taxRegime']),
    ativo: map['ativo'] == true,
    parentCompanyId: (map['parentCompanyId'] ?? '').toString().trim(),
  );
}

class _RepresentedCompanyAvatar extends StatelessWidget {
  const _RepresentedCompanyAvatar({required this.company, this.size = 24});

  final _RepresentedCompany company;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoUrl = company.logoUrl.trim();
    final trimmedName = company.nomeFantasia.trim();
    final initial = trimmedName.isEmpty
        ? 'R'
        : trimmedName.substring(0, 1).toUpperCase();
    final dataBytes = _decodeDataUrlImageBytes(logoUrl);
    ImageProvider<Object>? imageProvider;

    if (dataBytes != null) {
      imageProvider = MemoryImage(dataBytes);
    } else if (logoUrl.isNotEmpty) {
      imageProvider = NetworkImage(logoUrl);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: imageProvider == null
          ? Text(initial, style: TextStyle(fontSize: size * 0.42))
          : null,
    );
  }
}

Uint8List? _decodeDataUrlImageBytes(String value) {
  final normalized = value.trim();
  if (!normalized.startsWith('data:image/')) {
    return null;
  }

  final marker = ';base64,';
  final index = normalized.indexOf(marker);
  if (index == -1) {
    return null;
  }

  final encoded = normalized.substring(index + marker.length);
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}
