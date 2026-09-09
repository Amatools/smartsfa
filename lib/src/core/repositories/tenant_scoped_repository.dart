import '../contracts/tenant_scoped_entity.dart';

abstract class TenantScopedRepository<T extends TenantScopedEntity> {
  Stream<List<T>> watchAll({required String tenantId});

  Future<List<T>> fetchAll({required String tenantId});

  Future<T?> fetchById({required String tenantId, required String id});

  Future<void> save(T entity);

  Future<void> delete({required String tenantId, required String id});
}