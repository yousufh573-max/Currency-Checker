# Machine learning module

**Status: no trained model is included.** No licensed Bangladeshi banknote
dataset was available while building this project, so recognition is *not*
functional until you collect data, train, evaluate and install a model as
described below. Until then the backend returns `model_not_installed` and the
app says "the recognition model is not installed" — it never guesses.

## Architecture

```
photo ─► quality check ─► CV segmentation + perspective correction ─► rectified note crop
                                     │                                         │
                                     ▼                                         ▼
                            torn-area estimate                MobileNetV3-Small classifier
                       (expected geometry vs remaining)       (19 classes: 9 denominations ×
                                                               front/back + not_banknote)
```

* Localisation / torn estimation: classical OpenCV (`backend/app/services/torn.py`,
  Dart port in `mobile/lib/services/vision/torn_estimator.dart`).
* Recognition: a compact classifier on the rectified crop → ONNX for the
  backend (run by OpenCV DNN, no PyTorch at serving time) and TFLite for the phone.
* **Upgrading to YOLO:** a YOLOv8-seg model can replace the CV localiser.
  Keep its output contract (note polygon → rectified crop + mask) and the
  torn ratio and classifier code stay unchanged.

## 1. Collect data (legally)

* Photograph **your own** notes or notes you are permitted to photograph, or use
  datasets whose licence explicitly allows this use. Record the licence.
* Bangladesh Bank rules on reproducing currency images apply — keep the dataset
  private and do not publish full-resolution note images.
* Do **not** store serial numbers in labels; blur them if you share samples.
* Cover: all 9 denominations, every issued series you can get, **both sides**,
  varied lighting (daylight, indoor, dim, torch), backgrounds (table, cloth,
  hand), angles (≤35°), rotation (incl. upside down), folded, worn, torn,
  partially covered by fingers, and a `not_banknote` set (receipts, cards,
  paper, other currencies, empty table).
* Target ≥ 150 photos per class from ≥ 25 **different physical notes** per denomination.

## 2. Directory layout & manifest

```
machine_learning/datasets/bdt/
├── images/            any sub-folders you like
└── manifest.csv
```

`manifest.csv` columns:

| column | meaning |
|---|---|
| `image_path` | path relative to the manifest |
| `note_id` | ID of the **physical note** (all photos of one note share it — e.g. `n100-007`). For negatives use one ID per object/scene. |
| `denomination` | 2, 5, 10, 20, 50, 100, 200, 500, 1000, or `not_banknote` |
| `side` | `front` / `back` (empty for negatives) |
| `series` | issue year/series, free text (optional) |
| `torn_ratio` | measured missing area in % (optional, for torn-ratio evaluation) |
| `split` | filled by `split_dataset.py` |

### Annotation guidelines
* One note per photo for classifier data; label what is visible.
* `torn_ratio` ground truth: scan/photograph the note flat on a contrasting
  background, measure missing area against an intact note of the same series
  (e.g. pixel count of a traced mask). Do not count folds/fingers as missing.
* If you cannot tell the denomination, discard the photo — never guess.
* Two people should label independently for a 10 % sample; resolve disagreements.

## 3. Validate & split (no PyTorch needed)

```bash
python datasets/split_dataset.py datasets/bdt/manifest.csv --val 0.15 --test 0.15
python datasets/validate_dataset.py datasets/bdt/manifest.csv
```

The split is **grouped by `note_id`**, so the same physical note never appears
in two splits (prevents leakage). The validator fails on leakage, invalid
labels, undecodable files, and inconsistent note IDs.

## 4. Train

```bash
pip install -r requirements.txt
python training/train.py --manifest datasets/bdt/manifest.csv --epochs 40 --version 1.0.0
```

Augmentations: rotation, perspective, colour/lighting jitter, blur, 180°
flips, simulated tears/folded corners/finger occlusion.

## 5. Export & evaluate

```bash
python export/export_model.py --tflite --install     # ONNX (+verification) and TFLite
python evaluation/evaluate.py --manifest datasets/bdt/manifest.csv \
       --model weights/banknote_classifier.onnx --labels weights/labels.json
```

`evaluation/report/` gets `report.json` (accuracy, per-class accuracy,
threshold sweep, torn-ratio MAE) and the confusion matrix (CSV/PNG).
Pick `MIN_CONFIDENCE` from the sweep so that accuracy of *accepted* notes meets
your target (e.g. ≥ 99.5 %), and set it in `backend/.env` and
`mobile/lib/core/app_config.dart`.

## 6. Install

* Backend: `MODEL_PATH` / `MODEL_LABELS_PATH` in `backend/.env` (defaults point to `weights/`).
* App: `--install` copies `banknote_classifier.tflite` and `labels.json` to
  `mobile/assets/models/`; rebuild the APK. Settings → Recognition shows the model version.

## Tests

`python -m pytest tests` — grouped split and leakage detection.
