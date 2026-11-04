part of 'web_portal_page.dart';

class _TaxOperationProfilesSection extends StatefulWidget {
  const _TaxOperationProfilesSection({
    required this.activeTenant,
    this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_TaxOperationProfilesSection> createState() =>
      _TaxOperationProfilesSectionState();
}

class _TaxOperationProfilesSectionState
    extends State<_TaxOperationProfilesSection> {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('tax_operation_profiles');

  bool _working = false;
  bool _seedRequested = false;

  static const List<_NativeOperationProfileTemplate>
  _defaultProfiles = <_NativeOperationProfileTemplate>[
    _NativeOperationProfileTemplate(
      key: 'revenda_same_uf',
      name: 'Revenda - operação estadual (mesma UF)',
      description: 'Fluxo de revenda com origem e destino na mesma UF.',
      defaultPriority: 100,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'revenda_interstate',
      name: 'Revenda - operação interestadual (UF diferente)',
      description: 'Fluxo de revenda interestadual padrão.',
      defaultPriority: 95,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_contribuinte_same_uf',
      name: 'Uso/consumo - contribuinte - operação estadual (mesma UF)',
      description: 'Uso e consumo para cliente contribuinte na mesma UF.',
      defaultPriority: 90,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_contribuinte_interstate',
      name:
          'Uso/consumo - contribuinte - operação interestadual (UF diferente)',
      description: 'Uso e consumo contribuinte em operação interestadual.',
      defaultPriority: 85,
      calculateIcmsSt: false,
      calculateDifal: true,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_nao_contribuinte_same_uf',
      name: 'Uso/consumo - não contribuinte - operação estadual (mesma UF)',
      description: 'Uso e consumo para não contribuinte na mesma UF.',
      defaultPriority: 80,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'uso_consumo_nao_contribuinte_interstate',
      name: 'Uso/consumo - não contribuinte - operação interestadual (UF diferente)',
      description: 'Uso e consumo não contribuinte em operação interestadual.',
      defaultPriority: 75,
      calculateIcmsSt: false,
      calculateDifal: true,
      includeIpiInIcmsBase: true,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'industrializacao_same_uf',
      name: 'Industrialização - operação estadual (mesma UF)',
      description: 'Industrialização com origem e destino na mesma UF.',
      defaultPriority: 70,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'industrializacao_interstate',
      name: 'Industrialização - operação interestadual (UF diferente)',
      description: 'Industrialização em operação interestadual.',
      defaultPriority: 65,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    _NativeOperationProfileTemplate(
      key: 'zfm_industrializacao',
      name: 'ZFM/SUFRAMA - Industrialização',
      description: 'Cenário ZFM para industrialização.',
      defaultPriority: 60,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: false,
      reduceIcmsForZfm: true,
    ),
    _NativeOperationProfileTemplate(
      key: 'zfm_comercializacao_revenda',
      name: 'ZFM/SUFRAMA - Comercialização/Revenda',
      description: 'Cenário ZFM para comercialização e revenda.',
      defaultPriority: 55,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: false,
      reduceIcmsForZfm: true,
    ),
  ];

  String get _selectedRepresentedCompanyId {
    return (widget.selectedRepresentedCompanyId ?? '').trim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seedRequested) {
      return;
    }
    _seedRequested = true;
    Future<void>.microtask(_ensureDefaults);
  }

  Future<void> _ensureDefaults() async {
    try {
      final tenantId = widget.activeTenant.tenantId;
      final representedCompanyId = _resolveDefaultScope();

      final snapshot = await _collection
          .where('tenantId', isEqualTo: tenantId)
          .get();
      final existingFingerprints = <String>{};
      for (final doc in snapshot.docs) {
        final parsed = _TaxOperationProfileEntity.fromDoc(doc.id, doc.data());
        if (parsed == null) {
          continue;
        }
        existingFingerprints.add(
          _profileFingerprint(
            representedCompanyId: parsed.representedCompanyId,
            profileKey: parsed.profileKey,
          ),
        );
      }

      for (final template in _defaultProfiles) {
        final fingerprint = _profileFingerprint(
          representedCompanyId: representedCompanyId,
          profileKey: template.key,
        );
        if (existingFingerprints.contains(fingerprint)) {
          continue;
        }

        final id = FirebaseFirestore.instance
            .collection('tax_operation_profiles')
            .doc()
            .id;
        await _collection.doc(id).set({
          'tenantId': tenantId,
          'representedCompanyId': representedCompanyId,
          'profileKey': template.key,
          'name': template.name,
          'description': template.description,
          'status': 'active',
          'source': 'native_seed',
          'priority': template.defaultPriority,
          'calculateIcmsSt': template.calculateIcmsSt,
          'calculateDifal': template.calculateDifal,
          'includeIpiInIcmsBase': template.includeIpiInIcmsBase,
          'addIpiToTotal': template.addIpiToTotal,
          'reduceIcmsForZfm': template.reduceIcmsForZfm,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        'Não foi possível pré-carregar os perfis nativos: ${_extractErrorMessage(error)}',
      );
    }
  }

  String? _resolveDefaultScope() {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return null;
    }
    return selected;
  }

  String _profileFingerprint({
    required String? representedCompanyId,
    required String profileKey,
  }) {
    final scope = (representedCompanyId ?? '').trim();
    return '$scope|$profileKey';
  }

  bool _matchesSelectedScope(_TaxOperationProfileEntity profile) {
    final selected = _selectedRepresentedCompanyId;
    if (selected.isEmpty) {
      return true;
    }
    final scope = (profile.representedCompanyId ?? '').trim();
    return scope.isEmpty || scope == selected;
  }

  List<_TaxOperationProfileEntity> _sortForDisplay(
    List<_TaxOperationProfileEntity> profiles,
  ) {
    final selected = _selectedRepresentedCompanyId;
    final sorted = List<_TaxOperationProfileEntity>.from(profiles);
    sorted.sort((a, b) {
      final aScope = (a.representedCompanyId ?? '').trim();
      final bScope = (b.representedCompanyId ?? '').trim();
      final aIsSelected = selected.isNotEmpty && aScope == selected;
      final bIsSelected = selected.isNotEmpty && bScope == selected;
      if (aIsSelected != bIsSelected) {
        return aIsSelected ? -1 : 1;
      }
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Stream<List<_TaxOperationProfileEntity>> _watchProfiles() {
    return _collection
        .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
        .snapshots()
        .map((snapshot) {
          final profiles = <_TaxOperationProfileEntity>[];
          for (final doc in snapshot.docs) {
            final parsed = _TaxOperationProfileEntity.fromDoc(
              doc.id,
              doc.data(),
            );
            if (parsed == null) {
              continue;
            }
            profiles.add(parsed);
          }

          final scoped = profiles
              .where(_matchesSelectedScope)
              .toList(growable: false);
          return _sortForDisplay(scoped);
        });
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );
    final representedName = (widget.activeRepresentedCompanyName ?? '').trim();
    final scopeLabel = representedName.isEmpty
        ? widget.activeTenant.tenantName
        : representedName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Perfis de operação',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use os 10 tipos nativos pré-configurados para $scopeLabel. A ligação com o código do ERP (TOP) é feita na tela de Integração ERP.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: canEditSettings && !_working
                      ? _reseedCurrentScopeDefaults
                      : null,
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('Reaplicar 10 perfis'),
                ),
              ],
            ),
            if (!canEditSettings) ...[
              const SizedBox(height: 10),
              _ownerOnlyReadOnlyNotice(
                context,
                message: 'Perfis de operação ficam em modo somente leitura para este perfil. Apenas o owner pode alterar.',
              ),
            ],
            const SizedBox(height: 14),
            StreamBuilder<List<_TaxOperationProfileEntity>>(
              stream: _watchProfiles(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Falha ao carregar perfis de operação: ${_extractErrorMessage(snapshot.error!)}',
                  );
                }

                final profiles =
                    snapshot.data ?? const <_TaxOperationProfileEntity>[];

                if (snapshot.connectionState == ConnectionState.waiting &&
                    profiles.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (profiles.isEmpty) {
                  return const Text(
                    'Nenhum perfil de operação encontrado. Clique em "Reaplicar 10 perfis" para pré-carregar os tipos nativos.',
                  );
                }

                final activeCount = profiles
                    .where((item) => item.isActive)
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip(context, 'Total: ${profiles.length}'),
                        _statusChip(context, 'Ativos: $activeCount'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        final switches = <String>[
                          if (profile.calculateIcmsSt) 'ST',
                          if (profile.calculateDifal) 'DIFAL',
                          if (profile.includeIpiInIcmsBase) 'IPI na base ICMS',
                          if (profile.addIpiToTotal) 'IPI no total',
                          if (profile.reduceIcmsForZfm) 'Desconto ICMS ZFM',
                        ];

                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              10,
                              8,
                              10,
                            ),
                            title: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statusChip(context, profile.name),
                                _statusChip(context, profile.profileKey),
                                _statusChip(
                                  context,
                                  profile.isActive ? 'Ativo' : 'Inativo',
                                ),
                                _statusChip(context, profile.scopeLabel),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [
                                  if (profile.description.trim().isNotEmpty)
                                    profile.description.trim(),
                                  'Switches: ${switches.isEmpty ? 'Nenhum' : switches.join(', ')}',
                                  'Prioridade: ${profile.priority}',
                                ].join('\n'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Editar perfil',
                              onPressed: canEditSettings && !_working
                                  ? () => _openProfileDialog(profile)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }

  Future<void> _reseedCurrentScopeDefaults() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _working = true;
    });
    try {
      await _ensureDefaults();
      _showMessage('Perfis nativos verificados/reaplicados com sucesso.');
    } catch (error) {
      _showMessage(
        'Falha ao reaplicar perfis nativos: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _openProfileDialog(_TaxOperationProfileEntity profile) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: profile.name);
    final descriptionController = TextEditingController(
      text: profile.description,
    );
    final priorityController = TextEditingController(
      text: profile.priority.toString(),
    );
    var active = profile.isActive;
    var calculateIcmsSt = profile.calculateIcmsSt;
    var calculateDifal = profile.calculateDifal;
    var includeIpiInIcmsBase = profile.includeIpiInIcmsBase;
    var addIpiToTotal = profile.addIpiToTotal;
    var reduceIcmsForZfm = profile.reduceIcmsForZfm;

    const dialogChromeColor = Color(0xFFF5F6F8);
    const dialogBodyColor = Colors.white;
    const dialogBorderColor = Color(0xFFE3E6EA);
    const dialogFocusedBorderColor = Color(0xFFD0D6DE);
    const dialogFieldVerticalGap = 14.0;

    InputDecoration dialogInputDecoration({String? hintText}) {
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: dialogBodyColor,
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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
          borderSide: const BorderSide(
            color: dialogFocusedBorderColor,
            width: 1,
          ),
        ),
      );
    }

    Widget labeledField({
      required BuildContext fieldContext,
      required String label,
      required TextEditingController controller,
      String? hintText,
      int maxLines = 1,
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
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            validator: validator,
            decoration: dialogInputDecoration(hintText: hintText),
          ),
        ],
      );
    }

    Widget labeledSwitch({
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Material(
        color: dialogBodyColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: dialogBorderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: value,
          onChanged: onChanged,
          title: Text(title),
        ),
      );
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final maxDialogHeight =
                MediaQuery.sizeOf(dialogContext).height - 36;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
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
                          'Editar perfil nativo: ${profile.profileKey}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Flexible(
                        child: Container(
                          color: dialogBodyColor,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Form(
                            key: formKey,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  labeledField(
                                    fieldContext: context,
                                    label: 'Nome do perfil *',
                                    controller: nameController,
                                    validator: (value) {
                                      if ((value ?? '').trim().isEmpty) {
                                        return 'Nome obrigatório';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  labeledField(
                                    fieldContext: context,
                                    label: 'Descrição',
                                    controller: descriptionController,
                                    maxLines: 2,
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  labeledField(
                                    fieldContext: context,
                                    label: 'Prioridade (inteiro)',
                                    controller: priorityController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9-]'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: dialogFieldVerticalGap,
                                  ),
                                  labeledSwitch(
                                    title: 'Perfil ativo',
                                    value: active,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        active = value;
                                      });
                                    },
                                  ),
                                  const Divider(height: 28),
                                  Text(
                                    'Switches de cálculo fiscal',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 10),
                                  Column(
                                    children: [
                                      labeledSwitch(
                                        title: 'Calcular ICMS-ST',
                                        value: calculateIcmsSt,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            calculateIcmsSt = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      labeledSwitch(
                                        title: 'Calcular DIFAL',
                                        value: calculateDifal,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            calculateDifal = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      labeledSwitch(
                                        title: 'IPI entra na base do ICMS',
                                        value: includeIpiInIcmsBase,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            includeIpiInIcmsBase = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      labeledSwitch(
                                        title: 'Somar IPI no total',
                                        value: addIpiToTotal,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            addIpiToTotal = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      labeledSwitch(
                                        title: 'Aplicar desconto ICMS para ZFM',
                                        value: reduceIcmsForZfm,
                                        onChanged: (value) {
                                          setDialogState(() {
                                            reduceIcmsForZfm = value;
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
                              onPressed: () async {
                                if (!(formKey.currentState?.validate() ??
                                    true)) {
                                  return;
                                }

                                try {
                                  await _collection.doc(profile.id).set({
                                    'name': nameController.text.trim(),
                                    'description': descriptionController.text
                                        .trim(),
                                    'status': active ? 'active' : 'inactive',
                                    'priority':
                                        int.tryParse(
                                          priorityController.text.trim(),
                                        ) ??
                                        profile.priority,
                                    'calculateIcmsSt': calculateIcmsSt,
                                    'calculateDifal': calculateDifal,
                                    'includeIpiInIcmsBase':
                                        includeIpiInIcmsBase,
                                    'addIpiToTotal': addIpiToTotal,
                                    'reduceIcmsForZfm': reduceIcmsForZfm,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));

                                  if (!dialogContext.mounted) {
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(true);
                                } catch (error) {
                                  if (!dialogContext.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Falha ao salvar perfil: ${_extractErrorMessage(error)}',
                                      ),
                                    ),
                                  );
                                }
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

    if (updated == true) {
      _showMessage('Perfil de operação atualizado com sucesso.');
    }
  }

  String _extractErrorMessage(Object error) {
    final text = error.toString().trim();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NativeOperationProfileTemplate {
  const _NativeOperationProfileTemplate({
    required this.key,
    required this.name,
    required this.description,
    required this.defaultPriority,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
  });

  final String key;
  final String name;
  final String description;
  final int defaultPriority;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
}

class _TaxOperationProfileEntity {
  const _TaxOperationProfileEntity({
    required this.id,
    required this.tenantId,
    required this.profileKey,
    required this.name,
    required this.description,
    required this.status,
    required this.source,
    required this.priority,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
    this.representedCompanyId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String? representedCompanyId;
  final String profileKey;
  final String name;
  final String description;
  final String status;
  final String source;
  final int priority;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status.trim().toLowerCase() == 'active';

  String get scopeLabel {
    return (representedCompanyId ?? '').trim().isEmpty
        ? 'Escopo: Global'
        : 'Escopo: Representada';
  }

  static _TaxOperationProfileEntity? fromDoc(
    String id,
    Map<String, dynamic> raw,
  ) {
    final profileKey = (raw['profileKey'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    if (profileKey.isEmpty || name.isEmpty) {
      return null;
    }

    return _TaxOperationProfileEntity(
      id: id,
      tenantId: (raw['tenantId'] ?? '').toString().trim(),
      representedCompanyId:
          (raw['representedCompanyId'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['representedCompanyId'] ?? '').toString().trim(),
      profileKey: profileKey,
      name: name,
      description: (raw['description'] ?? '').toString(),
      status: (raw['status'] ?? 'active').toString().trim().toLowerCase(),
      source: (raw['source'] ?? 'manual').toString().trim().toLowerCase(),
      priority: _readInt(raw['priority']),
      calculateIcmsSt: raw['calculateIcmsSt'] == true,
      calculateDifal: raw['calculateDifal'] == true,
      includeIpiInIcmsBase: raw['includeIpiInIcmsBase'] == true,
      addIpiToTotal: raw['addIpiToTotal'] == true,
      reduceIcmsForZfm: raw['reduceIcmsForZfm'] == true,
      createdAt: _readDateTime(raw['createdAt']),
      updatedAt: _readDateTime(raw['updatedAt']),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}
