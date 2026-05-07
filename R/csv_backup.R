# csv_backup.R — CSV backup utilities for EduPulse AI
# Writes CSV backups alongside every DB write operation

library(readr)

# Ensure data directory exists
ensure_data_dir <- function() {
  dir.create("data", showWarnings = FALSE)
}

#' Append a row (data.frame/tibble) to a CSV file
#' Creates file with header if it doesn't exist
#' @param data Single-row data.frame or tibble
#' @param file_path Path to CSV file
csv_append_row <- function(data, file_path) {
  ensure_data_dir()
  tryCatch({
    if (nrow(data) == 0) return(invisible(FALSE))
    write_csv(data, file_path, append = file.exists(file_path))
    invisible(TRUE)
  }, error = function(e) {
    message(paste("CSV append failed for", file_path, ":", e$message))
    invisible(FALSE)
  })
}

#' Build a flat emotion record row for CSV backup from live face recognition data
#' @param parsed Named list from JSON response (student_id, student_name, emotion, etc.)
#' @param lecture_id The active lecture ID
#' @return data.frame with one row matching vw_emotion_records_flat columns
build_emotion_flat_row <- function(parsed, lecture_id) {
  now <- Sys.time()
  data.frame(
    record_id              = NA_integer_,
    student_id             = parsed$student_id %||% NA_character_,
    student_name           = parsed$student_name %||% NA_character_,
    lecture_id             = lecture_id,
    lecture_name           = NA_character_,
    lecturer_id            = NA_character_,
    lecturer_name          = NA_character_,
    course_id              = NA_character_,
    course_code            = NA_character_,
    course_name            = NA_character_,
    group_id               = NA_character_,
    group_name             = NA_character_,
    academic_week          = NA_integer_,
    timestamp              = format(now, "%Y-%m-%d %H:%M:%S"),
    time                   = format(now, "%H:%M:%S"),
    time_minute            = 0L,
    emotion                = parsed$emotion %||% "Neutral",
    confidence             = as.numeric(parsed$confidence %||% 0),
    engagement_score       = as.numeric(parsed$engagement_score %||% 0),
    focus_score            = as.numeric(parsed$focus_score %||% 0),
    attendance_status      = parsed$attendance_status %||% "Unknown",
    is_present             = parsed$is_present %||% TRUE,
    left_room              = parsed$left_room %||% FALSE,
    absence_duration_minutes = as.integer(parsed$absence_duration_minutes %||% 0),
    source_type            = "live_camera",
    model_name             = "EduPulse_v1.0",
    stringsAsFactors       = FALSE
  )
}

#' Append an emotion record to the CSV backup
#' @param parsed Named list from face recognition JSON
#' @param lecture_id Active lecture ID
csv_append_emotion_record <- function(parsed, lecture_id) {
  row <- build_emotion_flat_row(parsed, lecture_id)
  csv_append_row(row, "data/emotion_records.csv")
}

#' Full dump of a DB view/table to CSV (overwrite)
#' @param view_name SQL view or table name
#' @param file_path Output CSV path
csv_dump_table <- function(view_name, file_path) {
  ensure_data_dir()
  tryCatch({
    data <- db_query(paste0("SELECT * FROM ", view_name), list())
    write_csv(data, file_path)
    invisible(TRUE)
  }, error = function(e) {
    message(paste("CSV dump failed for", view_name, ":", e$message))
    invisible(FALSE)
  })
}

#' Full backup of all data tables to CSV files
csv_backup_all <- function() {
  ensure_data_dir()
  csv_dump_table("vw_emotion_records_flat", "data/emotion_records.csv")
  csv_dump_table("vw_lecture_schedule", "data/lecture_schedule.csv")
  csv_dump_table(
    "SELECT semester_id, academic_week, week_label, start_date, end_date, status::text AS status FROM semester_weeks ORDER BY academic_week",
    "data/semester_weeks.csv"
  )
  csv_dump_table("courses", "data/courses.csv")
  csv_dump_table(
    "SELECT sg.group_id, sg.group_code, sg.group_name, sg.course_id, sg.semester_id,
            (SELECT COUNT(*) FROM group_memberships gm WHERE gm.group_id = sg.group_id) AS student_count
     FROM student_groups sg ORDER BY sg.group_code",
    "data/groups.csv"
  )
  message(paste("CSV backup sync completed at", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
}

# Null coalescing operator (if not already defined)
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}
