import 'dart:typed_data';

import 'package:daily_order/domain/entities/insurance_assistant_models.dart';
import 'package:daily_order/domain/repositories/insurance_assistant_repository.dart';
import 'package:daily_order/presentation/insurance_assistant/page/insurance_assistant_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInsuranceRepository implements InsuranceAssistantRepository {
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
  }) => ask(
    question: 'confirmed clarification',
    branchName: branchName,
  );

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
  Future<void> submitFeedback(String messageId, int rating) async {}

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
}
