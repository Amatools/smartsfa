import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

import '../../../../core/constants/brazil_states.dart';
import '../../../../core/data/firestore/firestore_cliente_pre_cadastro_repository.dart';
import '../../../../core/data/firestore/firestore_cliente_repository.dart';
import '../../../../core/data/firestore/firestore_pedido_repository.dart';
import '../../../../core/data/firestore/firestore_product_base_price_repository.dart';
import '../../../../core/data/firestore/firestore_produto_repository.dart';
import '../../../../core/data/firestore/firestore_tabela_preco_repository.dart';
import '../../../../core/data/firestore/firestore_tax_rule_repository.dart';
import '../../../../core/models/app_identity.dart';
import '../../../../core/models/domain_types.dart';
import '../../../../core/models/tax_rule.dart';
import '../../../../core/models/tenant_entry_decision.dart';
import '../../../../shared/services/tabular_spreadsheet_service.dart';
import '../../../../shared/utils/file_download.dart';
import '../../../auth/services/solo_workspace_service.dart';
import '../../../auth/services/tenant_membership_service.dart';
import '../../../auth/services/workspace_profile_service.dart';
import '../../../auth/presentation/pages/pending_access_page.dart';
import '../../../clientes/presentation/pages/clientes_page.dart';
import '../../../pedidos/presentation/pages/pedidos_page.dart';
import '../../../precos/presentation/pages/tabelas_preco_page.dart';
import '../../../produtos/presentation/pages/produtos_page.dart';
import '../../../tenant/presentation/pages/tenant_admin_page.dart';
import '../../../enterprise/erp_integration/presentation/pages/enterprise_erp_integration_section.dart';
import '../../../produtos/presentation/services/product_editor_defaults.dart';
import '../../../produtos/presentation/services/product_unit_catalog_service.dart';

part 'web_portal_units_section.dart';
part 'web_portal_tax_rules_section.dart';
part 'web_portal_taxation_section.dart';
part 'web_portal_commercial_adjustments_section.dart';
part 'web_portal_order_discounts_section.dart';
part 'web_portal_payment_conditions_section.dart';
part 'web_portal_workspace_parameters_section.dart';
part 'web_portal_media_library_section.dart';
part 'web_portal_categories_section.dart';
part 'web_portal_workspace_profile_section.dart';
part 'web_portal_account_represented_sections.dart';
part 'web_portal_shell_ui_sections.dart';
part 'web_portal_catalog_sections.dart';
part 'web_portal_tenant_module_area_section.dart';
part 'web_portal_shell_state_section.dart';

const String _planTierBase = 'base';
const String _planTierUpgrade = 'upgrade';
const String _featureAdvancedPricing = 'advancedPricingEnabled';

String _normalizeDefaultScopeKey(String? representedCompanyId) {
  final represented = (representedCompanyId ?? '').trim();
  if (represented.isEmpty) {
    return 'tenant_default';
  }
  return represented.replaceAll('.', '_').replaceAll('/', '_');
}

String _enterpriseDefaultRepresentedCompanyId(TenantEntryOption tenant) {
  return 'enterprise_default_${tenant.tenantId}';
}

const String _defaultTaxRegime = defaultTaxRegime;
const List<String> _taxRegimeOptions = taxRegimeValues;

String _normalizeTaxRegimeValue(Object? value) {
  final normalized = normalizeTaxRegimeValue(value?.toString() ?? '');
  if (isValidTaxRegimeValue(normalized)) {
    return normalized;
  }
  return '';
}

String _taxRegimeLabel(Object? value) {
  return taxRegimeLabel(_normalizeTaxRegimeValue(value));
}

DateTime _readDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

const Map<String, Map<String, Set<String>>> _workspacePlanFeatureMatrix = {
  'seller_solo_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
  'rep_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
  'brand_owner_workspace': {
    _planTierBase: <String>{},
    _planTierUpgrade: <String>{_featureAdvancedPricing},
  },
};

class WebPortalPage extends StatelessWidget {
  const WebPortalPage({
    super.key,
    required this.identity,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _WebPortalShell(identity: identity, onSignOut: onSignOut);
  }
}

class _WebPortalShell extends StatefulWidget {
  const _WebPortalShell({required this.identity, required this.onSignOut});

  final AppIdentity identity;
  final VoidCallback onSignOut;

  @override
  State<_WebPortalShell> createState() => _WebPortalShellState();
}
