import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app_theme.dart';
import '../data/document_store.dart';
import '../utils/image_processor.dart';

class _PageEditState {
  final String path;
  String? croppedPreviewPath;
  int filterIndex = 0;
  int quarterTurns = 0;

  /// 4 independent normalized corners: [0]=topLeft, [1]=topRight, [2]=bottomRight, [3]=bottomLeft
  List<Offset> corners = [
    const Offset(0.0, 0.0),
    const Offset(1.0, 0.0),
    const Offset(1.0, 1.0),
    const Offset(0.0, 1.0),
  ];

  double brightness = 1.0;
  double contrast = 1.0;
  Size? intrinsicSize;

  _PageEditState({required this.path});

  static List<Offset> fullCorners() => [
        const Offset(0.0, 0.0),
        const Offset(1.0, 0.0),
        const Offset(1.0, 1.0),
        const Offset(0.0, 1.0),
      ];

  static List<Offset> autoMarginCorners() => [
        const Offset(0.06, 0.06),
        const Offset(0.94, 0.06),
        const Offset(0.94, 0.94),
        const Offset(0.06, 0.94),
      ];

  bool get isCropped =>
      (corners[0] - const Offset(0.0, 0.0)).distance > 0.008 ||
      (corners[1] - const Offset(1.0, 0.0)).distance > 0.008 ||
      (corners[2] - const Offset(1.0, 1.0)).distance > 0.008 ||
      (corners[3] - const Offset(0.0, 1.0)).distance > 0.008;

  Rect get boundingCropRect {
    final xs = corners.map((c) => c.dx);
    final ys = corners.map((c) => c.dy);
    final l = xs.reduce(math.min).clamp(0.0, 1.0);
    final t = ys.reduce(math.min).clamp(0.0, 1.0);
    final r = xs.reduce(math.max).clamp(l + 0.05, 1.0);
    final b = ys.reduce(math.max).clamp(t + 0.05, 1.0);
    return Rect.fromLTRB(l, t, r, b);
  }

  double get rotatedAspectRatio {
    final s = intrinsicSize;
    if (s == null || s.width <= 0 || s.height <= 0) {
      return (quarterTurns % 2 == 1) ? (4.0 / 3.0) : (3.0 / 4.0);
    }
    return (quarterTurns % 2 == 1)
        ? (s.height / s.width)
        : (s.width / s.height);
  }
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
  bool _isCropping = false;
  bool _applyFilterToAll = false;
  List<Offset> _draftCorners = _PageEditState.fullCorners();
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
    _loadIntrinsicSizes();
  }

  Future<void> _loadIntrinsicSizes() async {
    for (final page in _pages) {
      await _decodePageSize(page);
    }
    if (mounted) setState(() {});
  }

  Future<void> _decodePageSize(_PageEditState page) async {
    if (page.intrinsicSize != null) return;
    try {
      final f = File(page.path);
      if (!f.existsSync()) return;
      final bytes = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      page.intrinsicSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final p in _pages) {
      _cleanupPreviewFile(p.croppedPreviewPath);
    }
    _nameCtrl.dispose();
    super.dispose();
  }

  void _cleanupPreviewFile(String? previewPath) {
    if (previewPath == null) return;
    try {
      final f = File(previewPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _rebuildCroppedPreview(_PageEditState page) async {
    _cleanupPreviewFile(page.croppedPreviewPath);
    page.croppedPreviewPath = null;
    if (!page.isCropped) {
      if (mounted) setState(() {});
      return;
    }
    final srcFile = File(page.path);
    if (!srcFile.existsSync()) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final raw = await srcFile.readAsBytes();
      final c = _unrotatedCorners(page);
      final unwarped = await compute(unwarpPageQuadPreview, {
        'bytes': raw,
        'quarterTurns': 0,
        'tlX': c[0].dx,
        'tlY': c[0].dy,
        'trX': c[1].dx,
        'trY': c[1].dy,
        'brX': c[2].dx,
        'brY': c[2].dy,
        'blX': c[3].dx,
        'blY': c[3].dy,
      });
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/crop_prev_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(unwarped);
      page.croppedPreviewPath = outPath;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _selectPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    if (_isCropping) {
      _applyCropMode();
    }
    setState(() {
      _selectedPage = index;
    });
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

  List<Offset> _rotateCornerListCW(List<Offset> src) {
    final rot = src.map((p) => Offset(1.0 - p.dy, p.dx)).toList();
    return [rot[3], rot[0], rot[1], rot[2]];
  }

  void _rotateCurrentPage() {
    setState(() {
      _current.quarterTurns = (_current.quarterTurns + 1) % 4;
      _current.corners = _rotateCornerListCW(_current.corners);
      if (_isCropping) {
        _draftCorners = _rotateCornerListCW(_draftCorners);
      }
    });
  }

  void _toggleCropMode() {
    if (_isCropping) {
      _applyCropMode();
    } else {
      setState(() {
        _draftCorners = List<Offset>.from(_current.corners);
        _isCropping = true;
      });
    }
  }

  void _cancelCropMode() {
    setState(() {
      _isCropping = false;
    });
  }

  void _applyCropMode() {
    final page = _current;
    setState(() {
      page.corners = List<Offset>.from(_draftCorners);
      _isCropping = false;
    });
    _rebuildCroppedPreview(page);
  }

  Future<void> _addPagesFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final scanDir = Directory('${dir.path}/scans');
    await scanDir.create(recursive: true);

    final added = <_PageEditState>[];
    final baseTs = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < picked.length; i++) {
      final bytes = await File(picked[i].path).readAsBytes();
      final dest = '${scanDir.path}/${baseTs}_add_$i.jpg';
      await File(dest).writeAsBytes(bytes);
      final state = _PageEditState(path: dest);
      await _decodePageSize(state);
      added.add(state);
    }

    if (mounted && added.isNotEmpty) {
      setState(() {
        _pages.addAll(added);
        _selectedPage = _pages.length - 1;
      });
    }
  }

  void _deleteCurrentPage() {
    if (_pages.length <= 1) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            'Discard Scan?',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          content: const Text(
            'This is the only page in the scan. Do you want to discard it and go back?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Discard',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ).then((discard) {
        if (discard == true && mounted) {
          Navigator.pop(context, false);
        }
      });
      return;
    }

    final removed = _current;
    _cleanupPreviewFile(removed.croppedPreviewPath);
    setState(() {
      _isCropping = false;
      _pages.removeAt(_selectedPage);
      if (_selectedPage >= _pages.length) {
        _selectedPage = _pages.length - 1;
      }
    });
    try {
      final f = File(removed.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _showAdjustSheet() {
    if (_isCropping) {
      _applyCropMode();
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bPct = ((_current.brightness - 1.0) * 100).round();
          final cPct = ((_current.contrast - 1.0) * 100).round();
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_pages.length > 1)
                            TextButton(
                              onPressed: () {
                                final b = _current.brightness;
                                final c = _current.contrast;
                                setState(() {
                                  for (final p in _pages) {
                                    p.brightness = b;
                                    p.contrast = c;
                                  }
                                });
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Applied adjustments to all ${_pages.length} pages',
                                      ),
                                      duration:
                                          const Duration(milliseconds: 1200),
                                    ),
                                  );
                              },
                              child: const Text('Apply to All'),
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.light_mode_outlined,
                          color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 72,
                        child: Text('Brightness',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
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
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${bPct >= 0 ? '+' : ''}$bPct%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.contrast_rounded,
                          color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 72,
                        child: Text('Contrast',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
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
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${cPct >= 0 ? '+' : ''}$cPct%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Converts `page.corners` from `quarterTurns`-rotated space back to 0-turn space.
  List<Offset> _unrotatedCorners(_PageEditState page) {
    var list = List<Offset>.from(page.corners);
    final inverseTurns = (4 - (page.quarterTurns % 4)) % 4;
    for (var t = 0; t < inverseTurns; t++) {
      list = _rotateCornerListCW(list);
    }
    return list;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_isCropping) {
      _current.corners = List<Offset>.from(_draftCorners);
      _isCropping = false;
    }
    setState(() => _saving = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);

      final processedPaths = <String>[];
      final baseTs = DateTime.now().microsecondsSinceEpoch;

      for (var i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        final rawFile = File(page.path);
        final raw = await rawFile.readAsBytes();
        final c = page.corners;
        final processed = await compute(processImageFilter, {
          'bytes': raw,
          'filterIndex': page.filterIndex,
          'quarterTurns': page.quarterTurns,
          'tlX': c[0].dx,
          'tlY': c[0].dy,
          'trX': c[1].dx,
          'trY': c[1].dy,
          'brX': c[2].dx,
          'brY': c[2].dy,
          'blX': c[3].dx,
          'blY': c[3].dy,
          'brightness': page.brightness,
          'contrast': page.contrast,
        });
        final outPath = '${scanDir.path}/${baseTs}_p${i + 1}_f.jpg';
        await File(outPath).writeAsBytes(processed);
        processedPaths.add(outPath);

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
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (c) => pw.Center(
              child: pw.Image(pdfImg, fit: pw.BoxFit.contain),
            ),
          ),
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
          if (_isCropping)
            _buildCropActionBar()
          else ...[
            _buildPageStrip(),
            _buildFilterStrip(),
          ],
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
              onTap: () {
                if (_isCropping) {
                  _cancelCropMode();
                } else {
                  Navigator.pop(context, false);
                }
              },
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
                  label: _isCropping ? 'Apply crop' : 'Save document',
                  child: GestureDetector(
                    onTap: _isCropping ? _applyCropMode : _save,
                    child: Text(
                      _isCropping ? 'Done' : 'Save',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

    if (!file.existsSync()) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xFFF5F5F0),
        child: const Center(
          child: Icon(Icons.description_outlined, size: 80, color: Colors.grey),
        ),
      );
    }

    if (_isCropping) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: _InteractiveQuadCropStage(
          file: file,
          quarterTurns: page.quarterTurns,
          aspectRatio: page.rotatedAspectRatio,
          colorMatrix: matrix,
          corners: _draftCorners,
          onCornersChanged: (next) => setState(() => _draftCorners = next),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: _pages.length > 1
          ? (details) {
              final vx = details.primaryVelocity ?? 0.0;
              if (vx < -250 && _selectedPage < _pages.length - 1) {
                _selectPage(_selectedPage + 1);
              } else if (vx > 250 && _selectedPage > 0) {
                _selectPage(_selectedPage - 1);
              }
            }
          : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Center(
              child: _CroppedPageView(
                page: page,
                colorMatrix: matrix,
              ),
            ),
          ),
          if (_pages.length > 1)
            Positioned(
              bottom: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(165),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Page ${_selectedPage + 1} of ${_pages.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Overflow-safe crop action bar with Cancel, Full, Auto Margin, and Apply.
  Widget _buildCropActionBar() {
    return Container(
      height: 50,
      color: const Color(0xFF141416),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _CropBarBtn(
              icon: Icons.close_rounded,
              label: 'Cancel',
              color: Colors.white70,
              onTap: _cancelCropMode,
            ),
          ),
          Expanded(
            child: _CropBarBtn(
              label: 'Full',
              color: Colors.white,
              onTap: () => setState(() {
                _draftCorners = _PageEditState.fullCorners();
              }),
            ),
          ),
          Expanded(
            child: _CropBarBtn(
              label: 'Auto Margin',
              color: Colors.white,
              onTap: () => setState(() {
                _draftCorners = _PageEditState.autoMarginCorners();
              }),
            ),
          ),
          Expanded(
            child: _CropBarBtn(
              icon: Icons.check_rounded,
              label: 'Apply',
              color: AppTheme.primary,
              bold: true,
              onTap: _applyCropMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageStrip() {
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
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
                return GestureDetector(
                  key: ValueKey(page.path),
                  onTap: () => _selectPage(i),
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? AppTheme.primary : Colors.white24,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          file.existsSync()
                              ? _CroppedPageView(
                                  page: page,
                                  colorMatrix: matrix,
                                  fit: BoxFit.cover,
                                  cacheWidth: 180,
                                )
                              : Container(color: Colors.grey.shade800),
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(160),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Semantics(
              button: true,
              label: 'Add page',
              child: GestureDetector(
                onTap: _addPagesFromGallery,
                child: Container(
                  width: 46,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 22),
                      Text(
                        'Add',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterStrip() {
    final page = _current;
    final allSynced = _pages.length > 1 &&
        _pages.every((p) => p.filterIndex == page.filterIndex);
    final isApplyAllActive = _applyFilterToAll || (allSynced && page.filterIndex != 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Effect: ${_filterLabels[page.filterIndex]}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _applyFilterToAll = !_applyFilterToAll;
                    if (_applyFilterToAll) {
                      for (final p in _pages) {
                        p.filterIndex = page.filterIndex;
                      }
                    }
                  });
                  if (_applyFilterToAll) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Applied ${_filterLabels[page.filterIndex]} to all ${_pages.length} pages',
                          ),
                          duration: const Duration(milliseconds: 1100),
                        ),
                      );
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isApplyAllActive
                        ? AppTheme.primary.withAlpha(38)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isApplyAllActive ? AppTheme.primary : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isApplyAllActive
                            ? Icons.check_circle_rounded
                            : Icons.done_all_rounded,
                        color: isApplyAllActive
                            ? AppTheme.primary
                            : Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Apply to all pages',
                        style: TextStyle(
                          color: isApplyAllActive
                              ? AppTheme.primary
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: isApplyAllActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: _filterLabels.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final selected = i == page.filterIndex;
              final matrix = buildPreviewMatrix(
                filterIndex: i,
                brightness: page.brightness,
                contrast: page.contrast,
              );
              final file = File(page.path);
              return GestureDetector(
                onTap: () => setState(() {
                  if (_applyFilterToAll) {
                    for (final p in _pages) {
                      p.filterIndex = i;
                    }
                  } else {
                    page.filterIndex = i;
                  }
                }),
                onLongPress: () {
                  setState(() {
                    _applyFilterToAll = true;
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
                      width: 56,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? AppTheme.primary : Colors.white24,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: file.existsSync()
                            ? _CroppedPageView(
                                page: page,
                                colorMatrix: matrix,
                                fit: BoxFit.cover,
                                cacheWidth: 160,
                              )
                            : Container(color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _filterLabels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ),
      ],
    );
  }

  Widget _buildToolBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _ToolBtn(
              icon: Icons.crop_rounded,
              label: _isCropping
                  ? 'Apply Crop'
                  : (_current.isCropped ? 'Cropped' : 'Crop'),
              active: _isCropping || _current.isCropped,
              onTap: _toggleCropMode,
            ),
          ),
          Expanded(
            child: _ToolBtn(
              icon: Icons.rotate_right_rounded,
              label: 'Rotate',
              active: _current.quarterTurns != 0,
              onTap: _rotateCurrentPage,
            ),
          ),
          Expanded(
            child: _ToolBtn(
              icon: Icons.tune_rounded,
              label: 'Adjust',
              active: _current.brightness != 1.0 || _current.contrast != 1.0,
              onTap: _showAdjustSheet,
            ),
          ),
          Expanded(
            child: _ToolBtn(
              icon: Icons.delete_outline_rounded,
              label: _pages.length > 1 ? 'Delete Page' : 'Discard',
              onTap: _deleteCurrentPage,
            ),
          ),
        ],
      ),
    );
  }
}

class _CropBarBtn extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final bool bold;
  final VoidCallback onTap;

  const _CropBarBtn({
    this.icon,
    required this.label,
    required this.color,
    this.bold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the rotated, color-filtered, and 4-corner unwarped/cropped page.
class _CroppedPageView extends StatelessWidget {
  final _PageEditState page;
  final List<double>? colorMatrix;
  final BoxFit fit;
  final int? cacheWidth;

  const _CroppedPageView({
    required this.page,
    required this.colorMatrix,
    this.fit = BoxFit.contain,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final previewPath = page.croppedPreviewPath;
    if (previewPath != null && File(previewPath).existsSync()) {
      Widget img = Image.file(
        File(previewPath),
        fit: fit,
        cacheWidth: cacheWidth,
      );
      if (page.quarterTurns != 0) {
        img = RotatedBox(quarterTurns: page.quarterTurns, child: img);
      }
      if (colorMatrix != null) {
        img = ColorFiltered(
          colorFilter: ColorFilter.matrix(colorMatrix!),
          child: img,
        );
      }
      return img;
    }

    Widget rawImg = Image.file(
      File(page.path),
      fit: BoxFit.fill,
      cacheWidth: cacheWidth,
    );
    if (page.quarterTurns != 0) {
      rawImg = RotatedBox(quarterTurns: page.quarterTurns, child: rawImg);
    }
    if (colorMatrix != null) {
      rawImg = ColorFiltered(
        colorFilter: ColorFilter.matrix(colorMatrix!),
        child: rawImg,
      );
    }

    final cropRect = page.boundingCropRect;
    final cw = cropRect.width.clamp(0.05, 1.0);
    final ch = cropRect.height.clamp(0.05, 1.0);
    final aspectRatio = page.rotatedAspectRatio;
    final croppedAspect = (aspectRatio * cw) / ch;

    const fullW = 1000.0;
    final fullH = fullW / aspectRatio;
    final cropW = fullW * cw;
    final cropH = fullH * ch;

    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: cropW,
        height: cropH > 0 ? cropH : (cropW / croppedAspect),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: fullW,
            maxWidth: fullW,
            minHeight: fullH,
            maxHeight: fullH,
            child: Transform.translate(
              offset: Offset(-cropRect.left * fullW, -cropRect.top * fullH),
              child: SizedBox(
                width: fullW,
                height: fullH,
                child: rawImg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive 4-independent-corner crop stage.
/// Each of the 4 corners (`[0]=topLeft`, `[1]=topRight`, `[2]=bottomRight`, `[3]=bottomLeft`)
/// moves completely independently in 2D (`dx, dy`) without moving any other corner.
class _InteractiveQuadCropStage extends StatelessWidget {
  final File file;
  final int quarterTurns;
  final double aspectRatio;
  final List<double>? colorMatrix;
  final List<Offset> corners;
  final ValueChanged<List<Offset>> onCornersChanged;

  const _InteractiveQuadCropStage({
    required this.file,
    required this.quarterTurns,
    required this.aspectRatio,
    required this.colorMatrix,
    required this.corners,
    required this.onCornersChanged,
  });

  void _dragSingleCorner(int index, Offset delta, Size imgSize) {
    final dx = delta.dx / imgSize.width;
    final dy = delta.dy / imgSize.height;
    final next = List<Offset>.from(corners);
    final cur = next[index];
    final nx = (cur.dx + dx).clamp(0.0, 1.0);
    final ny = (cur.dy + dy).clamp(0.0, 1.0);

    // Prevent crossing over opposite corners so the quad stays valid
    const minGap = 0.06;
    switch (index) {
      case 0: // Top-Left
        next[0] = Offset(
          nx.clamp(0.0, math.min(next[1].dx, next[2].dx) - minGap),
          ny.clamp(0.0, math.min(next[3].dy, next[2].dy) - minGap),
        );
        break;
      case 1: // Top-Right
        next[1] = Offset(
          nx.clamp(math.max(next[0].dx, next[3].dx) + minGap, 1.0),
          ny.clamp(0.0, math.min(next[2].dy, next[3].dy) - minGap),
        );
        break;
      case 2: // Bottom-Right
        next[2] = Offset(
          nx.clamp(math.max(next[3].dx, next[0].dx) + minGap, 1.0),
          ny.clamp(math.max(next[1].dy, next[0].dy) + minGap, 1.0),
        );
        break;
      case 3: // Bottom-Left
        next[3] = Offset(
          nx.clamp(0.0, math.min(next[2].dx, next[1].dx) - minGap),
          ny.clamp(math.max(next[0].dy, next[1].dy) + minGap, 1.0),
        );
        break;
    }
    onCornersChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    Widget img = Image.file(file, fit: BoxFit.fill);
    if (quarterTurns != 0) {
      img = RotatedBox(quarterTurns: quarterTurns, child: img);
    }
    if (colorMatrix != null) {
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(colorMatrix!),
        child: img,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        var imgW = maxW;
        var imgH = imgW / aspectRatio;
        if (imgH > maxH) {
          imgH = maxH;
          imgW = imgH * aspectRatio;
        }
        final imgSize = Size(imgW, imgH);

        final pixelCorners = corners
            .map((c) => Offset(c.dx * imgW, c.dy * imgH))
            .toList(growable: false);

        const handleSize = 48.0;
        const halfHandle = handleSize / 2;
        final maxHX = math.max<double>(0.0, imgW - handleSize);
        final maxHY = math.max<double>(0.0, imgH - handleSize);

        return Center(
          child: SizedBox(
            width: imgW,
            height: imgH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                img,
                IgnorePointer(
                  child: CustomPaint(
                    painter: _QuadCropPainter(corners: pixelCorners),
                  ),
                ),
                // 4 Independent Corner Drag Targets
                for (var i = 0; i < 4; i++)
                  Positioned(
                    left: (pixelCorners[i].dx - halfHandle)
                        .clamp(0.0, maxHX)
                        .toDouble(),
                    top: (pixelCorners[i].dy - halfHandle)
                        .clamp(0.0, maxHY)
                        .toDouble(),
                    width: handleSize,
                    height: handleSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) =>
                          _dragSingleCorner(i, d.delta, imgSize),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuadCropPainter extends CustomPainter {
  final List<Offset> corners;
  const _QuadCropPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final tl = corners[0];
    final tr = corners[1];
    final br = corners[2];
    final bl = corners[3];

    final fullPath = Path()..addRect(Offset.zero & size);
    final quadPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    final maskPath =
        Path.combine(PathOperation.difference, fullPath, quadPath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withAlpha(135),
    );

    // Bilinear 3x3 perspective grid inside the 4-corner quad
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(75)
      ..strokeWidth = 0.9;
    for (var i = 1; i <= 2; i++) {
      final t = i / 3.0;
      final topPt = Offset.lerp(tl, tr, t)!;
      final botPt = Offset.lerp(bl, br, t)!;
      canvas.drawLine(topPt, botPt, gridPaint);

      final leftPt = Offset.lerp(tl, bl, t)!;
      final rightPt = Offset.lerp(tr, br, t)!;
      canvas.drawLine(leftPt, rightPt, gridPaint);
    }

    // Polygon border lines
    canvas.drawPath(
      quadPath,
      Paint()
        ..color = AppTheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Draw independent circular corner handles
    final fillPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final pt in corners) {
      final clamped = Offset(
        pt.dx.clamp(6.0, size.width - 6.0),
        pt.dy.clamp(6.0, size.height - 6.0),
      );
      canvas.drawCircle(clamped, 8.5, fillPaint);
      canvas.drawCircle(clamped, 8.5, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadCropPainter oldDelegate) {
    if (oldDelegate.corners.length != corners.length) return true;
    for (var i = 0; i < corners.length; i++) {
      if (oldDelegate.corners[i] != corners[i]) return true;
    }
    return false;
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
