part of 'web_portal_page.dart';

Future<String?> _pickAndResizeLogoDataUrl() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    allowMultiple: false,
  );

  final files = result?.files;
  if (files == null || files.isEmpty) {
    return null;
  }

  final file = files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }

  var resized = decoded;
  if (decoded.width > 256 || decoded.height > 256) {
    final width = decoded.width;
    final height = decoded.height;
    if (width >= height) {
      resized = image_lib.copyResize(decoded, width: 256);
    } else {
      resized = image_lib.copyResize(decoded, height: 256);
    }
  }

  final pngBytes = image_lib.encodePng(resized);
  return 'data:image/png;base64,${base64Encode(pngBytes)}';
}

Future<Map<String, Object?>?> _openRepresentedCompanyEditor(
  BuildContext context, {
  _RepresentedCompany? initial,
  required List<_RepresentedCompany> allCompanies,
}) async {
  const dialogChromeColor = Color(0xFFF5F6F8);
  const dialogBodyColor = Colors.white;
  const dialogBorderColor = Color(0xFFE3E6EA);
  const dialogFocusedBorderColor = Color(0xFFD0D6DE);
  const dialogFieldVerticalGap = 14.0;

  final nomeFantasiaController = TextEditingController(
    text: initial?.nomeFantasia ?? '',
  );
  final razaoSocialController = TextEditingController(
    text: initial?.razaoSocial ?? '',
  );
  final cnpjController = TextEditingController(
    text: _formatCnpjMasked(initial?.cnpj),
  );
  final cepController = TextEditingController(
    text: _formatCepMasked(initial?.cep),
  );
  final logradouroController = TextEditingController(
    text: initial?.logradouro ?? '',
  );
  final numeroController = TextEditingController(text: initial?.numero ?? '');
  final contatoController = TextEditingController(text: initial?.contato ?? '');
  final telefoneController = TextEditingController(
    text: _formatPhoneMasked(initial?.telefone),
  );
  final emailController = TextEditingController(text: initial?.email ?? '');
  final cidadeController = TextEditingController(text: initial?.cidade ?? '');
  final segmentoController = TextEditingController(
    text: initial?.segmento ?? '',
  );
  var taxRegime = _normalizeTaxRegimeValue(initial?.taxRegime);
  if (taxRegime.isEmpty) {
    taxRegime = _defaultTaxRegime;
  }
  var ativo = initial?.ativo ?? true;
  var logoData = initial?.logoUrl ?? '';
  var buscandoCep = false;
  var selectedUf = _normalizeStateForDropdown(initial?.uf);
  final currentCompanyId = initial?.id.trim() ?? '';
  final matrixCandidates = allCompanies
      .where(
        (company) =>
            company.id != currentCompanyId &&
            company.parentCompanyId.trim().isEmpty,
      )
      .toList(growable: false);
  var selectedParentCompanyId = _normalizeParentCompanyForEditor(
    currentParentCompanyId: initial?.parentCompanyId,
    matrixCandidates: matrixCandidates,
  );
  var isBranchCompany = selectedParentCompanyId.isNotEmpty;
  final linkedBranches = allCompanies
      .where((company) => company.parentCompanyId.trim() == currentCompanyId)
      .toList(growable: false);
  final isMatrixWithLinkedBranches =
      initial != null &&
      initial.parentCompanyId.trim().isEmpty &&
      linkedBranches.isNotEmpty;
  final formKey = GlobalKey<FormState>();

  InputDecoration dialogInputDecoration({String? hintText}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: dialogBodyColor,
      hintText: hintText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dialogBorderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dialogBorderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: dialogFocusedBorderColor, width: 1),
      ),
    );
  }

  Widget labeledField({
    required BuildContext fieldContext,
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
        Text(label, style: Theme.of(fieldContext).textTheme.bodySmall),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: dialogInputDecoration(hintText: hintText),
        ),
      ],
    );
  }

  Widget labeledStateDropdown({
    required BuildContext fieldContext,
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
    FormFieldValidator<String>? validator,
  }) {
    final dropdownTextStyle = Theme.of(fieldContext).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w400);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(fieldContext).textTheme.bodySmall),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(value),
          initialValue: value,
          style: dropdownTextStyle,
          validator: validator,
          decoration: dialogInputDecoration(),
          items: brazilStates
              .map(
                (uf) => DropdownMenuItem<String>(
                  value: uf,
                  child: Text(uf, style: dropdownTextStyle),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget labeledTaxRegimeDropdown({
    required BuildContext fieldContext,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final dropdownTextStyle = Theme.of(fieldContext).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w400);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Regime tributário',
          style: Theme.of(fieldContext).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(value),
          initialValue: value,
          style: dropdownTextStyle,
          decoration: dialogInputDecoration(),
          items: _taxRegimeOptions
              .map(
                (regime) => DropdownMenuItem<String>(
                  value: regime,
                  child: Text(
                    _taxRegimeLabel(regime),
                    style: dropdownTextStyle,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> buscarCep(StateSetter setDialogState) async {
    final cep = cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um CEP válido com 8 dígitos.')),
        );
      }
      return;
    }

    setDialogState(() {
      buscandoCep = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://brasilapi.com.br/api/cep/v2/$cep'),
      );
      if (response.statusCode != 200) {
        throw StateError('cep_lookup_error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final city = (data['city'] ?? data['cidade'] ?? '').toString().trim();
      final state = (data['state'] ?? data['uf'] ?? '').toString().trim();
      final street = (data['street'] ?? data['logradouro'] ?? '')
          .toString()
          .trim();

      if (street.isNotEmpty) {
        logradouroController.text = street;
      }

      if (city.isNotEmpty) {
        cidadeController.text = city;
      }
      if (state.isNotEmpty) {
        setDialogState(() {
          selectedUf = _normalizeStateForDropdown(state);
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endereço localizado pelo CEP.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível consultar esse CEP agora.'),
          ),
        );
      }
    } finally {
      setDialogState(() {
        buscandoCep = false;
      });
    }
  }

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final maxDialogHeight = MediaQuery.sizeOf(dialogContext).height - 36;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: maxDialogHeight,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: dialogBodyColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: dialogBorderColor, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      color: dialogChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Text(
                        initial == null
                            ? 'Nova empresa representada'
                            : 'Editar representada',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        color: dialogBodyColor,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: SizedBox(
                          width: 700,
                          child: Form(
                            key: formKey,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Nome fantasia *',
                                          controller: nomeFantasiaController,
                                          validator: (value) {
                                            if ((value ?? '').trim().isEmpty) {
                                              return 'Campo obrigatório';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Razão social',
                                          controller: razaoSocialController,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'CNPJ',
                                          controller: cnpjController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            _CnpjInputFormatter(),
                                          ],
                                          validator: (value) {
                                            final digits = _digitsOnly(value);
                                            if (digits.isEmpty) {
                                              return 'Informe o CNPJ';
                                            }
                                            if (!_isValidCnpjDigits(digits)) {
                                              return 'CNPJ inválido';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Contato',
                                          controller: contatoController,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Telefone',
                                          controller: telefoneController,
                                          keyboardType: TextInputType.phone,
                                          inputFormatters: <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            _PhoneInputFormatter(),
                                          ],
                                          validator: (value) {
                                            final digits = _digitsOnly(value);
                                            if (digits.isEmpty) {
                                              return null;
                                            }
                                            if (digits.length < 10 ||
                                                digits.length > 11) {
                                              return 'Telefone deve ter 10 ou 11 dígitos';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'E-mail',
                                          controller: emailController,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          validator: (value) {
                                            final email = (value ?? '').trim();
                                            if (email.isEmpty) {
                                              return null;
                                            }
                                            if (!_isValidEmailAddress(email)) {
                                              return 'E-mail inválido';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Logradouro',
                                          controller: logradouroController,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 120,
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Número',
                                          controller: numeroController,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'CEP',
                                          controller: cepController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            _CepInputFormatter(),
                                          ],
                                          validator: (value) {
                                            final digits = _digitsOnly(value);
                                            if (digits.isEmpty) {
                                              return null;
                                            }
                                            if (digits.length != 8) {
                                              return 'CEP deve ter 8 dígitos';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 48,
                                        child: FilledButton.tonalIcon(
                                          onPressed: buscandoCep
                                              ? null
                                              : () => buscarCep(setDialogState),
                                          icon: buscandoCep
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.search),
                                          label: Text(
                                            buscandoCep
                                                ? 'Buscando...'
                                                : 'Buscar CEP',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Cidade',
                                          controller: cidadeController,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 100,
                                        child: labeledStateDropdown(
                                          fieldContext: dialogContext,
                                          label: 'UF',
                                          value: selectedUf,
                                          onChanged: (value) {
                                            if (value == null) {
                                              return;
                                            }
                                            setDialogState(() {
                                              selectedUf = value;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: labeledField(
                                          fieldContext: dialogContext,
                                          label: 'Segmento',
                                          controller: segmentoController,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  labeledTaxRegimeDropdown(
                                    fieldContext: dialogContext,
                                    value: taxRegime,
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        final normalized =
                                            _normalizeTaxRegimeValue(value);
                                        taxRegime = normalized.isEmpty
                                            ? _defaultTaxRegime
                                            : normalized;
                                      });
                                    },
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    children: [
                                      _RepresentedCompanyAvatar(
                                        company: _RepresentedCompany(
                                          id: initial?.id ?? 'preview',
                                          nomeFantasia:
                                              nomeFantasiaController.text,
                                          razaoSocial:
                                              razaoSocialController.text,
                                          cnpj: cnpjController.text,
                                          cep: cepController.text,
                                          logradouro: logradouroController.text,
                                          numero: numeroController.text,
                                          logoUrl: logoData,
                                          contato: contatoController.text,
                                          telefone: telefoneController.text,
                                          email: emailController.text,
                                          cidade: cidadeController.text,
                                          uf: selectedUf,
                                          segmento: segmentoController.text,
                                          taxRegime: taxRegime,
                                          ativo: ativo,
                                          parentCompanyId: isBranchCompany
                                              ? selectedParentCompanyId
                                              : '',
                                        ),
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () async {
                                                final pickedData =
                                                    await _pickAndResizeLogoDataUrl();
                                                if (pickedData == null) {
                                                  return;
                                                }
                                                setDialogState(() {
                                                  logoData = pickedData;
                                                });
                                              },
                                              icon: const Icon(
                                                Icons.upload_file_outlined,
                                              ),
                                              label: const Text('Enviar logo'),
                                            ),
                                            if (logoData.trim().isNotEmpty)
                                              TextButton.icon(
                                                onPressed: () {
                                                  setDialogState(() {
                                                    logoData = '';
                                                  });
                                                },
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                label: const Text(
                                                  'Remover logo',
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 170,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Empresa filial'),
                                            Switch(
                                              value: isBranchCompany,
                                              onChanged:
                                                  isMatrixWithLinkedBranches
                                                  ? null
                                                  : (value) {
                                                      setDialogState(() {
                                                        isBranchCompany = value;
                                                        if (!isBranchCompany) {
                                                          selectedParentCompanyId =
                                                              '';
                                                        }
                                                      });
                                                    },
                                            ),
                                            if (isMatrixWithLinkedBranches)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  'Esta empresa já possui filiais vinculadas e não pode virar filial.',
                                                  style: Theme.of(dialogContext)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (isBranchCompany)
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Vínculo com matriz',
                                                style: Theme.of(dialogContext)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Selecione a matriz desta filial.',
                                                style: Theme.of(dialogContext)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                              const SizedBox(height: 10),
                                              DropdownButtonFormField<String>(
                                                initialValue:
                                                    selectedParentCompanyId
                                                        .trim()
                                                        .isEmpty
                                                    ? null
                                                    : selectedParentCompanyId,
                                                style: Theme.of(dialogContext)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                decoration:
                                                    dialogInputDecoration(),
                                                items: matrixCandidates
                                                    .map(
                                                      (
                                                        company,
                                                      ) => DropdownMenuItem<String>(
                                                        value: company.id,
                                                        child: Text(
                                                          '${company.nomeFantasia.trim().isEmpty ? company.id : company.nomeFantasia.trim()} (${company.uf.trim().isEmpty ? 'UF?' : company.uf.trim().toUpperCase()})',
                                                          style:
                                                              Theme.of(
                                                                    dialogContext,
                                                                  )
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w400,
                                                                  ),
                                                        ),
                                                      ),
                                                    )
                                                    .toList(growable: false),
                                                validator: (value) {
                                                  if (!isBranchCompany) {
                                                    return null;
                                                  }
                                                  final normalized =
                                                      (value ?? '').trim();
                                                  if (normalized.isEmpty) {
                                                    return 'Selecione a matriz da filial';
                                                  }

                                                  final currentDigits =
                                                      _digitsOnly(
                                                        cnpjController.text,
                                                      );
                                                  if (currentDigits.length ==
                                                      14) {
                                                    _RepresentedCompany?
                                                    selectedMatrix;
                                                    for (final company
                                                        in matrixCandidates) {
                                                      if (company.id ==
                                                          normalized) {
                                                        selectedMatrix =
                                                            company;
                                                        break;
                                                      }
                                                    }
                                                    final matrixDigits =
                                                        _digitsOnly(
                                                          selectedMatrix?.cnpj,
                                                        );
                                                    if (matrixDigits.length ==
                                                            14 &&
                                                        matrixDigits.substring(
                                                              0,
                                                              8,
                                                            ) !=
                                                            currentDigits
                                                                .substring(
                                                                  0,
                                                                  8,
                                                                )) {
                                                      return 'Filial e matriz devem compartilhar a mesma raiz de CNPJ.';
                                                    }
                                                  }
                                                  return null;
                                                },
                                                onChanged: (value) {
                                                  setDialogState(() {
                                                    selectedParentCompanyId =
                                                        value ?? '';
                                                  });
                                                },
                                              ),
                                              const SizedBox(height: 12),
                                              if (initial != null) ...[
                                                if (linkedBranches
                                                    .isNotEmpty) ...[
                                                  Text(
                                                    'Filiais vinculadas (somente leitura)',
                                                    style: Theme.of(
                                                      dialogContext,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  for (final branch
                                                      in linkedBranches)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 4,
                                                          ),
                                                      child: Text(
                                                        '• ${branch.nomeFantasia.trim().isEmpty ? branch.id : branch.nomeFantasia.trim()}${branch.uf.trim().isEmpty ? '' : ' (${branch.uf.trim().toUpperCase()})'}',
                                                      ),
                                                    ),
                                                ],
                                              ] else
                                                const Text(
                                                  'Após salvar a empresa principal, você poderá cadastrar filiais como novos cadastros e vinculá-las a ela.',
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Text('Ativa'),
                                      const SizedBox(width: 8),
                                      Switch(
                                        value: ativo,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            ativo = value;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: dialogChromeColor,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ?? true)) {
                                return;
                              }
                              Navigator.of(dialogContext).pop(true);
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

  final nomeFantasia = nomeFantasiaController.text.trim();
  final razaoSocial = razaoSocialController.text.trim();
  final cnpj = cnpjController.text.trim();
  final cep = cepController.text.trim();
  final logradouro = logradouroController.text.trim();
  final numero = numeroController.text.trim();
  final logoUrl = logoData.trim();
  final contato = contatoController.text.trim();
  final telefone = telefoneController.text.trim();
  final email = emailController.text.trim();
  final cidade = cidadeController.text.trim();
  final uf = selectedUf.trim();
  final segmento = segmentoController.text.trim();
  final normalizedTaxRegime = _normalizeTaxRegimeValue(taxRegime);
  final parentCompanyId = isBranchCompany ? selectedParentCompanyId.trim() : '';

  if (shouldSave != true) {
    return null;
  }

  if (nomeFantasia.isEmpty) {
    return null;
  }

  if (normalizedTaxRegime.isEmpty) {
    return null;
  }

  return {
    'nomeFantasia': nomeFantasia,
    'razaoSocial': razaoSocial,
    'cnpj': cnpj,
    'cep': cep,
    'logradouro': logradouro,
    'numero': numero,
    'logoUrl': logoUrl,
    'contato': contato,
    'telefone': telefone,
    'email': email,
    'cidade': cidade,
    'uf': uf,
    'segmento': segmento,
    'taxRegime': normalizedTaxRegime,
    'ativo': ativo,
    'parentCompanyId': parentCompanyId,
  };
}

String _normalizeStateForDropdown(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  if (isBrazilState(normalized)) {
    return normalized;
  }
  return 'SP';
}

String _normalizeParentCompanyForEditor({
  required String? currentParentCompanyId,
  required List<_RepresentedCompany> matrixCandidates,
}) {
  final requested = (currentParentCompanyId ?? '').trim();
  if (requested.isEmpty) {
    return '';
  }

  for (final company in matrixCandidates) {
    if (company.id == requested) {
      return requested;
    }
  }

  return '';
}

String _digitsOnly(String? value) {
  return (value ?? '').replaceAll(RegExp(r'\D'), '');
}

String _formatCnpjMasked(String? value) {
  final digits = _digitsOnly(value);
  if (digits.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (var index = 0; index < digits.length && index < 14; index++) {
    if (index == 2 || index == 5) {
      buffer.write('.');
    }
    if (index == 8) {
      buffer.write('/');
    }
    if (index == 12) {
      buffer.write('-');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _formatCepMasked(String? value) {
  final digits = _digitsOnly(value);
  if (digits.isEmpty) {
    return '';
  }

  if (digits.length <= 5) {
    return digits;
  }
  final first = digits.substring(0, 5);
  final second = digits.substring(5, digits.length > 8 ? 8 : digits.length);
  return '$first-$second';
}

String _formatPhoneMasked(String? value) {
  final digits = _digitsOnly(value);
  if (digits.isEmpty) {
    return '';
  }

  final ddd = digits.length >= 2 ? digits.substring(0, 2) : digits;
  final remaining = digits.length > 2 ? digits.substring(2) : '';
  if (remaining.isEmpty) {
    return '($ddd';
  }

  if (remaining.length <= 4) {
    return '($ddd) $remaining';
  }

  if (remaining.length <= 8) {
    final first = remaining.substring(0, remaining.length - 4);
    final last = remaining.substring(remaining.length - 4);
    return '($ddd) $first-$last';
  }

  final limited = remaining.substring(
    0,
    remaining.length > 9 ? 9 : remaining.length,
  );
  final first = limited.substring(0, 5);
  final last = limited.substring(5);
  return '($ddd) $first-$last';
}

bool _isValidEmailAddress(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return true;
  }

  return RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
      .hasMatch(normalized);
}

bool _isValidCnpjDigits(String value) {
  final digits = _digitsOnly(value);
  if (digits.length != 14) {
    return false;
  }

  if (RegExp(r'^(\d)\1{13}$').hasMatch(digits)) {
    return false;
  }

  int calcDigit(String source, List<int> weights) {
    var sum = 0;
    for (var i = 0; i < weights.length; i++) {
      sum += int.parse(source[i]) * weights[i];
    }
    final remainder = sum % 11;
    return remainder < 2 ? 0 : 11 - remainder;
  }

  final firstDigit = calcDigit(digits.substring(0, 12), <int>[
    5,
    4,
    3,
    2,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
  ]);
  final secondDigit = calcDigit(
    digits.substring(0, 12) + firstDigit.toString(),
    <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  );

  return digits.endsWith('$firstDigit$secondDigit');
}

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = _formatCnpjMasked(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = _formatCepMasked(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digitsOnly(newValue.text);
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final masked = _formatPhoneMasked(limitedDigits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
