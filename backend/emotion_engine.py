import os
import tempfile
import logging

DeepFace = None

logger = logging.getLogger(__name__)

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


def _compute_focus_score(emotion: str, confidence: float) -> float:
    """Deterministic focus score derived from model confidence + emotion bucket."""
    try:
        c = float(confidence)
    except Exception:
        c = 0.5
    c = max(0.0, min(1.0, c))

    if emotion in ['Happy', 'Neutral']:
        # Higher base focus for positive/neutral attention states.
        return 0.70 + 0.30 * c
    # Lower base focus for confused/bored states.
    return 0.20 + 0.40 * c

def analyze_emotion(image_bytes):
    global DeepFace
    if DeepFace is None:
        try:
            from deepface import DeepFace as LoadedDeepFace
        except Exception as exc:  # pragma: no cover - environment dependent
            raise RuntimeError("DeepFace is not installed or could not be imported") from exc
        DeepFace = LoadedDeepFace
    temp_path = None
    with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as temp_file:
        temp_file.write(image_bytes)
        temp_path = temp_file.name
    try:
        result = DeepFace.analyze(img_path=temp_path, actions=["emotion"], enforce_detection=False)
        if result:
            dominant = result[0]["dominant_emotion"]
            emotion = EMOTION_MAPPING.get(dominant, "Neutral")
            confidence = result[0]["emotion"][dominant] / 100.0
            engagement_score = ENGAGEMENT_SCORES[emotion]
            focus_score = _compute_focus_score(emotion, confidence)
            return {
                "emotion": emotion,
                "confidence": confidence,
                "engagement_score": engagement_score,
                "focus_score": focus_score,
            }
        return {
            "emotion": "Neutral",
            "confidence": 0.5,
            "engagement_score": 0.65,
            "focus_score": 0.5,
        }
    except Exception as e:
        logger.exception("Error in emotion analysis: %s", e)
        return {
            "emotion": "Neutral",
            "confidence": 0.5,
            "engagement_score": 0.65,
            "focus_score": 0.5,
        }
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass
