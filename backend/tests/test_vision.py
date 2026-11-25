import cv2
import numpy as np
import pytest

from app.core.config import Settings
from app.services.analyzer import classify_condition, decide_eligibility
from app.services.image_io import ImageValidationError, decode_image
from app.services.quality import assess_quality
from app.services.torn import analyze_torn
from tests.synth import encode, scene, tear

S = Settings(_env_file=None)


def test_quality_acceptable_dark_blurry():
    img, _ = scene()
    assert assess_quality(img, S).image_quality == "acceptable"
    assert assess_quality((img * 0.1).astype(np.uint8), S).image_quality == "too_dark"
    assert assess_quality(cv2.GaussianBlur(img, (41, 41), 15), S).image_quality == "blurry"


def test_intact_note_is_good():
    img, _ = scene()
    r = analyze_torn(img)
    assert r.found and r.reliable
    assert r.torn_ratio <= 5.0, r.torn_ratio
    assert classify_condition(r.torn_ratio, r.reliable, S) == "good"


@pytest.mark.parametrize("angle", [0, 15, -30, 90])
def test_rotated_note_geometry(angle):
    img, _ = scene(note_w=500, note_h=230, angle=angle)
    r = analyze_torn(img)
    assert r.found and r.reliable, r.flags
    assert r.torn_ratio <= 5.0
    assert r.rectified.shape[1] > r.rectified.shape[0]  # perspective-corrected landscape crop


@pytest.mark.parametrize("fraction", [0.15, 0.40])
def test_torn_ratio_estimation_error(fraction):
    img, mask = scene()
    torn_img, true_pct = tear(img, mask, fraction)
    r = analyze_torn(torn_img, expected_aspect=600 / 280)
    assert r.found
    assert abs(r.torn_ratio - true_pct) < 6.0, (r.torn_ratio, true_pct)


def test_heavily_torn_classified_too_torn():
    img, mask = scene()
    torn_img, _ = tear(img, mask, 0.40)
    r = analyze_torn(torn_img, expected_aspect=600 / 280)
    assert classify_condition(r.torn_ratio, r.reliable, S) == "too_torn"


def test_shadow_not_counted_as_missing():
    img, mask = scene()
    shadowed = img.copy()
    # Soft shadow below/right of the note on the background only.
    sh = np.zeros(mask.shape, np.uint8)
    cv2.rectangle(sh, (230, 230), (840, 540), 255, -1)
    sh = cv2.bitwise_and(sh, cv2.bitwise_not(mask))
    shadowed[sh > 0] = (shadowed[sh > 0] * 0.6).astype(np.uint8)
    r = analyze_torn(shadowed)
    assert r.found and r.torn_ratio <= 5.0, (r.torn_ratio, r.flags)


def test_finger_occlusion_flagged_not_torn():
    img, _ = scene()
    occ = img.copy()
    # Skin-coloured "finger" entering from the bottom of the frame over the note.
    cv2.rectangle(occ, (390, 450), (460, 700), (120, 150, 215), -1)
    cv2.circle(occ, (425, 450), 35, (120, 150, 215), -1)
    r = analyze_torn(occ)
    assert r.found
    assert "occlusion" in r.flags or r.torn_ratio <= 5.0
    if "occlusion" in r.flags:
        assert not r.reliable


def test_multiple_notes_detected():
    img = np.full((700, 1200, 3), (178, 190, 200), np.uint8)
    a, ma = scene(note_w=420, note_h=200, img_w=1200, img_h=700, offset=(-300, 0), seed=1)
    b, mb = scene(note_w=420, note_h=200, img_w=1200, img_h=700, offset=(300, 0), seed=2)
    img[ma > 0] = a[ma > 0]
    img[mb > 0] = b[mb > 0]
    r = analyze_torn(img)
    assert "multiple_notes" in r.flags and not r.reliable


def test_note_cut_off_by_frame_is_uncertain():
    img, _ = scene(offset=(320, 0))
    r = analyze_torn(img)
    assert "touches_frame_edge" in r.flags and not r.reliable


def test_empty_background_no_note():
    img = np.full((700, 1000, 3), (178, 190, 200), np.uint8)
    assert not analyze_torn(img).found


def test_eligibility_rules():
    common = dict(quality_ok=True, flags=[], s=S)
    assert decide_eligibility(denomination=20, confidence=0.98, condition="good", **common) == (True, None)
    assert decide_eligibility(denomination=20, confidence=0.5, condition="good", **common)[1] == "low_confidence"
    assert decide_eligibility(denomination=500, confidence=0.95, condition="too_torn", **common)[1] == "too_torn"
    assert decide_eligibility(denomination=500, confidence=0.95, condition="uncertain", **common)[1] == "condition_uncertain"
    assert decide_eligibility(denomination=None, confidence=0.99, condition="good", **common)[1] == "not_recognized"


def test_image_validation():
    img, _ = scene()
    assert decode_image(encode(img), max_bytes=6_000_000, max_side=4096).shape[1] <= 1024
    with pytest.raises(ImageValidationError) as e:
        decode_image(b"GIF89a....", max_bytes=1000, max_side=4096)
    assert e.value.code == "unsupported_type"
    with pytest.raises(ImageValidationError) as e:
        decode_image(encode(img), max_bytes=1000, max_side=4096)
    assert e.value.code == "file_too_large"
    with pytest.raises(ImageValidationError) as e:
        decode_image(b"\xff\xd8\xff" + b"\x00" * 50, max_bytes=10_000, max_side=4096)
    assert e.value.code == "decode_failed"
