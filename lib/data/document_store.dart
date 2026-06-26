import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';

class DocumentStore {
  static final DocumentStore instance = DocumentStore._();
  DocumentStore._();

  static const _uuid = Uuid();
  List<ScanDocument> _docs = [];
  List<ScanFolder> _folders = [];
  bool _initialized = false;

  List<ScanDocument> get documents => List.unmodifiable(_docs);
  List<ScanFolder> get folders => List.unmodifiable(_folders);

  List<ScanDocument> get uncategorized =>
      _docs.where((d) => d.folderId == null).toList();

  List<ScanDocument> documentsInFolder(String folderId) =>
      _docs.where((d) => d.folderId == folderId).toList();

  int folderFileCount(String folderId) => documentsInFolder(folderId).length;

  List<ScanDocument> search(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return _docs.where((d) => d.name.toLowerCase().contains(q)).toList();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _load();
    if (_folders.isEmpty) {
      _folders = [
        ScanFolder(id: _uuid.v4(), name: 'Invoices', colorValue: 0xFF2563EB, createdAt: DateTime.now()),
        ScanFolder(id: _uuid.v4(), name: 'Tax 2023', colorValue: 0xFFF97316, createdAt: DateTime.now()),
        ScanFolder(id: _uuid.v4(), name: 'School', colorValue: 0xFF22C55E, createdAt: DateTime.now()),
        ScanFolder(id: _uuid.v4(), name: 'Work', colorValue: 0xFFA855F7, createdAt: DateTime.now()),
      ];
      await _persist();
    }
  }

  Future<String> get _baseDir async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> scansDir() async {
    final base = await _baseDir;
    final dir = Directory('$base/scans');
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> pdfsDir() async {
    final base = await _baseDir;
    final dir = Directory('$base/pdfs');
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _load() async {
    try {
      final dir = await _baseDir;
      final file = File('$dir/manifest.json');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _docs = ((data['documents'] as List?) ?? [])
          .map((j) => ScanDocument.fromJson(j as Map<String, dynamic>))
          .toList();
      _folders = ((data['folders'] as List?) ?? [])
          .map((j) => ScanFolder.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('DocumentStore load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final dir = await _baseDir;
      await File('$dir/manifest.json').writeAsString(jsonEncode({
        'documents': _docs.map((d) => d.toJson()).toList(),
        'folders': _folders.map((f) => f.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('DocumentStore persist error: $e');
    }
  }

  Future<ScanDocument> addDocument({
    required String name,
    required String pdfPath,
    required List<String> pageImagePaths,
    String? folderId,
    required int sizeBytes,
  }) async {
    final doc = ScanDocument(
      id: _uuid.v4(),
      name: name,
      pdfPath: pdfPath,
      pageImagePaths: pageImagePaths,
      folderId: folderId,
      createdAt: DateTime.now(),
      sizeBytes: sizeBytes,
    );
    _docs.insert(0, doc);
    await _persist();
    return doc;
  }

  Future<void> deleteDocument(String id) async {
    final idx = _docs.indexWhere((d) => d.id == id);
    if (idx < 0) return;
    final doc = _docs[idx];
    for (final path in doc.pageImagePaths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    try {
      await File(doc.pdfPath).delete();
    } catch (_) {}
    _docs.removeAt(idx);
    await _persist();
  }

  Future<ScanFolder> createFolder(String name, int colorValue) async {
    final folder = ScanFolder(
      id: _uuid.v4(),
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    _folders.add(folder);
    await _persist();
    return folder;
  }

  Future<void> moveDocument(String docId, String? folderId) async {
    final idx = _docs.indexWhere((d) => d.id == docId);
    if (idx < 0) return;
    _docs[idx] = _docs[idx].copyWith(
      folderId: folderId,
      clearFolder: folderId == null,
    );
    await _persist();
  }

  Future<void> renameDocument(String id, String newName) async {
    final idx = _docs.indexWhere((d) => d.id == id);
    if (idx < 0) return;
    _docs[idx] = _docs[idx].copyWith(name: newName);
    await _persist();
  }
}
