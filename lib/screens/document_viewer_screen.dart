import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../data/models.dart';

class DocumentViewerScreen extends StatefulWidget {
  final ScanDocument doc;
  final int initialPage;
  const DocumentViewerScreen({
    super.key,
    required this.doc,
    this.initialPage = 0,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: widget.initialPage);
    _currentPage = widget.initialPage;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _toggleUI() => setState(() => _showUI = !_showUI);

  Future<void> _share() async {
    final file = File(widget.doc.pdfPath);
    if (await file.exists()) {
      await Share.shareXFiles(
        [XFile(widget.doc.pdfPath, mimeType: 'application/pdf')],
        subject: widget.doc.name,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.doc.pageImagePaths;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleUI,
        child: Stack(
          fit: StackFit.expand,
          children: [
            pages.isEmpty
                ? const Center(
                    child: Icon(Icons.picture_as_pdf_rounded,
                        size: 80, color: Colors.white24))
                : PageView.builder(
                    controller: _pageCtrl,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) {
                      final file = File(pages[i]);
                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: file.existsSync()
                            ? Image.file(file, fit: BoxFit.contain)
                            : const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    size: 48, color: Colors.white38)),
                      );
                    },
                  ),
            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _buildTopBar(pages.length),
              ),
            ),
            // Page dots
            if (pages.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0, right: 0,
                child: AnimatedOpacity(
                  opacity: _showUI ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildDots(pages.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(int pageCount) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(180), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16, right: 16, bottom: 32,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.doc.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (pageCount > 1)
                  Text(
                    'Page ${_currentPage + 1} of $pageCount',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _share,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.share_outlined,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots(int count) {
    final dots = count > 10 ? 10 : count;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        dots,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: i == _currentPage ? 18 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: i == _currentPage ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
