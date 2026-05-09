"""
DeepFace recognition helpers.

The public API keeps recognize_face for backward compatibility and adds
recognize_faces for multi-person attendance frames.
"""

from __future__ import annotations

import os
import tempfile
import logging
from pathlib import Path
from typing import Any

from .face_registry import KNOWN_FACES_PATH

DeepFace = None

logger = logging.getLogger(__name__)

DISTANCE_COLUMNS = (
    "distance",
    "VGG-Face_cosine",
    "Facenet_cosine",
    "Facenet512_cosine",
    "ArcFace_cosine",
    "SFace_cosine",
)


def _require_deepface():
    global DeepFace
    if DeepFace is None:
        try:
            from deepface import DeepFace as LoadedDeepFace
        except Exception as exc:  # pragma: no cover - environment dependent
            raise RuntimeError("DeepFace is not installed or could not be imported") from exc
        DeepFace = LoadedDeepFace
    if DeepFace is None:
        raise RuntimeError("DeepFace is not installed or could not be imported")
    if not os.path.isdir(KNOWN_FACES_PATH):
        raise RuntimeError(f"Known faces directory does not exist: {KNOWN_FACES_PATH}")


def _rows_from_find_result(result: Any) -> list[dict[str, Any]]:
    if result is None:
        return []
    frames = result if isinstance(result, list) else [result]
    rows: list[dict[str, Any]] = []
    for frame in frames:
        if frame is None:
            continue
        if hasattr(frame, "empty") and frame.empty:
            continue
        if hasattr(frame, "to_dict"):
            rows.extend(frame.to_dict("records"))
        elif isinstance(frame, list):
            rows.extend(row for row in frame if isinstance(row, dict))
    return rows


def _distance(row: dict[str, Any]) -> float | None:
    for column in DISTANCE_COLUMNS:
        if column in row:
            try:
                return float(row[column])
            except (TypeError, ValueError):
                return None
    for column, value in row.items():
        if column.endswith("_cosine") or column.endswith("_euclidean") or column.endswith("_euclidean_l2"):
            try:
                return float(value)
            except (TypeError, ValueError):
                return None
    return None


def _confidence(row: dict[str, Any], distance: float | None) -> float:
    threshold = row.get("threshold")
    try:
        threshold = float(threshold)
    except (TypeError, ValueError):
        threshold = 1.0
    if distance is None:
        return 0.5
    if threshold <= 0:
        return max(0.0, min(1.0, 1.0 - distance))
    return max(0.0, min(1.0, 1.0 - (distance / threshold)))


def _student_from_identity(identity: str) -> tuple[str, str]:
    folder = Path(identity).parent.name
    parts = folder.split("_", 1)
    if len(parts) == 2:
        return parts[0], parts[1].replace("_", " ")
    return folder, ""


def _best_match(rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not rows:
        return None
    return sorted(rows, key=lambda row: _distance(row) if _distance(row) is not None else 999.0)[0]


def _extract_faces(temp_path: str, detector_backend: str) -> list[dict[str, Any]]:
    kwargs = {
        "img_path": temp_path,
        "detector_backend": detector_backend,
        "enforce_detection": False,
        "align": True,
        "color_face": "bgr",
        "normalize_face": False,
    }
    try:
        return DeepFace.extract_faces(**kwargs)
    except TypeError:
        kwargs.pop("color_face", None)
        kwargs.pop("normalize_face", None)
        return DeepFace.extract_faces(**kwargs)


def _find_face(face_img: Any, refresh_database: bool) -> list[dict[str, Any]]:
    kwargs = {
        "img_path": face_img,
        "db_path": KNOWN_FACES_PATH,
        "enforce_detection": False,
        "detector_backend": "skip",
        "align": False,
    }
    if refresh_database:
        kwargs["refresh_database"] = True
    try:
        return _rows_from_find_result(DeepFace.find(**kwargs))
    except TypeError:
        kwargs.pop("refresh_database", None)
        return _rows_from_find_result(DeepFace.find(**kwargs))


def recognize_faces(
    image_bytes: bytes,
    *,
    detector_backend: str = "opencv",
    refresh_database: bool = False,
) -> dict[str, Any]:
    _require_deepface()
    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as temp_file:
        temp_file.write(image_bytes)
        temp_path = temp_file.name

    try:
        try:
            face_objs = _extract_faces(temp_path, detector_backend)
        except Exception as exc:
            logger.exception("Error extracting faces: %s", exc)
            face_objs = []

        recognized_by_student: dict[str, dict[str, Any]] = {}
        matched_face_count = 0
        for face_obj in face_objs:
            face_img = face_obj.get("face") if isinstance(face_obj, dict) else None
            if face_img is None:
                continue
            rows = _find_face(face_img, refresh_database)
            match = _best_match(rows)
            if not match or not match.get("identity"):
                continue
            matched_face_count += 1
            distance = _distance(match)
            confidence = _confidence(match, distance)
            student_id, student_name = _student_from_identity(str(match["identity"]))
            result = {
                "student_id": student_id,
                "student_name": student_name,
                "confidence": confidence,
                "distance": distance,
                "identity": str(match["identity"]),
            }
            existing = recognized_by_student.get(student_id)
            if existing is None or confidence > existing["confidence"]:
                recognized_by_student[student_id] = result

        recognized = sorted(
            recognized_by_student.values(),
            key=lambda item: item["confidence"],
            reverse=True,
        )
        total_faces = len(face_objs)
        return {
            "recognized": recognized,
            "recognized_count": len(recognized),
            "unknown_count": max(total_faces - matched_face_count, 0),
            "total_faces": total_faces,
            "recognized_any": bool(recognized),
        }
    except Exception as exc:
        logger.exception("Error in recognition: %s", exc)
        return {
            "recognized": [],
            "recognized_count": 0,
            "unknown_count": 0,
            "total_faces": 0,
            "recognized_any": False,
            "error": str(exc),
        }
    finally:
        os.unlink(temp_path)


def recognize_face(image_bytes: bytes) -> dict[str, Any]:
    result = recognize_faces(image_bytes)
    if result["recognized"]:
        first = result["recognized"][0]
        return {
            "student_id": first["student_id"],
            "student_name": first["student_name"],
            "confidence": first["confidence"],
            "recognized": True,
        }
    return {"student_id": "Unknown", "student_name": "", "recognized": False}
