import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/models/produto.dart';

void main() {
  group('Produto origem mercadoria CST', () {
    test('serializes and restores origemMercadoriaCst in valid range', () {
      const produto = Produto(
        id: 'prd-1',
        tenantId: 'tenant-1',
        codigoInterno: 'P-001',
        descricao: 'Produto de teste',
        origemCadastro: ProductSource.manual,
        status: ProductStatus.active,
        origemMercadoriaCst: '2',
      );

      final map = produto.toMap();
      final restored = Produto.fromMap(map);

      expect(map['origemMercadoriaCst'], '2');
      expect(restored.origemMercadoriaCst, '2');
    });

    test('normalizes invalid origemMercadoriaCst values to null', () {
      final restored = Produto.fromMap(<String, Object?>{
        'id': 'prd-2',
        'tenantId': 'tenant-1',
        'codigoInterno': 'P-002',
        'descricao': 'Produto invalido',
        'origemCadastro': ProductSource.manual.value,
        'status': ProductStatus.active.value,
        'origemMercadoriaCst': '9',
      });

      expect(restored.origemMercadoriaCst, isNull);
    });
  });
}
