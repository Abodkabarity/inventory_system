import 'dart:typed_data';

import '../../domain/entities/insurance_assistant_models.dart';
import '../../domain/repositories/insurance_assistant_repository.dart';
import '../datasources/remote/insurance_assistant_remote_ds.dart';

class InsuranceAssistantRepositoryImpl implements InsuranceAssistantRepository {
  final InsuranceAssistantRemoteDs remote;

  InsuranceAssistantRepositoryImpl(this.remote);

  InsuranceCitation _citation(Map<String, dynamic> map) => InsuranceCitation(
    chunkId: (map['chunk_id'] ?? '').toString(),
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

  InsuranceChatMessage _message(Map<String, dynamic> map) {
    final parsedData = map['parsed_data'] is Map
        ? Map<String, dynamic>.from(map['parsed_data'] as Map)
        : const <String, dynamic>{};
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
    return InsuranceChatMessage(
      id: (map['id'] ?? map['message_id'] ?? '').toString(),
      role: (map['role'] ?? 'assistant').toString(),
      message: (map['message'] ?? map['answer'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      confidence: (map['confidence'] as num?)?.toDouble(),
      citations: List<Map<String, dynamic>>.from(
        map['citations'] ?? const [],
      ).map(_citation).toList(),
      conversational:
          map['conversational'] == true ||
          parsedData['conversational'] == true ||
          conversationalIntents.contains(savedIntent),
      aiGenerated:
          map['answer_generator'] == 'groq' || parsedData['groq'] != null,
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
    )).map(_message).toList();
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
      message: _message(result),
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
      message: _message(result),
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
    return _message(result);
  }

  @override
  Future<String> createSourceUrl(InsuranceCitation citation) =>
      remote.createSourceUrl(citation.storageBucket, citation.storagePath);

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
