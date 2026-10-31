#!/usr/bin/env python3
"""
Extract ArcFace embeddings from images using InsightFace.

Default behavior returns one embedding per detected face, so group photos yield
multiple embeddings. Pass --first-only for selfie/debug flows where a single
largest face is expected. Pass --anti-spoof to run MiniFASNet before returning
the first embedding; this is intended for live verification selfies only.

Success stdout, one JSON line:
  {"embeddings":[[...]],"count":1,"model":"ArcFace","detector_backend":"scrfd"}

Failure stderr, one JSON line:
  {"error":"...","code":"face_not_detected"}
"""

import argparse
import json
import os
import sys
from functools import lru_cache

import cv2
import numpy as np
import onnxruntime as ort
from insightface.app import FaceAnalysis


BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_ROOT = (
    os.environ.get("FACE_VERIFICATION_MODEL_HOME")
    or os.environ.get("INSIGHTFACE_HOME")
    or os.environ.get("DEEPFACE_HOME")
    or os.path.join(BACKEND_ROOT, ".deepface-home")
)

MODEL = "ArcFace"
DETECTOR = "scrfd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract ArcFace embeddings from an image.")
    parser.add_argument("image", help="Path to the image file")
    parser.add_argument(
        "--detector",
        default=DETECTOR,
        help="Detector name for API compatibility. InsightFace uses SCRFD internally.",
    )
    parser.add_argument(
        "--first-only",
        action="store_true",
        help="Return only the largest detected face instead of all faces",
    )
    parser.add_argument(
        "--anti-spoof",
        action="store_true",
        help="Run MiniFASNet liveness detection before returning the embedding",
    )
    parser.add_argument(
        "--anti-spoof-model",
        default=os.path.join(BACKEND_ROOT, "models", "minifasnet_v2.onnx"),
        help="Path to the MiniFASNet ONNX model",
    )
    parser.add_argument(
        "--anti-spoof-threshold",
        type=float,
        default=0.50,
        help="Minimum live probability required for --anti-spoof",
    )
    return parser.parse_args()


def emit_error(message: str, code: str, **extra: object) -> int:
    payload = {"error": message, "code": code}
    payload.update(extra)
    print(json.dumps(payload, separators=(",", ":")), file=sys.stderr)
    return 1


@lru_cache(maxsize=1)
def face_app() -> FaceAnalysis:
    app = FaceAnalysis(
        name=os.environ.get("FACE_RECOGNITION_PACK", "buffalo_l"),
        root=MODEL_ROOT,
        allowed_modules=["detection", "recognition"],
        providers=["CPUExecutionProvider"],
    )
    app.prepare(ctx_id=-1, det_size=(640, 640))
    return app


def largest_first(faces):
    return sorted(
        faces,
        key=lambda face: max(0.0, float(face.bbox[2] - face.bbox[0]))
        * max(0.0, float(face.bbox[3] - face.bbox[1])),
        reverse=True,
    )


def crop_for_minifasnet(image: np.ndarray, bbox: np.ndarray, scale: float = 2.7) -> np.ndarray:
    height, width = image.shape[:2]
    x1, y1, x2, y2 = [float(value) for value in bbox]
    box_width = max(1.0, x2 - x1)
    box_height = max(1.0, y2 - y1)
    center_x = x1 + box_width / 2.0
    center_y = y1 + box_height / 2.0
    side = max(box_width, box_height) * scale

    left = int(max(0, round(center_x - side / 2.0)))
    top = int(max(0, round(center_y - side / 2.0)))
    right = int(min(width, round(center_x + side / 2.0)))
    bottom = int(min(height, round(center_y + side / 2.0)))

    crop = image[top:bottom, left:right]
    if crop.size == 0:
        raise ValueError("Anti-spoof crop was empty")

    crop = cv2.resize(crop, (80, 80), interpolation=cv2.INTER_LINEAR)
    crop = crop.astype(np.float32) / 255.0
    return np.transpose(crop, (2, 0, 1))[np.newaxis, :]


def softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - np.max(logits, axis=1, keepdims=True)
    exp = np.exp(shifted)
    return exp / np.sum(exp, axis=1, keepdims=True)


def liveness_result(image: np.ndarray, bbox: np.ndarray, model_path: str) -> dict:
    if not os.path.isfile(model_path):
        raise FileNotFoundError(f"MiniFASNet model not found: {model_path}")

    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    tensor = crop_for_minifasnet(image, bbox)
    logits = session.run(None, {input_name: tensor})[0]
    probabilities = softmax(logits.astype(np.float32))

    # Model output order is [live, print-attack, replay-attack].
    live_score = float(probabilities[0][0])
    print_attack_score = float(probabilities[0][1])
    replay_attack_score = float(probabilities[0][2])
    return {
        "live_score": live_score,
        "print_attack_score": print_attack_score,
        "replay_attack_score": replay_attack_score,
    }


def embedding_for(face) -> list[float]:
    embedding = getattr(face, "normed_embedding", None)
    if embedding is None:
        embedding = face.embedding
    embedding = np.asarray(embedding, dtype=np.float32)
    norm = float(np.linalg.norm(embedding))
    if norm > 0:
        embedding = embedding / norm
    return embedding.tolist()


def main() -> int:
    args = parse_args()

    if not os.path.isfile(args.image):
        return emit_error(f"Image not found: {args.image}", "image_processing_failed")

    if args.detector.lower() not in {"scrfd", "insightface"}:
        return emit_error(
            f"Unsupported detector '{args.detector}'. This pipeline uses SCRFD.",
            "image_processing_failed",
        )

    image = cv2.imread(args.image)
    if image is None:
        return emit_error("Image could not be decoded as a JPEG, PNG, or WebP image.", "image_processing_failed")

    try:
        faces = largest_first(face_app().get(image))
    except Exception as exc:
        return emit_error(str(exc), "image_processing_failed")

    if not faces:
        return emit_error(
            "Face could not be detected in the image. Please use a clear human face photo.",
            "face_not_detected",
        )

    if args.first_only:
        faces = faces[:1]

    liveness = None
    if args.anti_spoof:
        try:
            liveness = liveness_result(image, faces[0].bbox, args.anti_spoof_model)
        except Exception as exc:
            return emit_error(str(exc), "image_processing_failed")

        if liveness["live_score"] < args.anti_spoof_threshold:
            return emit_error(
                "Selfie liveness check failed. Please take a fresh live selfie.",
                "spoof_detected",
                liveness=liveness,
                threshold=args.anti_spoof_threshold,
            )

    embeddings = [embedding_for(face) for face in faces]
    payload = {
        "embeddings": embeddings,
        "count": len(embeddings),
        "model": MODEL,
        "detector_backend": DETECTOR,
    }
    if liveness is not None:
        payload["liveness"] = liveness

    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
