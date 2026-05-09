# EduPulse AI Backend

This backend provides face recognition, emotion detection, attendance tracking, and real authentication for the EduPulse AI classroom emotion system.

## Setup

1. Install dependencies: pip install -r requirements.txt
2. Ensure you have known face folders in `backend/known_faces/` with format `S001_Name`.
3. Set auth env vars:
   - `AUTH_SECRET`
   - `TOKEN_EXPIRY_MINUTES` (optional, default 60)
4. (Optional) Set SMTP env vars for password reset emails:
   - `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`
4. Run the server: uvicorn main:app --reload

## Adding Team Photos

- Create folders in `backend/known_faces/` named `SXXX_Name` where `SXXX` is student ID and `Name` is the student's name.
- Place student photos (e.g., .jpg) in each folder.
- **Privacy Warning:** Do not commit real student photos to version control. Use placeholder images or anonymized data for development.

## Importing StudentPicsDataset.csv

Run from the repo root:

```bash
.venv/bin/python database/import_student_pics.py
```

This imports numeric student IDs, creates the `FACE101` course, `FACE_G01` group, `FR001`-`FR016` lectures, downloads Google Drive photos into `backend/known_faces/`, and records photo metadata in PostgreSQL.

## Testing

- Access interactive API docs at http://localhost:8000/docs
- Public endpoint: `/health`
- Auth endpoints: `/auth/signup`, `/auth/login`, `/auth/logout`, `/auth/me`, `/auth/change-password`
- Signup requires `email`, `password`, `role`, and `institution_id`; IDs must start with `S`, `L`, or `A` for student, lecturer, or admin accounts.
- Protected endpoints: `/known-students`, `/recognize-face`, `/analyze-attendance-frame`, `/start-session/{lecture_id}`, `/session-status/{lecture_id}`
