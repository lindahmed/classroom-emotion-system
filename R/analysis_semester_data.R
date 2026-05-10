# analysis_semester_data.R — deterministic synthetic emotion rows before the active semester week.
#
# Weeks 1 .. ACTIVE-1: simulated from roster × lectures in schedule for that week.
# ACTIVE week: real rows only (scoped). Locked weeks excluded from merges (UI-driven).

EDUPULSE_ACTIVE_ACADEMIC_WEEK <- 13L
EDUPULSE_FIRST_LOCKED_WEEK <- 14L

edu_hash_u01 <- function(...) {
  s <- paste(unlist(list(...)), collapse = "|")
  ch <- enc2utf8(s)
  v <- suppressWarnings(utf8ToInt(ch))
  if (length(v) == 0L) return(0.5)
  ((((sum(abs(v)) * 7919L + nchar(ch) * 7937L)) %% 100003L) + 1L) / 100004L
}

edu_pick_emotion <- function(u_em) {
  if (u_em < 0.22) return("Happy")
  if (u_em < 0.50) return("Neutral")
  if (u_em < 0.78) return("Confused")
  "Bored"
}

edu_week_fallback_date <- function(academic_week_w) {
  as.Date("2026-02-09") + (as.integer(academic_week_w) - 1L) * 7L
}

edu_scope_emotion_frames <- function(fd, filter_course_choice, filter_group_choice) {
  if (is.null(fd) || nrow(fd) == 0L) return(fd)

  fc <- filter_course_choice
  if (!is.null(fc) && fc != "" && fc != "All") {
    cid <- suppressWarnings(as.integer(fc))
    if (!is.na(cid)) fd <- dplyr::filter(fd, course_id == cid)
  }

  fg <- filter_group_choice
  if (!is.null(fg) && fg != "" && fg != "All") {
    gid <- suppressWarnings(as.integer(fg))
    if (!is.na(gid)) fd <- dplyr::filter(fd, group_id == gid)
  }

  dplyr::distinct(fd)
}

edu_student_roster <- function(fd) {
  cols <- intersect(
    c(
      "student_id", "student_name", "course_id", "course_code", "course_name",
      "group_id", "group_name", "lecturer_id", "lecturer_name"
    ),
    names(fd)
  )
  dplyr::distinct(dplyr::select(fd, dplyr::all_of(cols)))
}

edu_scope_lecture_schedule <- function(sched, filter_course_choice, filter_group_choice, academic_week_w) {
  if (is.null(sched) || nrow(sched) == 0L) {
    return(NULL)
  }

  lt <- dplyr::filter(sched, academic_week == !!as.integer(academic_week_w))

  fc <- filter_course_choice
  if (!is.null(fc) && fc != "" && fc != "All") {
    cid <- suppressWarnings(as.integer(fc))
    if (!is.na(cid)) lt <- dplyr::filter(lt, course_id == cid)
  }

  fg <- filter_group_choice
  if (!is.null(fg) && fg != "" && fg != "All") {
    gid <- suppressWarnings(as.integer(fg))
    if (!is.na(gid)) lt <- dplyr::filter(lt, group_id == gid)
  }

  lt
}

edu_build_fake_week_records <- function(roster_templates, sched_rows_for_week, academic_week_w) {
  if (is.null(sched_rows_for_week)) sched_rows_for_week <- data.frame()
  w <- as.integer(academic_week_w)
  tmpl <- roster_templates

  col_order <- intersect(
    c(
      "record_id", "student_id", "student_name", "lecture_id", "lecture_name",
      "lecturer_id", "lecturer_name", "course_id", "course_code", "course_name",
      "group_id", "group_name", "academic_week", "timestamp", "time", "time_minute",
      "emotion", "confidence", "engagement_score", "focus_score",
      "attendance_status", "is_present", "left_room", "absence_duration_minutes",
      "source_type", "model_name"
    ),
    c(
      "record_id", "student_id", "student_name", "lecture_id", "lecture_name",
      "lecturer_id", "lecturer_name", "course_id", "course_code", "course_name",
      "group_id", "group_name", "academic_week", "timestamp", "time", "time_minute",
      "emotion", "confidence", "engagement_score", "focus_score",
      "attendance_status", "is_present", "left_room", "absence_duration_minutes",
      "source_type", "model_name"
    )
  )

  stopifnot(nrow(tmpl) >= 1L)

  base_rid <- -w * 1000000L
  row_ctr <- 0L
  rows_accum <- list()

  for (si in seq_len(nrow(tmpl))) {
    st <- tmpl[si, , drop = FALSE]
    scope_lec <- sched_rows_for_week
    if ("course_id" %in% names(scope_lec))
      scope_lec <- dplyr::filter(scope_lec, course_id == st$course_id[1])
    if ("group_id" %in% names(scope_lec))
      scope_lec <- dplyr::filter(scope_lec, group_id == st$group_id[1])

    if (!is.null(scope_lec) && nrow(scope_lec) >= 1L) {
      lec_seq <- seq_len(nrow(scope_lec))
    } else {
      scope_lec <- data.frame(
        lecture_id = sprintf(
          "SYN-%s-W%02d-G%s-%s",
          st$course_code[1], w, st$group_id[1], st$student_id[1]
        ),
        lecture_name = sprintf("%s (simulated)", st$course_name[1]),
        lecturer_id = st$lecturer_id[1],
        lecturer_name = st$lecturer_name[1],
        lecture_date = edu_week_fallback_date(w),
        course_id = st$course_id[1],
        group_id = st$group_id[1],
        stringsAsFactors = FALSE
      )
      lec_seq <- 1L
    }

    for (lj in lec_seq) {
      lr <- scope_lec[lj, , drop = FALSE]
      ldate <- if ("lecture_date" %in% names(lr)) {
        suppressWarnings(as.Date(lr$lecture_date[1]))
      } else edu_week_fallback_date(w)
      if (length(ldate) != 1L || is.na(ldate)) ldate <- edu_week_fallback_date(w)

      lect_id <- as.character(lr$lecture_id[1])
      lect_nm <- if ("lecture_name" %in% names(lr)) as.character(lr$lecture_name[1]) else lect_id
      lecid <- if ("lecturer_id" %in% names(lr)) lr$lecturer_id[1] else st$lecturer_id[1]
      lecnm <- if ("lecturer_name" %in% names(lr)) lr$lecturer_name[1] else st$lecturer_name[1]

      minute_seq <- seq(0L, 20L, by = 5L)
      for (minute in minute_seq) {
        row_ctr <- row_ctr + 1L
        u_e <- edu_hash_u01(as.character(st$student_id[[1]]), w, lect_id, minute, "emo")
        u_en <- edu_hash_u01(as.character(st$student_id[[1]]), w, lect_id, minute, "eng")
        u_fc <- edu_hash_u01(as.character(st$student_id[[1]]), w, lect_id, minute, "focus")
        u_abs <- edu_hash_u01(as.character(st$student_id[[1]]), w, lect_id, minute, "abs")
        emotion <- edu_pick_emotion(u_e)
        absent <- u_abs > 0.93
        is_present_val <- !absent

        eng <- ifelse(
          emotion == "Confused",
          0.38 + u_en * 0.42,
          ifelse(emotion == "Bored", 0.22 + u_en * 0.42, 0.55 + u_en * 0.38)
        )
        fcscore <- ifelse(absent, 0.18 + u_fc * 0.35, 0.48 + u_fc * 0.48)

        ts <- suppressWarnings(as.POSIXct(
          paste(ldate, sprintf("%02d:%02d", 10L + (minute %/% 60L), minute %% 60L)),
          tz = "UTC"
        ))
        if (!inherits(ts, "POSIXct") || length(ts) != 1L || is.na(ts)) {
          ts <- as.POSIXct(paste(edu_week_fallback_date(w), "10:00:00"), tz = "UTC")
        }

        rows_accum[[row_ctr]] <- data.frame(
          record_id = base_rid - row_ctr,
          student_id = st$student_id,
          student_name = st$student_name,
          lecture_id = lect_id,
          lecture_name = lect_nm,
          lecturer_id = lecid,
          lecturer_name = lecnm,
          course_id = st$course_id,
          course_code = st$course_code,
          course_name = st$course_name,
          group_id = st$group_id,
          group_name = st$group_name,
          academic_week = w,
          timestamp = ts,
          time = sprintf("%02d:%02d", lubridate::hour(ts), lubridate::minute(ts)),
          time_minute = as.integer(minute),
          emotion = emotion,
          confidence = 0.75 + edu_hash_u01("conf", st$student_id[[1]], w, lect_id, minute) * 0.23,
          engagement_score = pmin(eng, 0.98),
          focus_score = pmin(fcscore, 0.98),
          attendance_status = ifelse(is_present_val, "Present", "Absent"),
          is_present = is_present_val,
          left_room = absent,
          absence_duration_minutes = ifelse(absent, as.integer(8 + edu_hash_u01("abm", st$student_id[[1]]) * 28), 0L),
          source_type = "simulated_prior_week",
          model_name = "EduPulse_sim_v1",
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (row_ctr == 0L || length(rows_accum) == 0L) return(tmpl[FALSE, ])
  dplyr::bind_rows(rows_accum) %>%
    dplyr::select(dplyr::any_of(col_order))
}

edu_normalize_times_for_merge <- function(d) {
  if (is.null(d) || nrow(d) == 0L) {
    return(d)
  }

  ts <- suppressWarnings(as.POSIXct(d[["timestamp"]]))
  attr(ts, "tzone") <- "UTC"

  d$timestamp <- ts
  d$time <- ifelse(
    is.na(ts),
    rep(NA_character_, length(ts)),
    format(ts, "%H:%M", tz = "UTC")
  )
  d
}

# Strip RPostgres pq_* / enum S3 classes so dplyr::bind_rows & summaries never mix pq types with character.
edu_sanitize_postgres_frame <- function(d) {
  if (is.null(d) || nrow(d) == 0L) {
    return(d)
  }

  col_to_chr <- function(x) {
    if (is.factor(x)) {
      return(unname(as.character(x)))
    }
    unname(as.character(x))
  }

  for (nm in names(d)) {
    x <- d[[nm]]
    if (inherits(x, "POSIXt") || inherits(x, "Date")) {
      next
    }
    if (is.list(x) && !inherits(x, "data.frame")) {
      next
    }

    cl <- class(x)
    is_pq <- length(cl) > 0L && any(grepl("^pq_", cl, perl = TRUE))
    force_chr <- is_pq ||
      nm %in% c("emotion", "attendance_status", "source_type", "model_name")

    if (force_chr) {
      d[[nm]] <- tryCatch(
        col_to_chr(x),
        error = function(e) unname(format(x, trim = TRUE))
      )
    }
  }

  d
}

edu_coerce_emotion_plain_types <- function(d) {
  if (is.null(d) || nrow(d) == 0L) {
    return(d)
  }
  d <- edu_sanitize_postgres_frame(d)
  edu_normalize_times_for_merge(d)
}


edu_merge_prior_synthetic_weeks <- function(full_fd, lecture_sched, fc, gs) {
  scoped_fd <- edu_sanitize_postgres_frame(edu_scope_emotion_frames(full_fd, fc, gs))
  roster <- edu_student_roster(scoped_fd)

  if (is.null(roster) || nrow(roster) == 0L) {
    real_only <- dplyr::filter(scoped_fd, academic_week == EDUPULSE_ACTIVE_ACADEMIC_WEEK)
    return(edu_coerce_emotion_plain_types(real_only))
  }

  tmpl <- dplyr::slice_head(roster, n = min(nrow(roster), 400L))

  syn_parts <- vector("list", max(EDUPULSE_ACTIVE_ACADEMIC_WEEK - 1L, 0L))
  if (length(syn_parts) > 0L) {
    for (w in seq_along(syn_parts)) {
      lw <- edu_scope_lecture_schedule(lecture_sched, fc, gs, w)
      syn_parts[[w]] <- edu_build_fake_week_records(tmpl, lw, w)
    }
  }

  synth_raw <- edu_sanitize_postgres_frame(dplyr::bind_rows(syn_parts))
  real_act_raw <- dplyr::filter(scoped_fd, academic_week == EDUPULSE_ACTIVE_ACADEMIC_WEEK)

  synth <- edu_coerce_emotion_plain_types(synth_raw)
  real_act <- edu_coerce_emotion_plain_types(real_act_raw)

  out <- dplyr::bind_rows(synth, real_act)
  edu_sanitize_postgres_frame(out)
}
