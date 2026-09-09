import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_invitation.dart';
import '../../../../shared/domain/date_time_label.dart';
import '../../../../shared/presentation/widgets/app_info_card.dart';
import '../../../auth/services/tenant_invitation_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../controllers/notification_invitation_action_controller.dart';

class NotificacoesPage extends StatefulWidget {
  const NotificacoesPage({
    super.key,
    required this.identity,
    this.onAccessUpdated,
  });

  final AppIdentity identity;
  final VoidCallback? onAccessUpdated;

  @override
  State<NotificacoesPage> createState() => _NotificacoesPageState();
}

class _NotificacoesPageState extends State<NotificacoesPage> {
  String? _processingToken;

  TenantInvitationService get _invitationService =>
      TenantInvitationService(FirebaseFirestore.instance);

  NotificationInvitationActionController get _actions =>
      NotificationInvitationActionController(_invitationService);

  Future<void> _acceptInvite(TenantInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _processingToken = invitation.token;
    });

    try {
      await _actions.acceptInvitation(user: user, token: invitation.token);
      _showMessage('Convite aceito. Atualizando acessos da conta...');
      widget.onAccessUpdated?.call();
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Nao foi possivel aceitar o convite agora.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingToken = null;
        });
      }
    }
  }

  Future<void> _declineInvite(TenantInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sessao expirada. Faca login novamente.');
      return;
    }

    setState(() {
      _processingToken = invitation.token;
    });

    try {
      await _actions.declineInvitation(
        token: invitation.token,
        declinedByUid: user.uid,
      );
      _showMessage('Convite recusado.');
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'Nao foi possivel recusar o convite agora.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingToken = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase() ?? '';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notificacoes',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Convites pendentes para ${widget.identity.userLabel}.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta tela e apenas para aceitar ou recusar convites pessoais. O envio e gerenciamento ficam no modulo Tenant.',
            ),
            const SizedBox(height: 16),
            if (widget.identity.isMock)
              const AppInfoCard(
                title: 'Modo mock',
                subtitle: 'No modo mock, notificacoes reais de convite nao sao carregadas.',
              )
            else if (email.isEmpty)
              const AppInfoCard(
                title: 'Sem e-mail autenticado',
                subtitle: 'Nao foi possivel identificar convites para a sessao atual.',
              )
            else
              StreamBuilder<List<TenantInvitation>>(
                stream: _invitationService.watchPendingInvitationsForEmail(
                  email,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppInfoCard(
                      title: 'Carregando notificacoes',
                      subtitle: 'Buscando convites pendentes...',
                    );
                  }

                  final invitations = snapshot.data ?? const [];
                  if (invitations.isEmpty) {
                    return const AppInfoCard(
                      title: 'Sem convites pendentes',
                      subtitle: 'Quando um owner enviar convite para seu e-mail, ele aparece aqui.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: invitations
                        .map(
                          (invitation) => _InvitationCard(
                            invitation: invitation,
                            processing: _processingToken == invitation.token,
                            onAccept: () => _acceptInvite(invitation),
                            onDecline: () => _declineInvite(invitation),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
  });

  final TenantInvitation invitation;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Convite para tenant ${invitation.tenantId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Perfil: ${invitation.role}'),
            const SizedBox(height: 6),
            Text('Status: ${invitation.status.label}'),
            if (invitation.expiresAt != null) ...[
              const SizedBox(height: 6),
              Text('Expira em: ${formatDateTimeLabel(invitation.expiresAt!)}'),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: processing ? null : onAccept,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(processing ? 'Aceitando...' : 'Aceitar convite'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: processing ? null : onDecline,
              icon: const Icon(Icons.close),
              label: const Text('Recusar convite'),
            ),
          ],
        ),
      ),
    );
  }
}
