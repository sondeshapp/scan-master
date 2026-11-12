import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Category indices matching ScannerScreen:
/// 0 = Whiteboard (10:16 vertical or 16:10 horizontal)
/// 1 = Book (Open book 2-page spread -> splits into 2 pages at once)
/// 2 = Document (Free aspect ratio)
/// 3 = ID card (ISO ID-1: 1/1.586 vertical or 1.586 horizontal)
/// 4 = Business card (2:3.5 vertical or 3.5:2 horizontal)
Future<List<Uint8List>> processCapturedByCategory(
  Map<String, Object> args,
) async {
  final bytes = args['bytes'] as Uint8List;
  final categoryIndex = (args['categoryIndex'] as int?) ?? 2;
  final isHorizontal = (args['isHorizontal'] as bool?) ?? false;
  final cropLeft = (args['cropLeft'] as double?) ?? 0.0;
  final cropTop = (args['cropTop'] as double?) ?? 0.0;
  final cropWidth = (args['cropWidth'] as double?) ?? 1.0;
  final cropHeight = (args['cropHeight'] as double?) ?? 1.0;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [bytes];

  // Always bake EXIF orientation so pixel dimensions match what the user saw
  final oriented = img.bakeOrientation(decoded);

  final isFullFrame = cropLeft <= 0.005 &&
      cropTop <= 0.005 &&
      cropWidth >= 0.99 &&
      cropHeight >= 0.99;

  final img.Image cropped;
  if (isFullFrame) {
    cropped = oriented;
  } else {
    final x = (oriented.width * cropLeft).round().clamp(0, oriented.width - 2);
    final y = (oriented.height * cropTop).round().clamp(0, oriented.height - 2);
    final w =
        (oriented.width * cropWidth).round().clamp(2, oriented.width - x);
    final h =
        (oriented.height * cropHeight).round().clamp(2, oriented.height - y);
    cropped = img.copyCrop(oriented, x: x, y: y, width: w, height: h);
  }

  if (categoryIndex == 1) {
    // Book mode: split the cropped spread into 2 pages at once
    if (isHorizontal) {
      final halfWidth = cropped.width ~/ 2;
      if (halfWidth < 2) {
        return [Uint8List.fromList(img.encodeJpg(cropped, quality: 90))];
      }
      final leftPage = img.copyCrop(
        cropped,
        x: 0,
        y: 0,
        width: halfWidth,
        height: cropped.height,
      );
      final rightPage = img.copyCrop(
        cropped,
        x: halfWidth,
        y: 0,
        width: cropped.width - halfWidth,
        height: cropped.height,
      );
      return [
        Uint8List.fromList(img.encodeJpg(leftPage, quality: 90)),
        Uint8List.fromList(img.encodeJpg(rightPage, quality: 90)),
      ];
    } else {
      final halfHeight = cropped.height ~/ 2;
      if (halfHeight < 2) {
        return [Uint8List.fromList(img.encodeJpg(cropped, quality: 90))];
      }
      final topPage = img.copyCrop(
        cropped,
        x: 0,
        y: 0,
        width: cropped.width,
        height: halfHeight,
      );
      final bottomPage = img.copyCrop(
        cropped,
        x: 0,
        y: halfHeight,
        width: cropped.width,
        height: cropped.height - halfHeight,
      );
      return [
        Uint8List.fromList(img.encodeJpg(topPage, quality: 90)),
        Uint8List.fromList(img.encodeJpg(bottomPage, quality: 90)),
      ];
    }
  }

  return [Uint8List.fromList(img.encodeJpg(cropped, quality: 90))];
}

/// Unwarps a 4-corner quadrilateral (`tl, tr, br, bl` in normalized 0..1 coordinates
/// of the rotated image) into a flat rectangular JPEG image for live preview.
Future<Uint8List> unwarpPageQuadPreview(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final quarterTurns = ((args['quarterTurns'] as int?) ?? 0) % 4;
  final tlX = (args['tlX'] as double?) ?? 0.0;
  final tlY = (args['tlY'] as double?) ?? 0.0;
  final trX = (args['trX'] as double?) ?? 1.0;
  final trY = (args['trY'] as double?) ?? 0.0;
  final brX = (args['brX'] as double?) ?? 1.0;
  final brY = (args['brY'] as double?) ?? 1.0;
  final blX = (args['blX'] as double?) ?? 0.0;
  final blY = (args['blY'] as double?) ?? 1.0;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  img.Image current = img.bakeOrientation(decoded);
  if (quarterTurns != 0) {
    current = img.copyRotate(current, angle: quarterTurns * 90);
  }

  current = _unwarpQuad(
    current,
    tlX: tlX,
    tlY: tlY,
    trX: trX,
    trY: trY,
    brX: brX,
    brY: brY,
    blX: blX,
    blY: blY,
  );

  return Uint8List.fromList(img.encodeJpg(current, quality: 90));
}

// Top-level function for Flutter compute() — runs in isolate
Future<Uint8List> processImageFilter(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final filterIndex = (args['filterIndex'] as int?) ?? 0;
  final quarterTurns = ((args['quarterTurns'] as int?) ?? 0) % 4;
  final cropMargin = (args['cropMargin'] as double?) ?? 0.0;
  final brightness = (args['brightness'] as double?) ?? 1.0;
  final contrast = (args['contrast'] as double?) ?? 1.0;

  // Support either 4-corner quad coordinates or rectangular crop bounds
  final hasQuad = args.containsKey('tlX');
  final tlX = (args['tlX'] as double?) ??
      (args['cropLeft'] as double?) ??
      cropMargin;
  final tlY = (args['tlY'] as double?) ??
      (args['cropTop'] as double?) ??
      cropMargin;
  final cropW = (args['cropWidth'] as double?) ?? (1.0 - cropMargin * 2);
  final cropH = (args['cropHeight'] as double?) ?? (1.0 - cropMargin * 2);
  final trX = (args['trX'] as double?) ?? (tlX + cropW);
  final trY = (args['trY'] as double?) ?? tlY;
  final brX = (args['brX'] as double?) ?? (tlX + cropW);
  final brY = (args['brY'] as double?) ?? (tlY + cropH);
  final blX = (args['blX'] as double?) ?? tlX;
  final blY = (args['blY'] as double?) ?? (tlY + cropH);

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  img.Image current = img.bakeOrientation(decoded);

  // 1. Apply rotation (90° increments clockwise)
  if (quarterTurns != 0) {
    current = img.copyRotate(current, angle: quarterTurns * 90);
  }

  // 2. Apply 4-corner quad crop / unwarp
  final isFullQuad = tlX <= 0.005 &&
      tlY <= 0.005 &&
      trX >= 0.995 &&
      trY <= 0.005 &&
      brX >= 0.995 &&
      brY >= 0.995 &&
      blX <= 0.005 &&
      blY >= 0.995;

  if (!isFullQuad) {
    if (hasQuad) {
      current = _unwarpQuad(
        current,
        tlX: tlX,
        tlY: tlY,
        trX: trX,
        trY: trY,
        brX: brX,
        brY: brY,
        blX: blX,
        blY: blY,
      );
    } else {
      final x = (current.width * tlX).round().clamp(0, current.width - 2);
      final y = (current.height * tlY).round().clamp(0, current.height - 2);
      final w = (current.width * cropW).round().clamp(2, current.width - x);
      final h = (current.height * cropH).round().clamp(2, current.height - y);
      if (w > 1 && h > 1) {
        current = img.copyCrop(current, x: x, y: y, width: w, height: h);
      }
    }
  }

  // 3. Apply filter + brightness/contrast using the exact same color matrix
  // as the live GPU preview so saved output matches the preview 100%.
  final matrix = buildPreviewMatrix(
    filterIndex: filterIndex,
    brightness: brightness,
    contrast: contrast,
  );

  if (matrix != null) {
    _applyColorMatrixInPlace(current, matrix);
  }

  return Uint8List.fromList(img.encodeJpg(current, quality: 90));
}

/// Performs bilinear quadrilateral unwarping from 4 independent normalized corners
/// `(tl, tr, br, bl)` to a straightened rectangular image.
img.Image _unwarpQuad(
  img.Image src, {
  required double tlX,
  required double tlY,
  required double trX,
  required double trY,
  required double brX,
  required double brY,
  required double blX,
  required double blY,
}) {
  final sw = src.width.toDouble();
  final sh = src.height.toDouble();

  // Fast path if the 4 corners form an axis-aligned rectangle
  final isAxisAligned = (tlY - trY).abs() < 0.003 &&
      (blY - brY).abs() < 0.003 &&
      (tlX - blX).abs() < 0.003 &&
      (trX - brX).abs() < 0.003;
  if (isAxisAligned) {
    final x = (sw * math.min(tlX, blX)).round().clamp(0, src.width - 2);
    final y = (sh * math.min(tlY, trY)).round().clamp(0, src.height - 2);
    final right = (sw * math.max(trX, brX)).round().clamp(x + 2, src.width);
    final bottom = (sh * math.max(blY, brY)).round().clamp(y + 2, src.height);
    return img.copyCrop(src, x: x, y: y, width: right - x, height: bottom - y);
  }

  final p0x = tlX * (sw - 1), p0y = tlY * (sh - 1);
  final p1x = trX * (sw - 1), p1y = trY * (sh - 1);
  final p2x = brX * (sw - 1), p2y = brY * (sh - 1);
  final p3x = blX * (sw - 1), p3y = blY * (sh - 1);

  final topW = math.sqrt(math.pow(p1x - p0x, 2) + math.pow(p1y - p0y, 2));
  final botW = math.sqrt(math.pow(p2x - p3x, 2) + math.pow(p2y - p3y, 2));
  final leftH = math.sqrt(math.pow(p3x - p0x, 2) + math.pow(p3y - p0y, 2));
  final rightH = math.sqrt(math.pow(p2x - p1x, 2) + math.pow(p2y - p1y, 2));

  final outW = math.max(topW, botW).round().clamp(16, src.width);
  final outH = math.max(leftH, rightH).round().clamp(16, src.height);

  final dst = img.Image(width: outW, height: outH);
  final maxX = src.width - 1;
  final maxY = src.height - 1;
  final invW = outW > 1 ? 1.0 / (outW - 1) : 0.0;
  final invH = outH > 1 ? 1.0 / (outH - 1) : 0.0;

  for (var y = 0; y < outH; y++) {
    final v = y * invH;
    final oneMinusV = 1.0 - v;
    final lx = oneMinusV * p0x + v * p3x;
    final ly = oneMinusV * p0y + v * p3y;
    final rx = oneMinusV * p1x + v * p2x;
    final ry = oneMinusV * p1y + v * p2y;

    for (var x = 0; x < outW; x++) {
      final u = x * invW;
      final sx = (lx + u * (rx - lx)).round().clamp(0, maxX);
      final sy = (ly + u * (ry - ly)).round().clamp(0, maxY);
      final sp = src.getPixel(sx, sy);
      dst.setPixelRgb(x, y, sp.r, sp.g, sp.b);
    }
  }

  return dst;
}

void _applyColorMatrixInPlace(img.Image image, List<double> m) {
  final r0 = m[0], r1 = m[1], r2 = m[2], r4 = m[4];
  final g0 = m[5], g1 = m[6], g2 = m[7], g4 = m[9];
  final b0 = m[10], b1 = m[11], b2 = m[12], b4 = m[14];

  for (final p in image) {
    final r = p.r.toDouble();
    final g = p.g.toDouble();
    final b = p.b.toDouble();

    final nr = (r0 * r + r1 * g + r2 * b + r4).round().clamp(0, 255);
    final ng = (g0 * r + g1 * g + g2 * b + g4).round().clamp(0, 255);
    final nb = (b0 * r + b1 * g + b2 * b + b4).round().clamp(0, 255);

    p
      ..r = nr
      ..g = ng
      ..b = nb;
  }
}

// Color filter matrices for fast preview AND exact pixel processing on save
const List<List<double>?> filterMatrices = [
  null, // 0: Original
  [
    // 1: B&W grayscale
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ],
  [
    // 2: Magic (vivid enhanced document contrast & clarity)
    1.32, -0.06, -0.06, 0, -12,
    -0.06, 1.32, -0.06, 0, -12,
    -0.06, -0.06, 1.38, 0, -12,
    0, 0, 0, 1, 0,
  ],
  [
    // 3: Text (crisp high-contrast black text on bright white page)
    0.38, 1.28, 0.14, 0, -88,
    0.38, 1.28, 0.14, 0, -88,
    0.38, 1.28, 0.14, 0, -88,
    0, 0, 0, 1, 0,
  ],
  [
    // 4: Sepia
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ],
];

/// Combines the base filter matrix with user brightness/contrast for live GPU preview
/// and final image processing.
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

  final contrastOffset = (1.0 - contrast) * 128.0;
  final brightnessOffset = (brightness - 1.0) * 180.0;
  final totalOffset = contrastOffset + brightnessOffset;

  for (final row in [0, 5, 10]) {
    m[row + 0] *= contrast;
    m[row + 1] *= contrast;
    m[row + 2] *= contrast;
    m[row + 4] = m[row + 4] * contrast + totalOffset;
  }
  return m;
}
