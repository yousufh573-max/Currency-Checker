"""Export the trained PyTorch model to ONNX (backend) and TFLite (mobile).

Usage:
    python export/export_model.py --weights weights/banknote_classifier.pt --labels weights/labels.json --tflite --install

--install copies:
    weights/banknote_classifier.onnx + labels.json   → used by the backend (MODEL_PATH)
    banknote_classifier.tflite + labels.json         → mobile/assets/models/

TFLite conversion uses `ai-edge-torch` (pip install ai-edge-torch). The
TFLite model takes NHWC float input; labels.json is rewritten with
"layout": "NHWC" for the mobile copy.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import torch

ML = Path(__file__).resolve().parents[1]
ROOT = ML.parent
sys.path.insert(0, str(ML))
sys.path.insert(0, str(ML / "training"))
from common import INPUT_SIZE, LABELS  # noqa: E402
from train import build_model  # noqa: E402


class SoftmaxWrapper(torch.nn.Module):
    def __init__(self, m: torch.nn.Module, nhwc: bool = False):
        super().__init__()
        self.m, self.nhwc = m, nhwc

    def forward(self, x):
        if self.nhwc:
            x = x.permute(0, 3, 1, 2)
        return torch.softmax(self.m(x), dim=1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", type=Path, default=ML / "weights/banknote_classifier.pt")
    ap.add_argument("--labels", type=Path, default=ML / "weights/labels.json")
    ap.add_argument("--tflite", action="store_true")
    ap.add_argument("--install", action="store_true")
    a = ap.parse_args()

    meta = json.loads(a.labels.read_text())
    assert meta["labels"] == LABELS, "labels.json does not match common.LABELS"
    model = build_model(len(LABELS))
    model.load_state_dict(torch.load(a.weights, map_location="cpu"))
    model.eval()

    onnx_path = a.weights.with_suffix(".onnx")
    dummy = torch.zeros(1, 3, INPUT_SIZE, INPUT_SIZE)
    torch.onnx.export(SoftmaxWrapper(model), dummy, onnx_path, input_names=["input"], output_names=["probs"], opset_version=17)
    print("ONNX:", onnx_path)

    # Sanity check with OpenCV DNN (the backend runtime).
    import cv2

    net = cv2.dnn.readNetFromONNX(str(onnx_path))
    net.setInput(dummy.numpy())
    out = net.forward()
    ref = SoftmaxWrapper(model)(dummy).detach().numpy()
    assert np.allclose(out, ref, atol=1e-4), "ONNX output mismatch"
    print("ONNX verified against PyTorch")

    if a.tflite:
        import ai_edge_torch

        nhwc = torch.zeros(1, INPUT_SIZE, INPUT_SIZE, 3)
        edge = ai_edge_torch.convert(SoftmaxWrapper(model, nhwc=True).eval(), (nhwc,))
        tfl = a.weights.with_suffix(".tflite")
        edge.export(str(tfl))
        print("TFLite:", tfl)

    if a.install:
        dst_mobile = ROOT / "mobile/assets/models"
        dst_mobile.mkdir(parents=True, exist_ok=True)
        if a.tflite:
            shutil.copy(a.weights.with_suffix(".tflite"), dst_mobile / "banknote_classifier.tflite")
            mobile_meta = dict(meta, layout="NHWC")
            (dst_mobile / "labels.json").write_text(json.dumps(mobile_meta, indent=2))
            print("Installed mobile model →", dst_mobile)
        print("Backend reads", onnx_path, "(set MODEL_PATH / MODEL_LABELS_PATH in backend/.env if moved)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
