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

/// Philippine time (UTC+8) of a time from the server, whatever the computer's time zone.
DateTime ph(DateTime t) => t.toUtc().add(const Duration(hours: 8));

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 9:45 AM in Philippine time.
String clockPh(DateTime? t) => t == null ? '' : timeFmt(ph(t));

/// Sep 28, 9:15 AM in Philippine time.
String dateTimePh(DateTime? t) {
  if (t == null) return '';
  final p = ph(t);
  return '${_months[p.month - 1]} ${p.day}, ${timeFmt(p)}';
}

/// Money without the peso sign rounding issues: 35 -> 35.00
String money2(num v) => v.toStringAsFixed(2);

/// "Today", "Yesterday" or "Sep 28" (Philippine time).
String dayPh(DateTime? t) {
  if (t == null) return '';
  final p = ph(t);
  final now = ph(DateTime.now());
  final d0 = DateTime(p.year, p.month, p.day);
  final n0 = DateTime(now.year, now.month, now.day);
  final diff = n0.difference(d0).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_months[p.month - 1]} ${p.day}';
}
