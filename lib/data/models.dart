import 'package:flutter/material.dart';

class ScanDocument {
  final String id;
  final String name;
  final String pdfPath;
  final List<String> pageImagePaths;
  final String? folderId;
  final DateTime createdAt;
  final int sizeBytes;

  const ScanDocument({
    required this.id,
    required this.name,
    required this.pdfPath,
    required this.pageImagePaths,
    this.folderId,
    required this.createdAt,
    required this.sizeBytes,
  });

  ScanDocument copyWith({
    String? name,
    String? pdfPath,
    String? folderId,
    bool clearFolder = false,
  }) =>
      ScanDocument(
        id: id,
        name: name ?? this.name,
        pdfPath: pdfPath ?? this.pdfPath,
        pageImagePaths: pageImagePaths,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        createdAt: createdAt,
        sizeBytes: sizeBytes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pdfPath': pdfPath,
        'pageImagePaths': pageImagePaths,
        if (folderId != null) 'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  factory ScanDocument.fromJson(Map<String, dynamic> j) => ScanDocument(
        id: j['id'] as String,
        name: j['name'] as String,
        pdfPath: j['pdfPath'] as String,
        pageImagePaths: List<String>.from(j['pageImagePaths'] as List),
        folderId: j['folderId'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        sizeBytes: j['sizeBytes'] as int,
      );

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}, ${createdAt.year}';
  }

  String get meta => '$formattedDate • $formattedSize';

  Color get iconColor {
    final hash = id.codeUnits.fold(0, (a, b) => a + b);
    const colors = [
      Color(0xFFFF453A),
      Color(0xFF30D158),
      Color(0xFF2563EB),
      Color(0xFFFFA400),
    ];
    return colors[hash % colors.length];
  }
}

class ScanFolder {
  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;

  const ScanFolder({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ScanFolder.fromJson(Map<String, dynamic> j) => ScanFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        colorValue: j['colorValue'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
