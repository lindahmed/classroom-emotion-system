from datetime import datetime
from contextlib import asynccontextmanager
import os
import logging
from typing import Dict, List, Literal, Optional
import uuid

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field

from .attendance_service import AttendanceServiceError, get_attendance
from .attendance_tracker import tracker
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
from .face_registry import KNOWN_STUDENTS
from .storage import append_record, get_lecture_session_start, upsert_lecture_session_start

try:
    from .face_recognition_engine import recognize_face
    from .emotion_engine import analyze_emotion
except Exception:
    recognize_face = None
    analyze_emotion = None


logger = logging.getLogger(__name__)


def _cors_config():
    raw = os.getenv("EDUPULSE_CORS_ORIGINS", "").strip()
    if not raw:
        # Local dev: allow localhost/127.0.0.1 on any port (Shiny port varies).
        # Use allow_origins=["*"] for development to avoid preflight issues
        return {
            "allow_origins": ["http://localhost:3909", "http://127.0.0.1:3909", "http://localhost:3838", "http://127.0.0.1:3838"],
            "allow_origin_regex": r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
        }
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
    institution_id: str
    is_active: bool
    name: str
    user_code: str


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
        if analyze_emotion is not None:
            try:
                from .emotion_engine import warmup_emotion_model
                warmup_emotion_model()
            except Exception as exc:
                logger.warning("Emotion model warmup skipped: %s", exc)
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
    return {"students": KNOWN_STUDENTS, "count": len(KNOWN_STUDENTS)}


def _require_ml_engines():
    if recognize_face is None or analyze_emotion is None:
        raise HTTPException(
            status_code=503,
            detail="Recognition engines are unavailable. Install backend dependencies first.",
        )


@app.post("/recognize-face", tags=["faces"])
async def recognize_face_endpoint(
    file: UploadFile = File(...),
    current_user: Dict = Depends(get_current_user),
):
    _require_ml_engines()
    image_bytes = await file.read()
    return recognize_face(image_bytes)


@app.post("/analyze-attendance-frame", tags=["analytics"])
async def analyze_frame(
    file: UploadFile = File(...),
    lecture_id: str = Form(...),
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    _require_ml_engines()
    # Ensure we have a session start time for time_minute (survives restarts).
    # Also primes the in-process tracker timer so subsequent frames compute minutes consistently.
    try:
        if not get_lecture_session_start(lecture_id):
            upsert_lecture_session_start(lecture_id)
        tracker.start_session(lecture_id)
    except Exception:
        # In tests / CSV-only mode / missing DB schema: proceed without session start.
        pass
    image_bytes = await file.read()
    recognition = recognize_face(image_bytes)
    if not recognition["recognized"]:
        return {
            "message": "Face not recognized",
            "recognized": False,
            "session_active": True,
            "attendance_status": "Absent",
            "is_present": False,
            "left_room": False,
        }

    emotion_data = analyze_emotion(image_bytes)
    tracker.update_attendance(lecture_id, recognition["student_id"])
    attendance_status = tracker.get_attendance_status(lecture_id, recognition["student_id"])
    record = {
        "record_id": str(uuid.uuid4()),
        "student_id": recognition["student_id"],
        "student_name": recognition["student_name"],
        "lecture_id": lecture_id,
        "timestamp": datetime.now().isoformat(),
        "emotion": emotion_data["emotion"],
        "confidence": emotion_data["confidence"],
        "engagement_score": emotion_data["engagement_score"],
        "focus_score": emotion_data["focus_score"],
        "attendance_status": attendance_status,
        "is_present": attendance_status in ["Present", "Returned"],
        "left_room": attendance_status == "Left",
        "absence_duration_minutes": tracker.get_absence_minutes(lecture_id, recognition["student_id"]),
        "recognized": True,
    }

    # Persist emotion + attendance to PostgreSQL (core system behavior).
    # `append_record` will map student_id/lecture_id to student_code/lecture_code as needed.
    db_record_id = append_record(
        {
            "student_id": record["student_id"],
            "lecture_id": record["lecture_id"],
            "recorded_at": datetime.now(),
            "time_minute": tracker.get_time_minute(lecture_id),
            "emotion": record["emotion"],
            "confidence": record["confidence"],
            "engagement_score": record["engagement_score"],
            "focus_score": record["focus_score"],
            "is_present": record["is_present"],
            "left_room": record["left_room"],
            "absence_duration_minutes": int(record["absence_duration_minutes"] or 0),
            "source_type": "live_camera",
            "model_name": f"EduPulse_v1.0-{emotion_data.get('engine', 'unknown')}",
        }
    )
    record["db_record_id"] = db_record_id
    return record


@app.post("/start-session/{lecture_id}", tags=["sessions"])
def start_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    upsert_lecture_session_start(lecture_id)
    tracker.start_session(lecture_id)
    return {"message": f"Session started for lecture {lecture_id}", "status": "started"}


@app.post("/stop-session/{lecture_id}", tags=["sessions"])
def stop_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    # Stop local session timer/caches; DB end tracking can be added later if needed.
    try:
        tracker.stop_session(lecture_id)
    except Exception:
        pass
    return {"message": f"Session stopped for lecture {lecture_id}", "status": "stopped"}


@app.get("/session-status/{lecture_id}", tags=["sessions"])
def get_session_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    return tracker.get_session_status(lecture_id)


@app.get("/attendance/{lecture_id}", tags=["sessions"])
def attendance_snapshot(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    """R Shiny live monitor calls this to refresh roster counts (group + attendance_records)."""
    try:
        return get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
