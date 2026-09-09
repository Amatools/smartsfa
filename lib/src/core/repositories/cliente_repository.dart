import '../models/cliente.dart';
import 'tenant_scoped_repository.dart';

abstract class ClienteRepository extends TenantScopedRepository<Cliente> {}