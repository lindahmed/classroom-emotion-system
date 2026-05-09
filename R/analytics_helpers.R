compute_summary_metrics <- function(data) {
  if (nrow(data) == 0) {
    return(list(
      avg_engagement = 0,
      avg_focus = 0,
      attendance_rate = 0,
      confusion_rate = 0,
      students_present = 0,
      active_lecture = "N/A"
    ))
  }

  list(
    avg_engagement = round(mean(data$engagement_score, na.rm = TRUE), 3),
    avg_focus = round(mean(data$focus_score, na.rm = TRUE), 3),
    attendance_rate = round(sum(data$is_present) / nrow(data), 3),
    confusion_rate = round(sum(data$emotion == "Confused") / nrow(data), 3),
    students_present = sum(data$is_present),
    active_lecture = ifelse(nrow(data) > 0,
      data$lecture_name[1],
      "N/A"
    )
  )
}

compute_narrative_insights <- function(data) {
  if (nrow(data) == 0) {
    return("No data available for analysis.")
  }

  insights <- c()

  # Engagement insight
  avg_engagement <- mean(data$engagement_score, na.rm = TRUE)
  if (avg_engagement > 0.75) {
    insights <- c(insights, "✓ High engagement levels detected across the classroom.")
  } else if (avg_engagement < 0.45) {
    insights <- c(insights, "⚠ Low engagement levels detected. Consider interactive activities.")
  }

  # Confusion insight
  confusion_rate <- sum(data$emotion == "Confused") / nrow(data)
  if (confusion_rate > 0.3) {
    insights <- c(insights, "⚠ High confusion rates detected. Review complex topics.")
  }

  # Attendance insight
  attendance_rate <- sum(data$is_present) / nrow(data)
  if (attendance_rate < 0.9) {
    insights <- c(insights, "⚠ Some students are absent or have left the room.")
  }

  # Boredom insight
  boredom_rate <- sum(data$emotion == "Bored") / nrow(data)
  if (boredom_rate > 0.25) {
    insights <- c(insights, "⚠ Boredom signals detected. Vary teaching methods.")
  }

  # Focus insight
  avg_focus <- mean(data$focus_score, na.rm = TRUE)
  if (avg_focus > 0.7) {
    insights <- c(insights, "✓ Strong focus and attention observed.")
  }

  if (length(insights) == 0) {
    insights <- c("✓ Overall classroom dynamics appear healthy.")
  }

  paste(insights, collapse = " ")
}

compute_confusion_spikes <- function(data) {
  if (nrow(data) == 0) {
    return(data.frame())
  }

  spikes <- data %>%
    group_by(lecture_id, time_minute) %>%
    summarise(
      lecture_name = first(lecture_name),
      confusion_count = sum(emotion == "Confused"),
      total_present = sum(is_present),
      confusion_rate = round(confusion_count / max(1, total_present), 3),
      .groups = "drop"
    ) %>%
    filter(confusion_rate > 0.3) %>%
    mutate(
      message = paste0(
        "High confusion at minute ",
        time_minute,
        " (Rate: ",
        round(confusion_rate * 100, 1),
        "%)"
      )
    ) %>%
    arrange(desc(confusion_rate))

  spikes
}

perform_clustering <- function(data, k = 3) {
  if (nrow(data) == 0) {
    return(list(clusters = NULL, centers = NULL, message = "No data available"))
  }

  # Aggregate student metrics (use group_id instead of cohort)
  student_metrics <- data %>%
    group_by(student_id, student_name, group_id) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      avg_focus = mean(focus_score, na.rm = TRUE),
      confusion_rate = sum(emotion == "Confused") / n(),
      boredom_rate = sum(emotion == "Bored") / n(),
      total_absence_duration = sum(absence_duration_minutes),
      .groups = "drop"
    )

  if (nrow(student_metrics) == 0) {
    return(list(clusters = NULL, centers = NULL, message = "Insufficient data"))
  }

  # Scale features for clustering
  features <- student_metrics %>%
    select(
      avg_engagement, avg_focus, confusion_rate,
      boredom_rate, total_absence_duration
    ) %>%
    as.matrix()

  features_scaled <- scale(features)

  # Perform kmeans
  km <- stats::kmeans(features_scaled, centers = min(k, nrow(features_scaled)), nstart = 10)

  # Add clusters to data
  student_metrics$cluster <- km$cluster

  list(
    clusters = student_metrics,
    centers = km$centers,
    message = NULL
  )
}

# Calculate dominant emotion (most frequent, tie-break by confidence, then timestamp)
calculate_dominant_emotion <- function(emotions, confidences = NULL, timestamps = NULL) {
  if (length(emotions) == 0) return(NA_character_)

  emotion_counts <- table(emotions)
  max_count <- max(emotion_counts)
  candidates <- names(emotion_counts)[emotion_counts == max_count]

  if (length(candidates) == 1) {
    return(candidates[1])
  }

  # Tie-break by confidence
  if (!is.null(confidences)) {
    candidate_indices <- which(emotions %in% candidates)
    candidate_confidences <- confidences[candidate_indices]
    max_confidence_idx <- which.max(candidate_confidences)
    candidate <- emotions[candidate_indices[max_confidence_idx]]

    if (!is.na(candidate)) return(candidate)
  }

  # Tie-break by latest timestamp
  if (!is.null(timestamps)) {
    candidate_indices <- which(emotions %in% candidates)
    latest_idx <- candidate_indices[which.max(timestamps[candidate_indices])]
    return(emotions[latest_idx])
  }

  # Default: return first candidate
  candidates[1]
}

# Calculate student-level lecture report
calculate_lecture_report <- function(emotion_data, lecture_id) {
  if (nrow(emotion_data) == 0) {
    return(data.frame())
  }

  lecture_data <- emotion_data %>%
    filter(lecture_id == !!lecture_id)

  if (nrow(lecture_data) == 0) {
    return(data.frame())
  }

  report <- lecture_data %>%
    group_by(student_id, student_name, course_id, course_code, course_name,
      group_id, group_name, lecture_id, academic_week
    ) %>%
    summarise(
      total_records = n(),
      all_emotions = paste(emotion, collapse = " → "),
      emotion_timeline = paste(
        paste0(time_minute, " min: ", emotion),
        collapse = " → "
      ),
      happy_count = sum(emotion == "Happy"),
      neutral_count = sum(emotion == "Neutral"),
      confused_count = sum(emotion == "Confused"),
      bored_count = sum(emotion == "Bored"),
      avg_confidence = round(mean(confidence, na.rm = TRUE), 3),
      avg_engagement = round(mean(engagement_score, na.rm = TRUE), 3),
      avg_focus = round(mean(focus_score, na.rm = TRUE), 3),
      confusion_rate = round(confused_count / total_records, 3),
      boredom_rate = round(bored_count / total_records, 3),
      attendance_status = first(attendance_status),
      first_emotion = first(emotion),
      last_emotion = last(emotion),
      .groups = "drop"
    ) %>%
    rowwise() %>%
    mutate(
      dominant_emotion = calculate_dominant_emotion(
        strsplit(all_emotions, " → ")[[1]],
        NULL,
        NULL
      ),
      risk_flag = calculate_risk_flag(
        dominant_emotion,
        confusion_rate,
        boredom_rate,
        avg_focus,
        avg_engagement,
        attendance_status
      )
    ) %>%
    ungroup() %>%
    arrange(student_id)

  report
}

# Calculate risk flag for students
calculate_risk_flag <- function(dominant_emotion, confusion_rate, boredom_rate,
                              avg_focus, avg_engagement, attendance_status) {
  flags <- c()

  if (!is.na(dominant_emotion)) {
    if (dominant_emotion == "Confused" && confusion_rate > 0.4) {
      flags <- c(flags, "High Confusion")
    }
    if (dominant_emotion == "Bored" && boredom_rate > 0.4) {
      flags <- c(flags, "High Boredom")
    }
  }

  if (avg_focus < 0.4) {
    flags <- c(flags, "Low Focus")
  }

  if (avg_engagement < 0.4) {
    flags <- c(flags, "Low Engagement")
  }

  if (attendance_status == "Absent") {
    flags <- c(flags, "Absent")
  } else if (attendance_status %in% c("Left Room", "Partial")) {
    flags <- c(flags, "Partial Attendance")
  }

  if (length(flags) == 0) {
    return("Normal")
  }

  paste(flags, collapse = " / ")
}

# Calculate lecture summary for report header
calculate_lecture_summary <- function(emotion_data, lecture_id) {
  if (nrow(emotion_data) == 0) {
    return(list())
  }

  lecture_data <- emotion_data %>%
    filter(lecture_id == !!lecture_id)

  if (nrow(lecture_data) == 0) {
    return(list())
  }

  # Get most common emotion
  emotion_counts <- table(lecture_data$emotion)
  dominant_emotion <- names(emotion_counts)[which.max(emotion_counts)]

  list(
    total_students = n_distinct(lecture_data$student_id),
    present_students = sum(lecture_data$is_present) / n_distinct(lecture_data$student_id),
    absent_students = n_distinct(lecture_data[!lecture_data$is_present, ]$student_id),
    avg_engagement = round(mean(lecture_data$engagement_score, na.rm = TRUE), 3),
    avg_focus = round(mean(lecture_data$focus_score, na.rm = TRUE), 3),
    avg_confidence = round(mean(lecture_data$confidence, na.rm = TRUE), 3),
    dominant_emotion = dominant_emotion,
    confusion_rate = round(sum(lecture_data$emotion == "Confused") / nrow(lecture_data), 3),
    boredom_rate = round(sum(lecture_data$emotion == "Bored") / nrow(lecture_data), 3)
  )
}
