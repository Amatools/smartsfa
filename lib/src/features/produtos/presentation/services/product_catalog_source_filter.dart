enum ProductCatalogSourceFilter { catalogo, promocoes, destaques }

extension ProductCatalogSourceFilterLabel on ProductCatalogSourceFilter {
  String get label {
    switch (this) {
      case ProductCatalogSourceFilter.catalogo:
        return 'Catalogo';
      case ProductCatalogSourceFilter.promocoes:
        return 'Promocoes';
      case ProductCatalogSourceFilter.destaques:
        return 'Destaques';
    }
  }
}
