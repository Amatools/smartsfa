/// Calendário de fases da Reforma Tributária (EC 132/2023, LC 214/2025).
///
/// Este arquivo NÃO define alíquotas de IBS/CBS/Imposto Seletivo — apenas o
/// calendário de fases, que é público e estável. Os percentuais de
/// substituição e os valores de alíquota de referência devem ser carregados
/// de fonte oficial (Resoluções do Senado, ano a ano) somente quando a
/// necessidade de cálculo real existir.
///
/// Ver docs/tributacao_motor_especificacao_tecnica.md §5 e §7 para a decisão
/// de design por trás deste comportamento deliberadamente conservador.
enum TaxReformPhase {
  /// Antes de 2026: regime atual (ICMS/ISS/PIS/COFINS), sem obrigação da Reforma.
  naoIniciada,

  /// 2026: ano de teste de CBS/IBS. Recolhimento simbólico/compensável, sem
  /// impacto real de caixa ou de preço ao cliente.
  testeCbsIbs,

  /// 2027-2032: substituição gradual de ICMS/ISS por IBS e de PIS/COFINS por
  /// CBS, conforme calendário da LC 214/2025.
  transicao,

  /// A partir de 2033: ICMS, ISS, PIS e COFINS extintos; IBS/CBS/Imposto
  /// Seletivo plenamente vigentes.
  implantacaoPlena,
}

class TaxReformCalendar {
  const TaxReformCalendar._();

  static TaxReformPhase phaseForYear(int year) {
    if (year < 2026) {
      return TaxReformPhase.naoIniciada;
    }
    if (year == 2026) {
      return TaxReformPhase.testeCbsIbs;
    }
    if (year < 2033) {
      return TaxReformPhase.transicao;
    }
    return TaxReformPhase.implantacaoPlena;
  }

  static TaxReformPhase currentPhase({DateTime? now}) {
    return phaseForYear((now ?? DateTime.now()).year);
  }

  static String phaseLabel(TaxReformPhase phase) {
    switch (phase) {
      case TaxReformPhase.naoIniciada:
        return 'Reforma ainda não iniciada';
      case TaxReformPhase.testeCbsIbs:
        return 'Ano de teste do CBS/IBS (2026)';
      case TaxReformPhase.transicao:
        return 'Transição ICMS/ISS → IBS/CBS (2027-2032)';
      case TaxReformPhase.implantacaoPlena:
        return 'Implantação plena do IBS/CBS/IS (2033+)';
    }
  }

  /// Indica se, na fase atual, já faz sentido capturar os campos da Reforma
  /// (classificação tributária, alíquotas de referência, redução) para que o
  /// cadastro fiscal esteja pronto quando o cálculo entrar em vigor.
  static bool shouldCaptureReformFields({DateTime? now}) {
    return currentPhase(now: now) != TaxReformPhase.naoIniciada;
  }

  /// Indica se a Reforma já deve alterar o preço final ao cliente.
  ///
  /// Por decisão de design (ver docs/tributacao_motor_especificacao_tecnica.md
  /// §5 e §7), isto permanece `false` mesmo durante a transição: a
  /// substituição de tributos é desenhada para ser neutra em termos de preço
  /// até que exista necessidade real de negócio de alterar o cálculo. Quando
  /// essa necessidade existir (percentuais oficiais publicados + decisão de
  /// negócio), este método deve ser atualizado para refletir a regra real.
  static bool impactsFinalPrice({DateTime? now}) {
    return false;
  }

  // ---------------------------------------------------------------------
  // Percentuais de transição fixados em lei (EC 132/2023 + LC 214/2025).
  //
  // Diferente das alíquotas de referência de IBS/CBS/Imposto Seletivo (que
  // ainda dependem de Resolução do Senado e NÃO são fixadas aqui), o
  // CRONOGRAMA de substituição ano a ano já é definitivo em lei e não deve
  // mudar. Por isso já é seguro implementar esses percentuais agora, mesmo
  // sem a alíquota plena oficial.
  // ---------------------------------------------------------------------

  /// Alíquota de teste da CBS em 2026 (%). Apenas destacada em documento
  /// fiscal nesse ano; compensável com PIS/COFINS devido, sem impacto real
  /// de caixa ou de preço ao cliente.
  static const double testPhaseCbsPercent = 0.9;

  /// Alíquota de teste do IBS em 2026 (%). Mesma lógica de compensação da
  /// CBS de teste.
  static const double testPhaseIbsPercent = 0.1;

  /// A partir de que ano o Imposto Seletivo passa a incidir (2027, junto com
  /// a substituição plena de PIS/COFINS pela CBS).
  static const int impostoSeletivoStartYear = 2027;

  static bool impostoSeletivoActiveForYear(int year) {
    return year >= impostoSeletivoStartYear;
  }

  /// Percentual (0-100) da carga tributária "antiga" (ICMS/ISS) que ainda
  /// vigora no ano informado. A LC 214/2025 define substituição linear de
  /// 10 pontos percentuais ao ano entre 2029 e 2032, com extinção total do
  /// ICMS/ISS em 2033 (não é uma continuação linear até 0 — o corte final é
  /// integral nesse ano).
  static double oldTaxWeightPercentForYear(int year) {
    if (year < 2029) {
      return 100;
    }
    switch (year) {
      case 2029:
        return 90;
      case 2030:
        return 80;
      case 2031:
        return 70;
      case 2032:
        return 60;
      default:
        return 0; // 2033 em diante: ICMS/ISS extintos.
    }
  }

  /// Percentual (0-100) da carga tributária "nova" (IBS/CBS) equivalente no
  /// ano informado — sempre o complemento de [oldTaxWeightPercentForYear].
  static double newTaxWeightPercentForYear(int year) {
    return 100 - oldTaxWeightPercentForYear(year);
  }

  /// Mistura (pondera) o valor que seria cobrado pelo tributo "antigo"
  /// (ICMS/ISS, à regra de hoje) com o valor que seria cobrado pelo tributo
  /// "novo" (IBS/CBS, à alíquota de referência plena), conforme o peso de
  /// transição do ano informado.
  ///
  /// Função pura, não usada hoje por nenhum pipeline de cálculo real de
  /// preço (ver [impactsFinalPrice], que permanece `false`) — existe para
  /// permitir testes e simulações adiantadas do motor antes da substituição
  /// entrar em vigor de fato.
  static double blendOldAndNewTaxValues({
    required double oldTaxFullValue,
    required double newTaxFullValue,
    required int year,
  }) {
    final oldWeight = oldTaxWeightPercentForYear(year) / 100;
    final newWeight = newTaxWeightPercentForYear(year) / 100;
    return (oldTaxFullValue * oldWeight) + (newTaxFullValue * newWeight);
  }
}
