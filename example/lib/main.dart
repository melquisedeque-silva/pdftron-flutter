import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdftron_flutter/pdftron_flutter.dart';

/// ============================================================
/// REPRODUCTION SAMPLE: Binary Annotation ID Encoding Mismatch
/// ============================================================
///
/// This sample demonstrates a bug in pdftron_flutter where the
/// annotation IDs exported during creation (<add> section) have
/// different encoding than the IDs exported during deletion
/// (<delete> section).
///
/// STEPS TO REPRODUCE:
/// 1. Run this app on any device
/// 2. Draw an ink annotation on the PDF
/// 3. Observe the console log showing the 'name' attribute from <add>
/// 4. Delete that annotation (tap it, then tap delete)
/// 5. Observe the console log showing the <id> from <delete>
/// 6. Compare the two: they may differ due to control character encoding
///    (e.g., raw \r vs &#13;, raw \t vs &#9;)
///
/// EXPECTED: The ID in <delete> should exactly match the 'name' in <add>
/// ACTUAL: Control characters in the ID are encoded differently between
///         add and delete operations, making string comparison fail.
///
/// This prevents backends from correlating create/delete operations
/// using the annotation ID as a key.
/// ============================================================

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
  String _document =
      "https://pdftron.s3.amazonaws.com/downloads/pl/PDFTRON_mobile_about.pdf";

  /// Stores annotation IDs captured from <add> operations.
  /// Key: the raw 'name' attribute value from the XFDF <add> section.
  final Map<String, String> _createdAnnotationIds = {};

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    try {
      PdftronFlutter.initialize("your_pdftron_license_key");
    } on PlatformException catch (e) {
      print("Failed to initialize PDFTron: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return Scaffold(
      appBar: AppBar(
        title: Text('Binary ID Bug Reproduction'),
      ),
      body: SafeArea(
        child: DocumentView(
          onCreated: _onDocumentViewCreated,
        ),
      ),
    );
  }

  void _onDocumentViewCreated(DocumentViewController controller) async {
    Config config = Config();
    config.annotationToolbars = [
      DefaultToolbars.annotate,
      DefaultToolbars.draw,
    ];

    await controller.openDocument(_document, config: config);

    // Listen for annotation changes (create, modify, delete)
    startExportAnnotationCommandListener((xfdfCommand) {
      _analyzeXfdfCommand(xfdfCommand);
    });
  }

  /// Analyzes the XFDF command to detect ID encoding mismatches.
  void _analyzeXfdfCommand(dynamic xfdfCommand) {
    if (xfdfCommand is! String) return;
    final xfdf = xfdfCommand;

    print('\n${'=' * 60}');
    print('XFDF COMMAND RECEIVED');
    print('=' * 60);

    // Extract IDs from <add> section (name="..." attributes)
    final addNameRegex = RegExp(r'<add>.*?</add>', dotAll: true);
    final addMatch = addNameRegex.firstMatch(xfdf);
    if (addMatch != null) {
      final addSection = addMatch.group(0)!;
      final nameRegex = RegExp(r'name="([^"]*)"');
      final nameMatches = nameRegex.allMatches(addSection);
      for (final match in nameMatches) {
        final nameValue = match.group(1)!;
        _createdAnnotationIds[nameValue] = nameValue;

        print('\n[ADD] Annotation created with name:');
        print('  Raw value: "$nameValue"');
        print('  Length: ${nameValue.length}');
        print('  Code units: ${nameValue.codeUnits}');
        _printControlChars(nameValue, '  ');
      }
    }

    // Extract IDs from <delete> section (<id>...</id> tags)
    final deleteRegex = RegExp(r'<delete>.*?</delete>', dotAll: true);
    final deleteMatch = deleteRegex.firstMatch(xfdf);
    if (deleteMatch != null) {
      final deleteSection = deleteMatch.group(0)!;
      final idRegex = RegExp(r'<id>(.*?)</id>', dotAll: true);
      final idMatches = idRegex.allMatches(deleteSection);
      for (final match in idMatches) {
        final idValue = match.group(1)!;

        print('\n[DELETE] Annotation deleted with id:');
        print('  Raw value: "$idValue"');
        print('  Length: ${idValue.length}');
        print('  Code units: ${idValue.codeUnits}');
        _printControlChars(idValue, '  ');

        // Check if this ID matches any created annotation
        print('\n[COMPARISON] Checking against ${_createdAnnotationIds.length} known IDs:');

        bool exactMatch = _createdAnnotationIds.containsKey(idValue);
        print('  Exact string match: $exactMatch');

        if (!exactMatch) {
          print('  ⚠️  BUG DETECTED: The delete ID does NOT match the add name!');
          print('  This means the backend cannot correlate the delete with the create.');
          print('');

          // Try to find a "close" match by normalizing
          for (final createdId in _createdAnnotationIds.keys) {
            final normalizedCreated = _normalizeForComparison(createdId);
            final normalizedDeleted = _normalizeForComparison(idValue);
            if (normalizedCreated == normalizedDeleted) {
              print('  Found normalized match with created ID:');
              print('    Created (raw): "${createdId}"');
              print('    Deleted (raw): "${idValue}"');
              print('    Created code units: ${createdId.codeUnits}');
              print('    Deleted code units: ${idValue.codeUnits}');
              print('');
              print('  DIFFERENCE ANALYSIS:');
              _showDifferences(createdId, idValue);
              break;
            }
          }
        } else {
          print('  ✓ IDs match correctly.');
        }
      }
    }

    print('\n${'=' * 60}\n');
  }

  /// Prints control characters found in a string.
  void _printControlChars(String value, String indent) {
    final controlChars = <String>[];
    for (int i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 32) {
        controlChars.add('pos $i: char $code (0x${code.toRadixString(16)}) = ${_charName(code)}');
      }
    }
    // Check for XML entities
    final entityRegex = RegExp(r'&#(\d+);');
    final entities = entityRegex.allMatches(value);
    for (final match in entities) {
      controlChars.add('XML entity: &#${match.group(1)}; (represents char ${match.group(1)})');
    }
    if (controlChars.isEmpty) {
      print('${indent}Control chars: none');
    } else {
      print('${indent}Control chars/entities found:');
      for (final c in controlChars) {
        print('$indent  - $c');
      }
    }
  }

  /// Shows character-by-character differences between two strings.
  void _showDifferences(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < maxLen; i++) {
      final charA = i < a.length ? a[i] : '<missing>';
      final charB = i < b.length ? b[i] : '<missing>';
      if (charA != charB) {
        final codeA = i < a.length ? a.codeUnitAt(i) : -1;
        final codeB = i < b.length ? b.codeUnitAt(i) : -1;
        print('    pos $i: ADD has "${charA}" (code $codeA) vs DELETE has "${charB}" (code $codeB)');
      }
    }
    if (a.length != b.length) {
      print('    Length difference: ADD=${a.length} vs DELETE=${b.length}');
      print('    (XML entities like &#13; expand "\\r" from 1 char to 5 chars)');
    }
  }

  /// Normalizes a string for comparison by decoding XML entities
  /// and removing control characters.
  String _normalizeForComparison(String value) {
    var normalized = value.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    normalized = normalized.replaceAll(RegExp(r'[\x00-\x20]'), '');
    return normalized;
  }

  /// Returns a human-readable name for a control character.
  String _charName(int code) {
    switch (code) {
      case 0: return 'NULL';
      case 9: return 'TAB';
      case 10: return 'LF (\\n)';
      case 13: return 'CR (\\r)';
      default: return 'CTRL-${code}';
    }
  }
}
