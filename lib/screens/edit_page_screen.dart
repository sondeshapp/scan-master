import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app_theme.dart';
import '../data/document_store.dart';
import '../utils/image_processor.dart';

class _PageEditState {
  final String path;
  int filterIndex = 0;
  int quarterTurns = 0;
  double cropMargin = 0.0;
  double brightness = 1.0;
  double contrast = 1.0;

  _PageEditState({required this.path});
}

class EditPageScreen extends StatefulWidget {
  final List<String> imagePaths;
  final String? initialFolderId;

  const EditPageScreen({
    super.key,
    required this.imagePaths,
    this.initialFolderId,
  });

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  late List<_PageEditState> _pages;
  int _selectedPage = 0;
  bool _saving = false;
  String? _selectedFolderId;
  late final TextEditingController _nameCtrl;

  static const _filterLabels = ['Original', 'B&W', 'Magic', 'Text', 'Sepia'];

  _PageEditState get _current => _pages[_selectedPage];

  @override
  void initState() {
    super.initState();
    _pages = widget.imagePaths.map((p) => _PageEditState(path: p)).toList();
    _selectedFolderId = widget.initialFolderId;
    final n = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    _nameCtrl = TextEditingController(
      text: 'Scan ${months[n.month - 1]} ${n.day}, ${n.year}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _reorderPages(int oldIdx, int newIdx) {
    setState(() {
      final item = _pages.removeAt(oldIdx);
      _pages.insert(newIdx, item);
      if (_selectedPage == oldIdx) {
        _selectedPage = newIdx;
      } else if (_selectedPage > oldIdx && _selectedPage <= newIdx) {
        _selectedPage--;
      } else if (_selectedPage < oldIdx && _selectedPage >= newIdx) {
        _selectedPage++;
      }
    });
  }

  void _rotateCurrentPage() {
    setState(() {
      _current.quarterTurns = (_current.quarterTurns + 1) % 4;
    });
  }

  void _cycleCrop() {
    setState(() {
      if (_current.cropMargin == 0.0) {
        _current.cropMargin = 0.06;
      } else if (_current.cropMargin == 0.06) {
        _current.cropMargin = 0.12;
      } else {
        _current.cropMargin = 0.0;
      }
    });
    final label = _current.cropMargin == 0.0
        ? 'Crop: Full page'
        : _current.cropMargin == 0.06
            ? 'Crop: Auto margin (6%)'
            : 'Crop: Tight margin (12%)';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(label),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  void _deleteCurrentPage() {
    if (_pages.length <= 1) return;
    final removedPath = _current.path;
    setState(() {
      _pages.removeAt(_selectedPage);
      if (_selectedPage >= _pages.length) {
        _selectedPage = _pages.length - 1;
      }
    });
    try {
      final f = File(removedPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _showAdjustSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Adjust Page',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _current.brightness = 1.0;
                          _current.contrast = 1.0;
                        });
                        setSheetState(() {});
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.light_mode_outlined,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 76,
                      child: Text('Brightness',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                    Expanded(
                      child: Slider(
                        value: _current.brightness,
                        min: 0.6,
                        max: 1.4,
                        activeColor: AppTheme.primary,
                        onChanged: (v) {
                          setState(() => _current.brightness = v);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.contrast_rounded,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 76,
                      child: Text('Contrast',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                    Expanded(
                      child: Slider(
                        value: _current.contrast,
                        min: 0.6,
                        max: 1.6,
                        activeColor: AppTheme.primary,
                        onChanged: (v) {
                          setState(() => _current.contrast = v);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);

      final processedPaths = <String>[];
      for (final page in _pages) {
        final rawFile = File(page.path);
        final raw = await rawFile.readAsBytes();
        final processed = await compute(processImageFilter, {
          'bytes': raw,
          'filterIndex': page.filterIndex,
          'quarterTurns': page.quarterTurns,
          'cropMargin': page.cropMargin,
          'brightness': page.brightness,
          'contrast': page.contrast,
        });
        final ts = DateTime.now().microsecondsSinceEpoch;
        final outPath = '${scanDir.path}/${ts}_f.jpg';
        await File(outPath).writeAsBytes(processed);
        processedPaths.add(outPath);

        // Clean up raw intermediate capture file so it isn't orphaned
        if (rawFile.path != outPath && await rawFile.exists()) {
          try {
            await rawFile.delete();
          } catch (_) {}
        }
      }

      final pdf = pw.Document();
      for (final imgPath in processedPaths) {
        final imgBytes = await File(imgPath).readAsBytes();
        final pdfImg = pw.MemoryImage(imgBytes);
        pdf.addPage(
          pw.Page(build: (c) => pw.Center(child: pw.Image(pdfImg))),
        );
      }

      final pdfDir = Directory('${dir.path}/pdfs');
      await pdfDir.create(recursive: true);
      final pdfPath =
          '${pdfDir.path}/${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfBytes = await pdf.save();
      await File(pdfPath).writeAsBytes(pdfBytes);

      final docName = _nameCtrl.text.trim().isEmpty
          ? 'Untitled Scan'
          : _nameCtrl.text.trim();
      await DocumentStore.instance.addDocument(
        name: docName,
        pdfPath: pdfPath,
        pageImagePaths: processedPaths,
        folderId: _selectedFolderId,
        sizeBytes: pdfBytes.length,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildPreview()),
          if (_pages.length > 1) _buildPageStrip(),
          _buildFilterStrip(),
          _buildToolBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Semantics(
                  button: true,
                  label: 'Save document',
                  child: GestureDetector(
                    onTap: _save,
                    child: const Text('Save',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final page = _current;
    final file = File(page.path);
    final matrix = buildPreviewMatrix(
      filterIndex: page.filterIndex,
      brightness: page.brightness,
      contrast: page.contrast,
    );

    Widget img = file.existsSync()
        ? Image.file(file, fit: BoxFit.contain)
        : Container(
            color: const Color(0xFFF5F5F0),
            child: const Center(
              child: Icon(Icons.description_outlined,
                  size: 80, color: Colors.grey),
            ),
          );

    if (page.quarterTurns != 0) {
      img = RotatedBox(quarterTurns: page.quarterTurns, child: img);
    }
    if (matrix != null) {
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: img,
      );
    }
    if (page.cropMargin > 0) {
      img = Stack(
        alignment: Alignment.center,
        children: [
          img,
          IgnorePointer(
            child: FractionallySizedBox(
              widthFactor: 1.0 - (page.cropMargin * 2),
              heightFactor: 1.0 - (page.cropMargin * 2),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: img),
    );
  }

  // Drag to reorder pages before saving
  Widget _buildPageStrip() {
    return SizedBox(
      height: 80,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onReorderItem: _reorderPages,
        itemCount: _pages.length,
        itemBuilder: (_, i) {
          final selected = i == _selectedPage;
          final page = _pages[i];
          final file = File(page.path);
          final matrix = buildPreviewMatrix(
            filterIndex: page.filterIndex,
            brightness: page.brightness,
            contrast: page.contrast,
          );
          Widget thumb = file.existsSync()
              ? Image.file(file, fit: BoxFit.cover, cacheWidth: 160)
              : Container(color: Colors.grey.shade800);
          if (page.quarterTurns != 0) {
            thumb = RotatedBox(quarterTurns: page.quarterTurns, child: thumb);
          }
          if (matrix != null) {
            thumb = ColorFiltered(
              colorFilter: ColorFilter.matrix(matrix),
              child: thumb,
            );
          }
          return GestureDetector(
            key: ValueKey(page.path),
            onTap: () => setState(() => _selectedPage = i),
            child: Container(
              width: 52,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? AppTheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: thumb,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterStrip() {
    final page = _current;
    return SizedBox(
      height: 108,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _filterLabels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final selected = i == page.filterIndex;
          final matrix = filterMatrices[i];
          final file = File(page.path);
          Widget thumb = file.existsSync()
              ? Image.file(file, fit: BoxFit.cover, cacheWidth: 160)
              : Container(color: Colors.grey.shade700);
          if (page.quarterTurns != 0) {
            thumb = RotatedBox(quarterTurns: page.quarterTurns, child: thumb);
          }
          if (matrix != null) {
            thumb = ColorFiltered(
                colorFilter: ColorFilter.matrix(matrix), child: thumb);
          }
          return GestureDetector(
            onTap: () => setState(() => page.filterIndex = i),
            onLongPress: () {
              setState(() {
                for (final p in _pages) {
                  p.filterIndex = i;
                }
              });
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                        'Applied ${_filterLabels[i]} filter to all ${_pages.length} pages'),
                    duration: const Duration(milliseconds: 1200),
                  ),
                );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppTheme.primary : Colors.white24,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: thumb,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _filterLabels[i],
                  style: TextStyle(
                    color: selected ? AppTheme.primary : Colors.white60,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ToolBtn(
            icon: Icons.crop,
            label: _current.cropMargin > 0 ? 'Cropped' : 'Crop',
            active: _current.cropMargin > 0,
            onTap: _cycleCrop,
          ),
          _ToolBtn(
            icon: Icons.rotate_right,
            label: 'Rotate',
            active: _current.quarterTurns != 0,
            onTap: _rotateCurrentPage,
          ),
          _ToolBtn(
            icon: Icons.tune,
            label: 'Adjust',
            active: _current.brightness != 1.0 || _current.contrast != 1.0,
            onTap: _showAdjustSheet,
          ),
          if (_pages.length > 1)
            _ToolBtn(
              icon: Icons.delete_outline,
              label: 'Delete Page',
              onTap: _deleteCurrentPage,
            )
          else
            _ToolBtn(
              icon: Icons.text_fields,
              label: 'Text Mode',
              active: _current.filterIndex == 3,
              onTap: () => setState(() => _current.filterIndex = 3),
            ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.primary : Colors.white70;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppTheme.primary : Colors.white54,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
