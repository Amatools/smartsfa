import 'package:flutter/material.dart';

class AppPaginationBar extends StatelessWidget {
  const AppPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.pageSize,
    required this.startDisplay,
    required this.endDisplay,
    required this.totalItems,
    required this.onPageSizeChanged,
    this.onPrevious,
    this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int pageSize;
  final int startDisplay;
  final int endDisplay;
  final int totalItems;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Exibindo $startDisplay-$endDisplay de $totalItems'),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<int>(
                initialValue: pageSize,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Itens por pagina',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onPageSizeChanged(value);
                  }
                },
              ),
            ),
            Text('Pagina ${currentPage + 1} de $totalPages'),
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Anterior'),
            ),
            OutlinedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Proxima'),
            ),
          ],
        ),
      ),
    );
  }
}