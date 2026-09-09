import '../../models/produto.dart';
import '../../repositories/produto_repository.dart';
import 'in_memory_tenant_scoped_repository.dart';

class InMemoryProdutoRepository extends InMemoryTenantScopedRepository<Produto>
    implements ProdutoRepository {
  InMemoryProdutoRepository({Iterable<Produto> seedItems = const []})
      : super(seedItems: seedItems);
}