# EduPulse AI Backend

This backend provides face recognition, emotion detection, and attendance tracking for the EduPulse AI classroom emotion system.

## Setup

1. Install dependencies: pip install -r requirements.txt
2. Ensure you have known face folders in ackend/known_faces/ with format S001_Name.
3. Run the server: uvicorn main:app --reload

## Adding Team Photos

- Create folders in ackend/known_faces/ named SXXX_Name where SXXX is student ID and Name is the student's name.
- Place student photos (e.g., .jpg) in each folder.
- **Privacy Warning:** Do not commit real student photos to version control. Use placeholder images or anonymized data for development.

## Testing

- Access interactive API docs at http://localhost:8000/docs
- Test endpoints: /health, /known-students, /recognize-face, /analyze-attendance-frame, /session-status/{lecture_id}
