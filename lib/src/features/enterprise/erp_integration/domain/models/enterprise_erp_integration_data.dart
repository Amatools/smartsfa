class EnterpriseErpOrderTopCodes {
  const EnterpriseErpOrderTopCodes({
    required this.revendaSameUf,
    required this.revendaInterstate,
    required this.usoConsumoContribuinteSameUf,
    required this.usoConsumoContribuinteInterstate,
    required this.usoConsumoNaoContribuinteSameUf,
    required this.usoConsumoNaoContribuinteInterstate,
    required this.industrializacaoSameUf,
    required this.industrializacaoInterstate,
    required this.zfmIndustrializacao,
    required this.zfmComercializacaoRevenda,
  });

  static const EnterpriseErpOrderTopCodes empty = EnterpriseErpOrderTopCodes(
    revendaSameUf: '',
    revendaInterstate: '',
    usoConsumoContribuinteSameUf: '',
    usoConsumoContribuinteInterstate: '',
    usoConsumoNaoContribuinteSameUf: '',
    usoConsumoNaoContribuinteInterstate: '',
    industrializacaoSameUf: '',
    industrializacaoInterstate: '',
    zfmIndustrializacao: '',
    zfmComercializacaoRevenda: '',
  );

  final String revendaSameUf;
  final String revendaInterstate;
  final String usoConsumoContribuinteSameUf;
  final String usoConsumoContribuinteInterstate;
  final String usoConsumoNaoContribuinteSameUf;
  final String usoConsumoNaoContribuinteInterstate;
  final String industrializacaoSameUf;
  final String industrializacaoInterstate;
  final String zfmIndustrializacao;
  final String zfmComercializacaoRevenda;

  int get configuredCount {
    return <String>[
      revendaSameUf,
      revendaInterstate,
      usoConsumoContribuinteSameUf,
      usoConsumoContribuinteInterstate,
      usoConsumoNaoContribuinteSameUf,
      usoConsumoNaoContribuinteInterstate,
      industrializacaoSameUf,
      industrializacaoInterstate,
      zfmIndustrializacao,
      zfmComercializacaoRevenda,
    ].where((value) => value.trim().isNotEmpty).length;
  }

  bool get isComplete => configuredCount == 10;
}

class EnterpriseErpIntegrationData {
  const EnterpriseErpIntegrationData({
    required this.provider,
    required this.environment,
    required this.status,
    required this.selectedCompanyId,
    required this.selectedCompanyName,
    required this.apiBaseUrl,
    required this.username,
    required this.password,
    required this.accessToken,
    required this.priceTableCodes,
    required this.orderTopCodes,
  });

  final String provider;
  final String environment;
  final String status;
  final String selectedCompanyId;
  final String selectedCompanyName;
  final String apiBaseUrl;
  final String username;
  final String password;
  final String accessToken;
  final List<String> priceTableCodes;
  final EnterpriseErpOrderTopCodes orderTopCodes;

  bool get hasActiveConnector =>
      selectedCompanyId.isNotEmpty && selectedCompanyName.isNotEmpty;

  bool get credentialsReady =>
      apiBaseUrl.isNotEmpty &&
      (accessToken.isNotEmpty || (username.isNotEmpty && password.isNotEmpty));
}
