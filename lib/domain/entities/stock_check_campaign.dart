/// Lightweight campaign totals. Product responses are loaded separately.
class StockCheckCampaign {
  final Map<String, dynamic> data;
  StockCheckCampaign(Map<String, dynamic> data) : data = Map.unmodifiable(data);

  String _text(String key) => (data[key] ?? '').toString().trim();
  int _int(String key) => num.tryParse('${data[key]}')?.toInt() ?? 0;
  DateTime? _date(String key) => DateTime.tryParse(_text(key));
  String get id => _text('batch_id');
  String get title => _text('title');
  String get source => _text('source');
  String get kind => _text('check_kind') == 'kpi' ? 'kpi' : 'regular';
  String get senderId => _text('sender_user_id');
  String get senderName => _text('sender_name');
  String get senderLabel =>
      senderName.isEmpty ? 'Sender not recorded' : senderName;
  int? get year => data['kpi_year'] == null ? null : _int('kpi_year');
  int? get quarter => data['kpi_quarter'] == null ? null : _int('kpi_quarter');
  String get period =>
      year == null || quarter == null ? '' : '$year · Q$quarter';
  DateTime? get sentAt => _date('sent_at');
  DateTime? get expiresAt => _date('expires_at');
  int get total => _int('total');
  int get submitted => _int('submitted');
  int get pending => total - submitted;
  int get branches => _int('branches');
  int get products => _int('products');
  int get counted => _int('counted');
  int get correct => _int('correct');
  double? get accuracy => counted == 0 ? null : correct * 100 / counted;
  double get completion => total == 0 ? 0 : submitted / total;

  bool matches({
    required String kind,
    String sender = '',
    String search = '',
    String status = 'all',
    DateTime? now,
  }) {
    if (this.kind != kind || (sender.isNotEmpty && senderId != sender)) {
      return false;
    }
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty &&
        !'$title $senderName $period'.toLowerCase().contains(needle)) {
      return false;
    }
    return switch (status) {
      'pending' =>
        pending > 0 &&
            (expiresAt == null || !expiresAt!.isBefore(now ?? DateTime.now())),
      'completed' => pending == 0,
      'overdue' =>
        pending > 0 &&
            expiresAt != null &&
            expiresAt!.isBefore(now ?? DateTime.now()),
      _ => true,
    };
  }
}
