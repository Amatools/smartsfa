import '../models/tax_rule.dart';
import 'tenant_scoped_repository.dart';

abstract class TaxRuleRepository extends TenantScopedRepository<TaxRule> {}
