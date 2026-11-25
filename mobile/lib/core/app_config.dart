/// Provisional, configurable application thresholds.
///
/// These are demonstration values for this app — NOT Bangladesh Bank rules or
/// determinations of legal tender / exchange eligibility.
class Thresholds {
  const Thresholds({
    this.minConfidence = 0.85,
    this.tornGoodMax = 5.0,
    this.tornDamagedMax = 20.0,
    this.countDamagedNotes = true,
  });

  final double minConfidence;
  final double tornGoodMax;
  final double tornDamagedMax;
  final bool countDamagedNotes;
}

const supportedDenominations = [2, 5, 10, 20, 50, 100, 200, 500, 1000];

/// Approximate note sizes (mm) used only for expected aspect ratios. Verify
/// against official Bangladesh Bank specifications.
const noteDimensionsMm = <int, (double, double)>{
  2: (110, 60),
  5: (120, 60),
  10: (122, 60),
  20: (127, 60),
  50: (130, 60),
  100: (140, 62),
  200: (145, 64),
  500: (152, 65),
  1000: (160, 70),
};

const analysisTimeout = Duration(seconds: 25);
const connectTimeout = Duration(seconds: 6);
