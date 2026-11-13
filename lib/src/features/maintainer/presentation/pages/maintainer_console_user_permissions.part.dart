part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUserPermissionsPart on _MaintainerConsolePageState {
  Future<void> _openPermissionMatrixDialog(
    BuildContext context,
    MaintainerUserAccount user,
  ) async {
    final permissions = MaintainerPermission.all.toList(growable: false)
      ..sort();
    final granted = Set<String>.from(user.maintainerPermissions)
      ..retainAll(MaintainerPermission.all);
    final denied = Set<String>.from(user.maintainerDeniedPermissions)
      ..retainAll(MaintainerPermission.all);
    var maintainerRole = user.maintainerRole.trim().toLowerCase().replaceAll(
      ' ',
      '_',
    );
    if (!_MaintainerConsolePageState._maintainerRoleOptions.contains(maintainerRole)) {
      maintainerRole = 'none';
    }
    var consoleEnabled = user.maintainerConsoleEnabled;
    var mfaRequired = user.maintainerMfaRequired;
    var isSaving = false;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                'Matriz de permissoes: ${user.displayName.isEmpty ? user.uid : user.displayName}',
              ),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('UID: ${user.uid}'),
                      const SizedBox(height: 6),
                      Text('E-mail: ${user.email.isEmpty ? '--' : user.email}'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: maintainerRole,
                        decoration: const InputDecoration(
                          labelText: 'Role mantenedor (base)',
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
                        value: consoleEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Console habilitado'),
                        onChanged: (value) {
                          setLocalState(() {
                            consoleEnabled = value;
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        value: mfaRequired,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('MFA obrigatorio'),
                        onChanged: (value) {
                          setLocalState(() {
                            mfaRequired = value;
                          });
                        },
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Matriz de permissoes (Grant / Deny):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      for (final permission in permissions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(_permissionLabel(permission)),
                              ),
                              SizedBox(
                                width: 92,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: granted.contains(permission),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          if (value == true) {
                                            granted.add(permission);
                                            denied.remove(permission);
                                          } else {
                                            granted.remove(permission);
                                          }
                                        });
                                      },
                                    ),
                                    const Text('Grant'),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 92,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: denied.contains(permission),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          if (value == true) {
                                            denied.add(permission);
                                            granted.remove(permission);
                                          } else {
                                            denied.remove(permission);
                                          }
                                        });
                                      },
                                    ),
                                    const Text('Deny'),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                          setLocalState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          try {
                            await _userAdminService.saveUserProfile(
                              uid: user.uid,
                              email: user.email,
                              displayName: user.displayName,
                              platformRole: user.platformRole,
                              maintainerRole: maintainerRole,
                              activeGlobal: user.activeGlobal,
                              maintainerConsoleEnabled: consoleEnabled,
                              maintainerMfaRequired: mfaRequired,
                              maintainerPermissions: granted,
                              maintainerDeniedPermissions: denied,
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
                              errorText =
                                  'Falha ao salvar matriz de permissoes: $error';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Salvar matriz'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Matriz de permissoes atualizada.')),
      );
    }
  }
}
