import '../contracts/tenant_scoped_entity.dart';
import 'domain_types.dart';

class ClientePreCadastro implements TenantScopedEntity {
  const ClientePreCadastro({
    required this.id,
    required this.tenantId,
    required this.nome,
    required this.documento,
    required this.status,
    required this.requestedByUid,
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
    this.observacoes = '',
    this.origemCadastro = CustomerOrigin.manual,
    this.approvedByUid,
    this.mergedClienteId,
    this.createdAt,
    this.updatedAt,
  });

  factory ClientePreCadastro.fromMap(Map<String, Object?> map) {
    return ClientePreCadastro(
      id: map['id'] as String? ?? '',
      tenantId: map['tenantId'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      documento: map['documento'] as String? ?? '',
      status: PreRegistrationStatus.fromValue(
        map['status'] as String? ?? PreRegistrationStatus.draft.value,
      ),
      requestedByUid: map['requestedByUid'] as String? ?? '',
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
      observacoes: map['observacoes'] as String? ?? '',
      origemCadastro: CustomerOrigin.fromValue(
        map['origemCadastro'] as String? ?? CustomerOrigin.manual.value,
      ),
      approvedByUid: map['approvedByUid'] as String?,
      mergedClienteId: map['mergedClienteId'] as String?,
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
  final PreRegistrationStatus status;
  final String requestedByUid;
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
  final String observacoes;
  final CustomerOrigin origemCadastro;
  final String? approvedByUid;
  final String? mergedClienteId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClientePreCadastro copyWith({
    String? id,
    String? tenantId,
    String? nome,
    String? documento,
    PreRegistrationStatus? status,
    String? requestedByUid,
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
    String? observacoes,
    CustomerOrigin? origemCadastro,
    String? approvedByUid,
    String? mergedClienteId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientePreCadastro(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      nome: nome ?? this.nome,
      documento: documento ?? this.documento,
      status: status ?? this.status,
      requestedByUid: requestedByUid ?? this.requestedByUid,
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
      observacoes: observacoes ?? this.observacoes,
      origemCadastro: origemCadastro ?? this.origemCadastro,
      approvedByUid: approvedByUid ?? this.approvedByUid,
      mergedClienteId: mergedClienteId ?? this.mergedClienteId,
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
      'status': status.value,
      'requestedByUid': requestedByUid,
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
      'observacoes': observacoes,
      'origemCadastro': origemCadastro.value,
      'approvedByUid': approvedByUid,
      'mergedClienteId': mergedClienteId,
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
