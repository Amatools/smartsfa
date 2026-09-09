import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/access_request.dart';
import '../../services/access_request_service.dart';
import '../../services/tenant_invitation_service.dart';

class PendingAccessPage extends StatefulWidget {
  const PendingAccessPage({
    super.key,
    required this.user,
    this.onAccessUpdated,
  });

  final User user;
  final VoidCallback? onAccessUpdated;

  @override
  State<PendingAccessPage> createState() => _PendingAccessPageState();
}

class _PendingAccessPageState extends State<PendingAccessPage> {
  bool _sending = false;
  String? _message;
  AccessRequest? _currentRequest;
  final TextEditingController _inviteTokenController = TextEditingController();

  @override
  void dispose() {
    _inviteTokenController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentRequest();
  }

  Future<void> _loadCurrentRequest() async {
    final request = await AccessRequestService(FirebaseFirestore.instance)
        .load(widget.user);
    if (!mounted) {
      return;
    }

    setState(() {
      _currentRequest = request;
    });
  }

  Future<void> _requestAccess() async {
    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      final request = await AccessRequestService(FirebaseFirestore.instance)
          .upsertPending(user: widget.user);

      setState(() {
        _currentRequest = request;
        _message = 'Solicitacao enviada. Aguarde a liberacao de acesso interno.';
      });
    } catch (_) {
      setState(() {
        _message = 'Nao foi possivel enviar a solicitacao agora.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _acceptInvite() async {
    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      final token = _inviteTokenController.text.trim();
      if (token.isEmpty) {
        throw StateError('Informe um token de convite valido.');
      }

      await TenantInvitationService(FirebaseFirestore.instance).acceptInvitation(
        user: widget.user,
        token: token,
      );

      setState(() {
        _message =
            'Convite aceito com sucesso. Validando novo acesso ao tenant...';
      });

      widget.onAccessUpdated?.call();
    } catch (error) {
      setState(() {
        _message = error is StateError
            ? error.message.toString()
            : 'Nao foi possivel aceitar o convite agora.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conta autenticada sem permissao',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('Usuario: ${widget.user.email ?? widget.user.uid}'),
                if (_currentRequest != null) ...[
                  const SizedBox(height: 12),
                  Text('Status atual: ${_currentRequest!.status.label}'),
                  if (_currentRequest!.tenantSlugOuConvite != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Vinculo solicitado: ${_currentRequest!.tenantSlugOuConvite}',
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _inviteTokenController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Token de convite',
                    hintText: 'Ex: 4F7A-9D2B-ABCD',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _sending ? null : _acceptInvite,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: Text(_sending ? 'Validando convite...' : 'Entrar com convite'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _requestAccess,
                  child: Text(_sending
                      ? 'Enviando solicitacao...'
                      : 'Solicitar liberacao interna'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sair'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}