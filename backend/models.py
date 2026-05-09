"""
models.py — Pydantic models for EduPulse API request/response validation
"""

from datetime import datetime, date, time
from typing import Optional, List
from pydantic import BaseModel, EmailStr, Field
from enum import Enum


# Enums matching PostgreSQL types
class UserRole(str, Enum):
    admin = "admin"
    lecturer = "lecturer"
    student = "student"


class EmotionType(str, Enum):
    happy = "Happy"
    neutral = "Neutral"
    confused = "Confused"
    bored = "Bored"


class LectureStatus(str, Enum):
    scheduled = "scheduled"
    in_progress = "in_progress"
    analyzed = "analyzed"
    cancelled = "cancelled"


class SourceType(str, Enum):
    mock_video = "mock_video"
    live_camera = "live_camera"
    video_file = "video_file"
    manual = "manual"


# Request models
class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    role: UserRole
    institution_id: str = Field(..., min_length=2)
    full_name: Optional[str] = None


class EmotionRecordCreate(BaseModel):
    student_code: str = Field(..., alias="student_id")
    lecture_code: str = Field(..., alias="lecture_id")
    recorded_at: datetime
    time_minute: int = 0
    emotion: EmotionType
    confidence: float = Field(..., ge=0, le=1)
    engagement_score: float = Field(..., ge=0, le=1)
    focus_score: float = Field(..., ge=0, le=1)
    is_present: bool = True
    left_room: bool = False
    absence_duration_minutes: int = 0
    source: SourceType = SourceType.live_camera
    model_name: str = "EduPulse_v1.0"

    class Config:
        populate_by_name = True


class AttendanceUpsert(BaseModel):
    student_code: str
    lecture_code: str
    status: str = "Present"
    total_absence_minutes: int = 0


class StartSessionRequest(BaseModel):
    lecture_code: str


# Response models
class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    expires_in: int
    user: dict


class EmotionRecordResponse(BaseModel):
    record_id: int
    student_id: str
    student_name: str
    lecture_id: str
    lecture_name: str
    timestamp: datetime
    emotion: str
    confidence: float
    engagement_score: float
    focus_score: float
    attendance_status: str
    is_present: bool


class LectureSummaryResponse(BaseModel):
    lecture_id: int
    lecture_code: str
    lecture_name: str
    academic_week: int
    course_code: str
    lecturer_name: str
    total_students: int
    present_count: int
    avg_engagement: Optional[float]
    avg_focus: Optional[float]
    confusion_rate: Optional[float]
    dominant_emotion: Optional[str]


class StudentEngagementResponse(BaseModel):
    student_code: str
    student_name: str
    group_code: str
    course_code: str
    total_records: int
    avg_engagement: float
    avg_focus: float
    confusion_rate: float
    boredom_rate: float


class FaceRecognitionResult(BaseModel):
    student_code: str
    student_name: str
    confidence: float
    emotion: Optional[EmotionType] = None
    engagement_score: Optional[float] = None
    focus_score: Optional[float] = None


class AttendanceFrameResult(BaseModel):
    recognized: List[FaceRecognitionResult]
    total_faces: int
    timestamp: datetime
    lecture_code: Optional[str] = None


class AlertResponse(BaseModel):
    alert_id: int
    alert_type: str
    severity: str
    title: str
    message: str
    time_minute: Optional[int]
    actual_value: Optional[float]
    created_at: datetime
    is_read: bool
