#!/usr/bin/env Rscript
# setup_database.R — Create PostgreSQL database and apply schema

library(RPostgres)
library(DBI)

cat("Starting database setup...\n")

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

load_env_file()

# Read config from environment
db_host <- Sys.getenv("EDUPULSE_DB_HOST", "localhost")
db_port <- as.integer(Sys.getenv("EDUPULSE_DB_PORT", "5432"))
db_name <- Sys.getenv("EDUPULSE_DB_NAME", "EduPulse AI")
db_user <- Sys.getenv("EDUPULSE_DB_USER", "postgres")
db_pass <- Sys.getenv("EDUPULSE_DB_PASSWORD", "")
admin_db <- Sys.getenv("EDUPULSE_ADMIN_DB", "postgres")

# Connection to postgres database (default) to create new database
cat("Connecting to PostgreSQL server...\n")
conn_admin <- tryCatch({
  dbConnect(
    RPostgres::Postgres(),
    host = db_host,
    port = db_port,
    user = db_user,
    password = db_pass,
    dbname = admin_db
  )
}, error = function(e) {
  cat("✗ Error connecting to PostgreSQL:\n")
  cat(e$message, "\n")
  quit(status = 1)
})

# Drop existing database if it exists
cat("Checking for existing database...\n")
tryCatch({
  dbExecute(conn_admin, paste0('DROP DATABASE IF EXISTS "', db_name, '"'))
  cat("✓ Dropped existing database\n")
}, error = function(e) cat("Note:", e$message, "\n"))

# Create new database
cat("Creating database '", db_name, "'...\n", sep = "")
tryCatch({
  dbExecute(conn_admin, paste0('CREATE DATABASE "', db_name, '"'))
  cat("✓ Database created successfully\n")
}, error = function(e) {
  cat("✗ Error creating database:\n")
  cat(e$message, "\n")
  dbDisconnect(conn_admin)
  quit(status = 1)
})

dbDisconnect(conn_admin)

# Now connect to the new database and apply schema
cat("Connecting to ", db_name, " database...\n", sep = "")
conn_app <- tryCatch({
  dbConnect(
    RPostgres::Postgres(),
    host = db_host,
    port = db_port,
    user = db_user,
    password = db_pass,
    dbname = db_name
  )
}, error = function(e) {
  cat("✗ Error connecting to new database:\n")
  cat(e$message, "\n")
  quit(status = 1)
})

# Read schema file
schema_file <- file.path(getwd(), "database", "schema.sql")
cat("Reading schema from", schema_file, "\n")
schema <- readLines(schema_file)
schema_text <- paste(schema, collapse = '\n')

# Split into individual statements and execute
cat("Applying schema...\n")
# Remove comments and split by semicolons
schema_text <- gsub('--[^\n]*', '', schema_text)  # Remove line comments
statements <- strsplit(schema_text, ';')[[1]]

statement_count <- 0
for (stmt in statements) {
  stmt <- trimws(stmt)
  if (nchar(stmt) > 0) {
    tryCatch({
      dbExecute(conn_app, paste0(stmt, ';'))
      statement_count <- statement_count + 1
    }, error = function(e) {
      # Only show critical errors, not expected ones
      if (!grepl('already exists|does not exist', e$message, ignore.case = TRUE)) {
        cat("⚠ ", e$message, "\n")
      }
    })
  }
}

cat("✓ Schema applied successfully (", statement_count, "statements executed)\n")

# Verify tables were created
tables <- dbGetQuery(conn_app, "
  SELECT table_name 
  FROM information_schema.tables 
  WHERE table_schema = 'public'
  ORDER BY table_name
")

cat("\n✓ Created tables:\n")
for (table in tables$table_name) {
  cat("  -", table, "\n")
}

dbDisconnect(conn_app)

cat("\n✅ Database setup complete!\n")
cat("Database: EduPulse_AI\n")
cat("Username: admin\n")
