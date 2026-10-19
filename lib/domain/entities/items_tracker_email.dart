import 'dart:convert';
import 'package:intl/intl.dart';
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
  final String code, company, supplier, category, status;
  final double? quantity, cost, total;
  final DateTime? escalatedDate;
  const ItemsTrackerEmailProduct({
    required this.id,
    required this.name,
    required this.reason,
    required this.followUpRole,
    this.code = '',
    this.company = '',
    this.supplier = '',
    this.category = '',
    this.status = '',
    this.quantity,
    this.cost,
    this.total,
    this.escalatedDate,
  });

  factory ItemsTrackerEmailProduct.fromRecord(ItemsTrackerRecord record) =>
      ItemsTrackerEmailProduct(
        id: record.id,
        name: record.itemName,
        reason: record.inventoryNote,
        followUpRole: record.followUpRole,
        code: record.itemCode,
        company: record.company,
        supplier: record.supplier,
        category: record.category,
        status: record.statusUpdatedTo,
        quantity: record.requiredQty,
        cost: record.unitCost,
        total: record.requiredValue,
        escalatedDate: record.escalatedDate,
      );

  static double? _number(dynamic value) {
    final parsed = num.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed.toDouble() : null;
  }

  factory ItemsTrackerEmailProduct.fromMap(
    Map<String, dynamic> map,
    String role,
  ) => ItemsTrackerEmailProduct(
    id: '${map['id']}',
    name: '${map['name'] ?? ''}',
    reason: '${map['reason'] ?? ''}',
    followUpRole: role,
    code: '${map['code'] ?? ''}',
    company: '${map['company'] ?? ''}',
    supplier: '${map['supplier'] ?? ''}',
    category: '${map['category'] ?? ''}',
    status: '${map['status'] ?? ''}',
    quantity: _number(map['qty']),
    cost: _number(map['cost']),
    total: _number(map['total']),
    escalatedDate: DateTime.tryParse('${map['escalated_date'] ?? ''}'),
  );

  String get qtyLabel =>
      quantity == null ? '—' : NumberFormat('#,##0.##', 'en').format(quantity);
  static String money(double? value) =>
      value == null ? '—' : NumberFormat('#,##0.00', 'en').format(value);
  List<String> get cells => [
    [
      name,
      if (code.isNotEmpty) 'Code: $code',
      if (company.isNotEmpty) 'Company: $company',
      if (supplier.isNotEmpty) 'Supplier: $supplier',
      if (category.isNotEmpty) 'Category: $category',
      if (escalatedDate != null)
        'Date: ${DateFormat('dd/MM/yyyy').format(escalatedDate!)}',
    ].join('\n'),
    qtyLabel,
    money(cost),
    money(total),
    status.isEmpty ? '—' : status,
    reason.trim().isEmpty ? 'No reason provided' : reason.trim(),
  ];
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
  String get title => scope == 'company'
      ? company
      : products.length == 1
      ? products.first.name
      : '${products.length} products · ${products.take(3).map((p) => p.name).join(', ')}';
  String get subject =>
      'Items Tracker - ${ItemsTrackerRoles.label(followUpRole)} - '
      '${title.length > 150 ? '${title.substring(0, 147)}...' : title}';

  static const columns = [
    'Product / company',
    'Qty',
    'Cost (AED)',
    'Total (AED)',
    'Status',
    'Reason',
  ];
  double get knownTotal => products.fold(0, (sum, p) => sum + (p.total ?? 0));
  bool get hasCompleteTotal => products.every((p) => p.total != null);
  String get totalLabel => products.every((p) => p.total == null)
      ? 'Total: —'
      : '${hasCompleteTotal ? 'Total' : 'Known total'}: AED ${ItemsTrackerEmailProduct.money(knownTotal)}';
  String get body =>
      'Dear ${ItemsTrackerRoles.label(followUpRole)} Team,\n\n'
      '${scope == 'company' ? 'Company: $company\n' : ''}'
      'Please follow up on ${products.length == 1 ? 'the following product' : 'the following ${products.length} products'}:\n\n'
      '${products.map((p) => 'Product: ${p.name}\nCode: ${p.code}\nCompany: ${p.company}\nSupplier: ${p.supplier}\nQty: ${p.qtyLabel}\nCost (AED): ${ItemsTrackerEmailProduct.money(p.cost)}\nTotal (AED): ${ItemsTrackerEmailProduct.money(p.total)}\nStatus: ${p.status}\nReason: ${p.reason.trim().isEmpty ? 'No reason provided' : p.reason.trim()}').join('\n\n')}\n\n'
      '$totalLabel${hasCompleteTotal ? '' : ' (some costs are unavailable)'}\n\n'
      'Thank you,\nInventory Team';

  /// Inline styles and a real table survive Outlook's limited HTML renderer.
  String get htmlBody {
    String escape(String text) =>
        const HtmlEscape().convert(text).replaceAll('\n', '<br>');
    final out = StringBuffer(
      '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Arial,sans-serif;color:#19344a;font-size:14px">',
    );
    out.write(
      '<table role="presentation" width="100%" cellpadding="20" cellspacing="0"><tr><td bgcolor="#122d40" style="color:white"><h2 style="margin:0">Items Tracker</h2><p style="margin-bottom:0">${escape(title)}</p></td></tr></table>',
    );
    out.write(
      '<p>Dear ${escape(ItemsTrackerRoles.label(followUpRole))} Team,</p><p>Please follow up on the following ${products.length} product${products.length == 1 ? '' : 's'}:</p>',
    );
    out.write(
      '<table width="100%" cellpadding="10" cellspacing="0" style="border-collapse:collapse;font-size:12px"><thead><tr>',
    );
    for (final column in columns) {
      out.write(
        '<th align="left" bgcolor="#eaf5fb" style="border:1px solid #dce7ef">${escape(column)}</th>',
      );
    }
    out.write('</tr></thead><tbody>');
    for (var i = 0; i < products.length; i++) {
      out.write('<tr bgcolor="${i.isEven ? '#ffffff' : '#f6fafc'}">');
      for (final cell in products[i].cells) {
        out.write(
          '<td valign="top" style="border:1px solid #dce7ef;line-height:1.6;overflow-wrap:anywhere">${escape(cell)}</td>',
        );
      }
      out.write('</tr>');
    }
    out.write(
      '</tbody></table><p><strong>${escape(totalLabel)}</strong>${hasCompleteTotal ? '' : ' · Some costs are unavailable.'}</p><p>Thank you,<br>Inventory Team</p></body></html>',
    );
    return out.toString();
  }

  /// X-Unsent opens the downloaded message as a compose draft in desktop Outlook.
  String get eml {
    final boundary =
        'tracker_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
    String encoded(String value) {
      final raw = base64.encode(utf8.encode(value));
      return [
        for (var i = 0; i < raw.length; i += 76)
          raw.substring(i, i + 76 > raw.length ? raw.length : i + 76),
      ].join('\r\n');
    }

    final words = <String>[];
    var current = '';
    for (final rune in subject.runes) {
      final char = String.fromCharCode(rune);
      if (utf8.encode(current + char).length > 36) {
        words.add('=?UTF-8?B?${base64.encode(utf8.encode(current))}?=');
        current = '';
      }
      current += char;
    }
    if (current.isNotEmpty) {
      words.add('=?UTF-8?B?${base64.encode(utf8.encode(current))}?=');
    }
    return [
      'To: ${recipients.to.join(', ')}',
      'Cc: ${recipients.cc.join(', ')}',
      'Subject: ${words.join('\r\n ')}',
      'MIME-Version: 1.0',
      'X-Unsent: 1',
      'Message-ID: <$boundary@items-tracker.invalid>',
      'Content-Type: multipart/alternative; boundary="$boundary"',
      '',
      '--$boundary',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: base64',
      '',
      encoded(body),
      '--$boundary',
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: base64',
      '',
      encoded(htmlBody),
      '--$boundary--',
      '',
    ].join('\r\n');
  }

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
          return ItemsTrackerEmailProduct.fromMap(
            product,
            map['follow_up_role'].toString(),
          );
        }).toList(),
      );
}
