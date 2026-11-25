/// Voice command parsing for English and Bengali.
library;

enum VoiceCommand { start, scan, scanNext, scanMore, stop, finish, total, undo, repeat, scanAgain, exit, confirm, cancel }

/// Normalises recognised speech: lower-case, unify Bengali code points,
/// strip punctuation.
String normalizeSpeech(String input) {
  var s = input.toLowerCase().trim();
  s = s
      .replaceAll('য়', 'য়') // য় decomposed -> composed
      .replaceAll('ড়', 'ড়') // ড়
      .replaceAll('ঢ়', 'ঢ়') // ঢ়
      .replaceAll('ঊ', 'উ')
      .replaceAll('ী', 'ি') // tolerate long/short i spelling variants
      .replaceAll('ূ', 'ু');
  s = s.replaceAll(RegExp(r'[.,!?।"“”‘’\-]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Ordered: more specific phrases first ("scan again" before "scan").
final List<(VoiceCommand, List<String>)> _patterns = [
  (VoiceCommand.scanAgain, ['scan again', 'new session', 'start again', 'start over', 'restart', 'আবার স্ক্যান', 'নতুন সেশন', 'আবার শুরু']),
  (VoiceCommand.repeat, ['repeat summary', 'repeat', 'say again', 'say that again', 'pardon', 'আবার বলো', 'আবার বলুন', 'পুনরায় বলুন', 'পুনরাবৃত্তি', 'রিপিট']),
  (VoiceCommand.scanNext, ['scan next', 'next note', 'next', 'another', 'পরের নোট', 'পরেরটা', 'পরের', 'পরবর্তি']),
  (VoiceCommand.scanMore, ['scan more', 'add more', 'more notes', 'more', 'আরও স্ক্যান', 'আরো স্ক্যান', 'আরও', 'আরো']),
  (VoiceCommand.undo, ['undo', 'remove last', 'delete last', 'take back', 'আনডু', 'শেষেরটা বাদ', 'বাদ দাও', 'বাদ দিন', 'মুছে ফেলো', 'মুছুন']),
  (VoiceCommand.total, ['total', 'how much', 'balance', 'মোট', 'কত টাকা']),
  (VoiceCommand.finish, ['finish', 'finished', 'done', 'calculate', 'payment', 'pay', 'শেষ', 'হিসাব', 'সম্পন্ন']),
  (VoiceCommand.exit, ['exit', 'close', 'quit', 'goodbye', 'বের হও', 'বের হন', 'প্রস্থান', 'বন্ধ করো', 'বন্ধ করুন']),
  (VoiceCommand.stop, ['stop', 'pause', 'থামো', 'থামুন', 'থাম']),
  (VoiceCommand.confirm, ['confirm', 'yes', 'yeah', 'okay', 'ok', 'sure', 'হ্যাঁ', 'হ্যা', 'নিশ্চিত', 'ঠিক আছে']),
  (VoiceCommand.cancel, ['cancel', 'no', 'nope', 'বাতিল', 'না']),
  (VoiceCommand.start, ['start', 'begin', 'শুরু', 'স্টার্ট']),
  (VoiceCommand.scan, ['scan', 'capture', 'স্ক্যান', 'ছবি তোলো']),
];

bool _containsPhrase(String text, String phrase) {
  // Word-boundary match for Latin phrases; substring for Bengali (no \b support).
  if (RegExp(r'^[a-z ]+$').hasMatch(phrase)) {
    return RegExp('(^| )${RegExp.escape(phrase)}( |\$)').hasMatch(text);
  }
  final words = text.split(' ');
  if (!phrase.contains(' ')) return words.contains(phrase) || (phrase.length > 2 && text.contains(phrase));
  return text.contains(phrase);
}

/// Returns the first command found in [input], or null.
VoiceCommand? parseCommand(String input, {Set<VoiceCommand>? allowed}) {
  final text = normalizeSpeech(input);
  if (text.isEmpty) return null;
  for (final (cmd, phrases) in _patterns) {
    if (allowed != null && !allowed.contains(cmd)) continue;
    for (final p in phrases) {
      if (_containsPhrase(text, normalizeSpeech(p))) return cmd;
    }
  }
  return null;
}
