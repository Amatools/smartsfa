import 'package:flutter/material.dart';

class ProductEditorTabsShell extends StatelessWidget {
  const ProductEditorTabsShell({
    super.key,
    required this.priceTab,
    required this.informationTab,
    required this.fiscalTab,
    required this.variationsTab,
    required this.weightDimensionsTab,
  });

  final Widget priceTab;
  final Widget informationTab;
  final Widget fiscalTab;
  final Widget variationsTab;
  final Widget weightDimensionsTab;

  List<Widget> get _tabs => <Widget>[
    priceTab,
    informationTab,
    fiscalTab,
    variationsTab,
    weightDimensionsTab,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          tabs: [
            const Tab(icon: Icon(Icons.sell_outlined), text: 'Preco'),
            const Tab(icon: Icon(Icons.info_outline), text: 'Informacoes'),
            const Tab(
              icon: Icon(Icons.account_balance_outlined),
              text: 'Fiscal',
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
