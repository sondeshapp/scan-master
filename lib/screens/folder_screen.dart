import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../data/document_store.dart';
import '../data/models.dart';
import 'document_viewer_screen.dart';
import 'scanner_screen.dart';

class FolderScreen extends StatefulWidget {
  final ScanFolder folder;
  const FolderScreen({super.key, required this.folder});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final _store = DocumentStore.instance;
  final Set<String> _selectedIds = {};
  late ScanFolder _folder;

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
  }

  bool get _selectMode => _selectedIds.isNotEmpty;
  List<ScanDocument> get _docs => _store.documentsInFolder(_folder.id);

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

  Future<void> _scanIntoFolder() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(initialFolderId: _folder.id),
      ),
    );
    if (mounted) setState(() {});
  }

  void _showEditFolderDialog() {
    final nameCtrl = TextEditingController(text: _folder.name);
    final colors = [
      AppTheme.folderBlue,
      AppTheme.folderOrange,
      AppTheme.folderGreen,
      AppTheme.folderPurple,
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
    ];
    int selectedColor = colors.indexWhere(
      (c) => c.toARGB32() == _folder.colorValue,
    );
    if (selectedColor < 0) selectedColor = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit Folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Folder name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(colors.length, (i) {
                  return GestureDetector(
                    onTap: () => setS(() => selectedColor = i),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                        border: selectedColor == i
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                        boxShadow: selectedColor == i
                            ? [
                                BoxShadow(
                                    color: colors[i].withAlpha(120),
                                    blurRadius: 8)
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final newColor = colors[selectedColor].toARGB32();
                Navigator.pop(ctx);
                await _store.updateFolder(
                  _folder.id,
                  name: name,
                  colorValue: newColor,
                );
                if (mounted) {
                  setState(() {
                    _folder = _folder.copyWith(
                      name: name,
                      colorValue: newColor,
                    );
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFolder() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "${_folder.name}"? Documents inside will be moved to Uncategorized Files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _store.deleteFolder(_folder.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameDocDialog(ScanDocument doc) {
    final ctrl = TextEditingController(text: doc.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _store.renameDocument(doc.id, name);
              if (mounted) setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMoveDocDialog(ScanDocument doc) {
    final folders = _store.folders.toList();
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
                onTap: () async {
                  Navigator.pop(dialogCtx);
                  await _store.moveDocument(doc.id, null);
                  if (mounted) setState(() {});
                },
              ),
              ...folders.map((f) => ListTile(
                    leading: Icon(Icons.folder_rounded, color: f.color),
                    title: Text(f.name),
                    selected: doc.folderId == f.id,
                    onTap: () async {
                      Navigator.pop(dialogCtx);
                      await _store.moveDocument(doc.id, f.id);
                      if (mounted) setState(() {});
                    },
                  )),
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

  void _showOptions(ScanDocument doc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openViewer(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showRenameDocDialog(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final file = File(doc.pdfPath);
                if (await file.exists()) {
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(doc.pdfPath, mimeType: 'application/pdf')],
                      subject: doc.name,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showMoveDocDialog(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Remove from folder'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _store.moveDocument(doc.id, null);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Delete Document'),
                    content: Text('Delete "${doc.name}"?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () async {
                          Navigator.pop(dialogCtx);
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
            : Text(_folder.name),
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
            : [
                PopupMenuButton<String>(
                  tooltip: 'Folder options',
                  onSelected: (v) {
                    if (v == 'edit') {
                      _showEditFolderDialog();
                    } else if (v == 'delete') {
                      _confirmDeleteFolder();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Folder')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Folder',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.separator),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanIntoFolder,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        tooltip: 'Scan to ${_folder.name}',
        child: const Icon(Icons.add),
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
                    'This folder is empty\nTap + to scan directly into this folder',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGray, fontSize: 15),
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
                  onLongPress: () => setState(() => _selectedIds.add(doc.id)),
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
                              width: 48,
                              height: 60,
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
                                        cacheWidth: 180,
                                      )
                                    : Icon(Icons.picture_as_pdf_rounded,
                                        color: doc.iconColor, size: 24),
                              ),
                            ),
                            if (_selectMode)
                              Positioned(
                                top: 2,
                                left: 2,
                                child: Container(
                                  width: 20,
                                  height: 20,
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
                          Semantics(
                            button: true,
                            label: 'More options for ${doc.name}',
                            child: GestureDetector(
                              onTap: () => _showOptions(doc),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.more_vert,
                                    color: AppTheme.textGray, size: 20),
                              ),
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
