import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/brazil_states.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tax_rule.dart';
import '../../../../core/services/tax_reform_calendar.dart';
import '../services/tax_rule_formatting_utils.dart';

/// Rascunho de edição de uma regra de tributação, com os valores ainda em
/// formato de texto (string) tal como digitados no formulário — a
/// conversão para os tipos finais (double, DateTime normalizado, etc.) é
/// responsabilidade de quem chama [showTaxRuleFormDialog].
class TaxRuleDraft {
  const TaxRuleDraft({
    required this.active,
    required this.ncm,
    required this.cest,
    required this.fiscalException,
    required this.taxGroupId,
    required this.ufDestino,
    required this.stCalculationType,
    required this.stPriceForCalculation,
    required this.mvaIva,
    required this.stBaseReductionPercent,
    required this.stBaseAmount,
    required this.aliquotaDestino,
    required this.aliquotaCredito,
    required this.aliquotaDifal,
    required this.aliquotaFcp,
    required this.aliquotaFcpSt,
    required this.aliquotaFcpDifal,
    required this.applicableBuyerTaxRegime,
    required this.stReductionAppliesToIcmsProprio,
    required this.cstCsosn,
    required this.reformaAliquotaIbsEstadual,
    required this.reformaAliquotaIbsMunicipal,
    required this.reformaPercentualReducaoIbs,
    required this.reformaAliquotaReferenciaCbs,
    required this.reformaPercentualReducaoCbs,
    required this.reformaAliquotaReferenciaIs,
    required this.validFrom,
    required this.validUntil,
  });

  final bool active;
  final String ncm;
  final String cest;
  final String fiscalException;
  final String taxGroupId;
  final String ufDestino;
  final String stCalculationType;
  final String stPriceForCalculation;
  final String mvaIva;
  final String stBaseReductionPercent;
  final String stBaseAmount;
  final String aliquotaDestino;
  final String aliquotaCredito;
  final String aliquotaDifal;
  final String aliquotaFcp;
  final String aliquotaFcpSt;
  final String aliquotaFcpDifal;
  final String? applicableBuyerTaxRegime;
  final bool stReductionAppliesToIcmsProprio;
  final String cstCsosn;
  final String reformaAliquotaIbsEstadual;
  final String reformaAliquotaIbsMunicipal;
  final String reformaPercentualReducaoIbs;
  final String reformaAliquotaReferenciaCbs;
  final String reformaPercentualReducaoCbs;
  final String reformaAliquotaReferenciaIs;
  final DateTime? validFrom;
  final DateTime? validUntil;
}

const String _selectUfOption = 'SELECIONE';
final List<String> _ufOptions = <String>[_selectUfOption, ...brazilStates];

const Color _dialogChromeColor = Color(0xFFF5F6F8);
const Color _dialogBodyColor = Colors.white;
const Color _dialogBorderColor = Color(0xFFE3E6EA);
const Color _dialogFocusedBorderColor = Color(0xFFD0D6DE);
const double _dialogFieldVerticalGap = 14;

enum _StCalculationType { mva, pmc }

/// Abre o formulário (criação/edição) de uma regra de tributação e retorna
/// o [TaxRuleDraft] preenchido, ou `null` se o usuário cancelar.
///
/// Extraído de `_TaxRulesSectionState._showRuleFormDialog`
/// (`web_portal_tax_rules_section.dart`) para isolar a árvore de widgets do
/// diálogo da lógica de carregamento/persistência da seção de tributação.
Future<TaxRuleDraft?> showTaxRuleFormDialog(
  BuildContext context, {
  TaxRule? existing,
  required bool reformaEnabled,
}) async {
  final formKey = GlobalKey<FormState>();
  final ncmController = TextEditingController(
    text: formatNcmMasked(normalizeNcmDigits(existing?.ncm)),
  );
  final cestController = TextEditingController(
    text: formatCestMasked(normalizeCestDigits(existing?.cest)),
  );
  final fiscalExceptionController = TextEditingController(
    text: existing?.fiscalException ?? '',
  );
  final taxGroupIdController = TextEditingController(
    text: existing?.taxGroupId ?? '',
  );
  var selectedUfDestino = _normalizeUfForDropdown(existing?.ufDestino);
  var stCalculationType = _readStCalculationType(existing?.stCalculationType);
  final cstCsosnController = TextEditingController(
    text: existing?.cstCsosn ?? '',
  );
  final stPriceForCalculationController = TextEditingController(
    text: _formatDecimalForInput(existing?.stPriceForCalculation),
  );
  final mvaController = TextEditingController(
    text: _formatDecimalForInput(existing?.mvaIva),
  );
  final stBaseReductionController = TextEditingController(
    text: _formatDecimalForInput(existing?.stBaseReductionPercent),
  );
  final stBaseAmountController = TextEditingController(
    text: _formatDecimalForInput(existing?.stBaseAmount),
  );
  final aliquotaDestinoController = TextEditingController(
    text: _formatDecimalForInput(
      existing?.aliquotaDestino ?? existing?.aliquotaSt,
    ),
  );
  final aliquotaCreditoController = TextEditingController(
    text: _formatDecimalForInput(
      existing?.aliquotaCredito ?? existing?.aliquotaIcms,
    ),
  );
  final aliquotaDifalController = TextEditingController(
    text: _formatDecimalForInput(existing?.aliquotaDifal),
  );
  final aliquotaFcpController = TextEditingController(
    text: _formatDecimalForInput(existing?.aliquotaFcp),
  );
  final aliquotaFcpStController = TextEditingController(
    text: _formatDecimalForInput(existing?.aliquotaFcpSt),
  );
  final aliquotaFcpDifalController = TextEditingController(
    text: _formatDecimalForInput(existing?.aliquotaFcpDifal),
  );
  var selectedBuyerTaxRegime = existing?.applicableBuyerTaxRegime;
  var stReductionAppliesToIcmsProprio =
      existing?.stReductionAppliesToIcmsProprio ?? false;
  final reformaAliquotaIbsEstadualController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaAliquotaIbsEstadual),
  );
  final reformaAliquotaIbsMunicipalController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaAliquotaIbsMunicipal),
  );
  final reformaPercentualReducaoIbsController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaPercentualReducaoIbs),
  );
  final reformaAliquotaCbsController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaAliquotaReferenciaCbs),
  );
  final reformaPercentualReducaoCbsController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaPercentualReducaoCbs),
  );
  final reformaAliquotaIsController = TextEditingController(
    text: _formatDecimalForInput(existing?.reformaAliquotaReferenciaIs),
  );
  var validFrom = existing?.validFrom?.toLocal();
  var validUntil = existing?.validUntil?.toLocal();
  var active = existing?.isActive ?? true;

  final result = await showDialog<TaxRuleDraft>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 680,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: _dialogBodyColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _dialogBorderColor, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: double.infinity,
                      color: _dialogChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Text(
                        existing == null
                            ? 'Nova regra fiscal'
                            : 'Editar regra fiscal',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: _dialogBodyColor,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: SizedBox(
                          width: 620,
                          child: Form(
                            key: formKey,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Material(
                                  color: Colors.transparent,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: active,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        active = value;
                                      });
                                    },
                                    title: const Text('Regra ativa'),
                                  ),
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledTextField(
                                        label: 'NCM *',
                                        controller: ncmController,
                                        hintText: '0000.00.00',
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          _NcmInputFormatter(),
                                        ],
                                        validator: (raw) {
                                          final digits = normalizeNcmDigits(
                                            raw,
                                          );
                                          if (digits.isEmpty) {
                                            return 'NCM obrigatório';
                                          }
                                          if (!isValidNcmDigits(digits)) {
                                            return 'NCM deve ter 8 dígitos';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _labeledTextField(
                                        label: 'CEST (opcional)',
                                        controller: cestController,
                                        hintText: '00.000.00',
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          _CestInputFormatter(),
                                        ],
                                        validator: (raw) {
                                          final digits = normalizeCestDigits(
                                            raw,
                                          );
                                          if (digits.isEmpty) {
                                            return null;
                                          }
                                          if (!isValidCestDigits(digits)) {
                                            return 'CEST deve ter 7 dígitos';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledUfDropdown(
                                        label: 'UF destino *',
                                        value: selectedUfDestino,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            selectedUfDestino =
                                                value ?? _selectUfOption;
                                          });
                                        },
                                        validator: (value) {
                                          if ((value ?? _selectUfOption) ==
                                              _selectUfOption) {
                                            return 'Selecione a UF destino';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledTextField(
                                        label: 'Exceção fiscal',
                                        controller: fiscalExceptionController,
                                      ),
                                    ),
                                    const Expanded(
                                      child: SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledTextField(
                                        label: 'Grupo tributario',
                                        controller: taxGroupIdController,
                                        hintText:
                                            'ID do grupo cadastrado em Grupos tributarios',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledTextField(
                                        label: 'CST/CSOSN',
                                        controller: cstCsosnController,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaDifalController,
                                        label: 'Alíquota DIFAL',
                                        suffixText: '%',
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _labeledDateField(
                                        label: 'Vigência inicial',
                                        value: validFrom,
                                        onPick: () async {
                                          final picked = await _pickDate(
                                            context,
                                            initialDate: validFrom,
                                          );
                                          if (picked == null) {
                                            return;
                                          }
                                          setDialogState(() {
                                            validFrom = picked;
                                          });
                                        },
                                        onClear: validFrom == null
                                            ? null
                                            : () {
                                                setDialogState(() {
                                                  validFrom = null;
                                                });
                                              },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _labeledDateField(
                                        label: 'Vigência final',
                                        value: validUntil,
                                        onPick: () async {
                                          final picked = await _pickDate(
                                            context,
                                            initialDate: validUntil,
                                          );
                                          if (picked == null) {
                                            return;
                                          }
                                          setDialogState(() {
                                            validUntil = picked;
                                          });
                                        },
                                        onClear: validUntil == null
                                            ? null
                                            : () {
                                                setDialogState(() {
                                                  validUntil = null;
                                                });
                                              },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                _labeledStCalculationTypeDropdown(
                                  value: stCalculationType,
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(() {
                                      stCalculationType = value;
                                    });
                                  },
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                if (stCalculationType ==
                                    _StCalculationType.mva) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _unitField(
                                          controller:
                                              stPriceForCalculationController,
                                          label: 'Preço considerado no cálculo (opcional)',
                                          prefixText: 'R\$',
                                          required: false,
                                          min: 0,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _unitField(
                                          controller: mvaController,
                                          label: 'Margem de valor agregado',
                                          suffixText: '%',
                                          required: true,
                                          min: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _unitField(
                                          controller:
                                              stBaseReductionController,
                                          label: 'Redução de base ICMS-ST',
                                          suffixText: '%',
                                          required: true,
                                          min: 0,
                                          max: 100,
                                        ),
                                      ),
                                      const Expanded(
                                        child: SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _unitField(
                                          controller: stBaseAmountController,
                                          label: 'Base de cálculo ICMS-ST',
                                          prefixText: 'R\$',
                                          required: true,
                                          min: 0,
                                        ),
                                      ),
                                      const Expanded(
                                        child: SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaDestinoController,
                                        label: 'Alíquota destino',
                                        suffixText: '%',
                                        required: true,
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaCreditoController,
                                        label: 'Alíquota crédito',
                                        suffixText: '%',
                                        required: true,
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaFcpController,
                                        label: 'Alíquota FCP',
                                        suffixText: '%',
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaFcpStController,
                                        label: 'Alíquota FCP ST',
                                        suffixText: '%',
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _unitField(
                                        controller: aliquotaFcpDifalController,
                                        label: 'Alíquota FCP DIFAL',
                                        suffixText: '%',
                                        min: 0,
                                        max: 100,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Regime tributário do comprador (desempate)',
                                          ),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<String?>(
                                            initialValue:
                                                selectedBuyerTaxRegime,
                                            decoration:
                                                _dialogInputDecoration(),
                                            items: <DropdownMenuItem<String?>>[
                                              const DropdownMenuItem<String?>(
                                                value: null,
                                                child: Text('Qualquer regime'),
                                              ),
                                              ...taxRegimeValues.map(
                                                (value) =>
                                                    DropdownMenuItem<String?>(
                                                      value: value,
                                                      child: Text(
                                                        taxRegimeLabel(value),
                                                      ),
                                                    ),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              setDialogState(() {
                                                selectedBuyerTaxRegime =
                                                    value;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: _dialogFieldVerticalGap,
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: stReductionAppliesToIcmsProprio,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        stReductionAppliesToIcmsProprio =
                                            value;
                                      });
                                    },
                                    title: const Text(
                                      'Redução de base do ICMS-ST também aplica ao ICMS próprio',
                                    ),
                                  ),
                                ),
                                if (reformaEnabled) ...[
                                  const SizedBox(
                                    height: _dialogFieldVerticalGap,
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        10,
                                      ),
                                      border: Border.all(
                                        color: _dialogBorderColor,
                                      ),
                                      color: _dialogChromeColor,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.auto_graph_outlined,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Reforma Tributária (IBS/CBS/IS)',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Preenchimento opcional nesta fase (${TaxReformCalendar.phaseLabel(TaxReformCalendar.currentPhase())}). '
                                          'Os campos abaixo ficam prontos para quando a Reforma exigir cálculo ativo e não alteram o preço final hoje.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(
                                          height: _dialogFieldVerticalGap,
                                        ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _unitField(
                                                controller:
                                                    reformaAliquotaIbsEstadualController,
                                                label:
                                                    'Alíquota IBS estadual',
                                                suffixText: '%',
                                                min: 0,
                                                max: 100,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _unitField(
                                                controller:
                                                    reformaAliquotaIbsMunicipalController,
                                                label:
                                                    'Alíquota IBS municipal',
                                                suffixText: '%',
                                                min: 0,
                                                max: 100,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _unitField(
                                                controller:
                                                    reformaPercentualReducaoIbsController,
                                                label:
                                                    'Redução IBS',
                                                suffixText: '%',
                                                min: 0,
                                                max: 100,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(
                                          height: _dialogFieldVerticalGap,
                                        ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _unitField(
                                                controller:
                                                    reformaAliquotaCbsController,
                                                label:
                                                    'Alíquota referência CBS',
                                                suffixText: '%',
                                                min: 0,
                                                max: 100,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _unitField(
                                                controller:
                                                    reformaPercentualReducaoCbsController,
                                                label:
                                                    'Redução CBS',
                                                suffixText: '%',
                                                min: 0,
                                                max: 100,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(
                                          height: _dialogFieldVerticalGap,
                                        ),
                                        _unitField(
                                          controller:
                                              reformaAliquotaIsController,
                                          label:
                                              'Alíquota referência IS (seletivo) — sem redução',
                                          suffixText: '%',
                                          min: 0,
                                          max: 100,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: _dialogChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ??
                                  true)) {
                                return;
                              }

                              if (!_isValidDateWindow(
                                validFrom,
                                validUntil,
                              )) {
                                ScaffoldMessenger.of(dialogContext)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'A vigência final não pode ser anterior à vigência inicial.',
                                      ),
                                    ),
                                  );
                                return;
                              }

                              Navigator.of(dialogContext).pop(
                                TaxRuleDraft(
                                  active: active,
                                  ncm: ncmController.text,
                                  cest: cestController.text,
                                  fiscalException:
                                      fiscalExceptionController.text,
                                  taxGroupId: taxGroupIdController.text,
                                  ufDestino: selectedUfDestino,
                                  stCalculationType:
                                      _stCalculationTypeToStorage(
                                        stCalculationType,
                                      ),
                                  stPriceForCalculation:
                                      stPriceForCalculationController.text,
                                  mvaIva: mvaController.text,
                                  stBaseReductionPercent:
                                      stBaseReductionController.text,
                                  stBaseAmount: stBaseAmountController.text,
                                  aliquotaDestino:
                                      aliquotaDestinoController.text,
                                  aliquotaCredito:
                                      aliquotaCreditoController.text,
                                  aliquotaDifal: aliquotaDifalController.text,
                                  aliquotaFcp: aliquotaFcpController.text,
                                  aliquotaFcpSt: aliquotaFcpStController.text,
                                  aliquotaFcpDifal:
                                      aliquotaFcpDifalController.text,
                                  applicableBuyerTaxRegime:
                                      selectedBuyerTaxRegime,
                                  stReductionAppliesToIcmsProprio:
                                      stReductionAppliesToIcmsProprio,
                                  cstCsosn: cstCsosnController.text,
                                  reformaAliquotaIbsEstadual:
                                      reformaAliquotaIbsEstadualController
                                          .text,
                                  reformaAliquotaIbsMunicipal:
                                      reformaAliquotaIbsMunicipalController
                                          .text,
                                  reformaPercentualReducaoIbs:
                                      reformaPercentualReducaoIbsController
                                          .text,
                                  reformaAliquotaReferenciaCbs:
                                      reformaAliquotaCbsController.text,
                                  reformaPercentualReducaoCbs:
                                      reformaPercentualReducaoCbsController
                                          .text,
                                  reformaAliquotaReferenciaIs:
                                      reformaAliquotaIsController.text,
                                  validFrom: validFrom,
                                  validUntil: validUntil,
                                ),
                              );
                            },
                            child: const Text('Salvar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  // Os controllers ficam anexados aos campos durante a animacao de fechamento
  // do dialogo. Dispor aqui pode causar "used after disposed" no frame seguinte.

  return result;
}

Widget _labeledTextField({
  required String label,
  required TextEditingController controller,
  String? hintText,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  FormFieldValidator<String>? validator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: _dialogInputDecoration(hintText: hintText),
      ),
    ],
  );
}

Widget _labeledUfDropdown({
  required String label,
  required String value,
  required ValueChanged<String?> onChanged,
  FormFieldValidator<String>? validator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: _dialogInputDecoration(),
        validator: validator,
        items: _ufOptions
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item == _selectUfOption ? 'Selecione' : item),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    ],
  );
}

Widget _labeledDateField({
  required String label,
  required DateTime? value,
  required VoidCallback onPick,
  VoidCallback? onClear,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: _dialogInputDecoration(
            hintText: 'Sem limite',
            suffixText: onClear == null ? null : 'X',
          ),
          child: Row(
            children: [
              Expanded(child: Text(_formatDate(value))),
              IconButton(
                tooltip: onClear == null ? 'Selecionar data' : 'Limpar data',
                visualDensity: VisualDensity.compact,
                onPressed: onClear ?? onPick,
                icon: Icon(
                  onClear == null
                      ? Icons.calendar_today_outlined
                      : Icons.clear_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Widget _labeledStCalculationTypeDropdown({
  required _StCalculationType value,
  required ValueChanged<_StCalculationType?> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Tipo de subs. tributária'),
      const SizedBox(height: 6),
      DropdownButtonFormField<_StCalculationType>(
        initialValue: value,
        decoration: _dialogInputDecoration(),
        items: const [
          DropdownMenuItem<_StCalculationType>(
            value: _StCalculationType.mva,
            child: Text('Por MVA'),
          ),
          DropdownMenuItem<_StCalculationType>(
            value: _StCalculationType.pmc,
            child: Text('Por PMC'),
          ),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

Widget _unitField({
  required TextEditingController controller,
  required String label,
  String? prefixText,
  String? suffixText,
  bool required = false,
  double? min,
  double? max,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,\\.]')),
        ],
        decoration: _dialogInputDecoration(
          prefixText: prefixText,
          suffixText: suffixText,
          suffixBackground: _dialogChromeColor,
          prefixBackground: _dialogChromeColor,
        ),
        validator: (raw) {
          final source = (raw ?? '').trim();
          if (required && source.isEmpty) {
            return 'Campo obrigatório';
          }
          final value = nullableDouble(raw);
          if (source.isNotEmpty && value == null) {
            return 'Número inválido';
          }
          if (value == null) {
            return null;
          }
          if (min != null && value < min) {
            return 'Valor mínimo: ${min.toStringAsFixed(0)}';
          }
          if (max != null && value > max) {
            return 'Valor máximo: ${max.toStringAsFixed(0)}';
          }
          return null;
        },
      ),
    ],
  );
}

InputDecoration _dialogInputDecoration({
  String? prefixText,
  String? suffixText,
  Color? prefixBackground,
  Color? suffixBackground,
  String? hintText,
}) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: _dialogBodyColor,
    hintText: hintText,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: _dialogFieldBorder(_dialogBorderColor),
    enabledBorder: _dialogFieldBorder(_dialogBorderColor),
    focusedBorder: _dialogFieldBorder(_dialogFocusedBorderColor),
    prefixIcon: prefixText == null
        ? null
        : Container(
            width: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: prefixBackground ?? _dialogBodyColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              border: Border(
                right: BorderSide(color: _dialogBorderColor, width: 1),
              ),
            ),
            child: Text(
              prefixText,
              style: const TextStyle(),
            ),
          ),
    suffixIcon: suffixText == null
        ? null
        : Container(
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: suffixBackground ?? _dialogBodyColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              border: Border(
                left: BorderSide(color: _dialogBorderColor, width: 1),
              ),
            ),
            child: Text(
              suffixText,
              style: const TextStyle(),
            ),
          ),
  );
}

OutlineInputBorder _dialogFieldBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color, width: 1),
  );
}

String _normalizeUfForDropdown(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  if (normalized.isEmpty || normalized == 'ANY') {
    return _selectUfOption;
  }
  if (isBrazilState(normalized)) {
    return normalized;
  }
  return _selectUfOption;
}

Future<DateTime?> _pickDate(BuildContext context, {DateTime? initialDate}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? now,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
}

bool _isValidDateWindow(DateTime? validFrom, DateTime? validUntil) {
  if (validFrom == null || validUntil == null) {
    return true;
  }
  return !validUntil.isBefore(validFrom);
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Sem limite';
  }
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  return '$day/$month/$year';
}

_StCalculationType _readStCalculationType(String? value) {
  if ((value ?? '').trim().toLowerCase() == 'pmc') {
    return _StCalculationType.pmc;
  }
  return _StCalculationType.mva;
}

String _stCalculationTypeToStorage(_StCalculationType value) {
  return value == _StCalculationType.pmc ? 'pmc' : 'mva';
}

String _formatDecimalForInput(double? value) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

class _NcmInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 4 || i == 6) {
        buffer.write('.');
      }
      buffer.write(truncated[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CestInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final truncated = digits.length > 7 ? digits.substring(0, 7) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 2 || i == 5) {
        buffer.write('.');
      }
      buffer.write(truncated[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
