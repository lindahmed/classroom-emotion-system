#!/usr/bin/env Rscript
# EduPulse AI - Shiny Application Launcher

# Check for required packages
required_packages <- c(
  "shiny", "bslib", "dplyr", "ggplot2", "readr", "tidyr",
  "lubridate", "DT", "htmltools", "shinyjs", "scales"
)

missing_packages <- setdiff(required_packages, rownames(installed.packages()))

if (length(missing_packages) > 0) {
  cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
  install.packages(missing_packages)
}

# Load the app
shiny::runApp(appDir = ".", launch.browser = TRUE)
