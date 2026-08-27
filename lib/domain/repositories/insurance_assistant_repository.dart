import 'dart:typed_data';

import '../entities/insurance_assistant_models.dart';

abstract class InsuranceAssistantRepository {
  Future<bool> canManageDocuments();
  Future<List<InsuranceChatSession>> fetchSessions();
  Future<List<InsuranceChatMessage>> fetchMessages(String sessionId);
  Future<({String sessionId, InsuranceChatMessage message})> ask({
    required String question,
    required String branchName,
    String? sessionId,
    bool debug = false,
  });
  Future<({String sessionId, InsuranceChatMessage message})>
  confirmClarification({
    required String clarificationId,
    required String candidateId,
    required String branchName,
  });
  Future<void> submitFeedback(String messageId, int rating);
  Future<InsuranceChatMessage?> recoverFromFeedback({
    required String messageId,
    required String reason,
    required String branchName,
  });
  Future<String> createSourceUrl(InsuranceCitation citation);
  Future<List<InsuranceDocumentSummary>> fetchDocuments();
  Future<List<Map<String, dynamic>>> fetchKnowledgeReadiness();
  Future<List<Map<String, dynamic>>> inspectSearch(String query);
  Future<List<Map<String, dynamic>>> inspectSource(String documentId);
  Future<void> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String title,
  });
}
