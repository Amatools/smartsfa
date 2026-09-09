import '../models/pedido.dart';
import 'tenant_scoped_repository.dart';

abstract class PedidoRepository extends TenantScopedRepository<Pedido> {}