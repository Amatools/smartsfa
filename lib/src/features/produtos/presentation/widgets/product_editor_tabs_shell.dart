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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          tabs: [
            const Tab(icon: Icon(Icons.sell_outlined), text: 'Preco'),
            const Tab(icon: Icon(Icons.info_outline), text: 'Informacoes'),
            const Tab(icon: Icon(Icons.account_balance_outlined), text: 'Fiscal'),
            const Tab(icon: Icon(Icons.tune_outlined), text: 'Variacoes'),
            const Tab(icon: Icon(Icons.straighten_outlined), text: 'Peso e Dimensoes'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 332,
          child: TabBarView(
            children: [
              priceTab,
              informationTab,
              fiscalTab,
              variationsTab,
              weightDimensionsTab,
            ],
          ),
        ),
      ],
    );
  }
}