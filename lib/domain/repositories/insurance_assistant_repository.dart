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
  });
  Future<({String sessionId, InsuranceChatMessage message})>
  confirmClarification({
    required String clarificationId,
    required String candidateId,
    required String branchName,
  });
  Future<void> submitFeedback(String messageId, int rating);
  Future<String> createSourceUrl(InsuranceCitation citation);
  Future<List<InsuranceDocumentSummary>> fetchDocuments();
  Future<List<Map<String, dynamic>>> inspectSearch(String query);
  Future<List<Map<String, dynamic>>> inspectSource(String documentId);
  Future<void> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String title,
  });
}
