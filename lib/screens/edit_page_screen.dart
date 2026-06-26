import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app_theme.dart';
import '../data/document_store.dart';
import '../utils/image_processor.dart';

class EditPageScreen extends StatefulWidget {
  final List<String> imagePaths;
  const EditPageScreen({super.key, required this.imagePaths});

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  late List<String> _imagePaths;
  int _selectedFilter = 0;
  int _selectedPage = 0;
  bool _saving = false;
  late final TextEditingController _nameCtrl;

  static const _filterLabels = ['Original', 'B&W', 'Magic', 'Text', 'Sepia'];

  @override
  void initState() {
    super.initState();
    _imagePaths = [...widget.imagePaths]; // mutable copy for reorder
    final n = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    _nameCtrl = TextEditingController(
        text: 'Scan ${months[n.month - 1]} ${n.day}, ${n.year}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _reorderPages(int oldIdx, int newIdx) {
    setState(() {
      final item = _imagePaths.removeAt(oldIdx);
      _imagePaths.insert(newIdx, item);
      // Keep selected page tracking correct
      if (_selectedPage == oldIdx) {
        _selectedPage = newIdx;
      } else if (_selectedPage > oldIdx && _selectedPage <= newIdx) {
        _selectedPage--;
      } else if (_selectedPage < oldIdx && _selectedPage >= newIdx) {
        _selectedPage++;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);

      final processedPaths = <String>[];
      for (final path in _imagePaths) {
        final raw = await File(path).readAsBytes();
        final processed = await compute(processImageFilter, {
          'bytes': raw,
          'filterIndex': _selectedFilter,
        });
        final ts = DateTime.now().microsecondsSinceEpoch;
        final outPath = '${scanDir.path}/${ts}_f.jpg';
        await File(outPath).writeAsBytes(processed);
        processedPaths.add(outPath);
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
        sizeBytes: pdfBytes.length,
      );

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
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
          if (_imagePaths.length > 1) _buildPageStrip(),
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
        left: 16, right: 16, bottom: 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
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
              : GestureDetector(
                  onTap: _save,
                  child: const Text('Save',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final path = _imagePaths[_selectedPage];
    final file = File(path);
    final matrix = filterMatrices[_selectedFilter];
    Widget img = file.existsSync()
        ? Image.file(file, fit: BoxFit.contain)
        : Container(
            color: const Color(0xFFF5F5F0),
            child: const Center(
              child: Icon(Icons.description_outlined,
                  size: 80, color: Colors.grey),
            ),
          );
    if (matrix != null) {
      img = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix), child: img);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(6), child: img),
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
        itemCount: _imagePaths.length,
        itemBuilder: (_, i) {
          final selected = i == _selectedPage;
          final file = File(_imagePaths[i]);
          return GestureDetector(
            key: ValueKey(_imagePaths[i]),
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
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(color: Colors.grey.shade800),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterStrip() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _filterLabels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final selected = i == _selectedFilter;
          final matrix = filterMatrices[i];
          final file = File(_imagePaths[_selectedPage]);
          Widget thumb = file.existsSync()
              ? Image.file(file, fit: BoxFit.cover)
              : Container(color: Colors.grey.shade700);
          if (matrix != null) {
            thumb = ColorFiltered(
                colorFilter: ColorFilter.matrix(matrix), child: thumb);
          }
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = i),
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
          _ToolBtn(icon: Icons.crop, label: 'Crop', onTap: () {}),
          _ToolBtn(icon: Icons.rotate_right, label: 'Rotate', onTap: () {}),
          _ToolBtn(icon: Icons.text_fields, label: 'Text', onTap: () {}),
          _ToolBtn(icon: Icons.tune, label: 'Adjust', onTap: () {}),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
