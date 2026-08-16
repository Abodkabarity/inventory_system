import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/insurance_assistant_models.dart';
import 'insurance_conversation_pdf_builder.dart';

class InsuranceConversationPdfExporter {
  const InsuranceConversationPdfExporter._();

  static Future<void> export({
    required List<InsuranceChatMessage> messages,
    required String branchName,
    String? conversationTitle,
  }) async {
    if (messages.isEmpty) {
      throw StateError('There are no messages to export.');
    }
    final bytes = await buildPdf(
      messages: messages,
      branchName: branchName,
      conversationTitle: conversationTitle,
    );
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'insurance_conversation_$timestamp.pdf',
      subject: conversationTitle ?? 'Insurance conversation',
    );
  }

  static Future<Uint8List> buildPdf({
    required List<InsuranceChatMessage> messages,
    required String branchName,
    String? conversationTitle,
    pw.Font? regularFont,
    pw.Font? boldFont,
    pw.Font? arabicFont,
  }) async {
    // Noto Sans Arabic does not contain every Latin glyph. Using it as the
    // only base font caused the exported English text to render as squares.
    // Keep the full Latin font as the base and use Arabic as a true fallback.
    regularFont ??= await PdfGoogleFonts.notoSansRegular();
    boldFont ??= await PdfGoogleFonts.notoSansBold();
    arabicFont ??= await PdfGoogleFonts.notoSansArabicRegular();

    return InsuranceConversationPdfBuilder.build(
      messages: messages,
      regularFont: regularFont,
      boldFont: boldFont,
      arabicFont: arabicFont,
      title: conversationTitle,
    );
  }
}
