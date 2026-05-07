# db_connect.R — PostgreSQL connection pool for EduPulse AI
# Provides pool-based database connections for Shiny reactivity

library(RPostgres)
library(pool)
library(DBI)

# Connection config (override via environment variables)
DB_CONFIG <- list(
  host     = Sys.getenv("EDUPULSE_DB_HOST",     "localhost"),
  port     = as.integer(Sys.getenv("EDUPULSE_DB_PORT",     "5432")),
  dbname   = Sys.getenv("EDUPULSE_DB_NAME",     "edupulse"),
  user     = Sys.getenv("EDUPULSE_DB_USER",     "edupulse_app"),
  password = Sys.getenv("EDUPULSE_DB_PASSWORD", "edupulse_pass")
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
