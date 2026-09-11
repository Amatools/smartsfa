import 'package:flutter/material.dart';

import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
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
                      'Cadastro completo com visual resumido na lista e detalhes em abas ao abrir.',
                  actionLabel: 'Novo produto',
                  onAction: () => _openProductSheet(context),
                ),
                const SizedBox(height: 16),
                if (produtos.isEmpty)
                  const _EmptyState(
                    title: 'Nenhum produto carregado',
                    subtitle:
                        'A base de produtos vai aparecer aqui quando a carga inicial entrar.',
                  )
                else
                  ...produtos.map(
                    (produto) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ProdutoSummaryCard(
                        produto: produto,
                        onTap: () => _openProductSheet(context, produto: produto),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void _openProductSheet(BuildContext context, {Produto? produto}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final draft = produto ?? _emptyDraft();

      return DefaultTabController(
        length: 3,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            produto == null ? 'Novo produto' : 'Produto completo',
                            style: Theme.of(sheetContext).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            produto == null
                                ? 'Criação com abas de informações gerais, valores e impostos.'
                                : '${produto.codigoInterno} · ${produto.descricao}',
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.info_outline), text: 'Geral'),
                    Tab(icon: Icon(Icons.attach_money), text: 'Valores e impostos'),
                    Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Estoque e integração'),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ProductGeneralTab(produto: draft),
                      _ProductValuesTab(produto: draft),
                      _ProductStockTab(produto: draft),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showSoon(sheetContext, 'Salvar produto'),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar rascunho'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _showSoon(sheetContext, 'Publicar produto'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Publicar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Produto _emptyDraft() {
  return const Produto(
    id: 'draft',
    tenantId: 'draft',
    codigoInterno: 'NOVO-001',
    descricao: 'Novo produto',
    origemCadastro: ProductSource.manual,
    status: ProductStatus.active,
    descricaoResumida: 'Descrição resumida do novo produto.',
    valorBruto: 0,
    unidade: 'UN',
    ncm: '0000.00.00',
    cfop: '5102',
    aliquotaIcms: 0,
    aliquotaPis: 0,
    aliquotaCofins: 0,
    pesoKg: 0,
    tabelaPrecoVersao: 'rascunho',
    estoqueVersao: 'rascunho',
  );
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

class _ProdutoSummaryCard extends StatelessWidget {
  const _ProdutoSummaryCard({
    required this.produto,
    required this.onTap,
  });

  final Produto produto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductThumbnail(produto: produto),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${produto.codigoInterno} - ${produto.descricao}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          _formatCurrency(produto.valorBruto),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      produto.descricaoResumida ??
                          'Cadastro completo com valores, impostos, estoque e origem.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(label: produto.origemCadastro.label),
                        _InfoChip(label: produto.status.label),
                        _InfoChip(label: produto.unidade ?? '-'),
                        _InfoChip(label: 'NCM ${produto.ncm ?? '-'}'),
                        _InfoChip(label: 'CFOP ${produto.cfop ?? '-'}'),
                        _InfoChip(label: 'Tabela ${produto.tabelaPrecoVersao ?? '-'}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    final photoUrl = produto.fotoUrl?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 84,
        height: 84,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: photoUrl == null || photoUrl.isEmpty
            ? Center(
                child: Text(
                  produto.descricao.isNotEmpty ? produto.descricao[0].toUpperCase() : '?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              )
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    produto.descricao.isNotEmpty ? produto.descricao[0].toUpperCase() : '?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ProductGeneralTab extends StatelessWidget {
  const _ProductGeneralTab({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _TabSectionCard(
          title: 'Informações gerais',
          children: [
            _FieldLine(label: 'Código interno', value: produto.codigoInterno),
            _FieldLine(label: 'Descrição', value: produto.descricao),
            _FieldLine(label: 'Descrição resumida', value: produto.descricaoResumida),
            _FieldLine(label: 'Unidade', value: produto.unidade),
            _FieldLine(label: 'Origem', value: produto.origemCadastro.label),
            _FieldLine(label: 'Status', value: produto.status.label),
            _FieldLine(label: 'Peso líquido', value: _formatWeight(produto.pesoKg)),
          ],
        ),
        const SizedBox(height: 12),
        _TabSectionCard(
          title: 'Imagem e apresentação',
          children: [
            _FieldLine(label: 'Foto', value: produto.fotoUrl ?? 'Sem imagem'),
            const SizedBox(height: 8),
            if ((produto.fotoUrl ?? '').isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  produto.fotoUrl!,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProductValuesTab extends StatelessWidget {
  const _ProductValuesTab({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _TabSectionCard(
          title: 'Valores',
          children: [
            _FieldLine(label: 'Valor bruto', value: _formatCurrency(produto.valorBruto)),
            _FieldLine(label: 'Tabela de preço', value: produto.tabelaPrecoVersao),
            _FieldLine(label: 'Versão de estoque', value: produto.estoqueVersao),
          ],
        ),
        const SizedBox(height: 12),
        _TabSectionCard(
          title: 'Impostos',
          children: [
            _FieldLine(label: 'NCM', value: produto.ncm),
            _FieldLine(label: 'CFOP', value: produto.cfop),
            _FieldLine(label: 'ICMS', value: _formatPercent(produto.aliquotaIcms)),
            _FieldLine(label: 'PIS', value: _formatPercent(produto.aliquotaPis)),
            _FieldLine(label: 'COFINS', value: _formatPercent(produto.aliquotaCofins)),
          ],
        ),
      ],
    );
  }
}

class _ProductStockTab extends StatelessWidget {
  const _ProductStockTab({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _TabSectionCard(
          title: 'Estoque e integração',
          children: [
            _FieldLine(label: 'Versão de estoque', value: produto.estoqueVersao),
            _FieldLine(label: 'Versão da tabela', value: produto.tabelaPrecoVersao),
            _FieldLine(label: 'Integração ERP', value: produto.origemCadastro == ProductSource.erp ? 'Sincronizado com ERP' : 'Cadastro manual'),
            _FieldLine(
              label: 'Notas',
              value:
                  'Aqui entram regras de sincronização, disponibilidade e origem do dado para todos os membros.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TabSectionCard(
          title: 'Criação e publicação',
          children: const [
            _FieldLine(
              label: 'Fluxo sugerido',
              value: 'Geral > Valores e impostos > Estoque e integração',
            ),
            _FieldLine(
              label: 'Publicação',
              value: 'Pode ser salvo como rascunho e depois publicado',
            ),
          ],
        ),
      ],
    );
  }
}

class _TabSectionCard extends StatelessWidget {
  const _TabSectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(value?.isNotEmpty == true ? value! : '-'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
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

String _formatCurrency(double? value) {
  if (value == null) {
    return '-';
  }

  return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

String _formatPercent(double? value) {
  if (value == null) {
    return '-';
  }

  return '${value.toStringAsFixed(value == value.truncateToDouble() ? 0 : 2).replaceAll('.', ',')}%';
}

String _formatWeight(double? value) {
  if (value == null) {
    return '-';
  }

  return '${value.toStringAsFixed(3).replaceAll('.', ',')} kg';
}
