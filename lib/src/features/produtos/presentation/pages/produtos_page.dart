import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/produto.dart';
import '../../../../core/repositories/produto_repository.dart';

class ProdutosPage extends StatelessWidget {
  const ProdutosPage({
    super.key,
    required this.identity,
    required this.repository,
  });

  final AppIdentity identity;
  final ProdutoRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Produto>>(
      stream: repository.watchAll(tenantId: identity.tenantId),
      initialData: const [],
      builder: (context, snapshot) {
        final produtos = snapshot.data ?? const [];

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderCard(
                  title: 'Produtos',
                  subtitle:
                      'Lista operacional com preco, estoque e origem por tenant.',
                  actionLabel: 'Novo produto',
                  onAction: () => _showSoon(context, 'Cadastro de produto'),
                ),
                const SizedBox(height: 16),
                if (produtos.isEmpty)
                  const _EmptyState(
                    title: 'Nenhum produto carregado',
                    subtitle:
                        'A base de produtos vai aparecer aqui quando a carga inicial entrar.',
                  )
                else
                  ...produtos.map(_ProdutoCard.new),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  const _ProdutoCard(this.produto);

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(produto.descricao),
        subtitle: Text(
          '${produto.codigoInterno} · ${produto.origemCadastro.label} · ${produto.status.label} · tabela ${produto.tabelaPrecoVersao ?? '-'}',
        ),
        trailing: Text(produto.estoqueVersao ?? '-'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}

void _showSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature ainda esta em construcao.')),
  );
}