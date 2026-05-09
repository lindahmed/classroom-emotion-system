import pathlib
import sys

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))

from backend import face_recognition_engine as engine  # noqa: E402


class FakeDeepFace:
    calls = 0

    @staticmethod
    def extract_faces(**kwargs):
        return [{"face": "face-a"}, {"face": "face-b"}, {"face": "face-c"}]

    @staticmethod
    def find(**kwargs):
        FakeDeepFace.calls += 1
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

    result = engine.recognize_faces(b"fake-image")

    assert result["total_faces"] == 3
    assert result["unknown_count"] == 1
    assert result["recognized_count"] == 1
    assert result["recognized"][0]["student_id"] == "231006367"
    assert result["recognized"][0]["student_name"] == "Mohamed Alaa Lotfy"
    assert result["recognized"][0]["confidence"] == 0.8
