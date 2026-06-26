import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../data/document_store.dart';
import '../data/models.dart';
import 'document_viewer_screen.dart';

class FolderScreen extends StatefulWidget {
  final ScanFolder folder;
  const FolderScreen({super.key, required this.folder});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final _store = DocumentStore.instance;
  final Set<String> _selectedIds = {};

  bool get _selectMode => _selectedIds.isNotEmpty;
  List<ScanDocument> get _docs => _store.documentsInFolder(widget.folder.id);

  Future<void> _deleteSelected() async {
    final ids = [..._selectedIds];
    setState(() => _selectedIds.clear());
    for (final id in ids) {
      await _store.deleteDocument(id);
    }
    if (mounted) setState(() {});
  }

  void _openViewer(ScanDocument doc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentViewerScreen(doc: doc)),
    );
  }

  void _showOptions(ScanDocument doc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(context);
                _openViewer(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(context);
                final file = File(doc.pdfPath);
                if (await file.exists()) {
                  await Share.shareXFiles(
                    [XFile(doc.pdfPath, mimeType: 'application/pdf')],
                    subject: doc.name,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Remove from folder'),
              onTap: () async {
                Navigator.pop(context);
                await _store.moveDocument(doc.id, null);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Document'),
                    content: Text('Delete "${doc.name}"?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () async {
                          Navigator.pop(context);
                          await _store.deleteDocument(doc.id);
                          if (mounted) setState(() {});
                        },
                        child: const Text('Delete'),
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
  }

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    return Scaffold(
      backgroundColor: AppTheme.bgGray,
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selectedIds.length} selected',
                style: const TextStyle(color: AppTheme.primary))
            : Text(widget.folder.name),
        backgroundColor: AppTheme.cardBg,
        foregroundColor: AppTheme.textDark,
        elevation: 0,
        actions: _selectMode
            ? [
                TextButton(
                  onPressed: _deleteSelected,
                  child: const Text('Delete',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIds.clear()),
                  child: const Text('Cancel'),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.separator),
        ),
      ),
      body: docs.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_outlined,
                      size: 56, color: AppTheme.textGray),
                  SizedBox(height: 12),
                  Text(
                    'This folder is empty',
                    style: TextStyle(color: AppTheme.textGray, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final doc = docs[i];
                final selected = _selectedIds.contains(doc.id);
                return GestureDetector(
                  onTap: () {
                    if (_selectMode) {
                      setState(() {
                        if (selected) {
                          _selectedIds.remove(doc.id);
                        } else {
                          _selectedIds.add(doc.id);
                        }
                      });
                    } else {
                      _openViewer(doc);
                    }
                  },
                  onLongPress: () =>
                      setState(() => _selectedIds.add(doc.id)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.separator.withAlpha(128),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        // Thumbnail + selection overlay
                        Stack(
                          children: [
                            Container(
                              width: 48, height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: doc.iconColor.withAlpha(25),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: doc.pageImagePaths.isNotEmpty &&
                                        File(doc.pageImagePaths.first)
                                            .existsSync()
                                    ? Image.file(
                                        File(doc.pageImagePaths.first),
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(Icons.picture_as_pdf_rounded,
                                        color: doc.iconColor, size: 24),
                              ),
                            ),
                            if (_selectMode)
                              Positioned(
                                top: 2, left: 2,
                                child: Container(
                                  width: 20, height: 20,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppTheme.primary
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? AppTheme.primary
                                          : Colors.grey.shade400,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: selected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 12)
                                      : null,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(doc.meta,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textGray)),
                            ],
                          ),
                        ),
                        if (!_selectMode)
                          GestureDetector(
                            onTap: () => _showOptions(doc),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.more_vert,
                                  color: AppTheme.textGray, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
