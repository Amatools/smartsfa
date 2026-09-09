import 'dart:async';

import '../../contracts/tenant_scoped_entity.dart';
import '../../repositories/tenant_scoped_repository.dart';

class InMemoryTenantScopedRepository<T extends TenantScopedEntity>
    implements TenantScopedRepository<T> {
  InMemoryTenantScopedRepository({Iterable<T> seedItems = const []}) {
    for (final item in seedItems) {
      _storeItem(item);
    }
  }

  final Map<String, Map<String, T>> _itemsByTenant = {};
  final Map<String, StreamController<List<T>>> _controllers = {};

  @override
  Stream<List<T>> watchAll({required String tenantId}) {
    final controller = _controllerFor(tenantId);

    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(_snapshot(tenantId));
      }
    });

    return controller.stream;
  }

  @override
  Future<List<T>> fetchAll({required String tenantId}) async {
    return _snapshot(tenantId);
  }

  @override
  Future<T?> fetchById({required String tenantId, required String id}) async {
    return _itemsByTenant[tenantId]?[id];
  }

  @override
  Future<void> save(T entity) async {
    _storeItem(entity);
    _emit(entity.tenantId);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    final tenantItems = _itemsByTenant[tenantId];
    if (tenantItems == null) {
      return;
    }

    tenantItems.remove(id);
    _emit(tenantId);
  }

  List<T> _snapshot(String tenantId) {
    final tenantItems = _itemsByTenant[tenantId];
    if (tenantItems == null || tenantItems.isEmpty) {
      return const [];
    }

    return List.unmodifiable(tenantItems.values.toList());
  }

  void _storeItem(T entity) {
    final tenantItems = _itemsByTenant.putIfAbsent(entity.tenantId, () => {});
    tenantItems[entity.id] = entity;
  }

  void _emit(String tenantId) {
    final controller = _controllers[tenantId];
    if (controller == null || controller.isClosed) {
      return;
    }

    controller.add(_snapshot(tenantId));
  }

  StreamController<List<T>> _controllerFor(String tenantId) {
    return _controllers.putIfAbsent(
      tenantId,
      () => StreamController<List<T>>.broadcast(),
    );
  }
}