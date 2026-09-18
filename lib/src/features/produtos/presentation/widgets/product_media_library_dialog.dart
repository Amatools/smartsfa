import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../precos/presentation/services/default_price_table_guard.dart';
import '../models/product_media_models.dart';
import '../services/product_media_library_service.dart';
import 'product_media_image_content.dart';

class ProductMediaLibraryDialog extends StatefulWidget {
  const ProductMediaLibraryDialog({
    super.key,
    required this.tenantId,
    required this.representedCompanyId,
    required this.representedCompanyName,
    required this.selectedUrl,
    required this.onUploadNew,
  });

  final String tenantId;
  final String? representedCompanyId;
  final String? representedCompanyName;
  final String selectedUrl;
  final Future<ProductMediaSelection?> Function() onUploadNew;

  @override
  State<ProductMediaLibraryDialog> createState() => _ProductMediaLibraryDialogState();
}

class _ProductMediaLibraryDialogState extends State<ProductMediaLibraryDialog> {
  final ProductMediaLibraryService _mediaLibraryService =
      const ProductMediaLibraryService();
  TextEditingController? _searchController;
  String _searchTerm = '';

  TextEditingController get _safeSearchController =>
      _searchController ??= TextEditingController();

  @override
  void dispose() {
    _searchController?.dispose();
    super.dispose();
  }

  Future<void> _deleteAsset(ProductMediaAsset asset) async {
    final inUse = await _mediaLibraryService.isAssetInUse(
      tenantId: widget.tenantId,
      downloadUrl: asset.downloadUrl,
      storagePath: asset.storagePath,
    );
    if (!mounted) {
      return;
    }

    if (inUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível remover esta imagem porque ela está sendo usada em pelo menos um produto.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir imagem?'),
        content: Text(
          'A imagem ${asset.fileName} será removida da biblioteca e não poderá ser reutilizada nos produtos deste contexto. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _mediaLibraryService.deleteAsset(
        assetId: asset.id,
        storagePath: asset.storagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem removida da biblioteca.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir a imagem: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeKey = DefaultPriceTableGuard.normalizeDefaultPricingScopeKey(
      widget.representedCompanyId,
    );
    final scopeLabel = (widget.representedCompanyName ?? '').trim().isNotEmpty
        ? widget.representedCompanyName!.trim()
        : 'Tenant principal';

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biblioteca de imagens do produto',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Contexto: $scopeLabel. As imagens enviadas aqui podem ser reaproveitadas em outros produtos deste contexto.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      final created = await widget.onUploadNew();
                      if (!context.mounted || created == null) {
                        return;
                      }
                      Navigator.of(context).pop(created);
                    },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Enviar nova'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      const ProductMediaSelection(withoutImage: true),
                    ),
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Sem imagem'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _safeSearchController,
                        onChanged: (value) {
                          setState(() {
                            _searchTerm = value.trim().toLowerCase();
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nome do arquivo',
                          prefixIcon: Icon(Icons.search_outlined),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Chip(
                      avatar: const Icon(Icons.layers_outlined, size: 18),
                      label: Text('Escopo: $scopeLabel'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('product_media_assets')
                      .where('tenantId', isEqualTo: widget.tenantId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final allAssets = (snapshot.data?.docs ?? const [])
                        .map((doc) => ProductMediaAsset.fromMap(doc.id, doc.data()))
                        .where((asset) => asset.scopeKey == scopeKey)
                        .toList(growable: false)
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final assets = _searchTerm.isEmpty
                        ? allAssets
                        : allAssets
                            .where(
                              (asset) => asset.fileName.toLowerCase().contains(_searchTerm),
                            )
                            .toList(growable: false);

                    if (assets.isEmpty) {
                      return _MediaLibraryEmptyState(
                        title: allAssets.isEmpty
                            ? 'Nenhuma imagem cadastrada'
                            : 'Nenhum arquivo encontrado',
                        subtitle: allAssets.isEmpty
                            ? 'Envie a primeira imagem 500x500 para este contexto e depois reutilize nos demais produtos.'
                            : 'Tente outro termo na busca para localizar a imagem.',
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Mostrando ${assets.length} de ${allAssets.length} imagens',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final cardWidth = constraints.maxWidth >= 860
                                  ? 180.0
                                  : constraints.maxWidth >= 620
                                      ? 150.0
                                      : 128.0;
                              final crossAxisCount =
                                  (constraints.maxWidth / cardWidth).floor().clamp(2, 5);

                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.9,
                                ),
                                itemCount: assets.length,
                                itemBuilder: (context, index) {
                                  final asset = assets[index];
                                  final selected = asset.downloadUrl == widget.selectedUrl ||
                                      (widget.selectedUrl.isNotEmpty &&
                                          asset.storagePath == widget.selectedUrl);
                                  return Stack(
                                    children: [
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.of(context).pop(
                                              ProductMediaSelection(asset: asset),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(14),
                                          child: Ink(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: selected
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .outline
                                                        .withValues(alpha: 0.3),
                                                width: selected ? 2 : 1,
                                              ),
                                              color: Theme.of(context).colorScheme.surface,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(10),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: ProductMediaImageContent(
                                                        photoUrl: asset.downloadUrl,
                                                        storagePath: asset.storagePath,
                                                        previewBytes: decodeBase64Image(
                                                          asset.thumbnailBase64,
                                                        ),
                                                        size: 160,
                                                        fallbackText: 'IMG',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    asset.fileName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: Theme.of(context).textTheme.bodyMedium,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${asset.width} x ${asset.height} • ${_formatMediaDate(asset.createdAt)}',
                                                    style: Theme.of(context).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            visualDensity: VisualDensity.compact,
                                            tooltip: 'Excluir imagem',
                                            onPressed: () => _deleteAsset(asset),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMediaDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  return '$day/$month/$year';
}

class _MediaLibraryEmptyState extends StatelessWidget {
  const _MediaLibraryEmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}
