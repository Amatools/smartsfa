import '../../core/models/domain_types.dart';
import '../../core/models/pedido.dart';

class AppShellDashboardSalesPoint {
  const AppShellDashboardSalesPoint({
    required this.day,
    required this.total,
    required this.orders,
  });

  final DateTime day;
  final double total;
  final int orders;
}

class AppShellDashboardTopCustomer {
  const AppShellDashboardTopCustomer({
    required this.id,
    required this.label,
    required this.total,
    required this.orders,
  });

  final String id;
  final String label;
  final double total;
  final int orders;
}

class AppShellDashboardSalesSummary {
  const AppShellDashboardSalesSummary({
    required this.monthTotal,
    required this.monthOrders,
    required this.monthAverageTicket,
    required this.last7DaysTotal,
    required this.previous7DaysTotal,
    required this.dailySales,
    required this.topCustomers,
  });

  final double monthTotal;
  final int monthOrders;
  final double monthAverageTicket;
  final double last7DaysTotal;
  final double previous7DaysTotal;
  final List<AppShellDashboardSalesPoint> dailySales;
  final List<AppShellDashboardTopCustomer> topCustomers;

  bool get hasSalesData =>
      monthOrders > 0 ||
      dailySales.any((point) => point.total > 0 || point.orders > 0);
}

class AppShellDashboardSalesService {
  const AppShellDashboardSalesService();

  static const int _dailyWindowSize = 30;

  AppShellDashboardSalesSummary build({
    required List<Pedido> pedidos,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final firstChartDay = today.subtract(
      const Duration(days: _dailyWindowSize - 1),
    );

    final monthStart = DateTime(reference.year, reference.month, 1);
    final nextMonthStart = reference.month == 12
        ? DateTime(reference.year + 1, 1, 1)
        : DateTime(reference.year, reference.month + 1, 1);

    final last7Start = today.subtract(const Duration(days: 6));
    final previous7Start = today.subtract(const Duration(days: 13));
    final previous7End = today.subtract(const Duration(days: 7));

    final dailyTotals = <DateTime, _SalesAccumulator>{};
    for (var index = 0; index < _dailyWindowSize; index++) {
      final day = firstChartDay.add(Duration(days: index));
      dailyTotals[day] = const _SalesAccumulator();
    }

    var monthTotal = 0.0;
    var monthOrders = 0;
    var last7DaysTotal = 0.0;
    var previous7DaysTotal = 0.0;
    final topCustomers = <String, _TopCustomerAccumulator>{};

    for (final pedido in pedidos) {
      if (!_isEligibleSale(pedido)) {
        continue;
      }

      final saleDate = _resolveSaleDate(pedido);
      if (saleDate == null) {
        continue;
      }

      final day = DateTime(saleDate.year, saleDate.month, saleDate.day);
      final value = pedido.totalBruto;

      final existingDaily = dailyTotals[day];
      if (existingDaily != null) {
        dailyTotals[day] = existingDaily.add(value: value);
      }

      if (!saleDate.isBefore(monthStart) && saleDate.isBefore(nextMonthStart)) {
        monthTotal += value;
        monthOrders++;

        final customerKey = (pedido.clienteReferencia?.id ?? '').trim();
        final fallbackKey = customerKey.isEmpty
            ? 'unknown_customer'
            : customerKey;
        final customerLabel = _resolveCustomerLabel(pedido);
        final current = topCustomers[fallbackKey];
        if (current == null) {
          topCustomers[fallbackKey] = _TopCustomerAccumulator(
            id: fallbackKey,
            label: customerLabel,
            total: value,
            orders: 1,
          );
        } else {
          topCustomers[fallbackKey] = current.add(value: value);
        }
      }

      if (!day.isBefore(last7Start) && !day.isAfter(today)) {
        last7DaysTotal += value;
      } else if (!day.isBefore(previous7Start) && !day.isAfter(previous7End)) {
        previous7DaysTotal += value;
      }
    }

    final dailySales =
        dailyTotals.entries
            .map(
              (entry) => AppShellDashboardSalesPoint(
                day: entry.key,
                total: entry.value.total,
                orders: entry.value.orders,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.day.compareTo(b.day));

    final topRows = topCustomers.values.toList()
      ..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        if (byTotal != 0) {
          return byTotal;
        }
        return b.orders.compareTo(a.orders);
      });

    final top5 = topRows
        .take(5)
        .map(
          (entry) => AppShellDashboardTopCustomer(
            id: entry.id,
            label: entry.label,
            total: entry.total,
            orders: entry.orders,
          ),
        )
        .toList(growable: false);

    return AppShellDashboardSalesSummary(
      monthTotal: monthTotal,
      monthOrders: monthOrders,
      monthAverageTicket: monthOrders == 0 ? 0 : monthTotal / monthOrders,
      last7DaysTotal: last7DaysTotal,
      previous7DaysTotal: previous7DaysTotal,
      dailySales: dailySales,
      topCustomers: top5,
    );
  }

  bool _isEligibleSale(Pedido pedido) {
    if (pedido.deletedAt != null) {
      return false;
    }
    return pedido.statusFila == OrderStatus.sent ||
        pedido.statusFila == OrderStatus.pendingSend;
  }

  DateTime? _resolveSaleDate(Pedido pedido) {
    return pedido.updatedAt ?? pedido.createdAt;
  }

  String _resolveCustomerLabel(Pedido pedido) {
    final name = (pedido.clienteReferencia?.nomeSnapshot ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    final document = (pedido.clienteReferencia?.documentoSnapshot ?? '').trim();
    if (document.isNotEmpty) {
      return document;
    }
    return 'Cliente sem nome';
  }
}

class _SalesAccumulator {
  const _SalesAccumulator({this.total = 0, this.orders = 0});

  final double total;
  final int orders;

  _SalesAccumulator add({required double value}) {
    return _SalesAccumulator(total: total + value, orders: orders + 1);
  }
}

class _TopCustomerAccumulator {
  const _TopCustomerAccumulator({
    required this.id,
    required this.label,
    required this.total,
    required this.orders,
  });

  final String id;
  final String label;
  final double total;
  final int orders;

  _TopCustomerAccumulator add({required double value}) {
    return _TopCustomerAccumulator(
      id: id,
      label: label,
      total: total + value,
      orders: orders + 1,
    );
  }
}
