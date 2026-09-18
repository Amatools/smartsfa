import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ProductEditorFeedback {
  static void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String productSavedMessage({required bool isNew}) {
    return isNew
        ? 'Produto cadastrado com sucesso.'
        : 'Produto atualizado com sucesso.';
  }

  static String syncDefaultTableFailureMessage(Object error) {
    return 'Produto salvo, mas falhou a sincronizacao da tabela padrao: $error';
  }

  static String saveFailureMessage(Object error) {
    final rawMessage = error.toString();
    final isPermissionDenied =
        (error is FirebaseException && error.code == 'permission-denied') ||
        rawMessage.contains('permission-denied');
    if (isPermissionDenied) {
      return 'Falha ao salvar produto: permissao negada no Firestore. Verifique regras para produtos e, se habilitado, tabelas_preco/product_base_prices.';
    }
    if (rawMessage.contains('Dart exception thrown from converted Future')) {
      return 'Falha ao salvar produto: erro de runtime no navegador (DWDS) durante operacao assíncrona. Recarregue a pagina e tente novamente.';
    }
    return 'Falha ao salvar produto: $rawMessage';
  }

  static const String imageUploadSuccessMessage = 'Imagem enviada com sucesso.';

  static String uploadFirebaseFailureMessage(FirebaseException error) {
    final code = error.code.trim().toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    final storageNotConfigured =
        code == 'object-not-found' || message.contains('storage has not been set up');
    if (storageNotConfigured) {
      return 'Falha ao enviar imagem: Firebase Storage ainda nao foi iniciado no projeto. Abra Firebase Console > Storage > Get started.';
    }
    return 'Falha ao enviar imagem: ${error.code} ${error.message ?? ''}';
  }

  static const String uploadTimeoutFailureMessage =
      'Falha ao enviar imagem: tempo limite excedido. Verifique rede ou inicialize o Firebase Storage no console (Storage > Get started).';

  static String uploadGenericFailureMessage(Object error) {
    return 'Falha ao enviar imagem: $error';
  }

  static const String requiredDescriptionMessage =
      'Preencha o campo obrigatorio: descricao resumida.';

  static const String requiredTablePriceMessage =
      'Preencha o campo obrigatorio: preco de tabela.';

  static const String deletePermissionFallbackMessage =
      'Sem permissao para excluir definitivamente. Produto inativado com sucesso.';

  static String deleteFailureMessage(Object error) {
    return 'Falha ao excluir produto: $error';
  }
}