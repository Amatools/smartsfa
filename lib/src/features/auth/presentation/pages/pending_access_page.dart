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
  _OnboardingChoice _choice = _OnboardingChoice.sellerSolo;

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

  Stream<AccountContractLock> get _accountContractLockStream {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.user.uid)
        .snapshots()
        .map(
          (doc) => AccountContractLock.fromValue(
            (doc.data()?['accountContractLock'] ?? '').toString().trim(),
          ),
        );
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
      final shouldClearPendingRequest = _currentRequest != null;
      await SoloWorkspaceService(FirebaseFirestore.instance)
          .createOwnerWorkspace(
            user: widget.user,
            plan: OnboardingPlan.solo,
            workspaceType: WorkspaceType.sellerSoloWorkspace,
            workspaceName: _workspaceNameController.text,
            clearPendingRequest: shouldClearPendingRequest,
          );

      setState(() {
        _message =
        'Workspace vendedor solo criado com sucesso. Entrando no contexto privado...';
      });

      widget.onAccessUpdated?.call();
    } on FirebaseException catch (error) {
      setState(() {
        _message = 'Erro Firebase (${error.code}): ${error.message ?? 'falha ao criar workspace solo.'}';
      });
    } catch (error) {
      setState(() {
        _message = error is StateError
            ? error.message.toString()
            : 'Nao foi possivel criar workspace solo agora. Tente novamente.';
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
    WorkspaceType workspaceType,
  ) async {
    setState(() {
      _sending = true;
      _message = null;
    });

    try {
      final shouldClearPendingRequest = _currentRequest != null;
      await SoloWorkspaceService(FirebaseFirestore.instance).createOwnerWorkspace(
        user: widget.user,
        plan: plan,
        workspaceType: workspaceType,
        workspaceName: _workspaceNameController.text,
        cnpj: _cnpjController.text,
        clearPendingRequest: shouldClearPendingRequest,
      );

      setState(() {
        _message = 'Workspace criado com sucesso. Entrando no tenant...';
      });

      widget.onAccessUpdated?.call();
    } on StateError catch (error) {
      setState(() {
        _message = error.message.toString();
      });
    } on FirebaseException catch (error) {
      setState(() {
        _message = 'Erro Firebase (${error.code}): ${error.message ?? 'falha ao criar workspace.'}';
      });
    } catch (error) {
      setState(() {
        _message = error is StateError
            ? error.message.toString()
            : 'Nao foi possivel criar workspace agora. Tente novamente.';
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

  Widget _buildChoiceCard({
    required _OnboardingChoice value,
    required String title,
    required String subtitle,
  }) {
    final selected = _choice == value;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _selectChoice(value),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? colorScheme.primaryContainer.withAlpha(90)
              : colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceSection() {
    return StreamBuilder<AccountContractLock>(
      stream: _accountContractLockStream,
      builder: (context, snapshot) {
        final accountContractLock =
            snapshot.data ?? AccountContractLock.flexible;
        final canCreateFlexibleWorkspaces =
            accountContractLock != AccountContractLock.enterpriseOnly;

        if (!canCreateFlexibleWorkspaces &&
            (_choice == _OnboardingChoice.sellerSolo ||
                _choice == _OnboardingChoice.repWorkspace)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _choice = _OnboardingChoice.brandOwner;
            });
          });
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (canCreateFlexibleWorkspaces)
              _buildChoiceCard(
                value: _OnboardingChoice.sellerSolo,
                title: 'Individual',
                subtitle: 'Base privada sem equipe e sem interligacao com outros usuarios.',
              ),
            if (canCreateFlexibleWorkspaces)
              _buildChoiceCard(
                value: _OnboardingChoice.repWorkspace,
                title: 'Representacoes',
                subtitle: 'Representante opera base propria e pode convidar vendedores.',
              ),
            _buildChoiceCard(
              value: _OnboardingChoice.brandOwner,
              title: 'Empresa',
              subtitle: 'Tenant oficial da marca com CNPJ e cadeia completa de acesso.',
            ),
            _buildChoiceCard(
              value: _OnboardingChoice.invite,
              title: 'Entrar com convite',
              subtitle: 'Use o token recebido para entrar em um tenant existente.',
            ),
          ],
        );
      },
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
    final isSellerSolo = _choice == _OnboardingChoice.sellerSolo;
    final isBrandOwner = _choice == _OnboardingChoice.brandOwner;
    final plan = isBrandOwner
      ? OnboardingPlan.enterprise
      : isSellerSolo
      ? OnboardingPlan.solo
      : OnboardingPlan.team;
    final workspaceType = isBrandOwner
      ? WorkspaceType.brandOwnerWorkspace
      : isSellerSolo
      ? WorkspaceType.sellerSoloWorkspace
      : WorkspaceType.repWorkspace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _workspaceNameController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: isBrandOwner
                ? 'Nome da empresa contratante'
                : 'Nome interno do workspace',
          ),
        ),
        if (!isSellerSolo) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _cnpjController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: isBrandOwner
                  ? 'CNPJ da empresa contratante'
                  : 'CNPJ da representada (informativo)',
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          isBrandOwner
              ? 'Conta oficial da empresa contratante com cadeia completa de acesso.'
              : isSellerSolo
              ? 'Workspace individual com base privada e sem equipe vinculada.'
              : 'Workspace de representacoes com base propria e equipe comercial vinculada.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _sending
              ? null
              : () {
                  if (isSellerSolo) {
                    _createSoloWorkspace();
                    return;
                  }
                  _createTeamOrEnterpriseWorkspace(plan, workspaceType);
                },
          icon: const Icon(Icons.business_center_outlined),
          label: Text(
            _sending
                ? 'Criando workspace...'
                : isSellerSolo
                ? 'Criar workspace Individual'
                : isBrandOwner
                ? 'Criar workspace Empresa'
                : 'Criar workspace Representacoes',
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
                  'Escolha como deseja entrar: workspace Individual, Representacoes, Empresa ou convite.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                StreamBuilder<AccountContractLock>(
                  stream: _accountContractLockStream,
                  builder: (context, snapshot) {
                    final accountContractLock =
                        snapshot.data ?? AccountContractLock.flexible;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        accountContractLock == AccountContractLock.enterpriseOnly
                          ? 'Tipo de conta: Conta BrandOp. Este login so pode operar no contexto oficial da empresa contratante.'
                          : 'Tipo de conta: Conta MultiOp. Este login pode reunir workspace Individual, Representacoes e acessos convidados.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
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
  sellerSolo,
  repWorkspace,
  brandOwner,
  invite,
}