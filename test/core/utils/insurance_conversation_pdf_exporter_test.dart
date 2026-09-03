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

  test('builds the validated presentation card and selected evidence', () async {
    final now = DateTime(2026, 8, 30, 22, 30);
    final bytes = await InsuranceConversationPdfExporter.buildPdf(
      branchName: 'HEKMAT',
      conversationTitle: 'Eligibility comparison',
      regularFont: pw.Font.helvetica(),
      boldFont: pw.Font.helveticaBold(),
      arabicFont: pw.Font.helvetica(),
      messages: [
        InsuranceChatMessage(
          id: 'q-fm',
          role: 'user',
          message: 'Is Family Medicine eligible for preventive and acute CGRP?',
          createdAt: now,
        ),
        InsuranceChatMessage(
          id: 'a-fm',
          role: 'assistant',
          message: 'Internal validator fallback that must not drive the PDF.',
          createdAt: now,
          answerCard: const InsuranceAnswerCard(
            version: '1',
            verdict: 'partial',
            summary: 'Internal summary',
            presentation: InsuranceAnswerPresentation(
              answerType: 'eligibility_comparison',
              displayTitle: 'CGRP eligibility for Family Medicine',
              displayVerdict: 'Acute / Abortive only',
              tone: 'positive',
              complete: true,
              explanation:
                  'Family Medicine is listed for acute therapy but not preventive therapy.',
              comparisonRows: [
                InsurancePresentationRow(
                  label: 'Preventive CGRP',
                  status: 'not_eligible',
                  value: 'Not listed',
                  evidenceIds: ['preventive-evidence'],
                ),
                InsurancePresentationRow(
                  label: 'Acute / Abortive CGRP',
                  status: 'eligible',
                  value: 'Eligible',
                  evidenceIds: ['acute-evidence'],
                ),
              ],
              evidenceSourceCount: 2,
              displayedEvidenceIds: ['preventive-evidence', 'acute-evidence'],
            ),
          ),
          citations: const [
            InsuranceCitation(
              evidenceId: 'preventive-evidence',
              chunkId: 'preventive-chunk',
              documentTitle: 'Preventive CGRP Policy',
              fileName: 'preventive.pdf',
              storageBucket: 'insurance-documents',
              storagePath: 'preventive.pdf',
              excerpt: 'Eligible specialties table.',
              pageFrom: 2,
            ),
            InsuranceCitation(
              evidenceId: 'acute-evidence',
              chunkId: 'acute-chunk',
              documentTitle: 'Acute CGRP Policy',
              fileName: 'acute.pdf',
              storageBucket: 'insurance-documents',
              storagePath: 'acute.pdf',
              excerpt: 'Family Medicine is eligible.',
              pageFrom: 4,
            ),
            InsuranceCitation(
              evidenceId: 'retrieval-only',
              chunkId: 'retrieval-only-chunk',
              documentTitle: 'Irrelevant Erenumab Dose',
              fileName: 'dose.pdf',
              storageBucket: 'insurance-documents',
              storagePath: 'dose.pdf',
              excerpt: 'Retrieved but not answer evidence.',
              pageFrom: 1,
            ),
          ],
        ),
      ],
    );

    expect(bytes.length, greaterThan(2500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
