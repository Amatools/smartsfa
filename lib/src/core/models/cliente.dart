import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class Cliente implements TenantScopedEntity {
  const Cliente({
    required this.id,
    required this.tenantId,
    required this.nome,
    required this.documento,
    required this.origemCadastro,
    required this.status,
    this.ownerId,
    this.gerenteId,
    this.representanteId,
    this.vendedorId,
    this.tipoPessoa = 'pj',
    this.nomeFantasia = '',
    this.email = '',
    this.emailFinanceiro = '',
    this.canal = 'vendedor',
    this.celular = '',
    this.telefone = '',
    this.cep = '',
    this.logradouro = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.estado = '',
    this.pais = 'Brasil',
    this.inscricaoEstadual = '',
    this.inscricaoMunicipal = '',
    this.salePurpose = SalePurpose.revenda,
    this.taxProfile = CustomerTaxProfile.contribuinte,
    this.taxRegime = defaultTaxRegime,
    this.isZfmSuframa = false,
    this.observacoes = '',
    this.syncVersion = 0,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Cliente.fromMap(Map<String, Object?> map) {
    return Cliente(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      documento: map['documento'] as String? ?? '',
      origemCadastro: CustomerOrigin.fromValue(
        map['origemCadastro'] as String? ?? CustomerOrigin.manual.value,
      ),
      status: CustomerStatus.fromValue(
        map['status'] as String? ?? CustomerStatus.approved.value,
      ),
      ownerId: map['ownerId'] as String?,
      gerenteId: map['gerenteId'] as String?,
      representanteId: map['representanteId'] as String?,
      vendedorId: map['vendedorId'] as String?,
      tipoPessoa: map['tipoPessoa'] as String? ?? 'pj',
      nomeFantasia: map['nomeFantasia'] as String? ?? '',
      email: map['email'] as String? ?? '',
      emailFinanceiro: map['emailFinanceiro'] as String? ?? '',
      canal: map['canal'] as String? ?? 'vendedor',
      celular: map['celular'] as String? ?? '',
      telefone: map['telefone'] as String? ?? '',
      cep: map['cep'] as String? ?? '',
      logradouro: map['logradouro'] as String? ?? '',
      numero: map['numero'] as String? ?? '',
      complemento: map['complemento'] as String? ?? '',
      bairro: map['bairro'] as String? ?? '',
      cidade: map['cidade'] as String? ?? '',
      estado: map['estado'] as String? ?? '',
      pais: map['pais'] as String? ?? 'Brasil',
      inscricaoEstadual: map['inscricaoEstadual'] as String? ?? '',
      inscricaoMunicipal: map['inscricaoMunicipal'] as String? ?? '',
      salePurpose: SalePurpose.fromValue(
        map['salePurpose'] as String? ?? SalePurpose.revenda.value,
      ),
      taxProfile: CustomerTaxProfile.fromValue(
        map['taxProfile'] as String? ??
            map['customerTaxProfile'] as String? ??
            CustomerTaxProfile.contribuinte.value,
      ),
      taxRegime: normalizeTaxRegimeValue(map['taxRegime'] as String? ?? ''),
      isZfmSuframa: _readBool(
        map['isZfmSuframa'] ?? map['zfmSuframa'] ?? map['clienteZfmSuframa'],
      ),
      observacoes: map['observacoes'] as String? ?? '',
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
  final String nome;
  final String documento;
  final CustomerOrigin origemCadastro;
  final CustomerStatus status;
  final String? ownerId;
  final String? gerenteId;
  final String? representanteId;
  final String? vendedorId;
  final String tipoPessoa;
  final String nomeFantasia;
  final String email;
  final String emailFinanceiro;
  final String canal;
  final String celular;
  final String telefone;
  final String cep;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String estado;
  final String pais;
  final String inscricaoEstadual;
  final String inscricaoMunicipal;
  final SalePurpose salePurpose;
  final CustomerTaxProfile taxProfile;
  final String taxRegime;
  final bool isZfmSuframa;
  final String observacoes;
  final int syncVersion;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Cliente copyWith({
    String? id,
    String? tenantId,
    String? nome,
    String? documento,
    CustomerOrigin? origemCadastro,
    CustomerStatus? status,
    String? ownerId,
    String? gerenteId,
    String? representanteId,
    String? vendedorId,
    String? tipoPessoa,
    String? nomeFantasia,
    String? email,
    String? emailFinanceiro,
    String? canal,
    String? celular,
    String? telefone,
    String? cep,
    String? logradouro,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? pais,
    String? inscricaoEstadual,
    String? inscricaoMunicipal,
    SalePurpose? salePurpose,
    CustomerTaxProfile? taxProfile,
    String? taxRegime,
    bool? isZfmSuframa,
    String? observacoes,
    int? syncVersion,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Cliente(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      nome: nome ?? this.nome,
      documento: documento ?? this.documento,
      origemCadastro: origemCadastro ?? this.origemCadastro,
      status: status ?? this.status,
      ownerId: ownerId ?? this.ownerId,
      gerenteId: gerenteId ?? this.gerenteId,
      representanteId: representanteId ?? this.representanteId,
      vendedorId: vendedorId ?? this.vendedorId,
      tipoPessoa: tipoPessoa ?? this.tipoPessoa,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      email: email ?? this.email,
      emailFinanceiro: emailFinanceiro ?? this.emailFinanceiro,
      canal: canal ?? this.canal,
      celular: celular ?? this.celular,
      telefone: telefone ?? this.telefone,
      cep: cep ?? this.cep,
      logradouro: logradouro ?? this.logradouro,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      pais: pais ?? this.pais,
      inscricaoEstadual: inscricaoEstadual ?? this.inscricaoEstadual,
      inscricaoMunicipal: inscricaoMunicipal ?? this.inscricaoMunicipal,
      salePurpose: salePurpose ?? this.salePurpose,
      taxProfile: taxProfile ?? this.taxProfile,
      taxRegime: taxRegime ?? this.taxRegime,
      isZfmSuframa: isZfmSuframa ?? this.isZfmSuframa,
      observacoes: observacoes ?? this.observacoes,
      syncVersion: syncVersion ?? this.syncVersion,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tenantId': tenantId,
      'nome': nome,
      'documento': documento,
      'origemCadastro': origemCadastro.value,
      'status': status.value,
      'ownerId': ownerId,
      'gerenteId': gerenteId,
      'representanteId': representanteId,
      'vendedorId': vendedorId,
      'tipoPessoa': tipoPessoa,
      'nomeFantasia': nomeFantasia,
      'email': email,
      'emailFinanceiro': emailFinanceiro,
      'canal': canal,
      'celular': celular,
      'telefone': telefone,
      'cep': cep,
      'logradouro': logradouro,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'pais': pais,
      'inscricaoEstadual': inscricaoEstadual,
      'inscricaoMunicipal': inscricaoMunicipal,
      'salePurpose': salePurpose.value,
      'taxProfile': taxProfile.value,
      'taxRegime': taxRegime,
      'isZfmSuframa': isZfmSuframa,
      'observacoes': observacoes,
      'syncVersion': syncVersion,
      'deletedAt': deletedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
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

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 's' ||
        normalized == 'sim' ||
        normalized == 'y' ||
        normalized == 'yes';
  }

  return false;
}
