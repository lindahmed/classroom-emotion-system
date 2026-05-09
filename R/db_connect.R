# db_connect.R — PostgreSQL connection pool for EduPulse AI
# Provides pool-based database connections for Shiny reactivity

library(RPostgres)
library(pool)
library(DBI)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a) || !nzchar(as.character(a))) b else a

load_env_file <- function(path = ".env") {
  if (!file.exists(path)) return(invisible(FALSE))

  lines <- readLines(path, warn = FALSE)
  for (line in lines) {
    line <- trimws(line)
    if (!nzchar(line) || startsWith(line, "#") || !grepl("=", line, fixed = TRUE)) next

    key <- trimws(sub("=.*$", "", line))
    value <- trimws(sub("^[^=]*=", "", line))
    value <- sub("^['\"]", "", sub("['\"]$", "", value))

    if (nzchar(key) && !nzchar(Sys.getenv(key, unset = ""))) {
      do.call(Sys.setenv, stats::setNames(list(value), key))
    }
  }

  invisible(TRUE)
}

parse_database_url <- function(database_url) {
  if (!nzchar(database_url)) return(list())

  match <- regexec("^postgres(?:ql)?://([^:/@]+)(?::([^@]*))?@([^:/?]+)(?::([0-9]+))?/([^?]+)", database_url)
  parts <- regmatches(database_url, match)[[1]]
  if (length(parts) == 0) return(list())

  list(
    user = utils::URLdecode(parts[2]),
    password = if (length(parts) >= 3) utils::URLdecode(parts[3]) else "",
    host = parts[4],
    port = if (length(parts) >= 5 && nzchar(parts[5])) as.integer(parts[5]) else 5432L,
    dbname = if (length(parts) >= 6) utils::URLdecode(parts[6]) else ""
  )
}

load_env_file()
database_url_config <- parse_database_url(Sys.getenv("DATABASE_URL", Sys.getenv("EDUPULSE_DATABASE_URL", "")))

# Connection config (override via environment variables)
DB_CONFIG <- list(
  host     = Sys.getenv("EDUPULSE_DB_HOST",     database_url_config$host %||% "localhost"),
  port     = as.integer(Sys.getenv("EDUPULSE_DB_PORT",     as.character(database_url_config$port %||% 5432L))),
  dbname   = Sys.getenv("EDUPULSE_DB_NAME",     database_url_config$dbname %||% "EduPulse AI"),
  user     = Sys.getenv("EDUPULSE_DB_USER",     database_url_config$user %||% "postgres"),
  password = Sys.getenv("EDUPULSE_DB_PASSWORD", database_url_config$password %||% "")
)

# Global pool reference
.db_pool <- NULL

#' Get or create the database connection pool
#' @return Pool object
get_db_pool <- function() {
  if (is.null(.db_pool) || !pool::dbIsValid(.db_pool)) {
    .db_pool <<- pool::dbPool(
      drv      = RPostgres::Postgres(),
      host     = DB_CONFIG$host,
      port     = DB_CONFIG$port,
      dbname   = DB_CONFIG$dbname,
      user     = DB_CONFIG$user,
      password = DB_CONFIG$password,
      minSize  = 1,
      maxSize  = 5,
      idleTimeout = 300000
    )
  }
  .db_pool
}

#' Close the database pool (call on app stop)
close_db_pool <- function() {
  if (!is.null(.db_pool) && pool::dbIsValid(.db_pool)) {
    pool::poolClose(.db_pool)
    .db_pool <<- NULL
  }
}

#' Execute a parameterized query and return results as tibble
#' @param query SQL string with $1, $2, etc. placeholders
#' @param params List of parameters
#' @return tibble
db_query <- function(query, params = list()) {
  pool <- get_db_pool()
  pool::poolWithTransaction(pool, function(conn) {
    if (length(params) > 0) {
      res <- DBI::dbSendQuery(conn, query)
      DBI::dbBind(res, params)
      out <- DBI::dbFetch(res)
      DBI::dbClearResult(res)
    } else {
      out <- DBI::dbGetQuery(conn, query)
    }
    tibble::as_tibble(out)
  })
}

#' Execute a parameterized statement (INSERT, UPDATE, DELETE)
#' @param query SQL string with $1, $2, etc. placeholders
#' @param params List of parameters
#' @return Number of affected rows
db_execute <- function(query, params = list()) {
  pool <- get_db_pool()
  pool::poolWithTransaction(pool, function(conn) {
    if (length(params) > 0) {
      res <- DBI::dbSendStatement(conn, query)
      DBI::dbBind(res, params)
      rows <- DBI::dbGetRowsAffected(res)
      DBI::dbClearResult(res)
    } else {
      res <- DBI::dbExecute(conn, query)
      rows <- res
    }
    rows
  })
}

ensure_auth_schema <- function() {
  pool <- get_db_pool()
  pool::poolWithTransaction(pool, function(conn) {
    required_tables <- c("users", "students", "lecturers", "admins", "login_sessions")
    existing <- DBI::dbGetQuery(
      conn,
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
    )$table_name

    missing <- setdiff(required_tables, existing)
    if (length(missing) > 0) {
      stop(
        "Database schema is incomplete. Missing table(s): ",
        paste(missing, collapse = ", "),
        ". Run setup_database.R before starting the app."
      )
    }

    DBI::dbExecute(conn, 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
    DBI::dbExecute(conn, "ALTER TABLE users ADD COLUMN IF NOT EXISTS institution_id VARCHAR(20)")
    code_length <- DBI::dbGetQuery(
      conn,
      "SELECT character_maximum_length
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'students'
         AND column_name = 'student_code'"
    )$character_maximum_length
    if (length(code_length) > 0 && !is.na(code_length[1]) && code_length[1] < 20) {
      DBI::dbExecute(conn, "SAVEPOINT widen_student_code")
      tryCatch({
        DBI::dbExecute(conn, "ALTER TABLE students ALTER COLUMN student_code TYPE VARCHAR(20)")
      }, error = function(e) {
        DBI::dbExecute(conn, "ROLLBACK TO SAVEPOINT widen_student_code")
      })
      DBI::dbExecute(conn, "RELEASE SAVEPOINT widen_student_code")
    }
    DBI::dbExecute(
      conn,
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_institution_id_unique
       ON users (lower(institution_id))
       WHERE institution_id IS NOT NULL"
    )
    DBI::dbExecute(
      conn,
      "CREATE TABLE IF NOT EXISTS student_face_photos (
         photo_id BIGSERIAL PRIMARY KEY,
         student_id INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
         source_url TEXT NOT NULL,
         source_file_id VARCHAR(128),
         local_path VARCHAR(500),
         is_downloaded BOOLEAN NOT NULL DEFAULT FALSE,
         download_error TEXT,
         created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
         updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
         UNIQUE (student_id, source_url)
       )"
    )
    DBI::dbExecute(
      conn,
      "CREATE TABLE IF NOT EXISTS attendance_sessions (
         session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
         lecture_id INTEGER NOT NULL UNIQUE REFERENCES lectures(lecture_id) ON DELETE CASCADE,
         started_by INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
         started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
         ended_at TIMESTAMP WITH TIME ZONE,
         status VARCHAR(20) NOT NULL DEFAULT 'active',
         created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
         updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
         CONSTRAINT chk_attendance_session_status CHECK (status IN ('active', 'completed', 'cancelled')),
         CONSTRAINT chk_attendance_session_times CHECK (ended_at IS NULL OR ended_at >= started_at)
       )"
    )
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_student_face_photos_student ON student_face_photos(student_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_student_face_photos_file_id ON student_face_photos(source_file_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_attendance_sessions_lecture ON attendance_sessions(lecture_id)")
    DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_attendance_sessions_status ON attendance_sessions(status)")

    TRUE
  })
}
