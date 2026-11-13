part of 'maintainer_console_page.dart';

extension _MaintainerConsoleUserActionsPart on _MaintainerConsolePageState {
  Future<void> _onUserActionSelected(
    MaintainerUserAccount user,
    _MaintainerUserAction action, {
    required bool canManageUserCrud,
    required bool canManageUserPermissions,
    required bool canManageUserStatus,
    required bool canManageUserBilling,
  }) async {
    final actorUid = _currentActorUid();
    final actorEmail = _currentActorEmail();
    final actorLabel = _currentActorLabel();

    switch (action) {
      case _MaintainerUserAction.editProfile:
        if (!canManageUserCrud) {
          return;
        }
        await _openEditUserDialog(context, existing: user);
      case _MaintainerUserAction.editPermissionMatrix:
        if (!canManageUserPermissions) {
          return;
        }
        await _openPermissionMatrixDialog(context, user);
      case _MaintainerUserAction.deleteUser:
        if (!canManageUserCrud) {
          return;
        }
        await _confirmDeleteUser(context, user);
      case _MaintainerUserAction.toggleAccount:
        if (!canManageUserStatus) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: user.activeGlobal
              ? 'Conta desativada.'
              : 'Conta ativada.',
          action: () => _userAdminService.setGlobalActive(
            uid: user.uid,
            active: !user.activeGlobal,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.requestDeleteAccount:
        if (!canManageUserStatus) {
          return;
        }
        final reason = await _openUserLifecycleReasonDialog(
          context,
          title: 'Solicitar exclusao de conta',
          expectedPhrase: 'EXCLUIR CONTA ${user.uid}',
          helperText:
              'Digite a frase para confirmar e registrar a solicitacao.',
        );
        if (reason == null) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Solicitacao de exclusao de conta registrada.',
          action: () => _userAdminService.requestUserLifecycleAction(
            targetUid: user.uid,
            actionType: 'delete_user_account',
            reason: reason,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.grant7days:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta liberada por 7 dias.',
          action: () => _userAdminService.grantGracePeriod(
            uid: user.uid,
            duration: const Duration(days: 7),
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.grant30days:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta liberada por 30 dias.',
          action: () => _userAdminService.grantGracePeriod(
            uid: user.uid,
            duration: const Duration(days: 30),
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.normalizeBilling:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Billing normalizado para ativo.',
          action: () => _userAdminService.normalizeBilling(
            uid: user.uid,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
      case _MaintainerUserAction.suspendBilling:
        if (!canManageUserBilling) {
          return;
        }
        await _runUserAction(
          user.uid,
          successMessage: 'Conta marcada como suspensa.',
          action: () => _userAdminService.suspendBilling(
            uid: user.uid,
            actorUid: actorUid,
            actorEmail: actorEmail,
            actorLabel: actorLabel,
          ),
        );
    }
  }

  Future<void> _runUserAction(
    String uid, {
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    _markUserProcessing(uid);

    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar usuario: $error')),
      );
    } finally {
      _unmarkUserProcessing(uid);
    }
  }

  Future<String?> _openUserLifecycleReasonDialog(
    BuildContext context, {
    required String title,
    required String expectedPhrase,
    required String helperText,
  }) async {
    final phraseController = TextEditingController();
    final reasonController = TextEditingController();

    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(helperText),
                  const SizedBox(height: 8),
                  SelectableText(
                    expectedPhrase,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phraseController,
                    decoration: const InputDecoration(
                      labelText: 'Frase de confirmacao',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo (obrigatorio)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final typedPhrase = phraseController.text.trim();
                  final reason = reasonController.text.trim();
                  if (typedPhrase != expectedPhrase) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Frase de confirmacao invalida.'),
                      ),
                    );
                    return;
                  }
                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Informe o motivo.')),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(reason);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );

      final normalized = (result ?? '').trim();
      return normalized.isEmpty ? null : normalized;
    } finally {
      phraseController.dispose();
      reasonController.dispose();
    }
  }
}
