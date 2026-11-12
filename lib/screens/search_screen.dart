import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../data/document_store.dart';
import '../data/models.dart';
import 'document_viewer_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _store = DocumentStore.instance;
  List<ScanDocument> _results = [];

  void _runSearch(String q) {
    setState(() => _results = _store.search(q));
  }

  void _tapRecent(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: q.length),
    );
    _runSearch(q);
  }

  Future<void> _clearRecents() async {
    await _store.clearRecentSearches();
    if (mounted) setState(() {});
  }

  Future<void> _submitSearch() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    await _store.addRecentSearch(q);
    if (mounted) _runSearch(q);
  }

  Future<void> _openDocument(ScanDocument doc) async {
    final q = _ctrl.text.trim();
    if (q.isNotEmpty) {
      await _store.addRecentSearch(q);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentViewerScreen(doc: doc)),
    );
    if (mounted) _runSearch(_ctrl.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text;
    return Scaffold(
      backgroundColor: AppTheme.bgGray,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          _buildSearchBar(context),
          Expanded(
            child: q.isEmpty
                ? _buildRecentsView()
                : _buildResultsView(q),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.separator),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: AppTheme.textGray, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        if (v.isEmpty) {
                          setState(() => _results = []);
                        } else {
                          _runSearch(v);
                        }
                      },
                      onSubmitted: (_) => _submitSearch(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Search documents...',
                        hintStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      style: const TextStyle(
                          fontSize: 16, color: AppTheme.textDark),
                    ),
                  ),
                  if (_ctrl.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.cancel,
                          color: AppTheme.textGray, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _results = []);
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentsView() {
    final recents = _store.recentSearches;
    if (recents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: AppTheme.textGray),
            SizedBox(height: 12),
            Text(
              'Search your documents',
              style: TextStyle(color: AppTheme.textGray, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT SEARCHES',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGray,
                    letterSpacing: 0.5),
              ),
              TextButton(
                onPressed: _clearRecents,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear All',
                    style: TextStyle(color: AppTheme.primary, fontSize: 13)),
              ),
            ],
          ),
        ),
        ...recents.map(
          (r) => ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: const Icon(Icons.history, color: AppTheme.textGray),
            title: Text(r,
                style: const TextStyle(
                    fontSize: 15, color: AppTheme.textDark)),
            trailing: Transform.rotate(
              angle: 0.7854,
              child: const Icon(Icons.north, color: AppTheme.textGray, size: 16),
            ),
            onTap: () => _tapRecent(r),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView(String q) {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppTheme.textGray),
              const SizedBox(height: 12),
              Text(
                'No results for "$q"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textGray, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'RESULTS (${_results.length})',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textGray,
                letterSpacing: 0.5),
          ),
        ),
        ..._results.map(
          (doc) => _ResultItem(
            doc: doc,
            query: q,
            folder: _store.folderById(doc.folderId),
            onTap: () => _openDocument(doc),
            onDeleted: () {
              if (mounted) _runSearch(_ctrl.text);
            },
          ),
        ),
      ],
    );
  }
}

class _ResultItem extends StatelessWidget {
  final ScanDocument doc;
  final String query;
  final ScanFolder? folder;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  const _ResultItem({
    required this.doc,
    required this.query,
    this.folder,
    required this.onTap,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Container(
              width: 64,
              height: 80,
              decoration: BoxDecoration(
                color: doc.iconColor.withAlpha(31),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 8,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: doc.pageImagePaths.isNotEmpty &&
                      File(doc.pageImagePaths.first).existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(doc.pageImagePaths.first),
                        fit: BoxFit.cover,
                        cacheWidth: 180,
                      ),
                    )
                  : Icon(Icons.picture_as_pdf_rounded,
                      color: doc.iconColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  _HighlightText(text: doc.name, query: query),
                  const SizedBox(height: 3),
                  Text(
                    doc.meta,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textGray),
                  ),
                  if (folder != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_rounded,
                            size: 13, color: folder!.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            folder!.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: folder!.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More options',
              icon: const Icon(Icons.more_horiz,
                  color: AppTheme.textGray, size: 20),
              onSelected: (v) async {
                if (v == 'share') {
                  final file = File(doc.pdfPath);
                  if (await file.exists()) {
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [
                          XFile(doc.pdfPath, mimeType: 'application/pdf')
                        ],
                        subject: doc.name,
                      ),
                    );
                  }
                } else if (v == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      title: const Text('Delete?'),
                      content: Text('Delete "${doc.name}"?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await DocumentStore.instance.deleteDocument(doc.id);
                    onDeleted();
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  final String text, query;
  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textDark);
    final q = query.trim();
    if (q.isEmpty) return Text(text, style: base);
    final lower = text.toLowerCase();
    final qLower = q.toLowerCase();
    if (!lower.contains(qLower)) return Text(text, style: base);

    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(qLower, start);
      if (idx < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: base.copyWith(color: AppTheme.primary),
        ),
      );
      start = idx + q.length;
    }

    return RichText(text: TextSpan(style: base, children: spans));
  }
}
