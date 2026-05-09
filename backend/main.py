from datetime import datetime
import os
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
    create_account,
    get_current_user,
    require_roles,
    revoke_token,
    request_password_change,
    verify_and_change_password,
)
from .database import close_db, init_db
from .face_registry import refresh_known_students

try:
    from .face_recognition_engine import recognize_face, recognize_faces
    from .emotion_engine import analyze_emotion
except Exception:
    recognize_face = None
    recognize_faces = None
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


@app.post("/recognize-face")
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


@app.post("/analyze-attendance-frame")
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


@app.post("/start-session/{lecture_id}")
def start_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return start_attendance_session(lecture_id, current_user.get("id"))
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.post("/stop-session/{lecture_id}")
def stop_session(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return stop_attendance_session(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.get("/attendance/{lecture_id}")
def attendance_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)


@app.get("/session-status/{lecture_id}")
def get_session_status(
    lecture_id: str,
    current_user: Dict = Depends(require_roles("admin", "lecturer")),
):
    try:
        return get_attendance(lecture_id)
    except AttendanceServiceError as exc:
        _attendance_error(exc)
