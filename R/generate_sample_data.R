# Generate comprehensive 16-week mock data for EduPulse AI

generate_semester_weeks <- function(output_path = "data/semester_weeks.csv") {
  set.seed(42)

  # Generate 16 weeks starting from Feb 9, 2026 (Monday)
  semester_data <- list()
  start_date <- as.Date("2026-02-09")

  for (w in 1:16) {
    week_start <- start_date + ((w - 1) * 7)
    week_end <- week_start + 6

    semester_data[[w]] <- data.frame(
      semester_id = "SPRING2026",
      academic_week = w,
      week_label = paste("Week", w),
      start_date = week_start,
      end_date = week_end,
      status = ifelse(w <= 5, "completed", ifelse(w <= 10, "active", "scheduled"))
    )
  }

  df <- do.call(rbind, semester_data)
  rownames(df) <- NULL
  dir.create("data", showWarnings = FALSE)
  write.csv(df, output_path, row.names = FALSE)
  invisible(df)
}

generate_courses <- function(output_path = "data/courses.csv") {
  courses <- data.frame(
    course_id = c("C001", "C002", "C003", "C004"),
    course_code = c("CS301", "CS302", "CS401", "MATH201"),
    course_name = c(
      "Artificial Intelligence",
      "Data Science Fundamentals",
      "Advanced Machine Learning",
      "Statistics for Data Analysis"
    ),
    department = c("Computer Science", "Computer Science", "Computer Science", "Mathematics"),
    credit_hours = c(3, 3, 4, 3)
  )
  dir.create("data", showWarnings = FALSE)
  write.csv(courses, output_path, row.names = FALSE)
  invisible(courses)
}

generate_groups <- function(output_path = "data/groups.csv") {
  groups <- data.frame(
    group_id = c("G01", "G02", "G03", "G04", "G05", "G06"),
    group_name = c(
      "Group A", "Group B", "Group A", "Group B",
      "Group A", "Group B"
    ),
    course_id = c("C001", "C001", "C002", "C002", "C003", "C004"),
    semester_id = "SPRING2026",
    student_count = c(20, 20, 20, 20, 20, 20)
  )
  dir.create("data", showWarnings = FALSE)
  write.csv(groups, output_path, row.names = FALSE)
  invisible(groups)
}

generate_lecturers <- function(output_path = "data/lecturers.csv") {
  lecturers <- data.frame(
    lecturer_id = c("T01", "T02", "T03"),
    lecturer_name = c("Dr. Ahmed", "Dr. Smith", "Dr. Johnson"),
    department = c("Computer Science", "Computer Science", "Mathematics"),
    email = c("ahmed@edu.com", "smith@edu.com", "johnson@edu.com")
  )
  dir.create("data", showWarnings = FALSE)
  write.csv(lecturers, output_path, row.names = FALSE)
  invisible(lecturers)
}

generate_lecturer_assignments <- function(output_path = "data/lecturer_course_assignments.csv") {
  assignments <- data.frame(
    assignment_id = c("A01", "A02", "A03", "A04", "A05", "A06", "A07", "A08"),
    lecturer_id = c("T01", "T01", "T01", "T01", "T02", "T02", "T03", "T03"),
    course_id = c("C001", "C001", "C002", "C002", "C003", "C004", "C001", "C002"),
    group_id = c("G01", "G02", "G03", "G04", "G05", "G06", "G01", "G03"),
    semester_id = "SPRING2026"
  )
  dir.create("data", showWarnings = FALSE)
  write.csv(assignments, output_path, row.names = FALSE)
  invisible(assignments)
}

generate_lecture_schedule <- function(output_path = "data/lecture_schedule.csv") {
  set.seed(42)

  schedule_list <- list()
  record_id <- 1
  start_date <- as.Date("2026-02-09")

  lecturers <- data.frame(
    lecturer_id = c("T01", "T02", "T03"),
    lecturer_name = c("Dr. Ahmed", "Dr. Smith", "Dr. Johnson")
  )

  courses <- data.frame(
    course_id = c("C001", "C002", "C003", "C004"),
    course_code = c("CS301", "CS302", "CS401", "MATH201"),
    course_name = c(
      "Artificial Intelligence",
      "Data Science Fundamentals",
      "Advanced Machine Learning",
      "Statistics for Data Analysis"
    )
  )

  groups <- data.frame(
    group_id = c("G01", "G02", "G03", "G04", "G05", "G06"),
    group_name = c("Group A", "Group B", "Group A", "Group B", "Group A", "Group B"),
    course_id = c("C001", "C001", "C002", "C002", "C003", "C004"),
    student_count = c(20, 20, 20, 20, 20, 20)
  )

  # Assignments: (lecturer, course, group)
  assignments <- list(
    c("T01", "C001", "G01"),
    c("T01", "C001", "G02"),
    c("T01", "C002", "G03"),
    c("T01", "C002", "G04"),
    c("T02", "C003", "G05"),
    c("T02", "C004", "G06"),
    c("T03", "C001", "G01"),  # T03 co-teaches CS301 Group A
    c("T03", "C002", "G03")   # T03 co-teaches CS302 Group A
  )

  # Generate 2 lectures per week for each assignment
  for (week in 1:16) {
    week_start <- start_date + ((week - 1) * 7)

    # Typical schedule: Monday 10:00-11:00, Wednesday 14:00-15:00
    for (assignment in assignments) {
      lecturer_id <- assignment[1]
      course_id <- assignment[2]
      group_id <- assignment[3]

      # Get lecturer name
      lecturer_name <- lecturers$lecturer_name[lecturers$lecturer_id == lecturer_id]

      # Get course info
      course_info <- courses[courses$course_id == course_id, ]
      course_code <- course_info$course_code
      course_name <- course_info$course_name

      # Get group name and student count
      group_info <- groups[groups$group_id == group_id, ]
      group_name <- group_info$group_name
      expected_students <- group_info$student_count

      # Monday lecture
      monday_date <- week_start
      schedule_list[[length(schedule_list) + 1]] <- data.frame(
        lecture_id = paste0("L", sprintf("%03d", record_id)),
        lecture_name = paste(course_code, "Lecture", week, "- Part A"),
        semester_id = "SPRING2026",
        academic_week = week,
        lecture_date = monday_date,
        day_name = "Monday",
        start_time = "10:00",
        end_time = "11:00",
        course_id = course_id,
        course_code = course_code,
        course_name = course_name,
        group_id = group_id,
        group_name = group_name,
        lecturer_id = lecturer_id,
        lecturer_name = lecturer_name,
        room = paste("Room", sample(c("204", "305", "401", "501"), 1)),
        expected_students = expected_students,
        status = ifelse(week <= 5, "analyzed", "scheduled")
      )
      record_id <- record_id + 1

      # Wednesday lecture
      wednesday_date <- monday_date + 2
      schedule_list[[length(schedule_list) + 1]] <- data.frame(
        lecture_id = paste0("L", sprintf("%03d", record_id)),
        lecture_name = paste(course_code, "Lecture", week, "- Part B"),
        semester_id = "SPRING2026",
        academic_week = week,
        lecture_date = wednesday_date,
        day_name = "Wednesday",
        start_time = "14:00",
        end_time = "15:00",
        course_id = course_id,
        course_code = course_code,
        course_name = course_name,
        group_id = group_id,
        group_name = group_name,
        lecturer_id = lecturer_id,
        lecturer_name = lecturer_name,
        room = paste("Room", sample(c("204", "305", "401", "501"), 1)),
        expected_students = expected_students,
        status = ifelse(week <= 5, "analyzed", "scheduled")
      )
      record_id <- record_id + 1
    }
  }

  df <- do.call(rbind, schedule_list)
  rownames(df) <- NULL
  dir.create("data", showWarnings = FALSE)
  write.csv(df, output_path, row.names = FALSE)
  invisible(df)
}

generate_emotion_records <- function(output_path = "data/emotion_records.csv") {
  set.seed(42)

  # Define base parameters - 120 students across 6 groups
  students <- data.frame(
    student_id = paste0("S", sprintf("%03d", 1:120)),
    student_name = paste0("Student ", 1:120),
    group = rep(paste0("G", sprintf("%02d", 1:6)), each = 20)
  )

  # Load lecture schedule
  if (!file.exists("data/lecture_schedule.csv")) {
    generate_lecture_schedule("data/lecture_schedule.csv")
  }
  schedule <- readr::read_csv("data/lecture_schedule.csv", show_col_types = FALSE)

  # Only generate for analyzed lectures (week 1-5)
  analyzed_lectures <- schedule %>%
    filter(status == "analyzed") %>%
    pull(lecture_id)

  records <- list()
  record_id <- 1

  emotions <- c("Happy", "Neutral", "Confused", "Bored")
  emotion_engagement <- c(Happy = 0.95, Neutral = 0.65, Confused = 0.40, Bored = 0.20)

  # For each analyzed lecture, generate records for students in that group
  for (lec_id in analyzed_lectures) {
    lec_info <- schedule[schedule$lecture_id == lec_id, ]
    group_id <- lec_info$group_id
    course_code <- lec_info$course_code
    week <- lec_info$academic_week

    # Get students in this group
    group_students <- students[students$group == group_id, ]

    # Generate records every 5 minutes for 60 minutes
    for (minute in seq(0, 55, by = 5)) {
      for (i in seq_len(nrow(group_students))) {
        student_id <- group_students$student_id[i]
        student_name <- group_students$student_name[i]

        # Week 2-3 specific topics: higher confusion
        if (week %in% c(2, 3) && minute >= 20 && minute <= 40) {
          emotion <- "Confused"
          confidence <- runif(1, 0.70, 0.85)
        }
        # Week 4: higher engagement
        else if (week == 4) {
          emotion <- sample(emotions, 1, prob = c(0.45, 0.35, 0.10, 0.10))
          confidence <- runif(1, 0.80, 0.99)
        }
        # Default distribution
        else {
          emotion <- sample(emotions, 1, prob = c(0.35, 0.40, 0.15, 0.10))
          confidence <- runif(1, 0.75, 0.99)
        }

        engagement_score <- emotion_engagement[emotion] + rnorm(1, 0, 0.05)
        engagement_score <- pmax(0, pmin(1, engagement_score))

        # Students in later groups have slightly lower focus
        group_num <- as.integer(substring(group_id, 2))
        if (group_num > 3) {
          focus_score <- runif(1, 0.4, 0.75)
        } else {
          focus_score <- runif(1, 0.6, 0.95)
        }

        # Some students leave/return (5% chance)
        is_present <- TRUE
        left_room <- FALSE
        absence_duration_minutes <- 0

        if (runif(1) < 0.05) {
          is_present <- FALSE
          left_room <- TRUE
          absence_duration_minutes <- sample(c(5, 10, 15, 20), 1)
        }

        # Create timestamp from lecture date and time
        lec_date <- as.Date(lec_info$lecture_date)
        start_hour <- as.integer(substring(lec_info$start_time, 1, 2))
        timestamp <- as.POSIXct(
          paste(lec_date, sprintf("%02d:%02d:00", start_hour, minute)),
          tz = "UTC"
        ) + as.integer(runif(1, 0, 300))

        records[[length(records) + 1]] <- data.frame(
          record_id = record_id,
          student_id = student_id,
          student_name = student_name,
          lecture_id = lec_id,
          lecture_name = lec_info$lecture_name,
          lecturer_id = lec_info$lecturer_id,
          lecturer_name = lec_info$lecturer_name,
          course_id = lec_info$course_id,
          course_code = course_code,
          course_name = lec_info$course_name,
          group_id = group_id,
          group_name = lec_info$group_name,
          academic_week = week,
          timestamp = timestamp,
          time = sprintf("%02d:%02d", start_hour, minute),
          time_minute = minute,
          emotion = emotion,
          confidence = round(confidence, 2),
          engagement_score = round(engagement_score, 2),
          focus_score = round(focus_score, 2),
          attendance_status = ifelse(is_present, "Present", "Absent"),
          is_present = is_present,
          left_room = left_room,
          absence_duration_minutes = absence_duration_minutes,
          source_type = "mock_video",
          model_name = "EduPulse_v1.0",
          stringsAsFactors = FALSE
        )

        record_id <- record_id + 1
      }
    }
  }

  df <- do.call(rbind, records)
  rownames(df) <- NULL

  dir.create("data", showWarnings = FALSE)
  write.csv(df, output_path, row.names = FALSE)

  invisible(df)
}

# Master function to generate all data
generate_all_mock_data <- function() {
  cat("Generating semester weeks...\n")
  generate_semester_weeks()

  cat("Generating courses...\n")
  generate_courses()

  cat("Generating groups...\n")
  generate_groups()

  cat("Generating lecturers...\n")
  generate_lecturers()

  cat("Generating lecturer assignments...\n")
  generate_lecturer_assignments()

  cat("Generating lecture schedule...\n")
  generate_lecture_schedule()

  cat("Generating emotion records...\n")
  generate_emotion_records()

  cat("✓ All mock data generated successfully!\n")
}
