import '../models/discount_policy.dart';
import 'tenant_scoped_repository.dart';

abstract class DiscountPolicyRepository
    extends TenantScopedRepository<DiscountPolicy> {}
