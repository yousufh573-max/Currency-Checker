# On-device model

Place the exported TensorFlow Lite model here to enable offline recognition:

- `banknote_classifier.tflite`
- `labels.json`

Produce both with `machine_learning/export/export_model.py --tflite`.
No model is bundled: until one is installed, the app reports
"recognition model not installed" and never guesses a denomination.
