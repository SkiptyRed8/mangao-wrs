/// Money, phone numbers and times the way the wireframes show them.

/// ₱1,310.00
String peso(num v) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(2).split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '${neg ? '-' : ''}₱$b.${parts[1]}';
}

/// 0917 200 1111
String phoneFmt(String p) {
  final d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 11) return '${d.substring(0, 4)} ${d.substring(4, 7)} ${d.substring(7)}';
  return p;
}

/// 9:45 AM
String timeFmt(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "3 gallons" / "1 gallon"
String gallons(int n) => n == 1 ? '1 gallon' : '$n gallons';
