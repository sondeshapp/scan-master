import 'dart:typed_data';
import 'package:image/image.dart' as img;

// Top-level function for Flutter compute() — runs in isolate
Future<Uint8List> processImageFilter(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final filterIndex = (args['filterIndex'] as int?) ?? 0;
  final quarterTurns = ((args['quarterTurns'] as int?) ?? 0) % 4;
  final cropMargin = (args['cropMargin'] as double?) ?? 0.0;
  final brightness = (args['brightness'] as double?) ?? 1.0;
  final contrast = (args['contrast'] as double?) ?? 1.0;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final noEdits = filterIndex == 0 &&
      quarterTurns == 0 &&
      cropMargin <= 0.0 &&
      brightness == 1.0 &&
      contrast == 1.0;
  if (noEdits) return bytes;

  img.Image current = decoded;

  // 1. Apply rotation (90° increments clockwise)
  if (quarterTurns != 0) {
    current = img.copyRotate(current, angle: quarterTurns * 90);
  }

  // 2. Apply proportional margin crop if requested
  if (cropMargin > 0.0 && cropMargin < 0.4) {
    final dx = (current.width * cropMargin).round();
    final dy = (current.height * cropMargin).round();
    final w = current.width - (dx * 2);
    final h = current.height - (dy * 2);
    if (w > 1 && h > 1) {
      current = img.copyCrop(current, x: dx, y: dy, width: w, height: h);
    }
  }

  // 3. Apply filter
  switch (filterIndex) {
    case 1: // B&W
      current = img.grayscale(current);
      break;
    case 2: // Magic (enhanced contrast + saturation)
      current = img.adjustColor(current, saturation: 1.4, contrast: 1.25);
      break;
    case 3: // Text (high contrast grayscale)
      final gray = img.grayscale(current);
      current = img.adjustColor(gray, contrast: 1.8, brightness: 1.1);
      break;
    case 4: // Sepia
      current = img.sepia(current);
      break;
    default:
      break;
  }

  // 4. Apply user brightness / contrast adjustments
  if (brightness != 1.0 || contrast != 1.0) {
    current = img.adjustColor(
      current,
      brightness: brightness,
      contrast: contrast,
    );
  }

  return Uint8List.fromList(img.encodeJpg(current, quality: 88));
}

// Color filter matrices for fast preview (no image processing needed)
const List<List<double>?> filterMatrices = [
  null, // Original
  [ // B&W grayscale
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ],
  [ // Magic (punchy contrast)
    1.2, 0,   0,   0, 10,
    0,   1.2, 0,   0, 10,
    0,   0,   1.3, 0, 0,
    0,   0,   0,   1, 0,
  ],
  [ // Text (high contrast mono)
    0.33, 0.33, 0.33, 0, 30,
    0.33, 0.33, 0.33, 0, 30,
    0.33, 0.33, 0.33, 0, 30,
    0,    0,    0,    1, 0,
  ],
  [ // Sepia
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0,     0,     0,     1, 0,
  ],
];

/// Combines the base filter matrix with user brightness/contrast for live GPU preview.
List<double>? buildPreviewMatrix({
  required int filterIndex,
  double brightness = 1.0,
  double contrast = 1.0,
}) {
  final base = filterMatrices[filterIndex];
  if (base == null && brightness == 1.0 && contrast == 1.0) {
    return null;
  }
  final m = base != null
      ? List<double>.from(base)
      : <double>[
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ];
  if (brightness == 1.0 && contrast == 1.0) return m;

  final scale = contrast * brightness;
  final offset = (1.0 - contrast) * 128.0 + (brightness - 1.0) * 128.0;
  for (final row in [0, 5, 10]) {
    m[row + 0] *= scale;
    m[row + 1] *= scale;
    m[row + 2] *= scale;
    m[row + 4] = m[row + 4] * scale + offset;
  }
  return m;
}
