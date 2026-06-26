import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../app_theme.dart';
import 'edit_page_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _ctrl;
  bool _ready = false;
  bool _cameraError = false;
  bool _flashOn = false;
  final List<String> _capturedPaths = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _cameraError = true);
      return;
    }
    try {
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
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    setState(() => _flashOn = !_flashOn);
    await _ctrl?.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> _capture() async {
    if (_ready && _ctrl != null) {
      try {
        final xfile = await _ctrl!.takePicture();
        // Copy to persistent app directory so it survives controller disposal
        final dir = await getApplicationDocumentsDirectory();
        final scanDir = Directory('${dir.path}/scans');
        await scanDir.create(recursive: true);
        final dest = '${scanDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(xfile.path).copy(dest);
        if (mounted) setState(() => _capturedPaths.add(dest));
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
      final path = '${scanDir.path}/placeholder_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _writePlaceholderImage(path, _capturedPaths.length + 1);
      if (mounted) setState(() => _capturedPaths.add(path));
    }
  }

  // Creates a minimal white JPEG as placeholder when camera is unavailable
  Future<void> _writePlaceholderImage(String path, int pageNum) async {
    // Minimal 1x1 white JPEG bytes
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

  void _goToEdit() {
    if (_capturedPaths.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPageScreen(imagePaths: _capturedPaths),
      ),
    );
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
            bottom: 0, left: 0, right: 0,
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
                  Icon(Icons.camera_alt_outlined, size: 56, color: Colors.white54),
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
          _circleBtn(Icons.close_rounded, () => Navigator.pop(context)),
          Row(
            children: [
              _circleBtn(
                _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                _toggleFlash,
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(115),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AUTO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
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
    );
  }

  Widget _buildOverlay() {
    return Center(
      child: SizedBox(
        width: 270,
        height: 360,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withAlpha(128), width: 1),
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
                  _capturedPaths.isEmpty ? 'READY TO SCAN' : 'TAP TO SCAN MORE',
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

  List<Widget> _corners() => [
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
          // Thumbnails
          SizedBox(
            height: 82,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (count >= 1) ...[
                  _Thumb(path: _capturedPaths[0], number: 1, selected: true),
                  const SizedBox(width: 8),
                ],
                if (count >= 2) ...[
                  _Thumb(path: _capturedPaths[1], number: 2),
                  const SizedBox(width: 8),
                ],
                if (count >= 3) ...[
                  _Thumb(path: _capturedPaths[2], number: 3),
                  const SizedBox(width: 8),
                ],
                _AddBtn(),
              ],
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
              GestureDetector(
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
              // Save
              SizedBox(
                width: 72,
                child: GestureDetector(
                  onTap: count > 0 ? _goToEdit : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? AppTheme.primary
                          : Colors.grey.shade800,
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
  const _Corner({this.top, this.bottom, this.left, this.right,
      this.flipX = false, this.flipY = false});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
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
    canvas.drawLine(Offset(x, y), Offset(x + (flipX ? -size.width : size.width), y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + (flipY ? -size.height : size.height)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Thumb extends StatelessWidget {
  final String path;
  final int number;
  final bool selected;
  const _Thumb({required this.path, required this.number, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Stack(
      children: [
        Container(
          width: 58, height: 74,
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
                : Container(
                    color: const Color(0xFFF5E4CC),
                    child: const Icon(Icons.description_outlined,
                        color: Colors.grey, size: 22),
                  ),
          ),
        ),
        Positioned(
          bottom: 4, right: 4,
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58, height: 74,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: const Icon(Icons.add, color: Colors.white38, size: 24),
    );
  }
}
