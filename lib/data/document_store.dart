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
  List<String> _recentSearches = [];
  bool _initialized = false;
  bool _testMode = false;

  List<ScanDocument> get documents => List.unmodifiable(_docs);
  List<ScanFolder> get folders => List.unmodifiable(_folders);
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  ScanFolder? folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  @visibleForTesting
  void seedForTesting({
    List<ScanDocument>? docs,
    List<ScanFolder>? folders,
    List<String>? recentSearches,
  }) {
    _testMode = true;
    if (docs != null) _docs = [...docs];
    if (folders != null) _folders = [...folders];
    if (recentSearches != null) _recentSearches = [...recentSearches];
  }

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
      _recentSearches = List<String>.from((data['recentSearches'] as List?) ?? []);
    } catch (e) {
      debugPrint('DocumentStore load error: $e');
    }
  }

  Future<void> _persist() async {
    if (_testMode) return;
    try {
      final dir = await _baseDir;
      await File('$dir/manifest.json').writeAsString(jsonEncode({
        'documents': _docs.map((d) => d.toJson()).toList(),
        'folders': _folders.map((f) => f.toJson()).toList(),
        'recentSearches': _recentSearches,
      }));
    } catch (e) {
      debugPrint('DocumentStore persist error: $e');
    }
  }

  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _recentSearches.removeWhere((item) => item.toLowerCase() == q.toLowerCase());
    _recentSearches.insert(0, q);
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }
    await _persist();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    await _persist();
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
    final doc = _docs.removeAt(idx);
    for (final path in doc.pageImagePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    try {
      final pdfFile = File(doc.pdfPath);
      if (pdfFile.existsSync()) pdfFile.deleteSync();
    } catch (_) {}
    await _persist();
  }

  Future<ScanFolder> createFolder(String name, int colorValue) async {
    final folder = ScanFolder(
      id: _uuid.v4(),
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    _folders.insert(0, folder);
    await _persist();
    return folder;
  }

  Future<void> updateFolder(String id, {String? name, int? colorValue}) async {
    final idx = _folders.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    _folders[idx] = _folders[idx].copyWith(name: name, colorValue: colorValue);
    await _persist();
  }

  Future<void> deleteFolder(String id) async {
    final idx = _folders.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    _folders.removeAt(idx);
    for (var i = 0; i < _docs.length; i++) {
      if (_docs[i].folderId == id) {
        _docs[i] = _docs[i].copyWith(clearFolder: true);
      }
    }
    await _persist();
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
