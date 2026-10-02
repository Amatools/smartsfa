part of 'web_portal_page.dart';

class _MediaLibrarySection extends StatefulWidget {
  const _MediaLibrarySection({
    required this.activeTenant,
    required this.selectedRepresentedCompanyId,
    this.activeRepresentedCompanyName,
  });

  final TenantEntryOption activeTenant;
  final String? selectedRepresentedCompanyId;
  final String? activeRepresentedCompanyName;

  @override
  State<_MediaLibrarySection> createState() => _MediaLibrarySectionState();
}

class _MediaLibrarySectionState extends State<_MediaLibrarySection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  bool _uploading = false;

  String get _scopeKey =>
      _normalizeDefaultScopeKey(widget.selectedRepresentedCompanyId);
  String get _scopeLabel =>
      (widget.activeRepresentedCompanyName ?? '').trim().isNotEmpty
      ? widget.activeRepresentedCompanyName!.trim()
      : 'Tenant principal';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _uploadNewAsset() async {
    if (_uploading) {
      return;
    }

    setState(() {
      _uploading = true;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Arquivo de imagem invalido.');
      }

      final decoded = image_lib.decodeImage(bytes);
      if (decoded == null) {
        throw StateError('Formato de imagem invalido.');
      }

      final square = _resizeAndCropToSquare(decoded, 500);
      final processedJpg = Uint8List.fromList(
        image_lib.encodeJpg(square, quality: 88),
      );
      final id = 'pma_${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final storagePath =
          'tenants/${widget.activeTenant.tenantId}/product_media/$_scopeKey/$id.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putData(
        processedJpg,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'origin': 'media-library', 'scope-key': _scopeKey},
        ),
      );

      final downloadUrl = await ref.getDownloadURL();
      final asset = {
        'id': id,
        'tenantId': widget.activeTenant.tenantId,
        'representedCompanyId': widget.selectedRepresentedCompanyId,
        'scopeKey': _scopeKey,
        'fileName': file.name.trim().isEmpty ? '$id.jpg' : file.name.trim(),
        'downloadUrl': downloadUrl,
        'storagePath': storagePath,
        'thumbnailBase64': _buildThumbnailBase64(square),
        'width': 500,
        'height': 500,
        'createdAt': Timestamp.fromDate(DateTime.now().toUtc()),
        'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      };

      await FirebaseFirestore.instance
          .collection('product_media_assets')
          .doc(id)
          .set(asset, SetOptions(merge: true));

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem enviada com sucesso.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao enviar imagem: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<void> _deleteAsset(Map<String, dynamic> asset) async {
    final id = asset['id'] as String? ?? '';
    final storagePath = ((asset['storagePath'] as String?) ?? '').trim();
    final inUse = await _isAssetInUse(asset);
    if (inUse) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta imagem está em uso por um produto e não pode ser excluída.',
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir imagem?'),
        content: Text(
          'Deseja remover ${asset['fileName']} da biblioteca de fotos?',
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
      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(storagePath).delete();
      }
      await FirebaseFirestore.instance
          .collection('product_media_assets')
          .doc(id)
          .delete();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem removida da biblioteca.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir imagem: $error')),
      );
    }
  }

  Future<bool> _isAssetInUse(Map<String, dynamic> asset) async {
    final tenantId = widget.activeTenant.tenantId;
    final downloadUrl = ((asset['downloadUrl'] as String?) ?? '').trim();
    final storagePath = ((asset['storagePath'] as String?) ?? '').trim();

    final checks = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    if (downloadUrl.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: downloadUrl)
            .limit(1)
            .get(),
      );
    }
    if (storagePath.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: storagePath)
            .limit(1)
            .get(),
      );
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('storagePath', isEqualTo: storagePath)
            .limit(1)
            .get(),
      );
    }

    if (checks.isEmpty) {
      return false;
    }

    final snapshots = await Future.wait(checks);
    for (final snapshot in snapshots) {
      if (snapshot.docs.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  image_lib.Image _resizeAndCropToSquare(image_lib.Image source, int size) {
    final width = source.width;
    final height = source.height;
    final squareSize = width < height ? width : height;
    final offsetX = ((width - squareSize) / 2).round();
    final offsetY = ((height - squareSize) / 2).round();
    final cropped = image_lib.copyCrop(
      source,
      x: offsetX < 0 ? 0 : offsetX,
      y: offsetY < 0 ? 0 : offsetY,
      width: squareSize,
      height: squareSize,
    );
    if (cropped.width == size && cropped.height == size) {
      return cropped;
    }
    return image_lib.copyResize(
      cropped,
      width: size,
      height: size,
      interpolation: image_lib.Interpolation.cubic,
    );
  }

  String _buildThumbnailBase64(image_lib.Image source) {
    final thumb = image_lib.copyResize(
      source,
      width: 96,
      height: 96,
      interpolation: image_lib.Interpolation.average,
    );
    return base64Encode(image_lib.encodeJpg(thumb, quality: 70));
  }

  @override
  Widget build(BuildContext context) {
    final canEditSettings = _canEditRepresentedModuleSettings(
      role: widget.activeTenant.role,
      workspaceType: widget.activeTenant.workspaceType,
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_media_assets')
          .where('tenantId', isEqualTo: widget.activeTenant.tenantId)
          .snapshots(),
      builder: (context, snapshot) {
        final allAssets =
            (snapshot.data?.docs ?? const [])
                .map((doc) => doc.data())
                .where((asset) {
                  final representedCompanyId =
                      (asset['representedCompanyId'] as String? ?? '').trim();
                  final scopeKey = (asset['scopeKey'] as String? ?? '').trim();
                  final normalizedRepresented = _normalizeDefaultScopeKey(
                    representedCompanyId,
                  );
                  final matchesScopedCompany =
                      normalizedRepresented == _scopeKey;
                  final matchesStoredScope = scopeKey == _scopeKey;
                  final matchesLegacyTenantDefault =
                      _scopeKey == 'tenant_default' &&
                      representedCompanyId.isEmpty &&
                      (scopeKey.isEmpty || scopeKey == 'tenant_default');
                  final matchesLegacyNoScope =
                      representedCompanyId.isEmpty &&
                      scopeKey.isEmpty &&
                      _scopeKey == 'tenant_default';
                  return matchesScopedCompany ||
                      matchesStoredScope ||
                      matchesLegacyTenantDefault ||
                      matchesLegacyNoScope;
                })
                .toList(growable: false)
              ..sort((a, b) {
                final aDate = _readDateTime(a['createdAt']);
                final bDate = _readDateTime(b['createdAt']);
                return bDate.compareTo(aDate);
              });

        final assets = _searchTerm.trim().isEmpty
            ? allAssets
            : allAssets
                  .where(
                    (asset) => ((asset['fileName'] as String?) ?? '')
                        .toLowerCase()
                        .contains(_searchTerm.toLowerCase()),
                  )
                  .toList(growable: false);

        return Card(
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
                            'Fotos',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text('Gestao de imagens do contexto $_scopeLabel.'),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: canEditSettings && !_uploading
                          ? _uploadNewAsset
                          : null,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(_uploading ? 'Enviando...' : 'Enviar foto'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchTerm = value),
                  decoration: const InputDecoration(
                    labelText: 'Buscar por nome do arquivo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                if (assets.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                    child: Text(
                      allAssets.isEmpty
                          ? 'Nenhuma foto cadastrada para este contexto.'
                          : 'Nenhuma foto encontrada para a busca atual.',
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: assets.length,
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      final downloadUrl =
                          ((asset['downloadUrl'] as String?) ?? '').trim();
                      final storagePath =
                          ((asset['storagePath'] as String?) ?? '').trim();
                      final fileName =
                          ((asset['fileName'] as String?) ?? 'imagem').trim();
                      final thumbBase64 = (asset['thumbnailBase64'] as String?)
                          ?.trim();
                      final previewBytes =
                          thumbBase64 != null && thumbBase64.isNotEmpty
                          ? base64Decode(thumbBase64)
                          : null;

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child:
                                      previewBytes != null &&
                                          previewBytes.isNotEmpty
                                      ? Image.memory(
                                          previewBytes,
                                          fit: BoxFit.cover,
                                        )
                                      : (downloadUrl.isNotEmpty
                                            ? Image.network(
                                                downloadUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
                                                      Icons.image_outlined,
                                                      size: 32,
                                                    ),
                                              )
                                            : (storagePath.isNotEmpty
                                                  ? FutureBuilder<String>(
                                                      future: FirebaseStorage
                                                          .instance
                                                          .ref(storagePath)
                                                          .getDownloadURL(),
                                                      builder: (context, snapshot) {
                                                        if (snapshot
                                                                .connectionState ==
                                                            ConnectionState
                                                                .waiting) {
                                                          return const Center(
                                                            child: SizedBox(
                                                              width: 18,
                                                              height: 18,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                            ),
                                                          );
                                                        }
                                                        final url =
                                                            snapshot.data ?? '';
                                                        if (url.isEmpty) {
                                                          return const Icon(
                                                            Icons
                                                                .image_outlined,
                                                            size: 32,
                                                          );
                                                        }
                                                        return Image.network(
                                                          url,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => const Icon(
                                                                Icons
                                                                    .image_outlined,
                                                                size: 32,
                                                              ),
                                                        );
                                                      },
                                                    )
                                                  : const Icon(
                                                      Icons.image_outlined,
                                                      size: 32,
                                                    ))),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                tooltip: 'Excluir imagem',
                                onPressed: canEditSettings
                                    ? () => _deleteAsset(asset)
                                    : null,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.42,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
