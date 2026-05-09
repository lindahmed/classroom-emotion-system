import os

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

os.environ["SKIP_DB_INIT"] = "true"

from backend import auth, main


@pytest.fixture
def client():
    return TestClient(main.app)


def test_create_user_success(client, monkeypatch):
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
    resp = client.post(
        "/auth/signup",
        json={
            "email": "student1@example.com",
            "password": "StrongPass123",
            "role": "student",
            "institution_id": "S010",
            "full_name": "Student One",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["email"] == "student1@example.com"
    assert "password_hash" not in body


def test_duplicate_email_rejected(client, monkeypatch):
    def fake_create_account(email, password, role, institution_id, full_name=None):
        raise HTTPException(status_code=409, detail="Email already registered")

    monkeypatch.setattr(main, "create_account", fake_create_account)
    resp = client.post(
        "/auth/signup",
        json={
            "email": "student1@example.com",
            "password": "StrongPass123",
            "role": "student",
            "institution_id": "S010",
        },
    )
    assert resp.status_code == 409


@pytest.mark.parametrize(
    ("role", "institution_id"),
    [("student", "S12345"), ("lecturer", "L12345"), ("admin", "A12345")],
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


def test_login_success(client, monkeypatch):
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
    resp = client.post("/auth/login", json={"email": "student@example.com", "password": "StrongPass123"})
    assert resp.status_code == 200
    assert resp.json()["access_token"] == "token-abc"


def test_login_wrong_password_fails(client, monkeypatch):
    def fake_authenticate(email, password, ip_address, user_agent):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    monkeypatch.setattr(main, "authenticate", fake_authenticate)
    resp = client.post("/auth/login", json={"email": "student@example.com", "password": "wrong"})
    assert resp.status_code == 401


def test_protected_route_requires_auth(client):
    resp = client.get("/known-students")
    assert resp.status_code == 401


def test_protected_route_works_after_auth_override(client):
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "id": 2,
        "email": "lecturer@example.com",
        "role": "lecturer",
        "institution_id": "L01",
        "is_active": True,
        "name": "Lecturer",
        "user_code": "T01",
        "token": "token-xyz",
    }
    try:
        resp = client.post("/start-session/L101")
        assert resp.status_code == 200
        assert resp.json()["status"] == "started"
    finally:
        main.app.dependency_overrides.clear()


def test_logout_revokes_token(client, monkeypatch):
    revoked = {"value": False}

    def fake_revoke(token):
        if token == "token-xyz":
            revoked["value"] = True

    monkeypatch.setattr(main, "revoke_token", fake_revoke)
    main.app.dependency_overrides[main.get_current_user] = lambda: {
        "id": 2,
        "email": "lecturer@example.com",
        "role": "lecturer",
        "institution_id": "L01",
        "is_active": True,
        "name": "Lecturer",
        "user_code": "T01",
        "token": "token-xyz",
    }
    try:
        resp = client.post("/auth/logout")
        assert resp.status_code == 200
        assert revoked["value"] is True
        assert resp.json()["success"] is True
    finally:
        main.app.dependency_overrides.clear()


def test_change_password_authenticated_endpoint(client, monkeypatch):
    # Ensure the route exists and calls the helper.
    called = {"ok": False}

    def fake_change_password_authenticated(user_id: int, old_password: str, new_password: str):
        assert user_id == 2
        assert old_password == "oldpass"
        assert new_password == "NewStrongPass123"
        called["ok"] = True
        return {"message": "Password changed successfully"}

    # Override dependency properly
    main.app.dependency_overrides[main.get_current_user] = lambda: {"id": 2}
    monkeypatch.setattr(main, "change_password_authenticated", fake_change_password_authenticated)
    try:
        resp = client.post("/auth/change-password", json={"old_password": "oldpass", "new_password": "NewStrongPass123"})
        assert resp.status_code == 200
        assert resp.json()["message"] == "Password changed successfully"
        assert called["ok"] is True
    finally:
        main.app.dependency_overrides.clear()
