import '../models/analysis_result.dart';
import '../models/session.dart';

enum AppLanguage { en, bn }

/// UI + spoken strings in English and Bengali. Kept in one place so that the
/// displayed result and the spoken message are always generated from the same
/// data and can never disagree.
class S {
  const S(this.lang);
  final AppLanguage lang;
  bool get bn => lang == AppLanguage.bn;

  String _t(String en, String bnText) => bn ? bnText : en;

  String get ttsLocale => bn ? 'bn-BD' : 'en-US';
  String get sttLocale => bn ? 'bn_BD' : 'en_US';

  // ---------------------------------------------------------------- welcome
  String get appTitle => 'Banknote\nAssistant';
  String get tagline => _t('Automatic detection, voice guidance and amount calculation for everyone.',
      'সবার জন্য স্বয়ংক্রিয় নোট শনাক্তকরণ, কণ্ঠ নির্দেশনা ও টাকার হিসাব।');
  String get listening => _t('Listening....', 'শুনছি....');
  String get notListening => _t('Tap the microphone to talk', 'কথা বলতে মাইক্রোফোনে চাপুন');
  String get speaking => _t('Speaking....', 'বলছি....');
  String get sayStart => _t('Say “Start” to begin', 'শুরু করতে “শুরু” বলুন');
  String get welcomeSpeech => _t(
      'Welcome to Banknote Assistant. Say Start, or tap the large button at the bottom of the screen, to begin scanning your notes.',
      'ব্যাংকনোট সহকারীতে স্বাগতম। নোট স্ক্যান শুরু করতে শুরু বলুন, অথবা স্ক্রিনের নিচের বড় বোতামে চাপুন।');
  String get micPermissionDenied => _t(
      'Microphone permission is off. You can still use the on-screen buttons, or enable the microphone in settings.',
      'মাইক্রোফোনের অনুমতি বন্ধ। আপনি স্ক্রিনের বোতাম ব্যবহার করতে পারেন, অথবা সেটিংসে মাইক্রোফোন চালু করুন।');
  String get cameraPermissionDenied => _t('Camera permission is required to scan notes. Please allow camera access in settings.',
      'নোট স্ক্যান করতে ক্যামেরার অনুমতি প্রয়োজন। সেটিংসে ক্যামেরার অনুমতি দিন।');
  String get settings => _t('Settings', 'সেটিংস');

  // ---------------------------------------------------------------- scanner
  String get capturing => _t('Capturing....', 'ছবি তোলা হচ্ছে....');
  String get searching => _t('Looking for a note....', 'নোট খোঁজা হচ্ছে....');
  String get holdSteady => _t('Please hold steady.', 'স্থির করে ধরুন।');
  String get scannerIntro => _t('Hold one note flat in front of the camera, about 20 centimetres away.',
      'একটি নোট ক্যামেরার সামনে প্রায় ২০ সেন্টিমিটার দূরে সোজা করে ধরুন।');
  String guidance(String key) => switch (key) {
        'move_left' => _t('Move note left', 'নোট বাঁ দিকে সরান'),
        'move_right' => _t('Move note right', 'নোট ডান দিকে সরান'),
        'move_up' => _t('Move note up', 'নোট উপরে সরান'),
        'move_down' => _t('Move note down', 'নোট নিচে সরান'),
        'move_closer' => _t('Move note closer', 'নোট কাছে আনুন'),
        'move_farther' => _t('Move note farther away', 'নোট একটু দূরে সরান'),
        'hold_steady' => _t('Hold the note steady', 'নোট স্থির রাখুন'),
        'improve_lighting' => _t('Improve the lighting', 'আরও আলোতে নিন'),
        'reduce_glare' => _t('Too bright. Reduce glare', 'অতিরিক্ত আলো। ঝলক কমান'),
        'one_note' => _t('Place only one note inside the frame', 'ফ্রেমে শুধু একটি নোট রাখুন'),
        'place_note' => _t('Place a note inside the frame', 'ফ্রেমের ভিতরে একটি নোট রাখুন'),
        'remove_note' => _t('Remove the previous note', 'আগের নোটটি সরিয়ে নিন'),
        'capturing' => _t('Capturing. Hold steady', 'ছবি তোলা হচ্ছে। স্থির রাখুন'),
        _ => _t('Hold the note in the frame', 'নোট ফ্রেমের ভিতরে ধরুন'),
      };
  String get flashOn => _t('Turn flashlight on', 'ফ্ল্যাশলাইট চালু করুন');
  String get flashOff => _t('Turn flashlight off', 'ফ্ল্যাশলাইট বন্ধ করুন');
  String get torch => _t('Torch', 'টর্চ');
  String get capture => _t('Capture', 'ছবি তুলুন');
  String get captureNow => _t('Capture now', 'এখনই ছবি তুলুন');
  String get finish => _t('Finish', 'শেষ');
  String get demoBanner => _t('DEMO MODE — not real recognition', 'ডেমো মোড — আসল শনাক্তকরণ নয়');

  // --------------------------------------------------------------- analysis
  String get analyzing => _t('Analyzing note...', 'নোট বিশ্লেষণ হচ্ছে...');
  String get pleaseWait => _t('Please wait.....', 'অনুগ্রহ করে অপেক্ষা করুন.....');
  String stage(StageName s) => switch (s) {
        StageName.imageQuality => _t('Image quality check', 'ছবির মান যাচাই'),
        StageName.tornDetection => _t('Torn detection', 'ছেঁড়া অংশ শনাক্তকরণ'),
        StageName.tornRatio => _t('Torn ratio calculation', 'ছেঁড়ার হার গণনা'),
        StageName.currencyRecognition => _t('Currency recognition', 'নোট শনাক্তকরণ'),
      };
  String stageStatus(StageStatus s) => switch (s) {
        StageStatus.pending => _t('waiting', 'অপেক্ষমাণ'),
        StageStatus.running => _t('in progress', 'চলছে'),
        StageStatus.passed => _t('done', 'সম্পন্ন'),
        StageStatus.warning => _t('uncertain', 'অনিশ্চিত'),
        StageStatus.failed => _t('failed', 'ব্যর্থ'),
        StageStatus.skipped => _t('skipped', 'বাদ দেওয়া হয়েছে'),
      };
  String get analyzingSpeech => _t('Analyzing the note. Please wait.', 'নোট বিশ্লেষণ হচ্ছে। অপেক্ষা করুন।');
  String get retry => _t('Retry', 'আবার চেষ্টা');
  String get rescan => _t('Rescan', 'আবার স্ক্যান');
  String errorMessage(String code) => switch (code) {
        'timeout' => _t('The analysis took too long. Say Retry, or Scan to capture again.',
            'বিশ্লেষণে অনেক সময় লাগছে। আবার চেষ্টা বলুন, অথবা আবার স্ক্যান করতে স্ক্যান বলুন।'),
        'network' => _t('Cannot reach the recognition server. Check the internet connection, then say Retry.',
            'সার্ভারে সংযোগ করা যাচ্ছে না। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা বলুন।'),
        'consent_required' => _t('Server processing is not allowed yet. Open settings to give consent, or use on-device mode.',
            'সার্ভারে ছবি পাঠানোর অনুমতি দেওয়া হয়নি। সেটিংসে অনুমতি দিন অথবা অন-ডিভাইস মোড ব্যবহার করুন।'),
        'model_not_installed' => _t(
            'The banknote recognition model is not installed, so this note cannot be identified. It was not added to your total.',
            'নোট শনাক্তকরণ মডেল ইনস্টল করা নেই, তাই নোটটি শনাক্ত করা যায়নি। এটি মোটে যোগ হয়নি।'),
        'server_error' => _t('The server reported an error. Say Retry.', 'সার্ভারে সমস্যা হয়েছে। আবার চেষ্টা বলুন।'),
        'invalid_image' => _t('The photo could not be read. Please scan again.', 'ছবিটি পড়া যায়নি। আবার স্ক্যান করুন।'),
        _ => _t('Something went wrong. Say Retry or Scan.', 'একটি সমস্যা হয়েছে। আবার চেষ্টা বা স্ক্যান বলুন।'),
      };

  // ----------------------------------------------------------------- result
  String takaWord(int n) => _t('$n Taka', '$n টাকা');
  String detected(int n) => _t('$n Taka detected.', '$n টাকা শনাক্ত হয়েছে।');
  String confidence(double c) => _t('Confidence: ${(c * 100).toStringAsFixed(1)}%', 'নিশ্চয়তা: ${(c * 100).toStringAsFixed(1)}%');
  String conditionLabel(NoteCondition c) => switch (c) {
        NoteCondition.good => _t('Good', 'ভালো'),
        NoteCondition.damaged => _t('Damaged', 'ক্ষতিগ্রস্ত'),
        NoteCondition.tooTorn => _t('Too torn', 'অতিরিক্ত ছেঁড়া'),
        NoteCondition.uncertain => _t('Uncertain', 'অনিশ্চিত'),
      };
  String conditionLine(NoteCondition c) => _t('Condition: ${conditionLabel(c)}', 'অবস্থা: ${conditionLabel(c)}');
  String tornLine(double? t) =>
      t == null ? _t('(Torn ratio: unknown)', '(ছেঁড়ার হার: অজানা)') : _t('(Torn ratio: ${_pct(t)}%)', '(ছেঁড়ার হার: ${_pct(t)}%)');
  String get addedToTotal => _t('Added to total', 'মোটে যোগ হয়েছে');
  String get notAddedToTotal => _t('Not added to total', 'মোটে যোগ হয়নি');
  String get currentTotal => _t('Current Total', 'বর্তমান মোট');
  String get notRecognized => _t('Not recognized', 'শনাক্ত হয়নি');
  String get scanNext => _t('Scan next', 'পরের নোট');
  String get undo => _t('Undo', 'আনডু');
  String get hearTotal => _t('Hear total', 'মোট শুনুন');

  String _pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String reason(String? r) => switch (r) {
        'too_torn' => _t('The note is too torn.', 'নোটটি অতিরিক্ত ছেঁড়া।'),
        'damaged' => _t('The note is damaged.', 'নোটটি ক্ষতিগ্রস্ত।'),
        'low_confidence' => _t('I am not sure which note this is. Please rescan.', 'নোটটি নিশ্চিতভাবে চেনা যায়নি। আবার স্ক্যান করুন।'),
        'condition_uncertain' =>
          _t('I could not measure the note condition reliably. Please unfold the note, keep fingers off it, and rescan.',
              'নোটের অবস্থা নিশ্চিতভাবে মাপা যায়নি। নোটটি খুলে, আঙুল সরিয়ে আবার স্ক্যান করুন।'),
        'multiple_notes' => _t('More than one note was in the frame. Scan one note at a time.', 'ফ্রেমে একাধিক নোট ছিল। একবারে একটি নোট স্ক্যান করুন।'),
        'not_recognized' => _t('This does not look like a Bangladeshi banknote.', 'এটি বাংলাদেশি নোট বলে মনে হচ্ছে না।'),
        'poor_image_quality' => _t('The photo was not clear enough. Please rescan in better light.', 'ছবি যথেষ্ট পরিষ্কার নয়। আরও আলোতে আবার স্ক্যান করুন।'),
        'no_note_found' || 'note_too_small_or_absent' =>
          _t('No note was found in the photo. Please rescan.', 'ছবিতে কোনো নোট পাওয়া যায়নি। আবার স্ক্যান করুন।'),
        'model_not_installed' => errorMessage('model_not_installed'),
        _ => _t('The note could not be verified. Please rescan.', 'নোটটি যাচাই করা যায়নি। আবার স্ক্যান করুন।'),
      };

  /// Spoken result — built from the same fields as the displayed result.
  String resultSpeech(AnalysisResult r, {required bool added, required int total}) {
    final b = StringBuffer();
    if (r.isDemo) b.write(_t('Demo mode, not real recognition. ', 'ডেমো মোড, আসল শনাক্তকরণ নয়। '));
    if (r.denomination != null) {
      b.write('${detected(r.denomination!)} ');
      if (r.tornRatio != null && r.tornRatioReliable) {
        b.write(_t('Torn ratio is ${_pct(r.tornRatio!)} percent. ', 'ছেঁড়ার হার ${_pct(r.tornRatio!)} শতাংশ। '));
      }
    }
    if (added) {
      b.write(_t('Added to your total. ', 'আপনার মোটে যোগ হয়েছে। '));
    } else {
      if (r.rejectionReason != 'model_not_installed') b.write('${reason(r.rejectionReason)} ');
      b.write(_t('Not added to your total. ', 'আপনার মোটে যোগ হয়নি। '));
      if (r.rejectionReason == 'model_not_installed') b.write('${reason(r.rejectionReason)} ');
    }
    b.write(totalSpeech(total));
    return b.toString().trim();
  }

  String totalSpeech(int total) => _t('Current total: $total Taka.', 'বর্তমান মোট: $total টাকা।');
  String get resultHelp => _t('Say Scan Next, Undo, Total, or Finish.', 'পরের, আনডু, মোট, অথবা শেষ বলুন।');
  String undoSpeech(ScanRecord? removed, int total) {
    if (removed == null) return _t('There is nothing to undo. ', 'আনডু করার কিছু নেই। ') + totalSpeech(total);
    final what = removed.accepted && removed.denomination != null
        ? _t('Removed the last ${removed.denomination} Taka note. ', 'শেষ ${removed.denomination} টাকার নোট বাদ দেওয়া হয়েছে। ')
        : _t('Removed the last scan. It was not counted. ', 'শেষ স্ক্যান বাদ দেওয়া হয়েছে। এটি গণনায় ছিল না। ');
    return what + totalSpeech(total);
  }

  // ---------------------------------------------------------------- payment
  String get howMuch => _t('How much do you need to pay?\nPlease say the amount', 'আপনাকে কত টাকা দিতে হবে?\nঅনুগ্রহ করে পরিমাণ বলুন');
  String get howMuchSpeech => _t('How much do you need to pay? Please say the amount, for example, 70 Taka.',
      'আপনাকে কত টাকা দিতে হবে? পরিমাণ বলুন, যেমন সত্তর টাকা।');
  String get exampleAmount => _t('(e.g. say 70 Taka)', '(যেমন বলুন সত্তর টাকা)');
  String get totalScannedAmount => _t('Total Scanned Amount', 'মোট স্ক্যান করা টাকা');
  String get requiredPaymentAmount => _t('Required Payment Amount', 'প্রয়োজনীয় পরিশোধের পরিমাণ');
  String get notSetYet => _t('Not set — tap to type', 'নির্ধারিত নয় — লিখতে চাপুন');
  String get scanMoreNotes => _t('Scan more notes', 'আরও নোট স্ক্যান করুন');
  String get seeSummary => _t('See summary', 'সারসংক্ষেপ দেখুন');
  String get enterAmount => _t('Enter amount in Taka', 'টাকার পরিমাণ লিখুন');
  String get ok => _t('OK', 'ঠিক আছে');
  String get cancel => _t('Cancel', 'বাতিল');
  String paymentText(PaymentResult p) => p.sufficient
      ? _t('You have enough. Remaining ${p.remaining} Taka.', 'আপনার কাছে যথেষ্ট আছে। বাকি থাকবে ${p.remaining} টাকা।')
      : _t('Not enough. You need ${p.shortage} Taka more.', 'যথেষ্ট নয়। আরও ${p.shortage} টাকা প্রয়োজন।');
  String paymentSpeech(PaymentResult p) =>
      '${_t('You have ${p.total} Taka. You need to pay ${p.required} Taka. ', 'আপনার কাছে ${p.total} টাকা। দিতে হবে ${p.required} টাকা। ')}'
      '${paymentText(p)} '
      '${p.sufficient ? _t('Say Finish to hear the summary, or Scan More.', 'সারসংক্ষেপ শুনতে শেষ বলুন, অথবা আরও স্ক্যান বলুন।') : _t('Say Scan More to add notes, or Finish.', 'নোট যোগ করতে আরও স্ক্যান বলুন, অথবা শেষ বলুন।')}';
  String get amountNotUnderstood =>
      _t('Sorry, I did not catch the amount. Please say it again, for example 70 Taka.', 'দুঃখিত, পরিমাণ বোঝা যায়নি। আবার বলুন, যেমন সত্তর টাকা।');
  String get amountFirst => _t('Please say the amount you need to pay first.', 'প্রথমে কত টাকা দিতে হবে তা বলুন।');

  // -------------------------------------------------------------- ui extras
  String get totalLabel => _t('Total', 'মোট');
  String get notesLabel => _t('notes counted', 'টি নোট গণনা হয়েছে');
  String get notesShort => _t('notes', 'টি নোট');
  String modeLabel(String mode) => switch (mode) {
        'onDevice' => _t('Offline mode', 'অফলাইন মোড'),
        'server' => _t('Server mode', 'সার্ভার মোড'),
        _ => _t('Demo mode', 'ডেমো মোড'),
      };
  String get typeAmount => _t('Type amount', 'পরিমাণ লিখুন');
  String get youHave => _t('You have', 'আপনার আছে');
  String get youNeed => _t('You need', 'প্রয়োজন');
  String get breakdown => _t('Notes counted', 'গণনা করা নোট');
  String get confidenceShort => _t('Confidence', 'নিশ্চয়তা');
  String get tornShort => _t('Missing area', 'হারানো অংশ');
  String get scanSteady => _t('Steadiness', 'স্থিরতা');

  // ---------------------------------------------------------------- summary
  String get summary => _t('Summary', 'সারসংক্ষেপ');
  String totalScannedLine(int t) => _t('Total scanned : $t Taka', 'মোট স্ক্যান : $t টাকা');
  String neededLine(int? n) => _t('Needed amount : ${n ?? '-'} Taka', 'প্রয়োজন : ${n ?? '-'} টাকা');
  String remainingLine(PaymentResult? p) => p == null
      ? _t('Remaining : -', 'বাকি : -')
      : p.sufficient
          ? _t('Remaining : ${p.remaining} Taka', 'বাকি : ${p.remaining} টাকা')
          : _t('Short by : ${p.shortage} Taka', 'ঘাটতি : ${p.shortage} টাকা');
  String rejectedLine(int n) => _t('Not counted : $n note(s)', 'গণনা হয়নি : $nটি নোট');
  String get cashOnlyDisclaimer => _t('Cash calculation only. No payment was made or verified.',
      'শুধু নগদ টাকার হিসাব। কোনো লেনদেন করা বা যাচাই করা হয়নি।');
  String summaryText(SessionState s) {
    final p = s.payment;
    final b = StringBuffer(_t('Calculation complete. You scanned ${s.total} Taka. ', 'হিসাব সম্পন্ন। আপনি ${s.total} টাকা স্ক্যান করেছেন। '));
    if (p != null) {
      b.write(_t('Needed ${p.required} Taka. ', 'প্রয়োজন ${p.required} টাকা। '));
      b.write(p.sufficient ? _t('Remaining ${p.remaining} Taka.', 'বাকি ${p.remaining} টাকা।') : _t('Short by ${p.shortage} Taka.', 'ঘাটতি ${p.shortage} টাকা।'));
    }
    return b.toString().trim();
  }

  String summarySpeech(SessionState s) =>
      '${summaryText(s)} ${s.rejected.isNotEmpty ? '${rejectedLine(s.rejected.length)}. ' : ''}$cashOnlyDisclaimer '
      '${_t('Say Scan Again to start a new session, Exit to close, or Repeat.', 'নতুন সেশনের জন্য আবার স্ক্যান, বন্ধ করতে প্রস্থান, অথবা আবার বলো বলুন।')}';
  String get scanAgainTitle => _t('Scan Again by voice', 'কণ্ঠে আবার স্ক্যান');
  String get scanAgainHint => _t('Say “Scan Again” to Scan', 'স্ক্যান করতে “আবার স্ক্যান” বলুন');
  String get exitTitle => _t('Exit by voice', 'কণ্ঠে প্রস্থান');
  String get exitHint => _t('Say “Exit” to close session', 'সেশন বন্ধ করতে “প্রস্থান” বলুন');
  String get confirmNewSession => _t('Start a new session? The current total will be cleared. Say Confirm or Cancel.',
      'নতুন সেশন শুরু করবেন? বর্তমান মোট মুছে যাবে। নিশ্চিত অথবা বাতিল বলুন।');
  String get confirm => _t('Confirm', 'নিশ্চিত');
  String get goodbye => _t('Session saved. Goodbye.', 'সেশন সংরক্ষিত হয়েছে। বিদায়।');
}
