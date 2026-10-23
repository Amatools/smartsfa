class EnterpriseErpConnectorOption {
  const EnterpriseErpConnectorOption({
    required this.id,
    required this.provider,
    required this.name,
    required this.subtitle,
    required this.logoLabel,
    required this.enabled,
  });

  final String id;
  final String provider;
  final String name;
  final String subtitle;
  final String logoLabel;
  final bool enabled;
}
