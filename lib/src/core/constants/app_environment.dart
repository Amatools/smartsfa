enum AppEnvironment { dev, homolog, prod }

class AppEnvironmentConfig {
  static const String _rawEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const int _rawCloudDeltaRefreshIntervalSeconds = int.fromEnvironment(
    'CLOUD_DELTA_REFRESH_INTERVAL_SECONDS',
    defaultValue: -1,
  );

  static AppEnvironment get current {
    switch (_rawEnvironment.trim().toLowerCase()) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'homolog':
      case 'staging':
      case 'hml':
        return AppEnvironment.homolog;
      default:
        return AppEnvironment.dev;
    }
  }

  static String get currentName => current.name;

  static Duration get cloudDeltaRefreshInterval {
    final overrideSeconds = _rawCloudDeltaRefreshIntervalSeconds;
    if (overrideSeconds > 0) {
      return Duration(seconds: overrideSeconds < 15 ? 15 : overrideSeconds);
    }

    switch (current) {
      case AppEnvironment.dev:
        return const Duration(seconds: 20);
      case AppEnvironment.homolog:
        return const Duration(seconds: 45);
      case AppEnvironment.prod:
        return const Duration(seconds: 90);
    }
  }

  static int get costReadRegressionThreshold {
    switch (current) {
      case AppEnvironment.dev:
        return 3000;
      case AppEnvironment.homolog:
        return 1800;
      case AppEnvironment.prod:
        return 1200;
    }
  }

  static int get costQueryOperationRegressionThreshold {
    switch (current) {
      case AppEnvironment.dev:
        return 450;
      case AppEnvironment.homolog:
        return 300;
      case AppEnvironment.prod:
        return 200;
    }
  }

  static Duration get queryPaginationReviewCadence {
    switch (current) {
      case AppEnvironment.dev:
        return const Duration(days: 7);
      case AppEnvironment.homolog:
        return const Duration(days: 14);
      case AppEnvironment.prod:
        return const Duration(days: 14);
    }
  }
}
