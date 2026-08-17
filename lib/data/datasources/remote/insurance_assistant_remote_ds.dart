import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

class InsuranceAssistantRemoteDs {
  final SupabaseClient client;

  InsuranceAssistantRemoteDs(this.client);

  Future<bool> canManageDocuments() async {
    final result = await client.rpc('is_insurance_knowledge_admin');
    return result == true;
  }

  Future<List<Map<String, dynamic>>> fetchSessions() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('insurance_chat_sessions')
            .select('id,title,updated_at')
            .order('updated_at', ascending: false)
            .limit(40),
      );

  Future<List<Map<String, dynamic>>> fetchMessages(String sessionId) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('insurance_chat_messages')
            .select(
              'id,role,message,created_at,confidence,citations,parsed_data',
            )
            .eq('session_id', sessionId)
            .order('created_at')
            // UUIDs are random and several legacy rows can share the same
            // timestamp. Keep the user's question before the assistant answer
            // when that happens.
            .order('role', ascending: false),
      );

  Future<Map<String, dynamic>> ask({
    required String question,
    required String branchName,
    String? sessionId,
  }) async {
    return _invokeAssistant({
      'message': question,
      'branch_name': branchName,
      if (sessionId != null) 'session_id': sessionId,
    });
  }

  Future<Map<String, dynamic>> confirmClarification({
    required String clarificationId,
    required String candidateId,
    required String branchName,
  }) => _invokeAssistant({
    'clarification_id': clarificationId,
    'candidate_id': candidateId,
    'branch_name': branchName,
  });

  Future<Map<String, dynamic>> _invokeAssistant(
    Map<String, dynamic> body,
  ) async {
    final localUri = SupabaseConfig.localInsuranceAssistantUri;
    if (localUri != null) return _invokeLocalAssistant(localUri, body);
    final response = await client.functions.invoke(
      'insurance-assistant',
      body: body,
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  Future<Map<String, dynamic>> _invokeLocalAssistant(
    Uri endpoint,
    Map<String, dynamic> body,
  ) async {
    final accessToken = client.auth.currentSession?.accessToken;
    if (accessToken == null) throw Exception('Authentication is required.');
    try {
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
              'apikey': SupabaseConfig.anonKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded['error'] ??
              'Local assistant returned HTTP ${response.statusCode}.',
        );
      }
      if (decoded['error'] != null) throw Exception(decoded['error']);
      return decoded;
    } on FormatException {
      throw Exception(
        'Local assistant returned an invalid response. Check the local Edge Function terminal.',
      );
    } on http.ClientException {
      throw Exception(
        'Cannot reach the local assistant. Start the local Edge Function and retry.',
      );
    } on TimeoutException {
      throw Exception(
        'The local assistant timed out. Verify Ollama is running and the selected model is loaded.',
      );
    }
  }

  Future<void> submitFeedback(String messageId, int rating) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Authentication required.');
    await client.from('insurance_feedback').upsert({
      'message_id': messageId,
      'user_id': userId,
      'rating': rating,
    }, onConflict: 'message_id,user_id');
  }

  Future<String> createSourceUrl(String bucket, String path) =>
      client.storage.from(bucket).createSignedUrl(path, 300);

  Future<List<Map<String, dynamic>>> fetchDocuments() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('insurance_document_health_v1'),
      );

  Future<List<Map<String, dynamic>>> inspectSearch(String query) async =>
      List<Map<String, dynamic>>.from(
        await client.rpc(
          'inspect_insurance_search_v1',
          params: {'p_query': query},
        ),
      );

  Future<List<Map<String, dynamic>>> inspectSource(String documentId) async =>
      List<Map<String, dynamic>>.from(
        await client.rpc(
          'inspect_insurance_source_v1',
          params: {'p_document_id': documentId},
        ),
      );

  Future<void> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {
    final extension = fileName.split('.').last.toLowerCase();
    const mimeTypes = {
      'pdf': 'application/pdf',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
    if (!mimeTypes.containsKey(extension))
      throw Exception('Only PDF, DOCX, and XLSX files are supported.');
    final checksum = sha256.convert(bytes).toString();
    final existing = await client
        .from('insurance_documents')
        .select('id')
        .eq('checksum', checksum)
        .maybeSingle();
    if (existing != null)
      throw Exception('This exact document is already in the knowledge base.');
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    final storagePath = '${checksum.substring(0, 12)}/$safeName';
    await client.storage
        .from('insurance-documents')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeTypes[extension],
            upsert: false,
          ),
        );
    try {
      final row = await client
          .from('insurance_documents')
          .insert({
            'file_name': safeName,
            'original_file_name': fileName,
            'storage_path': storagePath,
            'mime_type': mimeTypes[extension],
            'file_extension': extension,
            'file_size': bytes.length,
            'title': title,
            'checksum': checksum,
            'processing_status': 'queued',
          })
          .select('id')
          .single();
      await client.from('insurance_ingestion_jobs').insert({
        'document_id': row['id'],
      });
    } catch (_) {
      await client.storage.from('insurance-documents').remove([storagePath]);
      rethrow;
    }
  }
}
