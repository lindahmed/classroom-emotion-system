from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from face_registry import KNOWN_STUDENTS
from face_recognition_engine import recognize_face
from emotion_engine import analyze_emotion
from attendance_tracker import tracker
from pydantic import BaseModel
from typing import List
import uuid
from datetime import datetime

class KnownStudent(BaseModel):
    student_id: str
    student_name: str
    image_count: int
    folder: str

class KnownStudentsResponse(BaseModel):
    students: List[KnownStudent]
    count: int

app = FastAPI()

origins = ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get('/health')
def health():
    return {'status': 'ok'}

@app.get('/known-students', response_model=KnownStudentsResponse)
def get_known_students():
    return {
        'students': KNOWN_STUDENTS,
        'count': len(KNOWN_STUDENTS)
    }

@app.post('/recognize-face')
async def recognize_face_endpoint(file: UploadFile = File(...)):
    image_bytes = await file.read()
    result = recognize_face(image_bytes)
    return result

@app.post('/analyze-attendance-frame')
async def analyze_frame(file: UploadFile = File(...), lecture_id: str = Form(...)):
    image_bytes = await file.read()
    recognition = recognize_face(image_bytes)
    if not recognition['recognized']:
        return {'message': 'Face not recognized', 'recognized': False}
    emotion_data = analyze_emotion(image_bytes)
    tracker.update_attendance(lecture_id, recognition['student_id'])
    attendance_status = tracker.get_attendance_status(lecture_id, recognition['student_id'])
    record = {
        'record_id': str(uuid.uuid4()),
        'student_id': recognition['student_id'],
        'student_name': recognition['student_name'],
        'lecture_id': lecture_id,
        'timestamp': datetime.now().isoformat(),
        'emotion': emotion_data['emotion'],
        'confidence': emotion_data['confidence'],
        'engagement_score': emotion_data['engagement_score'],
        'focus_score': emotion_data['focus_score'],
        'attendance_status': attendance_status,
        'is_present': attendance_status in ['Present', 'Returned'],
        'left_room': attendance_status == 'Left',
        'absence_duration_minutes': tracker.sessions.get(lecture_id, {}).get(recognition['student_id'], {}).get('absence_duration', 0) / 60,
        'group': 'Group1'  # Placeholder
    }
    record['recognized'] = True
    return record

@app.post('/start-session/{lecture_id}')
def start_session(lecture_id: str):
    if lecture_id not in tracker.sessions:
        tracker.sessions[lecture_id] = {}
    return {'message': f'Session started for lecture {lecture_id}', 'status': 'started'}

@app.get('/session-status/{lecture_id}')
def get_session_status(lecture_id: str):
    return tracker.get_session_status(lecture_id)
