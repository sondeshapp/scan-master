import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';
import 'edit_page_screen.dart';

class ScannerScreen extends StatefulWidget {
  final String? initialFolderId;

  const ScannerScreen({super.key, this.initialFolderId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _ctrl;
  bool _ready = false;
  bool _cameraError = false;
  bool _flashOn = false;
  bool _autoMode = false;
  int _autoCountdown = 0;
  Timer? _autoTimer;
  bool _saved = false;
  int _selectedThumbIndex = 0;
  final List<String> _capturedPaths = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  @override
  void dispose() {
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
    await _ctrl?.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
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

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final scanDir = Directory('${dir.path}/scans');
    await scanDir.create(recursive: true);
    for (final img in images) {
      final dest =
          '${scanDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(img.path).copy(dest);
      if (mounted) {
        setState(() {
          _capturedPaths.add(dest);
          _selectedThumbIndex = _capturedPaths.length - 1;
        });
      }
    }
  }

  Future<void> _capture() async {
    HapticFeedback.mediumImpact();
    if (_ready && _ctrl != null) {
      try {
        final xfile = await _ctrl!.takePicture();
        // Copy to persistent app directory so it survives controller disposal
        final dir = await getApplicationDocumentsDirectory();
        final scanDir = Directory('${dir.path}/scans');
        await scanDir.create(recursive: true);
        final dest =
            '${scanDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(xfile.path).copy(dest);
        try {
          await File(xfile.path).delete();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _capturedPaths.add(dest);
            _selectedThumbIndex = _capturedPaths.length - 1;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Capture failed: $e')),
          );
        }
      }
    } else {
      // Simulate capture for emulators
      final dir = await getApplicationDocumentsDirectory();
      final scanDir = Directory('${dir.path}/scans');
      await scanDir.create(recursive: true);
      final path =
          '${scanDir.path}/placeholder_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _writePlaceholderImage(path, _capturedPaths.length + 1);
      if (mounted) {
        setState(() {
          _capturedPaths.add(path);
          _selectedThumbIndex = _capturedPaths.length - 1;
        });
      }
    }
  }

  void _removeCapturedPage(int index) {
    if (index < 0 || index >= _capturedPaths.length) return;
    final removed = _capturedPaths[index];
    setState(() {
      _capturedPaths.removeAt(index);
      if (_selectedThumbIndex >= _capturedPaths.length) {
        _selectedThumbIndex =
            _capturedPaths.isEmpty ? 0 : _capturedPaths.length - 1;
      }
    });
    try {
      final f = File(removed);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // Creates a minimal white JPEG as placeholder when camera is unavailable
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
      // Remove any pages deleted inside EditPageScreen
      setState(() {
        _capturedPaths.removeWhere((p) => !File(p).existsSync());
        if (_selectedThumbIndex >= _capturedPaths.length) {
          _selectedThumbIndex =
              _capturedPaths.isEmpty ? 0 : _capturedPaths.length - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCamera(),
          _buildTopBar(),
          _buildOverlay(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (_ready && _ctrl != null) return CameraPreview(_ctrl!);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9A88E), Color(0xFFE8B89C)],
        ),
      ),
      child: _cameraError
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 56, color: Colors.white54),
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
              child: CircularProgressIndicator(color: Colors.white70)),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _circleBtn(
            Icons.close_rounded,
            () => Navigator.pop(context),
            label: 'Close scanner',
          ),
          Row(
            children: [
              _circleBtn(
                Icons.photo_library_outlined,
                _pickFromGallery,
                label: 'Import from gallery',
              ),
              const SizedBox(width: 10),
              _circleBtn(
                _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                _toggleFlash,
                label: _flashOn ? 'Turn flash off' : 'Turn flash on',
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: _autoMode ? 'Auto capture on' : 'Manual capture mode',
                child: GestureDetector(
                  onTap: _toggleAutoMode,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _autoMode
                          ? AppTheme.primary
                          : Colors.black.withAlpha(115),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _autoMode ? 'AUTO' : 'MANUAL',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {required String label}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(107),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final statusText = _autoMode && _autoCountdown > 0
        ? 'AUTO SCAN IN $_autoCountdown...'
        : (_capturedPaths.isEmpty ? 'READY TO SCAN' : 'TAP TO SCAN MORE');
    return Center(
      child: SizedBox(
        width: 270,
        height: 360,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.white.withAlpha(128), width: 1),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            ..._corners(),
            Align(
              alignment: const Alignment(0, 0.35),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners() => const [
        _Corner(top: 0, left: 0),
        _Corner(top: 0, right: 0, flipX: true),
        _Corner(bottom: 0, left: 0, flipY: true),
        _Corner(bottom: 0, right: 0, flipX: true, flipY: true),
      ];

  Widget _buildBottomBar() {
    final count = _capturedPaths.length;
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrollable thumbnail strip showing all captured pages + Add tile
          SizedBox(
            height: 82,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < count; i++) ...[
                      _Thumb(
                        path: _capturedPaths[i],
                        number: i + 1,
                        selected: i == _selectedThumbIndex,
                        onTap: () => setState(() => _selectedThumbIndex = i),
                        onRemove: () => _removeCapturedPage(i),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _AddBtn(onTap: _pickFromGallery),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Edit
              SizedBox(
                width: 72,
                child: TextButton(
                  onPressed: count > 0 ? _goToEdit : null,
                  child: Text(
                    'EDIT',
                    style: TextStyle(
                      color: count > 0 ? Colors.white : Colors.white30,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              // Shutter
              Semantics(
                button: true,
                label: 'Take photo',
                child: GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              // Save
              SizedBox(
                width: 84,
                child: Semantics(
                  button: true,
                  label: count > 0 ? 'Save $count pages' : 'Save',
                  child: GestureDetector(
                    onTap: count > 0 ? _goToEdit : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            count > 0 ? AppTheme.primary : Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          count > 0 ? 'SAVE ($count)' : 'SAVE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────

class _Corner extends StatelessWidget {
  final double? top, bottom, left, right;
  final bool flipX, flipY;
  const _Corner({
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.flipX = false,
    this.flipY = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: CustomPaint(
        size: const Size(22, 22),
        painter: _CornerPainter(flipX: flipX, flipY: flipY),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool flipX, flipY;
  const _CornerPainter({required this.flipX, required this.flipY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = flipX ? size.width : 0.0;
    final y = flipY ? size.height : 0.0;
    canvas.drawLine(
        Offset(x, y), Offset(x + (flipX ? -size.width : size.width), y), paint);
    canvas.drawLine(Offset(x, y),
        Offset(x, y + (flipY ? -size.height : size.height)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Thumb extends StatelessWidget {
  final String path;
  final int number;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _Thumb({
    required this.path,
    required this.number,
    this.selected = false,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 58,
            height: 74,
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
                  ? Image.file(file, fit: BoxFit.cover, cacheWidth: 160)
                  : Container(
                      color: const Color(0xFFF5E4CC),
                      child: const Icon(Icons.description_outlined,
                          color: Colors.grey, size: 22),
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Semantics(
              button: true,
              label: 'Remove page $number',
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 12),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add page from gallery',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 58,
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(Icons.add, color: Colors.white54, size: 24),
        ),
      ),
    );
  }
}
