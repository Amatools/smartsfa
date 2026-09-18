import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';

class ProductCatalogFeedback {
  const ProductCatalogFeedback._();

  static void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String erpProductsDeactivatedMessage(int updated) {
    return '$updated produto(s) ERP inativado(s).';
  }

  static String erpSyncUpdatedMessage({required bool enabled}) {
    return enabled
        ? 'Sincronizacao de produtos via ERP ativada.'
        : 'Sincronizacao de produtos via ERP desativada.';
  }

  static String erpSyncUpdateFailureMessage(Object error) {
    return 'Falha ao atualizar integracao de produtos: $error';
  }

  static String productSavedMessage({required bool isNew}) {
    return isNew
        ? 'Produto cadastrado com sucesso.'
        : 'Produto atualizado com sucesso.';
  }

  static String get productDeletedMessage => 'Produto excluido com sucesso.';

  static String productStatusUpdatedMessage(ProductStatus status) {
    return status == ProductStatus.active ? 'Produto ativado.' : 'Produto inativado.';
  }

  static String productStatusUpdateFailureMessage(Object error) {
    return 'Falha ao atualizar status do produto: $error';
  }
}
