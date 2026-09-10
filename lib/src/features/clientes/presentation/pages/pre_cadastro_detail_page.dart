import 'package:flutter/material.dart';

import '../../../../core/models/cliente_pre_cadastro.dart';
import '../../../../core/models/domain_types.dart';

/// Full-screen, read-only view of every field captured on a pre-cadastro.
/// Shows an "Aprovar" action at the bottom when [canApprove] is true and the
/// record is not already approved.
class PreCadastroDetailPage extends StatelessWidget {
  const PreCadastroDetailPage({
    super.key,
    required this.item,
    required this.isSyncedRemotely,
    required this.canApprove,
    required this.onApprove,
    this.canCancel = false,
    this.onCancel,
  });

  final ClientePreCadastro item;
  final bool isSyncedRemotely;
  final bool canApprove;
  final Future<void> Function() onApprove;
  final bool canCancel;
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final canShowApprove = item.status == PreRegistrationStatus.pending;

    return Scaffold(
      appBar: AppBar(title: Text(item.nome)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: isSyncedRemotely
                        ? 'Sincronizado com Firebase'
                        : 'Local • pendente sync',
                    color: isSyncedRemotely
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                  ),
                  _StatusChip(
                    label: item.status.label,
                    color: Colors.blueGrey.shade100,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Identificação',
                fields: {
                  'Nome / razão social': item.nome,
                  'Nome fantasia': item.nomeFantasia,
                  'Tipo de pessoa': item.tipoPessoa == 'pf' ? 'Pessoa física' : 'Pessoa jurídica',
                  'CPF / CNPJ': item.documento,
                  'Inscrição estadual': item.inscricaoEstadual,
                  'Inscrição municipal': item.inscricaoMunicipal,
                },
              ),
              _Section(
                title: 'Contato',
                fields: {
                  'E-mail': item.email,
                  'E-mail financeiro': item.emailFinanceiro,
                  'Celular': item.celular,
                  'Telefone': item.telefone,
                },
              ),
              _Section(
                title: 'Endereço',
                fields: {
                  'CEP': item.cep,
                  'Logradouro': item.logradouro,
                  'Número': item.numero,
                  'Complemento': item.complemento,
                  'Bairro': item.bairro,
                  'Cidade': item.cidade,
                  'Estado': item.estado,
                  'País': item.pais,
                },
              ),
              _Section(
                title: 'Cadastro',
                fields: {
                  'Canal': item.canal,
                  'Origem do cadastro': item.origemCadastro.label,
                  'Solicitado por': item.requestedByUid,
                  'Criado em': _formatDate(item.createdAt),
                  'Atualizado em': _formatDate(item.updatedAt),
                  'Observações': item.observacoes,
                },
              ),
              if (canApprove && canShowApprove) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await onApprove();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Aprovar pré-cadastro'),
                  ),
                ),
              ],
              if (canCancel && onCancel != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error),
                    ),
                    onPressed: () async {
                      await onCancel!();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancelar / excluir pré-cadastro'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return '—';
    }
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.fields});

  final String title;
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...fields.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        entry.value.isEmpty ? '—' : entry.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
