part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUserDialogs on _MaintainerConsolePageState {
  Future<void> _openEditUserDialog(
    BuildContext context, {
    MaintainerUserAccount? existing,
  }) async {
    final uidController = TextEditingController(text: existing?.uid ?? '');
    final emailController = TextEditingController(text: existing?.email ?? '');
    final displayNameController = TextEditingController(
      text: existing?.displayName ?? '',
    );
    var platformRole = (existing?.platformRole ?? 'none').trim().toLowerCase();
    if (platformRole != 'platform_admin') {
      platformRole = 'none';
    }
    var maintainerRole = (existing?.maintainerRole ?? 'none')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    if (!_MaintainerConsolePageState._maintainerRoleOptions.contains(maintainerRole)) {
      maintainerRole = 'none';
    }
    var activeGlobal = existing?.activeGlobal ?? true;
    var consoleEnabled = existing?.maintainerConsoleEnabled ?? true;
    var mfaRequired = existing?.maintainerMfaRequired ?? false;
    final grantedPermissions = Set<String>.from(
      existing?.maintainerPermissions ?? const <String>{},
    );
    final deniedPermissions = Set<String>.from(
      existing?.maintainerDeniedPermissions ?? const <String>{},
    );
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Novo usuario' : 'Editar cadastro',
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: uidController,
                        enabled: existing == null,
                        decoration: const InputDecoration(
                          labelText: 'UID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome exibicao',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: platformRole,
                        decoration: const InputDecoration(
                          labelText: 'Platform role (regras Firestore)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('none')),
                          DropdownMenuItem(
                            value: 'platform_admin',
                            child: Text('platform_admin'),
                          ),
                        ],
                        onChanged: (value) {
                          setLocalState(() {
                            platformRole = (value ?? 'none').trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: maintainerRole,
                        decoration: const InputDecoration(
                          labelText: 'Role mantenedor (base de permissoes)',
                          border: OutlineInputBorder(),
                        ),
                        items: _MaintainerConsolePageState._maintainerRoleOptions
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setLocalState(() {
                            maintainerRole = (value ?? 'none')
                                .trim()
                                .toLowerCase();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: activeGlobal,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Conta global ativa (ativoGlobal)'),
                        onChanged: (value) {
                          setLocalState(() {
                            activeGlobal = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: consoleEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Console de mantenedor habilitado'),
                        onChanged: (value) {
                          setLocalState(() {
                            consoleEnabled = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: mfaRequired,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Exigir MFA no mantenedor'),
                        onChanged: (value) {
                          setLocalState(() {
                            mfaRequired = value;
                          });
                        },
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final uid = uidController.text.trim();
                          if (uid.isEmpty) {
                            setLocalState(() {
                              errorText = 'UID e obrigatorio.';
                            });
                            return;
                          }

                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          try {
                            await _userAdminService.saveUserProfile(
                              uid: uid,
                              email: emailController.text.trim(),
                              displayName: displayNameController.text.trim(),
                              platformRole: platformRole,
                              maintainerRole: maintainerRole,
                              activeGlobal: activeGlobal,
                              maintainerConsoleEnabled: consoleEnabled,
                              maintainerMfaRequired: mfaRequired,
                              maintainerPermissions: grantedPermissions,
                              maintainerDeniedPermissions: deniedPermissions,
                              isCreate: existing == null,
                              actorUid: _currentActorUid(),
                              actorEmail: _currentActorEmail(),
                              actorLabel: _currentActorLabel(),
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop(true);
                          } catch (error) {
                            setLocalState(() {
                              errorText = 'Falha ao salvar usuario: $error';
                              isSaving = false;
                            });
                          }
                        },
                  child: Text(existing == null ? 'Criar usuario' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeTextEditingControllersSafely([
      uidController,
      emailController,
      displayNameController,
    ]);

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Usuario criado/atualizado com sucesso.'
                : 'Cadastro atualizado com sucesso.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    MaintainerUserAccount user,
  ) async {
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (currentUid.isNotEmpty && currentUid == user.uid.trim()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Por seguranca, nao e permitido excluir a propria conta administrativa.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir usuario'),
          content: Text(
            'Deseja excluir o cadastro de ${user.displayName.isEmpty ? user.uid : user.displayName} (${user.uid})? Esta acao remove o documento em usuarios/{uid}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _runUserAction(
      user.uid,
      successMessage: 'Usuario excluido com sucesso.',
      action: () => _userAdminService.deleteUser(
        user.uid,
        actorUid: _currentActorUid(),
        actorEmail: _currentActorEmail(),
        actorLabel: _currentActorLabel(),
      ),
    );
  }

}
