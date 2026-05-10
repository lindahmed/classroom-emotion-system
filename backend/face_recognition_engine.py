"""
DeepFace recognition helpers.

Multi-face frames use OpenCV Haar cascades (+ NMS) for boxes, aligned with the
working reference project, then DeepFace.find per crop. extract_faces often
yielded overlapping duplicate regions for one person.
"""

from __future__ import annotations

import logging
import os
import tempfile
from pathlib import Path
from typing import Any

import cv2
import numpy as np

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
    """Parse distance/score column from DeepFace.find row (pandas or dict names vary)."""
    dist_candidates: list[float] = []

    def _consider(column: Any, raw: Any) -> None:
        col = str(column).lower()
        if "threshold" in col or col == "identity":
            return
        if not (
            col == "distance"
            or "_cosine" in col
            or "euclidean" in col
            or col.endswith("_l2")
            or "_l2_" in col
        ):
            return
        try:
            dist_candidates.append(float(raw))
        except (TypeError, ValueError):
            return

    for column in DISTANCE_COLUMNS:
        if column in row:
            _consider(column, row[column])
            if dist_candidates:
                return min(dist_candidates)

    for column, value in row.items():
        _consider(column, value)

    return min(dist_candidates) if dist_candidates else None


def _confidence_cosine_heuristic(match: dict[str, Any], distance: float | None) -> float:
    threshold = match.get("threshold")
    try:
        threshold = float(threshold)
    except (TypeError, ValueError):
        threshold = 1.0
    if distance is None:
        return 0.5
    if threshold <= 0:
        return max(0.0, min(1.0, 1.0 - distance))
    return max(0.0, min(1.0, 1.0 - (distance / threshold)))


def _confidence_euclidean_l2(distance: float, max_distance: float) -> float:
    if max_distance <= 0:
        return 0.5
    return max(0.0, min(1.0, (max_distance - distance) / max_distance))


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


def _iou_xywh(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x1 = max(ax, bx)
    y1 = max(ay, by)
    x2 = min(ax + aw, bx + bw)
    y2 = min(ay + ah, by + bh)
    iw = max(0, x2 - x1)
    ih = max(0, y2 - y1)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    union = float(aw * ah + bw * bh) - float(inter)
    return float(inter) / union if union > 0 else 0.0


def _nms_xywh(boxes: list[tuple[int, int, int, int]], iou_thresh: float) -> list[tuple[int, int, int, int]]:
    if not boxes:
        return []
    boxes = sorted(boxes, key=lambda b: b[2] * b[3], reverse=True)
    keep: list[tuple[int, int, int, int]] = []
    for b in boxes:
        if all(_iou_xywh(b, k) < iou_thresh for k in keep):
            keep.append(b)
    return keep


def _decode_image_bgr(image_bytes: bytes) -> np.ndarray | None:
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    return img


def opencv_face_boxes_from_bgr(image_bgr: np.ndarray | None) -> list[tuple[int, int, int, int]]:
    """Detect face bounding boxes via Haar cascades (reference-style parameters)."""
    if image_bgr is None:
        return []

    cascade_path = os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml")
    detector = cv2.CascadeClassifier(cascade_path)

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)

    faces = detector.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(40, 40),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )
    boxes = [tuple(int(x) for x in b) for b in faces]

    try:
        iou_thresh = float(os.getenv("EDUPULSE_FACE_NMS_IOU", "0.35"))
    except (TypeError, ValueError):
        iou_thresh = 0.35
    boxes = _nms_xywh(boxes, iou_thresh)
    return boxes


def _find_face(face_img: Any, refresh_database: bool) -> list[dict[str, Any]]:
    """Match a cropped face against the gallery (skip separate detection; align embedding)."""
    model_name = os.getenv("EDUPULSE_FACE_MODEL", "SFace")
    metric = os.getenv("EDUPULSE_FACE_DISTANCE_METRIC", "euclidean_l2")
    kwargs: dict[str, Any] = {
        "img_path": face_img,
        "db_path": KNOWN_FACES_PATH,
        "enforce_detection": False,
        "detector_backend": "skip",
        "align": True,
        "model_name": model_name,
        "distance_metric": metric,
    }
    if refresh_database:
        kwargs["refresh_database"] = True
    try:
        kw_silent = dict(kwargs)
        kw_silent["silent"] = True
        return _rows_from_find_result(DeepFace.find(**kw_silent))
    except TypeError:
        try:
            return _rows_from_find_result(DeepFace.find(**kwargs))
        except TypeError:
            kwargs.pop("refresh_database", None)
            try:
                return _rows_from_find_result(DeepFace.find(**kwargs))
            except TypeError:
                kwargs.pop("model_name", None)
                try:
                    return _rows_from_find_result(DeepFace.find(**kwargs))
                except TypeError:
                    kwargs.pop("align", None)
                    return _rows_from_find_result(DeepFace.find(**kwargs))


def _find_face_full_frame(temp_path: str, refresh_database: bool) -> list[dict[str, Any]]:
    """Same pipeline as working reference single-face script: DeepFace.find on whole frame + OpenCV."""
    model_name = os.getenv("EDUPULSE_FACE_MODEL", "SFace")
    metric = os.getenv("EDUPULSE_FACE_DISTANCE_METRIC", "euclidean_l2")
    detector = os.getenv("EDUPULSE_FULLFRAME_DETECTOR", "opencv").strip() or "opencv"
    kwargs: dict[str, Any] = {
        "img_path": temp_path,
        "db_path": KNOWN_FACES_PATH,
        "model_name": model_name,
        "detector_backend": detector,
        "distance_metric": metric,
        "enforce_detection": False,
    }
    if refresh_database:
        kwargs["refresh_database"] = True
    try:
        kw_silent = dict(kwargs)
        kw_silent["silent"] = True
        return _rows_from_find_result(DeepFace.find(**kw_silent))
    except TypeError:
        try:
            return _rows_from_find_result(DeepFace.find(**kwargs))
        except TypeError:
            kwargs.pop("refresh_database", None)
            try:
                return _rows_from_find_result(DeepFace.find(**kwargs))
            except TypeError:
                kwargs.pop("model_name", None)
                return _rows_from_find_result(DeepFace.find(**kwargs))


def _apply_best_match(match: dict[str, Any], metric: str, max_dist: float) -> tuple[bool, float] | None:
    """Returns (accepted, confidence) if identity present, else None."""
    if not match or not match.get("identity"):
        return None

    distance = _distance(match)
    if metric == "euclidean_l2":
        if distance is not None and distance > max_dist:
            return None
        conf = (
            _confidence_euclidean_l2(distance, max_dist)
            if distance is not None
            else 0.5
        )
        return True, conf
    try:
        row_thresh = float(match["threshold"]) if match.get("threshold") is not None else None
    except (TypeError, ValueError):
        row_thresh = None
    cos_thresh = row_thresh if row_thresh is not None else 0.68
    if distance is not None and cos_thresh > 0 and distance > cos_thresh:
        return None
    return True, _confidence_cosine_heuristic(match, distance)


def recognize_faces(
    image_bytes: bytes,
    *,
    detector_backend: str = "opencv",
    refresh_database: bool = False,
) -> dict[str, Any]:
    _ = detector_backend  # retained for API compatibility (Haar is always used here)
    _require_deepface()
    temp_path: str | None = None
    try:
        bgr = _decode_image_bgr(image_bytes)
        if bgr is None:
            return {
                "recognized": [],
                "recognized_count": 0,
                "unknown_count": 0,
                "total_faces": 0,
                "recognized_any": False,
                "error": "Invalid or unreadable image.",
            }

        boxes = opencv_face_boxes_from_bgr(bgr)
        max_faces_raw = os.getenv("EDUPULSE_MAX_FACES_PER_FRAME", "12")
        try:
            max_faces = int(max_faces_raw)
        except ValueError:
            max_faces = 12
        if max_faces > 0:
            boxes = boxes[:max_faces]

        metric = os.getenv("EDUPULSE_FACE_DISTANCE_METRIC", "euclidean_l2").lower().strip()
        try:
            max_dist = float(os.getenv("EDUPULSE_FACE_DISTANCE_THRESHOLD", "1.15"))
        except (TypeError, ValueError):
            max_dist = 1.15

        fh_raw = os.getenv("EDUPULSE_FULLFRAME_FIND_MAX_HAAR_FACES", "1").strip()
        try:
            fullframe_when_haar_count_le = max(0, int(fh_raw))
        except ValueError:
            fullframe_when_haar_count_le = 1

        recognize_by_full_frame = (
            len(boxes) <= fullframe_when_haar_count_le and fullframe_when_haar_count_le >= 0
        )

        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
            tmp.write(image_bytes)
            temp_path = tmp.name

        recognized_by_student: dict[str, dict[str, Any]] = {}
        matched_face_count = 0

        if recognize_by_full_frame:
            rows = _find_face_full_frame(temp_path, refresh_database)
            match = _best_match(rows)
            applied = _apply_best_match(match, metric, max_dist) if match else None
            total_faces = 1 if applied else len(boxes)
            if applied and match:
                matched_face_count = 1
                ok, confidence = applied
                if ok:
                    distance = _distance(match)
                    student_id, student_name = _student_from_identity(str(match["identity"]))
                    recognized_by_student[student_id] = {
                        "student_id": student_id,
                        "student_name": student_name,
                        "confidence": confidence,
                        "distance": distance,
                        "identity": str(match["identity"]),
                        "box": None,
                    }
        else:
            total_faces = len(boxes)

            for (x, y, w, h) in boxes:
                crop = bgr[y : y + h, x : x + w]
                if crop.size == 0:
                    continue

                rows = _find_face(crop, refresh_database)
                match = _best_match(rows)
                applied = _apply_best_match(match, metric, max_dist) if match else None
                if applied is None or not applied[0]:
                    continue
                _, confidence = applied
                matched_face_count += 1

                distance = _distance(match)
                assert match is not None
                student_id, student_name = _student_from_identity(str(match["identity"]))
                result = {
                    "student_id": student_id,
                    "student_name": student_name,
                    "confidence": confidence,
                    "distance": distance,
                    "identity": str(match["identity"]),
                    "box": (x, y, w, h),
                }
                existing = recognized_by_student.get(student_id)
                if existing is None or confidence > existing["confidence"]:
                    recognized_by_student[student_id] = result

        recognized = sorted(recognized_by_student.values(), key=lambda item: item["confidence"], reverse=True)

        return {
            "recognized": recognized,
            "recognized_count": len(recognized),
            "unknown_count": max(total_faces - matched_face_count, 0),
            "total_faces": total_faces,
            "recognized_any": bool(recognized),
            "image_bgr": bgr,
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
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass


def recognize_face(image_bytes: bytes) -> dict[str, Any]:
    face_info = recognize_faces(image_bytes)
    if face_info.get("recognized"):
        first = face_info["recognized"][0]
        return {
            "student_id": first["student_id"],
            "student_name": first["student_name"],
            "confidence": first["confidence"],
            "recognized": True,
        }
    return {"student_id": "Unknown", "student_name": "", "recognized": False}


def warmup_recognition_model() -> None:
    """Pre-load DeepFace + representation model to reduce first-frame latency."""
    try:
        _require_deepface()
    except Exception as exc:
        logger.warning("Recognition warmup skipped (DeepFace unavailable): %s", exc)
        return
    model_name = os.getenv("EDUPULSE_FACE_MODEL", "SFace")
    try:
        DeepFace.build_model(model_name)
        logger.info("Face representation model warmed: %s", model_name)
    except Exception as exc:
        logger.warning("Face model warmup skipped (%s): %s", model_name, exc)
