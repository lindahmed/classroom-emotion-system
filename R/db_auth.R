# db_auth.R - PostgreSQL-based authentication for EduPulse AI
# Replaces hardcoded USERS list with bcrypt-verified DB auth

source("R/db_connect.R")

#' Authenticate a user against PostgreSQL
#' Uses PostgreSQL's crypt() with bcrypt for password verification
#' @param email Character
#' @param password Character (plaintext, hashed in DB)
#' @return Named list with safe user info, or NULL on failure
authenticate_user_pg <- function(email, password) {
  result <- db_query(
    "SELECT u.user_id, u.email, u.role::text AS role, u.institution_id, u.is_active,
            COALESCE(a.full_name, l.full_name, s.full_name) AS name,
            COALESCE(u.institution_id, l.lecturer_code, s.student_code) AS user_id_str
     FROM users u
     LEFT JOIN admins a ON u.user_id = a.user_id
     LEFT JOIN lecturers l ON u.user_id = l.user_id
     LEFT JOIN students s ON u.user_id = s.user_id
     WHERE lower(u.email) = lower($1)
        AND u.password_hash = crypt($2, u.password_hash)
        AND u.is_active = TRUE",
    list(email, password)
  )

  if (nrow(result) == 0) return(NULL)

  user <- result[1, ]
  list(
    user_id = user$user_id_str,
    email = user$email,
    role = capitalize_role(user$role),
    name = user$name,
    institution_id = user$institution_id,
    db_user_id = as.integer(user$user_id)
  )
}

#' Create a login session after successful auth
#' @param db_user_id Integer user_id from users table
#' @param ip_address Optional client IP
#' @return Session token (UUID string)
create_session <- function(db_user_id, ip_address = NULL) {
  token <- openssl::rand_uuid()
  token_hash <- hash_session_token(token)
  timeout_hours <- as.integer(get_setting("session_timeout_hours") %||% "24")
  expires_at <- format(Sys.time() + timeout_hours * 3600, "%Y-%m-%d %H:%M:%S")

  db_execute(
    "INSERT INTO login_sessions (user_id, token_hash, ip_address, expires_at)
     VALUES ($1, $2, $3::inet, $4)",
    list(as.integer(db_user_id), token_hash, ip_address %||% "127.0.0.1", expires_at)
  )

  log_audit(db_user_id, "LOGIN", "user", as.character(db_user_id))

  token
}

#' Validate an existing session token
#' @param token Session token string
#' @return TRUE if valid, FALSE otherwise
validate_session <- function(token) {
  token_hash <- hash_session_token(token)
  result <- db_query(
    "SELECT user_id FROM login_sessions
      WHERE token_hash = $1
        AND expires_at > NOW()
        AND revoked_at IS NULL",
    list(token_hash)
  )
  nrow(result) > 0
}

#' Destroy a session (logout)
#' @param token Session token string
destroy_session <- function(token) {
  token_hash <- hash_session_token(token)
  db_execute(
    "UPDATE login_sessions SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL",
    list(token_hash)
  )
}

#' Log an action to the audit trail
#' @param user_id Integer user ID (NULL for anonymous)
#' @param action Character action name
#' @param entity_type Character entity type
#' @param entity_id Character entity ID
log_audit <- function(user_id = NULL, action, entity_type = NULL, entity_id = NULL) {
  tryCatch({
    db_execute(
      "INSERT INTO audit_log (user_id, action, entity_type, entity_id) VALUES ($1, $2, $3, $4)",
      list(user_id, action, entity_type, entity_id)
    )
  }, error = function(e) {
    message(paste("Audit log error:", e$message))
  })
}

#' Update last login timestamp
update_last_login <- function(db_user_id) {
  db_execute(
    "UPDATE users SET last_login_at = NOW() WHERE user_id = $1",
    list(as.integer(db_user_id))
  )
}

#' Register a new account
#' Creates a user record + role-specific profile in PostgreSQL.
#' If registering a lecturer, optionally accepts teaching_assignments to create
#' lecturer_course_assignments + generate weekly lectures.
register_account_pg <- function(email, password, role, institution_id, full_name = NULL,
                                department_id = NULL,
                                teaching_assignments = NULL,
                                semester_id = NULL) {
  role <- normalize_role(role)
  institution_id <- normalize_institution_id(institution_id)
  full_name <- trimws(full_name %||% "")
  department_id <- if (is.null(department_id)) NA_integer_ else department_id

  if (nchar(trimws(password)) < 8) return(list(error = "Password must be at least 8 characters"))
  if (!grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimws(email), perl = TRUE)) {
    return(list(error = "Please enter a valid email address"))
  }
  if (nchar(full_name) < 2) return(list(error = "Please enter your full name"))
  if (is.null(role)) return(list(error = "Please choose a valid role"))

  id_error <- validate_institution_id(role, institution_id)
  if (!is.null(id_error)) return(list(error = id_error))

  if (identical(role, "lecturer") && !is.null(teaching_assignments)) {
    required_cols <- c("course_id", "group_id", "day_name", "start_time", "end_time", "room_id")
    missing_cols <- setdiff(required_cols, names(teaching_assignments))
    if (length(missing_cols) > 0) {
      return(list(error = paste0("Invalid teaching assignments (missing: ", paste(missing_cols, collapse = ", "), ")")))
    }
  }

  existing <- db_query(
    "SELECT email FROM users WHERE lower(email) = lower($1)",
    list(trimws(email))
  )
  if (nrow(existing) > 0) {
    return(list(error = "Email already registered"))
  }

  existing_id <- db_query(
    "SELECT institution_id FROM users WHERE lower(institution_id) = lower($1)",
    list(institution_id)
  )
  if (nrow(existing_id) > 0) {
    return(list(error = "Institution ID already registered"))
  }

  pool <- get_db_pool()

  tryCatch({
    pool::poolWithTransaction(pool, function(conn) {
      q <- function(sql, params = list()) {
        if (length(params) > 0) {
          res <- DBI::dbSendQuery(conn, sql)
          DBI::dbBind(res, params)
          out <- DBI::dbFetch(res)
          DBI::dbClearResult(res)
          out
        } else {
          DBI::dbGetQuery(conn, sql)
        }
      }

      exec <- function(sql, params = list()) {
        if (length(params) > 0) {
          res <- DBI::dbSendStatement(conn, sql)
          DBI::dbBind(res, params)
          rows <- DBI::dbGetRowsAffected(res)
          DBI::dbClearResult(res)
          rows
        } else {
          DBI::dbExecute(conn, sql)
        }
      }

      base_username <- gsub("[^a-z0-9_]", "_", tolower(sub("@.*$", "", trimws(email))))
      if (nchar(base_username) < 3) base_username <- "user"
      candidate <- substr(base_username, 1, 40)
      suffix <- 1L
      repeat {
        chk <- q("SELECT 1 FROM users WHERE username = $1 LIMIT 1", list(candidate))
        if (nrow(chk) == 0) break
        suffix <- suffix + 1L
        candidate <- substr(paste0(base_username, "_", suffix), 1, 50)
      }

      row <- q(
        "INSERT INTO users (username, email, password_hash, role, institution_id, is_active)
          VALUES ($1, $2, crypt($3, gen_salt('bf')), $4::user_role, $5, TRUE)
          RETURNING user_id",
        list(candidate, trimws(tolower(email)), password, role, institution_id)
      )
      user_id <- as.integer(row$user_id[1])

      if (role == "student") {
        exec(
          "INSERT INTO students (user_id, student_code, full_name, department_id, enrollment_year)
           VALUES ($1, $2, $3, $4, EXTRACT(YEAR FROM NOW())::integer)",
          list(user_id, institution_id, full_name, department_id)
        )
      } else if (role == "lecturer") {
        exec(
          "INSERT INTO lecturers (user_id, lecturer_code, full_name, department_id)
           VALUES ($1, $2, $3, $4)",
          list(user_id, institution_id, full_name, department_id)
        )

        if (!is.null(teaching_assignments) && nrow(teaching_assignments) > 0) {
          # Choose semester (active if available)
          semester_id_use <- semester_id %||% {
            sem <- q(
              "SELECT semester_id FROM semesters WHERE is_active = TRUE ORDER BY start_date DESC LIMIT 1",
              list()
            )
            if (nrow(sem) > 0) as.character(sem$semester_id[1]) else "SPRING2026"
          }

          lec_row <- q(
            "SELECT lecturer_id, lecturer_code FROM lecturers WHERE user_id = $1",
            list(user_id)
          )
          lecturer_db_id <- as.integer(lec_row$lecturer_id[1])
          lecturer_code  <- as.character(lec_row$lecturer_code[1])

          weeks <- q(
            "SELECT academic_week, start_date FROM semester_weeks WHERE semester_id = $1 ORDER BY academic_week",
            list(semester_id_use)
          )
          if (nrow(weeks) == 0) stop("No semester_weeks found for active semester")

          day_index <- c(Monday = 1L, Tuesday = 2L, Wednesday = 3L, Thursday = 4L, Friday = 5L, Saturday = 6L, Sunday = 7L)
          hash_hex <- function(txt) {
            raw <- openssl::sha1(charToRaw(txt))
            paste(sprintf("%02x", as.integer(raw)), collapse = "")
          }
          make_lecture_code <- function(parts) {
            paste0("L", substr(hash_hex(paste(parts, collapse = "|")), 1, 9))
          }

          for (i in seq_len(nrow(teaching_assignments))) {
            course_id <- as.integer(teaching_assignments$course_id[i])
            group_id  <- as.integer(teaching_assignments$group_id[i])
            day_name  <- as.character(teaching_assignments$day_name[i])
            start_t   <- as.character(teaching_assignments$start_time[i])
            end_t     <- as.character(teaching_assignments$end_time[i])
            room_id   <- as.integer(teaching_assignments$room_id[i])

            if (is.na(course_id) || is.na(group_id)) stop("Invalid course_id/group_id for lecturer assignment")
            if (!day_name %in% names(day_index)) stop(paste0("Invalid day_name: ", day_name))

            # Ensure group belongs to the selected course + semester
            ok <- q(
              "SELECT 1 FROM student_groups WHERE group_id = $1 AND course_id = $2 AND semester_id = $3 LIMIT 1",
              list(group_id, course_id, semester_id_use)
            )
            if (nrow(ok) == 0) stop("Selected group does not match the selected course/semester")

            arow <- q(
              "INSERT INTO lecturer_course_assignments (lecturer_id, course_id, group_id, semester_id, role)
               VALUES ($1, $2, $3, $4, 'primary')
               ON CONFLICT (lecturer_id, course_id, group_id, semester_id)
               DO UPDATE SET updated_at = NOW()
               RETURNING assignment_id",
              list(lecturer_db_id, course_id, group_id, semester_id_use)
            )
            assignment_id <- as.integer(arow$assignment_id[1])

            course <- q("SELECT course_code, course_name FROM courses WHERE course_id = $1", list(course_id))
            course_code <- as.character(course$course_code[1])

            grp <- q("SELECT group_code, group_name FROM student_groups WHERE group_id = $1", list(group_id))
            group_code <- as.character(grp$group_code[1])

            for (w in seq_len(nrow(weeks))) {
              academic_week <- as.integer(weeks$academic_week[w])
              week_start <- as.Date(weeks$start_date[w])
              week_start_u <- as.integer(format(week_start, "%u"))
              offset <- (day_index[[day_name]] - week_start_u + 7L) %% 7L
              lecture_date <- week_start + offset

              lecture_code <- make_lecture_code(c(lecturer_code, course_id, group_id, semester_id_use, academic_week, day_name, start_t, end_t))
              lecture_name <- paste0(course_code, " — ", group_code, " (Week ", academic_week, ")")

              q(
                "INSERT INTO lectures (lecture_code, lecture_name, assignment_id, semester_id, academic_week,
                                       lecture_date, day_name, start_time, end_time, room_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8::time, $9::time, $10, 'scheduled')
                 ON CONFLICT (lecture_code) DO UPDATE SET
                   lecture_name = EXCLUDED.lecture_name,
                   assignment_id = EXCLUDED.assignment_id,
                   semester_id = EXCLUDED.semester_id,
                   academic_week = EXCLUDED.academic_week,
                   lecture_date = EXCLUDED.lecture_date,
                   day_name = EXCLUDED.day_name,
                   start_time = EXCLUDED.start_time,
                   end_time = EXCLUDED.end_time,
                   room_id = EXCLUDED.room_id,
                   updated_at = NOW()",
                list(lecture_code, lecture_name, assignment_id, semester_id_use, academic_week,
                     lecture_date, day_name, start_t, end_t, if (is.na(room_id)) NULL else room_id)
              )
            }
          }
        }
      } else {
        exec(
          "INSERT INTO admins (user_id, full_name)
           VALUES ($1, $2)",
          list(user_id, full_name)
        )
      }

      exec(
        "INSERT INTO audit_log (user_id, action, entity_type, entity_id)
         VALUES ($1, 'REGISTER', $2, $3)",
        list(user_id, role, institution_id)
      )
    })

    list(
      success = TRUE,
      user_id = institution_id,
      email = trimws(tolower(email)),
      role = capitalize_role(role),
      institution_id = institution_id,
      name = full_name
    )
  }, error = function(e) {
    list(error = paste("Registration failed:", e$message))
  })
}

register_student_pg <- function(email, password, full_name, student_code,
                                department_id = NULL) {
  register_account_pg(
    email = email,
    password = password,
    role = "student",
    institution_id = student_code,
    full_name = full_name,
    department_id = department_id
  )
}

# Helpers

capitalize_role <- function(role) {
  paste0(toupper(substr(role, 1, 1)), tolower(substr(role, 2, nchar(role))))
}

normalize_role <- function(role) {
  role <- tolower(trimws(role %||% ""))
  if (role %in% c("student", "lecturer", "admin")) role else NULL
}

normalize_institution_id <- function(institution_id) {
  trimws(toupper(institution_id %||% ""))
}

validate_institution_id <- function(role, institution_id) {
  if (!nzchar(institution_id)) return("Please enter your institution ID")
  expected_prefix <- switch(role, student = "S", lecturer = "L", admin = "A")
  if (identical(role, "student") && grepl("^[0-9]+$", institution_id)) {
    return(NULL)
  }
  if (!startsWith(institution_id, expected_prefix)) {
    return(paste0(capitalize_role(role), " institution ID must start with ", expected_prefix))
  }
  NULL
}

# Null coalescing operator
`%||%` <- function(a, b) if (is.null(a)) b else a

hash_session_token <- function(token) {
  raw <- openssl::sha256(charToRaw(token))
  paste(sprintf("%02x", as.integer(raw)), collapse = "")
}
