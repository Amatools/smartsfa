import '../models/produto.dart';
import 'tenant_scoped_repository.dart';

abstract class ProdutoRepository extends TenantScopedRepository<Produto> {}