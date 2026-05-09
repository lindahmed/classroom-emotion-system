from datetime import datetime
from contextlib import asynccontextmanager
import os
import logging
from typing import Dict, List, Literal, Optional

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field

from .attendance_service import (
    AttendanceServiceError,
    get_attendance,
    mark_student_present,
    start_attendance_session,
    stop_attendance_session,
)
from .auth import (
    authenticate,
    change_password_authenticated,
    create_account,
    get_current_user,
    require_roles,
    revoke_token,
    request_password_change,
    verify_and_change_password,
)
from .database import close_db, get_connection, init_db
from .face_registry import refresh_known_students
from .storage import upsert_lecture_session_start

try:
    from .face_recognition_engine import recognize_face, recognize_faces
    from .emotion_engine import analyze_emotion
except Exception:
    recognize_face = None
    recognize_faces = None
    analyze_emotion = None


logger = logging.getLogger(__name__)


def _cors_config():
    raw = os.getenv("EDUPULSE_CORS_ORIGINS", "").strip()
    if not raw:
        # Local dev: allow localhost/127.0.0.1 on any port (Shiny port varies).
        return {"allow_origins": [], "allow_origin_regex": r"^https?://(localhost|127\\.0\\.0\\.1)(:\\d+)?$"}
    origins = [o.strip() for o in raw.split(",") if o.strip()]
    return {"allow_origins": origins, "allow_origin_regex": None}


def _configure_logging():
    level_name = os.getenv("EDUPULSE_LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    root = logging.getLogger()
    if not root.handlers:
        logging.basicConfig(level=level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    else:
        root.setLevel(level)


class KnownStudent(BaseModel):
    student_id: str
    student_name: str
    image_count: int
    folder: str


class KnownStudentsResponse(BaseModel):
    students: List[KnownStudent]
    count: int


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    role: Literal["student", "lecturer", "admin"]
    institution_id: str = Field(..., min_length=2)
    full_name: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserPublic(BaseModel):
    id: int
    email: str
    role: str
    institution_id: Optional[str] = None
    is_active: bool
    name: str
    user_code: Optional[str] = None


class AuthResponse(BaseModel):
    access_token: str
    token_type: str
    expires_in: int
    user: UserPublic


class LogoutResponse(BaseModel):
    success: bool
    message: str


class PasswordChangeRequest(BaseModel):
    email: EmailStr


class PasswordChangeResponse(BaseModel):
    message: str
    email: str


class PasswordResetRequest(BaseModel):
    email: EmailStr
    verification_code: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=8)


class PasswordResetResponse(BaseModel):
    message: str


class ChangePasswordRequest(BaseModel):
    old_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=8)


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        _configure_logging()
        if os.getenv("SKIP_DB_INIT", "false").lower() not in {"1", "true", "yes"}:
            init_db()
        yield
    finally:
        close_db()


app = FastAPI(
    title="EduPulse AI Backend",
    description="FastAPI backend for classroom emotion detection, attendance tracking, and analytics.",
    version="0.3.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    # Browsers reject allow_origins=["*"] when allow_credentials=True.
    # Default: allow localhost/127.0.0.1 on any port.
    # Override: set EDUPULSE_CORS_ORIGINS="http://localhost:3838,http://127.0.0.1:3838"
    **_cors_config(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["system"])
def health():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return {"status": "ok", "db": "ok"}
    except Exception as exc:
        # Health should reflect DB availability for real deployments.
        raise HTTPException(status_code=503, detail=f"Database unavailable: {exc}") from exc


@app.post("/auth/signup", response_model=UserPublic, status_code=201, tags=["auth"])
def signup(payload: SignupRequest):
    return create_account(
        email=payload.email,
        password=payload.password,
        role=payload.role,
        institution_id=payload.institution_id,
        full_name=payload.full_name,
    )


@app.post("/auth/login", response_model=AuthResponse, tags=["auth"])
def login(payload: LoginRequest, request: Request):
    return authenticate(
        email=payload.email,
        password=payload.password,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


@app.post("/auth/logout", response_model=LogoutResponse, tags=["auth"])
def logout(current_user: Dict = Depends(get_current_user)):
    revoke_token(current_user["token"])
    return {"success": True, "message": "Logged out"}


@app.post("/auth/request-password-change", response_model=PasswordChangeResponse, tags=["auth"])
def request_password_change_endpoint(payload: PasswordChangeRequest):
    return request_password_change(payload.email)


@app.post("/auth/verify-and-change-password", response_model=PasswordResetResponse, tags=["auth"])
def verify_and_change_password_endpoint(payload: PasswordResetRequest):
    return verify_and_change_password(
        email=payload.email,
        verification_code=payload.verification_code,
        new_password=payload.new_password,
    )


@app.post("/auth/change-password", response_model=PasswordResetResponse, tags=["auth"])
def change_password_endpoint(payload: ChangePasswordRequest, current_user: Dict = Depends(get_current_user)):
    return change_password_authenticated(
        user_id=current_user["id"],
        old_password=payload.old_password,
        new_password=payload.new_password,
    )


@app.get("/auth/me", response_model=UserPublic, tags=["auth"])
def me(current_user: Dict = Depends(get_current_user)):
    return {
        "id": current_user["id"],
        "email": current_user["email"],
        "role": current_user["role"],
        "institution_id": current_user["institution_id"],
        "is_active": current_user["is_active"],
        "name": current_user["name"],
        "user_code": current_user["user_code"],
    }


@app.get("/known-students", response_model=KnownStudentsResponse, tags=["faces"])
def get_known_students(current_user: Dict = Depends(get_current_user)):
    students = refresh_known_students()
    return {"students": students, "count": len(students)}


def _require_ml_engines():
    if recognize_face is None or recognize_faces is None or analyze_emotion is None:
        raise HTTPException(
            status_code=503,
            detail="Recognition engines are unavailable. Install backend dependencies first.",
        )


def _attendance_error(exc: AttendanceServiceError):
    raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc


@app.post("/recognize-face", tags=["faces"])
async def recognize_face_endpoint(
    file: UploadFile = File(...),
    current_user: Dict = Depends(get_current_user),
):
    _require_ml_engines()
    image_bytes = await file.read()
    try:
        return recognize_face(image_bytes)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/analyze-attendance-frame", tags=["analytics"])
async def analyze_frame(
    file: UploadFile = File(...),
    lecture_id: str = Form(...),
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    _require_ml_engines()
    image_bytes = await file.read()
    try:
        recognition = recognize_faces(image_bytes)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        emotion_data = analyze_emotion(image_bytes)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    persisted = []
    skipped = []
    for match in recognition.get("recognized", []):
        try:
            record = mark_student_present(lecture_id, match["student_id"], emotion_data)
        except AttendanceServiceError as exc:
            _attendance_error(exc)
        if record is None:
            skipped.append(
                {
                    "student_id": match["student_id"],
                    "student_name": match.get("student_name", ""),
                    "reason": "recognized student is not enrolled in this lecture group",
                }
            )
            continue
        record["face_confidence"] = match.get("confidence")
        record["face_distance"] = match.get("distance")
        persisted.append(record)

    try:
        attendance = get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)

    return {
        "recognized": persisted,
        "skipped": skipped,
        "recognized_count": len(persisted),
        "recognized_any": bool(persisted),
        "unknown_count": recognition.get("unknown_count", 0),
        "total_faces": recognition.get("total_faces", 0),
        "lecture_id": lecture_id,
        "timestamp": datetime.now().isoformat(),
        "emotion": emotion_data,
        "attendance": attendance["attendance"],
        "present_count": attendance["present_count"],
        "absent_count": attendance["absent_count"],
        "expected_students": attendance["expected_students"],
        "session_status": attendance["session_status"],
    }


@app.post("/start-session/{lecture_id}", tags=["sessions"])
def start_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        upsert_lecture_session_start(lecture_id)
        return start_attendance_session(lecture_id, current_user.get("id"))
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.post("/stop-session/{lecture_id}", tags=["sessions"])
def stop_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return stop_attendance_session(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.get("/attendance/{lecture_id}", tags=["sessions"])
def attendance_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.get("/session-status/{lecture_id}", tags=["sessions"])
def get_session_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)
