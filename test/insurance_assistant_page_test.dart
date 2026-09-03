import 'dart:async';
import 'dart:typed_data';

import 'package:daily_order/domain/entities/insurance_assistant_models.dart';
import 'package:daily_order/domain/repositories/insurance_assistant_repository.dart';
import 'package:daily_order/presentation/insurance_assistant/page/insurance_assistant_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInsuranceRepository implements InsuranceAssistantRepository {
  int _recoveryCount = 0;
  @override
  Future<bool> canManageDocuments() async => false;

  @override
  Future<List<InsuranceChatSession>> fetchSessions() async => const [];

  @override
  Future<List<InsuranceChatMessage>> fetchMessages(String sessionId) async =>
      const [];

  @override
  Future<({InsuranceChatMessage message, String sessionId})> ask({
    required String question,
    required String branchName,
    String? sessionId,
    bool debug = false,
  }) async => (
    sessionId: 'session-1',
    message: InsuranceChatMessage(
      id: 'answer-1',
      role: 'assistant',
      message: 'The maximum dose is 200 mg in 24 hours.',
      createdAt: DateTime(2026, 8, 12),
      confidence: .94,
      citations: const [
        InsuranceCitation(
          chunkId: 'chunk-1',
          documentTitle: 'CGRP Guideline',
          fileName: 'cgrp.pdf',
          storageBucket: 'insurance-documents',
          storagePath: 'cgrp.pdf',
          excerpt: 'Ubrogepant maximum dose is 200 mg in 24 hours.',
          pageFrom: 4,
        ),
      ],
    ),
  );

  @override
  Future<({InsuranceChatMessage message, String sessionId})>
  confirmClarification({
    required String clarificationId,
    required String candidateId,
    required String branchName,
  }) => ask(question: 'confirmed clarification', branchName: branchName);

  @override
  Future<String> createSourceUrl(InsuranceCitation citation) async =>
      'https://example.com/source.pdf';

  @override
  Future<List<InsuranceDocumentSummary>> fetchDocuments() async => const [];

  @override
  Future<List<Map<String, dynamic>>> inspectSearch(String query) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> inspectSource(String documentId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchKnowledgeReadiness() async =>
      const [];

  @override
  Future<void> submitFeedback(String messageId, int rating) async {}

  @override
  Future<InsuranceChatMessage?> recoverFromFeedback({
    required String messageId,
    required String reason,
    required String branchName,
  }) async {
    if (_recoveryCount++ > 0) return null;
    return InsuranceChatMessage(
      id: 'deep-review-1',
      role: 'assistant',
      message: 'The dose was re-checked against the approved policy.',
      createdAt: DateTime(2026, 8, 12, 12, 1),
      recoveryDepth: 1,
      citations: const [
        InsuranceCitation(
          chunkId: 'chunk-deep-1',
          documentTitle: 'CGRP Guideline',
          fileName: 'cgrp.pdf',
          storageBucket: 'insurance-documents',
          storagePath: 'cgrp.pdf',
          excerpt: 'The approved policy supports this dose.',
          pageFrom: 4,
        ),
      ],
    );
  }

  @override
  Future<void> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {}
}

class _HistoryInsuranceRepository extends _FakeInsuranceRepository {
  static final _timestamp = DateTime(2026, 8, 13, 13, 45);

  @override
  Future<List<InsuranceChatSession>> fetchSessions() async => [
    InsuranceChatSession(
      id: 'history-1',
      title: 'What is Mounjaro?',
      updatedAt: _timestamp,
    ),
  ];

  @override
  Future<List<InsuranceChatMessage>> fetchMessages(String sessionId) async => [
    InsuranceChatMessage(
      id: 'question-1',
      role: 'user',
      message: 'What is Mounjaro?',
      createdAt: _timestamp,
    ),
    InsuranceChatMessage(
      id: 'answer-1',
      role: 'assistant',
      message:
          'The approved document does not provide a general description of Mounjaro.\n\nSource\nGLP-1 Adjudication Rule Summary • Page 2',
      createdAt: _timestamp,
    ),
  ];
}

class _SlowFeedbackInsuranceRepository extends _FakeInsuranceRepository {
  final recoveryStarted = Completer<void>();
  final recoveryResult = Completer<InsuranceChatMessage?>();

  @override
  Future<InsuranceChatMessage?> recoverFromFeedback({
    required String messageId,
    required String reason,
    required String branchName,
  }) {
    if (!recoveryStarted.isCompleted) recoveryStarted.complete();
    return recoveryResult.future;
  }
}

class _StructuredAnswerRepository extends _FakeInsuranceRepository {
  final bool professional;

  _StructuredAnswerRepository({this.professional = false});

  @override
  Future<({InsuranceChatMessage message, String sessionId})> ask({
    required String question,
    required String branchName,
    String? sessionId,
    bool debug = false,
  }) async => (
    sessionId: 'structured-session',
    message: InsuranceChatMessage(
      id: 'structured-answer',
      role: 'assistant',
      message: 'نص احتياطي للرسائل القديمة',
      createdAt: DateTime(2026, 8, 29),
      answerStatus: 'grounded',
      evidenceChecked: true,
      answerGenerator: 'together',
      aiGenerated: true,
      answerCard: professional
          ? const InsuranceAnswerCard(
              version: '1',
              verdict: 'partial',
              summary: 'Internal validator summary.',
              presentation: InsuranceAnswerPresentation(
                answerType: 'eligibility_comparison',
                displayTitle: 'CGRP eligibility for Family Medicine',
                displayVerdict: 'Acute / Abortive only',
                tone: 'positive',
                complete: true,
                explanation:
                    'Family Medicine is eligible for acute CGRP therapy and is not listed for preventive CGRP therapy.',
                comparisonRows: [
                  InsurancePresentationRow(
                    label: 'Preventive',
                    status: 'eligible',
                    value: 'Neurology · Neurosurgery · Internal Medicine',
                    evidenceIds: ['evidence-1', 'evidence-2'],
                  ),
                  InsurancePresentationRow(
                    label: 'Acute / Abortive',
                    status: 'eligible',
                    value:
                        'Neurology · Neurosurgery · Internal Medicine · Family Medicine',
                    evidenceIds: ['evidence-2'],
                  ),
                ],
                evidenceSourceCount: 2,
                displayedEvidenceIds: ['evidence-1', 'evidence-2'],
              ),
            )
          : const InsuranceAnswerCard(
              version: '1',
              verdict: 'conditional',
              summary: 'يمكن النظر في التغطية بعد استكمال الشروط المتبقية.',
              criteria: [
                InsuranceAnswerCriterion(
                  label: 'شرط العمر',
                  status: 'met',
                  detail: 'عمر المريض يطابق الحد المذكور في السياسة.',
                  evidenceIds: ['evidence-1'],
                ),
                InsuranceAnswerCriterion(
                  label: 'العلاج السابق',
                  status: 'unknown',
                  evidenceIds: ['evidence-2'],
                ),
              ],
              doseSchedule: InsuranceDoseSchedule(
                dose: '75 mg',
                route: 'تحت الجلد',
                maintenance: 'كل 4 أسابيع',
                evidenceIds: ['evidence-1'],
              ),
              missingInformation: ['تفاصيل العلاج السابق'],
              nextAction: 'تحقق من سجل العلاج قبل إرسال طلب الموافقة.',
              claims: [
                InsuranceAnswerClaim(
                  id: 'claim-1',
                  text: 'جرعة الاستمرار موثقة في السياسة.',
                  evidenceIds: ['evidence-1'],
                  evidenceQuote: 'ثم كل أربعة أسابيع.',
                ),
              ],
            ),
      citations: [
        for (var index = 1; index <= 5; index++)
          InsuranceCitation(
            evidenceId: 'evidence-$index',
            chunkId: 'chunk-$index',
            documentTitle: 'وثيقة السياسة $index',
            fileName: 'policy-$index.pdf',
            storageBucket: 'insurance-documents',
            storagePath: 'policy-$index.pdf',
            excerpt: 'الدليل رقم $index',
            pageFrom: index,
            supportLevel: index == 1 ? 'gold_evidence' : 'supporting_evidence',
          ),
      ],
    ),
  );
}

void main() {
  testWidgets('assistant renders premium welcome and grounded answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InsuranceAssistantPage(
            branchName: 'HEKMAT',
            onBack: () {},
            repository: _FakeInsuranceRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insurance Knowledge Assistant'), findsOneWidget);
    expect(find.text('Ask. Verify. Dispense with confidence.'), findsOneWidget);
    expect(find.text('Dose check'), findsOneWidget);
    await expectLater(
      find.byType(InsuranceAssistantPage),
      matchesGoldenFile('goldens/insurance_assistant_welcome.png'),
    );

    await tester.tap(find.text('Dose check'));
    await tester.pumpAndSettle();

    expect(
      find.text('The maximum dose is 200 mg in 24 hours.'),
      findsOneWidget,
    );
    expect(find.textContaining('CGRP Guideline'), findsWidgets);
    expect(find.textContaining('Page 4'), findsWidgets);
  });

  testWidgets('historical chat is readable and ListTile paints on Material', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InsuranceAssistantPage(
            branchName: 'HEKMAT',
            onBack: () {},
            repository: _HistoryInsuranceRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('What is Mounjaro?').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('ANSWER'), findsOneWidget);
    expect(
      find.text(
        'The approved document does not provide a general description of Mounjaro.',
      ),
      findsOneWidget,
    );
    expect(find.text('SOURCE'), findsOneWidget);
    expect(
      find.text('GLP-1 Adjudication Rule Summary • Page 2'),
      findsOneWidget,
    );

    final questionTop = tester
        .getTopLeft(find.text('What is Mounjaro?').last)
        .dy;
    final answerTop = tester
        .getTopLeft(
          find.text(
            'The approved document does not provide a general description of Mounjaro.',
          ),
        )
        .dy;
    expect(questionTop, lessThan(answerTop));
  });

  testWidgets('composer remains editable immediately after an answer arrives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InsuranceAssistantPage(
            branchName: 'HEKMAT',
            onBack: () {},
            repository: _FakeInsuranceRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dose check'));
    await tester.pumpAndSettle();
    expect(
      find.text('The maximum dose is 200 mg in 24 hours.'),
      findsOneWidget,
    );

    final composer = find.byType(TextField).first;
    final field = tester.widget<TextField>(composer);
    expect(field.enabled, isNot(false));
    await tester.tap(composer);
    await tester.enterText(composer, 'Can I ask another question?');
    expect(find.text('Can I ask another question?'), findsOneWidget);
  });

  testWidgets('feedback reasons stay visible and render one deep review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InsuranceAssistantPage(
            branchName: 'HEKMAT',
            onBack: () {},
            repository: _FakeInsuranceRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dose check'));
    await tester.tap(find.text('Dose check'));
    await tester.pumpAndSettle();

    expect(find.text('Was this answer helpful?'), findsOneWidget);
    expect(find.text('Incorrect'), findsOneWidget);
    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text('What should I improve?'), findsNothing);
    expect(find.text('Misunderstood my question'), findsNothing);
    expect(find.text('Wrong source'), findsNothing);
    expect(find.text('Other'), findsNothing);

    await tester.tap(find.text('Incomplete'));
    await tester.pumpAndSettle();

    expect(find.text('DEEP REVIEW'), findsOneWidget);
    expect(
      find.text('Re-checked across approved documents after your feedback'),
      findsOneWidget,
    );
    expect(find.text('Was this deep review helpful?'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('PREVIOUS ANSWER'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Incorrect'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('DEEP REVIEW'), findsOneWidget);
  });

  testWidgets('negative feedback scrolls to the active evidence search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SlowFeedbackInsuranceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InsuranceAssistantPage(
            branchName: 'HEKMAT',
            onBack: () {},
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dose check'));
    await tester.tap(find.text('Dose check'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Incomplete'));
    await tester.tap(find.text('Incomplete'));
    await repository.recoveryStarted.future;
    await tester.pump(const Duration(milliseconds: 400));

    final searching = find.text('Searching policies and verifying evidence...');
    expect(searching, findsOneWidget);
    expect(tester.getBottomRight(searching).dy, lessThan(844));

    repository.recoveryResult.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'renders Arabic V5 answer card with claim evidence and all sources',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InsuranceAssistantPage(
              branchName: 'HEKMAT',
              onBack: () {},
              repository: _StructuredAnswerRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dose check'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('insurance-answer-card')),
        findsOneWidget,
      );
      expect(find.text('النتيجة'), findsOneWidget);
      expect(find.text('تغطية مشروطة'), findsOneWidget);
      expect(find.text('شروط التغطية'), findsOneWidget);
      expect(find.text('المعلومات الناقصة'), findsOneWidget);
      expect(find.text('الخطوة التالية'), findsOneWidget);
      expect(find.text('الحقائق المرتبطة بالأدلة'), findsOneWidget);
      expect(find.text('دليل مباشر معتمد'), findsOneWidget);
      expect(find.text('دليل 1'), findsWidgets);
      expect(find.text('وثيقة السياسة 4 • صفحة 4'), findsNothing);

      final summary = find.text(
        'يمكن النظر في التغطية بعد استكمال الشروط المتبقية.',
      );
      expect(
        tester
            .widgetList<Directionality>(
              find.ancestor(of: summary, matching: find.byType(Directionality)),
            )
            .any((widget) => widget.textDirection == TextDirection.rtl),
        isTrue,
      );

      final showAll = find.text('إظهار كل المصادر (5)');
      await tester.ensureVisible(showAll);
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      expect(find.text('وثيقة السياسة 4 • صفحة 4'), findsOneWidget);
      expect(find.text('إخفاء المصادر الإضافية'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the professional comparison and expands only answer evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InsuranceAssistantPage(
              branchName: 'HEKMAT',
              onBack: () {},
              repository: _StructuredAnswerRepository(professional: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dose check'));
      await tester.pumpAndSettle();

      expect(find.text('CGRP eligibility for Family Medicine'), findsOneWidget);
      expect(find.text('Acute / Abortive only'), findsOneWidget);
      expect(find.text('Preventive'), findsOneWidget);
      expect(
        find.text('Neurology · Neurosurgery · Internal Medicine'),
        findsOneWidget,
      );
      expect(find.text('Acute / Abortive'), findsOneWidget);
      expect(
        find.text(
          'Neurology · Neurosurgery · Internal Medicine · Family Medicine',
        ),
        findsOneWidget,
      );
      expect(find.text('Partially established'), findsNothing);
      expect(find.text('Internal validator summary.'), findsNothing);
      expect(find.text('Evidence checked'), findsNothing);
      expect(
        find.text('Evidence verified · 2 approved sources'),
        findsOneWidget,
      );
      expect(find.text('وثيقة السياسة 1'), findsNothing);

      await tester.tap(find.text('View evidence').first);
      await tester.pumpAndSettle();
      expect(find.text('Supporting evidence'), findsOneWidget);
      expect(find.text('وثيقة السياسة 1'), findsOneWidget);
      expect(find.text('وثيقة السياسة 2'), findsOneWidget);
      await tester.tap(find.byType(ModalBarrier).last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('insurance-evidence-verification')),
      );
      await tester.pumpAndSettle();

      expect(find.text('وثيقة السياسة 1'), findsOneWidget);
      expect(find.text('وثيقة السياسة 2'), findsOneWidget);
      expect(find.text('وثيقة السياسة 3'), findsNothing);
    },
  );
}
