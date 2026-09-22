import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/data/firestore/firestore_cliente_pre_cadastro_repository.dart';
import '../../core/data/firestore/firestore_cliente_repository.dart';
import '../../core/data/firestore/firestore_pedido_repository.dart';
import '../../core/data/firestore/firestore_produto_repository.dart';
import '../../core/data/in_memory/demo_workspace.dart';
import '../../core/models/app_identity.dart';
import '../models/app_shell_repository_bundle.dart';

class AppShellRepositoryBootstrapCoordinator {
  const AppShellRepositoryBootstrapCoordinator();

  AppShellRepositoryBundle build({
    required AppIdentity identity,
    required bool isWeb,
    required bool enableLocalMockFallback,
    required FirebaseFirestore firestore,
  }) {
    final shouldUseLocalFallback =
        !isWeb && enableLocalMockFallback && identity.isMock;

    if (shouldUseLocalFallback) {
      final workspace = DemoWorkspace.seeded(identity);
      return AppShellRepositoryBundle(
        clienteRepository: workspace.clientes,
        preCadastroRepository: workspace.preCadastros,
        produtoRepository: workspace.produtos,
        pedidoRepository: workspace.pedidos,
        usingLocalFallback: true,
      );
    }

    return AppShellRepositoryBundle(
      clienteRepository: FirestoreClienteRepository(firestore),
      preCadastroRepository: FirestoreClientePreCadastroRepository(firestore),
      produtoRepository: FirestoreProdutoRepository(firestore),
      pedidoRepository: FirestorePedidoRepository(firestore),
      usingLocalFallback: false,
    );
  }
}
