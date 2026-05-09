# db_queries.R — Database query functions for EduPulse AI
# Replaces all CSV-reading functions with PostgreSQL view queries

source("R/db_connect.R")
source("R/csv_backup.R")

#' Load emotion records (replaces readr::read_csv("data/emotion_records.csv"))
#' Returns a tibble with the same column names as the original CSV
load_emotion_data <- function(semester_id = "SPRING2026",
                               academic_week = NULL,
                               lecture_code = NULL,
                               student_code = NULL) {
  query <- "SELECT * FROM vw_emotion_records_flat WHERE 1=1"
  params <- list()

  if (!is.null(semester_id)) {
    query <- paste0(query, " AND lecture_id IN (SELECT lecture_code FROM lectures WHERE semester_id = $", length(params) + 1, ")")
    params <- c(params, semester_id)
  }

  if (!is.null(academic_week)) {
    query <- paste0(query, " AND academic_week = $", length(params) + 1)
    params <- c(params, as.integer(academic_week))
  }

  if (!is.null(lecture_code)) {
    query <- paste0(query, " AND lecture_id = $", length(params) + 1)
    params <- c(params, lecture_code)
  }

  if (!is.null(student_code)) {
    query <- paste0(query, " AND student_id = $", length(params) + 1)
    params <- c(params, student_code)
  }

  db_query(query, params)
}

#' Load lecture schedule (replaces readr::read_csv("data/lecture_schedule.csv"))
load_lecture_schedule <- function(semester_id = "SPRING2026") {
  db_query(
    "SELECT * FROM vw_lecture_schedule WHERE semester_id = $1 ORDER BY academic_week, lecture_date, start_time",
    list(semester_id)
  )
}

#' Load semester weeks
load_semester_weeks <- function(semester_id = "SPRING2026") {
  db_query(
    "SELECT semester_id, academic_week, week_label, start_date, end_date, status::text AS status FROM semester_weeks WHERE semester_id = $1 ORDER BY academic_week",
    list(semester_id)
  )
}

#' Load courses
load_courses <- function() {
  db_query("SELECT course_id, course_code, course_name, department_id, credit_hours FROM courses ORDER BY course_code")
}

#' Load rooms
load_rooms <- function() {
  db_query(
    "SELECT room_id, room_number, building, capacity FROM rooms ORDER BY room_number",
    list()
  )
}

#' Get active semester_id
get_active_semester_id <- function(default = "SPRING2026") {
  res <- db_query(
    "SELECT semester_id FROM semesters WHERE is_active = TRUE ORDER BY start_date DESC LIMIT 1",
    list()
  )
  if (nrow(res) > 0) as.character(res$semester_id[1]) else default
}

#' Load student groups
load_groups <- function(semester_id = "SPRING2026") {
  db_query(
    "SELECT sg.group_id, sg.group_code, sg.group_name, sg.course_id, sg.semester_id,
            (SELECT COUNT(*) FROM group_memberships gm WHERE gm.group_id = sg.group_id) AS student_count
     FROM student_groups sg WHERE sg.semester_id = $1 ORDER BY sg.group_code",
    list(semester_id)
  )
}

#' Get students in a specific group
get_students_in_group <- function(group_id) {
  db_query(
    "SELECT s.student_id, s.student_code, s.full_name AS student_name
     FROM students s
     JOIN group_memberships gm ON s.student_id = gm.student_id
     WHERE gm.group_id = $1
     ORDER BY s.student_code",
    list(as.integer(group_id))
  )
}

#' Get lectures for a specific lecturer
get_lectures_for_lecturer <- function(lecturer_code, semester_id = "SPRING2026") {
  db_query(
    "SELECT * FROM vw_lecture_schedule
     WHERE lecturer_id = $1 AND semester_id = $2
     ORDER BY academic_week, lecture_date, start_time",
    list(lecturer_code, semester_id)
  )
}

#' Get a student's own data
get_student_own_data <- function(student_code, semester_id = "SPRING2026") {
  db_query(
    "SELECT * FROM vw_emotion_records_flat
     WHERE student_id = $1
     ORDER BY timestamp",
    list(student_code)
  )
}

#' Get lecture summary metrics (dashboard cards)
get_lecture_summary <- function(lecture_code = NULL, semester_id = "SPRING2026", academic_week = NULL) {
  query <- "SELECT * FROM vw_lecture_summary WHERE 1=1"
  params <- list()

  if (!is.null(lecture_code)) {
    query <- paste0(query, " AND lecture_code = $", length(params) + 1)
    params <- c(params, lecture_code)
  }

  if (!is.null(academic_week)) {
    query <- paste0(query, " AND academic_week = $", length(params) + 1)
    params <- c(params, as.integer(academic_week))
  }

  db_query(query, params)
}

#' Get confusion spikes for a lecture
get_confusion_spikes <- function(lecture_code = NULL) {
  query <- "SELECT * FROM vw_confusion_spikes WHERE 1=1"
  params <- list()

  if (!is.null(lecture_code)) {
    query <- paste0(query, " AND lecture_id = (SELECT lecture_id FROM lectures WHERE lecture_code = $", length(params) + 1, ")")
    params <- c(params, lecture_code)
  }

  db_query(query, params)
}

#' Get student engagement data (for clustering/reports)
get_student_engagement <- function(semester_id = "SPRING2026") {
  db_query("SELECT * FROM vw_student_engagement ORDER BY student_code")
}

#' Get system setting value
get_setting <- function(key) {
  result <- db_query(
    "SELECT setting_value FROM system_settings WHERE setting_key = $1",
    list(key)
  )
  if (nrow(result) > 0) result$setting_value[1] else NULL
}

#' Insert an emotion record (DB + CSV backup)
insert_emotion_record <- function(student_code, lecture_code, recorded_at, emotion,
                                   confidence, engagement_score, focus_score,
                                   is_present = TRUE, left_room = FALSE,
                                   absence_duration_minutes = 0,
                                   source = "live_camera", model_name = "EduPulse_v1.0") {
  rows <- db_execute(
    "INSERT INTO emotion_records (student_id, lecture_id, recorded_at, time_minute,
       emotion, confidence, engagement_score, focus_score, is_present, left_room,
       absence_duration_minutes, source, model_name)
     VALUES (
       (SELECT student_id FROM students WHERE student_code = $1),
       (SELECT lecture_id FROM lectures WHERE lecture_code = $2),
       $3, 0, $4, $5, $6, $7, $8, $9, $10, $11, $12
     )",
    list(student_code, lecture_code, recorded_at, emotion,
         confidence, engagement_score, focus_score,
         is_present, left_room, as.integer(absence_duration_minutes),
         source, model_name)
  )

  # CSV backup (best-effort, must not fail the DB write)
  tryCatch({
    csv_append_row(data.frame(
      student_code = student_code,
      lecture_code = lecture_code,
      recorded_at  = recorded_at,
      emotion      = emotion,
      confidence   = confidence,
      engagement_score = engagement_score,
      focus_score  = focus_score,
      is_present   = is_present,
      left_room    = left_room,
      absence_duration_minutes = as.integer(absence_duration_minutes),
      source       = source,
      model_name   = model_name,
      stringsAsFactors = FALSE
    ), "data/emotion_records_raw.csv")
  }, error = function(e) {
    message(paste("CSV backup for emotion record failed:", e$message))
  })

  rows
}

#' Upsert an attendance record (DB + CSV backup)
upsert_attendance_record <- function(student_code, lecture_code, status = "Present") {
  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  rows <- db_execute(
    "INSERT INTO attendance_records (student_id, lecture_id, status, first_seen_at, last_seen_at, total_absence_minutes, attendance_pct)
     VALUES (
       (SELECT student_id FROM students WHERE student_code = $1),
       (SELECT lecture_id FROM lectures WHERE lecture_code = $2),
       $3::attendance_status_type, $4, $4, 0, 100.0
     )
     ON CONFLICT (student_id, lecture_id) DO UPDATE SET
       status = EXCLUDED.status,
       last_seen_at = EXCLUDED.last_seen_at,
       updated_at = NOW()",
    list(student_code, lecture_code, status, now)
  )

  # CSV backup
  tryCatch({
    csv_append_row(data.frame(
      student_code   = student_code,
      lecture_code   = lecture_code,
      status         = status,
      last_seen_at   = now,
      stringsAsFactors = FALSE
    ), "data/attendance_records.csv")
  }, error = function(e) {
    message(paste("CSV backup for attendance failed:", e$message))
  })

  rows
}

#' Check confusion rate and create alert if >30% (DB + CSV backup)
check_and_create_confusion_alert <- function(lecture_code, threshold = 0.30) {
  result <- tryCatch({
    db_query(
      "SELECT
         COUNT(*) FILTER (WHERE er.emotion = 'Confused') AS confused_count,
         COUNT(*) FILTER (WHERE er.is_present) AS present_count
       FROM emotion_records er
       JOIN lectures l ON er.lecture_id = l.lecture_id
       WHERE l.lecture_code = $1",
      list(lecture_code)
    )
  }, error = function(e) {
    message(paste("Confusion check query failed:", e$message))
    return(NULL)
  })

  if (is.null(result) || nrow(result) == 0) return(invisible(NULL))

  confused <- as.integer(result$confused_count[1])
  present  <- as.integer(result$present_count[1])
  if (is.na(present) || present == 0) return(invisible(NULL))

  rate <- confused / present
  if (rate > threshold) {
    msg <- sprintf("Confusion rate: %.1f%% (%d/%d students)", rate * 100, confused, present)
    tryCatch({
      db_execute(
        "INSERT INTO alerts (lecture_id, alert_type, severity, title, message, threshold_value, actual_value, time_minute)
         VALUES (
           (SELECT lecture_id FROM lectures WHERE lecture_code = $1),
           'confusion_spike', 'warning', 'Confusion Spike Detected', $2, $3, $4, 0
         )",
        list(lecture_code, msg, threshold, rate)
      )
    }, error = function(e) {
      message(paste("Alert insert failed:", e$message))
    })

    # CSV backup
    tryCatch({
      csv_append_row(data.frame(
        lecture_code     = lecture_code,
        alert_type       = "confusion_spike",
        severity         = "warning",
        message          = msg,
        threshold_value  = threshold,
        actual_value     = rate,
        created_at       = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      ), "data/alerts.csv")
    }, error = function(e) {
      message(paste("CSV backup for alert failed:", e$message))
    })
  }

  invisible(NULL)
}

#' Export lecture data as CSV (for download button)
export_lecture_csv <- function(lecture_code) {
  data <- db_query(
    "SELECT * FROM vw_emotion_records_flat WHERE lecture_id = $1 ORDER BY timestamp",
    list(lecture_code)
  )
  data
}
