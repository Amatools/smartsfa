import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/produto.dart';
import 'product_editor_defaults.dart';
import 'product_form_value_codec.dart';
import 'product_media_path_utils.dart';

class ProductEditorEntityMapper {
  const ProductEditorEntityMapper._();

  static Produto buildFromForm({
    required AppIdentity identity,
    required Produto? existing,
    required DateTime now,
    required String codigo,
    required String descricao,
    required ProductStatus status,
    required String currencyCode,
    required double tablePrice,
    required bool isEnterprise,
    required bool imageExplicitlyCleared,
    required String fotoUrlText,
    required String descricaoLongaText,
    required String codigoFabricanteText,
    required String eanText,
    required String marcaText,
    required List<String> availableBrands,
    required String categoriaText,
    required String subcategoriaText,
    required String bitolaText,
    required String bitolaUnit,
    required String comprimentoMmText,
    required String larguraMmText,
    required String alturaMmText,
    required String precoMinimoText,
    required String unidadeText,
    required String multiploVendaText,
    required String quantidadeMinimaText,
    required String ncmText,
    required String cfopText,
    required String icmsText,
    required String pisText,
    required String cofinsText,
    required String pesoText,
    required String erpProductIdText,
    required String erpSyncIdText,
    required String tabelaVersaoText,
    required String estoqueVersaoText,
    required String? currentImageStoragePath,
    required String? currentImageThumbBase64,
  }) {
    final normalizedPhotoUrl = ProductFormValueCodec.nullableText(fotoUrlText);
    final inferredStoragePath =
        normalizedPhotoUrl != null &&
            ProductMediaPathUtils.looksLikeStorageObjectPath(normalizedPhotoUrl)
        ? normalizedPhotoUrl
        : null;
    final normalizedStoragePath = imageExplicitlyCleared
        ? null
        : (currentImageStoragePath ??
              existing?.storagePath ??
              inferredStoragePath);
    final normalizedThumbBase64 = imageExplicitlyCleared
        ? null
        : (currentImageThumbBase64 ?? existing?.thumbnailBase64);

    final normalizedBrand = _normalizeBrand(
      rawBrand: marcaText,
      availableBrands: availableBrands,
    );

    return Produto(
      id: existing?.id ?? 'prd_${now.microsecondsSinceEpoch}',
      tenantId: identity.tenantId,
      codigoInterno: codigo,
      descricao: descricao,
      origemCadastro: existing?.origemCadastro ?? ProductSource.manual,
      status: status,
      fotoUrl: normalizedPhotoUrl,
      storagePath: normalizedPhotoUrl == null ? null : normalizedStoragePath,
      thumbnailBase64: normalizedPhotoUrl == null
          ? null
          : normalizedThumbBase64,
      descricaoLonga: ProductFormValueCodec.nullableText(descricaoLongaText),
      descricaoResumida: existing?.descricaoResumida,
      codigoFabricante: ProductFormValueCodec.nullableText(
        codigoFabricanteText,
      ),
      sku: existing?.sku,
      ean: ProductFormValueCodec.nullableText(eanText),
      marca: normalizedBrand,
      categoria: ProductFormValueCodec.nullableText(categoriaText),
      subcategoria: ProductFormValueCodec.nullableText(subcategoriaText),
      bitola: ProductFormValueCodec.nullableText(bitolaText),
      bitolaUnidade:
          ProductFormValueCodec.nullableText(bitolaUnit) ??
          ProductEditorDefaults.defaultBitolaUnit,
      moeda: currencyCode,
      comprimentoMm: ProductFormValueCodec.parseDecimal(comprimentoMmText),
      larguraMm: ProductFormValueCodec.parseDecimal(larguraMmText),
      alturaMm: ProductFormValueCodec.parseDecimal(alturaMmText),
      valorBruto: tablePrice,
      precoMinimo: ProductFormValueCodec.parseDecimal(precoMinimoText),
      percentualComissao: existing?.percentualComissao,
      unidade: ProductFormValueCodec.nullableText(unidadeText) ?? 'UN',
      multiploVenda: ProductFormValueCodec.parseDecimal(multiploVendaText),
      quantidadeMinima: ProductFormValueCodec.parseDecimal(
        quantidadeMinimaText,
      ),
      ncm: ProductFormValueCodec.nullableText(ncmText),
      cfop: ProductFormValueCodec.nullableText(cfopText),
      aliquotaIcms: ProductFormValueCodec.parseDecimal(icmsText),
      aliquotaPis: ProductFormValueCodec.parseDecimal(pisText),
      aliquotaCofins: ProductFormValueCodec.parseDecimal(cofinsText),
      pesoKg: ProductFormValueCodec.parseDecimal(pesoText),
      erpProductId: isEnterprise
          ? ProductFormValueCodec.nullableText(erpProductIdText)
          : null,
      erpSyncId: isEnterprise
          ? ProductFormValueCodec.nullableText(erpSyncIdText)
          : null,
      tabelaPrecoVersao: ProductFormValueCodec.nullableText(tabelaVersaoText),
      estoqueVersao: ProductFormValueCodec.nullableText(estoqueVersaoText),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  static String _normalizeBrand({
    required String rawBrand,
    required List<String> availableBrands,
  }) {
    final normalized = rawBrand.trim();
    if (normalized.isEmpty) {
      return '';
    }

    for (final brand in availableBrands) {
      if (brand.trim().toLowerCase() == normalized.toLowerCase()) {
        return brand;
      }
    }

    return normalized;
  }
}
