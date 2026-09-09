import '../../models/cliente.dart';
import '../../repositories/cliente_repository.dart';
import 'in_memory_tenant_scoped_repository.dart';

class InMemoryClienteRepository extends InMemoryTenantScopedRepository<Cliente>
    implements ClienteRepository {
  InMemoryClienteRepository({super.seedItems = const []});
}