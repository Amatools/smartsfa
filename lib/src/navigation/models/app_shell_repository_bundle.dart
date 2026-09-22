import '../../core/repositories/cliente_pre_cadastro_repository.dart';
import '../../core/repositories/cliente_repository.dart';
import '../../core/repositories/pedido_repository.dart';
import '../../core/repositories/produto_repository.dart';

class AppShellRepositoryBundle {
  const AppShellRepositoryBundle({
    required this.clienteRepository,
    required this.preCadastroRepository,
    required this.produtoRepository,
    required this.pedidoRepository,
    required this.usingLocalFallback,
  });

  final ClienteRepository clienteRepository;
  final ClientePreCadastroRepository preCadastroRepository;
  final ProdutoRepository produtoRepository;
  final PedidoRepository pedidoRepository;
  final bool usingLocalFallback;
}
