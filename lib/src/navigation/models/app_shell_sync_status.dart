class AppShellSyncStatus {
  const AppShellSyncStatus({
    required this.isRunning,
    required this.phase,
    required this.pendingUploadClientes,
    required this.pendingUploadPreCadastros,
    required this.pendingUploadPedidos,
    required this.pendingUploadDeletes,
    required this.pendingDownloadClientes,
    required this.pendingDownloadProdutos,
    required this.pendingDownloadPedidos,
    required this.pendingDownloadTabelasPreco,
    required this.pendingDownloadTaxRules,
    required this.cloudSnapshotAt,
    required this.cloudSnapshotReachable,
    required this.lastAttemptAt,
    required this.lastAttemptSucceeded,
    required this.lastMessage,
  });

  factory AppShellSyncStatus.initial() {
    return const AppShellSyncStatus(
      isRunning: false,
      phase: 'Aguardando sincronizacao',
      pendingUploadClientes: 0,
      pendingUploadPreCadastros: 0,
      pendingUploadPedidos: 0,
      pendingUploadDeletes: 0,
      pendingDownloadClientes: 0,
      pendingDownloadProdutos: 0,
      pendingDownloadPedidos: 0,
      pendingDownloadTabelasPreco: 0,
      pendingDownloadTaxRules: 0,
      cloudSnapshotAt: null,
      cloudSnapshotReachable: null,
      lastAttemptAt: null,
      lastAttemptSucceeded: null,
      lastMessage: null,
    );
  }

  final bool isRunning;
  final String phase;
  final int pendingUploadClientes;
  final int pendingUploadPreCadastros;
  final int pendingUploadPedidos;
  final int pendingUploadDeletes;
  final int pendingDownloadClientes;
  final int pendingDownloadProdutos;
  final int pendingDownloadPedidos;
  final int pendingDownloadTabelasPreco;
  final int pendingDownloadTaxRules;
  final DateTime? cloudSnapshotAt;
  final bool? cloudSnapshotReachable;
  final DateTime? lastAttemptAt;
  final bool? lastAttemptSucceeded;
  final String? lastMessage;

  int get totalUploadPending =>
      pendingUploadClientes +
      pendingUploadPreCadastros +
      pendingUploadPedidos +
      pendingUploadDeletes;

  int get totalDownloadPending =>
      pendingDownloadClientes +
      pendingDownloadProdutos +
      pendingDownloadPedidos +
      pendingDownloadTabelasPreco +
      pendingDownloadTaxRules;

  int get totalPending => totalUploadPending + totalDownloadPending;

  AppShellSyncStatus copyWith({
    bool? isRunning,
    String? phase,
    int? pendingUploadClientes,
    int? pendingUploadPreCadastros,
    int? pendingUploadPedidos,
    int? pendingUploadDeletes,
    int? pendingDownloadClientes,
    int? pendingDownloadProdutos,
    int? pendingDownloadPedidos,
    int? pendingDownloadTabelasPreco,
    int? pendingDownloadTaxRules,
    DateTime? cloudSnapshotAt,
    bool clearCloudSnapshotAt = false,
    bool? cloudSnapshotReachable,
    bool clearCloudSnapshotReachable = false,
    DateTime? lastAttemptAt,
    bool clearLastAttemptAt = false,
    bool? lastAttemptSucceeded,
    bool clearLastAttemptSucceeded = false,
    String? lastMessage,
    bool clearLastMessage = false,
  }) {
    return AppShellSyncStatus(
      isRunning: isRunning ?? this.isRunning,
      phase: phase ?? this.phase,
      pendingUploadClientes:
          pendingUploadClientes ?? this.pendingUploadClientes,
      pendingUploadPreCadastros:
          pendingUploadPreCadastros ?? this.pendingUploadPreCadastros,
      pendingUploadPedidos: pendingUploadPedidos ?? this.pendingUploadPedidos,
      pendingUploadDeletes: pendingUploadDeletes ?? this.pendingUploadDeletes,
      pendingDownloadClientes:
          pendingDownloadClientes ?? this.pendingDownloadClientes,
      pendingDownloadProdutos:
          pendingDownloadProdutos ?? this.pendingDownloadProdutos,
      pendingDownloadPedidos:
          pendingDownloadPedidos ?? this.pendingDownloadPedidos,
      pendingDownloadTabelasPreco:
          pendingDownloadTabelasPreco ?? this.pendingDownloadTabelasPreco,
      pendingDownloadTaxRules:
          pendingDownloadTaxRules ?? this.pendingDownloadTaxRules,
      cloudSnapshotAt: clearCloudSnapshotAt
          ? null
          : (cloudSnapshotAt ?? this.cloudSnapshotAt),
      cloudSnapshotReachable: clearCloudSnapshotReachable
          ? null
          : (cloudSnapshotReachable ?? this.cloudSnapshotReachable),
      lastAttemptAt: clearLastAttemptAt
          ? null
          : (lastAttemptAt ?? this.lastAttemptAt),
      lastAttemptSucceeded: clearLastAttemptSucceeded
          ? null
          : (lastAttemptSucceeded ?? this.lastAttemptSucceeded),
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}
