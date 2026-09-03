import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/insurance_assistant_models.dart';

class InsuranceConversationPdfBuilder {
  const InsuranceConversationPdfBuilder._();

  static Future<Uint8List> build({
    required List<InsuranceChatMessage> messages,
    required pw.Font regularFont,
    required pw.Font boldFont,
    required pw.Font arabicFont,
    String? title,
  }) async {
    if (messages.isEmpty) {
      throw StateError('There are no messages to export.');
    }

    final document = pw.Document(
      title: title ?? 'Insurance conversation',
      author: 'Insurance Knowledge Assistant',
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
        fontFallback: [arabicFont],
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        maxPages: 200,

        build: (_) {
          final widgets = <pw.Widget>[];

          for (final message in _effectiveMessages(messages)) {
            widgets.addAll(_messageWidgets(message));
            widgets.add(pw.SizedBox(height: 16));
          }

          return widgets;
        },
      ),
    );

    return document.save();
  }

  static List<pw.Widget> _messageWidgets(InsuranceChatMessage message) {
    final isQuestion = message.isUser;

    if (!isQuestion && message.answerCard?.presentation != null) {
      return _presentationWidgets(message);
    }

    final value = _plainText(
      isQuestion ? message.message : _answerOnly(message.message),
    );

    final direction = _containsArabic(value)
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;

    final borderColor = isQuestion
        ? PdfColors.indigo200
        : PdfColors.blueGrey200;

    final backgroundColor = isQuestion
        ? PdfColors.indigo50
        : PdfColors.blueGrey50;

    final parts = _splitText(value);

    return [
      // Header is intentionally a separate small widget.
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: backgroundColor,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: borderColor),
        ),
        child: pw.Text(
          isQuestion ? 'QUESTION' : 'ANSWER',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: isQuestion ? PdfColors.indigo700 : PdfColors.green700,
            letterSpacing: 1,
          ),
        ),
      ),

      pw.SizedBox(height: 7),

      // Each portion of the answer is a separate widget.
      // MultiPage can therefore move the next portion to a new page.
      for (final part in parts) ...[
        pw.Directionality(
          textDirection: direction,
          child: pw.Text(
            part,
            textAlign: direction == pw.TextDirection.rtl
                ? pw.TextAlign.right
                : pw.TextAlign.left,
            style: const pw.TextStyle(
              fontSize: 11,
              height: 1.55,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
      ],
      if (!isQuestion && _uniqueCitations(message.citations).isNotEmpty) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          'EVIDENCE',
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.indigo700,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 4),
        ..._uniqueCitations(message.citations).map(
          (citation) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(
              '- ${citation.documentTitle} - ${citation.locationLabel}',
              style: const pw.TextStyle(
                fontSize: 9,
                height: 1.35,
                color: PdfColors.blueGrey700,
              ),
            ),
          ),
        ),
      ],
    ];
  }

  static List<pw.Widget> _presentationWidgets(InsuranceChatMessage message) {
    final presentation = message.answerCard!.presentation!;
    final citations = _displayedCitations(message);
    final tone = _presentationTone(presentation.tone);
    final widgets = <pw.Widget>[];

    // Keep the answer label, title, verdict, and first result together. This
    // prevents a nearly empty continuation page for compact answer cards.
    widgets.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _answerLabel(),
          pw.SizedBox(height: 7),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(13),
            decoration: pw.BoxDecoration(
              color: tone.surface,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: tone.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _directionalText(
                  presentation.displayTitle,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 6),
                _directionalText(
                  presentation.displayVerdict,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: tone.foreground,
                  ),
                ),
              ],
            ),
          ),
          if (presentation.comparisonRows.isNotEmpty) ...[
            pw.SizedBox(height: 9),
            _presentationRows(
              presentation.comparisonRows,
              citations,
              comparison: true,
            ),
          ],
        ],
      ),
    );

    for (final section in presentation.sections) {
      if (section.rows.isEmpty) continue;
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _directionalText(
              section.title,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo800,
              ),
            ),
            pw.SizedBox(height: 5),
            _presentationRows(section.rows, citations),
          ],
        ),
      );
    }

    final explanation = presentation.explanation?.trim();
    if (explanation?.isNotEmpty == true) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(
        _directionalText(
          explanation!,
          style: const pw.TextStyle(
            fontSize: 10.5,
            height: 1.45,
            color: PdfColors.blueGrey800,
          ),
        ),
      );
    }

    if (presentation.missingInformation.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 9));
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: PdfColors.amber200),
          ),
          child: _directionalText(
            presentation.missingInformation.map((item) => '- $item').join('\n'),
            style: const pw.TextStyle(
              fontSize: 9.5,
              height: 1.4,
              color: PdfColors.brown800,
            ),
          ),
        ),
      );
    }

    final nextAction = presentation.nextAction?.trim();
    if (nextAction?.isNotEmpty == true) {
      widgets.add(pw.SizedBox(height: 7));
      widgets.add(
        _directionalText(
          nextAction!,
          style: const pw.TextStyle(
            fontSize: 9.5,
            height: 1.4,
            color: PdfColors.blueGrey800,
          ),
        ),
      );
    }

    if (citations.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.green200),
              ),
              child: pw.Text(
                'EVIDENCE VERIFIED - ${presentation.evidenceSourceCount} APPROVED '
                'SOURCE${presentation.evidenceSourceCount == 1 ? '' : 'S'}',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green800,
                  letterSpacing: .4,
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            ...citations.asMap().entries.map(
              (entry) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  '[${entry.key + 1}] ${entry.value.documentTitle} - '
                  '${entry.value.locationLabel}',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    height: 1.3,
                    color: PdfColors.blueGrey700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return widgets;
  }

  static pw.Widget _answerLabel() => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColors.blueGrey50,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.blueGrey200),
    ),
    child: pw.Text(
      'ANSWER',
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.green700,
        letterSpacing: 1,
      ),
    ),
  );

  static pw.Widget _presentationRows(
    List<InsurancePresentationRow> rows,
    List<InsuranceCitation> citations, {
    bool comparison = false,
  }) => pw.Column(
    children: rows
        .map((row) {
          final evidenceNumbers = <int>[];
          for (final id in row.evidenceIds) {
            final index = citations.indexWhere(
              (citation) =>
                  citation.resolvedEvidenceId == id || citation.chunkId == id,
            );
            if (index >= 0 && !evidenceNumbers.contains(index + 1)) {
              evidenceNumbers.add(index + 1);
            }
          }
          final rowTone = _rowTone(row.status);
          return pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 4),
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: pw.BoxDecoration(
              color: comparison ? PdfColors.grey100 : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(color: PdfColors.blueGrey100),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _directionalText(
                    row.label,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey800,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 4,
                  child: _directionalText(
                    '${row.value}${evidenceNumbers.isEmpty ? '' : '  [${evidenceNumbers.join(', ')}]'}',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: comparison
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      color: comparison ? rowTone : PdfColors.blueGrey900,
                    ),
                  ),
                ),
              ],
            ),
          );
        })
        .toList(growable: false),
  );

  static pw.Widget _directionalText(String value, {pw.TextStyle? style}) {
    final normalized = _plainText(value);
    final direction = _containsArabic(normalized)
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;
    return pw.Directionality(
      textDirection: direction,
      child: pw.Text(
        normalized,
        textAlign: direction == pw.TextDirection.rtl
            ? pw.TextAlign.right
            : pw.TextAlign.left,
        style: style,
      ),
    );
  }

  static ({PdfColor foreground, PdfColor surface, PdfColor border})
  _presentationTone(String tone) => switch (tone) {
    'positive' => (
      foreground: PdfColors.green800,
      surface: PdfColors.green50,
      border: PdfColors.green200,
    ),
    'negative' => (
      foreground: PdfColors.red800,
      surface: PdfColors.red50,
      border: PdfColors.red200,
    ),
    'warning' => (
      foreground: PdfColors.orange800,
      surface: PdfColors.amber50,
      border: PdfColors.amber200,
    ),
    _ => (
      foreground: PdfColors.indigo800,
      surface: PdfColors.indigo50,
      border: PdfColors.indigo200,
    ),
  };

  static PdfColor _rowTone(String status) => switch (status) {
    'eligible' || 'met' || 'covered' || 'affirmed' => PdfColors.green800,
    'not_eligible' ||
    'not_met' ||
    'not_covered' ||
    'denied' => PdfColors.red800,
    'conditional' || 'unknown' => PdfColors.orange800,
    _ => PdfColors.indigo800,
  };

  static List<InsuranceCitation> _displayedCitations(
    InsuranceChatMessage message,
  ) {
    final ids = message.answerCard?.presentation?.displayedEvidenceIds.toSet();
    final selected = ids == null || ids.isEmpty
        ? message.citations
        : message.citations
              .where(
                (citation) =>
                    ids.contains(citation.resolvedEvidenceId) ||
                    ids.contains(citation.chunkId),
              )
              .toList(growable: false);
    return _uniqueCitations(selected);
  }

  /// Place a deep-review answer where its original answer appeared and omit
  /// the superseded version. This keeps exported question/answer pairs intact
  /// even though a recovery response is created later in the conversation.
  static List<InsuranceChatMessage> _effectiveMessages(
    List<InsuranceChatMessage> messages,
  ) {
    final replacements = <String, InsuranceChatMessage>{};
    for (final message in messages) {
      final originalId = message.recoveryOfMessageId;
      if (!message.isUser && originalId != null && originalId.isNotEmpty) {
        replacements[originalId] = message;
      }
    }
    if (replacements.isEmpty) return messages;

    final recoveryIds = replacements.values
        .map((message) => message.id)
        .toSet();
    final result = <InsuranceChatMessage>[];
    for (final message in messages) {
      if (recoveryIds.contains(message.id)) continue;
      result.add(replacements[message.id] ?? message);
    }
    return result;
  }

  static List<InsuranceCitation> _uniqueCitations(
    List<InsuranceCitation> citations,
  ) {
    final unique = <String, InsuranceCitation>{};
    for (final citation in citations) {
      final document = citation.documentId?.trim().isNotEmpty == true
          ? citation.documentId!
          : citation.documentTitle.trim().toLowerCase();
      final key = '$document|${citation.locationLabel.toLowerCase()}';
      final existing = unique[key];
      if (existing == null || citation.score > existing.score) {
        unique[key] = citation;
      }
    }
    return unique.values.toList(growable: false);
  }

  /// Break large answers into manageable widgets so no individual
  /// Text widget can become taller than an A4 page.
  static List<String> _splitText(String value) {
    const maxChars = 1000;

    final result = <String>[];

    final paragraphs = value.split(RegExp(r'\n+'));

    for (final paragraph in paragraphs) {
      final text = paragraph.trim();

      if (text.isEmpty) {
        continue;
      }

      if (text.length <= maxChars) {
        result.add(text);
        continue;
      }

      var remaining = text;

      while (remaining.length > maxChars) {
        var cut = maxChars;

        final space = remaining.lastIndexOf(' ', maxChars);

        if (space > maxChars ~/ 2) {
          cut = space;
        }

        result.add(remaining.substring(0, cut).trim());

        remaining = remaining.substring(cut).trim();
      }

      if (remaining.isNotEmpty) {
        result.add(remaining);
      }
    }

    if (result.isEmpty) {
      result.add(value);
    }

    return result;
  }

  static bool _containsArabic(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  static String _plainText(String value) => value
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll('‑', '-')
      .replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1')
      .replaceAll(RegExp(r'([.!?])\1+'), r'$1')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String _answerOnly(String value) => value
      .replaceFirst(RegExp(r'\n+Source\s*\n[\s\S]*$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\n+المصدر\s*\n[\s\S]*$'), '')
      .trim();
}
