import 'dart:math' as math;

class PaginationSlice<T> {
  const PaginationSlice({
    required this.items,
    required this.currentPage,
    required this.pageSize,
    required this.totalItems,
    required this.totalPages,
    required this.startDisplay,
    required this.endDisplay,
  });

  final List<T> items;
  final int currentPage;
  final int pageSize;
  final int totalItems;
  final int totalPages;
  final int startDisplay;
  final int endDisplay;

  bool get hasPrevious => currentPage > 0;
  bool get hasNext => currentPage < totalPages - 1;
}

PaginationSlice<T> buildPaginationSlice<T>({
  required List<T> source,
  required int requestedPage,
  required int pageSize,
}) {
  final safePageSize = pageSize <= 0 ? 10 : pageSize;
  final totalItems = source.length;
  final totalPages = totalItems == 0 ? 1 : ((totalItems - 1) ~/ safePageSize) + 1;
  final safePage = requestedPage.clamp(0, totalPages - 1);

  final startOffset = safePage * safePageSize;
  final endOffset = math.min(startOffset + safePageSize, totalItems);
    final items =
      startOffset >= totalItems ? <T>[] : source.sublist(startOffset, endOffset);

  final startDisplay = totalItems == 0 ? 0 : startOffset + 1;
  final endDisplay = totalItems == 0 ? 0 : endOffset;

  return PaginationSlice<T>(
    items: items,
    currentPage: safePage,
    pageSize: safePageSize,
    totalItems: totalItems,
    totalPages: totalPages,
    startDisplay: startDisplay,
    endDisplay: endDisplay,
  );
}