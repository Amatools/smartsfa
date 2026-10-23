import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class TaxRule implements TenantScopedEntity {
  const TaxRule({
    required this.id,
    required this.tenantId,
    this.representedCompanyId,
    required this.status,
    required this.ufOrigem,
    required this.ufDestino,
    this.ncm,
    this.cest,
    this.fiscalException,
    this.stCalculationType,
    this.stPriceForCalculation,
    this.stBaseReductionPercent,
    this.stBaseAmount,
    this.aliquotaDestino,
    this.aliquotaCredito,
    this.grupoFiscalId,
    this.taxGroupId,
    this.operationProfileKey,
    this.salePurpose,
    this.cstCsosn,
    this.aliquotaIcms,
    this.mvaIva,
    this.aliquotaSt,
    this.aliquotaDifal,
    this.priority = 0,
    this.validFrom,
    this.validUntil,
    this.syncVersion = 0,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory TaxRule.fromMap(Map<String, Object?> map) {
    return TaxRule(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      representedCompanyId: (map['representedCompanyId'] as String?)?.trim(),
      status: (map['status'] as String? ?? 'active').trim().toLowerCase(),
      ncm: (map['ncm'] as String?)?.trim(),
      cest: (map['cest'] as String?)?.trim(),
      fiscalException: (map['fiscalException'] as String?)?.trim(),
      stCalculationType: (map['stCalculationType'] as String?)
          ?.trim()
          .toLowerCase(),
      stPriceForCalculation: _readDouble(map['stPriceForCalculation']),
      stBaseReductionPercent: _readDouble(map['stBaseReductionPercent']),
      stBaseAmount: _readDouble(map['stBaseAmount']),
      aliquotaDestino:
          _readDouble(map['aliquotaDestino']) ?? _readDouble(map['aliquotaSt']),
      aliquotaCredito:
          _readDouble(map['aliquotaCredito']) ??
          _readDouble(map['aliquotaIcms']),
      grupoFiscalId: (map['grupoFiscalId'] as String?)?.trim(),
      taxGroupId: _readTrimmedStringOrNull(
        map['taxGroupId'] ?? map['tax_group_id'] ?? map['grupoTributarioId'],
      ),
      operationProfileKey: _readTrimmedStringOrNull(
        map['operationProfileKey'] ?? map['operation_profile_key'],
      ),
      ufOrigem: (map['ufOrigem'] as String? ?? '').trim().toUpperCase(),
      ufDestino: (map['ufDestino'] as String? ?? '').trim().toUpperCase(),
      salePurpose: _readSalePurpose(map['salePurpose']),
      cstCsosn: (map['cstCsosn'] as String?)?.trim(),
      aliquotaIcms:
          _readDouble(map['aliquotaIcms']) ??
          _readDouble(map['aliquotaCredito']),
      mvaIva: _readDouble(map['mvaIva']) ?? _readDouble(map['stMvaPercent']),
      aliquotaSt:
          _readDouble(map['aliquotaSt']) ?? _readDouble(map['aliquotaDestino']),
      aliquotaDifal: _readDouble(map['aliquotaDifal']),
      priority: _readInt(map['priority']) ?? 0,
      validFrom: _readDateTime(map['validFrom']),
      validUntil: _readDateTime(map['validUntil']),
      syncVersion: _readInt(map['syncVersion']) ?? 0,
      deletedAt: _readDateTime(map['deletedAt']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  @override
  final String id;
  @override
  final String tenantId;
  final String? representedCompanyId;

  final String status;
  final String? ncm;
  final String? cest;
  final String? fiscalException;
  final String? stCalculationType;
  final double? stPriceForCalculation;
  final double? stBaseReductionPercent;
  final double? stBaseAmount;
  final double? aliquotaDestino;
  final double? aliquotaCredito;
  final String? grupoFiscalId;
  final String? taxGroupId;
  final String? operationProfileKey;
  final SalePurpose? salePurpose;
  final String ufOrigem;
  final String ufDestino;
  final String? cstCsosn;
  final double? aliquotaIcms;
  final double? mvaIva;
  final double? aliquotaSt;
  final double? aliquotaDifal;
  final int priority;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int syncVersion;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'tenantId': tenantId,
      'representedCompanyId': representedCompanyId,
      'status': status,
      'ncm': ncm,
      'cest': cest,
      'fiscalException': fiscalException,
      'stCalculationType': stCalculationType,
      'stPriceForCalculation': stPriceForCalculation,
      'stBaseReductionPercent': stBaseReductionPercent,
      'stBaseAmount': stBaseAmount,
      'aliquotaDestino': aliquotaDestino,
      'aliquotaCredito': aliquotaCredito,
      'grupoFiscalId': grupoFiscalId,
      'taxGroupId': taxGroupId,
      'operationProfileKey': operationProfileKey,
      'salePurpose': salePurpose?.value,
      'ufOrigem': ufOrigem,
      'ufDestino': ufDestino,
      'cstCsosn': cstCsosn,
      // Campos legados mantidos para leitura de clientes ainda nao migrados.
      'aliquotaIcms': aliquotaIcms ?? aliquotaCredito,
      'mvaIva': mvaIva,
      'aliquotaSt': aliquotaSt ?? aliquotaDestino,
      'aliquotaDifal': aliquotaDifal,
      'priority': priority,
      'validFrom': validFrom?.toIso8601String(),
      'validUntil': validUntil?.toIso8601String(),
      'syncVersion': syncVersion,
      'deletedAt': deletedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

SalePurpose? _readSalePurpose(Object? value) {
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return SalePurpose.fromValue(normalized);
  }
  return null;
}

String? _readTrimmedStringOrNull(Object? value) {
  final normalized = (value ?? '').toString().trim();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }
  return null;
}
