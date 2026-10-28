import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smartsfa/src/core/models/tenant_entry_decision.dart';

import '../../domain/models/enterprise_erp_connection_test_result.dart';
import '../../domain/models/enterprise_erp_connector_option.dart';
import '../../domain/models/enterprise_erp_integration_data.dart';
import '../../services/enterprise_erp_integration_service.dart';
import '../widgets/erp_connector_card.dart';

class EnterpriseErpIntegrationSection extends StatefulWidget {
  const EnterpriseErpIntegrationSection({
    super.key,
    required this.activeTenant,
  });

  final TenantEntryOption activeTenant;

  @override
  State<EnterpriseErpIntegrationSection> createState() =>
      _EnterpriseErpIntegrationSectionState();
}

class _EnterpriseErpIntegrationSectionState
    extends State<EnterpriseErpIntegrationSection>
    with SingleTickerProviderStateMixin {
  final EnterpriseErpIntegrationService _service =
      EnterpriseErpIntegrationService(FirebaseFirestore.instance);

  late final TabController _tabController;
  final GlobalKey<FormState> _authFormKey = GlobalKey<FormState>();
  final TextEditingController _apiBaseUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _accessTokenController = TextEditingController();
  final TextEditingController _priceTableCodesController =
      TextEditingController();
  final TextEditingController _topRevendaSameUfController =
      TextEditingController();
  final TextEditingController _topRevendaInterstateController =
      TextEditingController();
  final TextEditingController _topUsoConsumoContribuinteSameUfController =
      TextEditingController();
  final TextEditingController
  _topUsoConsumoContribuinteInterstateController =
      TextEditingController();
  final TextEditingController _topUsoConsumoNaoContribuinteSameUfController =
      TextEditingController();
  final TextEditingController
  _topUsoConsumoNaoContribuinteInterstateController =
      TextEditingController();
  final TextEditingController _topIndustrializacaoSameUfController =
      TextEditingController();
  final TextEditingController _topIndustrializacaoInterstateController =
      TextEditingController();
    final TextEditingController _topZfmIndustrializacaoController =
      TextEditingController();
    final TextEditingController _topZfmComercializacaoRevendaController =
      TextEditingController();

  String? _selectedConnectorId;
  String _selectedEnvironment = 'homolog';
  bool _environmentDirty = false;
  bool _savingConnector = false;
  bool _savingCredentials = false;
  bool _savingPriceTableCodes = false;
  bool _savingOrderTopCodes = false;
  bool _testingConnection = false;
  bool _syncingModule = false;
  String? _syncingModuleId;
  bool? _lastKnownHasActiveConnector;
  EnterpriseErpConnectionTestResult? _lastConnectionTest;
  EnterpriseErpModuleSyncResult? _lastModuleSyncResult;
  bool _fetchingOperationTypes = false;
  List<EnterpriseErpOperationType> _operationTypes =
      const <EnterpriseErpOperationType>[];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiBaseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _accessTokenController.dispose();
    _priceTableCodesController.dispose();
    _topRevendaSameUfController.dispose();
    _topRevendaInterstateController.dispose();
    _topUsoConsumoContribuinteSameUfController.dispose();
    _topUsoConsumoContribuinteInterstateController.dispose();
    _topUsoConsumoNaoContribuinteSameUfController.dispose();
    _topUsoConsumoNaoContribuinteInterstateController.dispose();
    _topIndustrializacaoSameUfController.dispose();
    _topIndustrializacaoInterstateController.dispose();
    _topZfmIndustrializacaoController.dispose();
    _topZfmComercializacaoRevendaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        widget.activeTenant.workspaceType == 'brand_owner_workspace' &&
        widget.activeTenant.role.trim().toLowerCase() == 'owner';

    return StreamBuilder<EnterpriseErpIntegrationData>(
      stream: _service.watchIntegration(widget.activeTenant.tenantId),
      builder: (context, snapshot) {
        final data =
            snapshot.data ??
            const EnterpriseErpIntegrationData(
              provider: '',
              environment: '',
              status: '',
              selectedCompanyId: '',
              selectedCompanyName: '',
              apiBaseUrl: '',
              username: '',
              password: '',
              accessToken: '',
              priceTableCodes: <String>[],
              orderTopCodes: EnterpriseErpOrderTopCodes.empty,
            );

        final hasFreshIntegrationData = snapshot.hasData;
        if (hasFreshIntegrationData) {
          _lastKnownHasActiveConnector = data.hasActiveConnector;
        }

        _syncFormFromData(data);

        final erpProvider = data.provider.isEmpty ? 'none' : data.provider;
        final hasActiveConnector = hasFreshIntegrationData
            ? data.hasActiveConnector
            : (_lastKnownHasActiveConnector ?? false);
        final activeConnectorName = data.selectedCompanyName;
        final activeConnectorId = data.selectedCompanyId;

        _selectedConnectorId ??= hasActiveConnector
            ? activeConnectorId
            : EnterpriseErpIntegrationService.supportedConnectors.first.id;

        if (hasFreshIntegrationData) {
          _ensureTabAccessState(hasActiveConnector);
        }

        final activeConnectorOption = _service.resolveConnectorById(
          activeConnectorId,
        );
        final selectedConnectorOption = _service.resolveConnectorById(
          (_selectedConnectorId ?? '').trim(),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ERP e integracao',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Configuracao de ERP exclusiva para web. No mobile/offline o vendedor nao acessa este setup.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Provider atual: $erpProvider')),
                Chip(
                  label: Text(
                    hasActiveConnector
                        ? 'Conector ativo: $activeConnectorName'
                        : 'Conector ativo: nao definido',
                  ),
                ),
                Chip(
                  label: Text(
                    'Ambiente: ${_selectedEnvironment == 'prod' ? 'producao' : 'homologacao'}',
                  ),
                ),
                Chip(
                  label: Text(
                    data.credentialsReady
                        ? 'Credenciais: configuradas'
                        : 'Credenciais: pendentes',
                  ),
                ),
                Chip(
                  label: Text(
                    data.priceTableCodes.isEmpty
                        ? 'Tabelas de preco: nao definidas'
                        : 'Tabelas de preco: ${data.priceTableCodes.join(', ')}',
                  ),
                ),
                Chip(
                  label: Text(
                    data.orderTopCodes.configuredCount == 0
                        ? 'TOPs pedido: nao definidas'
                        : 'TOPs pedido: ${data.orderTopCodes.configuredCount}/10',
                  ),
                ),
              ],
            ),
            if (!canEdit) ...[
              const SizedBox(height: 12),
              _OwnerReadOnlyNotice(
                message: 'Somente owner enterprise pode alterar integracao ERP. Este perfil pode apenas consultar.',
              ),
            ],
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              onTap: (index) => _handleTabTap(
                index: index,
                hasActiveConnector: hasActiveConnector,
              ),
              tabs: const [
                Tab(text: 'Integracoes'),
                Tab(text: 'Autenticacao'),
                Tab(text: 'Sincronizacao'),
                Tab(text: 'Monitoramento'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 740,
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildIntegrationsTab(
                    canEdit: canEdit,
                    hasActiveConnector: hasActiveConnector,
                    erpProvider: erpProvider,
                    activeConnectorId: activeConnectorId,
                    activeConnectorName: activeConnectorName,
                    activeConnectorOption: activeConnectorOption,
                    selectedConnectorOption: selectedConnectorOption,
                  ),
                  hasActiveConnector
                      ? _buildAuthenticationTab(
                          canEdit: canEdit,
                          activeConnectorName: activeConnectorName,
                          activeConnectorOption: activeConnectorOption,
                        )
                      : const _LockedTabContent(
                          title: 'Autenticacao bloqueada',
                          subtitle: 'Ative um conector na aba Integracoes para liberar a configuracao de credenciais.',
                        ),
                  hasActiveConnector
                      ? _buildSyncModulesTab(
                          canEdit: canEdit,
                          data: data,
                        )
                      : const _LockedTabContent(
                          title: 'Sincronizacao bloqueada',
                          subtitle: 'Selecione e ative um conector para abrir esta aba.',
                        ),
                  hasActiveConnector
                      ? _IntegrationContextTabContent(
                          title: 'Monitoramento e reprocessamento',
                          subtitle: 'Contexto da integracao ativa para acompanhar execucoes, falhas e fila de retry.',
                          items: const [
                            'Status da ultima execucao',
                            'Fila de erros e reprocessamento',
                            'Alertas operacionais por conector',
                          ],
                        )
                      : const _LockedTabContent(
                          title: 'Monitoramento bloqueado',
                          subtitle: 'Selecione e ative um conector para abrir esta aba.',
                        ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIntegrationsTab({
    required bool canEdit,
    required bool hasActiveConnector,
    required String erpProvider,
    required String activeConnectorId,
    required String activeConnectorName,
    required EnterpriseErpConnectorOption? activeConnectorOption,
    required EnterpriseErpConnectorOption? selectedConnectorOption,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integracoes Ativas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (hasActiveConnector)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ErpConnectorCard(
                          option:
                              activeConnectorOption ??
                              EnterpriseErpConnectorOption(
                                id: activeConnectorId,
                                provider: erpProvider,
                                name: activeConnectorName,
                                subtitle: 'Conector ativo neste tenant.',
                                logoLabel: 'ERP',
                                enabled: true,
                              ),
                          selected: true,
                          showStatusBadge: true,
                        ),
                      ],
                    )
                  else
                    const _InfoCardSection(
                      title: 'Nenhuma integracao ativa',
                      subtitle: 'Selecione um card em Conectores Disponiveis para iniciar o setup.',
                      items: [
                        'Apenas um ERP por tenant',
                        'Somente owner enterprise pode alterar',
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conectores Disponiveis',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escolha o ERP pelo card. No momento, Sankhya e o unico conector habilitado.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option
                          in EnterpriseErpIntegrationService
                              .supportedConnectors)
                        ErpConnectorCard(
                          option: option,
                          selected: option.id == _selectedConnectorId,
                          onTap: canEdit && option.enabled
                              ? () {
                                  setState(() {
                                    _selectedConnectorId = option.id;
                                  });
                                }
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedConnectorOption != null &&
                      !selectedConnectorOption.enabled)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Este conector ainda nao esta habilitado para ativacao.',
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        canEdit &&
                            !_savingConnector &&
                            selectedConnectorOption != null &&
                            selectedConnectorOption.enabled
                        ? _activateConnector
                        : null,
                    icon: _savingConnector
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_outlined),
                    label: Text(
                      _savingConnector
                          ? 'Ativando conector...'
                          : 'Ativar conector selecionado',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticationTab({
    required bool canEdit,
    required String activeConnectorName,
    required EnterpriseErpConnectorOption? activeConnectorOption,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _authFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuracao de autenticacao',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Conector ativo: $activeConnectorName. Preencha Client Id, Client Secret e Token de integracao (X-Token) para autenticar via OAuth.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('Ambiente', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'homolog',
                      label: Text('Homologacao'),
                    ),
                    ButtonSegment<String>(
                      value: 'prod',
                      label: Text('Producao'),
                    ),
                  ],
                  selected: <String>{_selectedEnvironment},
                  onSelectionChanged: canEdit
                      ? (values) {
                          if (values.isEmpty) {
                            return;
                          }
                          setState(() {
                            _selectedEnvironment = values.first;
                            _environmentDirty = true;
                            _apiBaseUrlController.text =
                                EnterpriseErpIntegrationService.sankhyaBaseUrlForEnvironment(
                                  values.first,
                                );
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiBaseUrlController,
                  readOnly: true,
                  keyboardType: TextInputType.url,
                  validator: _validateBaseUrl,
                  decoration: _authInputDecoration(
                    label: 'URL oficial da API Sankhya',
                    icon: Icons.link,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  enabled: canEdit,
                  decoration: _authInputDecoration(
                    label: 'Client Id',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: canEdit,
                  obscureText: true,
                  decoration: _authInputDecoration(
                    label: 'Client Secret',
                    icon: Icons.lock_outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accessTokenController,
                  enabled: canEdit,
                  obscureText: true,
                  decoration: _authInputDecoration(
                    label: 'Token de integracao (X-Token)',
                    icon: Icons.vpn_key_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.26,
                    ),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Text(
                    'Teste usa o Gateway OAuth oficial do ambiente selecionado + /authenticate.',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: canEdit && !_savingCredentials
                          ? () {
                              if (!_validateAuthenticationForm()) {
                                return;
                              }
                              _saveCredentials(
                                provider:
                                    activeConnectorOption?.provider ??
                                    'sankhya',
                              );
                            }
                          : null,
                      icon: _savingCredentials
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _savingCredentials
                            ? 'Salvando credenciais...'
                            : 'Salvar credenciais',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canEdit && !_testingConnection
                          ? _runConnectionTest
                          : null,
                      icon: _testingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_outlined),
                      label: Text(
                        _testingConnection
                            ? 'Testando conexao...'
                            : 'Testar conexao',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildConnectionStatusPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _authInputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hintText,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      prefixIcon: Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: border(colorScheme.outlineVariant.withValues(alpha: 0.32)),
      focusedBorder: border(
        colorScheme.primary.withValues(alpha: 0.48),
        width: 1.25,
      ),
      errorBorder: border(colorScheme.error.withValues(alpha: 0.72)),
      focusedErrorBorder: border(colorScheme.error, width: 1.25),
    );
  }

  String? _validateBaseUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return 'Informe a URL base da API.';
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.hasScheme && uri.host.isNotEmpty)) {
      return 'Informe uma URL valida com protocolo (https://...).';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Use apenas http ou https.';
    }
    return null;
  }

  String? _validatePriceTableCodesCsv(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }

    final tokens = raw.split(RegExp(r'[,;\s\n]+'));
    for (final token in tokens) {
      final clean = token.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (!RegExp(r'^\d+$').hasMatch(clean)) {
        return 'Use apenas codigos numericos separados por virgula.';
      }
    }
    return null;
  }

  List<String> _parsePriceTableCodesCsv(String raw) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final token in raw.split(RegExp(r'[,;\s\n]+'))) {
      final clean = token.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (!RegExp(r'^\d+$').hasMatch(clean)) {
        continue;
      }
      if (!seen.add(clean)) {
        continue;
      }
      normalized.add(clean);
    }
    return normalized;
  }

  String? _validateTopCode(String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      return 'Todos os 6 campos de TOP sao obrigatorios.';
    }
    if (!RegExp(r'^\d+$').hasMatch(clean)) {
      return 'TOP deve conter somente numeros.';
    }
    return null;
  }

  bool _validateAuthenticationForm() {
    final formState = _authFormKey.currentState;
    if (formState != null && !formState.validate()) {
      return false;
    }

    final token = _accessTokenController.text.trim();
    final clientId = _usernameController.text.trim();
    final clientSecret = _passwordController.text.trim();
    final hasToken = token.isNotEmpty;
    final hasClient = clientId.isNotEmpty;
    final hasSecret = clientSecret.isNotEmpty;

    if (!hasToken || !hasClient || !hasSecret) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe Client Id, Client Secret e Token de integracao (X-Token).',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _runConnectionTest() async {
    if (!_validateAuthenticationForm()) {
      return;
    }

    setState(() {
      _testingConnection = true;
      _lastConnectionTest = null;
    });

    final result = await _service.testConnection(
      apiBaseUrl: _apiBaseUrlController.text,
      environment: _selectedEnvironment,
      username: _usernameController.text,
      password: _passwordController.text,
      accessToken: _accessTokenController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _testingConnection = false;
      _lastConnectionTest = result;
    });
  }

  Future<void> _fetchOperationTypes() async {
    if (!_validateAuthenticationForm()) {
      return;
    }

    setState(() {
      _fetchingOperationTypes = true;
    });

    try {
      final items = await _service.fetchOperationTypes(
        environment: _selectedEnvironment,
        username: _usernameController.text,
        password: _passwordController.text,
        accessToken: _accessTokenController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _operationTypes = items;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} tipos de operacao (TOPs) encontrados no Sankhya.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao buscar TOPs do Sankhya: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _fetchingOperationTypes = false;
        });
      }
    }
  }

  Widget _buildConnectionStatusPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _lastConnectionTest;

    if (result == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.26),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: const Text(
          'Status de teste: ainda nao executado. Clique em "Testar conexao" para validar HTTP 200 do endpoint informado.',
        ),
      );
    }

    final isSuccess = result.success;
    final statusColor = isSuccess
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;
    final onStatusColor = isSuccess
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: statusColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                color: onStatusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: TextStyle(
                    color: onStatusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'HTTP: ${result.statusCode?.toString() ?? 'sem codigo'} | Metodo: ${result.requestMethod} | Tempo: ${result.latencyMs} ms',
            style: TextStyle(color: onStatusColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Bearer recebido: ${result.bearerReceived ? 'sim' : 'nao'}${result.tokenType == null || result.tokenType!.isEmpty ? '' : ' | Tipo: ${result.tokenType}'}${result.expiresInSeconds == null ? '' : ' | Expira em: ${result.expiresInSeconds}s'}',
            style: TextStyle(color: onStatusColor),
          ),
          if (result.bearerPreview != null && result.bearerPreview!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Preview do bearer: ${result.bearerPreview}',
                style: TextStyle(color: onStatusColor),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'URL testada: ${result.requestUrl}',
            style: TextStyle(color: onStatusColor),
          ),
          const SizedBox(height: 6),
          Text(
            'Observacao: este teste valida a autenticacao OAuth (/authenticate) e retorno de access_token.',
            style: TextStyle(color: onStatusColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncModulesTab({
    required bool canEdit,
    required EnterpriseErpIntegrationData data,
  }) {
    final result = _lastModuleSyncResult;

    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sincronizacao por modulo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Para o piloto, a sincronizacao ERP -> SaaS roda por secao. Regra temporaria ativa para produtos: limite ${EnterpriseErpIntegrationService.temporaryModuleImportLimit} e bloqueio de codigo 0.',
              ),
              const SizedBox(height: 12),
              for (final module in _orderedSyncModules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildSyncModuleCard(
                    canEdit: canEdit,
                    data: data,
                    module: module,
                  ),
                ),
              const SizedBox(height: 6),
              _buildOrderTopCodesCard(canEdit: canEdit, data: data),
              if (result != null) ...[
                const SizedBox(height: 4),
                _buildModuleSyncStatusPanel(result),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncModuleCard({
    required bool canEdit,
    required EnterpriseErpIntegrationData data,
    required EnterpriseErpSyncModuleOption module,
  }) {
    final isRunning = _syncingModule && _syncingModuleId == module.id;
    final hasSavedPriceTableCodes = data.priceTableCodes.isNotEmpty;
    final isPriceTablesModule = module.id == 'tabelas_preco';
    final actionEnabled =
      canEdit &&
      module.enabled &&
      !_syncingModule &&
      data.credentialsReady &&
      (!isPriceTablesModule || hasSavedPriceTableCodes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  module.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Chip(
                label: Text(module.enabled ? 'Disponivel' : 'Pendente'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(module.description),
          const SizedBox(height: 6),
          Text('Endpoint alvo: ${module.endpointPath}'),
          const SizedBox(height: 10),
          if (isPriceTablesModule) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceTableCodesController,
              enabled: canEdit && !_savingPriceTableCodes,
              validator: _validatePriceTableCodesCsv,
              decoration: _authInputDecoration(
                label: 'Codigos de tabela para sincronizar (CSV)',
                icon: Icons.format_list_numbered,
                hintText: 'Ex.: 0,1,2,3,4,5',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: canEdit && !_savingPriceTableCodes
                      ? _savePriceTableCodes
                      : null,
                  icon: _savingPriceTableCodes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _savingPriceTableCodes
                        ? 'Salvando codigos...'
                        : 'Salvar codigos de tabela',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Dica: no Sankhya normalmente as tabelas iniciam em 0 e seguem em sequencia.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: actionEnabled ? () => _runModuleSync(module: module) : null,
              icon: isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                isRunning
                    ? 'Sincronizando...'
                    : 'Sincronizar ${module.label}',
              ),
            ),
            if (!hasSavedPriceTableCodes)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Salve ao menos um codigo de tabela para liberar a sincronizacao deste modulo.',
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: actionEnabled
                  ? () => _runModuleSync(module: module)
                  : null,
              icon: isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                isRunning
                    ? 'Sincronizando...'
                    : 'Sincronizar ${module.label}',
              ),
            ),
          ],
          if (!data.credentialsReady)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Configure e salve credenciais na aba Autenticacao para liberar a execucao.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderTopCodesCard({
    required bool canEdit,
    required EnterpriseErpIntegrationData data,
  }) {
    final completionLabel = data.orderTopCodes.isComplete
        ? 'Configuracao completa (10/10)'
        : 'Configuracao pendente (${data.orderTopCodes.configuredCount}/10)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TOPs para criacao de pedido no Sankhya',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Chip(label: Text(completionLabel)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Defina as 10 TOPs por finalidade, perfil fiscal e tipo da operacao (mesma UF x interestadual), incluindo cenarios ZFM/SUFRAMA.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _fetchingOperationTypes ? null : _fetchOperationTypes,
                icon: _fetchingOperationTypes
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_outlined),
                label: Text(
                  _fetchingOperationTypes
                      ? 'Buscando TOPs...'
                      : 'Buscar TOPs do Sankhya',
                ),
              ),
              if (_operationTypes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Chip(label: Text('${_operationTypes.length} TOPs carregadas')),
              ],
            ],
          ),
          if (_operationTypes.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'Clique na lupa de cada campo para escolher a TOP pela descricao, em vez de digitar o codigo de cabeca.',
            ),
          ],
          const SizedBox(height: 12),
          _buildTopCodeField(
            controller: _topRevendaSameUfController,
            label: 'Revenda - operacao estadual (mesma UF)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topRevendaInterstateController,
            label: 'Revenda - operacao interestadual (UF diferente)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topUsoConsumoContribuinteSameUfController,
            label:
                'Uso/consumo - contribuinte - operacao estadual (mesma UF)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topUsoConsumoContribuinteInterstateController,
            label:
                'Uso/consumo - contribuinte - operacao interestadual (UF diferente)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topUsoConsumoNaoContribuinteSameUfController,
            label:
                'Uso/consumo - nao contribuinte - operacao estadual (mesma UF)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topUsoConsumoNaoContribuinteInterstateController,
            label:
                'Uso/consumo - nao contribuinte - operacao interestadual (UF diferente)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topIndustrializacaoSameUfController,
            label: 'Industrializacao - operacao estadual (mesma UF)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topIndustrializacaoInterstateController,
            label: 'Industrializacao - operacao interestadual (UF diferente)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topZfmIndustrializacaoController,
            label: 'ZFM/SUFRAMA - Industrializacao (CFOP 6.109)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 8),
          _buildTopCodeField(
            controller: _topZfmComercializacaoRevendaController,
            label: 'ZFM/SUFRAMA - Comercializacao/Revenda (CFOP 6.110)',
            canEdit: canEdit,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: canEdit && !_savingOrderTopCodes
                ? _saveOrderTopCodes
                : null,
            icon: _savingOrderTopCodes
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _savingOrderTopCodes
                  ? 'Salvando TOPs...'
                  : 'Salvar TOPs de pedido',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCodeField({
    required TextEditingController controller,
    required String label,
    required bool canEdit,
  }) {
    final fieldEnabled = canEdit && !_savingOrderTopCodes;
    return TextFormField(
      controller: controller,
      enabled: fieldEnabled,
      keyboardType: TextInputType.number,
      decoration: _authInputDecoration(
        label: label,
        icon: Icons.tag_outlined,
        hintText: 'Ex.: 1200',
      ).copyWith(
        suffixIcon: _operationTypes.isEmpty
            ? null
            : IconButton(
                tooltip: 'Escolher TOP pela descricao',
                icon: const Icon(Icons.search),
                onPressed: fieldEnabled
                    ? () => _pickOperationType(controller)
                    : null,
              ),
      ),
    );
  }

  Future<void> _pickOperationType(TextEditingController controller) async {
    final selected = await showDialog<EnterpriseErpOperationType>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = query.isEmpty
                ? _operationTypes
                : _operationTypes
                      .where(
                        (item) =>
                            item.code.toLowerCase().contains(query) ||
                            item.description.toLowerCase().contains(query),
                      )
                      .toList(growable: false);
            return AlertDialog(
              title: const Text('Selecionar TOP do Sankhya'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por codigo ou descricao',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          query = value.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Nenhuma TOP encontrada.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  title: Text(item.description.isEmpty
                                      ? item.code
                                      : item.description),
                                  subtitle: Text('Codigo: ${item.code}'),
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(item),
                                );
                              },
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
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        controller.text = selected.code;
      });
    }
  }

  Widget _buildModuleSyncStatusPanel(EnterpriseErpModuleSyncResult result) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = result.success
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;
    final foreground = result.success
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: background,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.message,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Modulo: ${result.moduleId} | HTTP: ${result.statusCode?.toString() ?? 'sem codigo'}',
            style: TextStyle(color: foreground),
          ),
          Text(
            'Fonte: ${result.sourceCount} | Importados: ${result.importedCount} | Filtrados codigo 0: ${result.filteredOutZeroCodeCount} | Ignorados sem cadastro: ${result.skippedNotFoundCount}',
            style: TextStyle(color: foreground),
          ),
          const SizedBox(height: 4),
          Text('Proxy: ${result.requestUrl}', style: TextStyle(color: foreground)),
        ],
      ),
    );
  }

  void _syncFormFromData(EnterpriseErpIntegrationData data) {
    final savedEnvironment = data.environment;
    if (savedEnvironment == 'homolog' || savedEnvironment == 'prod') {
      if (!_environmentDirty) {
        _selectedEnvironment = savedEnvironment;
      } else if (_selectedEnvironment == savedEnvironment) {
        _environmentDirty = false;
      }
    }

    final officialBaseUrl =
        EnterpriseErpIntegrationService.sankhyaBaseUrlForEnvironment(
          _selectedEnvironment,
        );
    if (_apiBaseUrlController.text != officialBaseUrl) {
      _apiBaseUrlController.text = officialBaseUrl;
    }
    if (_usernameController.text.isEmpty && data.username.isNotEmpty) {
      _usernameController.text = data.username;
    }
    if (_passwordController.text.isEmpty && data.password.isNotEmpty) {
      _passwordController.text = data.password;
    }
    if (_accessTokenController.text.isEmpty && data.accessToken.isNotEmpty) {
      _accessTokenController.text = data.accessToken;
    }
    if (_priceTableCodesController.text.isEmpty &&
        data.priceTableCodes.isNotEmpty) {
      _priceTableCodesController.text = data.priceTableCodes.join(',');
    }

    if (_topRevendaSameUfController.text.isEmpty) {
      _topRevendaSameUfController.text = data.orderTopCodes.revendaSameUf;
    }
    if (_topRevendaInterstateController.text.isEmpty) {
      _topRevendaInterstateController.text =
          data.orderTopCodes.revendaInterstate;
    }
    if (_topUsoConsumoContribuinteSameUfController.text.isEmpty) {
      _topUsoConsumoContribuinteSameUfController.text =
          data.orderTopCodes.usoConsumoContribuinteSameUf;
    }
    if (_topUsoConsumoContribuinteInterstateController.text.isEmpty) {
      _topUsoConsumoContribuinteInterstateController.text =
          data.orderTopCodes.usoConsumoContribuinteInterstate;
    }
    if (_topUsoConsumoNaoContribuinteSameUfController.text.isEmpty) {
      _topUsoConsumoNaoContribuinteSameUfController.text =
          data.orderTopCodes.usoConsumoNaoContribuinteSameUf;
    }
    if (_topUsoConsumoNaoContribuinteInterstateController.text.isEmpty) {
      _topUsoConsumoNaoContribuinteInterstateController.text =
          data.orderTopCodes.usoConsumoNaoContribuinteInterstate;
    }
    if (_topIndustrializacaoSameUfController.text.isEmpty) {
      _topIndustrializacaoSameUfController.text =
          data.orderTopCodes.industrializacaoSameUf;
    }
    if (_topIndustrializacaoInterstateController.text.isEmpty) {
      _topIndustrializacaoInterstateController.text =
          data.orderTopCodes.industrializacaoInterstate;
    }
    if (_topZfmIndustrializacaoController.text.isEmpty) {
      _topZfmIndustrializacaoController.text =
          data.orderTopCodes.zfmIndustrializacao;
    }
    if (_topZfmComercializacaoRevendaController.text.isEmpty) {
      _topZfmComercializacaoRevendaController.text =
          data.orderTopCodes.zfmComercializacaoRevenda;
    }
  }

  List<EnterpriseErpSyncModuleOption> get _orderedSyncModules {
    final all = EnterpriseErpIntegrationService.supportedSyncModules;
    final byId = <String, EnterpriseErpSyncModuleOption>{
      for (final item in all) item.id: item,
    };
    final ordered = <EnterpriseErpSyncModuleOption>[];
    for (final id in const <String>[
      'produtos',
      'tabelas_preco',
      'tax_rules',
      'parceiros',
    ]) {
      final module = byId[id];
      if (module != null) {
        ordered.add(module);
      }
    }
    for (final module in all) {
      if (!ordered.contains(module)) {
        ordered.add(module);
      }
    }
    return ordered;
  }

  void _ensureTabAccessState(bool hasActiveConnector) {
    if (hasActiveConnector || _tabController.index == 0) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index == 0) {
        return;
      }
      _tabController.animateTo(0);
    });
  }

  void _handleTabTap({required int index, required bool hasActiveConnector}) {
    if (hasActiveConnector || index == 0) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ative uma integracao na aba Integracoes antes de acessar as abas de contexto.',
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index == 0) {
        return;
      }
      _tabController.animateTo(0);
    });
  }

  Future<void> _activateConnector() async {
    final selectedId = (_selectedConnectorId ?? '').trim();
    if (selectedId.isEmpty) {
      return;
    }

    final selected = _service.resolveConnectorById(selectedId);
    if (selected == null || !selected.enabled) {
      return;
    }

    setState(() {
      _savingConnector = true;
    });

    try {
      await _service.activateConnector(
        tenantId: widget.activeTenant.tenantId,
        connector: selected,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conector ERP ativado.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao ativar conector ERP: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingConnector = false;
        });
      }
    }
  }

  Future<void> _saveCredentials({required String provider}) async {
    setState(() {
      _savingCredentials = true;
    });

    try {
      await _service.saveCredentials(
        tenantId: widget.activeTenant.tenantId,
        provider: provider,
        environment: _selectedEnvironment,
        apiBaseUrl: _apiBaseUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        accessToken: _accessTokenController.text,
        priceTableCodes: _parsePriceTableCodesCsv(
          _priceTableCodesController.text,
        ),
      );
      if (!mounted) {
        return;
      }
      _environmentDirty = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciais ERP salvas com sucesso.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar credenciais ERP: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingCredentials = false;
        });
      }
    }
  }

  Future<void> _savePriceTableCodes() async {
    final validationError = _validatePriceTableCodesCsv(
      _priceTableCodesController.text,
    );
    if (validationError != null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    setState(() {
      _savingPriceTableCodes = true;
    });

    try {
      await _service.savePriceTableCodes(
        tenantId: widget.activeTenant.tenantId,
        priceTableCodes: _parsePriceTableCodesCsv(
          _priceTableCodesController.text,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Codigos de tabela salvos com sucesso.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar codigos de tabela: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingPriceTableCodes = false;
        });
      }
    }
  }

  Future<void> _saveOrderTopCodes() async {
    final validationErrors = <String?>[
      _validateTopCode(_topRevendaSameUfController.text),
      _validateTopCode(_topRevendaInterstateController.text),
      _validateTopCode(_topUsoConsumoContribuinteSameUfController.text),
      _validateTopCode(_topUsoConsumoContribuinteInterstateController.text),
      _validateTopCode(_topUsoConsumoNaoContribuinteSameUfController.text),
      _validateTopCode(_topUsoConsumoNaoContribuinteInterstateController.text),
      _validateTopCode(_topIndustrializacaoSameUfController.text),
      _validateTopCode(_topIndustrializacaoInterstateController.text),
      _validateTopCode(_topZfmIndustrializacaoController.text),
      _validateTopCode(_topZfmComercializacaoRevendaController.text),
    ];
    final firstError = validationErrors.firstWhere(
      (error) => error != null,
      orElse: () => null,
    );
    if (firstError != null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(firstError)));
      return;
    }

    setState(() {
      _savingOrderTopCodes = true;
    });

    try {
      await _service.saveOrderTopCodes(
        tenantId: widget.activeTenant.tenantId,
        orderTopCodes: EnterpriseErpOrderTopCodes(
          revendaSameUf: _topRevendaSameUfController.text.trim(),
          revendaInterstate: _topRevendaInterstateController.text.trim(),
          usoConsumoContribuinteSameUf:
            _topUsoConsumoContribuinteSameUfController.text.trim(),
          usoConsumoContribuinteInterstate:
            _topUsoConsumoContribuinteInterstateController.text.trim(),
          usoConsumoNaoContribuinteSameUf:
            _topUsoConsumoNaoContribuinteSameUfController.text.trim(),
          usoConsumoNaoContribuinteInterstate:
            _topUsoConsumoNaoContribuinteInterstateController.text.trim(),
          industrializacaoSameUf:
              _topIndustrializacaoSameUfController.text.trim(),
          industrializacaoInterstate:
              _topIndustrializacaoInterstateController.text.trim(),
            zfmIndustrializacao:
              _topZfmIndustrializacaoController.text.trim(),
            zfmComercializacaoRevenda:
              _topZfmComercializacaoRevendaController.text.trim(),
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TOPs de pedido salvas com sucesso.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar TOPs de pedido: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingOrderTopCodes = false;
        });
      }
    }
  }

  Future<void> _runModuleSync({
    required EnterpriseErpSyncModuleOption module,
  }) async {
    if (_syncingModule) {
      return;
    }

    if (!_validateAuthenticationForm()) {
      return;
    }

    setState(() {
      _syncingModule = true;
      _syncingModuleId = module.id;
      _lastModuleSyncResult = null;
    });

    final result = await _service.syncCatalogModule(
      tenantId: widget.activeTenant.tenantId,
      module: module,
      environment: _selectedEnvironment,
      username: _usernameController.text,
      password: _passwordController.text,
      accessToken: _accessTokenController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _syncingModule = false;
      _syncingModuleId = null;
      _lastModuleSyncResult = result;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }
}

class _OwnerReadOnlyNotice extends StatelessWidget {
  const _OwnerReadOnlyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _InfoCardSection extends StatelessWidget {
  const _InfoCardSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(subtitle),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.check_circle_outline, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LockedTabContent extends StatelessWidget {
  const _LockedTabContent({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _IntegrationContextTabContent(
      title: title,
      subtitle: subtitle,
      items: const [
        'Selecione um conector disponivel',
        'Ative o conector selecionado',
        'Volte para liberar esta aba',
      ],
      locked: true,
    );
  }
}

class _IntegrationContextTabContent extends StatelessWidget {
  const _IntegrationContextTabContent({
    required this.title,
    required this.subtitle,
    required this.items,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final List<String> items;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                  if (locked)
                    const Chip(
                      avatar: Icon(Icons.lock_outline, size: 16),
                      label: Text('Bloqueada'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 12),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.circle, size: 8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
