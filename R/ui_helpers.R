ui_metric_card <- function(title, value, icon = "chart-line", color = "primary") {
  htmltools::div(
    class = "metric-card",
    style = paste0("border-left: 4px solid var(--bs-", color, ");"),
    htmltools::div(
      class = "metric-header",
      htmltools::span(class = "metric-icon", icon),
      htmltools::span(class = "metric-title", title)
    ),
    htmltools::div(class = "metric-value", value)
  )
}

ui_emotion_color <- function(emotion) {
  colors <- list(
    Happy = "#10b981",
    Neutral = "#6366f1",
    Confused = "#f59e0b",
    Bored = "#ef4444"
  )
  colors[[emotion]]
}

render_engagement_timeline <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  timeline_data <- data %>%
    group_by(time_minute) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      avg_focus = mean(focus_score, na.rm = TRUE),
      confusion_rate = sum(emotion == "Confused") / sum(is_present),
      .groups = "drop"
    ) %>%
    pivot_longer(
      cols = -time_minute,
      names_to = "metric",
      values_to = "value"
    ) %>%
    mutate(
      metric = factor(metric,
        levels = c("avg_engagement", "avg_focus", "confusion_rate"),
        labels = c("Engagement", "Focus", "Confusion Rate")
      )
    )

  ggplot(timeline_data, aes(x = time_minute, y = value, color = metric)) +
    geom_line(size = 1) +
    geom_point(size = 2.5) +
    scale_color_manual(
      values = c("Engagement" = "#10b981", "Focus" = "#3b82f6", "Confusion Rate" = "#f59e0b")
    ) +
    labs(
      title = "Engagement, Focus & Confusion Timeline",
      x = "Lecture Time (minutes)",
      y = "Score",
      color = "Metric"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_emotion_distribution <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  emotion_dist <- data %>%
    group_by(emotion) %>%
    summarise(count = n(), .groups = "drop") %>%
    mutate(
      percentage = round(count / sum(count) * 100, 1),
      label = paste0(emotion, "\n", percentage, "%")
    )

  emotion_colors <- c(
    Happy = "#10b981",
    Neutral = "#6366f1",
    Confused = "#f59e0b",
    Bored = "#ef4444"
  )

  ggplot(emotion_dist, aes(x = reorder(emotion, -count), y = count, fill = emotion)) +
    geom_col() +
    geom_text(aes(label = label), vjust = -0.3, color = "#f1f5f9", size = 4) +
    scale_fill_manual(
      values = emotion_colors[emotion_dist$emotion],
      guide = "none"
    ) +
    labs(
      title = "Emotion Distribution",
      x = "",
      y = "Count"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      axis.text.y = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3),
      axis.ticks = element_blank()
    )
}

# Lecture-level graphs

render_confusion_timeline <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  timeline_data <- data %>%
    group_by(time_minute) %>%
    summarise(
      confusion_rate = sum(emotion == "Confused") / max(1, sum(is_present)),
      .groups = "drop"
    )

  ggplot(timeline_data, aes(x = time_minute, y = confusion_rate)) +
    geom_line(color = "#f59e0b", size = 1.2) +
    geom_point(color = "#f59e0b", size = 2.5) +
    geom_hline(yintercept = 0.30, linetype = "dashed", color = "#ef4444", alpha = 0.7) +
    annotate("text", x = 5, y = 0.32, label = "Alert Threshold (30%)", color = "#ef4444", size = 3) +
    scale_y_continuous(labels = scales::percent) +
    labs(
      title = "Confusion Rate Timeline",
      x = "Lecture Time (minutes)",
      y = "Confusion Rate"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_boredom_timeline <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  timeline_data <- data %>%
    group_by(time_minute) %>%
    summarise(
      boredom_rate = sum(emotion == "Bored") / max(1, n()),
      .groups = "drop"
    )

  ggplot(timeline_data, aes(x = time_minute, y = boredom_rate)) +
    geom_line(color = "#ef4444", size = 1.2) +
    geom_point(color = "#ef4444", size = 2.5) +
    scale_y_continuous(labels = scales::percent) +
    labs(
      title = "Boredom Rate Timeline",
      x = "Lecture Time (minutes)",
      y = "Boredom Rate"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_dominant_emotion_by_student <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  student_emotions <- data %>%
    group_by(student_id, student_name) %>%
    summarise(
      emotion = names(which.max(table(emotion))),
      .groups = "drop"
    ) %>%
    group_by(emotion) %>%
    summarise(count = n(), .groups = "drop")

  emotion_colors <- c(
    Happy = "#10b981",
    Neutral = "#6366f1",
    Confused = "#f59e0b",
    Bored = "#ef4444"
  )

  ggplot(student_emotions, aes(x = reorder(emotion, -count), y = count, fill = emotion)) +
    geom_col() +
    scale_fill_manual(
      values = emotion_colors[student_emotions$emotion],
      guide = "none"
    ) +
    labs(
      title = "Student Count by Dominant Emotion",
      x = "Dominant Emotion",
      y = "Number of Students"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_student_engagement_ranking <- function(data, top_n = 15) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  student_engagement <- data %>%
    group_by(student_id, student_name) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(avg_engagement)) %>%
    head(top_n) %>%
    mutate(student_name = factor(student_name, levels = rev(student_name)))

  ggplot(student_engagement, aes(x = student_name, y = avg_engagement, fill = avg_engagement)) +
    geom_col() +
    scale_fill_gradient(low = "#ef4444", high = "#10b981", guide = "none") +
    coord_flip() +
    scale_y_continuous(limits = c(0, 1)) +
    labs(
      title = paste("Top", top_n, "Students by Engagement"),
      x = "",
      y = "Average Engagement"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_confusion_rate_by_student <- function(data, top_n = 10) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  student_confusion <- data %>%
    group_by(student_id, student_name) %>%
    summarise(
      confusion_rate = sum(emotion == "Confused") / n(),
      .groups = "drop"
    ) %>%
    arrange(desc(confusion_rate)) %>%
    head(top_n) %>%
    mutate(student_name = factor(student_name, levels = rev(student_name)))

  ggplot(student_confusion, aes(x = student_name, y = confusion_rate, fill = confusion_rate)) +
    geom_col() +
    scale_fill_gradient(low = "#10b981", high = "#f59e0b", guide = "none") +
    coord_flip() +
    scale_y_continuous(labels = scales::percent) +
    labs(
      title = paste("Top", top_n, "Students by Confusion Rate"),
      x = "",
      y = "Confusion Rate"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_engagement_vs_focus_scatter <- function(data) {
  if (nrow(data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  student_metrics <- data %>%
    group_by(student_id, student_name) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      avg_focus = mean(focus_score, na.rm = TRUE),
      dominant_emotion = names(which.max(table(emotion))),
      .groups = "drop"
    )

  emotion_colors <- c(
    Happy = "#10b981",
    Neutral = "#6366f1",
    Confused = "#f59e0b",
    Bored = "#ef4444"
  )

  ggplot(student_metrics, aes(x = avg_engagement, y = avg_focus, color = dominant_emotion)) +
    geom_point(size = 3, alpha = 0.7) +
    scale_color_manual(
      values = emotion_colors,
      name = "Dominant Emotion"
    ) +
    scale_x_continuous(limits = c(0, 1)) +
    scale_y_continuous(limits = c(0, 1)) +
    labs(
      title = "Student Engagement vs Focus",
      x = "Average Engagement",
      y = "Average Focus"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

# Week-level graphs

render_weekly_lecture_emotions <- function(emotion_data, lecture_schedule, week_num) {
  if (nrow(emotion_data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  week_lectures <- lecture_schedule %>%
    filter(academic_week == week_num) %>%
    pull(lecture_id)

  week_data <- emotion_data %>%
    filter(lecture_id %in% week_lectures) %>%
    group_by(lecture_id, lecture_name) %>%
    summarise(
      happy = sum(emotion == "Happy"),
      neutral = sum(emotion == "Neutral"),
      confused = sum(emotion == "Confused"),
      bored = sum(emotion == "Bored"),
      .groups = "drop"
    ) %>%
    pivot_longer(
      cols = c(happy, neutral, confused, bored),
      names_to = "emotion",
      values_to = "count"
    )

  emotion_colors <- c(
    happy = "#10b981",
    neutral = "#6366f1",
    confused = "#f59e0b",
    bored = "#ef4444"
  )

  ggplot(week_data, aes(x = lecture_name, y = count, fill = emotion)) +
    geom_col(position = "stack") +
    scale_fill_manual(
      values = emotion_colors,
      name = "Emotion"
    ) +
    coord_flip() +
    labs(
      title = paste("Week", week_num, "- Emotion Distribution by Lecture"),
      x = "Lecture",
      y = "Emotion Count"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

# Semester-level graphs

render_semester_engagement_trend <- function(emotion_data) {
  if (nrow(emotion_data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  semester_data <- emotion_data %>%
    group_by(academic_week) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      avg_focus = mean(focus_score, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    pivot_longer(
      cols = c(avg_engagement, avg_focus),
      names_to = "metric",
      values_to = "value"
    ) %>%
    mutate(
      metric = factor(metric,
        levels = c("avg_engagement", "avg_focus"),
        labels = c("Engagement", "Focus")
      )
    )

  ggplot(semester_data, aes(x = academic_week, y = value, color = metric)) +
    geom_line(size = 1.2) +
    geom_point(size = 2.5) +
    scale_color_manual(
      values = c("Engagement" = "#10b981", "Focus" = "#3b82f6"),
      name = "Metric"
    ) +
    scale_x_continuous(breaks = 1:16) +
    scale_y_continuous(limits = c(0, 1)) +
    labs(
      title = "Semester Engagement & Focus Trends",
      x = "Academic Week",
      y = "Score"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_semester_confusion_trend <- function(emotion_data) {
  if (nrow(emotion_data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  semester_data <- emotion_data %>%
    group_by(academic_week) %>%
    summarise(
      confusion_rate = sum(emotion == "Confused") / n(),
      boredom_rate = sum(emotion == "Bored") / n(),
      .groups = "drop"
    ) %>%
    pivot_longer(
      cols = c(confusion_rate, boredom_rate),
      names_to = "metric",
      values_to = "value"
    ) %>%
    mutate(
      metric = factor(metric,
        levels = c("confusion_rate", "boredom_rate"),
        labels = c("Confusion", "Boredom")
      )
    )

  ggplot(semester_data, aes(x = academic_week, y = value, color = metric)) +
    geom_line(size = 1.2) +
    geom_point(size = 2.5) +
    scale_color_manual(
      values = c("Confusion" = "#f59e0b", "Boredom" = "#ef4444"),
      name = "Rate"
    ) +
    scale_x_continuous(breaks = 1:16) +
    scale_y_continuous(labels = scales::percent) +
    labs(
      title = "Semester Confusion & Boredom Trends",
      x = "Academic Week",
      y = "Rate"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}

render_course_engagement_comparison <- function(emotion_data) {
  if (nrow(emotion_data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No data available"))
  }

  course_data <- emotion_data %>%
    group_by(course_code) %>%
    summarise(
      avg_engagement = mean(engagement_score, na.rm = TRUE),
      avg_focus = mean(focus_score, na.rm = TRUE),
      .groups = "drop"
    )

  if (nrow(course_data) == 0) {
    return(ggplot() + theme_minimal() + ggtitle("No course data available"))
  }

  ggplot(course_data, aes(x = reorder(course_code, avg_engagement), y = avg_engagement, fill = avg_focus)) +
    geom_col() +
    scale_fill_gradient(low = "#ef4444", high = "#10b981", name = "Avg Focus") +
    coord_flip() +
    scale_y_continuous(limits = c(0, 1)) +
    labs(
      title = "Course Engagement Comparison",
      x = "Course",
      y = "Average Engagement"
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "#0b1220", color = NA),
      panel.background = element_rect(fill = "#111a2d", color = NA),
      text = element_text(color = "#f1f5f9", family = "sans"),
      axis.text = element_text(color = "#94a3b8"),
      legend.background = element_rect(fill = "#111a2d", color = NA),
      legend.text = element_text(color = "#f1f5f9"),
      panel.grid.major = element_line(color = "#1e293b", linewidth = 0.3)
    )
}
