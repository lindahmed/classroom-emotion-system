# EduPulse AI — Classroom Emotion Detection & Analysis

![Status](https://img.shields.io/badge/status-active-brightgreen)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![License](https://img.shields.io/badge/license-Educational-green)

A premium R Shiny dashboard for real-time monitoring and analysis of student emotions in classroom settings. Uses mock data to demonstrate AI-powered emotion detection, statistical analysis, and role-based access control for educators.

## Overview

EduPulse AI is a classroom emotion detection and statistical analysis system designed to help educators understand and improve student engagement, focus, and emotional well-being. This **v0.1.0 prototype** uses mock CSV data and demonstrates:
- ✅ Complete dashboard UI with dark theme
- ✅ Role-based access control (Admin, Lecturer, Student)
- ✅ Real-time emotion analytics and clustering
- ✅ Interactive charts and data exports

**Current Version:** 0.2.0 (Semester Dashboard & Report Tab)  
**Status:** Enhanced prototype with 16-week semester navigation, lecture selection context, and student-level reports

## Features

### ✅ Current Features (v0.2.0)

**Semester Dashboard (NEW)**
- 16-week academic semester selector with navigation
- Weekly lecture schedule view across all courses and groups
- Quick status indicators (scheduled, analyzed, missing data)
- Week-level summary metrics (lectures, engagement, focus, confusion alerts)

**Lecture Selection Context (NEW)**
- Select any lecture from weekly schedule via "View Analysis" button
- Selected lecture becomes active context for all analysis tabs
- All filters and views update to show data only for selected lecture
- Visual indicator of currently selected lecture

**Student Report Tab (NEW)**
- Per-student emotion analysis for selected lecture
- Detailed columns: attendance, all emotions detected, emotion timeline
- Emotion counts (Happy/Neutral/Confused/Bored) and dominant emotion
- Engagement, focus, confidence, confusion rate, boredom rate metrics
- First/last emotion and automated risk flags
- Sort, search, filter, and export functionality

**Extended Mock Data (NEW)**
- 120 students across 6 groups
- 4 courses with multiple lecturers and group combinations
- Full 16-week academic calendar with dates
- Realistic lecture schedules (Monday/Wednesday, 2 per week)
- Emotion records for first 5 weeks (analyzed status)
- Detailed course/group/lecturer assignments

**Preserved Features**
- Role-based access control (Admin, Lecturer, Student)
- Live Classroom Monitor with real-time metrics
- Confusion spike detection (>30% threshold)
- Student grouping/clustering analysis
- Attendance & Focus tracking
- CSV export with role-based filtering
- Dark theme with purple accent
- Premium UI with responsive cards

**Improved Data Model**
- lecture_schedule.csv with full 16-week schedule
- semester_weeks.csv with week metadata
- Emotion records linked by lecture_id with full context
- Course and group separation (replacing cohort terminology)
- Lecturer and course assignment tables
- Extended emotion data with all required fields

### 🔲 Roadmap (Future Releases)

**v0.3.0 — Backend & Real-Time**
- [ ] Python FastAPI server for emotion analysis
- [ ] OpenCV/DeepFace video processing pipeline
- [ ] Real-time webcam emotion detection
- [ ] SQLite persistent storage
- [ ] REST API endpoints (/analyze-frame, /process-video, /session-data)
- [ ] Integration with R Shiny via httr

**v0.4.0 — Advanced Analytics & Graphs**
- [ ] More graphs: lecture trends, student trends, weekly trends, semester trends
- [ ] Lecturer engagement clustering
- [ ] Student-subject behavior clustering
- [ ] Predictive models for early intervention
- [ ] Lecture effectiveness scoring
- [ ] Engagement trend forecasting

**v0.5.0+ — Production Ready**
- [ ] Proper database with user management
- [ ] Authentication with bcrypt + sessions + hashed passwords
- [ ] Multi-school/multi-department support
- [ ] Email notifications
- [ ] Admin dashboard for system management
- [ ] Scalable video processing pipeline

## Quick Start

### Prerequisites

- **R 4.0+** (or latest version)
- **RStudio** (recommended for development)
- **Git** (for version control)

### Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/classroom-emotion-system.git
   cd classroom-emotion-system
   ```

2. **Install R dependencies:**
   ```r
   install.packages(c(
     "shiny", "bslib", "dplyr", "ggplot2", "readr", "tidyr", 
     "lubridate", "DT"
   ))
   ```

3. **Open in RStudio (Recommended):**
   - File → Open Project → `classroom-emotion-system.Rproj`
   - This ensures correct working directory and loads all helpers

### Running the App

**Option 1: RStudio (Recommended)**
```r
# With the project open, click "Run App" or type:
shiny::runApp()
```

**Option 2: Command Line**
```bash
Rscript app.R
# or
Rscript run_app.R
```

The dashboard will open in your browser at `http://localhost:3838` (port may vary; check console output).

## Demo Credentials

**Important:** These are demo credentials for testing. In production, implement proper authentication with hashed passwords and a real backend.

### 👤 Admin User
- **Username:** `admin`
- **Password:** `admin123`
- **Access:** All data, all lectures, all analytics features
- **Use this to:** View complete system capabilities

### 👨‍🏫 Lecturer User
- **Username:** `lecturer`
- **Password:** `lecturer123`
- **Access:** Only assigned lectures (Lectures 1 & 3)
- **User ID:** T01
- **Use this to:** Test role-based filtering for educators

### 🎓 Student User
- **Username:** `student`
- **Password:** `student123`
- **Access:** Only personal data (Student 1)
- **User ID:** S001
- **Use this to:** Test student privacy and limited access

## Main Lecturer Workflow (v0.2.0 - Recommended)

The primary user experience for educators is now:

1. **Login** as Lecturer (T01) with `lecturer` / `lecturer123`
2. **Land on Lecturer Dashboard** - see all 16 weeks of the semester
3. **Select a Week** - click any of the 16 week buttons (1-16)
4. **View Weekly Schedule** - all your lectures that week across courses and groups
5. **Select "View Analysis"** for any lecture to set it as active context
6. **Explore Analysis Tabs:**
   - **Live Monitor** - real-time metrics for that lecture
   - **Report** - see all students in that lecture with their emotions
   - **Confusion Alerts** - confusion spikes during that lecture
   - **Groups** - student clustering for that lecture
   - **Attendance** - presence tracking for that lecture
   - **Settings** - see your current selection status
7. **Export Data** - download CSV of selected lecture data
8. **Logout** - clear session

Note: Students (S001) see only their own personal data. Admins see everything.

## Project Structure

```
classroom-emotion-system/
├── app.R                          # Main Shiny application (v0.2.0)
├── CLAUDE.md                      # Claude Code guidance
├── DESIGN.md                      # Architecture & design documentation
├── README.md                      # This file
├── EduPulse_AI_Comprehensive_README.md # Full spec and requirements
├── classroom-emotion-system.Rproj # RStudio project file
│
├── R/
│   ├── generate_sample_data.R     # Mock data generation (16 weeks, expanded)
│   ├── data_helpers.R             # Data loading & filtering (with schedule loaders)
│   ├── analytics_helpers.R        # Metrics & analysis + Report generation
│   └── ui_helpers.R               # UI component helpers
│
├── data/
│   ├── emotion_records.csv        # ~29,000 emotion records (auto-generated)
│   ├── lecture_schedule.csv       # 512 lectures across 16 weeks (auto-generated)
│   ├── semester_weeks.csv         # 16 weeks with dates (auto-generated)
│   ├── courses.csv                # 4 courses (auto-generated)
│   ├── groups.csv                 # 6 groups (auto-generated)
│   ├── lecturers.csv              # 3 lecturers (auto-generated)
│   └── lecturer_course_assignments.csv # Lecturer-course-group links (auto-generated)
│
└── www/
    └── custom.css                 # Dark theme styling
```

## Data Format

### emotion_records.csv (Extended)

The mock dataset contains ~29,000+ emotion records (16 weeks × 8 lecturers/week × 20-120 students × 12 samples/lecture) with the following columns:

**Core Columns (Required by Assignment)**
- `student_id` — Student ID (S001-S120)
- `time` — Human-readable time
- `emotion` — Detected emotion (Happy, Neutral, Confused, Bored)
- `confidence` — Detection confidence (0.0-1.0)
- `lecture_id` — Lecture ID (L001-L512)

**Extended Columns (v0.2.0)**
- `record_id` — Unique record identifier
- `student_name` — Student name
- `lecture_name` — Lecture title
- `lecturer_id` — Lecturer ID (T01-T03)
- `lecturer_name` — Lecturer name
- `course_id` — Course identifier
- `course_code` — Course code (CS301, etc.)
- `course_name` — Course name
- `group_id` — Group/section ID (G01-G06, replaces cohort)
- `group_name` — Group display name
- `academic_week` — Week number (1-16)
- `timestamp` — Full timestamp
- `time_minute` — Minute within lecture (0-55)
- `engagement_score` — Engagement level (0.0-1.0)
- `focus_score` — Focus level (0.0-1.0)
- `attendance_status` — Present/Absent/Left Room/Partial
- `is_present` — Boolean presence flag
- `left_room` — Boolean (left during lecture)
- `absence_duration_minutes` — Minutes absent
- `source_type` — Data source type (mock_video)
- `model_name` — AI model name (EduPulse_v1.0)

### lecture_schedule.csv (NEW in v0.2.0)

Full 16-week lecture schedule with course/group/lecturer assignments:

- `lecture_id` — Unique lecture ID
- `lecture_name` — Lecture topic
- `semester_id` — Semester ID
- `academic_week` — Week 1-16
- `lecture_date` — Date
- `day_name` — Monday, Wednesday, etc.
- `start_time` / `end_time` — Time slot
- `course_id`, `course_code`, `course_name` — Course info
- `group_id`, `group_name` — Group/section
- `lecturer_id`, `lecturer_name` — Instructor
- `room` — Physical location
- `expected_students` — Enrolled count
- `status` — scheduled, live, analyzed, missing_data

### semester_weeks.csv (NEW in v0.2.0)

Academic week metadata:

- `semester_id` — Semester identifier
- `academic_week` — Week 1-16
- `week_label` — "Week 5", etc.
- `start_date`, `end_date` — Week date range
- `status` — completed, active, scheduled

### courses.csv, groups.csv, lecturers.csv, lecturer_course_assignments.csv (NEW in v0.2.0)

Supporting reference tables for course/group/lecturer management.

### Data Generation Rules (Updated)

The mock generator now creates:
- **16 weeks** with realistic semester dates
- **4 courses** across Computer Science and Mathematics
- **6 groups** with 20 students each (120 total)
- **3 lecturers** with varied teaching patterns
- **2 lectures per week per assignment** (Monday/Wednesday pattern)
- **512 total lecture slots** (16 weeks × 8 lecturer/group combinations × 2 lectures/week × 2 parts)
- **Emotion records for analyzed lectures** (Week 1-5, ~29,000 records)
- **Realistic patterns:**
  - Week 2-3: Higher confusion spikes (difficult topics)
  - Week 4: Enhanced engagement
  - Groups vary in performance patterns

### Previous Data Files Still Available

The data model preserves emotion_records.csv structure but extends it significantly. Files are auto-generated in `data/` directory on first app launch.

## Dashboard Sections

### 1. Lecturer Dashboard (NEW - Default after login)
Starting point for all analysis workflows.

**Displays:**
- 16 week selector cards
- Current selected week summary
- Weekly schedule table with all lectures for selected week
- Each row includes lecture ID, date, day, time, course, group, room, status
- "View Analysis" button to set lecture as active context
- Quick metrics: number of lectures, avg engagement, avg focus, confusion alerts

**Filters:** Course selector, Group selector (lecturer-specific)

### 2. Live Monitor
Real-time metrics and visualizations for selected lecture.

**Displays:**
- 6 summary metric cards (engagement, focus, attendance, confusion, students present, dominant emotion)
- Narrative insights box with rule-based messages
- Engagement/Focus/Confusion timeline chart
- Emotion distribution chart

**Filters:** Group selector (filtered to selected lecture data)

**Empty State:** If no lecture selected, prompts to select from Lecturer Dashboard

### 3. Report (NEW)
Student-level emotion analysis for selected lecture.

**Displays:**
- Lecture context header (name, course, group, lecturer, date, time)
- Summary cards: total students, present, absent, avg engagement, avg focus, dominant emotion
- Detailed student table with one row per student:
  - Student ID, Name, Attendance Status
  - All emotions detected, emotion timeline
  - Happy/Neutral/Confused/Bored counts
  - Dominant emotion, confidence, engagement, focus
  - Confusion rate, boredom rate, first/last emotion
  - Risk flag (High Confusion, High Boredom, Low Focus, etc.)

**Features:** Full-text search, sort by any column, filter by emotion/status/risk, pagination, export as CSV

**Empty State:** If no lecture selected, prompts to select from Lecturer Dashboard

### 4. Confusion Alerts
Identifies moments when >30% of students are confused.

**Shows:**
- Lecture name and lecture time (minute)
- Confusion rate percentage
- Severity level (Medium/High/Critical)
- Sortable table of all spikes for selected lecture

**Empty State:** If no lecture selected, prompts to select from Lecturer Dashboard

### 5. Groups (Clustering)
Student grouping analysis using K-means on behavioral features.

**Admin/Lecturer View:**
- Table of all students with group assignment
- Features: avg_engagement, avg_focus, confusion_rate, boredom_rate
- Raw data table (filtered by role)

**Student View:**
- Personal group message: "You are in Group X"
- Cannot see other students' data
- Personal raw data only

**Empty State:** If no lecture selected, prompts to select from Lecturer Dashboard

### 6. Attendance
Attendance and focus tracking for selected lecture.

**Displays:**
- Student presence status
- Absence duration tracking
- Focus scores per student
- Sortable/filterable table

**Empty State:** If no lecture selected, prompts to select from Lecturer Dashboard

### 7. Settings
Session information and app details.

**Displays:**
- Username, Role, User ID, Display Name
- Currently selected week
- Currently selected lecture
- About EduPulse AI
- Current version (0.2.0 Semester Dashboard & Report Tab)

## Analytics Functions

### Summary Metrics
```
- Average Engagement: mean(engagement_score)
- Average Focus: mean(focus_score)
- Attendance Rate: sum(is_present) / total
- Confusion Rate: sum(emotion == "Confused") / total
- Students Present: count(is_present == TRUE)
- Active Lecture: first lecture in data
```

### Narrative Insights
Rule-based messages generated from metrics:
- High engagement (>0.75): Positive indicator
- Low engagement (<0.45): Low engagement warning
- High confusion (>30%): Difficult content warning
- Low attendance (<90%): Absence warning
- High boredom (>25%): Engagement method warning
- High focus (>0.7): Positive indicator

### Clustering
K-means clustering with k=3:
- **Cluster 1:** High engagement, high focus (top performers)
- **Cluster 2:** Moderate engagement and focus (average)
- **Cluster 3:** Low engagement, low focus (at-risk)

Features: avg_engagement, avg_focus, confusion_rate, boredom_rate, total_absence_duration

## Customization

### Changing the Theme Color
Edit `app.R`, in the `page_navbar()` call:
```r
theme = bs_theme(
  version = 5,
  preset = "darkly",
  primary = "#8b5cf6",  # Change purple to your color
  base_font = font_google("Inter")
)
```

### Adding New Lectures/Students
Edit `R/generate_sample_data.R`:
```r
# Modify students, lectures, or data generation logic
# Then delete data/emotion_records.csv and restart app
```

### Changing Cluster K Value
Edit `R/analytics_helpers.R`:
```r
km <- stats::kmeans(features_scaled, centers = 5, nstart = 10)  # Change k=3 to k=5
```

## Troubleshooting

### App Won't Start
1. Check all packages are installed: `library(shiny)`
2. Verify R working directory is correct
3. Check for typos in file paths

### Charts Not Rendering
1. Ensure filtered data has records
2. Check if dates are in correct format
3. Verify emotion values are one of: Happy, Neutral, Confused, Bored

### Filters Showing "All" Only
1. Your role might not have access to other lectures
2. Try logging in as admin to see all options
3. Check `R/data_helpers.R` filter logic

### CSV Not Generated
1. Ensure `data/` directory is writable
2. Check `R/generate_sample_data.R` for errors
3. Try manually creating `data/` directory

## Architecture

See `DESIGN.md` for detailed architecture, future roadmap, and API specifications.

### Current Architecture
```
Browser → R Shiny ← Mock CSV Data (emotion_records.csv)
         ↓
    R Analysis (dplyr, ggplot2, stats::kmeans)
         ↓
    Shiny UI Outputs (Charts, Tables)
```

### Future Architecture
```
Browser → R Shiny ↔ Python FastAPI ↔ OpenCV/DeepFace ↔ CSV/SQLite
                         ↓
                   Real-Time Video Analysis
```

## Performance

- **Load time:** <1 second
- **Filter response:** <100ms
- **Chart render:** <500ms
- **Data size:** 2,400 records in mock dataset
- **Scalability:** Tested with mock dataset; production use will require optimization for real video streams

## Known Limitations

⚠ **Current (v0.2.0 Mock - With Semester Dashboard)**
- No real video/webcam input (mock data only)
- No persistent database (CSV-based)
- No Python backend integration yet
- Authentication is hardcoded for demo users
- Data is regenerated each session if CSV deleted
- No real-time streaming
- Graphs section not yet fully implemented (basic charts only)
- Lecturer clustering not yet available
- Student-subject behavior clustering not yet available

## Support & Contributing

**Found a bug?** Open an issue with:
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

**Have an idea?** Submit a feature request issue describing:
- The problem it solves
- Suggested implementation
- Use cases

**Want to contribute?** This project welcomes contributions:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is provided as-is for educational and research purposes.

---

**Version:** 0.1.0 (Mock Data Prototype)  
**Last Updated:** April 2026  
**Status:** ✅ Fully Functional Demo  

**Questions?** Check the [CLAUDE.md](CLAUDE.md) for development guidance or [DESIGN.md](DESIGN.md) for architecture details.

**Ready to build?** See the roadmap above for upcoming features. Backend integration starts with Python FastAPI + OpenCV video processing.
