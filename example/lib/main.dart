import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdftron_flutter/pdftron_flutter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Viewer(),
    );
  }
}

class Viewer extends StatefulWidget {
  @override
  _ViewerState createState() => _ViewerState();
}

class _ViewerState extends State<Viewer> {
  // PDF Reference 1.7 — 756 pages, publicly available.
  // Annotations in the XFDF are distributed across pages 0-599.
  final String _document =
      "https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf";

  @override
  void initState() {
    super.initState();
    _initPlatformState();
  }

  Future<void> _initPlatformState() async {
    try {
      PdftronFlutter.initialize("your_pdftron_license_key");
    } on PlatformException catch (e) {
      print("Failed to initialize PDFTron: ${e.message}");
    }
  }

  void _onDocumentViewCreated(DocumentViewController controller) async {
    var config = Config();

    // Listen for the document loaded event — equivalent to knowing the
    // PDF is fully rendered and interactive.
    startDocumentLoadedListener((filePath) {
      print("Document loaded: $filePath");

      // Simulate receiving a large XFDF payload from a backend API
      // after the document has been rendered.
      _fetchAndImportAnnotations(controller);
    });

    await controller.openDocument(_document, config: config);
  }

  /// Simulates an API call that returns a ~28MB XFDF payload, then
  /// imports it via the PDFTron SDK. The import runs on the platform
  /// UI thread and blocks it for 7-10s, causing ANR/freeze.
  Future<void> _fetchAndImportAnnotations(
      DocumentViewController controller) async {
    print("[ANR Repro] Simulating API fetch of large XFDF...");

    // Simulate network delay (e.g., downloading 28MB from server).
    await Future.delayed(const Duration(seconds: 2));

    // Load the XFDF from a local asset — in production this would be
    // the response body from an HTTP GET call.
    final String xfdfString = await rootBundle.loadString(
      'assets/sample_large_annotations.xfdf',
    );

    print("[ANR Repro] XFDF received (${xfdfString.length} chars). "
        "Calling controller.importAnnotations — UI will freeze...");

    try {
      await controller.importAnnotations(xfdfString);
      print("[ANR Repro] importAnnotations completed.");
    } on PlatformException catch (e) {
      print("[ANR Repro] importAnnotations failed: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    return Scaffold(
      body: SafeArea(
        child: DocumentView(
          onCreated: _onDocumentViewCreated,
        ),
      ),
    );
  }
}
