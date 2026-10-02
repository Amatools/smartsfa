import 'package:flutter/material.dart';

import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import 'product_editor_defaults.dart';
import 'product_form_value_codec.dart';

class ProductEditorFormControllers {
  ProductEditorFormControllers._({
    required this.codigo,
    required this.codigoFabricante,
    required this.ean,
    required this.descricao,
    required this.precoTabela,
    required this.precoMinimo,
    required this.descricaoLonga,
    required this.marca,
    required this.categoria,
    required this.subcategoria,
    required this.bitola,
    required this.unidade,
    required this.ncm,
    required this.cest,
    required this.ipiBase,
    required this.peso,
    required this.comprimentoMm,
    required this.larguraMm,
    required this.alturaMm,
    required this.quantidadeMinima,
    required this.multiploVenda,
    required this.fotoUrl,
    required this.erpProductId,
    required this.erpSyncId,
  });

  final TextEditingController codigo;
  final TextEditingController codigoFabricante;
  final TextEditingController ean;
  final TextEditingController descricao;
  final TextEditingController precoTabela;
  final TextEditingController precoMinimo;
  final TextEditingController descricaoLonga;
  final TextEditingController marca;
  final TextEditingController categoria;
  final TextEditingController subcategoria;
  final TextEditingController bitola;
  final TextEditingController unidade;
  final TextEditingController ncm;
  final TextEditingController cest;
  final TextEditingController ipiBase;
  final TextEditingController peso;
  final TextEditingController comprimentoMm;
  final TextEditingController larguraMm;
  final TextEditingController alturaMm;
  final TextEditingController quantidadeMinima;
  final TextEditingController multiploVenda;
  final TextEditingController fotoUrl;
  final TextEditingController erpProductId;
  final TextEditingController erpSyncId;

  factory ProductEditorFormControllers.fromProduto(Produto produto) {
    return ProductEditorFormControllers._(
      codigo: TextEditingController(text: produto.codigoInterno),
      codigoFabricante: TextEditingController(
        text: produto.codigoFabricante ?? '',
      ),
      ean: TextEditingController(text: produto.ean ?? ''),
      descricao: TextEditingController(text: produto.descricao),
      precoTabela: TextEditingController(
        text: ProductFormValueCodec.toText(produto.valorBruto),
      ),
      precoMinimo: TextEditingController(
        text: ProductFormValueCodec.toText(produto.precoMinimo),
      ),
      descricaoLonga: TextEditingController(
        text: produto.descricaoLonga ?? produto.descricaoResumida ?? '',
      ),
      marca: TextEditingController(text: produto.marca ?? ''),
      categoria: TextEditingController(text: produto.categoria ?? ''),
      subcategoria: TextEditingController(text: produto.subcategoria ?? ''),
      bitola: TextEditingController(text: produto.bitola ?? ''),
      unidade: TextEditingController(
        text: produto.unidade ?? ProductEditorDefaults.defaultStandardUnit,
      ),
      ncm: TextEditingController(text: _formatNcmMasked(produto.ncm)),
      cest: TextEditingController(text: produto.cest ?? ''),
      ipiBase: TextEditingController(
        text: ProductFormValueCodec.toText(produto.aliquotaIpiBase),
      ),
      peso: TextEditingController(
        text: ProductFormValueCodec.toText(produto.pesoKg),
      ),
      comprimentoMm: TextEditingController(
        text: ProductFormValueCodec.toText(produto.comprimentoMm),
      ),
      larguraMm: TextEditingController(
        text: ProductFormValueCodec.toText(produto.larguraMm),
      ),
      alturaMm: TextEditingController(
        text: ProductFormValueCodec.toText(produto.alturaMm),
      ),
      quantidadeMinima: TextEditingController(
        text: ProductFormValueCodec.toText(produto.quantidadeMinima),
      ),
      multiploVenda: TextEditingController(
        text: ProductFormValueCodec.toText(produto.multiploVenda),
      ),
      fotoUrl: TextEditingController(text: produto.fotoUrl ?? ''),
      erpProductId: TextEditingController(text: produto.erpProductId ?? ''),
      erpSyncId: TextEditingController(text: produto.erpSyncId ?? ''),
    );
  }

  void dispose() {
    codigo.dispose();
    codigoFabricante.dispose();
    ean.dispose();
    descricao.dispose();
    precoTabela.dispose();
    precoMinimo.dispose();
    descricaoLonga.dispose();
    marca.dispose();
    categoria.dispose();
    subcategoria.dispose();
    bitola.dispose();
    unidade.dispose();
    ncm.dispose();
    cest.dispose();
    ipiBase.dispose();
    peso.dispose();
    comprimentoMm.dispose();
    larguraMm.dispose();
    alturaMm.dispose();
    quantidadeMinima.dispose();
    multiploVenda.dispose();
    fotoUrl.dispose();
    erpProductId.dispose();
    erpSyncId.dispose();
  }
}

String _formatNcmMasked(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
  for (var i = 0; i < limited.length; i++) {
    if (i == 4 || i == 6) {
      buffer.write('.');
    }
    buffer.write(limited[i]);
  }
  return buffer.toString();
}

class ProductEditorInitializationState {
  const ProductEditorInitializationState({
    required this.controllers,
    required this.status,
    required this.bitolaUnit,
    required this.currencyCode,
    required this.currentImageStoragePath,
    required this.currentImageThumbBase64,
  });

  final ProductEditorFormControllers controllers;
  final ProductStatus status;
  final String bitolaUnit;
  final String currencyCode;
  final String? currentImageStoragePath;
  final String? currentImageThumbBase64;
}

class ProductEditorInitializationCoordinator {
  const ProductEditorInitializationCoordinator();

  ProductEditorInitializationState build({
    required Produto? existingProduct,
    required Produto emptyDraft,
    required String nextCodigoInterno,
    required String defaultCurrencyCode,
    required Map<String, String> currencyLabels,
    required List<String> bitolaUnits,
  }) {
    final produto =
        existingProduct ??
        emptyDraft.copyWith(codigoInterno: nextCodigoInterno);
    final incomingCurrency = (produto.moeda ?? defaultCurrencyCode)
        .trim()
        .toUpperCase();
    final currencyCode = currencyLabels.containsKey(incomingCurrency)
        ? incomingCurrency
        : defaultCurrencyCode;
    final incomingUnit = _normalizeMeasureUnit(
      produto.bitolaUnidade ?? ProductEditorDefaults.defaultBitolaUnit,
    );
    final bitolaUnit = bitolaUnits.contains(incomingUnit)
        ? incomingUnit
        : ProductEditorDefaults.defaultBitolaUnit;

    return ProductEditorInitializationState(
      controllers: ProductEditorFormControllers.fromProduto(produto),
      status: produto.status,
      bitolaUnit: bitolaUnit,
      currencyCode: currencyCode,
      currentImageStoragePath: produto.storagePath,
      currentImageThumbBase64: produto.thumbnailBase64,
    );
  }

  String _normalizeMeasureUnit(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    switch (normalized) {
      case 'mm':
        return 'milimetro';
      case 'cm':
        return 'centimetro';
      case 'm':
        return 'metro';
      default:
        return normalized;
    }
  }
}
