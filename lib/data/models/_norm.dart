String normCode(dynamic v) {
  if (v == null) return '';
  var s = v.toString().trim().replaceAll(' ', '');
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}

num parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}
