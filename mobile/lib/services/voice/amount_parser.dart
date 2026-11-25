/// Parses spoken money amounts in English and Bengali, e.g.
/// "70 taka", "seventy taka", "one hundred and fifty", "সত্তর টাকা",
/// "একশ পঞ্চাশ টাকা", "৭০ টাকা", "1,500".
library;

import 'command_parser.dart' show normalizeSpeech;

const _enUnits = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40,
  'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90, 'a': 1,
};
const _enScales = {'hundred': 100, 'thousand': 1000, 'lakh': 100000, 'lac': 100000, 'million': 1000000};

/// Bengali number words 1–99 are irregular, so each has an entry.
const _bnWords = [
  'এক', 'দুই', 'তিন', 'চার', 'পাঁচ', 'ছয়', 'সাত', 'আট', 'নয়', 'দশ', //
  'এগারো', 'বারো', 'তেরো', 'চৌদ্দ', 'পনেরো', 'ষোলো', 'সতেরো', 'আঠারো', 'উনিশ', 'বিশ',
  'একুশ', 'বাইশ', 'তেইশ', 'চব্বিশ', 'পঁচিশ', 'ছাব্বিশ', 'সাতাশ', 'আঠাশ', 'উনত্রিশ', 'ত্রিশ',
  'একত্রিশ', 'বত্রিশ', 'তেত্রিশ', 'চৌত্রিশ', 'পঁয়ত্রিশ', 'ছত্রিশ', 'সাঁইত্রিশ', 'আটত্রিশ', 'উনচল্লিশ', 'চল্লিশ',
  'একচল্লিশ', 'বিয়াল্লিশ', 'তেতাল্লিশ', 'চুয়াল্লিশ', 'পঁয়তাল্লিশ', 'ছেচল্লিশ', 'সাতচল্লিশ', 'আটচল্লিশ', 'উনপঞ্চাশ', 'পঞ্চাশ',
  'একান্ন', 'বাহান্ন', 'তিপ্পান্ন', 'চুয়ান্ন', 'পঞ্চান্ন', 'ছাপ্পান্ন', 'সাতান্ন', 'আটান্ন', 'উনষাট', 'ষাট',
  'একষট্টি', 'বাষট্টি', 'তেষট্টি', 'চৌষট্টি', 'পঁয়ষট্টি', 'ছেষট্টি', 'সাতষট্টি', 'আটষট্টি', 'উনসত্তর', 'সত্তর',
  'একাত্তর', 'বাহাত্তর', 'তিয়াত্তর', 'চুয়াত্তর', 'পঁচাত্তর', 'ছিয়াত্তর', 'সাতাত্তর', 'আটাত্তর', 'উনআশি', 'আশি',
  'একাশি', 'বিরাশি', 'তিরাশি', 'চুরাশি', 'পঁচাশি', 'ছিয়াশি', 'সাতাশি', 'অষ্টআশি', 'উননব্বই', 'নব্বই',
  'একানব্বই', 'বিরানব্বই', 'তিরানব্বই', 'চুরানব্বই', 'পঁচানব্বই', 'ছিয়ানব্বই', 'সাতানব্বই', 'আটানব্বই', 'নিরানব্বই',
];

final Map<String, int> _bnMap = () {
  final m = <String, int>{};
  for (var i = 0; i < _bnWords.length; i++) {
    m[normalizeSpeech(_bnWords[i])] = i + 1;
  }
  // Common variants.
  m.addAll({'দু': 2, 'দুটো': 2, 'ছ': 6, 'শূন্য': 0, 'শুন্য': 0, 'ষোল': 16, 'এগার': 11, 'বার': 12, 'তের': 13, 'পনের': 15, 'সতের': 17, 'আঠার': 18, 'আটাশি': 88});
  return {for (final e in m.entries) normalizeSpeech(e.key): e.value};
}();

const _bnScales = {'শ': 100, 'শো': 100, 'শত': 100, 'হাজার': 1000, 'লাখ': 100000, 'লক্ষ': 100000};

String _bnDigitsToAscii(String s) {
  const bn = '০১২৩৪৫৬৭৮৯';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final i = bn.indexOf(String.fromCharCode(ch));
    b.write(i >= 0 ? '$i' : String.fromCharCode(ch));
  }
  return b.toString();
}

/// Splits Bengali tokens like "একশ"/"দুইশো"/"পাঁচশত" into [number, scale].
List<String> _splitBnToken(String t) {
  for (final suf in ['শত', 'শো', 'শ']) {
    if (t.length > suf.length && t.endsWith(suf)) {
      final head = t.substring(0, t.length - suf.length);
      if (_bnMap.containsKey(head) || RegExp(r'^\d+$').hasMatch(head)) return [head, suf];
    }
  }
  return [t];
}

/// Returns the amount in Taka, or null if no amount is found.
int? parseAmount(String input) {
  var text = normalizeSpeech(_bnDigitsToAscii(input));
  // "1,500" / "1 500" → "1500"; drop currency words.
  text = text.replaceAllMapped(RegExp(r'(\d)[, ](?=\d{3}\b)'), (m) => m[1]!);
  text = text.replaceAll(RegExp(r'\b(taka|tk|takas|bdt|rupees?)\b'), ' ').replaceAll('টাকা', ' ').replaceAll('৳', ' ');

  final tokens = <String>[];
  for (final t in text.split(RegExp(r'\s+'))) {
    if (t.isEmpty) continue;
    tokens.addAll(_splitBnToken(t));
  }

  int total = 0, current = 0;
  var found = false;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i].trim();
    if (t == 'and' || t == 'এবং' || t == 'ও') continue;
    if (t == 'a') {
      // "a" counts as 1 only in "a hundred" / "a thousand".
      final next = i + 1 < tokens.length ? tokens[i + 1] : '';
      if (_enScales.containsKey(next)) {
        current += 1;
        found = true;
      }
      continue;
    }
    final digits = RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
    final unit = digits ?? _enUnits[t] ?? _bnMap[t];
    final scale = _enScales[t] ?? _bnScales[t];
    if (unit != null) {
      current += unit;
      found = true;
    } else if (scale != null) {
      found = true;
      if (current == 0) current = 1;
      if (scale == 100) {
        current *= 100;
      } else {
        total += current * scale;
        current = 0;
      }
    } else if (found) {
      break; // stop at the first non-number word after the amount
    }
  }
  if (!found) return null;
  final value = total + current;
  return value >= 0 && value <= 10000000 ? value : null;
}
