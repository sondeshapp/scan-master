import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../data/document_store.dart';
import '../data/models.dart';

class DocumentViewerScreen extends StatefulWidget {
  final ScanDocument doc;
  final int initialPage;

  const DocumentViewerScreen({
    super.key,
    required this.doc,
    this.initialPage = 0,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _store = DocumentStore.instance;
  late ScanDocument _doc;
  late final PageController _pageCtrl;
  final TransformationController _zoomCtrl = TransformationController();
  int _currentPage = 0;
  bool _showControls = true;
  bool _verticalMode = false;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
    _currentPage = widget.initialPage;
    _pageCtrl = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  void _refreshDocFromStore() {
    final latest = _store.documents.where((d) => d.id == _doc.id).firstOrNull;
    if (latest != null && mounted) {
      setState(() => _doc = latest);
    }
  }

  void _resetZoom() {
    _zoomCtrl.value = Matrix4.identity();
    if (_isZoomed) {
      setState(() => _isZoomed = false);
    }
  }

  void _toggleZoom() {
    setState(() {
      if (_isZoomed) {
        _zoomCtrl.value = Matrix4.identity();
        _isZoomed = false;
      } else {
        _zoomCtrl.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
        _isZoomed = true;
      }
    });
  }

  void _jumpToPage(int index) {
    final pages = _doc.pageImagePaths;
    if (index < 0 || index >= pages.length) return;
    _resetZoom();
    setState(() => _currentPage = index);
    if (!_verticalMode && _pageCtrl.hasClients) {
      _pageCtrl.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _share() async {
    final file = File(_doc.pdfPath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_doc.pdfPath, mimeType: 'application/pdf')],
          subject: _doc.name,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF file not found on device'),
          duration: Duration(milliseconds: 1500),
        ),
      );
    }
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _doc.name);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Document name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dialogCtx);
              await _store.renameDocument(_doc.id, name);
              _refreshDocFromStore();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog() {
    final folders = _store.folders;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('Uncategorized'),
                selected: _doc.folderId == null,
                onTap: () async {
                  Navigator.pop(dialogCtx);
                  await _store.moveDocument(_doc.id, null);
                  _refreshDocFromStore();
                },
              ),
              ...folders.map(
                (f) => ListTile(
                  leading: Icon(Icons.folder_rounded, color: f.color),
                  title: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _doc.folderId == f.id,
                  onTap: () async {
                    Navigator.pop(dialogCtx);
                    await _store.moveDocument(_doc.id, f.id);
                    _refreshDocFromStore();
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete "${_doc.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _store.deleteDocument(_doc.id);
              if (mounted) Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _doc.pageImagePaths;
    final folder = _store.folderById(_doc.folderId);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.bgGray,
      appBar: _buildAppBar(folder, pages.length),
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showControls = !_showControls),
            onDoubleTap: _toggleZoom,
            child: pages.isEmpty
                ? _buildEmptyState()
                : _verticalMode
                    ? _buildVerticalReader(pages, safeBottom)
                    : _buildPagedReader(pages, safeBottom),
          ),
          // Floating page indicator & thumbnail strip
          if (pages.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: _buildBottomSection(pages, safeBottom),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ScanFolder? folder, int pageCount) {
    return AppBar(
      backgroundColor: AppTheme.cardBg,
      foregroundColor: AppTheme.textDark,
      elevation: 0,
      leadingWidth: 52,
      leading: Semantics(
        button: true,
        label: 'Back',
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: _showRenameDialog,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    _doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'PDF',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(
                    _doc.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (folder != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.folder_rounded, size: 12, color: folder.color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: folder.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (pageCount > 1)
          IconButton(
            tooltip: _verticalMode ? 'Page swipe view' : 'Continuous scroll',
            icon: Icon(
              _verticalMode
                  ? Icons.view_carousel_outlined
                  : Icons.view_agenda_outlined,
              size: 21,
              color: AppTheme.textDark,
            ),
            onPressed: () {
              _resetZoom();
              setState(() => _verticalMode = !_verticalMode);
            },
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.separator),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.separator),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 34,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _doc.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _doc.meta,
                style: const TextStyle(fontSize: 13, color: AppTheme.textGray),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagedReader(List<String> pages, double safeBottom) {
    final bottomInset = _showControls
        ? (pages.length > 1 ? safeBottom + 178 : safeBottom + 110)
        : safeBottom + 20;

    return PageView.builder(
      controller: _pageCtrl,
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      itemCount: pages.length,
      onPageChanged: (i) {
        _resetZoom();
        setState(() => _currentPage = i);
      },
      itemBuilder: (_, i) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
          child: Center(
            child: InteractiveViewer(
              transformationController: i == _currentPage ? _zoomCtrl : null,
              minScale: 1.0,
              maxScale: 4.0,
              onInteractionEnd: (_) {
                final scale = _zoomCtrl.value.getMaxScaleOnAxis();
                final zoomed = scale > 1.05;
                if (zoomed != _isZoomed) {
                  setState(() => _isZoomed = zoomed);
                }
              },
              child: _PageSheet(
                path: pages[i],
                pageNumber: i + 1,
                totalPages: pages.length,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerticalReader(List<String> pages, double safeBottom) {
    final bottomInset = _showControls
        ? (pages.length > 1 ? safeBottom + 178 : safeBottom + 110)
        : safeBottom + 24;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
      itemCount: pages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        return GestureDetector(
          onTap: () => setState(() {
            _currentPage = i;
            _showControls = !_showControls;
          }),
          child: _PageSheet(
            path: pages[i],
            pageNumber: i + 1,
            totalPages: pages.length,
            showCornerBadge: true,
          ),
        );
      },
    );
  }

  Widget _buildBottomSection(List<String> pages, double safeBottom) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, safeBottom + 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page counter pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.textDark.withAlpha(210),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Page ${_currentPage + 1} of ${pages.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Multi-page thumbnail strip
          if (pages.length > 1) ...[
            SizedBox(
              height: 58,
              child: Center(
                child: ListView.separated(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = i == _currentPage;
                    final file = File(pages[i]);
                    return GestureDetector(
                      onTap: () => _jumpToPage(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.separator,
                            width: selected ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(12),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: file.existsSync()
                              ? Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  cacheWidth: 120,
                                )
                              : Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.textGray,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Frosted-glass bottom action dock matching HomeScreen
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(232),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: AppTheme.separator.withAlpha(180)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(14),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _ViewerActionBtn(
                        icon: Icons.edit_outlined,
                        label: 'Rename',
                        onTap: _showRenameDialog,
                      ),
                    ),
                    Expanded(
                      child: _ViewerActionBtn(
                        icon: Icons.folder_outlined,
                        label: 'Folder',
                        onTap: _showMoveDialog,
                      ),
                    ),
                    if (!_verticalMode)
                      Expanded(
                        child: _ViewerActionBtn(
                          icon: _isZoomed
                              ? Icons.zoom_out_map_rounded
                              : Icons.zoom_in_rounded,
                          label: _isZoomed ? 'Reset' : 'Zoom',
                          active: _isZoomed,
                          onTap: _toggleZoom,
                        ),
                      ),
                    Expanded(
                      child: _ViewerActionBtn(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: _share,
                      ),
                    ),
                    Expanded(
                      child: _ViewerActionBtn(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: _confirmDelete,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageSheet extends StatelessWidget {
  final String path;
  final int pageNumber;
  final int totalPages;
  final bool showCornerBadge;

  const _PageSheet({
    required this.path,
    required this.pageNumber,
    required this.totalPages,
    this.showCornerBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          file.existsSync()
              ? Image.file(file, fit: BoxFit.contain)
              : AspectRatio(
                  aspectRatio: 1 / 1.414,
                  child: Container(
                    color: const Color(0xFFFAFAFC),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF4FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            size: 30,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Page $pageNumber of $totalPages',
                          style: const TextStyle(
                            color: AppTheme.textGray,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          if (showCornerBadge && totalPages > 1)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.textDark.withAlpha(180),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$pageNumber / $totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewerActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  const _ViewerActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? (active ? AppTheme.primary : AppTheme.textDark);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color ?? (active ? AppTheme.primary : AppTheme.textGray),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
