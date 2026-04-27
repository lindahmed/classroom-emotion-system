load_emotion_data <- function(path = "data/emotion_records.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_all_mock_data()
  }

  df <- readr::read_csv(path, show_col_types = FALSE)

  # Ensure correct data types
  df <- df %>%
    mutate(
      record_id = as.integer(record_id),
      timestamp = as.POSIXct(timestamp),
      is_present = as.logical(is_present),
      left_room = as.logical(left_room)
    )

  df
}

load_lecture_schedule <- function(path = "data/lecture_schedule.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_lecture_schedule(path)
  }

  df <- readr::read_csv(path, show_col_types = FALSE)
  df <- df %>%
    mutate(
      lecture_date = as.Date(lecture_date),
      start_time = as.character(start_time),
      end_time = as.character(end_time)
    )
  df
}

load_semester_weeks <- function(path = "data/semester_weeks.csv") {
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

load_courses <- function(path = "data/courses.csv") {
  if (!file.exists(path)) {
    source("R/generate_sample_data.R", local = TRUE)
    generate_courses(path)
  }
  readr::read_csv(path, show_col_types = FALSE)
}

load_groups <- function(path = "data/groups.csv") {
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
    # Lecturer sees only their assigned lectures
    lecturer_data <- data %>%
      filter(lecturer_id == user_id)
    return(lecturer_data)
  } else if (user_role == "Student") {
    # Student sees only their own data
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
    return(schedule %>% filter(lecturer_id == user_id))
  }
  # Students don't see schedule
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

# Get unique groups (replacing cohorts)
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
