import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemsTrackerRoles', () {
    test(
      'routes medicine to purchase and every other category to category',
      () {
        expect(
          ItemsTrackerRoles.defaultFollowUpForCategory('  medicine  '),
          ItemsTrackerRoles.purchase,
        );
        expect(
          ItemsTrackerRoles.defaultFollowUpForCategory('COSMETICS'),
          ItemsTrackerRoles.category,
        );
        expect(
          ItemsTrackerRoles.defaultFollowUpForCategory(''),
          ItemsTrackerRoles.category,
        );
      },
    );

    test('normalizes role labels and preserves an unknown display label', () {
      expect(ItemsTrackerRoles.label(' INVENTORY '), 'Inventory');
      expect(ItemsTrackerRoles.label('Purchase'), 'Purchase');
      expect(ItemsTrackerRoles.label(' category '), 'Category');
      expect(ItemsTrackerRoles.label('Auditor'), 'Auditor');
      expect(ItemsTrackerRoles.label('  '), 'Unknown');
    });

    test('exposes the expected role capabilities', () {
      expect(ItemsTrackerRoles.isAllowed(' INVENTORY '), isTrue);
      expect(ItemsTrackerRoles.isAllowed('purchase'), isTrue);
      expect(ItemsTrackerRoles.isAllowed('Category'), isTrue);
      expect(ItemsTrackerRoles.isAllowed('store'), isFalse);

      expect(ItemsTrackerRoles.canEditInventoryFields('inventory'), isTrue);
      expect(ItemsTrackerRoles.canEditInventoryFields('purchase'), isFalse);
      expect(ItemsTrackerRoles.canEditInventoryFields('category'), isFalse);

      expect(ItemsTrackerRoles.canComment('inventory'), isTrue);
      expect(ItemsTrackerRoles.canComment(' PURCHASE '), isTrue);
      expect(ItemsTrackerRoles.canComment('category'), isTrue);
      expect(ItemsTrackerRoles.canComment('store'), isFalse);
    });
  });

  group('calculateItemsTrackerValue', () {
    test('multiplies and rounds the result to two decimal places', () {
      expect(calculateItemsTrackerValue(12.5, 4), 50);
      expect(calculateItemsTrackerValue(10.129, 3), 30.39);
      expect(calculateItemsTrackerValue(3.456, 2), 6.91);
    });

    test('handles null and invalid quantities without inventing a value', () {
      expect(calculateItemsTrackerValue(null, 2), isNull);
      expect(calculateItemsTrackerValue(12, null), isNull);
      expect(calculateItemsTrackerValue(-1, 2), isNull);
      expect(calculateItemsTrackerValue(12, 0), isNull);
      expect(calculateItemsTrackerValue(12, -1), isNull);
      expect(calculateItemsTrackerValue(0, 3), 0);
    });
  });

  group('ItemsTrackerCaseStatuses', () {
    test('offers only Pending and Done tracker states', () {
      expect(ItemsTrackerCaseStatuses.values, const ['pending', 'done']);
      expect(ItemsTrackerCaseStatuses.label('pending'), 'Pending');
      expect(ItemsTrackerCaseStatuses.label('done'), 'Done');
    });
  });

  group('ItemsTrackerRecord', () {
    test('maps Supabase values and calculates a missing required value', () {
      final record = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'retail_snapshot': '18.75',
        'unit_cost_snapshot': '12.50',
        'required_qty': '4',
        'required_value': null,
        'comment_count': '3',
        'row_version': 7,
        'case_status': 'DONE',
        'follow_up_role': 'PURCHASE',
      });

      expect(record.id, 'tracker-1');
      expect(record.escalatedDate, DateTime(2026, 8, 5));
      expect(record.itemCode, '16-01-00001');
      expect(record.itemName, 'Test medicine');
      expect(record.category, 'MEDICINE');
      expect(record.retailSnapshot, 18.75);
      expect(record.unitCost, 12.5);
      expect(record.requiredQty, 4);
      expect(record.requiredValue, 50);
      expect(record.followUpRole, ItemsTrackerRoles.purchase);
      expect(record.caseStatus, ItemsTrackerCaseStatuses.done);
      expect(record.commentCount, 3);
      expect(record.rowVersion, 7);
      expect(record.createdAt, DateTime.parse('2026-08-05T08:30:00Z'));
      expect(record.updatedAt, DateTime.parse('2026-08-05T09:45:00Z'));
    });

    test('canAct requires the current follow-up role and normalizes input', () {
      final record = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'follow_up_role': 'purchase',
      });

      expect(record.canAct(' PURCHASE '), isTrue);
      expect(record.canAct('inventory'), isFalse);
      expect(record.canAct('category'), isFalse);
    });

    test('displayed activity uses the latest server-selected activity', () {
      final record = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'latest_activity_type': 'action',
        'latest_activity': 'Supplier confirmed replacement',
        'latest_activity_date': '2026-08-07',
        'latest_activity_by_role': 'purchase',
        'latest_activity_by_name': 'Dr. Ahmad Alkouz',
        'latest_activity_attachment_id': 'attachment-7',
        'latest_activity_attachment_path': 'tracker-1/user-1/quote.pdf',
        'latest_activity_attachment_name': 'quote.pdf',
        'latest_activity_attachment_mime_type': 'application/pdf',
        'latest_activity_attachment_size': 4096,
        'last_action_body': 'Supplier confirmed replacement',
        'last_action_date': '2026-08-07',
        'last_action_by_role': 'purchase',
        'last_follow_up_body': 'Sent to Purchase',
        'last_follow_up_date': '2026-08-06',
        'last_follow_up_to_role': 'purchase',
      });

      expect(record.displayedLastActivity, 'Supplier confirmed replacement');
      expect(record.displayedLastActivityDate, DateTime(2026, 8, 7));
      expect(record.displayedLastActivityRole, 'purchase');
      expect(record.displayedLastActivityByName, 'Dr. Ahmad Alkouz');
      expect(record.displayedLastActivityType, 'action');
      expect(record.displayedLastActivityHasAttachment, isTrue);
      expect(record.latestActivityAttachmentName, 'quote.pdf');
    });

    test('newer follow-up is displayed even when an older action exists', () {
      final followUpRecord = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'latest_activity_type': 'follow_up',
        'latest_activity': 'Assigned to Category',
        'latest_activity_date': '2026-08-08',
        'latest_activity_by_role': 'inventory',
        'last_action_body': 'Older supplier call',
        'last_action_date': '2026-08-07',
        'last_follow_up_body': 'Assigned to Category',
        'last_follow_up_date': '2026-08-08',
        'last_follow_up_to_role': 'category',
      });

      expect(followUpRecord.displayedLastActivity, 'Assigned to Category');
      expect(followUpRecord.displayedLastActivityDate, DateTime(2026, 8, 8));
      expect(followUpRecord.displayedLastActivityRole, 'inventory');
      expect(followUpRecord.displayedLastActivityType, 'follow_up');

      final latestRecord = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'latest_activity_body': 'Initial escalation',
        'latest_activity_date': '2026-08-05',
        'latest_activity_by_role': 'inventory',
      });

      expect(latestRecord.displayedLastActivity, 'Initial escalation');
      expect(latestRecord.displayedLastActivityDate, DateTime(2026, 8, 5));
      expect(latestRecord.displayedLastActivityRole, 'inventory');
    });

    test('maps a secure timeline attachment', () {
      final entry = ItemsTrackerTimelineEntry.fromMap({
        'id': 91,
        'entry_type': 'event',
        'event_type': 'file_uploaded',
        'body': 'Uploaded file: quotation.pdf',
        'created_at': '2026-08-10T08:30:00Z',
        'actor_role': 'purchase',
        'actor_name': 'Dr. Ahmad Alkouz',
        'attachment_id': 'attachment-1',
        'storage_path': 'tracker-1/user-1/file.pdf',
        'file_name': 'quotation.pdf',
        'mime_type': 'application/pdf',
        'file_size': '2048',
      });

      expect(entry.hasAttachment, isTrue);
      expect(entry.isImageAttachment, isFalse);
      expect(entry.fileName, 'quotation.pdf');
      expect(entry.fileSize, 2048);
      expect(entry.actorName, 'Dr. Ahmad Alkouz');
    });

    test('maps the item_tracker_grid view aliases', () {
      final record = ItemsTrackerRecord.fromMap({
        ..._baseRecordMap(),
        'last_action': 'Purchase confirmed delivery',
        'last_action_date': '2026-08-08',
        'last_action_by_role': 'purchase',
        'last_follow_up_note': 'Assigned to Purchase',
        'last_follow_up_role': 'purchase',
        'latest_activity': 'Follow-up: category -> purchase',
        'latest_activity_added_at': '2026-08-08T09:00:00Z',
        'last_comment': 'Please confirm the ETA',
        'comment_by_role': 'inventory',
        'comment_by_name': 'Dr. Ahmad Alkouz',
        'last_comment_at': '2026-08-08T09:10:00Z',
      });

      expect(record.lastActionBody, 'Purchase confirmed delivery');
      expect(record.lastFollowUpBody, 'Assigned to Purchase');
      expect(record.lastFollowUpToRole, 'purchase');
      expect(record.latestActivityBody, 'Follow-up: category -> purchase');
      expect(record.latestComment, 'Please confirm the ETA');
      expect(record.commentByRole, 'inventory');
      expect(record.commentByName, 'Dr. Ahmad Alkouz');
      expect(record.latestCommentAt, DateTime.parse('2026-08-08T09:10:00Z'));
    });
  });
}

Map<String, dynamic> _baseRecordMap() {
  return {
    'id': 'tracker-1',
    'escalated_date': '2026-08-05',
    'item_code': '16-01-00001',
    'item_name': 'Test medicine',
    'category': 'MEDICINE',
    'supplier': 'Test supplier',
    'company': 'Test company',
    'source_item_status': 'NORMAL PURCHASE',
    'inventory_note': 'Expiry risk',
    'required_qty': 2,
    'status_updated_to': 'PR',
    'follow_up_role': 'purchase',
    'case_status': 'pending',
    'created_at': '2026-08-05T08:30:00Z',
    'updated_at': '2026-08-05T09:45:00Z',
  };
}
