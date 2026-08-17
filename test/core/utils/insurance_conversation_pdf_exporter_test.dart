import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/core/utils/insurance_conversation_pdf_exporter.dart';
import 'package:daily_order/domain/entities/insurance_assistant_models.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('builds a question-and-answer-only conversation PDF', () async {
    final now = DateTime(2026, 8, 13, 14, 30);
    final bytes = await InsuranceConversationPdfExporter.buildPdf(
      branchName: 'HEKMAT',
      conversationTitle: 'CGRP coverage review',
      regularFont: pw.Font.helvetica(),
      boldFont: pw.Font.helveticaBold(),
      arabicFont: pw.Font.helvetica(),
      messages: [
        InsuranceChatMessage(
          id: 'q1',
          role: 'user',
          message: 'What are the two main classes?',
          createdAt: now,
        ),
        InsuranceChatMessage(
          id: 'a1',
          role: 'assistant',
          message:
              'The two main classes are monoclonal antibodies and Gepants.',
          createdAt: now,
          citations: const [
            InsuranceCitation(
              chunkId: 'chunk-1',
              documentTitle: 'CGRP Adjudication Rule',
              fileName: 'cgrp.pdf',
              storageBucket: 'insurance-documents',
              storagePath: 'cgrp.pdf',
              excerpt: 'Two classes are listed.',
              pageFrom: 1,
            ),
          ],
        ),
      ],
    );

    expect(bytes.length, greaterThan(1500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
