import 'package:flutter/material.dart';

import '../../core/models/app_identity.dart';

class AppShellDashboardPage extends StatelessWidget {
  const AppShellDashboardPage({
    super.key,
    required this.identity,
    required this.usingLocalFallback,
  });

  final AppIdentity identity;
  final bool usingLocalFallback;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Tenant', identity.tenantName),
      ('Usuario', identity.userLabel),
      ('Perfil', identity.role),
      (
        'Conexao',
        usingLocalFallback ? 'Local mock / fallback' : 'Firebase autenticado',
      ),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Painel inicial',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Shell base do Smart SFA preparada para multi-tenant, navegacao por perfil e evolucao modular.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Column(
              children: cards
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.$1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Flexible(
                                child: Text(entry.$2, textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const AppShellStageCard(
              title: 'Proxima entrega',
              lines: [
                'Refatorar dados para tenants e memberships',
                'Criar navegacao funcional por modulo',
                'Mostrar listas reais de clientes, produtos e pedidos',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AppShellModulePage extends StatelessWidget {
  const AppShellModulePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            AppShellStageCard(title: 'Escopo inicial', lines: bullets),
          ],
        ),
      ),
    );
  }
}

class AppShellStageCard extends StatelessWidget {
  const AppShellStageCard({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

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
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 8),
                    ),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
