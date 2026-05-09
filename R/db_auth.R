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
register_account_pg <- function(email, password, role, institution_id, full_name = NULL,
                                department_id = NULL) {
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
      base_username <- gsub("[^a-z0-9_]", "_", tolower(sub("@.*$", "", trimws(email))))
      if (nchar(base_username) < 3) base_username <- "user"
      candidate <- substr(base_username, 1, 40)
      suffix <- 1L
      repeat {
        chk_res <- DBI::dbSendQuery(conn, "SELECT 1 FROM users WHERE username = $1 LIMIT 1")
        DBI::dbBind(chk_res, list(candidate))
        chk <- DBI::dbFetch(chk_res)
        DBI::dbClearResult(chk_res)
        if (nrow(chk) == 0) break
        suffix <- suffix + 1L
        candidate <- substr(paste0(base_username, "_", suffix), 1, 50)
      }

      res <- DBI::dbSendQuery(conn,
        "INSERT INTO users (username, email, password_hash, role, institution_id, is_active)
          VALUES ($1, $2, crypt($3, gen_salt('bf')), $4::user_role, $5, TRUE)
          RETURNING user_id"
      )
      DBI::dbBind(res, list(candidate, trimws(tolower(email)), password, role, institution_id))
      row <- DBI::dbFetch(res)
      DBI::dbClearResult(res)
      user_id <- as.integer(row$user_id[1])

      if (role == "student") {
        res2 <- DBI::dbSendStatement(conn,
          "INSERT INTO students (user_id, student_code, full_name, department_id, enrollment_year)
           VALUES ($1, $2, $3, $4, EXTRACT(YEAR FROM NOW())::integer)"
        )
        DBI::dbBind(res2, list(user_id, institution_id, full_name, department_id))
      } else if (role == "lecturer") {
        res2 <- DBI::dbSendStatement(conn,
          "INSERT INTO lecturers (user_id, lecturer_code, full_name, department_id)
           VALUES ($1, $2, $3, $4)"
        )
        DBI::dbBind(res2, list(user_id, institution_id, full_name, department_id))
      } else {
        res2 <- DBI::dbSendStatement(conn,
          "INSERT INTO admins (user_id, full_name)
           VALUES ($1, $2)"
        )
        DBI::dbBind(res2, list(user_id, full_name))
      }
      DBI::dbClearResult(res2)

      res3 <- DBI::dbSendStatement(conn,
        "INSERT INTO audit_log (user_id, action, entity_type, entity_id)
         VALUES ($1, 'REGISTER', $2, $3)"
      )
      DBI::dbBind(res3, list(user_id, role, institution_id))
      DBI::dbClearResult(res3)
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
