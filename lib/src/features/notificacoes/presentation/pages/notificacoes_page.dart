import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/tenant_invitation.dart';
import '../../../../shared/domain/date_time_label.dart';
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

  String _invitationAccordionSubtitle({
    required ConnectionState state,
    required int count,
  }) {
    if (state == ConnectionState.waiting) {
      return 'Carregando...';
    }
    if (count == 0) {
      return 'Sem convites pendentes';
    }
    if (count == 1) {
      return '1 convite pendente';
    }
    return '$count convites pendentes';
  }

  Widget _buildInvitationsAccordion(String email) {
    if (email.isEmpty) {
      return const Card(
        child: ExpansionTile(
          leading: Icon(Icons.mail_outline),
          title: Text('Convites'),
          subtitle: Text('Sem e-mail autenticado'),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Nao foi possivel identificar convites para esta sessao.',
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<TenantInvitation>>(
      stream: _invitationService.watchPendingInvitationsForEmail(email),
      builder: (context, snapshot) {
        final invitations = snapshot.data ?? const <TenantInvitation>[];
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.mail_outline),
            initiallyExpanded: invitations.isNotEmpty,
            title: const Text('Convites'),
            subtitle: Text(
              _invitationAccordionSubtitle(
                state: snapshot.connectionState,
                count: invitations.length,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (invitations.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nenhum convite novo no momento.'),
                )
              else
                ...invitations.map(
                  (invitation) => _InvitationCard(
                    invitation: invitation,
                    processing: _processingToken == invitation.token,
                    onAccept: () => _acceptInvite(invitation),
                    onDecline: () => _declineInvite(invitation),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGeneralNotificationsAccordion() {
    return const Card(
      child: ExpansionTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: Text('Outras notificacoes'),
        subtitle: Text('Comunicados da representada e da equipe'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Informacoes da representada'),
            subtitle: Text('Sem novas informacoes.'),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Mensagens do owner para equipe'),
            subtitle: Text('Sem novos comunicados.'),
          ),
        ],
      ),
    );
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
            const SizedBox(height: 16),
            _buildInvitationsAccordion(email),
            const SizedBox(height: 12),
            _buildGeneralNotificationsAccordion(),
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
      margin: const EdgeInsets.only(bottom: 10),
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
