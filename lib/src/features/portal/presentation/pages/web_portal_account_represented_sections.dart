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

class _BillingSection extends StatefulWidget {
  const _BillingSection({
    required this.activeTenant,
    required this.canManageBillingActions,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final bool canManageBillingActions;
  final String? activeRepresentedCompanyName;

  @override
  State<_BillingSection> createState() => _BillingSectionState();
}

class _BillingSectionState extends State<_BillingSection> {
  static const int _maxSeatAddonDeltaPerOperation = 10;

  late final WebPortalBillingService _billingService;
  late final TextEditingController _checkoutAddonSeatsController;
  Future<List<WebPortalAvailableBillingPlan>>? _availablePlansFuture;
  String _selectedCheckoutPlanKey = '';
  int _checkoutAddonSeats = 0;
  bool _startingCheckout = false;
  bool _openingPortal = false;
  bool _applyingSelfServiceAction = false;

  @override
  void initState() {
    super.initState();
    _billingService = WebPortalBillingService();
    _checkoutAddonSeatsController = TextEditingController(text: '0');
    _selectedCheckoutPlanKey = _normalizeBillingPlanKey(
      _requestedBillingPlanFromUrl(),
    );
    _availablePlansFuture = _billingService.listAvailableCheckoutPlans(
      tenantId: widget.activeTenant.tenantId,
    );
  }

  String _requestedBillingPlanFromUrl() {
    final direct = (Uri.base.queryParameters['plan'] ?? '').trim();
    if (direct.isNotEmpty) {
      return direct;
    }

    final fragment = Uri.base.fragment;
    final queryIndex = fragment.indexOf('?');
    if (queryIndex < 0 || queryIndex + 1 >= fragment.length) {
      return '';
    }

    final rawQuery = fragment.substring(queryIndex + 1).trim();
    if (rawQuery.isEmpty) {
      return '';
    }

    try {
      return (Uri.splitQueryString(rawQuery)['plan'] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  @override
  void didUpdateWidget(covariant _BillingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTenantId = oldWidget.activeTenant.tenantId.trim();
    final newTenantId = widget.activeTenant.tenantId.trim();
    if (oldTenantId != newTenantId) {
      setState(() {
        _selectedCheckoutPlanKey = '';
        _checkoutAddonSeats = 0;
        _availablePlansFuture = _billingService.listAvailableCheckoutPlans(
          tenantId: widget.activeTenant.tenantId,
        );
      });
      _checkoutAddonSeatsController.value = const TextEditingValue(
        text: '0',
        selection: TextSelection.collapsed(offset: 1),
      );
    }
  }

  @override
  void dispose() {
    _checkoutAddonSeatsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('tenants')
              .doc(widget.activeTenant.tenantId)
              .snapshots(),
          builder: (context, snapshot) {
            final tenantData =
                snapshot.data?.data() ?? const <String, dynamic>{};
            final rawBillingStatus =
                (tenantData['billingStatus'] ?? '').toString();
            final rawBillingPlanKey =
                (tenantData['billingPlanKey'] ?? '').toString();
            final billingStatus = _billingStatusLabel(
              rawBillingStatus,
            );
            final billingPlan = _nonEmptyOrDash(rawBillingPlanKey);
            final billingCycle = _billingCycleLabel(
              (tenantData['billingCycle'] ?? '').toString(),
            );
            final stripeCustomerId = (tenantData['stripeCustomerId'] ?? '')
                .toString()
                .trim();
            final asaasSubscriptionId =
                (tenantData['asaasSubscriptionId'] ?? '').toString().trim();
            final hasStripeCustomerId = stripeCustomerId.isNotEmpty;
            final hasAsaasSubscriptionId = asaasSubscriptionId.isNotEmpty;
            final billingProvider = _resolveBillingProviderFromTenantData(
              tenantData,
            );
            final billingProviderLabel = _billingProviderDisplayLabel(
              billingProvider,
            );
            final graceUntil = _formatDateOrDash(
              tenantData['billingGraceUntilAt'],
            );
            final updatedAt = _formatDateOrDash(tenantData['billingUpdatedAt']);
            final periodStart = _formatDateOrDash(
              tenantData['billingCurrentPeriodStartAt'],
            );
            final periodEnd = _formatDateOrDash(
              tenantData['billingCurrentPeriodEndAt'],
            );
            final periodLabel = _billingCurrentPeriodLabel(
              periodStart: periodStart,
              periodEnd: periodEnd,
              rawBillingStatus: rawBillingStatus,
              billingProvider: billingProvider,
              hasLinkedBillingContract:
                  hasStripeCustomerId || hasAsaasSubscriptionId,
            );
            final isOperationalAccessBlocked = _isOperationalAccessBlocked(
              rawStatus: rawBillingStatus,
              rawPlanKey: rawBillingPlanKey,
              rawGraceUntilAt: tenantData['billingGraceUntilAt'],
            );
            final operationalAccess = isOperationalAccessBlocked
                ? 'Sem acesso'
                : 'Liberado';
            final workspaceType = (widget.activeTenant.workspaceType)
                .trim()
                .toLowerCase();
            final enterpriseWorkspace =
                workspaceType == 'brand_owner_workspace';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Billing', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Controle de plano, ciclo e elegibilidade de uso do tenant ativo.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _SummaryCard(
                      title: 'Tenant',
                      value: widget.activeTenant.tenantName,
                    ),
                    _SummaryCard(title: 'Status', value: billingStatus),
                    _SummaryCard(title: 'Plano', value: billingPlan),
                    _SummaryCard(
                      title: 'Acesso operacional',
                      value: operationalAccess,
                    ),
                    _SummaryCard(title: 'Provider', value: billingProviderLabel),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Estado de cobrança',
                                style: textTheme.titleMedium,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isOperationalAccessBlocked
                                    ? const Color(0xFFFDEBEC)
                                    : const Color(0xFFE8F5EE),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                operationalAccess,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color:
                                          isOperationalAccessBlocked
                                          ? const Color(0xFF9A1E2A)
                                          : const Color(0xFF15603C),
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _WorkspaceInfoGrid(
                          items: [
                            _WorkspaceInfoItem(
                              label: 'Ciclo de cobrança',
                              value: billingCycle,
                            ),
                            _WorkspaceInfoItem(
                              label: 'Período atual',
                              value: periodLabel,
                            ),
                            _WorkspaceInfoItem(
                              label: 'Grace period até',
                              value: graceUntil,
                            ),
                            _WorkspaceInfoItem(
                              label: 'Última atualização',
                              value: updatedAt,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSeatGovernancePanel(
                          tenantData: tenantData,
                          textTheme: textTheme,
                        ),
                        if (enterpriseWorkspace) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Workspace enterprise usa cobrança contratual (boleto/NF). O checkout self-service Stripe não é usado nesse contexto.',
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.shopping_cart_checkout),
                                label: const Text('Checkout indisponível'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    !widget.canManageBillingActions ||
                                        _openingPortal ||
                                        billingProvider != 'stripe' ||
                                        !hasStripeCustomerId
                                    ? null
                                    : () => _openPortal(),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: Text(
                                  !widget.canManageBillingActions
                                      ? 'Somente owner/admin pode gerir billing'
                                      : billingProvider != 'stripe'
                                      ? 'Portal exclusivo Stripe'
                                      : !hasStripeCustomerId
                                      ? 'Portal indisponível (sem assinatura)'
                                      : _openingPortal
                                      ? 'Abrindo portal...'
                                      : 'Abrir portal Stripe',
                                ),
                              ),
                            ],
                          ),
                          if (billingProvider == 'stripe' &&
                              !hasStripeCustomerId) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'O portal Stripe só fica disponível após a primeira assinatura ativa. Para iniciar pagamento, use checkout ao selecionar um plano.',
                            ),
                          ] else if (billingProvider == 'asaas') ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Asaas não possui portal de assinatura equivalente ao Stripe. Use as ações de autoatendimento para interromper ou cancelar.',
                            ),
                          ],
                        ] else ...[
                          const SizedBox(height: 16),
                          _buildSelfServicePlansPanel(
                            tenantData: tenantData,
                            textTheme: textTheme,
                            workspaceType: workspaceType,
                            billingProvider: billingProvider,
                            hasStripeCustomerId: hasStripeCustomerId,
                            hasAsaasSubscriptionId: hasAsaasSubscriptionId,
                            rawBillingStatus: rawBillingStatus,
                            rawGraceUntilAt: tenantData['billingGraceUntilAt'],
                            canManageBillingActions:
                                widget.canManageBillingActions,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelfServicePlansPanel({
    required Map<String, dynamic> tenantData,
    required TextTheme textTheme,
    required String workspaceType,
    required String billingProvider,
    required bool hasStripeCustomerId,
    required bool hasAsaasSubscriptionId,
    required String rawBillingStatus,
    required Object? rawGraceUntilAt,
    required bool canManageBillingActions,
  }) {
    return FutureBuilder<List<WebPortalAvailableBillingPlan>>(
      future: _availablePlansFuture,
      builder: (context, plansSnapshot) {
        final plans =
            plansSnapshot.data ?? const <WebPortalAvailableBillingPlan>[];
        final currentPlanKey = _normalizeBillingPlanKey(
          (tenantData['billingPlanKey'] ?? '').toString(),
        );
        final selectedPlanKey = _resolveSelectedCheckoutPlanKey(
          plans,
          currentPlanKey: currentPlanKey,
          workspaceType: widget.activeTenant.workspaceType,
        );
        final hasActiveCurrentPlan = _isCurrentPlanEffectivelyActive(
          rawStatus: rawBillingStatus,
          rawGraceUntilAt: rawGraceUntilAt,
        );
        final selectedIsCurrent =
            hasActiveCurrentPlan &&
            selectedPlanKey.isNotEmpty &&
            selectedPlanKey == currentPlanKey;
        final isStripeProvider = billingProvider == 'stripe';
        final isAsaasProvider = billingProvider == 'asaas';
        final currentAddonSeats = _readNonNegativeInt(
          tenantData['billingSeatsAddon'],
          fallback: _readNonNegativeInt(tenantData['billingSeatAddons']),
        );
        final selectedPlan = _findPlanByKey(plans, selectedPlanKey);
        final selectedPlanSupportsSeatAddon =
          selectedPlan != null &&
          _normalizeBillingPlanKey(selectedPlan.seatAddonPlanKey).isNotEmpty;
        final selectedAddonSeats = _checkoutAddonSeats;
        final canApplySeatAddonsToCurrentPlan =
          isStripeProvider && selectedIsCurrent && selectedPlanSupportsSeatAddon;
        final canSubmitSeatAddonDelta =
          selectedAddonSeats > 0 &&
          selectedAddonSeats <= _maxSeatAddonDeltaPerOperation;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escolha seu Plano',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (plansSnapshot.connectionState == ConnectionState.waiting &&
                !plansSnapshot.hasData)
              const LinearProgressIndicator(minHeight: 2)
            else if (plansSnapshot.hasError)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Falha ao carregar planos: ${plansSnapshot.error}',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _reloadAvailablePlans,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              )
            else if (plans.isEmpty)
              const Text(
                'Nenhum plano ativo disponível para o seu workspace no momento.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final orderedPlans = _sortPlansForDisplay(
                    plans,
                    currentPlanKey: currentPlanKey,
                    workspaceType: workspaceType,
                    hasActiveCurrentPlan: hasActiveCurrentPlan,
                  );
                  final columns = constraints.maxWidth >= 1080
                      ? 3
                      : constraints.maxWidth >= 700
                      ? 2
                      : 1;
                  final cardWidth =
                      (constraints.maxWidth - ((columns - 1) * 12)) / columns;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: orderedPlans
                        .map((plan) {
                          final normalizedPlanKey = _normalizeBillingPlanKey(
                            plan.billingPlanKey,
                          );
                          final isSelected =
                              selectedPlanKey == normalizedPlanKey;
                          final isCurrent =
                              hasActiveCurrentPlan &&
                              currentPlanKey.isNotEmpty &&
                              currentPlanKey == normalizedPlanKey;
                          final planTier = _inferPlanTierFromBillingPlanKey(
                            normalizedPlanKey,
                          );
                          final isUpgrade =
                              !isCurrent &&
                              planTier == _planTierUpgrade &&
                              (currentPlanKey.isEmpty ||
                                  _inferPlanTierFromBillingPlanKey(
                                        currentPlanKey,
                                      ) ==
                                      _planTierBase);
                          final features = _featureLabelsForPlan(
                            workspaceType: workspaceType,
                            planTier: planTier,
                          );
                          final planSupportsSeatAddon =
                              _normalizeBillingPlanKey(plan.seatAddonPlanKey).isNotEmpty;
                          final showSeatAddonCard =
                              isStripeProvider &&
                              isCurrent &&
                              planSupportsSeatAddon;
                          var seatAddonUnitPriceCents = plan.seatAddonUnitPriceCents;
                          if (isCurrent && seatAddonUnitPriceCents <= 0) {
                            seatAddonUnitPriceCents = _readNonNegativeInt(
                              tenantData['billingSeatAddonUnitPriceCents'],
                            );
                          }

                          return SizedBox(
                            width: cardWidth,
                            child: _BillingPlanCard(
                              plan: plan,
                              isSelected: isSelected,
                              isCurrent: isCurrent,
                              isUpgrade: isUpgrade,
                              features: features,
                              onTap: () {
                                setState(() {
                                  _selectedCheckoutPlanKey = normalizedPlanKey;
                                  _setCheckoutAddonSeatsDelta(0);
                                });
                              },
                              seatAddonCard: showSeatAddonCard
                                  ? _buildStripeSeatAddonSideCard(
                                      billingPlanKey: normalizedPlanKey,
                                      includedSeats: plan.includedSeats,
                                      currentAddonSeats: currentAddonSeats,
                                      addonSeats: _checkoutAddonSeats,
                                      addonUnitPriceCents: seatAddonUnitPriceCents,
                                      addonDisplayAmount: plan.seatAddonDisplayAmount,
                                      canManageBillingActions:
                                          canManageBillingActions &&
                                          !_startingCheckout,
                                    )
                                  : null,
                            ),
                          );
                        })
                        .toList(growable: false),
                  );
                },
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      !canManageBillingActions ||
                          _startingCheckout ||
                          selectedPlanKey.isEmpty ||
                          (canApplySeatAddonsToCurrentPlan
                              ? !canSubmitSeatAddonDelta
                              : selectedIsCurrent)
                      ? null
                      : () {
                          if (canApplySeatAddonsToCurrentPlan) {
                            _addSeatAddonsToCurrentPlan(
                              billingPlanKey: selectedPlanKey,
                              addonSeatsDelta: selectedAddonSeats,
                            );
                            return;
                          }

                          _startCheckout(
                            billingPlanKey: selectedPlanKey,
                            addonSeats: selectedAddonSeats,
                            billingProvider: billingProvider,
                          );
                        },
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: Text(
                    !canManageBillingActions
                        ? 'Somente owner/admin pode contratar ou alterar plano'
                        : _startingCheckout
                        ? canApplySeatAddonsToCurrentPlan
                              ? 'Aplicando seats extras...'
                              : 'Abrindo checkout...'
                        : canApplySeatAddonsToCurrentPlan
                        ? canSubmitSeatAddonDelta
                              ? 'Adicionar +$selectedAddonSeats seats e cobrar agora'
                              : 'Defina de 1 a 10 seats extras'
                        : selectedIsCurrent
                        ? 'Plano já ativo'
                        : 'Contratar e ativar plano selecionado',
                  ),
                ),
                if (isStripeProvider)
                  OutlinedButton.icon(
                    onPressed:
                        !canManageBillingActions ||
                            _openingPortal ||
                            !hasStripeCustomerId
                        ? null
                        : () => _openPortal(),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      !canManageBillingActions
                          ? 'Somente owner/admin pode gerir billing'
                          : !hasStripeCustomerId
                          ? 'Portal indisponível (sem assinatura)'
                          : _openingPortal
                          ? 'Abrindo portal...'
                          : 'Abrir portal Stripe',
                    ),
                  )
                else if (isAsaasProvider)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Asaas sem portal de assinatura'),
                  ),
              ],
            ),
            if (isStripeProvider &&
                canManageBillingActions &&
                !hasStripeCustomerId) ...[
              const SizedBox(height: 8),
              const Text(
                'O portal Stripe só abre após a criação da primeira assinatura. Para o primeiro pagamento, selecione um plano e clique em contratar e ativar.',
              ),
            ],
            if (isAsaasProvider) ...[
              const SizedBox(height: 12),
              Text(
                'Autoatendimento Asaas',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasAsaasSubscriptionId
                    ? 'Use as ações abaixo para interromper a recorrência ou cancelar o plano atual.'
                    : 'Ações indisponíveis até existir uma assinatura Asaas vinculada ao tenant.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        !canManageBillingActions ||
                            _applyingSelfServiceAction ||
                            !hasAsaasSubscriptionId
                        ? null
                        : () => _runAsaasSelfServiceAction(
                          action: 'stop_renewal',
                          confirmTitle: 'Interromper renovação automática?',
                          confirmMessage:
                              'Esta ação muda a assinatura para INACTIVE no Asaas e impede novas cobranças recorrentes.',
                        ),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text(
                      _applyingSelfServiceAction
                          ? 'Aplicando ação...'
                          : 'Interromper renovação',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        !canManageBillingActions ||
                            _applyingSelfServiceAction ||
                            !hasAsaasSubscriptionId
                        ? null
                        : () => _runAsaasSelfServiceAction(
                          action: 'cancel_now',
                          confirmTitle: 'Cancelar plano agora?',
                          confirmMessage:
                              'Esta ação remove a assinatura no Asaas. Ela é irreversível pelo portal e exige nova contratação para retomar.',
                        ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      _applyingSelfServiceAction
                          ? 'Aplicando ação...'
                          : 'Cancelar plano',
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  void _reloadAvailablePlans() {
    setState(() {
      _availablePlansFuture = _billingService.listAvailableCheckoutPlans(
        tenantId: widget.activeTenant.tenantId,
      );
    });
  }

  List<WebPortalAvailableBillingPlan> _sortPlansForDisplay(
    List<WebPortalAvailableBillingPlan> plans, {
    required String currentPlanKey,
    required String workspaceType,
    required bool hasActiveCurrentPlan,
  }) {
    final ordered = List<WebPortalAvailableBillingPlan>.from(plans);
    final defaultPlan = _normalizeBillingPlanKey(
      _defaultPlanForWorkspaceType(workspaceType),
    );

    ordered.sort((a, b) {
      final keyA = _normalizeBillingPlanKey(a.billingPlanKey);
      final keyB = _normalizeBillingPlanKey(b.billingPlanKey);
      final isCurrentA =
          hasActiveCurrentPlan &&
          currentPlanKey.isNotEmpty &&
          keyA == currentPlanKey;
      final isCurrentB =
          hasActiveCurrentPlan &&
          currentPlanKey.isNotEmpty &&
          keyB == currentPlanKey;
      if (isCurrentA != isCurrentB) {
        return isCurrentA ? -1 : 1;
      }

      final isDefaultA = defaultPlan.isNotEmpty && keyA == defaultPlan;
      final isDefaultB = defaultPlan.isNotEmpty && keyB == defaultPlan;
      if (isDefaultA != isDefaultB) {
        return isDefaultA ? -1 : 1;
      }

      final tierA = _inferPlanTierFromBillingPlanKey(keyA);
      final tierB = _inferPlanTierFromBillingPlanKey(keyB);
      if (tierA != tierB) {
        if (tierA == _planTierBase) {
          return -1;
        }
        if (tierB == _planTierBase) {
          return 1;
        }
      }

      return a.planDisplayName.toLowerCase().compareTo(
        b.planDisplayName.toLowerCase(),
      );
    });

    return ordered;
  }

  String _inferPlanTierFromBillingPlanKey(String billingPlanKey) {
    final key = _normalizeBillingPlanKey(billingPlanKey);
    if (key.endsWith('_upgrade') ||
        key.contains('_upgrade_') ||
        key.contains('premium') ||
        key.contains('pro')) {
      return _planTierUpgrade;
    }
    return _planTierBase;
  }

  List<String> _featureLabelsForPlan({
    required String workspaceType,
    required String planTier,
  }) {
    final workspaceFeatures =
        _workspacePlanFeatureMatrix[workspaceType.trim().toLowerCase()] ??
        const <String, Set<String>>{};
    final planFeatures = workspaceFeatures[planTier] ?? const <String>{};

    final labels = <String>[];
    labels.add('Fluxo principal do workspace habilitado');
    if (planFeatures.contains(_featureAdvancedPricing)) {
      labels.add('Libera tabelas de preço avançadas');
    }
    labels.add('Checkout e gestão de cobrança no portal');
    return labels;
  }

  static String _nonEmptyOrDash(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '-' : normalized;
  }

  static String _billingStatusLabel(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Ativo';
      case 'past_due':
        return 'Em atraso';
      case 'grace':
        return 'Em tolerância';
      case 'suspended':
        return 'Suspenso';
      case 'canceled':
        return 'Cancelado';
      case 'no_plan':
        return 'Sem plano';
      default:
        return value.isEmpty ? 'Não definido' : value;
    }
  }

  static String _billingCycleLabel(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'month':
      case 'monthly':
        return 'Mensal';
      case 'year':
      case 'yearly':
        return 'Anual';
      default:
        return value.isEmpty ? 'Não definido' : value;
    }
  }

  static String _billingCurrentPeriodLabel({
    required String periodStart,
    required String periodEnd,
    required String rawBillingStatus,
    required String billingProvider,
    required bool hasLinkedBillingContract,
  }) {
    final status = rawBillingStatus.trim().toLowerCase();
    final hasStart = periodStart != '-';
    final hasEnd = periodEnd != '-';

    if (hasStart && hasEnd) {
      return '$periodStart até $periodEnd';
    }
    if (hasStart && !hasEnd) {
      return 'Iniciado em $periodStart (fim pendente)';
    }
    if (!hasStart && hasEnd) {
      return 'Até $periodEnd (início pendente)';
    }

    if (status == 'active' && hasLinkedBillingContract) {
      return 'Aguardando sincronização do ciclo no ${_billingProviderDisplayLabel(billingProvider)}';
    }

    return 'Não definido';
  }

  static bool _isOperationalAccessBlocked({
    required String rawStatus,
    required String rawPlanKey,
    Object? rawGraceUntilAt,
  }) {
    final status = rawStatus.trim().toLowerCase();
    if (status == 'suspended' || status == 'canceled' || status == 'no_plan') {
      return true;
    }

    final hasBillingPlan = rawPlanKey.trim().isNotEmpty;
    if (status == 'active' && !hasBillingPlan) {
      return true;
    }

    if (status == 'grace') {
      final graceUntil = _tryReadDateTime(rawGraceUntilAt);
      if (graceUntil != null && !DateTime.now().toUtc().isBefore(graceUntil.toUtc())) {
        return true;
      }
    }

    return false;
  }

  static bool _isCurrentPlanEffectivelyActive({
    required String rawStatus,
    Object? rawGraceUntilAt,
  }) {
    final status = rawStatus.trim().toLowerCase();
    if (status == 'active' || status == 'trial' || status == 'past_due') {
      return true;
    }

    if (status == 'grace') {
      final graceUntil = _tryReadDateTime(rawGraceUntilAt);
      if (graceUntil == null) {
        return false;
      }
      return DateTime.now().toUtc().isBefore(graceUntil.toUtc());
    }

    return false;
  }

  static DateTime? _tryReadDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  static String _formatDateOrDash(Object? value) {
    if (value == null) {
      return '-';
    }
    if (value is String && value.trim().isEmpty) {
      return '-';
    }
    final parsed = _readDateTime(value);
    if (parsed.millisecondsSinceEpoch == 0) {
      return '-';
    }
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  Widget _buildSeatGovernancePanel({
    required Map<String, dynamic> tenantData,
    required TextTheme textTheme,
  }) {
    final tenantId = widget.activeTenant.tenantId.trim();
    if (tenantId.isEmpty) {
      return const SizedBox.shrink();
    }

    final billingStatus = (tenantData['billingStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final billingPlanKey = (tenantData['billingPlanKey'] ?? '').toString().trim();
    final hasActiveBillingPlan =
        billingPlanKey.isNotEmpty &&
        billingStatus != 'no_plan' &&
        billingStatus != 'canceled' &&
        billingStatus != 'suspended';

    final includedSeats = _readNonNegativeInt(
      tenantData['billingSeatsIncluded'],
      fallback: 0,
    );
    final addonSeats = _readNonNegativeInt(
      tenantData['billingSeatsAddon'],
      fallback: _readNonNegativeInt(tenantData['billingSeatAddons']),
    );
    final configuredLimit = hasActiveBillingPlan
        ? (includedSeats + addonSeats).clamp(0, 999999)
        : 0;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tenant_memberships')
          .where('tenantId', isEqualTo: tenantId)
          .where('ativo', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];

        var activeCount = 0;
        var graceCount = 0;
        var regularCount = 0;
        var irregularCount = 0;
        final graceLabels = <String>[];

        for (final doc in docs) {
          final data = doc.data();
          final state = (data['state'] ?? '').toString().trim().toLowerCase();
          if (state != 'active') {
            continue;
          }
          activeCount += 1;

          if (!hasActiveBillingPlan) {
            irregularCount += 1;
            continue;
          }

          final seatState = (data['seatAccessState'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (seatState == 'over_limit_grace') {
            graceCount += 1;
            irregularCount += 1;
            final uid = (data['uid'] ?? '').toString().trim();
            final role = (data['role'] ?? '').toString().trim();
            final until = _formatDateOrDash(data['seatGraceUntilAt']);
            final roleLabel = role.isEmpty ? 'membro' : role;
            final uidLabel = uid.isEmpty ? doc.id : uid;
            graceLabels.add('$roleLabel • $uidLabel • até $until');
          } else if (seatState.isEmpty || seatState == 'regular') {
            regularCount += 1;
          } else {
            irregularCount += 1;
          }
        }

        final overLimitBy = configuredLimit > 0
            ? (activeCount - configuredLimit).clamp(0, 999999)
            : 0;
        final usageSummary = configuredLimit > 0
            ? '$activeCount / $configuredLimit ativos'
          : 'Sem plano ativo';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDCE3F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Governança de assentos',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  Text('Uso: $usageSummary'),
                  Text('Membros ativos: $activeCount'),
                  Text('Regulares: $regularCount'),
                  Text('Irregulares: $irregularCount'),
                  Text('Em grace: $graceCount'),
                  Text('Excesso: $overLimitBy'),
                ],
              ),
              if (!hasActiveBillingPlan && activeCount > 0) ...[
                const SizedBox(height: 6),
                const Text(
                  'Sem plano ativo: membros ativos ficam em estado irregular até a regularização da assinatura.',
                ),
              ],
              if (graceLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Membros em grace',
                  style: textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                ...graceLabels.map(
                  (label) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• $label'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static int _readNonNegativeInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is num) {
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed < 0 ? 0 : parsed;
      }
    }
    return fallback < 0 ? 0 : fallback;
  }

  void _setCheckoutAddonSeatsDelta(int value) {
    final clamped = value.clamp(0, _maxSeatAddonDeltaPerOperation).toInt();
    _checkoutAddonSeats = clamped;
    final textValue = '$clamped';
    if (_checkoutAddonSeatsController.text != textValue) {
      _checkoutAddonSeatsController.value = TextEditingValue(
        text: textValue,
        selection: TextSelection.collapsed(offset: textValue.length),
      );
    }
  }

  Widget _buildStripeSeatAddonSideCard({
    required String billingPlanKey,
    required int includedSeats,
    required int currentAddonSeats,
    required int addonSeats,
    required int addonUnitPriceCents,
    required String addonDisplayAmount,
    required bool canManageBillingActions,
  }) {
    final totalAddonCents = addonUnitPriceCents * addonSeats;
    final perUserAmountLabel = addonUnitPriceCents > 0
        ? '${WebPortalDashboardFormatService.formatCurrencyBr(addonUnitPriceCents / 100)} por usuario/mes'
        : (addonDisplayAmount.trim().isEmpty
              ? 'Valor por usuario sob consulta'
              : '${addonDisplayAmount.trim()} por usuario');
    final totalAmountLabel = addonUnitPriceCents > 0
        ? WebPortalDashboardFormatService.formatCurrencyBr(totalAddonCents / 100)
        : '--';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE3F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usuarios Adicionais',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            perUserAmountLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text('Seats inclusos: $includedSeats'),
          Text('Seats extras atuais: $currentAddonSeats'),
          const SizedBox(height: 10),
          Text(
            'Adicionar agora',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: !canManageBillingActions || addonSeats <= 0
                    ? null
                    : () {
                        setState(() {
                          _selectedCheckoutPlanKey = billingPlanKey;
                          _setCheckoutAddonSeatsDelta(addonSeats - 1);
                        });
                      },
                child: const Text('-'),
              ),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _checkoutAddonSeatsController,
                  enabled: canManageBillingActions,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Qtd',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) {
                    final parsed = int.tryParse(raw.trim()) ?? 0;
                    final clamped = parsed.clamp(
                      0,
                      _maxSeatAddonDeltaPerOperation,
                    );
                    if (_checkoutAddonSeats != clamped) {
                      setState(() {
                        _selectedCheckoutPlanKey = billingPlanKey;
                        _setCheckoutAddonSeatsDelta(clamped);
                      });
                    }
                    if ('$clamped' != _checkoutAddonSeatsController.text) {
                      _checkoutAddonSeatsController.value = TextEditingValue(
                        text: '$clamped',
                        selection: TextSelection.collapsed(
                          offset: '$clamped'.length,
                        ),
                      );
                    }
                  },
                ),
              ),
              OutlinedButton(
                onPressed: !canManageBillingActions ||
                        addonSeats >= _maxSeatAddonDeltaPerOperation
                    ? null
                    : () {
                        setState(() {
                          _selectedCheckoutPlanKey = billingPlanKey;
                          _setCheckoutAddonSeatsDelta(addonSeats + 1);
                        });
                      },
                child: const Text('+'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            addonUnitPriceCents > 0
                ? 'Total para adicionar agora: $totalAmountLabel'
                : 'Defina a quantidade e clique para adicionar seats extras.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCheckout({
    required String billingPlanKey,
    int addonSeats = 0,
    required String billingProvider,
  }) async {
    if (_startingCheckout) {
      return;
    }

    final normalizedPlanKey = _normalizeBillingPlanKey(billingPlanKey);
    if (normalizedPlanKey.isEmpty) {
      _showBillingActionInfo(
        context,
        'Selecione um plano disponível antes de continuar.',
      );
      return;
    }

    final successUrl = _resolvePortalResultUrl(result: 'success');
    final cancelUrl = _resolvePortalResultUrl(result: 'cancel');

    setState(() {
      _startingCheckout = true;
    });

    try {
      final requiresAsaasQuote = billingProvider.trim().toLowerCase() == 'asaas';
      final result = await _billingService.createCheckoutSession(
        tenantId: widget.activeTenant.tenantId,
        billingPlanKey: normalizedPlanKey,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
        addonSeats: addonSeats,
        generateQuoteBeforeCheckout: requiresAsaasQuote,
      );

      final opened = openUrlInCurrentTab(result.checkoutUrl);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: result.checkoutUrl));
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Checkout aberto em nova aba.'
                : 'Link do checkout copiado para a área de transferência.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showBillingActionInfo(context, 'Falha ao abrir checkout: $error');
    } finally {
      if (mounted) {
        setState(() {
          _startingCheckout = false;
        });
      }
    }
  }

  Future<void> _addSeatAddonsToCurrentPlan({
    required String billingPlanKey,
    required int addonSeatsDelta,
  }) async {
    if (_startingCheckout) {
      return;
    }

    final normalizedPlanKey = _normalizeBillingPlanKey(billingPlanKey);
    if (normalizedPlanKey.isEmpty) {
      _showBillingActionInfo(
        context,
        'Selecione um plano valido antes de adicionar seats extras.',
      );
      return;
    }

    if (addonSeatsDelta <= 0 || addonSeatsDelta > _maxSeatAddonDeltaPerOperation) {
      _showBillingActionInfo(
        context,
        'Informe de 1 a $_maxSeatAddonDeltaPerOperation seats extras por operacao.',
      );
      return;
    }

    setState(() {
      _startingCheckout = true;
    });

    try {
      final result = await _billingService.updateSeatAddons(
        tenantId: widget.activeTenant.tenantId,
        billingPlanKey: normalizedPlanKey,
        addonSeatsDelta: addonSeatsDelta,
      );

      if (!mounted) {
        return;
      }

      var invoiceInfo = '';
      if (result.invoiceUrl.trim().isNotEmpty) {
        final openedInvoice = openUrlInCurrentTab(result.invoiceUrl);
        if (!openedInvoice) {
          await Clipboard.setData(ClipboardData(text: result.invoiceUrl));
          if (!mounted) {
            return;
          }
          invoiceInfo = ' Link da fatura copiado para a area de transferencia.';
        } else {
          invoiceInfo = ' Fatura aberta em nova aba.';
        }
      }

      _showBillingActionInfo(
        context,
        '${result.message} Seats extras: ${result.previousAddonSeats} -> ${result.currentAddonSeats}.$invoiceInfo',
      );

      setState(() {
        _setCheckoutAddonSeatsDelta(0);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showBillingActionInfo(
        context,
        'Falha ao adicionar seats extras: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _startingCheckout = false;
        });
      }
    }
  }

  Future<void> _openPortal() async {
    if (_openingPortal) {
      return;
    }

    final returnUrl = _resolvePortalResultUrl(result: 'portal');

    setState(() {
      _openingPortal = true;
    });

    try {
      final result = await _billingService.createPortalSession(
        tenantId: widget.activeTenant.tenantId,
        returnUrl: returnUrl,
      );

      final opened = openUrlInCurrentTab(result.portalUrl);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: result.portalUrl));
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Página de billing aberta em nova aba.'
                : 'Link do portal copiado para a área de transferência.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showBillingActionInfo(context, 'Falha ao abrir página de billing: $error');
    } finally {
      if (mounted) {
        setState(() {
          _openingPortal = false;
        });
      }
    }
  }

  String _resolvePortalResultUrl({required String result}) {
    final current = Uri.base;
    final query = Map<String, String>.from(current.queryParameters)
      ..remove('billingResult')
      ..remove('billingTenant')
      ..addAll(<String, String>{
        'billingResult': result,
        'billingTenant': widget.activeTenant.tenantId,
      });
    return current.replace(queryParameters: query).toString();
  }

  String _resolveSelectedCheckoutPlanKey(
    List<WebPortalAvailableBillingPlan> plans, {
    required String currentPlanKey,
    required String workspaceType,
  }) {
    if (plans.isEmpty) {
      return '';
    }

    final selected = _normalizeBillingPlanKey(_selectedCheckoutPlanKey);
    if (selected.isNotEmpty &&
        plans.any((plan) => plan.billingPlanKey == selected)) {
      return selected;
    }

    final normalizedCurrent = _normalizeBillingPlanKey(currentPlanKey);
    if (normalizedCurrent.isNotEmpty &&
        plans.any((plan) => plan.billingPlanKey == normalizedCurrent)) {
      return normalizedCurrent;
    }

    final fallback = _normalizeBillingPlanKey(
      _defaultPlanForWorkspaceType(workspaceType),
    );
    if (fallback.isNotEmpty &&
        plans.any((plan) => plan.billingPlanKey == fallback)) {
      return fallback;
    }

    return plans.first.billingPlanKey;
  }

  WebPortalAvailableBillingPlan? _findPlanByKey(
    List<WebPortalAvailableBillingPlan> plans,
    String billingPlanKey,
  ) {
    final normalized = _normalizeBillingPlanKey(billingPlanKey);
    if (normalized.isEmpty) {
      return null;
    }
    for (final plan in plans) {
      if (_normalizeBillingPlanKey(plan.billingPlanKey) == normalized) {
        return plan;
      }
    }
    return null;
  }

  String _defaultPlanForWorkspaceType(String workspaceType) {
    final normalized = workspaceType.trim().toLowerCase();
    if (normalized == 'rep_workspace') {
      return 'representacoes_base';
    }
    if (normalized == 'seller_solo_workspace') {
      return 'individual_base';
    }
    if (normalized == 'brand_owner_workspace') {
      return 'enterprise_custom';
    }
    return '';
  }

  String _normalizeBillingPlanKey(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  String _resolveBillingProviderFromTenantData(Map<String, dynamic> tenantData) {
    String normalize(Object? value) {
      final normalized = (value ?? '').toString().trim().toLowerCase();
      if (normalized == 'stripe' || normalized == 'asaas') {
        return normalized;
      }
      return '';
    }

    final explicitContractProvider = normalize(
      tenantData['billingContractProvider'],
    );
    if (explicitContractProvider.isNotEmpty) {
      return explicitContractProvider;
    }

    final hasStripeLink = (tenantData['stripeSubscriptionId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasAsaasLink = (tenantData['asaasSubscriptionId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    if (hasStripeLink && !hasAsaasLink) {
      return 'stripe';
    }
    if (hasAsaasLink && !hasStripeLink) {
      return 'asaas';
    }

    final tenantProvider = normalize(tenantData['billingProvider']);
    if (tenantProvider.isNotEmpty) {
      return tenantProvider;
    }

    final gatewayProvider = normalize(tenantData['billingGateway']);
    if (gatewayProvider.isNotEmpty) {
      return gatewayProvider;
    }

    return 'stripe';
  }

  static String _billingProviderDisplayLabel(String providerKey) {
    final normalized = providerKey.trim().toLowerCase();
    if (normalized == 'asaas') {
      return 'Asaas';
    }
    if (normalized == 'stripe') {
      return 'Stripe';
    }
    return normalized.isEmpty ? 'Não definido' : providerKey;
  }

  Future<void> _runAsaasSelfServiceAction({
    required String action,
    required String confirmTitle,
    required String confirmMessage,
  }) async {
    if (_applyingSelfServiceAction) {
      return;
    }

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (shouldContinue != true) {
      return;
    }

    setState(() {
      _applyingSelfServiceAction = true;
    });

    try {
      final result = await _billingService.manageBillingSelfService(
        tenantId: widget.activeTenant.tenantId,
        action: action,
        reason: 'portal_owner_$action',
      );

      if (!mounted) {
        return;
      }

      _showBillingActionInfo(context, result.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showBillingActionInfo(
        context,
        'Falha ao aplicar ação de autoatendimento: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _applyingSelfServiceAction = false;
        });
      }
    }
  }

  static void _showBillingActionInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BillingPlanCard extends StatelessWidget {
  const _BillingPlanCard({
    required this.plan,
    required this.isSelected,
    required this.isCurrent,
    required this.isUpgrade,
    required this.features,
    required this.onTap,
    this.seatAddonCard,
  });

  final WebPortalAvailableBillingPlan plan;
  final bool isSelected;
  final bool isCurrent;
  final bool isUpgrade;
  final List<String> features;
  final VoidCallback onTap;
  final Widget? seatAddonCard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accentColor = isCurrent
        ? const Color(0xFF0B57D0)
        : isUpgrade
        ? const Color(0xFF0D7A3E)
        : colors.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withValues(alpha: isSelected ? 0.16 : 0.08),
              Colors.white,
            ],
          ),
          border: Border.all(
            color: isSelected
                ? accentColor
                : colors.outlineVariant.withValues(alpha: 0.55),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: isSelected ? 0.14 : 0.05),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mainContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isCurrent)
                      _BillingPlanTag(
                        label: 'Plano ativo',
                        background: const Color(0xFFE8F0FE),
                        foreground: const Color(0xFF0B57D0),
                      ),
                    if (!isCurrent && isUpgrade)
                      _BillingPlanTag(
                        label: 'Upgrade',
                        background: const Color(0xFFE7F6ED),
                        foreground: const Color(0xFF0D7A3E),
                      ),
                    if (isSelected)
                      _BillingPlanTag(
                        label: 'Selecionado',
                        background: colors.primaryContainer,
                        foreground: colors.onPrimaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  plan.planDisplayName,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  plan.planDisplayAmount.trim().isEmpty
                      ? 'Valor sob consulta'
                      : plan.planDisplayAmount,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: accentColor, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _BillingPlanTag(
                      label: 'Seats inclusos: ${plan.includedSeats}',
                      background: const Color(0xFFEFF3FA),
                      foreground: const Color(0xFF24426A),
                    ),
                    if (plan.seatAddonPlanKey.trim().isNotEmpty)
                      _BillingPlanTag(
                        label: 'Permite seats extras',
                        background: const Color(0xFFEAF8EF),
                        foreground: const Color(0xFF155A36),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final item in features.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: accentColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  plan.billingPlanKey,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            );

            if (seatAddonCard == null) {
              return mainContent;
            }

            final placeAtRight = constraints.maxWidth >= 640;
            if (placeAtRight) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: mainContent),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 260,
                    child: seatAddonCard,
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mainContent,
                const SizedBox(height: 12),
                seatAddonCard!,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BillingPlanTag extends StatelessWidget {
  const _BillingPlanTag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
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
  });

  final TenantEntryOption activeTenant;
  final AccountContractLock accountContractLock;

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
        _buildAccountDataCard(context),
        const SizedBox(height: 16),
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
                                    'Informações base do workspace em uso.',
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
        _buildAccountLifecycleActionsCard(context),
      ],
    );
  }

  Widget _buildAccountDataCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    final displayName = (user?.displayName ?? '').trim();
    final uid = (user?.uid ?? '').trim();

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
                        'Dados da Conta',
                        style: textTheme.titleMedium,
                      ),
                    ),
                    Tooltip(
                      message: 'Editar nome de exibição',
                      child: IconButton.outlined(
                        onPressed: () => _editDisplayName(context),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _WorkspaceInfoGrid(
                  items: [
                    _WorkspaceInfoItem(
                      label: 'Conta autenticada',
                      value: email.isEmpty ? uid : email,
                    ),
                    _WorkspaceInfoItem(
                      label: 'Tipo de conta',
                      value: _accountContractLockLabel(accountContractLock),
                    ),
                    _WorkspaceInfoItem(
                      label: 'Nome de exibição',
                      value: displayName.isEmpty ? '-' : displayName,
                    ),
                    _WorkspaceInfoItem(
                      label: 'Provedor de login',
                      value: _authProviderLabel(user),
                    ),
                    _WorkspaceInfoItem(
                      label: 'Papel no workspace',
                      value: _roleLabel(
                        activeTenant.role,
                        activeTenant.workspaceType,
                        activeTenant.tenantName,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountLifecycleActionsCard(BuildContext context) {
    final normalizedRole = activeTenant.role.trim().toLowerCase();
    final canRequestWorkspaceDeletion =
        normalizedRole == 'owner' || normalizedRole == 'platform_admin';

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          color: const Color(0xFFFFF2F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFF2B8B8)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                collapsedIconColor: const Color(0xFF7A2E2E),
                iconColor: const Color(0xFF7A2E2E),
                title: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFF7A2E2E),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Desativar ou Excluir Conta',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF7A2E2E),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _submitLifecycleRequest(
                            context,
                            actionType: 'deactivate_account',
                            title: 'Desativar conta',
                            helperText: 'A conta perde acesso até reativação por administrador.',
                            expectedPhrase: 'DESATIVAR CONTA',
                          ),
                          icon: const Icon(Icons.person_off_outlined),
                          label: const Text('Desativar conta'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _submitLifecycleRequest(
                            context,
                            actionType: 'delete_user_account',
                            title: 'Excluir conta',
                            helperText: 'Se voce for o ultimo owner ativo, sera obrigatorio definir um novo owner neste fluxo.',
                            expectedPhrase: 'EXCLUIR CONTA',
                            enforceReplacementOwnerForLastOwner: true,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Excluir conta'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: !canRequestWorkspaceDeletion
                              ? null
                              : () => _submitLifecycleRequest(
                                  context,
                                  actionType: 'delete_account_and_workspace',
                                  title: 'Excluir conta e workspace',
                                  helperText: 'Ação irreversível após janela de segurança. Use apenas no encerramento definitivo da empresa.',
                                  expectedPhrase:
                                      'DELETAR WORKSPACE ${activeTenant.tenantId}',
                                ),
                          icon: const Icon(Icons.warning_amber_outlined),
                          label: const Text('Excluir conta e workspace'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Excluir conta: promova novo Administrador antes da confirmação.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (!canRequestWorkspaceDeletion) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Somente owner (ou platform_admin) pode solicitar exclusão de workspace.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitLifecycleRequest(
    BuildContext context, {
    required String actionType,
    required String title,
    required String helperText,
    required String expectedPhrase,
    bool enforceReplacementOwnerForLastOwner = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirada. Faça login novamente.')),
      );
      return;
    }

    _OwnerTransferContext? ownerTransferContext;
    var ownerTransferValidationStatus = enforceReplacementOwnerForLastOwner
        ? 'pending_validation'
        : 'not_required';
    if (enforceReplacementOwnerForLastOwner) {
      try {
        ownerTransferContext = await _loadOwnerTransferContext(
          currentUid: user.uid,
        );
        ownerTransferValidationStatus = 'validated';
      } catch (error) {
        ownerTransferValidationStatus = 'validation_unavailable';
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao foi possivel validar ownership agora. Voce pode registrar a solicitacao e o time admin validara na execucao.',
            ),
          ),
        );
      }
      if (!context.mounted) {
        return;
      }
      if ((ownerTransferContext?.requiresReplacementOwner ?? false) &&
          (ownerTransferContext?.candidates.isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao ha membros ativos para assumir ownership. Convide um membro antes de excluir sua conta.',
            ),
          ),
        );
        return;
      }
    }

    final requestData = await _openLifecycleRequestDialog(
      context,
      title: title,
      helperText: helperText,
      expectedPhrase: expectedPhrase,
      requireReplacementOwner:
          ownerTransferContext?.requiresReplacementOwner ?? false,
      replacementOwnerCandidates:
          ownerTransferContext?.candidates ?? const <_OwnerTransferCandidate>[],
    );
    if (!context.mounted || requestData == null) {
      return;
    }

    final reason = (requestData['reason'] ?? '').trim();
    final replacementOwnerUid = (requestData['replacementOwnerUid'] ?? '')
        .trim();
    final replacementOwnerEmail = (requestData['replacementOwnerEmail'] ?? '')
        .trim();
    final replacementOwnerMembershipId =
        (requestData['replacementOwnerMembershipId'] ?? '').trim();

    if ((ownerTransferContext?.requiresReplacementOwner ?? false) &&
        replacementOwnerUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um novo owner para prosseguir.'),
        ),
      );
      return;
    }

    try {
      if (replacementOwnerUid.isNotEmpty) {
        await _applyOwnerTransferForAccountDeletion(
          actorUid: user.uid,
          replacementOwnerUid: replacementOwnerUid,
          replacementOwnerEmail: replacementOwnerEmail,
          replacementOwnerMembershipId: replacementOwnerMembershipId,
          candidates:
              ownerTransferContext?.candidates ??
              const <_OwnerTransferCandidate>[],
        );
      }

      final tenantDoc = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(activeTenant.tenantId)
          .get();
      final tenantData = tenantDoc.data() ?? const <String, dynamic>{};
      final ownerSnapshot = <String, dynamic>{
        'activeOwnerCountAtRequest':
            ownerTransferContext?.activeOwnerCount ?? 0,
        'currentUserIsActiveOwner':
            ownerTransferContext?.currentUserIsActiveOwner ?? false,
        'currentUserIsOnlyActiveOwner':
            ownerTransferContext?.requiresReplacementOwner ?? false,
      };

      await FirebaseFirestore.instance
          .collection('workspace_deletion_requests')
          .add({
            'tenantId': activeTenant.tenantId,
            'tenantName': activeTenant.tenantName,
            'targetUid': user.uid,
            'actionType': actionType,
            'status': 'requested',
            'requestedByUid': user.uid,
            'requestedByEmail': (user.email ?? '').trim(),
            'actorRole': activeTenant.role,
            'reason': reason,
            'replacementOwnerUid': replacementOwnerUid,
            'replacementOwnerEmail': replacementOwnerEmail,
            'replacementOwnerMembershipId': replacementOwnerMembershipId,
            'ownerTransferRequired':
                ownerTransferContext?.requiresReplacementOwner ?? false,
            'ownerTransferPlanned': replacementOwnerUid.isNotEmpty,
            'ownerTransferValidationStatus': ownerTransferValidationStatus,
            'ownerSnapshot': ownerSnapshot,
            'billingSnapshot': {
              'stripeCustomerId': (tenantData['stripeCustomerId'] ?? '')
                  .toString()
                  .trim(),
              'billingPlanKey': (tenantData['billingPlanKey'] ?? '')
                  .toString()
                  .trim(),
              'billingStatus': (tenantData['billingStatus'] ?? '')
                  .toString()
                  .trim(),
              'billingCycle': (tenantData['billingCycle'] ?? '')
                  .toString()
                  .trim(),
            },
            'source': 'portal_account_section',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação registrada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao registrar solicitação: $error')),
      );
    }
  }

  Future<Map<String, String>?> _openLifecycleRequestDialog(
    BuildContext context, {
    required String title,
    required String helperText,
    required String expectedPhrase,
    bool requireReplacementOwner = false,
    List<_OwnerTransferCandidate> replacementOwnerCandidates =
        const <_OwnerTransferCandidate>[],
  }) async {
    final phraseController = TextEditingController();
    final reasonController = TextEditingController();
    var selectedReplacementOwnerUid =
        requireReplacementOwner && replacementOwnerCandidates.isNotEmpty
        ? replacementOwnerCandidates.first.uid
        : '';
    final candidateByUid = {
      for (final candidate in replacementOwnerCandidates)
        candidate.uid: candidate,
    };

    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(helperText),
                    const SizedBox(height: 8),
                    SelectableText(
                      expectedPhrase,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (requireReplacementOwner) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedReplacementOwnerUid.isEmpty
                            ? null
                            : selectedReplacementOwnerUid,
                        decoration: const InputDecoration(
                          labelText: 'Novo owner (obrigatorio)',
                        ),
                        items: replacementOwnerCandidates
                            .map(
                              (candidate) => DropdownMenuItem<String>(
                                value: candidate.uid,
                                child: Text(
                                  candidate.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        selectedItemBuilder: (context) {
                          return replacementOwnerCandidates
                              .map(
                                (candidate) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    candidate.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false);
                        },
                        onChanged: (value) {
                          setDialogState(() {
                            selectedReplacementOwnerUid = (value ?? '').trim();
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: phraseController,
                      decoration: const InputDecoration(
                        labelText: 'Frase de confirmação',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Motivo (obrigatório)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final typedPhrase = phraseController.text.trim();
                    final reason = reasonController.text.trim();
                    if (typedPhrase != expectedPhrase) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Frase de confirmação inválida.'),
                        ),
                      );
                      return;
                    }
                    if (requireReplacementOwner &&
                        selectedReplacementOwnerUid.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione o novo owner.'),
                        ),
                      );
                      return;
                    }
                    if (reason.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Informe o motivo.')),
                      );
                      return;
                    }
                    final selectedCandidate =
                        candidateByUid[selectedReplacementOwnerUid];
                    Navigator.of(dialogContext).pop({
                      'reason': reason,
                      'replacementOwnerUid': selectedReplacementOwnerUid,
                      'replacementOwnerEmail': (selectedCandidate?.email ?? '')
                          .trim(),
                      'replacementOwnerMembershipId':
                          (selectedCandidate?.membershipId ?? '').trim(),
                    });
                  },
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        ),
      );

      return result;
    } finally {
      phraseController.dispose();
      reasonController.dispose();
    }
  }

  Future<_OwnerTransferContext> _loadOwnerTransferContext({
    required String currentUid,
  }) async {
    final tenantId = activeTenant.tenantId.trim();
    if (tenantId.isEmpty) {
      return const _OwnerTransferContext(
        requiresReplacementOwner: false,
        currentUserIsActiveOwner: false,
        activeOwnerCount: 0,
        candidates: <_OwnerTransferCandidate>[],
      );
    }

    final activeMemberships = await _loadActiveMembershipsForOwnerTransfer(
      tenantId: tenantId,
      currentUid: currentUid,
    );

    final activeOwners = activeMemberships
        .where((membership) {
          return membership.role.trim().toLowerCase() == 'owner';
        })
        .toList(growable: false);

    final currentUserIsActiveOwner = activeOwners.any(
      (membership) => membership.uid.trim() == currentUid.trim(),
    );
    final requiresReplacementOwner =
        currentUserIsActiveOwner && activeOwners.length <= 1;

    final candidatesByUid = <String, TenantMembership>{};
    for (final membership in activeMemberships) {
      final uid = membership.uid.trim();
      if (uid.isEmpty || uid == currentUid.trim()) {
        continue;
      }
      final existing = candidatesByUid[uid];
      if (existing == null) {
        candidatesByUid[uid] = membership;
        continue;
      }
      final existingIsOwner = existing.role.trim().toLowerCase() == 'owner';
      final currentIsOwner = membership.role.trim().toLowerCase() == 'owner';
      if (!existingIsOwner && currentIsOwner) {
        candidatesByUid[uid] = membership;
      }
    }

    final candidates = <_OwnerTransferCandidate>[];
    for (final entry in candidatesByUid.entries) {
      final uid = entry.key;
      final membership = entry.value;
      final email = (membership.userEmail ?? '').trim();
      final displayName = _sanitizeOwnerCandidateName(
        (membership.userName ?? '').trim(),
        tenantName: activeTenant.tenantName,
      );
      final role = membership.role.trim().toLowerCase();
      final primaryLabel = email.isNotEmpty
          ? email
          : displayName.isNotEmpty
          ? displayName
          : uid;
      final secondaryLabel =
          displayName.isNotEmpty && displayName != primaryLabel
          ? ' - $displayName'
          : '';
      candidates.add(
        _OwnerTransferCandidate(
          uid: uid,
          membershipId: membership.membershipId,
          email: email,
          displayName: displayName,
          role: role,
          label: '$primaryLabel$secondaryLabel',
        ),
      );
    }

    candidates.sort((a, b) {
      final aOwner = a.role == 'owner';
      final bOwner = b.role == 'owner';
      if (aOwner != bOwner) {
        return aOwner ? -1 : 1;
      }
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return _OwnerTransferContext(
      requiresReplacementOwner: requiresReplacementOwner,
      currentUserIsActiveOwner: currentUserIsActiveOwner,
      activeOwnerCount: activeOwners.length,
      candidates: candidates,
    );
  }

  Future<List<TenantMembership>> _loadActiveMembershipsForOwnerTransfer({
    required String tenantId,
    required String currentUid,
  }) async {
    final membershipsById = <String, TenantMembership>{};

    void addMembership(TenantMembership membership) {
      final membershipId = membership.membershipId.trim();
      if (membershipId.isEmpty) {
        return;
      }
      membershipsById.putIfAbsent(membershipId, () => membership);
    }

    List<TenantMembership> parseMemberships(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
      return docs
          .map((doc) {
            final data = doc.data();
            data.putIfAbsent('membershipId', () => doc.id);
            return TenantMembership.fromMap(data);
          })
          .where((membership) {
            if (!membership.isActive) {
              return false;
            }
            if (membership.isInInactivityPeriod()) {
              return false;
            }
            return membership.uid.trim().isNotEmpty;
          })
          .toList(growable: false);
    }

    try {
      final broadSnapshot = await FirebaseFirestore.instance
          .collection('tenant_memberships')
          .where('tenantId', isEqualTo: tenantId)
          .where('ativo', isEqualTo: true)
          .get();
      for (final membership in parseMemberships(broadSnapshot.docs)) {
        addMembership(membership);
      }
      return membershipsById.values.toList(growable: false);
    } catch (_) {
      // Fallback for legacy docs blocked by rules: load only slices that an
      // owner can deterministically read.
    }

    try {
      final ownerSnapshot = await FirebaseFirestore.instance
          .collection('tenant_memberships')
          .where('tenantId', isEqualTo: tenantId)
          .where('ativo', isEqualTo: true)
          .where('role', isEqualTo: 'owner')
          .get();
      for (final membership in parseMemberships(ownerSnapshot.docs)) {
        addMembership(membership);
      }
    } catch (_) {
      // Best-effort fallback continues below.
    }

    try {
      final managedSnapshot = await FirebaseFirestore.instance
          .collection('tenant_memberships')
          .where('tenantId', isEqualTo: tenantId)
          .where('ativo', isEqualTo: true)
          .where('ownerId', isEqualTo: currentUid.trim())
          .get();
      for (final membership in parseMemberships(managedSnapshot.docs)) {
        addMembership(membership);
      }
    } catch (_) {
      // Keep best-effort result.
    }

    final selfMembershipId = '${tenantId}_${currentUid.trim()}';
    try {
      final selfDoc = await FirebaseFirestore.instance
          .collection('tenant_memberships')
          .doc(selfMembershipId)
          .get();
      if (selfDoc.exists) {
        final data = selfDoc.data() ?? <String, dynamic>{};
        data.putIfAbsent('membershipId', () => selfDoc.id);
        final membership = TenantMembership.fromMap(data);
        if (membership.isActive &&
            !membership.isInInactivityPeriod() &&
            membership.uid.trim().isNotEmpty) {
          addMembership(membership);
        }
      }
    } catch (_) {
      // Keep best-effort result.
    }

    if (membershipsById.isNotEmpty) {
      return membershipsById.values.toList(growable: false);
    }

    throw StateError(
      'Nao foi possivel carregar memberships para validar ownership.',
    );
  }

  String _sanitizeOwnerCandidateName(
    String rawName, {
    required String tenantName,
  }) {
    var normalized = rawName.trim();
    if (normalized.isEmpty) {
      return '';
    }

    final tenant = tenantName.trim();
    if (tenant.isNotEmpty) {
      normalized = normalized.replaceAll(
        RegExp(RegExp.escape(tenant), caseSensitive: false),
        '',
      );
    }

    normalized = normalized.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (normalized.endsWith('-')) {
      normalized = normalized.substring(0, normalized.length - 1).trim();
    }
    return normalized;
  }

  Future<void> _applyOwnerTransferForAccountDeletion({
    required String actorUid,
    required String replacementOwnerUid,
    required String replacementOwnerEmail,
    required String replacementOwnerMembershipId,
    required List<_OwnerTransferCandidate> candidates,
  }) async {
    final normalizedActorUid = actorUid.trim();
    final normalizedReplacementOwnerUid = replacementOwnerUid.trim();
    if (normalizedActorUid.isEmpty || normalizedReplacementOwnerUid.isEmpty) {
      return;
    }

    final replacementCandidate = candidates.firstWhere(
      (candidate) => candidate.uid.trim() == normalizedReplacementOwnerUid,
      orElse: () => _OwnerTransferCandidate(
        uid: normalizedReplacementOwnerUid,
        membershipId: replacementOwnerMembershipId,
        email: replacementOwnerEmail,
        displayName: '',
        role: '',
        label: normalizedReplacementOwnerUid,
      ),
    );

    final normalizedRole = replacementCandidate.role.trim().toLowerCase();
    if (replacementCandidate.membershipId.trim().isNotEmpty &&
        normalizedRole != 'owner') {
      final membershipService = TenantMembershipService(
        FirebaseFirestore.instance,
      );
      await membershipService.changeRoleByActor(
        membershipId: replacementCandidate.membershipId,
        newRole: 'owner',
        actorUid: normalizedActorUid,
      );
    }

    await FirebaseFirestore.instance
        .collection('tenants')
        .doc(activeTenant.tenantId)
        .set({
          'ownerUid': normalizedReplacementOwnerUid,
          'billingOwnerUid': normalizedReplacementOwnerUid,
          'billingOwnerEmail': replacementCandidate.email.trim(),
          'workspaceIntegrityState': 'ok',
          'ownershipLastTransferredAt': DateTime.now()
              .toUtc()
              .toIso8601String(),
          'ownershipLastTransferredByUid': normalizedActorUid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  String _authProviderLabel(User? user) {
    final providers = <String>{};
    for (final provider in user?.providerData ?? const <UserInfo>[]) {
      final providerId = provider.providerId.trim().toLowerCase();
      if (providerId.isNotEmpty) {
        providers.add(providerId);
      }
    }

    if (providers.contains('google.com')) {
      return 'Google';
    }
    if (providers.contains('password')) {
      return 'E-mail e senha';
    }
    if (providers.isEmpty) {
      return 'Não identificado';
    }
    return providers.join(', ');
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirada. Faça login novamente.')),
      );
      return;
    }

    final updatedName = await _openDisplayNameDialog(
      context,
      initialName: (user.displayName ?? '').trim(),
    );
    if (!context.mounted) {
      return;
    }
    if (updatedName == null) {
      return;
    }
    if (updatedName.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe ao menos 3 caracteres.')),
      );
      return;
    }

    try {
      await user.updateDisplayName(updatedName);
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final safeEmail = (refreshedUser?.email ?? user.email ?? '').trim();

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(
        {
          'uid': user.uid,
          if (safeEmail.isNotEmpty) 'email': safeEmail,
          'displayName': updatedName,
          'name': updatedName,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nome de exibição atualizado com sucesso.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar nome de exibição: $error')),
      );
    }
  }

  Future<String?> _openDisplayNameDialog(
    BuildContext context, {
    required String initialName,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(initialName: initialName),
    );

    final normalized = (result ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class _OwnerTransferContext {
  const _OwnerTransferContext({
    required this.requiresReplacementOwner,
    required this.currentUserIsActiveOwner,
    required this.activeOwnerCount,
    required this.candidates,
  });

  final bool requiresReplacementOwner;
  final bool currentUserIsActiveOwner;
  final int activeOwnerCount;
  final List<_OwnerTransferCandidate> candidates;
}

class _OwnerTransferCandidate {
  const _OwnerTransferCandidate({
    required this.uid,
    required this.membershipId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.label,
  });

  final String uid;
  final String membershipId;
  final String email;
  final String displayName;
  final String role;
  final String label;
}

class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
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
      title: const Text('Editar nome de exibição'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Nome de exibição',
          hintText: 'Ex.: João da Silva',
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
