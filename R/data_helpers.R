# data_helpers.R — Data loading and filtering for EduPulse AI
# Uses PostgreSQL queries via db_queries.R

source("R/db_queries.R")

# Use PostgreSQL as primary source, with CSV fallback
USE_DATABASE <- tolower(Sys.getenv("EDUPULSE_USE_DB", "true")) %in% c("1", "true", "yes")

# CSV loaders (explicit fallback paths)
load_emotion_data_csv <- function(path = "data/emotion_records.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_all_mock_data()
  }
  df <- readr::read_csv(path, show_col_types = FALSE)
  df <- df %>%
    mutate(
      record_id = as.integer(record_id),
      timestamp = as.POSIXct(timestamp),
      is_present = as.logical(is_present),
      left_room = as.logical(left_room)
    )
  df
}

load_lecture_schedule_csv <- function(path = "data/lecture_schedule.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_lecture_schedule(path)
  }
  df <- readr::read_csv(path, show_col_types = FALSE)

  # Backward-compatible column mapping (older CSVs had *_str and lecture_status)
  if (("lecture_status" %in% names(df)) && !("status" %in% names(df))) {
    df <- dplyr::rename(df, status = lecture_status)
  }
  if (("lecturer_id_str" %in% names(df)) && !("lecturer_id" %in% names(df))) {
    df <- dplyr::rename(df, lecturer_id = lecturer_id_str)
  }
  if (("lecture_id_str" %in% names(df)) && !("lecture_id" %in% names(df))) {
    df <- dplyr::rename(df, lecture_id = lecture_id_str)
  }

  df <- df %>%
    mutate(
      lecture_date = as.Date(lecture_date),
      start_time = as.character(start_time),
      end_time = as.character(end_time)
    )
  df
}

load_semester_weeks_csv <- function(path = "data/semester_weeks.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_semester_weeks(path)
  }
  df <- readr::read_csv(path, show_col_types = FALSE)
  df <- df %>%
    mutate(
      start_date = as.Date(start_date),
      end_date = as.Date(end_date)
    )
  df
}

load_emotion_data <- function(path = "data/emotion_records.csv") {
  if (USE_DATABASE) {
    tryCatch({
      df <- db_query("SELECT * FROM vw_emotion_records_flat", list())
      return(df)
    }, error = function(e) {
      message(paste("Database load failed, falling back to CSV:", e$message))
    })
  }
  load_emotion_data_csv(path)
}

load_lecture_schedule <- function(path = "data/lecture_schedule.csv") {
  if (USE_DATABASE) {
    tryCatch({
      df <- db_query("SELECT * FROM vw_lecture_schedule", list())
      return(df)
    }, error = function(e) {
      message(paste("Database load failed, falling back to CSV:", e$message))
    })
  }
  load_lecture_schedule_csv(path)
}

load_semester_weeks <- function(path = "data/semester_weeks.csv") {
  if (USE_DATABASE) {
    tryCatch({
      return(db_query(
        "SELECT semester_id, academic_week, week_label, start_date, end_date, status::text AS status FROM semester_weeks ORDER BY academic_week",
        list()
      ))
    }, error = function(e) {
      message(paste("Database load failed, falling back to CSV:", e$message))
    })
  }
  load_semester_weeks_csv(path)
}

load_courses <- function(path = "data/courses.csv") {
  if (USE_DATABASE) {
    tryCatch({
      return(db_query("SELECT * FROM courses ORDER BY course_code", list()))
    }, error = function(e) {
      message(paste("Database load failed, falling back to CSV:", e$message))
    })
  }

  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_courses(path)
  }
  readr::read_csv(path, show_col_types = FALSE)
}

load_groups <- function(path = "data/groups.csv") {
  if (USE_DATABASE) {
    tryCatch({
      return(db_query(
        "SELECT sg.group_id, sg.group_code, sg.group_name, sg.course_id, sg.semester_id,
                (SELECT COUNT(*) FROM group_memberships gm WHERE gm.group_id = sg.group_id) AS student_count
         FROM student_groups sg ORDER BY sg.group_code",
        list()
      ))
    }, error = function(e) {
      message(paste("Database load failed, falling back to CSV:", e$message))
    })
  }

  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_groups(path)
  }
  readr::read_csv(path, show_col_types = FALSE)
}

# Filter data based on user role
filter_by_role <- function(data, user_role, user_id = NULL) {
  if (user_role == "Admin") {
    return(data)
  } else if (user_role == "Lecturer") {
    lecturer_data <- data %>%
      filter(lecturer_id == user_id)
    return(lecturer_data)
  } else if (user_role == "Student") {
    student_data <- data %>%
      filter(student_id == user_id)
    return(student_data)
  }
  data
}

# Filter schedule by role
filter_schedule_by_role <- function(schedule, user_role, user_id = NULL) {
  if (user_role == "Admin") {
    return(schedule)
  } else if (user_role == "Lecturer") {
    if ("lecturer_id_str" %in% names(schedule)) {
      return(schedule %>% filter(lecturer_id_str == user_id))
    }
    return(schedule %>% filter(lecturer_id == user_id))
  }
  data.frame()
}

# Filter schedule for a specific week
filter_schedule_by_week <- function(schedule, week_number) {
  schedule %>% filter(academic_week == week_number)
}

# Get unique lectures
get_lectures <- function(data) {
  data %>%
    distinct(lecture_id, lecture_name) %>%
    arrange(lecture_id) %>%
    pull(lecture_id)
}

# Get unique groups
get_groups_from_data <- function(data) {
  if (nrow(data) == 0 || !("group_id" %in% names(data))) {
    return(c())
  }
  data %>%
    distinct(group_id) %>%
    arrange(group_id) %>%
    pull(group_id)
}

get_students <- function(data) {
  data %>%
    distinct(student_id, student_name) %>%
    arrange(student_id)
}

get_courses_from_data <- function(data) {
  if (nrow(data) == 0 || !("course_id" %in% names(data))) {
    return(c())
  }
  data %>%
    distinct(course_id) %>%
    arrange(course_id) %>%
    pull(course_id)
}

# Get weeks that have data
get_available_weeks <- function(schedule) {
  schedule %>%
    distinct(academic_week) %>%
    arrange(academic_week) %>%
    pull(academic_week)
}
