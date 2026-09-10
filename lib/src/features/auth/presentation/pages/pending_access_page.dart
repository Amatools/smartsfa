import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/access_request.dart';
import '../../services/access_request_service.dart';
import '../../services/solo_workspace_service.dart';
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
  final TextEditingController _workspaceNameController = TextEditingController();
  final TextEditingController _cnpjController = TextEditingController();
  _OnboardingChoice _choice = _OnboardingChoice.solo;

  @override
  void dispose() {
    _inviteTokenController.dispose();
    _workspaceNameController.dispose();
    _cnpjController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _workspaceNameController.text = _defaultWorkspaceName;
    _loadCurrentRequest();
  }

  String get _defaultWorkspaceName {
    final displayName = (widget.user.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return '$displayName Negocios';
    }

    final email = (widget.user.email ?? '').trim();
    if (email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Meu Workspace';
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

  Future<void> _createSoloWorkspace() async {
    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      await SoloWorkspaceService(FirebaseFirestore.instance)
          .createOwnerWorkspace(
            user: widget.user,
            plan: OnboardingPlan.solo,
            workspaceName: _workspaceNameController.text,
          );

      setState(() {
        _message =
            'Workspace solo criado com sucesso. Entrando como owner...';
      });

      widget.onAccessUpdated?.call();
    } catch (_) {
      setState(() {
        _message =
            'Nao foi possivel criar workspace solo agora. Tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _createTeamOrEnterpriseWorkspace(
    OnboardingPlan plan,
  ) async {
    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      await SoloWorkspaceService(FirebaseFirestore.instance).createOwnerWorkspace(
        user: widget.user,
        plan: plan,
        workspaceName: _workspaceNameController.text,
        cnpj: _cnpjController.text,
      );

      setState(() {
        _message = 'Workspace criado com sucesso. Entrando como owner...';
      });

      widget.onAccessUpdated?.call();
    } on StateError catch (error) {
      setState(() {
        _message = error.message.toString();
      });
    } catch (_) {
      setState(() {
        _message = 'Nao foi possivel criar workspace agora. Tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _selectChoice(_OnboardingChoice value) {
    setState(() {
      _choice = value;
      _message = null;
    });
  }

  Widget _buildChoiceChip({
    required _OnboardingChoice value,
    required String label,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: _choice == value,
      onSelected: (_) => _selectChoice(value),
    );
  }

  Widget _buildChoiceSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChoiceChip(value: _OnboardingChoice.solo, label: 'Plano Solo'),
        _buildChoiceChip(value: _OnboardingChoice.team, label: 'Plano Team'),
        _buildChoiceChip(
          value: _OnboardingChoice.enterprise,
          label: 'Plano Enterprise',
        ),
        _buildChoiceChip(
          value: _OnboardingChoice.invite,
          label: 'Entrar com convite',
        ),
      ],
    );
  }

  Widget _buildInvitePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _buildWorkspacePanel() {
    final isSolo = _choice == _OnboardingChoice.solo;
    final plan = _choice == _OnboardingChoice.enterprise
        ? OnboardingPlan.enterprise
        : _choice == _OnboardingChoice.team
        ? OnboardingPlan.team
        : OnboardingPlan.solo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _workspaceNameController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: isSolo ? 'Nome do seu workspace' : 'Nome da empresa',
          ),
        ),
        if (!isSolo) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _cnpjController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'CNPJ (opcional neste momento)',
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          isSolo
              ? 'Voce entrara como owner do seu workspace solo.'
              : 'Voce entrara como owner do tenant criado para sua empresa.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _sending
              ? null
              : () {
                  if (isSolo) {
                    _createSoloWorkspace();
                    return;
                  }
                  _createTeamOrEnterpriseWorkspace(plan);
                },
          icon: const Icon(Icons.business_center_outlined),
          label: Text(
            _sending
                ? 'Criando workspace...'
                : isSolo
                ? 'Criar workspace solo (owner)'
                : 'Criar empresa e continuar',
          ),
        ),
      ],
    );
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
                  'Primeiro acesso ao Smart SFA',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('Usuario: ${widget.user.email ?? widget.user.uid}'),
                const SizedBox(height: 8),
                Text(
                  'Escolha como deseja entrar: conta solo, criar empresa, ou convite.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                _buildChoiceSection(),
                const SizedBox(height: 8),
                if (_choice == _OnboardingChoice.invite)
                  _buildInvitePanel()
                else
                  _buildWorkspacePanel(),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _sending ? null : _requestAccess,
                  child: Text(_sending
                      ? 'Enviando solicitacao...'
                      : 'Solicitar liberacao interna (suporte)'),
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

enum _OnboardingChoice {
  solo,
  team,
  enterprise,
  invite,
}