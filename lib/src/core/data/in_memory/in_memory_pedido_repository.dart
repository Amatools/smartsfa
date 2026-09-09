import '../../models/pedido.dart';
import '../../repositories/pedido_repository.dart';
import 'in_memory_tenant_scoped_repository.dart';

class InMemoryPedidoRepository extends InMemoryTenantScopedRepository<Pedido>
    implements PedidoRepository {
  InMemoryPedidoRepository({super.seedItems = const []});
}