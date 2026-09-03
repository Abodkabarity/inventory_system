import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/insurance_assistant_models.dart';
import '../../domain/repositories/insurance_assistant_repository.dart';
import '../datasources/remote/insurance_assistant_remote_ds.dart';

class InsuranceAssistantRepositoryImpl implements InsuranceAssistantRepository {
  final InsuranceAssistantRemoteDs remote;

  InsuranceAssistantRepositoryImpl(this.remote);

  InsuranceCitation _citation(Map<String, dynamic> map) => InsuranceCitation(
    evidenceId: (map['evidence_id'] ?? map['id'] ?? '').toString(),
    chunkId: (map['chunk_id'] ?? '').toString(),
    documentId: map['document_id']?.toString(),
    documentTitle: (map['document_title'] ?? 'Insurance guideline').toString(),
    fileName: (map['file_name'] ?? '').toString(),
    storageBucket: (map['storage_bucket'] ?? 'insurance-documents').toString(),
    storagePath: (map['storage_path'] ?? '').toString(),
    excerpt: (map['excerpt'] ?? '').toString(),
    sectionTitle: map['section_title']?.toString(),
    pageFrom: (map['page_from'] as num?)?.toInt(),
    pageTo: (map['page_to'] as num?)?.toInt(),
    sheetName: map['sheet_name']?.toString(),
    rowFrom: (map['row_from'] as num?)?.toInt(),
    rowTo: (map['row_to'] as num?)?.toInt(),
    score: (map['score'] as num?)?.toDouble() ?? 0,
    supportLevel: (map['support_level'] ?? 'supporting_evidence').toString(),
  );

  Map<String, dynamic>? _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  List<Object?> _list(Object? value) => value is List ? value : const [];

  String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  List<String> _stringList(Object? value) => _list(
    value,
  ).map(_optionalString).whereType<String>().toList(growable: false);

  InsuranceAnswerCriterion? _criterion(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return InsuranceAnswerCriterion(label: value.trim(), status: 'unknown');
    }
    final row = _map(value);
    final label = _optionalString(
      row?['label'] ?? row?['criterion'] ?? row?['text'],
    );
    if (row == null || label == null) return null;
    return InsuranceAnswerCriterion(
      label: label,
      status: _optionalString(row['status']) ?? 'unknown',
      detail: _optionalString(row['detail'] ?? row['explanation']),
      evidenceIds: _stringList(
        row['evidence_ids'] ?? row['citation_ids'] ?? row['citations'],
      ),
    );
  }

  InsuranceDoseSchedule? _doseSchedule(Object? value) {
    final row = _map(value);
    if (row == null) return null;
    final schedule = InsuranceDoseSchedule(
      dose: _optionalString(row['dose']),
      route: _optionalString(row['route']),
      frequency: _optionalString(row['frequency']),
      loading: _optionalString(row['loading']),
      maintenance: _optionalString(row['maintenance']),
      evidenceIds: _stringList(
        row['evidence_ids'] ?? row['citation_ids'] ?? row['citations'],
      ),
    );
    return schedule.isEmpty ? null : schedule;
  }

  InsuranceAnswerClaim? _claim(Object? value, int index) {
    if (value is String && value.trim().isNotEmpty) {
      return InsuranceAnswerClaim(id: 'claim-$index', text: value.trim());
    }
    final row = _map(value);
    final text = _optionalString(row?['text'] ?? row?['claim']);
    if (row == null || text == null) return null;
    return InsuranceAnswerClaim(
      id: _optionalString(row['id']) ?? 'claim-$index',
      text: text,
      subjectEntityId: _optionalString(row['subject_entity_id']),
      predicate: _optionalString(row['predicate']),
      value: _optionalString(row['value']),
      unit: _optionalString(row['unit']),
      polarity: _optionalString(row['polarity']) ?? 'affirmed',
      certainty: _optionalString(row['certainty']) ?? 'direct',
      evidenceIds: _stringList(
        row['evidence_ids'] ?? row['citation_ids'] ?? row['citations'],
      ),
      evidenceQuote: _optionalString(row['evidence_quote'] ?? row['quote']),
    );
  }

  InsurancePresentationRow? _presentationRow(Object? value) {
    final row = _map(value);
    final label = _optionalString(row?['label']);
    final displayValue = _optionalString(row?['value']);
    if (row == null || label == null || displayValue == null) return null;
    return InsurancePresentationRow(
      label: label,
      status: _optionalString(row['status']) ?? 'informational',
      value: displayValue,
      evidenceIds: _stringList(row['evidence_ids']),
    );
  }

  InsurancePresentationSection? _presentationSection(Object? value) {
    final row = _map(value);
    final id = _optionalString(row?['id']);
    final title = _optionalString(row?['title']);
    if (row == null || id == null || title == null) return null;
    return InsurancePresentationSection(
      id: id,
      title: title,
      rows: _list(row['rows'])
          .map(_presentationRow)
          .whereType<InsurancePresentationRow>()
          .toList(growable: false),
    );
  }

  InsuranceAnswerPresentation? _presentation(Object? value) {
    final row = _map(value);
    final answerType = _optionalString(row?['answer_type']);
    final title = _optionalString(row?['display_title']);
    final verdict = _optionalString(row?['display_verdict']);
    if (row == null || answerType == null || title == null || verdict == null) {
      return null;
    }
    return InsuranceAnswerPresentation(
      answerType: answerType,
      displayTitle: title,
      displayVerdict: verdict,
      tone: _optionalString(row['tone']) ?? 'informational',
      complete: row['complete'] == true,
      explanation: _optionalString(row['explanation']),
      comparisonRows: _list(row['comparison_rows'])
          .map(_presentationRow)
          .whereType<InsurancePresentationRow>()
          .toList(growable: false),
      sections: _list(row['sections'])
          .map(_presentationSection)
          .whereType<InsurancePresentationSection>()
          .toList(growable: false),
      missingInformation: _stringList(row['missing_information']),
      nextAction: _optionalString(row['next_action']),
      evidenceSourceCount: (row['evidence_source_count'] as num?)?.toInt() ?? 0,
      displayedEvidenceIds: _stringList(row['displayed_evidence_ids']),
    );
  }

  InsuranceAnswerCard? _answerCard(Object? value) {
    final row = _map(value);
    if (row == null) return null;
    final verdictValue = row['verdict'];
    final verdictMap = _map(verdictValue);
    final verdict = _optionalString(
      verdictMap?['status'] ?? verdictMap?['value'] ?? verdictValue,
    );
    final summary = _optionalString(
      row['summary'] ?? verdictMap?['summary'] ?? row['answer'],
    );
    if (verdict == null || summary == null) return null;
    final criteria = _list(
      row['criteria'] ?? row['coverage_criteria'],
    ).map(_criterion).whereType<InsuranceAnswerCriterion>().toList();
    final claims = <InsuranceAnswerClaim>[];
    final claimRows = _list(row['claims'] ?? row['supported_claims']);
    for (var index = 0; index < claimRows.length; index++) {
      final claim = _claim(claimRows[index], index);
      if (claim != null) claims.add(claim);
    }
    return InsuranceAnswerCard(
      version: _optionalString(row['version']) ?? '1',
      verdict: verdict,
      summary: summary,
      criteria: criteria,
      doseSchedule: _doseSchedule(
        row['dose_schedule'] ?? row['dose'] ?? row['schedule'],
      ),
      missingInformation: _stringList(
        row['missing_information'] ?? row['missing'] ?? row['unknowns'],
      ),
      nextAction: _optionalString(
        row['next_action'] ?? row['recommended_action'],
      ),
      claims: claims,
      presentation: _presentation(row['presentation']),
    );
  }

  InsuranceChatMessage messageFromMap(Map<String, dynamic> map) {
    final parsedData = _map(map['parsed_data']) ?? const <String, dynamic>{};
    final semantic = _map(parsedData['semantic']);
    const conversationalIntents = {
      'greeting',
      'thanks',
      'goodbye',
      'assistant_identity',
      'assistant_developer',
      'assistant_capabilities',
      'assistant_nature',
      'user_identity',
      'casual_smalltalk',
      'out_of_scope',
      // Compatibility with conversations saved before the dedicated router.
      'capabilities',
    };
    final savedIntent = (parsedData['intent'] ?? parsedData['primary_intent'])
        ?.toString();
    final clarificationMap = map['clarification'] is Map
        ? Map<String, dynamic>.from(map['clarification'] as Map)
        : parsedData['clarification_id'] != null
        ? <String, dynamic>{
            'id': parsedData['clarification_id'],
            'candidates': parsedData['clarification_candidates'],
          }
        : null;
    final candidateRows = clarificationMap?['candidates'] is List
        ? List<Map<String, dynamic>>.from(
            clarificationMap!['candidates'] as List,
          )
        : const <Map<String, dynamic>>[];
    final citations = List<Map<String, dynamic>>.from(
      map['citations'] ?? parsedData['citations'] ?? const [],
    ).map(_citation).toList(growable: false);
    final answerStatus =
        _optionalString(map['answer_status'] ?? parsedData['answer_status']) ??
        'legacy';
    final answerGenerator = _optionalString(
      map['answer_generator'] ?? parsedData['answer_generator'],
    );
    final evidenceChecked =
        map['evidence_checked'] == true ||
        parsedData['evidence_checked'] == true ||
        (answerStatus.startsWith('grounded') && citations.isNotEmpty);
    return InsuranceChatMessage(
      id: (map['id'] ?? map['message_id'] ?? '').toString(),
      role: (map['role'] ?? 'assistant').toString(),
      message: (map['message'] ?? map['answer'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      confidence: (map['confidence'] as num?)?.toDouble(),
      citations: citations,
      conversational:
          map['conversational'] == true ||
          parsedData['conversational'] == true ||
          semantic?['route'] == 'conversation' ||
          answerStatus == 'conversation' ||
          conversationalIntents.contains(savedIntent),
      aiGenerated:
          (answerGenerator != null &&
              !answerGenerator.startsWith('deterministic')) ||
          parsedData['groq'] != null,
      clarification: clarificationMap == null
          ? null
          : InsuranceClarification(
              id: clarificationMap['id'].toString(),
              candidates: candidateRows
                  .map(
                    (candidate) => InsuranceClarificationCandidate(
                      id: candidate['candidate_id'].toString(),
                      canonicalName: candidate['canonical_name'].toString(),
                      entityType: candidate['entity_type'].toString(),
                      queryFragment: candidate['query_fragment'].toString(),
                      similarity:
                          (candidate['similarity_score'] as num?)?.toDouble() ??
                          0,
                    ),
                  )
                  .toList(),
            ),
      debugTrace: map['debug'] is Map
          ? Map<String, dynamic>.from(map['debug'] as Map)
          : null,
      recoveryDepth:
          (parsedData['recovery_depth'] as num?)?.toInt() ??
          (map['recovery_used'] == true ? 1 : 0),
      recoveryOfMessageId:
          (parsedData['recovery_of_message_id'] ??
                  map['recovery_of_message_id'])
              ?.toString(),
      answerStatus: answerStatus,
      evidenceChecked: evidenceChecked,
      answerGenerator: answerGenerator,
      answerCard: _answerCard(map['answer_card'] ?? parsedData['answer_card']),
    );
  }

  @override
  Future<bool> canManageDocuments() => remote.canManageDocuments();

  @override
  Future<List<InsuranceChatSession>> fetchSessions() async =>
      (await remote.fetchSessions())
          .map(
            (row) => InsuranceChatSession(
              id: row['id'].toString(),
              title: row['title'].toString(),
              updatedAt: DateTime.parse(row['updated_at'].toString()),
            ),
          )
          .toList();

  @override
  Future<List<Map<String, dynamic>>> fetchKnowledgeReadiness() =>
      remote.fetchKnowledgeReadiness();

  @override
  Future<List<InsuranceChatMessage>> fetchMessages(String sessionId) async {
    final messages = (await remote.fetchMessages(
      sessionId,
    )).map(messageFromMap).toList();
    messages.sort((left, right) {
      final chronological = left.createdAt.compareTo(right.createdAt);
      if (chronological != 0) return chronological;
      if (left.isUser != right.isUser) return left.isUser ? -1 : 1;
      return left.id.compareTo(right.id);
    });
    return messages;
  }

  @override
  Future<({String sessionId, InsuranceChatMessage message})> ask({
    required String question,
    required String branchName,
    String? sessionId,
    bool debug = false,
  }) async {
    final result = await remote.ask(
      question: question,
      branchName: branchName,
      sessionId: sessionId,
      debug: debug,
    );
    return (
      sessionId: result['session_id'].toString(),
      message: messageFromMap(result),
    );
  }

  @override
  Future<({String sessionId, InsuranceChatMessage message})>
  confirmClarification({
    required String clarificationId,
    required String candidateId,
    required String branchName,
  }) async {
    final result = await remote.confirmClarification(
      clarificationId: clarificationId,
      candidateId: candidateId,
      branchName: branchName,
    );
    return (
      sessionId: result['session_id'].toString(),
      message: messageFromMap(result),
    );
  }

  @override
  Future<void> submitFeedback(String messageId, int rating) =>
      remote.submitFeedback(messageId, rating);

  @override
  Future<InsuranceChatMessage?> recoverFromFeedback({
    required String messageId,
    required String reason,
    required String branchName,
  }) async {
    final result = await remote.recoverFromFeedback(
      messageId: messageId,
      reason: reason,
      branchName: branchName,
    );
    if (result['recovery_exhausted'] == true || result['answer'] == null) {
      return null;
    }
    return messageFromMap(result);
  }

  @override
  Future<String> createSourceUrl(InsuranceCitation citation) =>
      remote.createSourceUrl(
        citation.storageBucket,
        citation.storagePath,
        documentId: citation.documentId,
      );

  @override
  Future<List<InsuranceDocumentSummary>> fetchDocuments() async =>
      (await remote.fetchDocuments())
          .map(
            (row) => InsuranceDocumentSummary(
              id: row['id'].toString(),
              title: row['title'].toString(),
              fileName: row['original_file_name'].toString(),
              status: row['processing_status'].toString(),
              error: row['last_error']?.toString(),
              fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
              uploadedAt: DateTime.parse(row['uploaded_at'].toString()),
              validationStatus:
                  row['search_validation_status']?.toString() ?? 'pending',
              lifecycleStatus: row['lifecycle_status']?.toString() ?? 'current',
              chunkCount: (row['chunk_count'] as num?)?.toInt() ?? 0,
              embeddedCount: (row['embedded_count'] as num?)?.toInt() ?? 0,
              entityCount: (row['entity_count'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

  @override
  Future<List<Map<String, dynamic>>> inspectSearch(String query) =>
      remote.inspectSearch(query);

  @override
  Future<List<Map<String, dynamic>>> inspectSource(String documentId) =>
      remote.inspectSource(documentId);

  @override
  Future<void> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) => remote.uploadDocument(bytes: bytes, fileName: fileName, title: title);
}
