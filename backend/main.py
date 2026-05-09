from datetime import datetime
import os
from typing import Dict, List, Literal, Optional
import uuid

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field

from .attendance_tracker import tracker
from .auth import (
    authenticate,
    create_account,
    get_current_user,
    require_roles,
    revoke_token,
    request_password_change,
    verify_and_change_password,
)
from .database import close_db, init_db
from .face_registry import KNOWN_STUDENTS

try:
    from .face_recognition_engine import recognize_face
    from .emotion_engine import analyze_emotion
except Exception:
    recognize_face = None
    analyze_emotion = None


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


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    print("\n" + "="*60)
    print("STARTUP: Initializing EduPulse AI backend...")
    print("="*60)
    try:
        if os.getenv("SKIP_DB_INIT", "false").lower() in {"1", "true", "yes"}:
            print("SKIP_DB_INIT is set, skipping database initialization")
            return
        print("STARTUP: Calling init_db()...")
        init_db()
        print("STARTUP: Database initialized successfully!")
    except Exception as e:
        print(f"STARTUP FAILED: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        raise
    print("="*60 + "\n")


@app.on_event("shutdown")
def on_shutdown():
    close_db()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/signup", response_model=UserPublic, status_code=201)
def signup(payload: SignupRequest):
    return create_account(
        email=payload.email,
        password=payload.password,
        role=payload.role,
        institution_id=payload.institution_id,
        full_name=payload.full_name,
    )


@app.post("/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest, request: Request):
    return authenticate(
        email=payload.email,
        password=payload.password,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


@app.post("/auth/logout", response_model=LogoutResponse)
def logout(current_user: Dict = Depends(get_current_user)):
    revoke_token(current_user["token"])
    return {"success": True, "message": "Logged out"}


@app.post("/auth/request-password-change", response_model=PasswordChangeResponse)
def request_password_change_endpoint(payload: PasswordChangeRequest):
    return request_password_change(payload.email)


@app.post("/auth/verify-and-change-password", response_model=PasswordResetResponse)
def verify_and_change_password_endpoint(payload: PasswordResetRequest):
    return verify_and_change_password(
        email=payload.email,
        verification_code=payload.verification_code,
        new_password=payload.new_password,
    )


@app.get("/auth/me", response_model=UserPublic)
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


@app.get("/known-students", response_model=KnownStudentsResponse)
def get_known_students(current_user: Dict = Depends(get_current_user)):
    return {"students": KNOWN_STUDENTS, "count": len(KNOWN_STUDENTS)}


def _require_ml_engines():
    if recognize_face is None or analyze_emotion is None:
        raise HTTPException(
            status_code=503,
            detail="Recognition engines are unavailable. Install backend dependencies first.",
        )


@app.post("/recognize-face")
async def recognize_face_endpoint(
    file: UploadFile = File(...),
    current_user: Dict = Depends(get_current_user),
):
    _require_ml_engines()
    image_bytes = await file.read()
    return recognize_face(image_bytes)


@app.post("/analyze-attendance-frame")
async def analyze_frame(
    file: UploadFile = File(...),
    lecture_id: str = Form(...),
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    _require_ml_engines()
    image_bytes = await file.read()
    recognition = recognize_face(image_bytes)
    if not recognition["recognized"]:
        return {"message": "Face not recognized", "recognized": False}

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
        "absence_duration_minutes": tracker.sessions.get(lecture_id, {})
        .get(recognition["student_id"], {})
        .get("absence_duration", 0)
        / 60,
        "group": "Group1",
        "recognized": True,
    }
    return record


@app.post("/start-session/{lecture_id}")
def start_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    if lecture_id not in tracker.sessions:
        tracker.sessions[lecture_id] = {}
    return {"message": f"Session started for lecture {lecture_id}", "status": "started"}


@app.get("/session-status/{lecture_id}")
def get_session_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    return tracker.get_session_status(lecture_id)
