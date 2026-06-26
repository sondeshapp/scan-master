import 'dart:typed_data';
import 'package:image/image.dart' as img;

// Top-level function for Flutter compute() — runs in isolate
Future<Uint8List> processImageFilter(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final filterIndex = args['filterIndex'] as int;

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  img.Image result;
  switch (filterIndex) {
    case 1: // B&W
      result = img.grayscale(src);
      break;
    case 2: // Magic (enhanced contrast + saturation)
      result = img.adjustColor(src, saturation: 1.4, contrast: 1.25);
      break;
    case 3: // Text (high contrast grayscale)
      final gray = img.grayscale(src);
      result = img.adjustColor(gray, contrast: 1.8, brightness: 1.1);
      break;
    case 4: // Sepia
      result = img.sepia(src);
      break;
    default:
      return bytes;
  }

  return Uint8List.fromList(img.encodeJpg(result, quality: 88));
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
