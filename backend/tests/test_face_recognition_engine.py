import pathlib
import sys

import numpy as np

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))

from backend import face_recognition_engine as engine  # noqa: E402


class FakeDeepFace:
    calls = 0

    @staticmethod
    def find(**kwargs):
        FakeDeepFace.calls += 1
        img = kwargs["img_path"]
        if isinstance(img, str):
            assert img.endswith(".jpg") or "/" in img or "\\" in img
        else:
            assert hasattr(img, "shape")
            assert len(img.shape) == 3
        if FakeDeepFace.calls == 1:
            return [[{
                "identity": "/faces/231006367_Mohamed_Alaa_Lotfy/photo_01.jpg",
                "distance": 0.1,
                "threshold": 0.5,
            }]]
        if FakeDeepFace.calls == 2:
            return [[{
                "identity": "/faces/231006367_Mohamed_Alaa_Lotfy/photo_02.jpg",
                "distance": 0.2,
                "threshold": 0.5,
            }]]
        return [[]]


def test_recognize_faces_deduplicates_students_and_counts_unknowns(tmp_path, monkeypatch):
    FakeDeepFace.calls = 0
    monkeypatch.setattr(engine, "DeepFace", FakeDeepFace)
    monkeypatch.setattr(engine, "KNOWN_FACES_PATH", str(tmp_path))
    monkeypatch.setattr(engine, "_decode_image_bgr", lambda b: np.zeros((80, 200, 3), dtype=np.uint8))
    monkeypatch.setattr(
        engine,
        "opencv_face_boxes_from_bgr",
        lambda _bgr: [(0, 0, 48, 48), (52, 0, 48, 48), (104, 0, 48, 48)],
    )

    result = engine.recognize_faces(b"fake-image")

    assert result["total_faces"] == 3
    assert result["unknown_count"] == 1
    assert result["recognized_count"] == 1
    assert result["recognized"][0]["student_id"] == "231006367"
    assert result["recognized"][0]["student_name"] == "Mohamed Alaa Lotfy"
    thresh = 1.15  # EDUPULSE_FACE_DISTANCE_THRESHOLD default
    assert abs(result["recognized"][0]["confidence"] - (thresh - 0.1) / thresh) < 1e-6


def test_recognize_one_detected_face_uses_full_frame_find(tmp_path, monkeypatch):
    """0–1 Haar hits use reference-style DeepFace.find on disk (opencv), not ndarray crops."""
    FakeDeepFace.calls = 0
    monkeypatch.setattr(engine, "DeepFace", FakeDeepFace)
    monkeypatch.setattr(engine, "KNOWN_FACES_PATH", str(tmp_path))
    monkeypatch.setattr(engine, "_decode_image_bgr", lambda b: np.zeros((80, 120, 3), dtype=np.uint8))
    monkeypatch.setattr(engine, "opencv_face_boxes_from_bgr", lambda _bgr: [(0, 0, 48, 48)])

    result = engine.recognize_faces(b"fake-image")

    assert FakeDeepFace.calls == 1
    assert result["total_faces"] == 1
    assert result["recognized_count"] == 1
