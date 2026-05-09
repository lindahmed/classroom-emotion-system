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

    DBI::dbExecute(conn, "ALTER TABLE users ADD COLUMN IF NOT EXISTS institution_id VARCHAR(20)")
    DBI::dbExecute(
      conn,
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_institution_id_unique
       ON users (lower(institution_id))
       WHERE institution_id IS NOT NULL"
    )

    TRUE
  })
}
