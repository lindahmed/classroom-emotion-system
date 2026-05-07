# db_auth.R — PostgreSQL-based authentication for EduPulse AI
# Replaces hardcoded USERS list with bcrypt-verified DB auth

source("R/db_connect.R")

#' Authenticate a user against PostgreSQL
#' Uses PostgreSQL's crypt() with bcrypt for password verification
#' @param username Character
#' @param password Character (plaintext, hashed in DB)
#' @return Named list with user info, or NULL on failure
authenticate_user_pg <- function(username, password) {
  result <- db_query(
    "SELECT u.user_id, u.username, u.role::text AS role, u.is_active,
            COALESCE(a.full_name, l.full_name, s.full_name) AS name,
            COALESCE(l.lecturer_code, s.student_code, 'ADMIN') AS user_id_str
     FROM users u
     LEFT JOIN admins a ON u.user_id = a.user_id
     LEFT JOIN lecturers l ON u.user_id = l.user_id
     LEFT JOIN students s ON u.user_id = s.user_id
     WHERE u.username = $1
       AND u.password_hash = crypt($2, u.password_hash)
       AND u.is_active = TRUE",
    list(username, password)
  )

  if (nrow(result) == 0) return(NULL)

  user <- result[1, ]
  list(
    user_id   = user$user_id_str,
    username  = user$username,
    role      = capitalize_role(user$role),
    name      = user$name,
    db_user_id = as.integer(user$user_id)
  )
}

#' Create a login session after successful auth
#' @param db_user_id Integer user_id from users table
#' @param ip_address Optional client IP
#' @return Session token (UUID string)
create_session <- function(db_user_id, ip_address = NULL) {
  token <- openssl::rand_uuid()
  timeout_hours <- as.integer(get_setting("session_timeout_hours") %||% "24")
  expires_at <- format(Sys.time() + timeout_hours * 3600, "%Y-%m-%d %H:%M:%S")

  db_execute(
    "INSERT INTO login_sessions (user_id, token_hash, ip_address, expires_at)
     VALUES ($1, $2, $3::inet, $4)",
    list(as.integer(db_user_id), token, ip_address %||% "127.0.0.1", expires_at)
  )

  # Log the login
  log_audit(db_user_id, "LOGIN", "user", as.character(db_user_id))

  token
}

#' Validate an existing session token
#' @param token Session token string
#' @return TRUE if valid, FALSE otherwise
validate_session <- function(token) {
  result <- db_query(
    "SELECT user_id FROM login_sessions
     WHERE token_hash = $1
       AND expires_at > NOW()
       AND revoked_at IS NULL",
    list(token)
  )
  nrow(result) > 0
}

#' Destroy a session (logout)
#' @param token Session token string
destroy_session <- function(token) {
  db_execute(
    "UPDATE login_sessions SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL",
    list(token)
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

#' Register a new student account
#' Creates a user record + student profile in PostgreSQL
#' @param username Desired username
#' @param email Student email
#' @param password Plaintext password (will be bcrypt-hashed in DB)
#' @param full_name Student's full name
#' @param student_code Student ID code (e.g., S121)
#' @param department_id Optional department ID
#' @return Named list with user info on success, or list with error message
register_student_pg <- function(username, email, password, full_name, student_code,
                                  department_id = NULL) {
  # Validate inputs
  if (nchar(trimws(username)) < 3) return(list(error = "Username must be at least 3 characters"))
  if (nchar(trimws(password)) < 6) return(list(error = "Password must be at least 6 characters"))
  if (!grepl("@", email)) return(list(error = "Please enter a valid email address"))
  if (nchar(trimws(full_name)) < 2) return(list(error = "Please enter your full name"))
  if (nchar(trimws(student_code)) < 2) return(list(error = "Please enter your student ID"))

  # Check if username or email already exists
  existing <- db_query(
    "SELECT username, email FROM users WHERE username = $1 OR email = $2",
    list(trimws(username), trimws(email))
  )
  if (nrow(existing) > 0) {
    if (any(existing$username == trimws(username))) {
      return(list(error = "Username already taken"))
    }
    if (any(existing$email == trimws(email))) {
      return(list(error = "Email already registered"))
    }
  }

  # Check if student_code already exists
  existing_code <- db_query(
    "SELECT student_code FROM students WHERE student_code = $1",
    list(trimws(toupper(student_code)))
  )
  if (nrow(existing_code) > 0) {
    return(list(error = "Student ID already registered"))
  }

  pool <- get_db_pool()

  tryCatch({
    pool::poolWithTransaction(pool, function(conn) {
      # Create user with bcrypt-hashed password
      res <- DBI::dbSendQuery(conn,
        "INSERT INTO users (username, email, password_hash, role, is_active)
         VALUES ($1, $2, crypt($3, gen_salt('bf')), 'student', TRUE)
         RETURNING user_id"
      )
      DBI::dbBind(res, list(trimws(username), trimws(email), password))
      row <- DBI::dbFetch(res)
      DBI::dbClearResult(res)
      user_id <- as.integer(row$user_id[1])

      # Create student profile
      res2 <- DBI::dbSendStatement(conn,
        "INSERT INTO students (user_id, student_code, full_name, department_id, enrollment_year)
         VALUES ($1, $2, $3, $4, 2026)"
      )
      DBI::dbBind(res2, list(user_id, trimws(toupper(student_code)), trimws(full_name), NA_integer_))
      DBI::dbClearResult(res2)

      # Audit log
      res3 <- DBI::dbSendStatement(conn,
        "INSERT INTO audit_log (user_id, action, entity_type, entity_id)
         VALUES ($1, 'REGISTER', 'student', $2)"
      )
      DBI::dbBind(res3, list(user_id, trimws(toupper(student_code))))
      DBI::dbClearResult(res3)
    })

    # Return success — authenticate the new user
    list(
      success = TRUE,
      user_id = trimws(toupper(student_code)),
      username = trimws(username),
      role = "Student",
      name = trimws(full_name)
    )
  }, error = function(e) {
    list(error = paste("Registration failed:", e$message))
  })
}

# Helpers

capitalize_role <- function(role) {
  paste0(toupper(substr(role, 1, 1)), tolower(substr(role, 2, nchar(role))))
}

# Null coalescing operator
`%||%` <- function(a, b) if (is.null(a)) b else a
