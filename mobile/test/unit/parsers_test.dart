import 'package:banknote_assistant/services/voice/amount_parser.dart';
import 'package:banknote_assistant/services/voice/command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAmount (English)', () {
    final cases = {
      '70 Taka': 70,
      '70 taka': 70,
      'Seventy Taka': 70,
      'seventy': 70,
      'One hundred and fifty Taka': 150,
      'a hundred taka': 100,
      'two thousand five hundred': 2500,
      'one lakh': 100000,
      '1,500 taka': 1500,
      '৳250': 250,
      'I need to pay seventy five taka please': 75,
      'twenty one': 21,
    };
    cases.forEach((input, expected) => test('"$input" → $expected', () => expect(parseAmount(input), expected)));

    test('no amount', () {
      expect(parseAmount('scan more'), isNull);
      expect(parseAmount(''), isNull);
      expect(parseAmount('it is a note'), isNull);
    });
  });

  group('parseAmount (Bengali)', () {
    final cases = {
      'সত্তর টাকা': 70,
      'একশ পঞ্চাশ টাকা': 150,
      'একশো পঞ্চাশ': 150,
      'এক শ পঞ্চাশ': 150,
      '৭০ টাকা': 70,
      'পাঁচশ টাকা': 500,
      'দুই হাজার': 2000,
      'এক হাজার দুইশ বিশ টাকা': 1220,
      'নিরানব্বই': 99,
      'ঊনত্রিশ টাকা': 29, // long-u variant
      'বিশ': 20,
    };
    cases.forEach((input, expected) => test('"$input" → $expected', () => expect(parseAmount(input), expected)));
  });

  group('parseCommand', () {
    final cases = <String, VoiceCommand>{
      'Start': VoiceCommand.start,
      'please start': VoiceCommand.start,
      'Scan': VoiceCommand.scan,
      'scan next': VoiceCommand.scanNext,
      'next': VoiceCommand.scanNext,
      'Scan More': VoiceCommand.scanMore,
      'stop': VoiceCommand.stop,
      'Finish': VoiceCommand.finish,
      "I'm done": VoiceCommand.finish,
      'total': VoiceCommand.total,
      'how much do I have': VoiceCommand.total,
      'Undo': VoiceCommand.undo,
      'repeat': VoiceCommand.repeat,
      'Repeat Summary': VoiceCommand.repeat,
      'Scan Again': VoiceCommand.scanAgain,
      'Exit': VoiceCommand.exit,
      'confirm': VoiceCommand.confirm,
      'yes': VoiceCommand.confirm,
      'cancel': VoiceCommand.cancel,
      // Bengali
      'শুরু': VoiceCommand.start,
      'শুরু করুন': VoiceCommand.start,
      'স্ক্যান': VoiceCommand.scan,
      'পরের নোট': VoiceCommand.scanNext,
      'আরও স্ক্যান': VoiceCommand.scanMore,
      'থামুন': VoiceCommand.stop,
      'শেষ': VoiceCommand.finish,
      'মোট কত': VoiceCommand.total,
      'আনডু': VoiceCommand.undo,
      'আবার বলুন': VoiceCommand.repeat,
      'আবার স্ক্যান': VoiceCommand.scanAgain,
      'প্রস্থান': VoiceCommand.exit,
      'হ্যাঁ': VoiceCommand.confirm,
      'বাতিল': VoiceCommand.cancel,
    };
    cases.forEach((input, expected) => test('"$input" → $expected', () => expect(parseCommand(input), expected)));

    test('word boundaries: "restarting" handled, "nextdoor" not "next"', () {
      expect(parseCommand('nextdoor'), isNull);
      expect(parseCommand('scanner'), isNull);
    });

    test('allowed filter', () {
      expect(parseCommand('exit', allowed: {VoiceCommand.start}), isNull);
      expect(parseCommand('start', allowed: {VoiceCommand.start}), VoiceCommand.start);
    });

    test('scan again is not confused with scan or repeat', () {
      expect(parseCommand('scan again please'), VoiceCommand.scanAgain);
    });
  });
}
