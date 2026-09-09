enum TenantOperationMode {
  manual('manual', 'Manual'),
  sankhya('sankhya', 'Sankhya'),
  custom('custom', 'Custom');

  const TenantOperationMode(this.value, this.label);

  final String value;
  final String label;

  static TenantOperationMode fromValue(String value) {
    return TenantOperationMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TenantOperationMode.manual,
    );
  }
}

enum ErpProviderKind {
  none('none', 'Nenhum'),
  sankhya('sankhya', 'Sankhya'),
  custom('custom', 'Custom');

  const ErpProviderKind(this.value, this.label);

  final String value;
  final String label;

  static ErpProviderKind fromValue(String value) {
    return ErpProviderKind.values.firstWhere(
      (item) => item.value == value,
      orElse: () => ErpProviderKind.none,
    );
  }
}

enum CustomerOrigin {
  manual('manual', 'Manual'),
  erp('erp', 'ERP'),
  excel('excel', 'Excel');

  const CustomerOrigin(this.value, this.label);

  final String value;
  final String label;

  static CustomerOrigin fromValue(String value) {
    return CustomerOrigin.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CustomerOrigin.manual,
    );
  }
}

enum CustomerStatus {
  draft('rascunho', 'Rascunho'),
  pendingApproval('pendente_aprovacao', 'Pendente aprovacao'),
  approved('aprovado', 'Aprovado'),
  synchronized('sincronizado', 'Sincronizado'),
  blocked('bloqueado', 'Bloqueado'),
  inactive('inativo', 'Inativo');

  const CustomerStatus(this.value, this.label);

  final String value;
  final String label;

  static CustomerStatus fromValue(String value) {
    return CustomerStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CustomerStatus.draft,
    );
  }
}

enum PreRegistrationStatus {
  draft('rascunho', 'Rascunho'),
  pending('pendente', 'Pendente'),
  approved('aprovado', 'Aprovado'),
  rejected('rejeitado', 'Rejeitado'),
  merged('mesclado', 'Mesclado');

  const PreRegistrationStatus(this.value, this.label);

  final String value;
  final String label;

  static PreRegistrationStatus fromValue(String value) {
    return PreRegistrationStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => PreRegistrationStatus.draft,
    );
  }
}

enum ProductSource {
  manual('manual', 'Manual'),
  erp('erp', 'ERP'),
  excel('excel', 'Excel');

  const ProductSource(this.value, this.label);

  final String value;
  final String label;

  static ProductSource fromValue(String value) {
    return ProductSource.values.firstWhere(
      (item) => item.value == value,
      orElse: () => ProductSource.manual,
    );
  }
}

enum ProductStatus {
  active('ativo', 'Ativo'),
  inactive('inativo', 'Inativo'),
  replaced('substituido', 'Substituido'),
  discontinued('descontinuado', 'Descontinuado');

  const ProductStatus(this.value, this.label);

  final String value;
  final String label;

  static ProductStatus fromValue(String value) {
    return ProductStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => ProductStatus.active,
    );
  }
}

enum OrderOrigin {
  manual('manual', 'Manual'),
  sync('sync', 'Sincronizado');

  const OrderOrigin(this.value, this.label);

  final String value;
  final String label;

  static OrderOrigin fromValue(String value) {
    return OrderOrigin.values.firstWhere(
      (item) => item.value == value,
      orElse: () => OrderOrigin.manual,
    );
  }
}

enum OrderStatus {
  draft('rascunho', 'Rascunho'),
  pendingCustomer('pendente_cliente', 'Pendente cliente'),
  pendingSend('pendente_envio', 'Pendente envio'),
  sent('enviado', 'Enviado'),
  error('erro', 'Erro'),
  canceled('cancelado', 'Cancelado');

  const OrderStatus(this.value, this.label);

  final String value;
  final String label;

  static OrderStatus fromValue(String value) {
    return OrderStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => OrderStatus.draft,
    );
  }
}

enum CustomerReferenceType {
  official('oficial', 'Oficial'),
  preRegistration('pre_cadastro', 'Pre cadastro');

  const CustomerReferenceType(this.value, this.label);

  final String value;
  final String label;

  static CustomerReferenceType fromValue(String value) {
    return CustomerReferenceType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CustomerReferenceType.official,
    );
  }
}

enum CustomerApprovalPolicy {
  ownerOrManager('owner_or_manager', 'Owner ou gerente'),
  ownerOnly('owner_only', 'Somente owner'),
  selfApprovalBootstrap('self_approval_bootstrap', 'Auto aprovacao bootstrap'),
  optInSelfApproval('opt_in_self_approval', 'Auto aprovacao opt in');

  const CustomerApprovalPolicy(this.value, this.label);

  final String value;
  final String label;

  static CustomerApprovalPolicy fromValue(String value) {
    return CustomerApprovalPolicy.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CustomerApprovalPolicy.ownerOrManager,
    );
  }
}

enum TenantEntryPath {
  directTenant('direct_tenant', 'Tenant direto'),
  selector('selector', 'Seletor de tenant'),
  invitation('invitation', 'Convite'),
  requestAccess('request_access', 'Solicitacao de acesso'),
  personalWorkspace('personal_workspace', 'Workspace pessoal');

  const TenantEntryPath(this.value, this.label);

  final String value;
  final String label;

  static TenantEntryPath fromValue(String value) {
    return TenantEntryPath.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TenantEntryPath.requestAccess,
    );
  }
}