from __future__ import annotations

import logging
import os
import tempfile
from typing import Any

import io

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# opencv = fast Haar heuristics (reference-style); deepface = TensorFlow emotion model
_engine = os.getenv("EDUPULSE_EMOTION_ENGINE", "opencv").lower().strip()

EMOTION_MAPPING = {
    "happy": "Happy",
    "neutral": "Neutral",
    "sad": "Bored",
    "disgust": "Bored",
    "angry": "Confused",
    "fear": "Confused",
    "surprise": "Confused",
}

ENGAGEMENT_SCORES = {
    "Happy": 0.95,
    "Neutral": 0.65,
    "Confused": 0.40,
    "Bored": 0.20,
}

VIT_EMOTION_MAPPING = {
    "Angry": "Confused",
    "Disgusted": "Bored",
    "Fearful": "Confused",
    "Happy": "Happy",
    "Neutral": "Neutral",
    "Sad": "Bored",
    "Surprised": "Confused",
}

_EMOTION_MODEL: Any | None = None
_FACE_CASCADE: Any | None = None
_SMILE_CASCADE: Any | None = None
_VIT_PIPELINE: Any | None = None


def _compute_focus_score(emotion: str, confidence: float) -> float:
    try:
        c = float(confidence)
    except Exception:
        c = 0.5
    c = max(0.0, min(1.0, c))
    if emotion in ("Happy", "Neutral"):
        return 0.70 + 0.30 * c
    return 0.20 + 0.40 * c


def warmup_emotion_model() -> None:
    """Pre-load emotion path so first full-mode frame does not stall."""
    global _FACE_CASCADE, _SMILE_CASCADE, _EMOTION_MODEL, _VIT_PIPELINE
    if _engine == "deepface":
        if _EMOTION_MODEL is not None:
            return
        from deepface import DeepFace

        logger.info("Warming up emotion model (DeepFace)")
        _EMOTION_MODEL = DeepFace.build_model("Emotion")
        logger.info("Emotion model ready (DeepFace)")
        return

    if _engine == "vit":
        if _VIT_PIPELINE is not None:
            return
        from transformers import pipeline as hf_pipeline

        model_name = os.getenv(
            "EDUPULSE_VIT_MODEL",
            "mo-thecreator/vit-Facial-Expression-Recognition",
        )
        logger.info("Warming up ViT emotion model (%s)", model_name)
        _VIT_PIPELINE = hf_pipeline(
            "image-classification",
            model=model_name,
            top_k=7,
        )
        logger.info("ViT emotion model ready (%s)", model_name)
        return

    import cv2

    base = cv2.data.haarcascades
    fp = os.path.join(base, "haarcascade_frontalface_default.xml")
    sp = os.path.join(base, "haarcascade_smile.xml")
    logger.info("Warming up emotion engine (OpenCV cascades)")
    _FACE_CASCADE = cv2.CascadeClassifier(fp)
    _SMILE_CASCADE = cv2.CascadeClassifier(sp)
    if _FACE_CASCADE.empty() or _SMILE_CASCADE.empty():
        logger.warning("OpenCV cascade load failed — emotion may fall back to Neutral")
    else:
        logger.info("OpenCV emotion cascades ready")


def analyze_emotion(image_bytes: bytes):
    if _engine == "deepface":
        return _analyze_emotion_deepface(image_bytes)
    if _engine == "vit":
        return _analyze_emotion_vit(image_bytes)
    return _analyze_emotion_opencv(image_bytes)


def analyze_emotion_crop(face_bgr) -> dict:
    """Analyze emotion from a pre-cropped face BGR numpy array.

    Falls back to Neutral if encoding or analysis fails.
    """
    import cv2

    try:
        _, buf = cv2.imencode(".jpg", face_bgr)
        return analyze_emotion(buf.tobytes())
    except Exception as exc:
        logger.warning("Per-face emotion analysis failed, falling back to Neutral: %s", exc)
        return {
            "emotion": "Neutral",
            "confidence": 0.5,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.5,
            "engine": "fallback",
        }


def _analyze_emotion_deepface(image_bytes: bytes):
    global _EMOTION_MODEL
    from deepface import DeepFace

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as temp_file:
            temp_file.write(image_bytes)
            temp_path = temp_file.name
        if _EMOTION_MODEL is None:
            warmup_emotion_model()
        result = DeepFace.analyze(img_path=temp_path, actions=["emotion"], enforce_detection=False)
        if result:
            dominant = result[0]["dominant_emotion"]
            emotion = EMOTION_MAPPING.get(dominant, "Neutral")
            confidence = float(result[0]["emotion"][dominant]) / 100.0
            return {
                "emotion": emotion,
                "confidence": confidence,
                "engagement_score": ENGAGEMENT_SCORES[emotion],
                "focus_score": _compute_focus_score(emotion, confidence),
                "engine": "deepface",
            }
        return {
            "emotion": "Neutral",
            "confidence": 0.5,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.5,
            "engine": "deepface",
        }
    except Exception as exc:
        logger.exception("DeepFace emotion failed: %s", exc)
        raise RuntimeError("DeepFace emotion analysis failed") from exc
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass


def _analyze_emotion_vit(image_bytes: bytes):
    """Analyze emotion using HuggingFace ViT model fine-tuned on AffectNet."""
    global _VIT_PIPELINE

    if _VIT_PIPELINE is None:
        warmup_emotion_model()

    try:
        image = Image.open(io.BytesIO(image_bytes))
        if image.mode != "RGB":
            image = image.convert("RGB")

        results = _VIT_PIPELINE(image)
        scores = {r["label"]: float(r["score"]) for r in results}

        dominant_label = max(scores, key=scores.get)
        confidence = scores[dominant_label]

        emotion = VIT_EMOTION_MAPPING.get(dominant_label, "Neutral")

        return {
            "emotion": emotion,
            "confidence": confidence,
            "engagement_score": ENGAGEMENT_SCORES[emotion],
            "focus_score": _compute_focus_score(emotion, confidence),
            "engine": "vit",
        }
    except Exception as exc:
        logger.exception("ViT emotion analysis failed: %s", exc)
        return {
            "emotion": "Neutral",
            "confidence": 0.5,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.5,
            "engine": "vit-fallback",
        }


def _analyze_emotion_opencv(image_bytes: bytes):
    import cv2

    global _FACE_CASCADE, _SMILE_CASCADE
    if _FACE_CASCADE is None or _SMILE_CASCADE is None:
        warmup_emotion_model()

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return {
            "emotion": "Neutral",
            "confidence": 0.4,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.45,
            "engine": "opencv",
        }

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)

    if _FACE_CASCADE is None or _FACE_CASCADE.empty():
        return {
            "emotion": "Neutral",
            "confidence": 0.45,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.45,
            "engine": "opencv",
        }

    faces = _FACE_CASCADE.detectMultiScale(
        gray, scaleFactor=1.15, minNeighbors=5, minSize=(56, 56), flags=cv2.CASCADE_SCALE_IMAGE
    )
    if len(faces) == 0:
        return {
            "emotion": "Neutral",
            "confidence": 0.48,
            "engagement_score": ENGAGEMENT_SCORES["Neutral"],
            "focus_score": 0.42,
            "engine": "opencv",
        }

    x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
    roi = gray[y : y + h, x : x + w]
    var = float(cv2.Laplacian(roi, cv2.CV_64F).var())
    smile_raw = (
        _SMILE_CASCADE.detectMultiScale(
            roi, scaleFactor=1.7, minNeighbors=18, minSize=(int(w * 0.15), int(h * 0.15))
        )
        if _SMILE_CASCADE is not None and not _SMILE_CASCADE.empty()
        else ()
    )

    if len(smile_raw) > 0:
        emotion = "Happy"
        base = 0.72 + min(0.23, len(smile_raw) * 0.05)
    elif var < 80.0:
        emotion = "Bored"
        base = 0.55
    elif var > 350.0:
        emotion = "Confused"
        base = 0.58
    else:
        emotion = "Neutral"
        base = 0.62

    confidence = max(0.35, min(0.95, base))
    return {
        "emotion": emotion,
        "confidence": confidence,
        "engagement_score": ENGAGEMENT_SCORES[emotion],
        "focus_score": _compute_focus_score(emotion, confidence),
        "engine": "opencv",
    }
