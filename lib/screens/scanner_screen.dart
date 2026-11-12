import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/image_processor.dart';
import 'edit_page_screen.dart';

class ScannerScreen extends StatefulWidget {
  final String? initialFolderId;

  const ScannerScreen({super.key, this.initialFolderId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const _accentBlue = Color(0xFF3888FF);
  static const _tiltChannel = EventChannel('scan_master/device_tilt');
  static const _categories = [
    'Whiteboard',
    'Book',
    'Document',
    'ID card',
    'Business card',
  ];

  CameraController? _ctrl;
  StreamSubscription<dynamic>? _tiltSub;
  bool _ready = false;
  bool _cameraError = false;
  bool _flashOn = false;
  bool _autoMode = false;
  bool _isHorizontal = false;
  bool _processingCapture = false;
  int _selectedCategory = 2; // 'Document' (free aspect ratio)
  int _autoCountdown = 0;
  Timer? _autoTimer;
  bool _saved = false;
  final List<String> _capturedPaths = [];

  // Scale factor (0.25 .. 1.0) for fixed-aspect-ratio modes; 1.0 = full sensor fit
  final List<double> _categoryScales = [1.0, 1.0, 1.0, 1.0, 1.0];

  // Free-aspect-ratio normalized bounds (0.0 .. 1.0) for Document mode
  Rect _docNormalizedRect = const Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);

  // Latest normalized crop rect in viewport coordinates (0.0 .. 1.0)
  Rect _activeNormalizedCrop = const Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _listenToDeviceTilt();
    _initCamera();
  }

  void _listenToDeviceTilt() {
    try {
      _tiltSub = _tiltChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is bool && mounted && _isHorizontal != event) {
            setState(() {
              _isHorizontal = event;
              _applyDocumentOrientationBounds();
            });
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _applyDocumentOrientationBounds() {
    // Utilize full sensor width/height by default when switching orientation
    if (_isHorizontal) {
      _docNormalizedRect = const Rect.fromLTRB(0.0, 0.18, 1.0, 0.82);
    } else {
      _docNormalizedRect = const Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);
    }
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _cameraError = true);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = true);
        return;
      }
      _ctrl = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _ctrl!.initialize();
      try {
        await _ctrl!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    _autoTimer?.cancel();
    _ctrl?.dispose();
    if (!_saved) {
      for (final p in _capturedPaths) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    setState(() => _flashOn = !_flashOn);
    try {
      await _ctrl?.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
  }

  void _toggleAutoMode() {
    setState(() {
      _autoMode = !_autoMode;
      if (_autoMode) {
        _startAutoCountdown();
      } else {
        _autoTimer?.cancel();
        _autoCountdown = 0;
      }
    });
  }

  void _startAutoCountdown() {
    _autoTimer?.cancel();
    _autoCountdown = 3;
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted || !_autoMode) {
        timer.cancel();
        return;
      }
      if (_autoCountdown > 1) {
        setState(() => _autoCountdown--);
      } else {
        timer.cancel();
        setState(() => _autoCountdown = 0);
        await _capture();
        if (mounted && _autoMode) {
          _startAutoCountdown();
        }
      }
    });
  }

  Future<List<String>> _saveProcessedBytes(
    Uint8List rawBytes,
    Directory scanDir,
  ) async {
    final crop = _activeNormalizedCrop;
    final pages = await compute(processCapturedByCategory, {
      'bytes': rawBytes,
      'categoryIndex': _selectedCategory,
      'isHorizontal': _isHorizontal,
      'cropLeft': crop.left,
      'cropTop': crop.top,
      'cropWidth': crop.width,
      'cropHeight': crop.height,
    });
    final savedPaths = <String>[];
    final baseTs = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < pages.length; i++) {
      final dest = '${scanDir.path}/${baseTs}_p${i + 1}.jpg';
      await File(dest).writeAsBytes(pages[i]);
      savedPaths.add(dest);
    }
    return savedPaths;
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    setState(() => _processingCapture = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);
      for (final imgFile in images) {
        final rawBytes = await File(imgFile.path).readAsBytes();
        final newPaths = await _saveProcessedBytes(rawBytes, scanDir);
        if (mounted) {
          setState(() {
            _capturedPaths.addAll(newPaths);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _processingCapture = false);
    }
  }

  Future<void> _capture() async {
    if (_processingCapture) return;
    HapticFeedback.mediumImpact();
    setState(() => _processingCapture = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);

      if (_ready && _ctrl != null) {
        final xfile = await _ctrl!.takePicture();
        final rawBytes = await File(xfile.path).readAsBytes();
        try {
          await File(xfile.path).delete();
        } catch (_) {}
        final newPaths = await _saveProcessedBytes(rawBytes, scanDir);
        if (mounted) {
          setState(() {
            _capturedPaths.addAll(newPaths);
          });
        }
      } else {
        // Simulator / unavailable camera fallback
        final countToAdd = _selectedCategory == 1 ? 2 : 1;
        final baseTs = DateTime.now().microsecondsSinceEpoch;
        for (var i = 0; i < countToAdd; i++) {
          final path = '${scanDir.path}/placeholder_${baseTs}_p${i + 1}.jpg';
          await _writePlaceholderImage(path, _capturedPaths.length + 1);
          if (mounted) {
            setState(() {
              _capturedPaths.add(path);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingCapture = false);
    }
  }

  void _removeLastCapturedPage() {
    if (_capturedPaths.isEmpty) return;
    final removed = _capturedPaths.removeLast();
    setState(() {});
    try {
      final f = File(removed);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _writePlaceholderImage(String path, int pageNum) async {
    final bytes = <int>[
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
      0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
      0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
      0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
      0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
      0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
      0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
      0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
      0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
      0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
      0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
      0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
      0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
      0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
      0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
      0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
      0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD6, 0xFF, 0xD9,
    ];
    await File(path).writeAsBytes(bytes);
  }

  Future<void> _goToEdit() async {
    if (_capturedPaths.isEmpty) return;
    _autoTimer?.cancel();
    setState(() {
      _autoMode = false;
      _autoCountdown = 0;
    });
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPageScreen(
          imagePaths: _capturedPaths,
          initialFolderId: widget.initialFolderId,
        ),
      ),
    );
    if (saved == true && mounted) {
      _saved = true;
      Navigator.pop(context, true);
    } else if (mounted) {
      setState(() {
        _capturedPaths.removeWhere((p) => !File(p).existsSync());
      });
    }
  }

  void _onCornerDrag({
    required _CornerPos corner,
    required Offset delta,
    required Size viewportSize,
    required Size maxAspectFitSize,
  }) {
    setState(() {
      if (_selectedCategory == 2) {
        // Free aspect ratio (Document mode): move each corner independently up to full screen (0.0 .. 1.0)
        const minSpan = 0.15;
        final dx = delta.dx / viewportSize.width;
        final dy = delta.dy / viewportSize.height;
        var l = _docNormalizedRect.left;
        var t = _docNormalizedRect.top;
        var r = _docNormalizedRect.right;
        var b = _docNormalizedRect.bottom;

        switch (corner) {
          case _CornerPos.topLeft:
            l = (l + dx).clamp(0.0, r - minSpan);
            t = (t + dy).clamp(0.0, b - minSpan);
            break;
          case _CornerPos.topRight:
            r = (r + dx).clamp(l + minSpan, 1.0);
            t = (t + dy).clamp(0.0, b - minSpan);
            break;
          case _CornerPos.bottomLeft:
            l = (l + dx).clamp(0.0, r - minSpan);
            b = (b + dy).clamp(t + minSpan, 1.0);
            break;
          case _CornerPos.bottomRight:
            r = (r + dx).clamp(l + minSpan, 1.0);
            b = (b + dy).clamp(t + minSpan, 1.0);
            break;
        }
        _docNormalizedRect = Rect.fromLTRB(l, t, r, b);
      } else {
        // Fixed aspect ratio modes: dragging any corner scales the frame up to 100% of sensor fit
        final signX = (corner == _CornerPos.topRight ||
                corner == _CornerPos.bottomRight)
            ? 1.0
            : -1.0;
        final signY = (corner == _CornerPos.bottomLeft ||
                corner == _CornerPos.bottomRight)
            ? 1.0
            : -1.0;
        final dScaleX = (delta.dx * signX * 2.0) / maxAspectFitSize.width;
        final dScaleY = (delta.dy * signY * 2.0) / maxAspectFitSize.height;
        final dScale = (dScaleX + dScaleY) / 2.0;
        _categoryScales[_selectedCategory] =
            (_categoryScales[_selectedCategory] + dScale).clamp(0.25, 1.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(child: _buildCameraPreview()),
                // Interactive crop area with draggable corners for all modes
                _CategoryFrameOverlay(
                  categoryIndex: _selectedCategory,
                  isHorizontal: _isHorizontal,
                  scale: _categoryScales[_selectedCategory],
                  docNormalizedRect: _docNormalizedRect,
                  onCornerDrag: _onCornerDrag,
                  onActiveCropChanged: (normRect) {
                    _activeNormalizedCrop = normRect;
                  },
                  onToggleOrientation: () => setState(() {
                    _isHorizontal = !_isHorizontal;
                    _applyDocumentOrientationBounds();
                  }),
                ),
                if (_autoMode && _autoCountdown > 0)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Auto scan in $_autoCountdown...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 14,
        left: 24,
        right: 24,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Home button
          Semantics(
            button: true,
            label: 'Back to Home',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.home_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          // 2. Auto-scanning toggle button
          Semantics(
            button: true,
            label: _autoMode ? 'Auto scan on' : 'Auto scan off',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleAutoMode,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _SmartCropDocIcon(active: _autoMode),
              ),
            ),
          ),
          // 3. Flash toggle button
          Semantics(
            button: true,
            label: _flashOn ? 'Turn flash off' : 'Turn flash on',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleFlash,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _flashOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  color: _flashOn ? _accentBlue : Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_ready && _ctrl != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = _ctrl!.value.previewSize;
          final portraitRatio = previewSize != null
              ? (previewSize.height / previewSize.width)
              : (1 / _ctrl!.value.aspectRatio);
          final screenRatio = constraints.maxWidth / constraints.maxHeight;
          final scale = screenRatio > portraitRatio
              ? screenRatio / portraitRatio
              : portraitRatio / screenRatio;
          return Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: portraitRatio,
                child: _ctrl!.buildPreview(),
              ),
            ),
          );
        },
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
        ),
      ),
      child: _cameraError
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 52, color: Colors.white54),
                  SizedBox(height: 12),
                  Text(
                    'Camera unavailable\nTap shutter to simulate a scan',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            )
          : const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
    );
  }

  Widget _buildBottomPanel() {
    final count = _capturedPaths.length;
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category tabs: Whiteboard | Book | Document | ID card | Business card
          SizedBox(
            height: 32,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_categories.length, (i) {
                  final selected = i == _selectedCategory;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedCategory = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      child: Text(
                        _categories[i],
                        style: TextStyle(
                          color: selected ? _accentBlue : Colors.white,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Bottom camera controls row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Gallery import button
                Semantics(
                  button: true,
                  label: 'Import from gallery',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickFromGallery,
                    child: const SizedBox(
                      width: 58,
                      height: 58,
                      child: Center(
                        child: Icon(
                          Icons.photo_outlined,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Center Pro Shutter Button
                Semantics(
                  button: true,
                  label: 'Take photo',
                  child: _ShutterButton(
                    processing: _processingCapture,
                    onTap: _capture,
                  ),
                ),
                // 3. Captured thumbnail stack with blue count badge
                SizedBox(
                  width: 58,
                  height: 70,
                  child: count > 0
                      ? _CapturedThumbBadge(
                          path: _capturedPaths.last,
                          count: count,
                          onTap: _goToEdit,
                          onLongPress: _removeLastCapturedPage,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────

enum _CornerPos { topLeft, topRight, bottomLeft, bottomRight }

typedef _CornerDragCallback = void Function({
  required _CornerPos corner,
  required Offset delta,
  required Size viewportSize,
  required Size maxAspectFitSize,
});

/// Renders the interactive crop frame with draggable corners.
/// - Document (index 2): free aspect ratio (each corner moves independently).
/// - Whiteboard (0), Book (1), ID card (3), Business card (4): fixed aspect ratio
///   that scales bigger/smaller when any corner is dragged.
class _CategoryFrameOverlay extends StatelessWidget {
  final int categoryIndex;
  final bool isHorizontal;
  final double scale;
  final Rect docNormalizedRect;
  final _CornerDragCallback onCornerDrag;
  final ValueChanged<Rect> onActiveCropChanged;
  final VoidCallback onToggleOrientation;

  const _CategoryFrameOverlay({
    required this.categoryIndex,
    required this.isHorizontal,
    required this.scale,
    required this.docNormalizedRect,
    required this.onCornerDrag,
    required this.onActiveCropChanged,
    required this.onToggleOrientation,
  });

  double get _baseHorizontalAspect {
    switch (categoryIndex) {
      case 0: // Whiteboard (16:10)
        return 1.6;
      case 1: // Book (2 pages)
        return 1.38;
      case 3: // ID card (85.6mm x 54mm)
        return 1.586;
      case 4: // Business card (3.5" x 2.0")
        return 1.75;
      default:
        return 1.414;
    }
  }

  double get _targetAspect =>
      isHorizontal ? _baseHorizontalAspect : (1.0 / _baseHorizontalAspect);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final viewportSize = Size(maxW, maxH);
        final borderRadius = categoryIndex == 3 ? 14.0 : 8.0;

        // Compute 100% full-sensor fit size for fixed-aspect-ratio modes
        var maxFitW = maxW;
        var maxFitH = maxFitW / _targetAspect;
        if (maxFitH > maxH) {
          maxFitH = maxH;
          maxFitW = maxFitH * _targetAspect;
        }
        final maxAspectFitSize = Size(maxFitW, maxFitH);

        final Rect rect;
        if (categoryIndex == 2) {
          // Free aspect ratio for Document mode
          rect = Rect.fromLTRB(
            docNormalizedRect.left * maxW,
            docNormalizedRect.top * maxH,
            docNormalizedRect.right * maxW,
            docNormalizedRect.bottom * maxH,
          );
        } else {
          final frameW = maxFitW * scale;
          final frameH = maxFitH * scale;
          rect = Rect.fromCenter(
            center: Offset(maxW / 2, maxH / 2),
            width: frameW,
            height: frameH,
          );
        }

        // Report normalized crop rect for capture processing
        onActiveCropChanged(
          Rect.fromLTRB(
            (rect.left / maxW).clamp(0.0, 1.0),
            (rect.top / maxH).clamp(0.0, 1.0),
            (rect.right / maxW).clamp(0.0, 1.0),
            (rect.bottom / maxH).clamp(0.0, 1.0),
          ),
        );

        const handleSize = 48.0;
        const halfHandle = handleSize / 2;

        // Keep full handle hitboxes inside the viewport even at 100% full-screen edges
        final maxHandleX = math.max<double>(0.0, maxW - handleSize);
        final maxHandleY = math.max<double>(0.0, maxH - handleSize);
        final double leftHandleX =
            (rect.left - halfHandle).clamp(0.0, maxHandleX).toDouble();
        final double rightHandleX =
            (rect.right - halfHandle).clamp(0.0, maxHandleX).toDouble();
        final double topHandleY =
            (rect.top - halfHandle).clamp(0.0, maxHandleY).toDouble();
        final double bottomHandleY =
            (rect.bottom - halfHandle).clamp(0.0, maxHandleY).toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _FrameMaskPainter(
                  frameRect: rect,
                  borderRadius: borderRadius,
                  isBookSpread: categoryIndex == 1,
                  isHorizontal: isHorizontal,
                ),
              ),
            ),
            // Book 2-page badges
            if (categoryIndex == 1) ...[
              Positioned(
                left: rect.left + 12,
                top: rect.top + 12,
                child: const IgnorePointer(
                  child: _BookPageTag(label: '1'),
                ),
              ),
              Positioned(
                left: isHorizontal ? null : rect.left + 12,
                right: isHorizontal ? (maxW - rect.right) + 12 : null,
                top: isHorizontal ? rect.top + 12 : rect.center.dy + 12,
                child: const IgnorePointer(
                  child: _BookPageTag(label: '2'),
                ),
              ),
            ],
            // 4 Draggable Corner Handles
            Positioned(
              left: leftHandleX,
              top: topHandleY,
              width: handleSize,
              height: handleSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onCornerDrag(
                  corner: _CornerPos.topLeft,
                  delta: d.delta,
                  viewportSize: viewportSize,
                  maxAspectFitSize: maxAspectFitSize,
                ),
              ),
            ),
            Positioned(
              left: rightHandleX,
              top: topHandleY,
              width: handleSize,
              height: handleSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onCornerDrag(
                  corner: _CornerPos.topRight,
                  delta: d.delta,
                  viewportSize: viewportSize,
                  maxAspectFitSize: maxAspectFitSize,
                ),
              ),
            ),
            Positioned(
              left: leftHandleX,
              top: bottomHandleY,
              width: handleSize,
              height: handleSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onCornerDrag(
                  corner: _CornerPos.bottomLeft,
                  delta: d.delta,
                  viewportSize: viewportSize,
                  maxAspectFitSize: maxAspectFitSize,
                ),
              ),
            ),
            Positioned(
              left: rightHandleX,
              top: bottomHandleY,
              width: handleSize,
              height: handleSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onCornerDrag(
                  corner: _CornerPos.bottomRight,
                  delta: d.delta,
                  viewportSize: viewportSize,
                  maxAspectFitSize: maxAspectFitSize,
                ),
              ),
            ),
            // Subtle icon-only orientation button (centered at top so it never blocks corners)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Semantics(
                  button: true,
                  label: 'Toggle frame orientation',
                  child: GestureDetector(
                    onTap: onToggleOrientation,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isHorizontal
                            ? Icons.stay_current_landscape_rounded
                            : Icons.stay_current_portrait_rounded,
                        color: const Color(0xFF3888FF),
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BookPageTag extends StatelessWidget {
  final String label;
  const _BookPageTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF3888FF).withAlpha(210),
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FrameMaskPainter extends CustomPainter {
  final Rect frameRect;
  final double borderRadius;
  final bool isBookSpread;
  final bool isHorizontal;

  const _FrameMaskPainter({
    required this.frameRect,
    required this.borderRadius,
    required this.isBookSpread,
    required this.isHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()..addRect(Offset.zero & size);
    // Keep stroke inside canvas bounds when expanded to 100% full screen
    final drawRect = Rect.fromLTRB(
      frameRect.left.clamp(2.0, size.width - 2.0),
      frameRect.top.clamp(2.0, size.height - 2.0),
      frameRect.right.clamp(2.0, size.width - 2.0),
      frameRect.bottom.clamp(2.0, size.height - 2.0),
    );
    final isFullEdges = frameRect.left <= 2.0 &&
        frameRect.top <= 2.0 &&
        frameRect.right >= size.width - 2.0 &&
        frameRect.bottom >= size.height - 2.0;
    final effectiveRadius = isFullEdges ? 0.0 : borderRadius;

    final rrect =
        RRect.fromRectAndRadius(frameRect, Radius.circular(effectiveRadius));
    final holePath = Path()..addRRect(rrect);
    final maskPath =
        Path.combine(PathOperation.difference, fullPath, holePath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withAlpha(115),
    );

    // Subtle frame outline
    final borderPaint = Paint()
      ..color = Colors.white.withAlpha(170)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(drawRect, Radius.circular(effectiveRadius)),
      borderPaint,
    );

    // Highlighted blue corner handles
    final cornerPaint = Paint()
      ..color = const Color(0xFF3888FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cLen = 22.0;
    final l = drawRect.left;
    final t = drawRect.top;
    final r = drawRect.right;
    final b = drawRect.bottom;

    // Top-left
    canvas.drawLine(Offset(l, t + cLen), Offset(l, t), cornerPaint);
    canvas.drawLine(Offset(l, t), Offset(l + cLen, t), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(r - cLen, t), Offset(r, t), cornerPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - cLen), Offset(l, b), cornerPaint);
    canvas.drawLine(Offset(l, b), Offset(l + cLen, b), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(r - cLen, b), Offset(r, b), cornerPaint);
    canvas.drawLine(Offset(r, b - cLen), Offset(r, b), cornerPaint);

    // Dashed center spine for Book mode
    if (isBookSpread) {
      final dashPaint = Paint()
        ..color = const Color(0xFF3888FF)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      const dashLen = 8.0;
      const gapLen = 6.0;
      if (isHorizontal) {
        final spineX = frameRect.center.dx;
        var y = frameRect.top + 8;
        while (y < frameRect.bottom - 8) {
          final endY = math.min(y + dashLen, frameRect.bottom - 8);
          canvas.drawLine(Offset(spineX, y), Offset(spineX, endY), dashPaint);
          y += dashLen + gapLen;
        }
      } else {
        final spineY = frameRect.center.dy;
        var x = frameRect.left + 8;
        while (x < frameRect.right - 8) {
          final endX = math.min(x + dashLen, frameRect.right - 8);
          canvas.drawLine(Offset(x, spineY), Offset(endX, spineY), dashPaint);
          x += dashLen + gapLen;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FrameMaskPainter oldDelegate) =>
      oldDelegate.frameRect != frameRect ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isBookSpread != isBookSpread ||
      oldDelegate.isHorizontal != isHorizontal;
}

class _SmartCropDocIcon extends StatelessWidget {
  final bool active;
  const _SmartCropDocIcon({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF3888FF) : Colors.white;
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _SmartCropPainter(color: color),
        child: Center(
          child: Icon(
            Icons.auto_awesome_rounded,
            color: color,
            size: 15,
          ),
        ),
      ),
    );
  }
}

class _SmartCropPainter extends CustomPainter {
  final Color color;
  const _SmartCropPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 6.0;
    final w = size.width;
    final h = size.height;

    // Top-left bracket
    canvas.drawLine(const Offset(0, len), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    // Top-right bracket
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // Bottom-left bracket
    canvas.drawLine(Offset(0, h - len), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    // Bottom-right bracket
    canvas.drawLine(Offset(w - len, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h - len), Offset(w, h), paint);

    // Inner document outline
    final docRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 4, w - 10, h - 8),
      const Radius.circular(2),
    );
    canvas.drawRRect(docRect, paint..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _SmartCropPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ShutterButton extends StatefulWidget {
  final bool processing;
  final VoidCallback onTap;

  const _ShutterButton({
    required this.processing,
    required this.onTap,
  });

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 78,
          height: 78,
          child: CustomPaint(
            painter: _ShutterRingPainter(pressed: _pressed),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _pressed ? 52 : 58,
                height: _pressed ? 52 : 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed ? const Color(0xFF3888FF) : Colors.white,
                ),
                child: widget.processing
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _pressed
                                ? Colors.white
                                : const Color(0xFF3888FF),
                          ),
                        ),
                      )
                    : Center(
                        child: Container(
                          width: _pressed ? 42 : 48,
                          height: _pressed ? 42 : 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _pressed
                                  ? Colors.white.withAlpha(90)
                                  : Colors.black.withAlpha(28),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterRingPainter extends CustomPainter {
  final bool pressed;
  const _ShutterRingPainter({this.pressed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2.5;

    // Solid dark gap backdrop
    final fillPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Solid white outer ring
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _ShutterRingPainter oldDelegate) =>
      oldDelegate.pressed != pressed;
}

class _CapturedThumbBadge extends StatelessWidget {
  final String path;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CapturedThumbBadge({
    required this.path,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Semantics(
      button: true,
      label: 'Edit $count scanned pages',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 50,
                height: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      file.existsSync()
                          ? Image.file(
                              file,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                            )
                          : const Icon(
                              Icons.description_outlined,
                              color: Colors.white54,
                              size: 24,
                            ),
                      // Subtle blue document selection frame inside thumbnail
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF3888FF),
                              width: 1.8,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
