import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ProductEditorTabsShell extends StatelessWidget {
  const ProductEditorTabsShell({
    super.key,
    required this.priceTab,
    required this.informationTab,
    required this.taxationTab,
    required this.variationsTab,
    required this.weightDimensionsTab,
  });

  final Widget priceTab;
  final Widget informationTab;
  final Widget taxationTab;
  final Widget variationsTab;
  final Widget weightDimensionsTab;

  List<Widget> get _tabs => <Widget>[
    priceTab,
    informationTab,
    taxationTab,
    variationsTab,
    weightDimensionsTab,
  ];

  @override
  Widget build(BuildContext context) {
    final compactTabLabelStyle = !kIsWeb
        ? Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, height: 1.1)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          labelStyle: compactTabLabelStyle,
          unselectedLabelStyle: compactTabLabelStyle?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            const Tab(icon: Icon(Icons.sell_outlined), text: 'Preco'),
            const Tab(icon: Icon(Icons.info_outline), text: 'Informacoes'),
            const Tab(
              icon: Icon(Icons.account_balance_outlined),
              text: 'Tributacao',
            ),
            const Tab(icon: Icon(Icons.tune_outlined), text: 'Outras infos'),
            const Tab(
              icon: Icon(Icons.straighten_outlined),
              text: 'Peso e Dimensoes',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final controller = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return _tabs[controller.index];
              },
            );
          },
        ),
      ],
    );
  }
}
