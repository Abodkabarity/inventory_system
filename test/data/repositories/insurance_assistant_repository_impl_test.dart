import 'package:daily_order/data/datasources/remote/insurance_assistant_remote_ds.dart';
import 'package:daily_order/data/repositories/insurance_assistant_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late InsuranceAssistantRepositoryImpl repository;

  setUp(() {
    repository = InsuranceAssistantRepositoryImpl(
      InsuranceAssistantRemoteDs(
        SupabaseClient('https://example.supabase.co', 'test-anon-key'),
      ),
    );
  });

  test('V45 is the default function and V44 remains the rollback endpoint', () {
    const configured = String.fromEnvironment(
      'INSURANCE_POLICY_FUNCTION',
      defaultValue: 'insurance-policy-simple-v45-deep-review-candidate',
    );
    expect(InsuranceAssistantRemoteDs.policyFunctionName, configured);
    expect(
      InsuranceAssistantRemoteDs.rollbackPolicyFunctionName,
      'insurance-policy-simple-v44-agentic-candidate',
    );
  });

  test('parses the complete V5 answer card and evidence metadata', () {
    final message = repository.messageFromMap({
      'message_id': 'message-1',
      'role': 'assistant',
      'answer': 'Legacy fallback text',
      'created_at': '2026-08-29T12:00:00Z',
      'answer_status': 'grounded',
      'evidence_checked': true,
      'answer_generator': 'together',
      'citations': [
        {
          'evidence_id': 'evidence-1',
          'chunk_id': 'chunk-1',
          'document_title': 'Policy A',
          'file_name': 'policy-a.pdf',
          'storage_bucket': 'insurance-documents',
          'storage_path': 'policy-a.pdf',
          'excerpt': 'Direct policy wording.',
          'page_from': 3,
          'support_level': 'gold_evidence',
        },
      ],
      'answer_card': {
        'version': '1',
        'verdict': 'conditional',
        'summary': 'Coverage is conditional.',
        'criteria': [
          {
            'label': 'Age requirement',
            'status': 'met',
            'detail': 'The patient is old enough.',
            'evidence_ids': ['evidence-1'],
          },
        ],
        'dose_schedule': {
          'dose': '75 mg',
          'route': 'SC',
          'maintenance': 'Every 4 weeks',
          'evidence_ids': ['evidence-1'],
        },
        'missing_information': ['Prior therapy history'],
        'next_action': 'Confirm previous treatment.',
        'claims': [
          {
            'id': 'claim-1',
            'text': 'The maintenance dose is every 4 weeks.',
            'polarity': 'affirmed',
            'certainty': 'direct',
            'evidence_ids': ['evidence-1'],
            'evidence_quote': 'Every 4 weeks thereafter.',
          },
        ],
        'presentation': {
          'answer_type': 'eligibility_comparison',
          'display_title': 'CGRP eligibility for Family Medicine',
          'display_verdict': 'Acute / Abortive only',
          'tone': 'positive',
          'complete': true,
          'explanation': 'Family Medicine is eligible only for acute therapy.',
          'comparison_rows': [
            {
              'label': 'Preventive CGRP',
              'status': 'not_eligible',
              'value': 'Not listed',
              'evidence_ids': ['evidence-1'],
            },
          ],
          'sections': [],
          'missing_information': [],
          'evidence_source_count': 1,
          'displayed_evidence_ids': ['evidence-1'],
        },
      },
    });

    expect(message.answerStatus, 'grounded');
    expect(message.evidenceChecked, isTrue);
    expect(message.answerGenerator, 'together');
    expect(message.aiGenerated, isTrue);
    expect(message.citations.single.resolvedEvidenceId, 'evidence-1');
    expect(message.citations.single.supportLevel, 'gold_evidence');
    expect(message.answerCard?.verdict, 'conditional');
    expect(message.answerCard?.criteria.single.status, 'met');
    expect(message.answerCard?.doseSchedule?.dose, '75 mg');
    expect(message.answerCard?.missingInformation, ['Prior therapy history']);
    expect(message.answerCard?.claims.single.evidenceIds, ['evidence-1']);
    expect(
      message.answerCard?.presentation?.displayVerdict,
      'Acute / Abortive only',
    );
    expect(
      message.answerCard?.presentation?.comparisonRows.single.status,
      'not_eligible',
    );
    expect(message.answerCard?.presentation?.evidenceSourceCount, 1);
  });

  test('reads saved V5 metadata and keeps legacy messages compatible', () {
    final saved = repository.messageFromMap({
      'id': 'saved-1',
      'role': 'assistant',
      'message': 'Saved structured answer',
      'created_at': '2026-08-29T12:00:00Z',
      'citations': [
        {
          'evidence_id': 'evidence-saved',
          'chunk_id': 'chunk-saved',
          'document_title': 'Saved policy',
          'file_name': 'saved.pdf',
          'storage_bucket': 'insurance-documents',
          'storage_path': 'saved.pdf',
          'excerpt': 'Saved evidence.',
        },
      ],
      'parsed_data': {
        'answer_status': 'grounded_extractive',
        'answer_generator': 'deterministic_extractive',
        'evidence_checked': true,
        'answer_card': {
          'version': '1',
          'verdict': 'informational',
          'summary': 'Saved summary',
          'criteria': [],
          'missing_information': [],
          'claims': [],
        },
      },
    });
    final legacy = repository.messageFromMap({
      'id': 'legacy-1',
      'role': 'assistant',
      'message': 'Legacy answer remains readable.',
      'created_at': '2026-08-29T12:00:00Z',
    });

    expect(saved.answerStatus, 'grounded_extractive');
    expect(saved.evidenceChecked, isTrue);
    expect(saved.aiGenerated, isFalse);
    expect(saved.answerCard?.summary, 'Saved summary');
    expect(legacy.answerCard, isNull);
    expect(legacy.answerStatus, 'legacy');
    expect(legacy.message, 'Legacy answer remains readable.');
  });
}
