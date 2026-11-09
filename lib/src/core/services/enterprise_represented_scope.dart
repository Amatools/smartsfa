/// Fonte unica de verdade para o id sintetico de "representada" usado por
/// contas `brand_owner_workspace` (enterprise).
///
/// Contas enterprise nao tem representada de verdade (nenhum documento em
/// `tenant_represented_companies`/`represented_companies`) - so a propria
/// empresa. Para reaproveitar a mesma UI/telas de configuracao escopada por
/// representada (condicoes de pagamento, acrescimos/descontos comerciais,
/// descontos de pedido, taxonomia de produtos, biblioteca de midia,
/// tabelas de preco), tanto o app mobile (`app_shell.dart`) quanto o portal
/// web (`web_portal_page.dart`/`web_portal_shell_state_section.dart`)
/// sintetizam o mesmo `representedCompanyId` literal
/// (`enterprise_default_<tenantId>`) para a sessao enterprise ativa.
///
/// HISTORICO (ver `/memories/repo/smartsfa-notes.md`, "BUG EM CADEIA" partes
/// 1-7): qualquer codigo que usa esse `representedCompanyId` sintetico
/// diretamente para montar uma chave de escopo/doc id no Firestore (em vez
/// de primeiro normaliza-lo de volta para "sem representada"/tenant-level)
/// acaba lendo/gravando num escopo que nunca teve dado historico, porque o
/// dado real dessas contas sempre viveu no escopo tenant-level (chave
/// `tenant_default`). Esse bug ja se repetiu em pelo menos 7 familias de
/// codigo diferentes (tabela de preco, condicoes de pagamento, acrescimos
/// comerciais, descontos de pedido, taxonomia de produtos, biblioteca de
/// midia, e o fluxo de pedidos: `pedidos_page.dart`/`pedido_inline_editor.dart`
/// + o filtro de escopo de `tax_rules` em
/// `ProductTaxEngineService.calcularTotaisItem`) justamente porque a logica
/// de deteccao/normalizacao do id sintetico estava duplicada manualmente em
/// cada arquivo. Esta classe existe para ser o UNICO lugar que sabe
/// construir e reconhecer esse id - qualquer novo servico/tela/mixin
/// escopado por representada deve delegar para ca em vez de reimplementar a
/// comparacao de string.
class EnterpriseRepresentedScope {
  const EnterpriseRepresentedScope._();

  /// Constroi o id sintetico de representada para um tenant enterprise.
  /// Unica funcao do codebase que deve literalmente montar essa string -
  /// todo outro lugar (mobile `app_shell.dart`, portal
  /// `web_portal_shell_state_section.dart`/`web_portal_page.dart`) deve
  /// chamar esta funcao em vez de interpolar `'enterprise_default_$tenantId'`
  /// manualmente.
  static String syntheticId(String tenantId) {
    return 'enterprise_default_${tenantId.trim()}';
  }

  /// `true` quando `representedCompanyId` e exatamente o id sintetico
  /// enterprise deste tenant (comparacao apos trim em ambos os lados).
  static bool isSynthetic(String tenantId, String? representedCompanyId) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == syntheticId(tenantId);
  }

  /// Normaliza `representedCompanyId` para uso em qualquer calculo de chave
  /// de escopo/doc id: retorna `null` quando vazio OU quando e o id
  /// sintetico enterprise deste tenant (ambos os casos devem cair no escopo
  /// tenant-level/`tenant_default`); caso contrario retorna o id (trimado)
  /// inalterado, preservando 100% do comportamento para
  /// `rep_workspace`/`seller_solo_workspace` com representada real
  /// selecionada.
  static String? effectiveRepresentedCompanyId({
    required String tenantId,
    String? representedCompanyId,
  }) {
    final normalized = (representedCompanyId ?? '').trim();
    if (normalized.isEmpty || normalized == syntheticId(tenantId)) {
      return null;
    }
    return normalized;
  }
}
