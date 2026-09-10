import '../../models/cliente_pre_cadastro.dart';
import '../../repositories/cliente_pre_cadastro_repository.dart';
import 'in_memory_tenant_scoped_repository.dart';

class InMemoryClientePreCadastroRepository
    extends InMemoryTenantScopedRepository<ClientePreCadastro>
    implements ClientePreCadastroRepository {
  InMemoryClientePreCadastroRepository({super.seedItems = const []});
}
