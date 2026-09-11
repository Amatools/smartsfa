import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/in_memory/demo_workspace.dart';
import '../../../../core/models/app_identity.dart';
import '../../../produtos/presentation/pages/produtos_page.dart';

class CatalogPreviewPage extends StatelessWidget {
  const CatalogPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    const identity = AppIdentity(
      tenantId: 'preview-tenant',
      userLabel: 'Preview local',
      role: 'owner',
      tenantName: 'Visualizacao local',
      isMock: true,
      isPersonalWorkspace: false,
    );

    final workspace = DemoWorkspace.seeded(identity);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF6F8FA), Color(0xFFE8F2EE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pré-visualização de catálogo',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Abra esta tela com ?preview=catalogs para ver Produtos e tabelas de preço sem autenticacao.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Modo preview'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Produtos'),
                      Tab(icon: Icon(Icons.price_change_outlined), text: 'Tabelas de preço'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      ProdutosPage(
                        identity: identity,
                        repository: workspace.produtos,
                      ),
                      const _PricesPreviewPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PricesPreviewPage extends StatelessWidget {
  const _PricesPreviewPage();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tabelas de preço', style: textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                      'Exemplo de tela separada para tabelas de preço, sem misturar com o cadastro base do produto.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _openPreviewPriceImport(context),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Importar planilha Excel'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showPreviewSoon(context, 'Vincular a cliente ou região'),
                          icon: const Icon(Icons.link_outlined),
                          label: const Text('Vínculo opcional'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _PriceRuleCard(
              title: 'Tabela atacado / canal representante',
              subtitle: 'Preço bruto, desconto e vigência por volume ou canal.',
              chips: ['Bruto: R\$ 129,90', 'Desconto: 8%', 'Vigência: 2026.09'],
            ),
            const SizedBox(height: 12),
            const _PriceRuleCard(
              title: 'Tabela regional',
              subtitle: 'Variação por praça, imposto e condição comercial.',
              chips: ['Bruto: R\$ 139,90', 'ICMS: 12%', 'Canal: revenda'],
            ),
            const SizedBox(height: 12),
            const _PriceRuleCard(
              title: 'Integração ERP enterprise',
              subtitle: 'A base do ERP alimenta produtos, tabelas de preço e estoque para todos os membros.',
              chips: ['ERP source', 'Carga em lote', 'Sincronização'],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openPreviewPriceImport(BuildContext context) async {
  var scope = 'general';
  String? fileName;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickFile() async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['xlsx', 'xls', 'csv'],
              allowMultiple: false,
              withData: true,
            );

            final selected = result?.files.isNotEmpty == true ? result!.files.first : null;
            if (selected == null) {
              return;
            }

            setSheetState(() {
              fileName = selected.name;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Importar tabela de preço', style: Theme.of(sheetContext).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Aqui começa o fluxo de Excel, com vínculo opcional por cliente ou região.'),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'general',
                          groupValue: scope,
                          title: const Text('Tabela sem vínculo'),
                          subtitle: const Text('Aplica como base geral.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                        RadioListTile<String>(
                          value: 'client',
                          groupValue: scope,
                          title: const Text('Vincular a cliente'),
                          subtitle: const Text('Uma planilha para um cliente específico.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                        RadioListTile<String>(
                          value: 'region',
                          groupValue: scope,
                          title: const Text('Vincular a região'),
                          subtitle: const Text('Uma planilha por praça/UF/grupo regional.'),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => scope = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (fileName != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Planilha selecionada'),
                        subtitle: Text(fileName!),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: pickFile,
                        icon: const Icon(Icons.attach_file_outlined),
                        label: const Text('Selecionar planilha'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showPreviewSoon(context, 'Mapeamento de colunas e validacao'),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Validar estrutura'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

void _showPreviewSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature ainda esta em construcao.')),
  );
}

class _PriceRuleCard extends StatelessWidget {
  const _PriceRuleCard({
    required this.title,
    required this.subtitle,
    required this.chips,
  });

  final String title;
  final String subtitle;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips.map((chip) => Chip(label: Text(chip))).toList(),
            ),
          ],
        ),
      ),
    );
  }
}