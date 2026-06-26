import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../data/document_store.dart';
import '../data/models.dart';
import 'scanner_screen.dart';
import 'search_screen.dart';
import 'folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = DocumentStore.instance;
  int _navIndex = 0;

  Future<void> _openScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (mounted) setState(() {});
  }

  void _showNewFolderDialog() {
    final nameCtrl = TextEditingController();
    final colors = [
      AppTheme.folderBlue,
      AppTheme.folderOrange,
      AppTheme.folderGreen,
      AppTheme.folderPurple,
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
    ];
    int selectedColor = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New Folder'),
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
                            ? [BoxShadow(color: colors[i].withAlpha(120), blurRadius: 8)]
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
                Navigator.pop(ctx);
                await _store.createFolder(name, colors[selectedColor].toARGB32());
                if (mounted) setState(() {});
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileOptions(ScanDocument doc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FileOptionsSheet(
        doc: doc,
        folders: _store.folders.toList(),
        onDelete: () async {
          await _store.deleteDocument(doc.id);
          if (mounted) setState(() {});
        },
        onRename: (newName) async {
          await _store.renameDocument(doc.id, newName);
          if (mounted) setState(() {});
        },
        onMove: (folderId) async {
          await _store.moveDocument(doc.id, folderId);
          if (mounted) setState(() {});
        },
        onShare: () async {
          final file = File(doc.pdfPath);
          if (await file.exists()) {
            await Share.shareXFiles(
              [XFile(doc.pdfPath, mimeType: 'application/pdf')],
              subject: doc.name,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final folders = _store.folders;
    final uncategorized = _store.uncategorized;

    return Scaffold(
      backgroundColor: AppTheme.bgGray,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(bottom: safeBottom + 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
                _buildHeader(),
                _buildSearchBar(),
                const SizedBox(height: 24),
                _buildFoldersSection(folders),
                const SizedBox(height: 24),
                _buildFilesSection(uncategorized),
              ],
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomBar(safeBottom),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Folders',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
              letterSpacing: -0.5,
            ),
          ),
          GestureDetector(
            onTap: _showNewFolderDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: AppTheme.primary),
                  SizedBox(width: 4),
                  Text(
                    'New Folder',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
          if (mounted) setState(() {});
        },
        child: Container(
          height: 47,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.separator),
          ),
          child: const Row(
            children: [
              SizedBox(width: 16),
              Icon(Icons.search, color: AppTheme.textGray, size: 20),
              SizedBox(width: 12),
              Text(
                'Search folders and files',
                style: TextStyle(color: AppTheme.textGray, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersSection(List<ScanFolder> folders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Folders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View All',
                    style: TextStyle(color: AppTheme.primary, fontSize: 14)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _showNewFolderDialog,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.separator, style: BorderStyle.solid),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.create_new_folder_outlined, color: AppTheme.textGray, size: 28),
                      SizedBox(height: 6),
                      Text('Create a folder', style: TextStyle(color: AppTheme.textGray)),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.26,
            ),
            itemCount: folders.length,
            itemBuilder: (_, i) {
              final f = folders[i];
              final count = _store.folderFileCount(f.id);
              return _FolderCard(
                folder: f,
                fileCount: count,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderScreen(folder: f),
                  ),
                ).then((_) => setState(() {})),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilesSection(List<ScanDocument> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Uncategorized Files',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('See All',
                    style: TextStyle(color: AppTheme.primary, fontSize: 14)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (docs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.description_outlined, size: 40, color: AppTheme.textGray),
                  SizedBox(height: 8),
                  Text(
                    'No documents yet\nTap + to scan your first document',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGray, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _FileCard(
              doc: docs[i],
              onMoreTap: () => _showFileOptions(docs[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(double safeBottom) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, safeBottom + 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(224),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.separator.withAlpha(153)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _NavBtn(
                        icon: Icons.home_rounded,
                        selected: _navIndex == 0,
                        onTap: () => setState(() => _navIndex = 0),
                      ),
                      _NavBtn(
                        icon: Icons.search_rounded,
                        selected: _navIndex == 1,
                        onTap: () async {
                          setState(() => _navIndex = 1);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SearchScreen()),
                          );
                          if (mounted) setState(() => _navIndex = 0);
                        },
                      ),
                      _NavBtn(
                        icon: Icons.folder_outlined,
                        selected: _navIndex == 2,
                        onTap: () => setState(() => _navIndex = 2),
                      ),
                      _NavBtn(
                        icon: Icons.history_rounded,
                        label: 'Recents',
                        selected: _navIndex == 3,
                        onTap: () => setState(() => _navIndex = 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _openScanner,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(102),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    this.label = '',
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textGray;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final ScanFolder folder;
  final int fileCount;
  final VoidCallback onTap;

  const _FolderCard({
    required this.folder,
    required this.fileCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.separator.withAlpha(128)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: folder.color.withAlpha(31),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.folder_rounded, color: folder.color, size: 28),
            ),
            const Spacer(),
            Text(
              folder.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$fileCount ${fileCount == 1 ? "file" : "files"}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final ScanDocument doc;
  final VoidCallback onMoreTap;

  const _FileCard({required this.doc, required this.onMoreTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.separator.withAlpha(128)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: doc.iconColor.withAlpha(31),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.picture_as_pdf_rounded,
                color: doc.iconColor, size: 24),
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
                Text(
                  doc.meta,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onMoreTap,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.more_vert, color: AppTheme.textGray, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// File options bottom sheet
// ──────────────────────────────────────────────────────────────

class _FileOptionsSheet extends StatelessWidget {
  final ScanDocument doc;
  final List<ScanFolder> folders;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;
  final ValueChanged<String?> onMove;
  final VoidCallback onShare;

  const _FileOptionsSheet({
    required this.doc,
    required this.folders,
    required this.onDelete,
    required this.onRename,
    required this.onMove,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              doc.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          _Option(
            icon: Icons.edit_outlined,
            label: 'Rename',
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(context);
            },
          ),
          _Option(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () {
              Navigator.pop(context);
              onShare();
            },
          ),
          if (folders.isNotEmpty)
            _Option(
              icon: Icons.drive_file_move_outlined,
              label: 'Move to folder',
              onTap: () {
                Navigator.pop(context);
                _showMoveDialog(context);
              },
            ),
          _Option(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: Colors.red,
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: doc.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                onRename(name);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (doc.folderId != null)
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Uncategorized'),
                  onTap: () {
                    Navigator.pop(context);
                    onMove(null);
                  },
                ),
              ...folders.map((f) => ListTile(
                    leading: Icon(Icons.folder_rounded, color: f.color),
                    title: Text(f.name),
                    selected: doc.folderId == f.id,
                    onTap: () {
                      Navigator.pop(context);
                      onMove(f.id);
                    },
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete "${doc.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textDark;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
