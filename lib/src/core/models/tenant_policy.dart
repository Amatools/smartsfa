import 'domain_types.dart';

class TenantPolicy {
  const TenantPolicy({
    required this.productSource,
    required this.allowManualProductCreation,
    required this.allowExcelProductImport,
    required this.allowPreRegistration,
    required this.customerApprovalPolicy,
    required this.allowPersonalWorkspace,
    required this.allowManagerDisableRepresentative,
    required this.allowRepresentativeDisableSeller,
    required this.requireCanonicalCustomerMerge,
    required this.allowMultipleMemberships,
  });

  factory TenantPolicy.defaultSaas() {
    return const TenantPolicy(
      productSource: ProductSource.erp,
      allowManualProductCreation: false,
      allowExcelProductImport: true,
      allowPreRegistration: true,
      customerApprovalPolicy: CustomerApprovalPolicy.ownerOrManager,
      allowPersonalWorkspace: true,
      allowManagerDisableRepresentative: false,
      allowRepresentativeDisableSeller: true,
      requireCanonicalCustomerMerge: true,
      allowMultipleMemberships: true,
    );
  }

  final ProductSource productSource;
  final bool allowManualProductCreation;
  final bool allowExcelProductImport;
  final bool allowPreRegistration;
  final CustomerApprovalPolicy customerApprovalPolicy;
  final bool allowPersonalWorkspace;
  final bool allowManagerDisableRepresentative;
  final bool allowRepresentativeDisableSeller;
  final bool requireCanonicalCustomerMerge;
  final bool allowMultipleMemberships;

  Map<String, Object?> toMap() {
    return {
      'productSource': productSource.value,
      'allowManualProductCreation': allowManualProductCreation,
      'allowExcelProductImport': allowExcelProductImport,
      'allowPreRegistration': allowPreRegistration,
      'customerApprovalPolicy': customerApprovalPolicy.value,
      'allowPersonalWorkspace': allowPersonalWorkspace,
      'allowManagerDisableRepresentative': allowManagerDisableRepresentative,
      'allowRepresentativeDisableSeller': allowRepresentativeDisableSeller,
      'requireCanonicalCustomerMerge': requireCanonicalCustomerMerge,
      'allowMultipleMemberships': allowMultipleMemberships,
    };
  }

  factory TenantPolicy.fromMap(Map<String, Object?> map) {
    return TenantPolicy(
      productSource: ProductSource.fromValue(
        map['productSource'] as String? ?? ProductSource.erp.value,
      ),
      allowManualProductCreation:
          map['allowManualProductCreation'] as bool? ?? false,
      allowExcelProductImport: map['allowExcelProductImport'] as bool? ?? true,
      allowPreRegistration: map['allowPreRegistration'] as bool? ?? true,
      customerApprovalPolicy: CustomerApprovalPolicy.fromValue(
        map['customerApprovalPolicy'] as String? ??
            CustomerApprovalPolicy.ownerOrManager.value,
      ),
      allowPersonalWorkspace: map['allowPersonalWorkspace'] as bool? ?? true,
      allowManagerDisableRepresentative:
          map['allowManagerDisableRepresentative'] as bool? ?? false,
      allowRepresentativeDisableSeller:
          map['allowRepresentativeDisableSeller'] as bool? ?? true,
      requireCanonicalCustomerMerge:
          map['requireCanonicalCustomerMerge'] as bool? ?? true,
      allowMultipleMemberships: map['allowMultipleMemberships'] as bool? ?? true,
    );
  }
}