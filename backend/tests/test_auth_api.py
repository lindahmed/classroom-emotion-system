import asyncio
import os

import pytest
from fastapi import HTTPException

os.environ["SKIP_DB_INIT"] = "true"

from backend import auth, main


class FakeRequest:
    class Client:
        host = "127.0.0.1"

    client = Client()
    headers = {"user-agent": "pytest"}


class FakeUpload:
    async def read(self):
        return b"fake-image"


def test_create_user_success(monkeypatch):
    def fake_create_account(email, password, role, institution_id, full_name=None):
        return {
            "id": 10,
            "email": email,
            "role": role,
            "institution_id": institution_id,
            "is_active": True,
            "name": full_name or "Student",
            "user_code": institution_id,
        }

    monkeypatch.setattr(main, "create_account", fake_create_account)
    payload = main.SignupRequest(
        email="student1@example.com",
        password="StrongPass123",
        role="student",
        institution_id="S010",
        full_name="Student One",
    )

    body = main.signup(payload)

    assert body["email"] == "student1@example.com"
    assert "password_hash" not in body


def test_duplicate_email_rejected(monkeypatch):
    def fake_create_account(email, password, role, institution_id, full_name=None):
        raise HTTPException(status_code=409, detail="Email already registered")

    monkeypatch.setattr(main, "create_account", fake_create_account)
    payload = main.SignupRequest(
        email="student1@example.com",
        password="StrongPass123",
        role="student",
        institution_id="S010",
    )

    with pytest.raises(HTTPException) as exc_info:
        main.signup(payload)
    assert exc_info.value.status_code == 409


@pytest.mark.parametrize(
    ("role", "institution_id"),
    [("student", "S12345"), ("student", "231006367"), ("lecturer", "L12345"), ("admin", "A12345")],
)
def test_role_prefix_validation_accepts_matches(role, institution_id):
    auth._validate_signup_input("user@example.com", "StrongPass123", role, institution_id)


@pytest.mark.parametrize(
    ("role", "institution_id", "expected"),
    [
        ("student", "L12345", "Student institution ID must start with S"),
        ("student", "A12345", "Student institution ID must start with S"),
        ("lecturer", "S12345", "Lecturer institution ID must start with L"),
        ("lecturer", "A12345", "Lecturer institution ID must start with L"),
        ("admin", "S12345", "Admin institution ID must start with A"),
        ("admin", "L12345", "Admin institution ID must start with A"),
    ],
)
def test_role_prefix_validation_rejects_mismatches(role, institution_id, expected):
    with pytest.raises(HTTPException) as exc_info:
        auth._validate_signup_input("user@example.com", "StrongPass123", role, institution_id)
    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == expected


def test_password_hash_is_not_plaintext():
    password_hash = auth._get_password_hash("StrongPass123")

    assert password_hash != "StrongPass123"
    assert auth._verify_password("StrongPass123", password_hash)


def test_login_success(monkeypatch):
    def fake_authenticate(email, password, ip_address, user_agent):
        return {
            "access_token": "token-abc",
            "token_type": "bearer",
            "expires_in": 3600,
            "user": {
                "id": 1,
                "email": email,
                "role": "student",
                "institution_id": "S001",
                "is_active": True,
                "name": "Student",
                "user_code": "S001",
            },
        }

    monkeypatch.setattr(main, "authenticate", fake_authenticate)
    payload = main.LoginRequest(email="student@example.com", password="StrongPass123")

    body = main.login(payload, FakeRequest())

    assert body["access_token"] == "token-abc"


def test_login_wrong_password_fails(monkeypatch):
    def fake_authenticate(email, password, ip_address, user_agent):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    monkeypatch.setattr(main, "authenticate", fake_authenticate)
    payload = main.LoginRequest(email="student@example.com", password="wrong")

    with pytest.raises(HTTPException) as exc_info:
        main.login(payload, FakeRequest())
    assert exc_info.value.status_code == 401


def test_protected_dependency_requires_auth():
    with pytest.raises(HTTPException) as exc_info:
        auth.get_current_user(None)
    assert exc_info.value.status_code == 401


def test_start_session_endpoint_uses_attendance_service(monkeypatch):
    def fake_start_attendance_session(lecture_id, started_by_user_id):
        return {"status": "started", "lecture_code": lecture_id, "started_by": started_by_user_id}

    monkeypatch.setattr(main, "start_attendance_session", fake_start_attendance_session)

    body = main.start_session("FR001", current_user={"id": 2, "role": "lecturer"})

    assert body["status"] == "started"
    assert body["started_by"] == 2


def test_logout_revokes_token(monkeypatch):
    revoked = {"value": False}

    def fake_revoke(token):
        if token == "token-xyz":
            revoked["value"] = True

    monkeypatch.setattr(main, "revoke_token", fake_revoke)

    body = main.logout(current_user={"token": "token-xyz"})

    assert revoked["value"] is True
    assert body["success"] is True


def test_analyze_attendance_frame_persists_all_recognized(monkeypatch):
    monkeypatch.setattr(main, "recognize_faces", lambda image_bytes: {
        "recognized": [
            {"student_id": "231006367", "student_name": "Mohamed Alaa Lotfy", "confidence": 0.91, "distance": 0.12},
            {"student_id": "231015291", "student_name": "Bishoy Morcos Habib", "confidence": 0.88, "distance": 0.15},
        ],
        "unknown_count": 1,
        "total_faces": 3,
    })
    monkeypatch.setattr(main, "analyze_emotion", lambda image_bytes: {
        "emotion": "Neutral",
        "confidence": 0.75,
        "engagement_score": 0.65,
        "focus_score": 0.8,
    })
    persisted = []

    def fake_mark_student_present(lecture_id, student_id, emotion_data):
        record = {
            "record_id": len(persisted) + 1,
            "student_id": student_id,
            "student_name": f"Student {student_id}",
            "lecture_id": lecture_id,
            "timestamp": "2026-05-09T12:00:00+00:00",
            "emotion": emotion_data["emotion"],
            "confidence": emotion_data["confidence"],
            "engagement_score": emotion_data["engagement_score"],
            "focus_score": emotion_data["focus_score"],
            "attendance_status": "Present",
            "is_present": True,
            "left_room": False,
            "absence_duration_minutes": 0,
        }
        persisted.append(record)
        return record

    monkeypatch.setattr(main, "mark_student_present", fake_mark_student_present)
    monkeypatch.setattr(main, "get_attendance", lambda lecture_id: {
        "attendance": [],
        "present_count": 2,
        "absent_count": 117,
        "expected_students": 119,
        "session_status": "active",
    })

    body = asyncio.run(
        main.analyze_frame(
            file=FakeUpload(),
            lecture_id="FR001",
            current_user={"id": 2, "role": "lecturer"},
        )
    )

    assert body["recognized_count"] == 2
    assert body["unknown_count"] == 1
    assert body["present_count"] == 2
    assert len(persisted) == 2


def test_change_password_authenticated_endpoint(monkeypatch):
    called = {"ok": False}

    def fake_change_password_authenticated(user_id: int, old_password: str, new_password: str):
        assert user_id == 2
        assert old_password == "oldpass"
        assert new_password == "NewStrongPass123"
        called["ok"] = True
        return {"message": "Password changed successfully"}

    monkeypatch.setattr(main, "change_password_authenticated", fake_change_password_authenticated)
    payload = main.ChangePasswordRequest(old_password="oldpass", new_password="NewStrongPass123")
    body = main.change_password_endpoint(payload, current_user={"id": 2})
    assert body["message"] == "Password changed successfully"
    assert called["ok"] is True
