# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Classroom Emotion System — an R Shiny dashboard for analyzing and visualizing student emotions in a classroom setting. Uses Python via `reticulate` for ML/emotion detection, with an SQLite backend for data storage.

## Tech Stack

- **R Shiny** with `bs4Dash` for the dashboard UI
- **reticulate** for R-Python interop (emotion detection models)
- **DBI** + **RSQLite** for database access
- **shinymanager** + **bcrypt** for authentication
- **cluster** + **factoextra** for clustering analysis
- **plotly** + **ggplot2** for visualization
- **DT** for interactive data tables
- **rmarkdown** for report generation

## Setup

Install all R dependencies:
```r
install.packages(c(
  "shiny", "bs4Dash", "dplyr", "ggplot2", "plotly", "DT",
  "tidyr", "lubridate", "DBI", "RSQLite", "reticulate",
  "shinymanager", "sodium", "bcrypt", "cluster", "factoextra",
  "bslib", "shinycssloaders", "rmarkdown", "jsonlite", "httr"
))
```

Open the project in RStudio via `classroom-emotion-system.Rproj`.

## Development

Run the Shiny app (once `app.R` or `ui.R`/`server.R` exist):
```r
shiny::runApp()
```

Check Python configuration for reticulate:
```r
library(reticulate)
py_config()
```
