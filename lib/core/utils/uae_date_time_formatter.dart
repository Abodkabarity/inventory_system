class UaeDateTimeFormatter {
  static const Duration _uaeOffset = Duration(hours: 4);

  static DateTime toUae(DateTime value) {
    if (value.isUtc) {
      return value.add(_uaeOffset);
    }

    return value;
  }

  static String yMdHm(DateTime? value) {
    if (value == null) return '-';

    final uae = toUae(value);
    String two(int v) => v.toString().padLeft(2, '0');

    return '${uae.year.toString().padLeft(4, '0')}-'
        '${two(uae.month)}-'
        '${two(uae.day)} '
        '${two(uae.hour)}:'
        '${two(uae.minute)}';
  }
}
