import 'items_tracker_record.dart';

/// Fixed department routing for the Outlook message and its preview.
class ItemsTrackerEmailRecipients {
  final List<String> to;
  final List<String> cc;
  const ItemsTrackerEmailRecipients(this.to, this.cc);

  static ItemsTrackerEmailRecipients forRole(String role) =>
      switch (ItemsTrackerRoles.normalize(role)) {
        ItemsTrackerRoles.category => const ItemsTrackerEmailRecipients(
          ['doaa.hassan@alain-pharmacy.com', 'Saria.Bahaa@alain-pharmacy.com'],
          ['Inventory@alain-pharmacy.com', 'ahmad.alkouz@alain-pharmacy.com'],
        ),
        ItemsTrackerRoles.purchase => const ItemsTrackerEmailRecipients(
          ['a.altamimi@alain-pharmacy.com'],
          [
            'Inventory@alain-pharmacy.com',
            'ahmad.alkouz@alain-pharmacy.com',
            'a.bittar@alain-pharmacy.com',
          ],
        ),
        ItemsTrackerRoles.inventory => const ItemsTrackerEmailRecipients(
          ['Inventory@alain-pharmacy.com'],
          ['ahmad.alkouz@alain-pharmacy.com'],
        ),
        _ => throw ArgumentError.value(role, 'role', 'Unknown department'),
      };
}

class ItemsTrackerEmailProduct {
  final String id;
  final String name;
  final String reason;
  final String followUpRole;
  const ItemsTrackerEmailProduct({
    required this.id,
    required this.name,
    required this.reason,
    required this.followUpRole,
  });

  factory ItemsTrackerEmailProduct.fromRecord(ItemsTrackerRecord record) =>
      ItemsTrackerEmailProduct(
        id: record.id,
        name: record.itemName,
        reason: record.inventoryNote,
        followUpRole: record.followUpRole,
      );
}

class ItemsTrackerEmailDraft {
  final String id;
  final String status;
  final String scope;
  final String company;
  final String followUpRole;
  final List<ItemsTrackerEmailProduct> products;
  final DateTime? openedAt;
  final DateTime? sentAt;
  const ItemsTrackerEmailDraft({
    required this.id,
    required this.status,
    required this.scope,
    required this.company,
    required this.followUpRole,
    required this.products,
    this.openedAt,
    this.sentAt,
  });

  bool get isSent => status == 'sent';
  ItemsTrackerEmailRecipients get recipients =>
      ItemsTrackerEmailRecipients.forRole(followUpRole);
  String get title => scope == 'company' ? company : products.first.name;
  String get subject =>
      'Items Tracker - ${scope == 'company' ? 'Company' : 'Product'} - '
      '${title.length > 150 ? '${title.substring(0, 147)}...' : title}';
  String get body =>
      'Dear ${ItemsTrackerRoles.label(followUpRole)} Team,\n\n'
      '${scope == 'company' ? 'Company: $company\n' : ''}'
      'Please follow up on ${products.length == 1 ? 'the following product' : 'the following ${products.length} products'}:\n\n'
      '${products.map((product) => 'Product: ${product.name}\nReason: ${product.reason.trim().isEmpty ? 'No reason provided' : product.reason.trim()}').join('\n\n')}\n\n'
      'Thank you,\nInventory Team';

  Uri outlookUri({bool includeBody = true}) => Uri.parse(
    'mailto:${recipients.to.join(';')}'
    '?cc=${Uri.encodeComponent(recipients.cc.join(';'))}'
    '&subject=${Uri.encodeComponent(subject)}'
    '${includeBody ? '&body=${Uri.encodeComponent(body)}' : ''}',
  );

  factory ItemsTrackerEmailDraft.fromMap(Map<String, dynamic> map) =>
      ItemsTrackerEmailDraft(
        id: map['id'].toString(),
        status: map['status'].toString(),
        scope: map['scope'].toString(),
        company: (map['company'] ?? '').toString(),
        followUpRole: map['follow_up_role'].toString(),
        openedAt: DateTime.tryParse((map['opened_at'] ?? '').toString()),
        sentAt: DateTime.tryParse((map['sent_at'] ?? '').toString()),
        products: (map['products'] as List).map((value) {
          final product = Map<String, dynamic>.from(value as Map);
          return ItemsTrackerEmailProduct(
            id: product['id'].toString(),
            name: product['name'].toString(),
            reason: (product['reason'] ?? '').toString(),
            followUpRole: map['follow_up_role'].toString(),
          );
        }).toList(),
      );
}
