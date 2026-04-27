# EduPulse AI - Classroom Emotion Detection, Semester Dashboard, and Statistical Analysis System

**Comprehensive Project README and Implementation Specification**  
**Version:** 0.2.0 Enhanced Specification  
**Prototype Base:** v0.1.0 Mock Data Prototype  
**Status:** Prototype exists; this document defines the full project scope, UI, data model, analytics, optional features, and implementation requirements.  
**Primary Stack:** R Shiny, R statistical analysis, CSV storage, optional Python FastAPI + OpenCV/DeepFace backend.

---

## 1. Project Overview

EduPulse AI is an intelligent classroom emotion detection and statistical analysis system. The system analyzes students during lectures using artificial intelligence, stores structured emotion records, and uses R-based statistical analysis to help lecturers understand engagement, focus, confusion, boredom, attendance, and emotional trends across a full academic semester.

The system supports both real-time and pre-recorded lecture analysis. A webcam or uploaded lecture video can be processed by AI-based facial emotion recognition to classify student emotions such as:

- Happy
- Neutral
- Confused
- Bored

Each detected emotion is stored with metadata such as student ID, lecture ID, confidence score, timestamp, lecturer, course, group, academic week, attendance status, engagement score, and focus score.

The project currently has a functional R Shiny prototype using mock CSV data. The enhanced version described in this README keeps all existing prototype features and adds the complete project assignment requirements, optional requirements, and the new requested features:

- A lecturer dashboard showing the 16 weeks of the academic semester.
- The lecturer/doctor can select any week from the 16-week semester.
- The selected week displays the lecturer's schedule across all courses and all groups.
- The lecturer can select a specific lecture from the weekly schedule.
- The selected lecture opens the full lecture analysis already available in the prototype.
- A new Report tab displays all students in the selected lecture, all their detected emotions during the lecture, and the dominant emotion for each student.
- More graphs and visual analytics are added for weekly trends, student trends, emotion heatmaps, course/group comparison, lecturer clustering, and student-subject behavior clustering.

In this documentation, the words **lecturer** and **doctor** refer to the same academic user role.

---

## 2. Project Goals

The goal of EduPulse AI is to combine artificial intelligence and R statistical computing to understand classroom dynamics and improve the teaching-learning process.

The system should allow lecturers to answer questions such as:

- Which lectures had the highest confusion rate?
- Which week had the lowest engagement?
- Which students were frequently bored, confused, absent, or unfocused?
- Which course groups are struggling the most?
- Which lecture topics caused emotional spikes?
- Which students need academic support?
- Which lecturer/course combinations have strong or weak engagement patterns?
- How do student emotions change throughout a lecture?
- How do emotions vary across the 16-week semester?

---

## 3. Project Objectives

The system must satisfy the following objectives:

1. Design an automated AI-based system for detecting student emotions using facial recognition and facial emotion classification.
2. Capture real-time images through a webcam or process pre-recorded lecture videos.
3. Detect and classify emotions such as Happy, Neutral, Confused, and Bored.
4. Store emotion data in structured CSV datasets.
5. Store the required fields: student ID, time, emotion, confidence score, and lecture ID.
6. Extend the dataset with course, group, lecturer, academic week, timestamp, attendance, engagement, focus, and model metadata.
7. Analyze emotional trends across multiple lectures using R.
8. Evaluate student engagement by transforming emotions into quantitative engagement and focus measures.
9. Visualize emotional distributions and engagement trends using R tools such as dplyr, ggplot2, Plotly, DT, and Shiny.
10. Build a Shiny dashboard that allows lecturers to explore lecture-level, student-level, week-level, group-level, and semester-level analytics.
11. Provide a 16-week academic semester dashboard for lecturers.
12. Allow a lecturer to select a week and view their complete schedule for that week across all courses and groups.
13. Allow a lecturer to select a lecture and open the full lecture analysis for that lecture.
14. Provide a Report tab showing all students in the selected lecture, their emotion history, emotion counts, and dominant emotion.
15. Detect confusion spikes and notify lecturers when a high percentage of students are confused.
16. Cluster students and student-subject behavior based on engagement and focus.
17. Cluster lecturers based on engagement patterns across their lectures.
18. Optionally provide a real-time emotion notification dashboard to help lecturers improve lecture efficiency during the session.
19. Keep role-based access control for Admin, Lecturer, and Student users.
20. Support CSV export for filtered data, lecture reports, and analytics results.

---

## 4. Current Prototype Features to Preserve

The enhanced system must not remove the existing v0.1.0 prototype features. The following features must remain available and should be improved only when needed.

### 4.1 Authentication and Access Control

The current prototype includes:

- Role-based access control.
- Admin role.
- Lecturer role.
- Student role.
- Session management.
- Logout functionality.
- Data filtering based on user role.
- UI customization based on user role.

Required preservation and enhancement:

- Admin can view all data, all users, all courses, all groups, all lecturers, and all lectures.
- Lecturer/Doctor can view only their assigned courses, groups, schedules, lectures, and student emotion records.
- Student can view only their own personal data and summary.
- Role filtering must apply to dashboards, charts, tables, reports, clustering results, exports, and API responses.

### 4.2 Live Classroom Monitor

The current prototype includes a live monitoring dashboard with:

- Real-time engagement metrics.
- Focus metrics.
- Attendance metrics.
- Narrative insights generated from analytics.
- Time-series visualization of emotion trends.
- Emotion distribution analysis.

Required preservation and enhancement:

- The live monitor becomes lecture-context aware.
- When a lecturer selects a lecture from the weekly schedule, the Live Monitor tab must display analysis only for that lecture.
- Admin can choose any lecture.
- Student users see only their own records if the Live Monitor is available to them.

### 4.3 Confusion Detection

The current prototype includes:

- Automatic confusion spike detection.
- Spike threshold: more than 30% of students confused.
- Contextual alerts linked to lecture time/content.
- Sortable event table with timestamps.

Required preservation and enhancement:

- Confusion alerts must work for the selected lecture.
- Confusion alerts should also be summarized by week, course, group, and lecturer.
- Real-time notification behavior should be optional and configurable.

### 4.4 Student Cohort Clustering

The current prototype includes:

- K-means clustering on engagement and focus patterns.
- Identification of high-performing, average, and at-risk students.
- Admin/Lecturer view of student clusters.
- Student view of personal cluster assignment only.

Required preservation and enhancement:

- Clustering must support lecture-level clustering.
- Clustering must support course-level clustering.
- Clustering must support group-level clustering.
- Clustering must support semester-level clustering.
- Add student-subject behavior clustering based on each student's behavior in each course/subject.

### 4.5 Attendance and Focus Tracking

The current prototype includes:

- Student presence monitoring.
- Absence duration tracking.
- Focus score metrics by student.
- Sortable and filterable attendance table.

Required preservation and enhancement:

- Attendance and focus must be available for selected lecture, week, course, group, and semester.
- The Report tab should include attendance status and focus score for every student in the selected lecture.

### 4.6 Data and Reporting

The current prototype includes:

- Export filtered data as CSV.
- Timestamp-based export filenames.
- Role-based filtering in exports.
- Interactive DT tables with sorting and searching.

Required preservation and enhancement:

- Export selected lecture report.
- Export selected week schedule.
- Export lecture analytics summary.
- Export student emotion history for a selected lecture.
- Export clustering results.
- Export confusion alerts.
- Exports must respect role-based access.

### 4.7 Premium UI/UX

The current prototype includes:

- Dark theme.
- Purple accent color `#8b5cf6`.
- Responsive card-based layout.
- Bootstrap 5 framework.
- ggplot2 and Plotly-style visualizations.
- Inter font typography.

Required preservation and enhancement:

- Keep the premium dashboard look.
- Add semester/week navigation without breaking the existing layout.
- Add lecture cards and report tables using the same visual style.
- All new tabs must match the same dark theme and responsive card design.

---

## 5. User Roles and Permissions

### 5.1 Admin

Admin has full access to the system.

Admin can:

- View all lecturers.
- View all students.
- View all courses.
- View all groups.
- View all 16 academic weeks.
- View all lecture schedules.
- View all lecture analytics.
- View all reports.
- View all clustering outputs.
- View lecturer engagement clusters.
- Export all data.
- Manage or inspect system-wide settings in future versions.

### 5.2 Lecturer / Doctor

Lecturer is the main dashboard user.

Lecturer can:

- Log in with lecturer credentials.
- View the 16-week academic semester dashboard.
- Select any week from Week 1 to Week 16.
- See their schedule in the selected week across all assigned courses and all assigned groups.
- Select a lecture from the weekly schedule.
- View lecture-level analytics for the selected lecture.
- View Live Monitor analytics for the selected lecture.
- View Confusion Alerts for the selected lecture.
- View the Report tab for the selected lecture.
- View all students in that selected lecture.
- View each student's emotion records during the lecture.
- View each student's dominant emotion for the lecture.
- View group-level, course-level, and week-level trends for their assigned data.
- Export lecture report and analytics CSV files.

Lecturer cannot:

- View lectures that are not assigned to them.
- View data for courses or groups they do not teach.
- View private student data outside their assigned lectures.
- Modify Admin-only system configuration unless specifically allowed in a future release.

### 5.3 Student

Student has limited access.

Student can:

- Log in with student credentials.
- View personal emotional trend summary.
- View personal attendance and focus summary.
- View personal cluster assignment.
- View personal records only.

Student cannot:

- View other students' data.
- View lecturer-wide analytics.
- View class-level private reports.
- Export other users' data.

---

## 6. Main Lecturer Workflow

This is the most important workflow in the enhanced system.

### Step 1: Lecturer Login

The lecturer logs in using their lecturer account. The system identifies the lecturer ID and filters all data accordingly.

### Step 2: Open Lecturer Dashboard

After login, the lecturer lands on the **Lecturer Dashboard**.

The dashboard displays:

- Academic semester overview.
- 16 selectable week cards or buttons.
- Current selected week.
- Summary cards for the selected week.
- Weekly schedule table.
- Course and group filters.

### Step 3: Select a Week from the 16-Week Semester

The lecturer chooses one week from:

- Week 1
- Week 2
- Week 3
- Week 4
- Week 5
- Week 6
- Week 7
- Week 8
- Week 9
- Week 10
- Week 11
- Week 12
- Week 13
- Week 14
- Week 15
- Week 16

The system loads only the lecturer's schedule for that week.

### Step 4: View Weekly Schedule

The selected week shows all lectures assigned to the lecturer across:

- All assigned courses.
- All assigned groups.
- All assigned lecture rooms.
- All lecture days and time slots in the week.

Each lecture row/card should show:

- Lecture ID.
- Week number.
- Date.
- Day.
- Start time.
- End time.
- Course code.
- Course name.
- Group ID/name.
- Room or location.
- Lecturer name.
- Number of enrolled students.
- Attendance rate if analysis exists.
- Average engagement if analysis exists.
- Dominant class emotion if analysis exists.
- Status: scheduled, analyzed, missing data, or live.
- Action button: `View Analysis`.

### Step 5: Select a Lecture

When the lecturer clicks `View Analysis`, the system sets that lecture as the active lecture context.

All analysis tabs must update based on the selected lecture:

- Live Monitor.
- Report.
- Confusion Alerts.
- Graphs and Trends.
- Attendance.
- Cohort Clusters.
- Raw Data.

### Step 6: View Lecture Analysis

The selected lecture analysis must include the analytics already available in the prototype:

- Engagement score.
- Focus score.
- Attendance rate.
- Confusion rate.
- Number of students present.
- Active lecture name.
- Narrative insights.
- Emotion distribution.
- Time-series trends.
- Confusion alerts.
- Student cohort clustering.
- Attendance and focus table.

### Step 7: Open Report Tab

The lecturer opens the new **Report** tab.

The Report tab shows all students in the selected lecture and provides:

- Student ID.
- Student name.
- Course.
- Group.
- Lecture ID.
- Attendance status.
- Number of emotion records.
- All emotions detected during the lecture.
- Emotion sequence over time.
- Emotion count by type.
- Dominant emotion.
- Average confidence.
- Average engagement score.
- Average focus score.
- Confusion rate.
- Boredom rate.
- First detected emotion.
- Last detected emotion.
- Export button.

---

## 7. Dashboard Navigation Structure

The final dashboard should use the following navigation structure.

### 7.1 Common Navigation

Available after login:

1. Lecturer Dashboard
2. Live Monitor
3. Report
4. Graphs and Trends
5. Confusion Alerts
6. Cohort Clusters
7. Attendance
8. Raw Data / Exports
9. Settings

### 7.2 Admin Additional Navigation

Admin should additionally see:

1. System Overview
2. All Lecturers
3. Lecturer Engagement Clusters
4. All Courses and Groups
5. All Schedules
6. Data Health

### 7.3 Student Navigation

Student should see a restricted version:

1. My Summary
2. My Emotion Trends
3. My Attendance and Focus
4. My Cluster
5. Settings

### 7.4 Tab Visibility Matrix

| Tab / Feature | Admin | Lecturer / Doctor | Student |
|---|---:|---:|---:|
| Lecturer Dashboard | Yes | Yes | No |
| 16-Week Semester Selector | Yes | Yes | No |
| Weekly Schedule | Yes, all schedules | Yes, own schedules | No |
| Select Lecture | Yes | Yes, own lectures | No |
| Live Monitor | Yes | Yes, own lectures | Personal only if enabled |
| Report Tab | Yes | Yes, own lectures | No |
| Graphs and Trends | Yes | Yes, own lectures | Personal only |
| Confusion Alerts | Yes | Yes, own lectures | No |
| Cohort Clusters | Yes | Yes, own lectures | Own cluster only |
| Attendance | Yes | Yes, own lectures | Own record only |
| Raw Data Export | Yes | Yes, own lectures | Own data only |
| Lecturer Clustering | Yes | Optional read-only summary | No |
| Settings | Yes | Yes | Yes |

---

## 8. Detailed Page Specifications

## 8.1 Login Page

### Purpose

Authenticate users and determine their role.

### Inputs

- Username.
- Password.

### Outputs

- Logged-in session.
- Current user object.
- User role.
- User ID.
- Display name.
- Allowed data scope.

### Demo Credentials

These demo users are preserved from the prototype.

#### Admin

- Username: `admin`
- Password: `admin123`
- Access: all data and all analytics.

#### Lecturer

- Username: `lecturer`
- Password: `lecturer123`
- User ID: `T01`
- Access: assigned lectures only.

#### Student

- Username: `student`
- Password: `student123`
- User ID: `S001`
- Access: personal data only.

### Production Requirement

The current prototype uses hardcoded demo credentials. Production should replace this with:

- User table.
- Hashed passwords.
- Secure sessions.
- Role permissions.
- Optional database-backed authentication.

---

## 8.2 Lecturer Dashboard Page

### Purpose

Provide a semester-level entry point for lecturers. The lecturer selects one of 16 academic weeks, views their schedule for that week, then selects a lecture to analyze.

### Required UI Components

#### Header Area

Show:

- Lecturer name.
- Current academic semester.
- Current selected week.
- Number of assigned lectures in selected week.
- Average weekly engagement.
- Average weekly focus.
- Weekly attendance rate.
- Number of confusion alerts in selected week.

#### 16-Week Selector

Display 16 week cards/buttons:

- Week 1 through Week 16.
- Highlight selected week.
- Show week date range if available.
- Show quick status indicator:
  - No data.
  - Scheduled.
  - Partially analyzed.
  - Fully analyzed.
  - High confusion detected.

Recommended UI:

- A horizontal scrollable row of week chips, or
- A 4x4 grid of week cards.

Each week card can include:

```text
Week 5
Mar 10 - Mar 14
4 lectures
Avg engagement: 72%
```

#### Weekly Schedule Section

When a week is selected, show schedule table and cards.

Schedule table columns:

| Column | Description |
|---|---|
| Week | Academic week number from 1 to 16 |
| Date | Lecture date |
| Day | Day of week |
| Start Time | Lecture start time |
| End Time | Lecture end time |
| Course Code | Example: CS301 |
| Course Name | Example: Artificial Intelligence |
| Group | Group or section identifier |
| Room | Physical room or online link |
| Lecture ID | Unique lecture/session ID |
| Students | Number of enrolled students |
| Attendance | Attendance rate if available |
| Engagement | Average engagement if available |
| Dominant Emotion | Most common class emotion if available |
| Status | Scheduled, live, analyzed, missing data |
| Action | View Analysis button |

#### Filters

The lecturer dashboard should support:

- Week selection.
- Course filter.
- Group filter.
- Day filter.
- Status filter.

### Interaction Rules

- Selecting a week updates the schedule.
- Selecting a lecture sets `selected_lecture_id`.
- All analysis pages use `selected_lecture_id` as the active context.
- If no lecture is selected, analysis tabs show an instruction card: `Select a lecture from the Lecturer Dashboard to view analysis.`
- If the selected lecture has no emotion records, show an empty-state message and offer mock generation or upload instructions.

---

## 8.3 Live Monitor Page

### Purpose

Show real-time or lecture-level metrics for the selected lecture.

### Required Metrics

Show metric cards:

1. Average Engagement
2. Average Focus
3. Attendance Rate
4. Confusion Rate
5. Students Present
6. Active Lecture
7. Dominant Class Emotion
8. Boredom Rate
9. Average Confidence
10. Number of Emotion Records

### Required Charts

- Engagement, focus, and confusion timeline.
- Emotion distribution bar chart.
- Emotion distribution donut chart or pie chart.
- Confusion spike timeline.
- Attendance over lecture time.

### Narrative Insights

Generate rule-based insights such as:

- High engagement if average engagement is above 0.75.
- Low engagement warning if average engagement is below 0.45.
- High confusion warning if confusion rate exceeds 30%.
- Low attendance warning if attendance is below 90%.
- Boredom warning if boredom rate exceeds 25%.
- Strong focus indicator if focus is above 0.70.

### Required Filters

- Active lecture is inherited from Lecturer Dashboard.
- Optional filters:
  - Course.
  - Group.
  - Cohort.
  - Time range within lecture.
  - Emotion type.

---

## 8.4 Report Tab

### Purpose

Show a student-level report for the selected lecture. This is a new required feature.

### User

Visible to:

- Admin.
- Lecturer/Doctor for their assigned lectures.

Not visible to:

- Student users, except possibly a restricted personal version in future.

### Report Header

Show selected lecture context:

- Lecture ID.
- Lecture name/topic.
- Course code.
- Course name.
- Group.
- Lecturer.
- Week number.
- Date.
- Start time and end time.
- Number of students.
- Number of present students.
- Average engagement.
- Dominant class emotion.

### Main Report Table

The Report tab must show one row per student in the selected lecture.

Required columns:

| Column | Description |
|---|---|
| Student ID | Unique student identifier |
| Student Name | Student name |
| Course | Course code/name |
| Group | Group or section |
| Lecture ID | Selected lecture/session ID |
| Attendance Status | Present, Absent, Left Room, Partial |
| Emotion Records | Number of captured emotion records |
| All Emotions | Full emotion sequence or compact list |
| Emotion Timeline | Time-stamped emotions, e.g. `10:05 Neutral -> 10:10 Confused` |
| Happy Count | Number of Happy detections |
| Neutral Count | Number of Neutral detections |
| Confused Count | Number of Confused detections |
| Bored Count | Number of Bored detections |
| Dominant Emotion | Most frequent emotion for the student in the lecture |
| Average Confidence | Mean model confidence for the student |
| Average Engagement | Mean engagement score |
| Average Focus | Mean focus score |
| Confusion Rate | Confused records / total records |
| Boredom Rate | Bored records / total records |
| First Emotion | First detected emotion in lecture |
| Last Emotion | Last detected emotion in lecture |
| Notes / Risk Flag | Optional generated status such as High Confusion or Low Focus |

### Dominant Emotion Rule

For each student:

1. Count emotion records in the selected lecture.
2. The dominant emotion is the emotion with the highest count.
3. If there is a tie, choose the emotion with the highest total confidence.
4. If there is still a tie, choose the latest emotion among the tied emotions.

### Report Table Features

The table must support:

- Search.
- Sort.
- Filter by emotion.
- Filter by attendance status.
- Filter by risk flag.
- Pagination.
- CSV export.
- Optional row expansion to show full time-stamped records.

### Report Summary Cards

Above the table, show:

- Total students.
- Present students.
- Absent students.
- Most common dominant emotion.
- Students with dominant Confused.
- Students with dominant Bored.
- Average confidence.
- Average engagement.
- Average focus.

### Report Graphs

The Report tab should include:

1. Dominant emotion count by student.
2. Dominant emotion distribution for the lecture.
3. Student confusion rate bar chart.
4. Student boredom rate bar chart.
5. Student engagement ranking chart.
6. Student focus ranking chart.
7. Student emotion timeline heatmap.

---

## 8.5 Graphs and Trends Tab

### Purpose

Add more visual analytics beyond the original prototype.

### Required Graphs

The system should include the following graphs. These can be grouped into sections.

#### Lecture-Level Graphs

| Graph | Purpose | Recommended Visualization |
|---|---|---|
| Emotion Distribution | Shows emotion frequency in selected lecture | Bar chart or donut chart |
| Engagement/Focus Timeline | Shows engagement and focus across lecture time | Line chart |
| Confusion Timeline | Shows confusion rate across lecture time | Line chart with threshold line |
| Boredom Timeline | Shows boredom rate across lecture time | Line chart |
| Confidence Distribution | Shows AI confidence quality | Histogram or density chart |
| Attendance Over Time | Shows present students across lecture time | Step/line chart |
| Emotion Heatmap by Time | Shows emotion intensity per time interval | Heatmap |
| Student Emotion Heatmap | Shows dominant emotion by student and time | Heatmap |

#### Student-Level Graphs

| Graph | Purpose | Recommended Visualization |
|---|---|---|
| Dominant Emotion by Student | Shows each student's dominant emotion | Horizontal bar chart |
| Student Engagement Ranking | Ranks students by average engagement | Bar chart |
| Student Focus Ranking | Ranks students by average focus | Bar chart |
| Confusion Rate by Student | Identifies students frequently confused | Bar chart |
| Boredom Rate by Student | Identifies students frequently bored | Bar chart |
| Student Emotion Sequence | Shows one student's emotion over time | Timeline chart |
| Engagement vs Focus Scatter | Shows student behavior patterns | Scatter plot |

#### Week-Level Graphs

| Graph | Purpose | Recommended Visualization |
|---|---|---|
| Weekly Engagement Trend | Shows engagement across selected week | Line chart |
| Weekly Focus Trend | Shows focus across selected week | Line chart |
| Weekly Confusion Alerts | Shows number of confusion spikes by lecture | Bar chart |
| Schedule Analytics | Shows lectures per day/course/group | Calendar or bar chart |
| Dominant Emotion by Lecture | Compares lectures in selected week | Stacked bar chart |

#### Semester-Level Graphs

| Graph | Purpose | Recommended Visualization |
|---|---|---|
| Engagement Across 16 Weeks | Shows semester trend | Line chart |
| Focus Across 16 Weeks | Shows semester focus trend | Line chart |
| Confusion Across 16 Weeks | Shows difficult weeks/topics | Line chart |
| Emotion Distribution by Week | Compares emotions by week | Stacked bar chart |
| Attendance Across 16 Weeks | Shows attendance trend | Line chart |
| Course Engagement Comparison | Compares courses | Boxplot or grouped bar chart |
| Group Engagement Comparison | Compares groups | Boxplot or grouped bar chart |
| Lecturer Engagement Cluster Plot | Clusters lecturers by engagement | Scatter/PCA plot |
| Student-Subject Cluster Plot | Clusters student behavior by subject | Scatter/PCA plot |

### Graph Implementation Requirements

- Use `ggplot2` for static charts.
- Use `plotly` for interactive charts when useful.
- Use `DT` for tables.
- Use consistent dark theme styling.
- Add loading states for expensive charts.
- Add empty states when data is unavailable.
- All charts must respect role-based filtering.
- All charts must update when `selected_lecture_id`, week, course, group, or cohort changes.

---

## 8.6 Confusion Alerts Page

### Purpose

Identify moments when a high percentage of students are confused.

### Existing Rule

A confusion spike occurs when:

```text
Confusion Rate > 30%
```

Where:

```text
Confusion Rate = Number of Confused records / Number of present student records in the time interval
```

### Required Columns

| Column | Description |
|---|---|
| Lecture ID | Lecture/session identifier |
| Course | Course code/name |
| Group | Group/section |
| Week | Academic week |
| Time Minute | Minute within lecture |
| Timestamp | Actual timestamp |
| Confused Count | Number of confused detections |
| Present Count | Number of present detections |
| Confusion Rate | Percentage confused |
| Severity | Low, Medium, High |
| Suggested Message | Contextual alert for lecturer |

### Severity Levels

| Confusion Rate | Severity |
|---:|---|
| 30% to 45% | Medium |
| 45% to 60% | High |
| Above 60% | Critical |

### Optional Real-Time Notification

If enabled, the lecturer dashboard should show an alert card when confusion crosses the threshold during a live lecture.

Example message:

```text
High confusion detected at minute 25. Consider pausing, re-explaining, or asking a quick question.
```

---

## 8.7 Cohort Clusters Page

### Purpose

Group students by behavior patterns using clustering.

### Existing Prototype Clustering

The prototype uses K-means clustering with `k = 3` based on:

- Average engagement.
- Average focus.
- Confusion rate.
- Boredom rate.
- Total absence duration.

### Required Clusters

Default cluster labels:

| Cluster Type | Description |
|---|---|
| High Engagement / High Focus | Strong performance and attention |
| Moderate Engagement / Moderate Focus | Average behavior |
| Low Engagement / Low Focus | At-risk or needs support |

### Enhanced Clustering Requirements

The system should support:

1. Student clustering within selected lecture.
2. Student clustering within selected course.
3. Student clustering within selected group.
4. Student clustering across the full 16-week semester.
5. Student-subject behavior clustering.
6. Lecturer clustering based on engagement.

### Student-Subject Behavior Clustering

Each row should represent one student in one subject/course.

Features:

- Student ID.
- Course ID.
- Average engagement in that course.
- Average focus in that course.
- Confusion rate in that course.
- Boredom rate in that course.
- Attendance rate in that course.
- Number of lectures attended.
- Total absence duration.

Purpose:

- Identify subjects where a student is engaged.
- Identify subjects where a student is struggling.
- Compare student behavior across courses.

### Lecturer Engagement Clustering

Each row should represent one lecturer.

Features:

- Lecturer ID.
- Average engagement across lectures.
- Average focus across lectures.
- Average attendance rate.
- Average confusion rate.
- Average boredom rate.
- Number of lectures analyzed.
- Number of groups taught.
- Number of courses taught.

Purpose:

- Cluster lecturers based on engagement patterns.
- Identify courses or teaching contexts that may need support.
- Compare engagement across lecturers without exposing unnecessary student details.

---

## 8.8 Attendance Page

### Purpose

Track student presence and focus during lectures.

### Required Metrics

- Present count.
- Absent count.
- Attendance rate.
- Average absence duration.
- Students who left room.
- Average focus score.
- Low-focus students.

### Required Table Columns

| Column | Description |
|---|---|
| Student ID | Student identifier |
| Student Name | Student name |
| Lecture ID | Lecture/session identifier |
| Course | Course |
| Group | Group |
| Attendance Status | Present, Absent, Left Room, Partial |
| Is Present | Boolean present flag |
| Left Room | Boolean left-room flag |
| Absence Duration | Minutes absent |
| Average Focus | Focus score |
| Average Engagement | Engagement score |
| Last Seen | Last timestamp detected |

---

## 8.9 Raw Data and Exports Page

### Purpose

Allow authorized users to inspect and export filtered data.

### Export Types

- Filtered emotion records.
- Selected lecture report.
- Selected week schedule.
- Confusion alerts.
- Attendance report.
- Student clusters.
- Lecturer clusters.
- Student-subject behavior clusters.
- Graph data summaries.

### Export Requirements

- Use timestamped filenames.
- Use clear file naming.
- Respect role permissions.
- Export CSV as the required default format.

Example filenames:

```text
emotion_records_L001_2026-04-27_1430.csv
lecture_report_L001_2026-04-27_1430.csv
weekly_schedule_T01_week05_2026-04-27_1430.csv
confusion_alerts_L001_2026-04-27_1430.csv
```

---

## 8.10 Settings Page

### Purpose

Show session details, app details, and future configuration options.

### Required Content

- Username.
- Role.
- User ID.
- Display name.
- Active semester.
- Active selected week.
- Active selected lecture.
- App version.
- Prototype status.
- Logout button.

### Future Settings

- Confusion threshold.
- Real-time notification enable/disable.
- Export options.
- Theme customization.
- Data source selection: mock CSV, uploaded CSV, webcam, video, API.

---

## 9. Data Model

The assignment requires a minimum dataset structure:

| Student_ID | Time | Emotion | Confidence | Lecture_ID |
|---|---|---|---:|---|
| S01 | 10:05 | Happy | 0.85 | L1 |

The enhanced project should keep this required structure and extend it to support the prototype and new semester dashboard features.

---

## 9.1 Main Emotion Records CSV

File:

```text
data/emotion_records.csv
```

Required extended columns:

| Column | Type | Required | Description |
|---|---|---:|---|
| record_id | string | Yes | Unique record identifier |
| student_id | string | Yes | Student ID, e.g. S001 |
| student_name | string | Yes | Student display name |
| lecture_id | string | Yes | Lecture/session ID |
| lecture_name | string | Yes | Lecture title/topic |
| lecturer_id | string | Yes | Lecturer/doctor ID |
| lecturer_name | string | Yes | Lecturer/doctor name |
| course_id | string | Yes | Course identifier |
| course_code | string | Yes | Course code, e.g. CS301 |
| course_name | string | Yes | Course name |
| group_id | string | Yes | Group/section identifier |
| group_name | string | Yes | Group/section display name |
| academic_week | integer | Yes | Week number from 1 to 16 |
| timestamp | datetime | Yes | Full detection timestamp |
| time | string | Yes | Human-readable time, e.g. 10:05 |
| time_minute | integer | Yes | Minute inside lecture, e.g. 0 to 55 |
| emotion | string | Yes | Happy, Neutral, Confused, Bored |
| confidence | numeric | Yes | AI confidence from 0 to 1 |
| engagement_score | numeric | Yes | Calculated or stored score from 0 to 1 |
| focus_score | numeric | Yes | Calculated or stored score from 0 to 1 |
| attendance_status | string | Yes | Present, Absent, Left Room, Partial |
| is_present | boolean | Yes | TRUE/FALSE |
| left_room | boolean | Yes | TRUE/FALSE |
| absence_duration_minutes | numeric | Yes | Minutes absent |
| cohort | string | Optional | Cohort label, e.g. A, B, C |
| source_type | string | Yes | mock_video, webcam, uploaded_video, api |
| model_name | string | Yes | AI model used |
| frame_id | string | Optional | Frame identifier for video processing |
| face_id | string | Optional | Face tracking identifier |

### Example Row

```csv
record_id,student_id,student_name,lecture_id,lecture_name,lecturer_id,lecturer_name,course_id,course_code,course_name,group_id,group_name,academic_week,timestamp,time,time_minute,emotion,confidence,engagement_score,focus_score,attendance_status,is_present,left_room,absence_duration_minutes,cohort,source_type,model_name
R0001,S001,Student 1,L001,Intro to AI,T01,Dr. Ahmed,C001,CS301,Artificial Intelligence,G01,Group A,1,2026-02-09 10:05:00,10:05,5,Neutral,0.87,0.65,0.80,Present,TRUE,FALSE,0,A,mock_video,EduPulse_v1.0
```

---

## 9.2 Users CSV

File:

```text
data/users.csv
```

Columns:

| Column | Type | Description |
|---|---|---|
| user_id | string | Unique user ID |
| username | string | Login username |
| password_hash | string | Hashed password in production; plain demo only in prototype |
| role | string | admin, lecturer, student |
| display_name | string | User display name |
| student_id | string | Linked student ID if role is student |
| lecturer_id | string | Linked lecturer ID if role is lecturer |
| active | boolean | Account status |

---

## 9.3 Semester Weeks CSV

File:

```text
data/semester_weeks.csv
```

Columns:

| Column | Type | Description |
|---|---|---|
| semester_id | string | Semester identifier |
| academic_week | integer | Week number, 1 to 16 |
| week_label | string | Example: Week 1 |
| start_date | date | Week start date |
| end_date | date | Week end date |
| status | string | scheduled, active, completed |

---

## 9.4 Courses CSV

File:

```text
data/courses.csv
```

Columns:

| Column | Type | Description |
|---|---|---|
| course_id | string | Course ID |
| course_code | string | Course code |
| course_name | string | Course name |
| department | string | Department name |
| credit_hours | numeric | Optional course credit hours |

---

## 9.5 Groups CSV

File:

```text
data/groups.csv
```

Columns:

| Column | Type | Description |
|---|---|---|
| group_id | string | Group/section ID |
| group_name | string | Group display name |
| course_id | string | Related course |
| semester_id | string | Related semester |
| student_count | integer | Number of students |

---

## 9.6 Lecturer Course Assignments CSV

File:

```text
data/lecturer_course_assignments.csv
```

Columns:

| Column | Type | Description |
|---|---|---|
| assignment_id | string | Unique assignment ID |
| lecturer_id | string | Lecturer ID |
| course_id | string | Course ID |
| group_id | string | Group ID |
| semester_id | string | Semester ID |

---

## 9.7 Lecture Schedule CSV

File:

```text
data/lecture_schedule.csv
```

This file powers the 16-week lecturer dashboard.

Columns:

| Column | Type | Description |
|---|---|---|
| lecture_id | string | Unique lecture/session ID |
| lecture_name | string | Lecture title/topic |
| semester_id | string | Semester identifier |
| academic_week | integer | Week number from 1 to 16 |
| lecture_date | date | Lecture date |
| day_name | string | Monday, Tuesday, etc. |
| start_time | time | Lecture start time |
| end_time | time | Lecture end time |
| course_id | string | Course ID |
| course_code | string | Course code |
| course_name | string | Course name |
| group_id | string | Group ID |
| group_name | string | Group name |
| lecturer_id | string | Lecturer ID |
| lecturer_name | string | Lecturer name |
| room | string | Room/location |
| expected_students | integer | Enrolled/expected students |
| status | string | scheduled, live, analyzed, missing_data |

### Example Row

```csv
lecture_id,lecture_name,semester_id,academic_week,lecture_date,day_name,start_time,end_time,course_id,course_code,course_name,group_id,group_name,lecturer_id,lecturer_name,room,expected_students,status
L001,Introduction to AI,SPRING2026,1,2026-02-09,Monday,10:00,11:00,C001,CS301,Artificial Intelligence,G01,Group A,T01,Dr. Ahmed,Room 204,40,analyzed
```

---

## 9.8 Computed Lecture Report Dataset

This can be generated dynamically from `emotion_records.csv`, but it may also be cached as:

```text
data/lecture_student_reports.csv
```

Columns:

| Column | Description |
|---|---|
| lecture_id | Lecture ID |
| student_id | Student ID |
| student_name | Student name |
| course_id | Course ID |
| group_id | Group ID |
| academic_week | Week number |
| total_records | Number of emotion records |
| all_emotions | Compact emotion list |
| emotion_timeline | Time-stamped emotion sequence |
| happy_count | Count of Happy |
| neutral_count | Count of Neutral |
| confused_count | Count of Confused |
| bored_count | Count of Bored |
| dominant_emotion | Dominant emotion |
| avg_confidence | Average confidence |
| avg_engagement | Average engagement |
| avg_focus | Average focus |
| confusion_rate | Confusion rate |
| boredom_rate | Boredom rate |
| attendance_status | Attendance status |
| first_emotion | First emotion |
| last_emotion | Last emotion |
| risk_flag | Optional generated risk label |

---

## 10. Data Generation Rules for Mock Prototype

The existing prototype uses mock data. The enhanced prototype should continue to support mock data, but the generator should be expanded for a full 16-week semester.

### Existing Prototype Mock Rules to Preserve

- Mock dataset contains emotion records.
- Students are distributed across cohorts.
- Lectures have multiple emotion records per student.
- Emotion records are generated every few minutes during a lecture.
- Some lectures include confusion spikes.
- Cohort C has lower focus scores than other cohorts.
- Certain lectures can have enhanced engagement.
- Absences occur with a small random probability.
- Source type is `mock_video`.
- Model name can be `EduPulse_v1.0`.

### Enhanced Mock Rules

The mock generator should create:

- 16 semester weeks.
- Multiple courses.
- Multiple groups per course.
- Multiple lecturers.
- Weekly schedules for each lecturer.
- Lecture records linked to schedule rows.
- At least one analyzed lecture per week for demo purposes.
- Emotion records for each student in each analyzed lecture.
- Realistic variation between weeks, courses, groups, lecturers, and topics.

Recommended default mock size:

- 16 weeks.
- 3 lecturers.
- 3 to 5 courses.
- 2 to 4 groups.
- 40 to 120 students.
- 1 to 5 lectures per lecturer per week.
- 12 emotion samples per student per lecture, one every 5 minutes over a 60-minute lecture.

---

## 11. Emotion and Score Calculations

## 11.1 Emotion Categories

Default supported emotions:

| Emotion | Meaning |
|---|---|
| Happy | Student appears positive or engaged |
| Neutral | Student appears emotionally neutral |
| Confused | Student appears confused or uncertain |
| Bored | Student appears disengaged or bored |

The system may support additional emotions in future versions, but the required project emotions are Happy, Neutral, Bored, and Confused.

---

## 11.2 Engagement Score Calculation

Emotion records can contain an existing `engagement_score`. If it is not provided by the backend, calculate it from emotion and confidence.

Recommended base mapping:

| Emotion | Base Engagement |
|---|---:|
| Happy | 1.00 |
| Neutral | 0.65 |
| Confused | 0.35 |
| Bored | 0.20 |

Recommended formula:

```text
engagement_score = base_engagement(emotion) * confidence
```

Alternative:

```text
engagement_score = base_engagement(emotion)
```

Use the first formula if confidence is reliable. Use the second formula if confidence should only be used for quality filtering.

---

## 11.3 Focus Score Calculation

Recommended base mapping:

| Emotion / Status | Base Focus |
|---|---:|
| Neutral | 0.80 |
| Happy | 0.75 |
| Confused | 0.50 |
| Bored | 0.25 |
| Absent | 0.00 |

If the student is absent, `focus_score = 0`.

If the student is present:

```text
focus_score = base_focus(emotion) * confidence
```

---

## 11.4 Attendance Rate

```text
attendance_rate = present_students / expected_students
```

Or at record level:

```text
attendance_rate = count(is_present == TRUE) / total_records
```

For lecture-level reporting, prefer student-level attendance instead of raw record-level attendance.

---

## 11.5 Confusion Rate

```text
confusion_rate = count(emotion == "Confused") / total_emotion_records
```

For time intervals:

```text
interval_confusion_rate = confused_records_in_interval / present_records_in_interval
```

A confusion alert is triggered when:

```text
interval_confusion_rate > 0.30
```

---

## 11.6 Boredom Rate

```text
boredom_rate = count(emotion == "Bored") / total_emotion_records
```

---

## 11.7 Dominant Emotion

For a lecture:

```text
dominant_class_emotion = most frequent emotion in selected lecture
```

For a student inside a lecture:

```text
dominant_student_emotion = most frequent emotion for that student in selected lecture
```

Tie-breaking:

1. Highest count.
2. Highest sum of confidence.
3. Latest timestamp.

---

## 11.8 Risk Flag Logic

Recommended student risk flags for the Report tab:

| Condition | Risk Flag |
|---|---|
| Dominant emotion is Confused and confusion rate > 40% | High Confusion |
| Dominant emotion is Bored and boredom rate > 40% | High Boredom |
| Average focus < 0.40 | Low Focus |
| Average engagement < 0.40 | Low Engagement |
| Attendance status is Absent | Absent |
| Attendance status is Left Room or Partial | Partial Attendance |
| No condition matched | Normal |

---

## 12. Statistical Analysis Requirements in R

The project must use R for statistical analysis. The dashboard should use Shiny and R packages for analysis and visualization.

### Required R Analysis

1. Emotion frequency distribution.
2. Emotion variation across lectures.
3. Emotion variation across weeks.
4. Emotion variation across courses.
5. Emotion variation across groups.
6. Engagement score calculation.
7. Focus score calculation.
8. Attendance rate calculation.
9. Time-based emotional trends.
10. Confusion spike detection.
11. Student-level dominant emotion analysis.
12. Lecture-level dominant emotion analysis.
13. Weekly engagement trend analysis.
14. Semester-level engagement trend analysis.
15. Cluster lecturers based on engagement.
16. Cluster student-subject behavior based on engagement.
17. Exportable summaries and reports.

### Required R Packages

Core packages:

```r
install.packages(c(
  "shiny",
  "bslib",
  "dplyr",
  "ggplot2",
  "readr",
  "tidyr",
  "lubridate",
  "DT",
  "plotly",
  "scales",
  "stringr"
))
```

Optional packages:

```r
install.packages(c(
  "httr",
  "jsonlite",
  "shinycssloaders",
  "shinydashboard",
  "cluster",
  "factoextra"
))
```

---

## 13. Recommended R Helper Functions

The implementation should organize analytics into reusable helper functions.

### 13.1 Data Loading

```r
load_emotion_records <- function(path = "data/emotion_records.csv")
load_lecture_schedule <- function(path = "data/lecture_schedule.csv")
load_users <- function(path = "data/users.csv")
load_semester_weeks <- function(path = "data/semester_weeks.csv")
```

### 13.2 Role-Based Filtering

```r
filter_data_for_user <- function(data, current_user)
filter_schedule_for_user <- function(schedule, current_user)
filter_lectures_for_week <- function(schedule, week_number, current_user)
```

### 13.3 Lecture Analytics

```r
calculate_summary_metrics <- function(emotion_data)
generate_narrative_insights <- function(metrics)
detect_confusion_spikes <- function(emotion_data, threshold = 0.30)
calculate_emotion_distribution <- function(emotion_data)
calculate_time_trends <- function(emotion_data)
```

### 13.4 Report Tab

```r
calculate_student_lecture_report <- function(emotion_data, lecture_id) {
  emotion_data |>
    dplyr::filter(.data$lecture_id == lecture_id) |>
    dplyr::group_by(
      .data$student_id,
      .data$student_name,
      .data$course_id,
      .data$course_name,
      .data$group_id,
      .data$group_name,
      .data$lecture_id,
      .data$academic_week
    ) |>
    dplyr::summarise(
      total_records = dplyr::n(),
      all_emotions = paste(.data$emotion, collapse = " -> "),
      emotion_timeline = paste(.data$time, .data$emotion, collapse = " | "),
      happy_count = sum(.data$emotion == "Happy", na.rm = TRUE),
      neutral_count = sum(.data$emotion == "Neutral", na.rm = TRUE),
      confused_count = sum(.data$emotion == "Confused", na.rm = TRUE),
      bored_count = sum(.data$emotion == "Bored", na.rm = TRUE),
      avg_confidence = mean(.data$confidence, na.rm = TRUE),
      avg_engagement = mean(.data$engagement_score, na.rm = TRUE),
      avg_focus = mean(.data$focus_score, na.rm = TRUE),
      confusion_rate = confused_count / total_records,
      boredom_rate = bored_count / total_records,
      attendance_status = dplyr::first(.data$attendance_status),
      first_emotion = dplyr::first(.data$emotion),
      last_emotion = dplyr::last(.data$emotion),
      .groups = "drop"
    ) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      dominant_emotion = calculate_dominant_emotion_from_counts(
        happy_count,
        neutral_count,
        confused_count,
        bored_count
      ),
      risk_flag = calculate_student_risk_flag(
        dominant_emotion,
        confusion_rate,
        boredom_rate,
        avg_focus,
        avg_engagement,
        attendance_status
      )
    ) |>
    dplyr::ungroup()
}
```

### 13.5 Clustering

```r
cluster_students <- function(emotion_data, k = 3)
cluster_student_subject_behavior <- function(emotion_data, k = 3)
cluster_lecturers <- function(emotion_data, k = 3)
```

---

## 14. UI State Management Requirements

The Shiny app should use reactive state for selected week and selected lecture.

Recommended reactive values:

```r
rv <- reactiveValues(
  current_user = NULL,
  selected_week = 1,
  selected_lecture_id = NULL,
  selected_course_id = "All",
  selected_group_id = "All",
  selected_cohort = "All"
)
```

### Required Behavior

- Login sets `current_user`.
- Week click updates `selected_week`.
- Course filter updates `selected_course_id`.
- Group filter updates `selected_group_id`.
- Lecture selection updates `selected_lecture_id`.
- All tabs read from `selected_lecture_id`.
- If `selected_lecture_id` is NULL, analysis pages show an empty-state message.

---

## 15. Recommended Shiny Modules

To make implementation easier, split the app into modules.

```text
R/
├── generate_sample_data.R
├── data_helpers.R
├── analytics_helpers.R
├── ui_helpers.R
├── auth_helpers.R
├── schedule_helpers.R
├── report_helpers.R
├── graph_helpers.R
├── clustering_helpers.R
├── module_login.R
├── module_lecturer_dashboard.R
├── module_live_monitor.R
├── module_report_tab.R
├── module_graphs_trends.R
├── module_confusion_alerts.R
├── module_clusters.R
├── module_attendance.R
├── module_exports.R
└── module_settings.R
```

### Module Responsibilities

| Module | Responsibility |
|---|---|
| `module_login.R` | Login UI/server and session setup |
| `module_lecturer_dashboard.R` | 16-week selector and weekly schedule |
| `module_live_monitor.R` | Current lecture metrics and live charts |
| `module_report_tab.R` | Student-level lecture report |
| `module_graphs_trends.R` | Additional graphs and trends |
| `module_confusion_alerts.R` | Confusion spike detection and alerts |
| `module_clusters.R` | Student, lecturer, and student-subject clustering |
| `module_attendance.R` | Attendance and focus tracking |
| `module_exports.R` | CSV exports |
| `module_settings.R` | Session and app settings |

---

## 16. Architecture

## 16.1 Current Prototype Architecture

```text
Browser
  -> R Shiny App
      -> CSV Data Files
      -> R Analysis with dplyr, ggplot2, stats::kmeans
      -> Shiny UI Outputs: charts, cards, tables, exports
```

## 16.2 Enhanced R Shiny Architecture

```text
Browser
  -> R Shiny Dashboard
      -> Authentication and role filtering
      -> 16-week lecturer dashboard
      -> Weekly schedule selection
      -> Selected lecture context
      -> Lecture analytics
      -> Report tab
      -> Graphs and trends
      -> CSV exports
      -> CSV data storage
```

## 16.3 Optional Real-Time AI Architecture

```text
Camera / Uploaded Video
  -> Python Video Processing
      -> OpenCV frame extraction
      -> DeepFace or emotion API
      -> Face recognition / student matching
      -> Emotion classification
      -> Confidence scoring
      -> FastAPI backend
          -> CSV or SQLite storage
          -> R Shiny integration through httr or REST API
              -> Real-time dashboard updates
```

## 16.4 Optional Frontend Architecture

The assignment allows optional frontend frameworks.

Possible architecture:

```text
React or Streamlit Frontend
  -> FastAPI Backend
      -> OpenCV / DeepFace Emotion Detection
      -> CSV / SQLite Data Storage
      -> R Statistical Analysis Service or R scripts
      -> Dashboard Visualizations
```

For the current project, R Shiny remains the recommended main dashboard because the assignment explicitly requires R visualizations using Shiny.

---

## 17. Optional Python FastAPI Backend

The prototype roadmap includes a Python FastAPI backend for future real-time processing.

### Python Tools

Recommended Python dependencies:

```bash
pip install fastapi uvicorn opencv-python deepface pandas numpy python-multipart
```

### API Endpoints

#### Health Check

```http
GET /health
```

Response:

```json
{
  "status": "ok",
  "service": "edupulse-ai-backend"
}
```

#### Analyze Single Frame

```http
POST /analyze-frame
```

Purpose:

- Accept one webcam frame or image.
- Detect faces.
- Match student identity if possible.
- Classify emotion.
- Return emotion records.

#### Process Uploaded Video

```http
POST /process-video
```

Purpose:

- Accept a lecture video.
- Extract frames.
- Detect faces and emotions.
- Save records to CSV or database.
- Return processing summary.

#### Get Session Data

```http
GET /session-data/{lecture_id}
```

Purpose:

- Return all emotion records for a lecture.

#### Get Lecturer Schedule

```http
GET /lecturers/{lecturer_id}/schedule?week=5
```

Purpose:

- Return lecturer schedule for a selected academic week.

#### Get Lecture Analysis

```http
GET /lectures/{lecture_id}/analysis
```

Purpose:

- Return summary metrics and trends for one lecture.

#### Get Lecture Student Report

```http
GET /lectures/{lecture_id}/student-report
```

Purpose:

- Return all students in the lecture with their emotions and dominant emotion.

### R Shiny Integration with FastAPI

Use R package `httr` or `httr2`.

Example:

```r
library(httr)
library(jsonlite)

response <- GET("http://localhost:8000/lectures/L001/student-report")
report_data <- fromJSON(content(response, "text"))
```

---

## 18. Project Structure

Recommended full project structure:

```text
classroom-emotion-system/
├── app.R
├── README.md
├── DESIGN.md
├── classroom-emotion-system.Rproj
│
├── R/
│   ├── generate_sample_data.R
│   ├── data_helpers.R
│   ├── analytics_helpers.R
│   ├── ui_helpers.R
│   ├── auth_helpers.R
│   ├── schedule_helpers.R
│   ├── report_helpers.R
│   ├── graph_helpers.R
│   ├── clustering_helpers.R
│   ├── module_login.R
│   ├── module_lecturer_dashboard.R
│   ├── module_live_monitor.R
│   ├── module_report_tab.R
│   ├── module_graphs_trends.R
│   ├── module_confusion_alerts.R
│   ├── module_clusters.R
│   ├── module_attendance.R
│   ├── module_exports.R
│   └── module_settings.R
│
├── data/
│   ├── users.csv
│   ├── semester_weeks.csv
│   ├── courses.csv
│   ├── groups.csv
│   ├── lecturer_course_assignments.csv
│   ├── lecture_schedule.csv
│   ├── emotion_records.csv
│   ├── lecture_student_reports.csv
│   ├── student_clusters.csv
│   ├── lecturer_clusters.csv
│   └── student_subject_clusters.csv
│
├── www/
│   ├── custom.css
│   ├── logo.png
│   └── assets/
│
├── python_backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── emotion_detector.py
│   ├── video_processor.py
│   ├── face_matcher.py
│   ├── data_writer.py
│   └── README.md
│
├── exports/
│   └── generated_csv_exports/
│
└── tests/
    ├── test_data_helpers.R
    ├── test_analytics_helpers.R
    ├── test_report_helpers.R
    └── test_clustering_helpers.R
```

---

## 19. Quick Start

### 19.1 Prerequisites

Required:

- R 4.0 or newer.
- RStudio recommended.
- Git recommended.

Optional:

- Python 3.10 or newer.
- FastAPI backend dependencies.
- Webcam for real-time capture.
- Pre-recorded lecture videos.

---

### 19.2 Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/classroom-emotion-system.git
cd classroom-emotion-system
```

---

### 19.3 Install R Dependencies

```r
install.packages(c(
  "shiny",
  "bslib",
  "dplyr",
  "ggplot2",
  "readr",
  "tidyr",
  "lubridate",
  "DT",
  "plotly",
  "scales",
  "stringr"
))
```

Optional:

```r
install.packages(c(
  "httr",
  "jsonlite",
  "shinycssloaders",
  "cluster",
  "factoextra"
))
```

---

### 19.4 Run the Shiny App

From RStudio:

```r
shiny::runApp()
```

From command line:

```bash
Rscript app.R
```

The dashboard opens in the browser. The port may vary depending on the local environment.

---

## 20. Implementation Requirements for the New Lecturer Dashboard

### 20.1 Required Inputs

The dashboard needs:

- Logged-in lecturer ID.
- 16-week semester data.
- Lecture schedule data.
- Emotion records linked by `lecture_id`.
- Course and group data.

### 20.2 Required Outputs

The dashboard must render:

- 16 week selector.
- Weekly schedule for selected week.
- Lecture selection action.
- Active lecture context.
- Lecture analytics.
- Student report.

### 20.3 Logic

Pseudo-flow:

```text
current_user logs in
if current_user.role == lecturer:
    load schedules where lecturer_id == current_user.lecturer_id
    show weeks 1 to 16
    when selected_week changes:
        filter schedule by selected_week
        show all assigned lectures in that week
    when lecturer clicks View Analysis:
        set selected_lecture_id
        filter emotion_records by selected_lecture_id
        update Live Monitor, Report, Graphs, Alerts, Attendance, Clusters
```

---

## 21. Implementation Requirements for the Report Tab

### 21.1 Required Inputs

- Selected lecture ID.
- Filtered emotion records for that lecture.
- Student metadata.
- Attendance metadata.

### 21.2 Required Outputs

- Student-level report table.
- Dominant emotion for each student.
- All emotions for each student during the lecture.
- Emotion counts.
- Emotion sequence timeline.
- Engagement/focus summary.
- Export button.

### 21.3 Empty States

If no lecture is selected:

```text
Select a lecture from the Lecturer Dashboard to view the student report.
```

If selected lecture has no records:

```text
No emotion records are available for this lecture yet.
```

### 21.4 Report Aggregation Logic

For each student in selected lecture:

1. Filter records by `lecture_id` and `student_id`.
2. Sort by timestamp.
3. Count emotions.
4. Build emotion sequence.
5. Calculate dominant emotion.
6. Calculate engagement/focus averages.
7. Calculate confusion and boredom rates.
8. Determine attendance status.
9. Assign risk flag.
10. Display row in report table.

---

## 22. Implementation Requirements for More Graphs

### 22.1 Graph Filtering

Every graph must respond to:

- Selected lecture.
- Selected week.
- Selected course.
- Selected group.
- Selected cohort.
- User role.

### 22.2 Recommended Graph Layout

Use cards grouped into sections:

```text
Graphs and Trends
├── Lecture Snapshot
│   ├── Emotion Distribution
│   ├── Engagement/Focus Timeline
│   └── Confusion/Boredom Timeline
│
├── Student Insights
│   ├── Dominant Emotion by Student
│   ├── Student Emotion Heatmap
│   └── Engagement vs Focus Scatter
│
├── Weekly Trends
│   ├── Weekly Engagement Trend
│   ├── Dominant Emotion by Lecture
│   └── Confusion Alerts by Lecture
│
└── Semester Trends
    ├── Engagement Across 16 Weeks
    ├── Emotion Distribution by Week
    └── Course/Group Comparison
```

### 22.3 Graph Quality Requirements

- Include chart titles.
- Include axis labels.
- Use consistent colors for emotions.
- Use readable legends.
- Avoid overcrowded labels.
- Use hover details for interactive Plotly charts.
- Add download/export where useful.

Recommended emotion color mapping:

| Emotion | Suggested Color Meaning |
|---|---|
| Happy | Positive/accent color |
| Neutral | Muted/gray |
| Confused | Warning color |
| Bored | Low-energy/danger color |

The implementation can adapt colors to the dark theme.

---

## 23. Backend Data Processing Pipeline

### 23.1 Real-Time Webcam Pipeline

```text
Webcam frame
  -> capture image
  -> detect faces
  -> identify/match student if face recognition is enabled
  -> classify emotion
  -> calculate confidence
  -> assign timestamp and lecture_id
  -> store CSV row
  -> refresh dashboard
```

### 23.2 Pre-Recorded Video Pipeline

```text
Upload lecture video
  -> extract frames at configured interval
  -> detect faces in each frame
  -> identify students
  -> classify emotion
  -> save emotion records
  -> calculate lecture analytics
  -> update dashboard and reports
```

### 23.3 Required Stored Fields

At minimum, every detection must store:

- Student ID.
- Time.
- Emotion.
- Confidence.
- Lecture ID.

The full implementation should store the extended fields described in the data model.

---

## 24. Roadmap

This roadmap preserves the existing prototype roadmap and adds the new semester dashboard/report features.

### v0.1.0 - Existing Mock Data Prototype

Implemented in the early prototype:

- R Shiny dashboard.
- Dark premium UI.
- Role-based access.
- Mock CSV data.
- Live classroom monitor.
- Engagement metrics.
- Focus metrics.
- Attendance metrics.
- Emotion distribution.
- Time-series trends.
- Confusion alerts.
- Student clustering.
- Attendance and focus tracking.
- CSV export.
- Settings page.

### v0.2.0 - Semester Dashboard and Lecture Report

Required by this enhanced specification:

- 16-week academic semester dashboard.
- Lecturer week selector.
- Weekly lecturer schedule across all courses and groups.
- Lecture selection from schedule.
- Selected lecture context shared across all analytics tabs.
- New Report tab.
- Student-level emotion report for selected lecture.
- Dominant emotion per student.
- More graphs and trends.
- Extended mock data generator for 16 weeks.
- Extended schedule CSV data.

### v0.3.0 - Backend and Real-Time AI

Planned from prototype roadmap and assignment optional features:

- Python FastAPI server.
- OpenCV/DeepFace video processing pipeline.
- Real-time webcam emotion detection.
- Pre-recorded video upload and processing.
- SQLite or database persistence.
- REST API endpoints.
- R Shiny integration using `httr`.
- Optional real-time student emotion notification dashboard.

### v0.4.0 - Advanced Analytics

Planned analytics features:

- Predictive models for early intervention.
- Lecture effectiveness scoring.
- Engagement trend forecasting.
- Automated recommendations.
- Historical trend analysis.
- Student-subject behavior clustering.
- Lecturer engagement clustering.

### v0.5.0 - Production Ready

Planned production features:

- Proper database with user management.
- Secure authentication with hashed passwords and sessions.
- Multi-school or multi-department support.
- Admin dashboard for system management.
- Email or system notifications.
- Improved privacy controls.
- Deployment documentation.

---

## 25. Known Limitations of the Current Prototype

The current v0.1.0 prototype has the following limitations:

- Uses mock data only.
- No real video or webcam input yet.
- No persistent production database.
- No Python backend integration yet.
- Authentication is hardcoded for demo users.
- Data may be regenerated if mock CSV is deleted.
- No real-time streaming yet.
- Lecturer 16-week schedule dashboard is not yet implemented.
- Report tab with dominant student emotions is not yet implemented.
- Advanced semester-level graphs are not yet implemented.

This README describes how to upgrade the prototype into the complete project.

---

## 26. Acceptance Criteria

The project is complete when all required criteria below are satisfied.

### 26.1 Assignment Criteria

- The system detects student emotions using AI-based facial recognition or a mock equivalent for prototype demonstration.
- The system records student ID, time, emotion, confidence, and lecture ID.
- The system performs statistical analysis in R.
- The system calculates engagement scores.
- The system visualizes emotion distribution and engagement trends using Shiny.
- The system stores data in CSV files.
- Optional real-time notification dashboard is available or clearly planned.

### 26.2 Prototype Preservation Criteria

- Existing login works.
- Existing role-based access works.
- Existing Live Monitor works.
- Existing confusion alerts work.
- Existing clustering works.
- Existing attendance page works.
- Existing data export works.
- Existing dark premium UI is preserved.

### 26.3 New Feature Criteria

- Lecturer sees all 16 academic weeks.
- Lecturer can select any week.
- Selected week displays the lecturer's schedule for all assigned courses and groups.
- Lecturer can select a lecture from the weekly schedule.
- Selected lecture opens and controls the existing lecture analysis views.
- Report tab appears for lecturer and admin.
- Report tab shows all students in the selected lecture.
- Report tab shows all emotions detected for each student in the lecture.
- Report tab calculates and displays the dominant emotion for each student.
- Report tab includes emotion counts, engagement, focus, confidence, and attendance.
- Additional graphs are available for lecture, student, week, and semester analysis.
- All new views respect role-based filtering.

---

## 27. Security, Privacy, and Ethics Requirements

Because the system deals with student faces and emotional data, implementation should be privacy-aware.

Required considerations:

- Use the minimum data needed for the project.
- Restrict access by role.
- Do not expose student-level reports to unauthorized users.
- Avoid public display of private student emotion records.
- Use hashed passwords in production.
- Store sensitive data securely in production.
- Clearly label AI results as predictions, not guaranteed truth.
- Allow administrators to delete or anonymize records if required.
- Use emotion analytics to support learning, not punish students.

---

## 28. UI Style Guide

The enhanced system should keep the prototype's premium design.

### Theme

- Bootstrap 5.
- Dark theme.
- Primary accent: `#8b5cf6`.
- Inter font.
- Card-based layout.
- Responsive design.

### Recommended Visual Components

- Metric cards.
- Week cards.
- Lecture schedule table.
- Lecture cards.
- Status badges.
- Alert cards.
- Interactive tables.
- Plot cards.
- Empty-state cards.
- Export buttons.

### Status Badge Examples

| Status | Meaning |
|---|---|
| Scheduled | Lecture exists in schedule but has no emotion data yet |
| Live | Lecture is currently being monitored |
| Analyzed | Emotion records and analytics are available |
| Missing Data | Schedule exists but expected data is unavailable |
| High Confusion | Confusion threshold was exceeded |

---

## 29. Example User Stories

### Lecturer Week Selection

As a lecturer, I want to see the 16 weeks of the semester so that I can choose the week I want to analyze.

Acceptance:

- I can click Week 1 through Week 16.
- The selected week is highlighted.
- My schedule updates after selecting a week.

### Lecturer Schedule View

As a lecturer, I want to see all my lectures in a selected week across all courses and groups so that I can choose the lecture I want to analyze.

Acceptance:

- The table shows my courses only.
- The table shows all my groups.
- Each lecture has a View Analysis action.

### Lecture Analysis

As a lecturer, I want to select a lecture and see its analytics so that I can understand student engagement and emotions in that session.

Acceptance:

- Selecting a lecture updates the Live Monitor.
- Charts and metrics are filtered to that lecture.
- Confusion alerts show only for that lecture.

### Report Tab

As a lecturer, I want to see all students in the selected lecture with their emotions and dominant emotion so that I can identify students who were mostly confused, bored, neutral, or happy.

Acceptance:

- The report shows one row per student.
- Each row shows all detected emotions.
- Each row shows dominant emotion.
- I can sort, search, filter, and export the table.

### More Graphs

As a lecturer, I want more graphs for lecture, week, and semester trends so that I can understand patterns over time.

Acceptance:

- The system includes lecture-level graphs.
- The system includes week-level graphs.
- The system includes semester-level graphs.
- Graphs update based on selected lecture/week/course/group.

---

## 30. AI Implementation Prompt

Use the following prompt if giving this project to an AI coding assistant.

```text
Build or update an R Shiny project called EduPulse AI.

The project is a classroom emotion detection and statistical analysis dashboard. Keep all existing prototype features: role-based login for Admin/Lecturer/Student, dark premium UI, Live Monitor, confusion alerts, student clustering, attendance/focus tracking, CSV export, and settings.

Add a new Lecturer Dashboard. The dashboard must show the 16 weeks of the academic semester. A lecturer/doctor selects one week. After selecting a week, show the lecturer's schedule in that week across all assigned courses and groups. Each schedule row/card must include lecture ID, date, day, start/end time, course, group, room, status, attendance, engagement, dominant emotion, and a View Analysis button.

When the lecturer clicks View Analysis, set selected_lecture_id. All existing analysis tabs must show data only for that selected lecture.

Add a new Report tab for Admin and Lecturer. The Report tab must show all students in the selected lecture. For each student, show student ID, name, attendance status, all detected emotions during the lecture, a time-stamped emotion sequence, counts of Happy/Neutral/Confused/Bored, dominant emotion, average confidence, average engagement, average focus, confusion rate, boredom rate, first emotion, last emotion, and a risk flag. Dominant emotion is the most frequent emotion; break ties by highest total confidence, then latest timestamp.

Add more graphs: emotion distribution, engagement/focus timeline, confusion and boredom timelines, student emotion heatmap, dominant emotion by student, student engagement ranking, student focus ranking, confusion rate by student, weekly engagement trend, emotion distribution by week, attendance across 16 weeks, course/group comparison, lecturer engagement clusters, and student-subject behavior clusters.

Use CSV files for storage. Required CSVs include emotion_records.csv, lecture_schedule.csv, semester_weeks.csv, users.csv, courses.csv, groups.csv, and lecturer_course_assignments.csv. Extend generate_sample_data.R to create realistic 16-week mock data.

Use R packages shiny, bslib, dplyr, ggplot2, readr, tidyr, lubridate, DT, plotly, scales, and stringr. Keep the dark Bootstrap 5 theme with primary color #8b5cf6.

Optional backend: create a Python FastAPI service with endpoints /health, /analyze-frame, /process-video, /session-data/{lecture_id}, /lecturers/{lecturer_id}/schedule, /lectures/{lecture_id}/analysis, and /lectures/{lecture_id}/student-report. Use OpenCV or DeepFace for real emotion detection when replacing mock data.

Ensure role-based filtering everywhere. Admin sees all data. Lecturer sees only assigned lectures/courses/groups. Student sees only personal data.
```

---

## 31. Final Summary

EduPulse AI should evolve from a mock R Shiny prototype into a full classroom emotion detection and statistical analysis system. The enhanced project must combine:

- AI-based emotion detection.
- R statistical analysis.
- Shiny dashboard visualization.
- CSV data storage.
- Role-based access control.
- 16-week academic semester navigation.
- Lecturer weekly schedules across courses and groups.
- Per-lecture analytics.
- Student-level lecture reports.
- Dominant emotion analysis.
- Confusion alerts.
- Attendance and focus tracking.
- Student clustering.
- Lecturer clustering.
- Student-subject behavior clustering.
- Optional real-time notification dashboard.
- Optional Python FastAPI backend.

The most important new experience is the lecturer workflow:

```text
Login as Lecturer
  -> Select one of 16 semester weeks
  -> View weekly schedule across all courses and groups
  -> Select a lecture
  -> View existing lecture analytics
  -> Open Report tab
  -> See all students, all emotions, and dominant emotion per student
  -> Explore additional graphs and export reports
```

This README is designed to be implementation-ready and can be used directly as a guide for building the full UI, data model, analytics logic, and optional backend.
