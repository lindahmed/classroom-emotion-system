"""
auth.py — Real authentication helpers for EduPulse FastAPI backend.
"""

from __future__ import annotations

import hashlib
import os
import re
import uuid
import logging
import smtplib
from email.message import EmailMessage
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from .database import get_connection

ALGORITHM = "HS256"
PASSWORD_MIN_LENGTH = 8
EMAIL_REGEX = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
ROLE_PREFIXES = {"student": "S", "lecturer": "L", "admin": "A"}
security = HTTPBearer(auto_error=False)
logger = logging.getLogger(__name__)


def _auth_secret() -> str:
    return os.getenv("AUTH_SECRET", "change-me-in-env")


def _token_expiry_minutes() -> int:
    raw = os.getenv("TOKEN_EXPIRY_MINUTES", "60")
    try:
        minutes = int(raw)
    except ValueError:
        minutes = 60
    return minutes if minutes > 0 else 60


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _update_password_hash_pg(cur, user_id: int, new_password: str) -> None:
    """Update password_hash using PostgreSQL pgcrypto crypt().

    This keeps hashes compatible with the Shiny/R auth path which verifies via:
      password_hash = crypt(plain, password_hash)
    """
    cur.execute(
        "UPDATE users SET password_hash = crypt(%s, gen_salt('bf')), updated_at = NOW() WHERE user_id = %s",
        (new_password, int(user_id)),
    )


def _verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def _decode_token(token: str) -> Dict[str, Any]:
    try:
        payload = jwt.decode(token, _auth_secret(), algorithms=[ALGORITHM])
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        ) from exc
    return payload


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _normalize_role(role: str) -> str:
    normalized_role = (role or "").strip().lower()
    if normalized_role not in ROLE_PREFIXES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Role must be one of: student, lecturer, admin",
        )
    return normalized_role


def _normalize_institution_id(institution_id: str) -> str:
    return (institution_id or "").strip().upper()


def _validate_signup_input(email: str, password: str, role: str, institution_id: str) -> None:
    if not EMAIL_REGEX.match(email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid email format",
        )
    if len(password) < PASSWORD_MIN_LENGTH:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Password must be at least {PASSWORD_MIN_LENGTH} characters",
        )
    expected_prefix = ROLE_PREFIXES[role]
    if not institution_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Institution ID is required",
        )
    if role == "student" and institution_id.isdigit():
        return
    if not institution_id.startswith(expected_prefix):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{role.title()} institution ID must start with {expected_prefix}",
        )


def _build_unique_username(cur, email: str) -> str:
    base = re.sub(r"[^a-z0-9_]", "_", email.split("@", 1)[0].lower())[:40] or "user"
    candidate = base
    suffix = 1
    while True:
        cur.execute("SELECT 1 FROM users WHERE username = %s", (candidate,))
        if cur.fetchone() is None:
            return candidate
        suffix += 1
        candidate = f"{base}_{suffix}"


def _query_user_public(user_id: int) -> Dict[str, Any]:
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    u.user_id,
                    u.email,
                    u.role::text AS role,
                    u.institution_id,
                    u.is_active,
                    COALESCE(a.full_name, l.full_name, s.full_name, split_part(u.email, '@', 1)) AS name,
                    COALESCE(u.institution_id, l.lecturer_code, s.student_code) AS user_code
                FROM users u
                LEFT JOIN admins a ON a.user_id = u.user_id
                LEFT JOIN lecturers l ON l.user_id = u.user_id
                LEFT JOIN students s ON s.user_id = u.user_id
                WHERE u.user_id = %s
                LIMIT 1
                """,
                (user_id,),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="User not found",
                )
            return {
                "id": row[0],
                "email": row[1],
                "role": row[2],
                "institution_id": row[3] or "",
                "is_active": row[4],
                "name": row[5] or "",
                "user_code": row[6] or "",
            }


def create_account(
    email: str,
    password: str,
    role: str,
    institution_id: str,
    full_name: Optional[str] = None,
) -> Dict[str, Any]:
    normalized_email = _normalize_email(email)
    normalized_role = _normalize_role(role)
    normalized_institution_id = _normalize_institution_id(institution_id)
    _validate_signup_input(normalized_email, password, normalized_role, normalized_institution_id)

    display_name = (full_name or "").strip() or normalized_email.split("@", 1)[0]
    password_hash = _get_password_hash(password)

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM users WHERE lower(email) = lower(%s)", (normalized_email,))
            if cur.fetchone() is not None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Email already registered",
                )

            cur.execute("SELECT 1 FROM users WHERE lower(institution_id) = lower(%s)", (normalized_institution_id,))
            if cur.fetchone() is not None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Institution ID already registered",
                )

            username = _build_unique_username(cur, normalized_email)
            cur.execute(
                """
                INSERT INTO users (username, email, password_hash, role, institution_id, is_active)
                VALUES (%s, %s, %s, %s, %s, TRUE)
                RETURNING user_id
                """,
                (username, normalized_email, password_hash, normalized_role, normalized_institution_id),
            )
            user_id = cur.fetchone()[0]
            if normalized_role == "student":
                cur.execute(
                    """
                    INSERT INTO students (user_id, student_code, full_name, enrollment_year)
                    VALUES (%s, %s, %s, EXTRACT(YEAR FROM NOW())::integer)
                    """,
                    (user_id, normalized_institution_id, display_name),
                )
            elif normalized_role == "lecturer":
                cur.execute(
                    """
                    INSERT INTO lecturers (user_id, lecturer_code, full_name)
                    VALUES (%s, %s, %s)
                    """,
                    (user_id, normalized_institution_id, display_name),
                )
            else:
                cur.execute(
                    """
                    INSERT INTO admins (user_id, full_name)
                    VALUES (%s, %s)
                    """,
                    (user_id, display_name),
                )

    return _query_user_public(user_id)


def authenticate(email: str, password: str, ip_address: Optional[str], user_agent: Optional[str]) -> Dict[str, Any]:
    normalized_email = _normalize_email(email)
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT user_id, email, password_hash, role::text, institution_id, is_active
                FROM users
                WHERE lower(email) = lower(%s)
                LIMIT 1
                """,
                (normalized_email,),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid email or password",
                )

            user_id, user_email, password_hash, role, institution_id, is_active = row
            if not is_active or not _verify_password(password, password_hash):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid email or password",
                )

            expires_in_minutes = _token_expiry_minutes()
            expires_at = datetime.now(timezone.utc) + timedelta(minutes=expires_in_minutes)
            session_id = str(uuid.uuid4())
            payload = {
                "sub": str(user_id),
                "email": user_email,
                "role": role,
                "institution_id": institution_id,
                "sid": session_id,
                "exp": expires_at,
            }
            access_token = jwt.encode(payload, _auth_secret(), algorithm=ALGORITHM)
            token_hash = _hash_token(access_token)

            cur.execute(
                """
                INSERT INTO login_sessions (session_id, user_id, token_hash, ip_address, user_agent, expires_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (session_id, user_id, token_hash, ip_address, user_agent, expires_at),
            )
            cur.execute(
                "UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE user_id = %s",
                (user_id,),
            )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": expires_in_minutes * 60,
        "user": _query_user_public(int(user_id)),
    }


def revoke_token(token: str) -> None:
    payload = _decode_token(token)
    session_id = payload.get("sid")
    if not session_id:
        return

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE login_sessions
                SET revoked_at = NOW()
                WHERE session_id = %s AND revoked_at IS NULL
                """,
                (session_id,),
            )


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> Dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    token = credentials.credentials
    payload = _decode_token(token)
    user_id = payload.get("sub")
    session_id = payload.get("sid")
    if not user_id or not session_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )

    token_hash = _hash_token(token)
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Single query: validate session + fetch user public fields.
            cur.execute(
                """
                SELECT
                    u.user_id,
                    u.email,
                    u.role::text AS role,
                    u.institution_id,
                    u.is_active,
                    COALESCE(a.full_name, l.full_name, s.full_name, split_part(u.email, '@', 1)) AS name,
                    COALESCE(u.institution_id, l.lecturer_code, s.student_code) AS user_code
                FROM login_sessions ls
                JOIN users u ON u.user_id = ls.user_id
                LEFT JOIN admins a ON a.user_id = u.user_id
                LEFT JOIN lecturers l ON l.user_id = u.user_id
                LEFT JOIN students s ON s.user_id = u.user_id
                WHERE ls.session_id = %s
                  AND ls.user_id = %s
                  AND ls.token_hash = %s
                  AND ls.revoked_at IS NULL
                  AND ls.expires_at > NOW()
                  AND u.is_active = TRUE
                LIMIT 1
                """,
                (session_id, int(user_id), token_hash),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Session is invalid or expired",
                )

    user = {
        "id": row[0],
        "email": row[1],
        "role": row[2],
        "institution_id": row[3],
        "is_active": row[4],
        "name": row[5],
        "user_code": row[6],
        "token": token,
        "session_id": session_id,
    }
    return user


def require_roles(*allowed_roles: str):
    def _dependency(current_user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        if current_user["role"] not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user

    return _dependency


def _generate_verification_code() -> str:
    """Generate a 6-digit verification code."""
    import secrets
    return f"{secrets.randbelow(1_000_000):06d}"


def _smtp_config() -> Dict[str, Any]:
    return {
        "host": os.getenv("SMTP_HOST", "").strip(),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "user": os.getenv("SMTP_USER", "").strip(),
        "password": os.getenv("SMTP_PASSWORD", "").strip(),
        "from_email": os.getenv("SMTP_FROM_EMAIL", "").strip() or os.getenv("SMTP_USER", "").strip(),
        "from_name": os.getenv("SMTP_FROM_NAME", "EduPulse AI").strip() or "EduPulse AI",
        "use_tls": os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"},
    }


def _send_password_reset_email(to_email: str, verification_code: str) -> None:
    cfg = _smtp_config()
    if not cfg["host"] or not cfg["from_email"]:
        raise RuntimeError("SMTP is not configured (set SMTP_HOST/SMTP_USER/SMTP_PASSWORD/SMTP_FROM_EMAIL)")

    msg = EmailMessage()
    msg["Subject"] = "EduPulse AI password reset code"
    msg["From"] = f"{cfg['from_name']} <{cfg['from_email']}>"
    msg["To"] = to_email
    msg.set_content(
        "You requested a password reset for EduPulse AI.\n\n"
        f"Your verification code is: {verification_code}\n\n"
        "If you did not request this, you can ignore this email.\n"
    )

    with smtplib.SMTP(cfg["host"], cfg["port"], timeout=15) as smtp:
        smtp.ehlo()
        if cfg["use_tls"]:
            smtp.starttls()
            smtp.ehlo()
        if cfg["user"] and cfg["password"]:
            smtp.login(cfg["user"], cfg["password"])
        smtp.send_message(msg)


def request_password_change(email: str) -> Dict[str, str]:
    """Request a password change by generating and storing a verification code."""
    normalized_email = _normalize_email(email)

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM users WHERE lower(email) = lower(%s)", (normalized_email,))
            row = cur.fetchone()
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="User not found",
                )

            user_id = row[0]
            verification_code = _generate_verification_code()
            code_hash = _hash_token(verification_code)

            expires_at = datetime.now(timezone.utc) + timedelta(minutes=30)

            cur.execute(
                """
                DELETE FROM password_reset_tokens
                WHERE user_id = %s AND used_at IS NULL AND expires_at > NOW()
                """,
                (user_id,),
            )

            cur.execute(
                """
                INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
                VALUES (%s, %s, %s)
                """,
                (user_id, code_hash, expires_at),
            )

    # Send real email via SMTP.
    _send_password_reset_email(normalized_email, verification_code)
    logger.info("Password reset code emailed to %s (valid 30 minutes)", normalized_email)

    return {"message": "Verification code sent to email", "email": normalized_email}


def verify_and_change_password(email: str, verification_code: str, new_password: str) -> Dict[str, str]:
    """Verify code and update password."""
    normalized_email = _normalize_email(email)

    if len(new_password) < PASSWORD_MIN_LENGTH:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Password must be at least {PASSWORD_MIN_LENGTH} characters",
        )

    code_hash = _hash_token(verification_code)

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT u.user_id, prt.reset_id
                FROM password_reset_tokens prt
                JOIN users u ON u.user_id = prt.user_id
                WHERE lower(u.email) = lower(%s)
                  AND prt.token_hash = %s
                  AND prt.used_at IS NULL
                  AND prt.expires_at > NOW()
                LIMIT 1
                """,
                (normalized_email, code_hash),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid or expired verification code",
                )

            user_id, reset_id = row

            _update_password_hash_pg(cur, user_id, new_password)

            cur.execute(
                "UPDATE password_reset_tokens SET used_at = NOW() WHERE reset_id = %s",
                (reset_id,),
            )

    return {"message": "Password changed successfully"}


def change_password_authenticated(user_id: int, old_password: str, new_password: str) -> Dict[str, str]:
    """Change password for an already-authenticated user (no email verification)."""
    if len(new_password) < PASSWORD_MIN_LENGTH:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Password must be at least {PASSWORD_MIN_LENGTH} characters",
        )

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT password_hash FROM users WHERE user_id = %s AND is_active = TRUE LIMIT 1",
                (int(user_id),),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

            current_hash = row[0]
            if not _verify_password(old_password, current_hash):
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Old password is incorrect")

            _update_password_hash_pg(cur, int(user_id), new_password)

    return {"message": "Password changed successfully"}
