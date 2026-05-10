library(shiny)
library(bslib)
library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)
library(lubridate)
library(DT)
library(htmltools)
library(scales)
library(shinyjs)
library(httr)
library(jsonlite)
library(openssl)
library(promises)
library(future)

# Optional project `.env` (KEY=value, no `export`) — DATABASE_URL / EDUPULSE_* for R before helpers load.
if (file.exists(".env")) {
  suppressWarnings(tryCatch(readRenviron(".env"), error = function(e) invisible(NULL)))
}

# Load helper functions
source("R/db_connect.R")
source("R/db_auth.R")
source("R/db_queries.R")
source("R/data_helpers.R")
source("R/analytics_helpers.R")
source("R/ui_helpers.R")
source("R/csv_backup.R")
source("R/analysis_semester_data.R")

# Initialize database pool on app start
# (conditional — falls back to CSV if DB unavailable)
.db_init_error <- NULL
.try_db_init <- if (isTRUE(USE_DATABASE)) {
  tryCatch({
    get_db_pool()
    ensure_auth_schema()
    TRUE
  }, error = function(e) {
    .db_init_error <<- e$message
    message(paste("Database not available, using CSV fallback:", e$message))
    FALSE
  })
} else {
  FALSE
}

# Use background R sessions for async operations (prevents UI freeze)
plan(multisession)

# Initialize app-level data
app_data <- reactiveValues(
  all_data = NULL,
  filtered_data = NULL,
  lecture_schedule = NULL,
  semester_weeks = NULL,
  user_role = NULL,
  user_id = NULL,
  institution_id = NULL,
  user_name = NULL,
  user_email = NULL,
  db_user_id = NULL,
  api_token = NULL,
  selected_week = 13,
  selected_lecture_id = NULL,
  start_session_request = NULL,
  live_face_response = NULL,
  live_attendance = NULL,
  session_mode = "full"
)

# Authenticate user via PostgreSQL (email + password)
authenticate_user <- function(email, password) {
  if (!.try_db_init) {
    return(NULL)
  }
  tryCatch({
    authenticate_user_pg(email, password)
  }, error = function(e) NULL)
}

# API configuration (mirror browser camera JS via EDUPULSE_API_BASE_URL — no trailing slash)
API_BASE_URL <- sub("/+$", "", trimws(Sys.getenv("EDUPULSE_API_BASE_URL", "http://localhost:8000")))

# Turn attendance JSON payloads into one stable roster data.frame & trim quirks that break summaries.
normalize_live_attendance <- function(att) {
  if (is.null(att)) return(NULL)
  if (inherits(att, "tbl_df")) att <- as.data.frame(att, stringsAsFactors = FALSE)
  if (!inherits(att, "data.frame") && inherits(att, "list")) {
    if (length(att) == 0L) return(NULL)
    merged <- NULL
    if (length(att) >= 1L && is.list(att[[1L]])) {
      merged <- tryCatch({
        dplyr::bind_rows(lapply(att, function(r) {
          if (!is.list(r)) return(NULL)
          as.data.frame(r, stringsAsFactors = FALSE)
        }))
      }, error = function(e) NULL)
    }
    if (!is.null(merged) && ncol(merged) > 0) {
      att <- as.data.frame(merged, stringsAsFactors = FALSE)
    } else {
      att <- tryCatch(as.data.frame(att, stringsAsFactors = FALSE), error = function(e) NULL)
    }
  }
  if (!is.data.frame(att) || nrow(att) == 0) return(if (inherits(att, "data.frame")) att else NULL)
  if ("student_code" %in% names(att) && !"student_id" %in% names(att)) names(att)[names(att) == "student_code"] <- "student_id"
  if ("status" %in% names(att)) {
    ch <- ifelse(is.na(att$status), "", trimws(as.character(att$status)))
    ch <- ifelse(nzchar(ch), ch, "Absent")
    att$status <- ch
  }
  att
}

# Reload roster snapshot from backend (FastAPI POST /start-session does not embed attendance.)
refresh_live_roster <- function(lecture_id, token) {
  if (is.null(lecture_id) || !nzchar(as.character(lecture_id))) return(NULL)
  if (is.null(token) || !nzchar(as.character(token))) return(NULL)
  snap <- tryCatch(call_api(paste0("/attendance/", lecture_id), token = token, timeout_sec = 30),
                   error = function(e) NULL)
  if (!is.null(snap) && !isTRUE(snap$error) && !is.null(snap$attendance)) normalize_live_attendance(snap$attendance) else NULL
}

# Robust present tally (PostgreSQL/driver/jsonlite sometimes mixes casing/spaces.)
attendance_present_count <- function(att) {
  if (is.null(att) || !is.data.frame(att) || nrow(att) == 0) return(0L)
  if (!("status" %in% names(att))) return(0L)
  s <- tolower(trimws(as.character(att$status)))
  as.integer(sum(!is.na(s) & s %in% c("present", "returned"), na.rm = TRUE))
}

# FastAPI `/analyze-attendance-frame` uses scalar `recognized` (TRUE/FALSE) + flat fields;
# legacy payloads used `recognized` as a dataframe / list — normalize for observers + summary UI.
edu_normalize_live_frame_payload <- function(parsed) {
  if (is.null(parsed) || !is.list(parsed)) return(parsed)

  blank_df <- data.frame(
    student_id = character(),
    student_name = character(),
    emotion = character(),
    face_confidence = numeric(),
    stringsAsFactors = FALSE
  )

  rid <- parsed$recognized
  if (is.null(rid)) {
    parsed$recognized <- blank_df
    return(parsed)
  }

  if (is.data.frame(rid) && nrow(rid) > 0L) return(parsed)

  if (is.list(rid) && length(rid) >= 1L && all(vapply(rid, is.list, FUN.VALUE = logical(1)))) {
    parsed$recognized <- dplyr::bind_rows(lapply(rid, function(x) as.data.frame(x, stringsAsFactors = FALSE)))
    return(parsed)
  }

  if (is.logical(rid) && length(rid) == 1L) {
    if (isTRUE(rid)) {
      sid <- trimws(paste(as.character(parsed$student_id %||% ""), collapse = ""))
      if (!nzchar(sid)) {
        parsed$recognized <- blank_df
      } else {
        fc <- suppressWarnings(as.numeric(parsed$confidence %||% NA))
        if (length(fc) != 1L || is.na(fc)) fc <- NA_real_
        parsed$recognized <- data.frame(
          student_id = sid,
          student_name = trimws(paste(as.character(parsed$student_name %||% ""), collapse = "")),
          emotion = trimws(paste(as.character(parsed$emotion %||% "Neutral"), collapse = "")),
          face_confidence = fc,
          stringsAsFactors = FALSE
        )
      }
    } else {
      parsed$recognized <- blank_df
    }
    return(parsed)
  }

  if (inherits(rid, "data.frame")) parsed$recognized <- rid else parsed$recognized <- blank_df
  parsed
}

# Function to call FastAPI with timeout
call_api <- function(endpoint, method = "GET", body = NULL, token = NULL, timeout_sec = 45) {
  url <- paste0(API_BASE_URL, endpoint)
  tryCatch({
    config <- timeout(ceiling(timeout_sec))
    headers <- if (!is.null(token) && nzchar(token)) add_headers(Authorization = paste("Bearer", token)) else NULL
    if (method == "POST") {
      args <- list(url = url, body = body, encode = "json", config = config)
      if (!is.null(headers)) args <- c(args, list(headers))
      response <- do.call(POST, args)
    } else {
      args <- list(url = url, config = config)
      if (!is.null(headers)) args <- c(args, list(headers))
      response <- do.call(GET, args)
    }
    if (status_code(response) >= 200 && status_code(response) < 300) {
      return(fromJSON(content(response, "text", encoding = "UTF-8")))
    } else {
      body <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "")
      message(paste("API call failed:", method, url, "Status:", status_code(response), "Body:", body))
      return(list(error = TRUE, status = status_code(response), body = body))
    }
  }, error = function(e) {
    message(paste("API call error:", e$message))
    return(list(error = TRUE, status = 0, body = e$message))
  })
}

# ── Sidebar / shell helpers (same nav targets as legacy nav_* inputs) ────────
ep_sb_nav_button <- function(inputId, label, material_icon = "") {
  lab <- if (nzchar(material_icon)) {
    tagList(tags$span(class = "material-symbols-outlined ep-sb-ms", material_icon), "\u00a0", label)
  } else {
    label
  }
  tagAppendAttributes(
    actionButton(inputId, label = lab, class = "btn ep-sb-link action-button"),
    `data-panel` = sub("^sb_", "", inputId)
  )
}

# Week chips: grey + disabled once semester week is locked (see analysis_semester_data.R).
ep_week_nav_button <- function(week_num, id_prefix = "week_btn_") {
  wid <- paste0(id_prefix, week_num)
  if (week_num >= EDUPULSE_FIRST_LOCKED_WEEK) {
    tags$button(
      paste0("W", week_num),
      id = wid,
      type = "button",
      class = if (nzchar(id_prefix) && id_prefix != "week_btn_") {
        "ep-week-chip week-btn ep-week-locked"
      } else {
        "week-btn ep-week-locked"
      },
      disabled = NA
    )
  } else {
    tags$button(
      paste0("W", week_num),
      id = wid,
      class = if (nzchar(id_prefix) && id_prefix != "week_btn_") {
        "ep-week-chip week-btn"
      } else {
        "week-btn"
      },
      onclick = sprintf(
        "Shiny.setInputValue('selected_week_click', %d, {priority: 'event'});", week_num
      )
    )
  }
}

# ── UI ──────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  useShinyjs(),
  tags$head(
    tags$link(rel = "stylesheet", href = "custom.css"),
    tags$style(HTML("
      /* ── EduPulse AI – Theme Variables ─────────────────────────────────── */
      /* Dark Mode (default) – navy/slate + sky-blue accent */
      :root {
        --bg: #12141d;
        --surface: #1c1f2a;
        --surface-alt: #161a24;
        --text: #f1f5f9;
        --muted: #94a3b8;
        --accent: #a5d8ff;
        --accent-strong: #7ec8f5;
        --border: #2a3142;
        --border-strong: #a5d8ff;
        --panel-text: #a5d8ff;
        --alert-info-bg: rgba(129,170,217,0.12);
        --alert-info-border: #81aad9;
        --alert-info-text: #a8c4e0;
        --alert-warning-bg: rgba(245,158,11,0.12);
        --alert-warning-border: #f59e0b;
        --alert-warning-text: #fcd34d;
        --field-bg: #111a2d;
        --field-border: #334766;
        --datatable-head: #0f172a;
        --datatable-row: #0b1220;
        --datatable-row-hover: #111a2d;
        --datatable-text: #f1f5f9;
        --dataTables-input-bg: #111a2d;
        --dataTables-input-border: #334766;
        --dataTables-input-text: #f1f5f9;
        --navbar-bg: #12141d;
        --navbar-link: #94a3b8;
        --navbar-link-hover: #81aad9;
        --login-bg: #111a2d;
        --login-border: #334766;
        --login-shadow: rgba(0,0,0,0.5);
        --login-logo: #81aad9;
        --shadow-card: 0 1px 3px rgba(0,0,0,0.3);
        --shadow-soft: 0 4px 20px rgba(0,0,0,0.25);
      }
      /* Light Mode – applied via html[data-theme='light'] */
      html[data-theme='light'] {
        --bg: #f6f7f8;
        --surface: #ffffff;
        --surface-alt: #eef2f7;
        --text: #0f172a;
        --muted: #64748b;
        --accent: #81aad9;
        --accent-strong: #6b96c7;
        --border: #dbe4ef;
        --border-strong: #81aad9;
        --panel-text: #81aad9;
        --alert-info-bg: rgba(129,170,217,0.08);
        --alert-info-border: #81aad9;
        --alert-info-text: #3a6fa0;
        --alert-warning-bg: rgba(245,158,11,0.10);
        --alert-warning-border: #d97706;
        --alert-warning-text: #92400e;
        --field-bg: #ffffff;
        --field-border: #c3d0e0;
        --datatable-head: #eef2f7;
        --datatable-row: #ffffff;
        --datatable-row-hover: rgba(129,170,217,0.08);
        --datatable-text: #0f172a;
        --dataTables-input-bg: #ffffff;
        --dataTables-input-border: #c3d0e0;
        --dataTables-input-text: #0f172a;
        --navbar-bg: #ffffff;
        --navbar-link: #64748b;
        --navbar-link-hover: #81aad9;
        --login-bg: #ffffff;
        --login-border: #dbe4ef;
        --login-shadow: rgba(15,23,42,0.10);
        --login-logo: #81aad9;
        --shadow-card: 0 1px 3px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04);
        --shadow-soft: 0 4px 20px rgba(15,23,42,0.08);
      }
      /* Transition everything smoothly on theme change */
      *, *::before, *::after {
        transition: background-color 0.26s ease-out, border-color 0.26s ease-out, color 0.18s ease-out, box-shadow 0.26s ease-out;
      }
      body { background-color: var(--bg) !important; color: var(--text) !important; font-family: 'Plus Jakarta Sans', 'Inter', sans-serif; margin:0; font-size:17px; }
      .ep-navbar { background-color: var(--navbar-bg); border-bottom: 1px solid var(--border);
                   padding: 1rem 2rem; display: flex; align-items: center; gap: 0.75rem;
                   box-shadow: var(--shadow-card); flex-wrap: wrap; row-gap: 0.5rem; min-height: 76px; }
      .ep-brand { color: var(--accent); font-weight: 800; font-size: 1.75rem; margin-right: 0.5rem;
                  flex-shrink: 0; }
      .ep-nav-links { display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem;
                      flex: 1 1 auto; min-width: min(520px, 100%); row-gap: 0.35rem; }
      .ep-nav-tail { margin-left: auto; display: flex; flex-wrap: wrap; align-items: center;
                     gap: 0.35rem; flex-shrink: 0; }
      .ep-nav-link { color: var(--navbar-link); background: none; border: none; cursor: pointer;
                     font-size: 1.15rem; padding: 8px 16px; border-radius: 10px; font-weight: 600;
                     transition: color 0.22s ease-out, background 0.22s ease-out; }
      .ep-nav-link:hover { color: var(--navbar-link-hover); background: rgba(129,170,217,0.08); }
      .ep-navbar .ep-nav-link.ep-top-active { color: var(--accent-strong) !important; font-weight: 700;
        background: rgba(129,170,217,0.16) !important; border: 1px solid rgba(129,170,217,0.38) !important; }
      .sidebar { background-color: var(--surface); border-right: 1px solid var(--border);
                 min-height: calc(100vh - 56px); padding: 1.25rem; width: 220px; flex-shrink: 0; }
      .main-panel { background-color: var(--bg); padding: 1.5rem; flex-grow: 1; overflow-y: auto; }
      .ep-card { background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
                 padding: 1.25rem; margin-bottom: 1rem; box-shadow: var(--shadow-card); }
      .ep-card-header { color: var(--panel-text); font-weight: 700; font-size: 0.92rem;
                        text-transform: uppercase; letter-spacing: 0.07em; margin-bottom: 0.85rem; }
      .metric-card { background: var(--surface);
                     border: 1px solid var(--border); border-radius: 16px; padding: 1.1rem;
                     margin-bottom: 0.75rem; transition: border-color 0.22s ease-out, box-shadow 0.22s ease-out;
                     box-shadow: var(--shadow-card); }
      .metric-card:hover { border-color: var(--border-strong); box-shadow: var(--shadow-soft); }
      .metric-value { font-size: 2.2rem; font-weight: 700; color: var(--accent); line-height: 1.1; }
      .metric-label { font-size: 0.82rem; color: var(--muted); text-transform: uppercase;
                      letter-spacing: 0.09em; margin-top: 0.3rem; }
      .metric-icon  { font-size: 1.3rem; margin-bottom: 0.3rem; }
      .week-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 4px; }
      .week-btn { width:100%; background: var(--bg); border:1px solid var(--border); color: var(--muted);
                  border-radius:10px; padding:5px 2px; font-size:0.82rem; cursor:pointer;
                  transition:all 0.22s ease-out; line-height:1.2; }
      .week-btn:hover  { background: var(--surface); color: var(--text); border-color: var(--border-strong); }
      .week-btn.active { background: var(--accent-strong); border-color: var(--accent-strong); color:#fff; font-weight:700; }
      .section-title { color: var(--accent); font-size:1.6rem; font-weight:800; margin-bottom:0.2rem; }
      .section-sub   { color: var(--muted); font-size:0.88rem; margin-bottom:1.25rem; }
      .week-info-bar { background: var(--surface);
                       border:1px solid var(--border-strong); border-radius:14px;
                       padding:0.65rem 1.2rem; margin-bottom:1.1rem;
                       color: var(--accent); font-weight:700; font-size:0.95rem; }
      .badge-role { background: var(--surface); color: var(--accent); padding:5px 16px;
                   border-radius:24px; font-size:0.92rem; font-weight:700; border:1px solid var(--border); }
      .form-label { color: var(--muted); font-size:0.78rem; font-weight:700; letter-spacing:0.05em; display:block; }
      .alert-info    { background: var(--alert-info-bg)!important; border:1px solid var(--alert-info-border)!important;
                       color: var(--alert-info-text)!important; border-radius:14px; padding:0.65rem 1rem; }
      .alert-warning { background: var(--alert-warning-bg)!important; border:1px solid var(--alert-warning-border)!important;
                       color: var(--alert-warning-text)!important; border-radius:14px; padding:0.65rem 1rem; }
      select.form-select, .form-control { background: var(--field-bg)!important; border:1px solid var(--field-border)!important;
        color: var(--text)!important; border-radius:12px!important; }
      table.dataTable thead th { background: var(--datatable-head)!important; color: var(--accent); border-bottom:2px solid var(--border); }
      table.dataTable tbody tr { background: var(--datatable-row)!important; }
      table.dataTable tbody tr:hover { background: var(--datatable-row-hover)!important; }
      table.dataTable tbody td { color: var(--datatable-text)!important; border-color: var(--border); }
      .dataTables_wrapper { background: var(--surface)!important; border-radius: 16px; padding: 1rem; border: 1px solid var(--border); box-shadow: var(--shadow-card); }
      .dataTables_info,.dataTables_length label,.dataTables_filter label { color: var(--muted); }
      .dataTables_filter input,.dataTables_length select { background: var(--dataTables-input-bg)!important; border:1px solid var(--dataTables-input-border)!important;
        color: var(--dataTables-input-text)!important; border-radius:10px; padding:2px 8px; }
      .paginate_button { color: var(--muted)!important; border-radius:10px!important; background: transparent!important; }
      .paginate_button.current { background: var(--accent-strong)!important; color:#fff!important; border-color: var(--accent-strong)!important; }
      #login_overlay { position:fixed; inset:0; background: var(--bg); display:flex;
                       align-items:center; justify-content:center; z-index:9999; }
      .login-card { background: var(--login-bg); border:1px solid var(--login-border); border-radius:24px;
                    padding:2.5rem; width:100%; max-width:400px; box-shadow:0 25px 60px var(--login-shadow); }
      .login-logo { color: var(--login-logo); font-size:2.2rem; font-weight:800; text-align:center; margin-bottom:0.2rem; }
      .login-sub  { text-align:center; color: var(--muted); font-size:0.88rem; margin-bottom:2rem; }
      .btn-primary { background-color: var(--accent-strong)!important; border-color: var(--accent-strong)!important; color:#fff!important; }
      .btn-primary:hover { background-color: var(--accent)!important; border-color: var(--accent)!important; }
      .btn-outline-primary { border-color: var(--border)!important; color: var(--muted)!important; background: var(--surface)!important; font-size: 0.95rem!important; }
      .btn-outline-primary:hover { border-color: var(--accent)!important; color: var(--accent)!important; background: var(--surface)!important; }
      hr.ep-hr { border-color: var(--border); margin:0.9rem 0; }
      h4.sub-section { color: var(--accent-strong); font-size:1.15rem; font-weight:700;
                        margin-top:1.25rem; margin-bottom:0.75rem; }
      /* ── Theme Toggle Button ─────────────────────────────────────────────── */
      #toggle_theme {
        display: inline-flex !important;
        align-items: center;
        gap: 6px;
        height: 40px;
        min-width: 100px;
        padding: 0 16px !important;
        border-radius: 999px !important;
        border: 1px solid var(--border) !important;
        background: var(--surface) !important;
        color: var(--muted) !important;
        font-size: 14px !important;
        font-weight: 700 !important;
        letter-spacing: 0.04em;
        cursor: pointer;
        transition: border-color 0.22s ease-out, background 0.22s ease-out, color 0.22s ease-out, transform 0.22s ease-out !important;
        white-space: nowrap;
      }
      #toggle_theme:hover {
        border-color: var(--accent) !important;
        color: var(--accent) !important;
        transform: translateY(-2px) !important;
      }
    ")),
    tags$script(HTML(
      paste0(
        "var eduPulseApiBase = ", jsonlite::toJSON(API_BASE_URL, auto_unbox = TRUE), ";\n",
        "var cameraStream = null;\n"
      ) ,
      "var cameraInterval = null;\n" ,
      "var currentLectureId = null;\n" ,
      "var currentSessionMode = 'full';\n" ,
      "var eduPulseApiToken = null;\n" ,
      "var cameraReady = false;\n" ,
      "function startMonitorCamera(message) {\n" ,
      "  var video = document.getElementById('monitor_video');\n" ,
      "  var canvas = document.getElementById('monitor_canvas');\n" ,
      "  var status = document.getElementById('camera_status');\n" ,
      "  if (!video || !canvas || !status) {\n" ,
      "    console.error('Camera elements not found in DOM. Retrying in 500ms...');\n" ,
      "    setTimeout(function() { startMonitorCamera(message); }, 500);\n" ,
      "    return;\n" ,
      "  }\n" ,
      "  if (cameraStream) { stopMonitorCamera(); }\n" ,
      "  currentLectureId = message.lecture_id;\n" ,
      "  currentSessionMode = message.mode || 'full';\n" ,
      "  status.innerText = 'Requesting camera access...';\n" ,
      "  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {\n" ,
      "    status.innerText = 'Camera error: getUserMedia not supported (need HTTPS or localhost).';\n" ,
      "    return;\n" ,
      "  }\n" ,
      "  navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' }, audio: false })\n" ,
      "    .then(function(stream) {\n" ,
      "      cameraStream = stream;\n" ,
      "      video.srcObject = stream;\n" ,
      "      video.setAttribute('playsinline', '');\n" ,
      "      video.muted = true;\n" ,
      "      video.onloadedmetadata = function() {\n" ,
      "        video.play().then(function() {\n" ,
      "          cameraReady = true;\n" ,
      "          status.innerText = 'Camera active. Capturing frames...';\n" ,
      "          if (!cameraInterval) {\n" ,
      "            cameraInterval = setInterval(sendCaptureFrame, 3000);\n" ,
      "            sendCaptureFrame();\n" ,
      "          }\n" ,
      "        }).catch(function(playErr) {\n" ,
      "          status.innerText = 'Video play failed: ' + playErr.message;\n" ,
      "        });\n" ,
      "      };\n" ,
      "    })\n" ,
      "    .catch(function(err) {\n" ,
      "      status.innerText = 'Camera unavailable: ' + err.message;\n" ,
      "    });\n" ,
      "}\n" ,
      "function stopMonitorCamera() {\n" ,
      "  if (cameraInterval) { clearInterval(cameraInterval); cameraInterval = null; }\n" ,
      "  cameraReady = false;\n" ,
      "  if (cameraStream) { cameraStream.getTracks().forEach(function(track) { track.stop(); }); cameraStream = null; }\n" ,
      "  var status = document.getElementById('camera_status');\n" ,
      "  var video = document.getElementById('monitor_video');\n" ,
      "  if (status) status.innerText = 'Camera is idle. Start a session from the schedule to begin.';\n" ,
      "  if (video) { video.pause(); video.srcObject = null; }\n" ,
      "  currentLectureId = null;\n" ,
      "  currentSessionMode = 'full';\n" ,
      "}\n" ,
      "function sendCaptureFrame() {\n" ,
      "  if (!cameraStream || !currentLectureId || !cameraReady) return;\n" ,
      "  var video = document.getElementById('monitor_video');\n" ,
      "  var canvas = document.getElementById('monitor_canvas');\n" ,
      "  var status = document.getElementById('camera_status');\n" ,
      "  if (!video || !canvas || !status) return;\n" ,
      "  var w = video.videoWidth || 0, h = video.videoHeight || 0;\n" ,
      "  if (w < 16 || h < 16) {\n" ,
      "    status.innerText = 'Camera warming up… waiting for video frames.';\n" ,
      "    return;\n" ,
      "  }\n" ,
      "  canvas.width = w;\n" ,
      "  canvas.height = h;\n" ,
      "  var ctx = canvas.getContext('2d');\n" ,
      "  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);\n" ,
      "  canvas.toBlob(function(blob) {\n" ,
      "    if (!blob) {\n" ,
      "      if (status) status.innerText = 'Capture skipped — empty frame (browser blocked canvas draw).';\n" ,
      "      return;\n" ,
      "    }\n" ,
      "    var data = new FormData();\n" ,
      "    data.append('file', blob, 'frame.jpg');\n" ,
      "    data.append('lecture_id', currentLectureId);\n" ,
      "    data.append('mode', currentSessionMode);\n" ,
      "    var headers = {};\n" ,
      "    if (eduPulseApiToken) { headers['Authorization'] = 'Bearer ' + eduPulseApiToken; }\n" ,
      "    fetch(eduPulseApiBase + '/analyze-attendance-frame', { method: 'POST', body: data, credentials: 'omit', headers: headers })\n" ,
      "      .then(function(response) {\n" ,
      "        return response.text().then(function(txt) {\n" ,
      "          var json = null;\n" ,
      "          try { json = txt ? JSON.parse(txt) : null; } catch (e) { json = null; }\n" ,
      "          if (!response.ok) {\n" ,
      "            var detail = '';\n" ,
      "            if (json && json.detail !== undefined)\n" ,
      "              detail = (typeof json.detail === 'string') ? json.detail : JSON.stringify(json.detail);\n" ,
      "            else if (txt) detail = txt;\n" ,
      "            throw new Error('HTTP ' + response.status + (detail ? (': ' + detail) : ''));\n" ,
      "          }\n" ,
      "          return json;\n" ,
      "        });\n" ,
      "      })\n" ,
      "      .then(function(json) {\n" ,
      "        if (!json) return;\n" ,
      "        Shiny.setInputValue('live_face_response', JSON.stringify(json), { priority: 'event' });\n" ,
      "        status.innerText = 'Camera active. Last capture: ' + new Date().toLocaleTimeString();\n" ,
      "      })\n" ,
      "      .catch(function(err) {\n" ,
      "        console.error('Frame capture error:', err);\n" ,
      "        if (status) status.innerText = 'Analyze frame failed — ' + (err && err.message ? err.message : String(err));\n" ,
      "      });\n" ,
      "  }, 'image/jpeg', 0.7);\n" ,
      "}\n" ,
      "Shiny.addCustomMessageHandler('startCamera', function(message) { startMonitorCamera(message); });\n" ,
      "Shiny.addCustomMessageHandler('stopCamera', function(message) { stopMonitorCamera(); });\n" ,
      "Shiny.addCustomMessageHandler('setApiToken', function(message) { eduPulseApiToken = message && message.token ? message.token : null; });\n" ,
      "Shiny.addCustomMessageHandler('highlightSb', function(m) {\n" ,
      "  var p = String(m.panel);\n" ,
      "  document.querySelectorAll('#main_app .ep-navbar .ep-nav-link.ep-top-active').forEach(function(el){ el.classList.remove('ep-top-active'); });\n" ,
      "  document.querySelectorAll('.ep-primary-sidebar [data-panel]').forEach(function(el){ el.classList.remove('ep-sb-active'); });\n" ,
      "  document.querySelectorAll('.ep-primary-sidebar [data-panel=\"' + p + '\"]').forEach(function(el){ el.classList.add('ep-sb-active'); });\n" ,
      "  var nm = ({ dashboard:'nav_dashboard', monitor:'nav_monitor', report:'nav_report',\n" ,
      "    graphs:'nav_graphs', confusion:'nav_confusion', groups:'nav_groups',\n" ,
      "    attendance:'nav_attendance', settings:'nav_settings' })[p];\n" ,
      "  if (nm) { var tg = document.getElementById(nm); if (tg) tg.classList.add('ep-top-active'); }\n" ,
      "});\n" ,
      "function toggleTheme() {\n" ,
      "  var html = document.documentElement;\n" ,
      "  var btn = document.getElementById('toggle_theme');\n" ,
      "  if (!html || !btn) return;\n" ,
      "  if (html.getAttribute('data-theme') === 'light') {\n" ,
      "    html.removeAttribute('data-theme');\n" ,
      "    html.classList.remove('light');\n" ,
      "    document.body.classList.remove('light');\n" ,
      "    btn.innerHTML = '&#9728;&#xFE0F; Light';\n" ,
      "  } else {\n" ,
      "    html.setAttribute('data-theme', 'light');\n" ,
      "    html.classList.add('light');\n" ,
      "    document.body.classList.add('light');\n" ,
      "    btn.innerHTML = '&#127769; Dark';\n" ,
      "  }\n" ,
      "}\n" ,
      "document.addEventListener('DOMContentLoaded', function() {\n" ,
      "  var btn = document.getElementById('toggle_theme');\n" ,
      "  if (btn) {\n" ,
      "    btn.innerHTML = '&#9728;&#xFE0F; Light';\n" ,
      "    btn.addEventListener('click', toggleTheme);\n" ,
      "  }\n" ,
      "});\n" ))
  ),
  
  # ── Login / Sign-up overlay ─────────────────────────────────────────────────
  div(
    id = "login_overlay",
    # Login card
    div(
      id = "login_card",
      class = "login-card",
      div(class = "login-logo", "LogIn"),
      div(class = "login-sub",  "Classroom Emotion Detection & Analysis"),
      div(class = "mb-3",
          tags$label("Email", class = "form-label"),
          textInput("login_email", NULL, placeholder = "Enter your email")
      ),
      div(class = "mb-4",
          tags$label("Password", class = "form-label"),
          passwordInput("login_password", NULL, placeholder = "Enter password")
      ),
      actionButton("login_btn", "Sign In", class = "btn btn-primary w-100",
                   style = "padding:0.6rem; font-weight:700; font-size:1rem;"
      ),
      div(style = "display:flex; justify-content:space-between; margin-top:0.85rem; gap:0.75rem;",
          actionLink("forgot_password_link", "Forgot password?",
                     style = "color: var(--accent-strong); font-weight:600; font-size:0.9rem; text-decoration:none;"),
          actionLink("show_signup", "Don't have an account? Sign Up",
                     style = "color: var(--accent-strong); font-weight:600; font-size:0.9rem; text-decoration:none;")
      )
      ,
      shinyjs::hidden(
        div(id = "login_error", class = "alert alert-warning mt-3 small mb-0",
            "Invalid email or password.")
      )
    ),
    # Sign-up card
    shinyjs::hidden(
      div(
        id = "signup_card",
        class = "login-card",
        div(class = "login-logo", "Sign Up"),
        div(class = "login-sub",  "Create a new account"),
        div(class = "mb-3",
            tags$label("Full Name", class = "form-label"),
            textInput("signup_name", NULL, placeholder = "Enter your full name")
        ),
        div(class = "mb-3",
            tags$label("Role", class = "form-label"),
            selectInput(
              "signup_role",
              NULL,
              choices = c("Student" = "student", "Lecturer" = "lecturer", "Admin" = "admin"),
              selected = "student"
            )
        ),
        uiOutput("signup_lecturer_setup"),
        div(class = "mb-3",
            tags$label("Institution ID", class = "form-label"),
            textInput("signup_institution_id", NULL, placeholder = "e.g., S12345, L12345, A12345")
        ),
        div(class = "mb-3",
            tags$label("Email", class = "form-label"),
            textInput("signup_email", NULL, placeholder = "Enter your email")
        ),
        div(class = "mb-3",
            tags$label("Password", class = "form-label"),
            passwordInput("signup_password", NULL, placeholder = "Min. 8 characters")
        ),
        div(class = "mb-4",
            tags$label("Confirm Password", class = "form-label"),
            passwordInput("signup_password_confirm", NULL, placeholder = "Re-enter password")
        ),
        actionButton("signup_btn", "Create Account", class = "btn btn-primary w-100",
                     style = "padding:0.6rem; font-weight:700; font-size:1rem;"
        ),
        shinyjs::hidden(
          div(id = "signup_error", class = "alert alert-warning mt-3 small mb-0", "")
        ),
        shinyjs::hidden(
          div(id = "signup_success", class = "alert alert-success mt-3 small mb-0",
              "Account created! You can now sign in.")
        ),
        div(style = "text-align:center; margin-top:1rem;",
            actionLink("show_login", "Already have an account? Sign In",
                       style = "color: var(--accent-strong); font-weight:600; font-size:0.9rem; text-decoration:none;")
        )
      )
    )
  ),
  
  # ── Forgot Password Modal (login overlay) ──────────────────────────────────
  shinyjs::hidden(div(
    id = "forgot_password_modal",
    style = paste(
      "position:fixed; top:50%; left:50%; transform:translate(-50%, -50%);",
      "background:var(--surface); border:1px solid var(--border);",
      "border-radius:12px; padding:2rem; z-index:9999; width:90%; max-width:420px;",
      "box-shadow: 0 10px 40px rgba(0,0,0,0.3);"
    ),
    h3("🔑 Reset Password", style = "margin-top:0; margin-bottom:1.5rem;"),
    div(id = "fp_step1", style = "display:block;",
        p(style = "color:var(--muted); font-size:0.9rem;", "Enter your email address to receive a verification code."),
        div(class = "mb-3",
            tags$label("Email Address", class = "form-label"),
            textInput("fp_email", NULL, value = "", placeholder = "your@email.com")
        ),
        actionButton("fp_request_code_btn", "Send Verification Code",
                     class = "btn btn-primary w-100")
    ),
    div(id = "fp_step2", style = "display:none;",
        p(style = "color:var(--muted); font-size:0.9rem;", "Enter the code from your email and set a new password."),
        div(class = "mb-3",
            tags$label("Verification Code (6 digits)", class = "form-label"),
            htmltools::tagAppendAttributes(
              textInput("fp_code", NULL, value = "", placeholder = "000000"),
              maxlength = 6,
              inputmode = "numeric",
              pattern = "[0-9]*"
            )
        ),
        div(class = "mb-3",
            tags$label("New Password", class = "form-label"),
            passwordInput("fp_new_password", NULL, value = "", placeholder = "8+ characters")
        ),
        actionButton("fp_verify_btn", "Verify & Reset Password",
                     class = "btn btn-primary w-100")
    ),
    div(id = "fp_message", style = "margin-top:1rem; padding:0.75rem; border-radius:6px; display:none; font-size:0.9rem;"),
    div(style = "display:flex; gap:0.5rem; margin-top:1.5rem; justify-content:flex-end;",
        actionButton("fp_cancel_btn", "Cancel",
                     class = "btn btn-secondary btn-sm")
    )
  )),
  div(id = "auth_modal_overlay", style = paste(
    "position:fixed; top:0; left:0; width:100%; height:100%;",
    "background:rgba(0,0,0,0.5); z-index:9998; display:none;"
  )),
  
  # ── Main app (hidden until login) ──────────────────────────────────────────
  shinyjs::hidden(
    div(
      id = "main_app",
      
      div(class = "ep-shell-inner",

        div(class = "ep-main-stack",
          div(class = "ep-navbar ep-shell-navbar",
            div(class = "ep-nav-links",
              actionButton("nav_dashboard", "Dashboard", class = "btn ep-nav-link action-button"),
              actionButton("nav_monitor", "Live Monitor", class = "btn ep-nav-link action-button"),
              actionButton("nav_graphs", "Analytics", class = "btn ep-nav-link action-button"),
              actionButton("nav_report", "Reports", class = "btn ep-nav-link action-button"),
              actionButton("nav_confusion", "Alerts", class = "btn ep-nav-link action-button"),
              actionButton("nav_groups", "Groups", class = "btn ep-nav-link action-button"),
              actionButton("nav_attendance", "Attendance", class = "btn ep-nav-link action-button"),
              actionButton("nav_settings", "Settings", class = "btn ep-nav-link action-button")
            ),
            div(class = "ep-navbar-toolbar",
              div(class = "ep-nav-tail",
              div(class = "badge-role ms-1", textOutput("role_badge", inline = TRUE)),
              tags$button(
                type = "button",
                id = "ep_top_help_btn",
                class = "btn btn-sm ep-icon-soft",
                onclick = "alert('Tips: Pick a week, filter course/group, then start a session from the schedule table.')",
                `aria-label` = "Tips",
                title = "Tips",
                tags$span(class = "material-symbols-outlined", "notifications")
              ),
              tags$button(
                type = "button", id = "ep_dummy_avatar", class = "btn btn-sm ep-avatar-chip",
                `aria-label` = "Profile", title = "Profile",
                tags$span(class = "material-symbols-outlined", "person")
              ),
              actionButton("toggle_theme", "☀️ Light", class = "btn btn-sm btn-outline-primary ms-1"),
              actionButton("logout_btn", "Logout",
                class = "btn btn-sm btn-outline-primary ms-1",
                style = "font-size:0.75rem; padding:3px 12px;"
              )
            )
            )
          ),

          div(class = "ep-body-row",

        # Sidebar (week + filters)
        div(
          class = "sidebar ep-context-sidebar",
          
          div(class = "ep-card-header mt-1", "📅 Select Week"),
          div(
            class = "week-grid",
            lapply(1:16, function(w) ep_week_nav_button(w, "week_btn_"))
          ),
          
          hr(class = "ep-hr"),
          div(class = "ep-card-header", " Filters"),
          
          div(class = "mb-2",
              tags$label("Course", class = "form-label"),
              selectInput("filter_course_schedule", NULL, choices = c("All"))
          ),
          div(class = "mb-2",
              tags$label("Group", class = "form-label"),
              selectInput("filter_group_schedule", NULL, choices = c("All"))
          ),
          div(class = "mb-2",
              tags$label("Group (Monitor)", class = "form-label"),
              selectInput("filter_group", NULL, choices = c("All"))
          ),
          
          hr(class = "ep-hr"),
          downloadButton("download_data", "⬇ Export CSV",
                         class = "btn btn-sm btn-outline-primary w-100"
          )
        ),
        
        # Main content area
        div(
          class = "main-panel ep-main-scroll",
          
          # ── Lecturer Dashboard ────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_dashboard",
            div(class = "ep-dash-hero ep-dash-hero-slim ep-dash-hero-tight",
              div(class = "ep-dash-hero-text",
                tags$p(class = "ep-dash-greeting-inline", textOutput("dash_hero_line1")),
                tags$p(class = "ep-dash-sub ep-dash-sub-compact", textOutput("dash_hero_line2"))
              )
            ),

            div(class = "ep-section-head-dash",
              h2(class = "ep-section-title-dash", "Semester overview"),
              div(class = "week-info-bar ep-week-info-inline", textOutput("selected_week_display"))
            ),

            div(class = "ep-week-strip-wrap",
              div(class = "ep-week-strip-label", "Jump to week"),
              div(class = "ep-week-strip",
                lapply(1:16, function(w) ep_week_nav_button(w, "ep_week_strip_"))
              )
            ),

            fluidRow(class = "ep-dash-metrics-row ep-mt-std",
              column(3, div(class = "metric-card",
                            div(class = "metric-icon", "📚"),
                            div(class = "metric-value", textOutput("card_week_lectures")),
                            div(class = "metric-label", "Lectures This Week")
              )),
              column(3, div(class = "metric-card",
                            div(class = "metric-icon", "💡"),
                            div(class = "metric-value", textOutput("card_week_engagement")),
                            div(class = "metric-label", "Avg Engagement")
              )),
              column(3, div(class = "metric-card",
                            div(class = "metric-icon", "🎯"),
                            div(class = "metric-value", textOutput("card_week_focus")),
                            div(class = "metric-label", "Avg Focus")
              )),
              column(3, div(class = "metric-card",
                            div(class = "metric-icon", "⚠️"),
                            div(class = "metric-value", textOutput("card_week_confusion")),
                            div(class = "metric-label", "Confusion Alerts")
              ))
            ),

            div(class = "ep-card ep-sched-card",
              div(class = "ep-sched-head",
                  div(div(class = "ep-card-header ep-sched-title", HTML("Week schedule & analysis")),
                      p(class = "ep-sched-hint",
                        "Use filters on the left, then Actions to start or view sessions.")),
                  tags$button(
                    type = "button",
                    class = "btn btn-sm ep-btn-export",
                    onclick = "var a=document.getElementById('download_data'); if(a) a.click();",
                    HTML('<span class="material-symbols-outlined ep-sbtn-ico">download</span> Export report')
                  )
              ),
              DTOutput("table_weekly_schedule")
            )

          )),
          
          # ── Live Monitor ──────────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_monitor",
            h1(class = "section-title", "🔴 Live Classroom Monitor"),
            p(class = "section-sub", "Real-time emotion detection and student engagement metrics"),
            
            div(class = "alert alert-info mb-3", textOutput("selected_lecture_display")),
            
            div(class = "ep-card mb-3",
                div(class = "ep-card-header", "🎥 Live Camera Feed"),
                div(style = "display:flex; flex-wrap:wrap; gap:1rem;",
                    div(style = "flex:1 1 360px; min-width:320px;",
                        tags$video(id = "monitor_video", autoplay = NA, playsinline = NA, muted = NA,
                                   style = "width:100%; height:auto; border-radius:12px; border:1px solid #334155; background:#000;"
                        )
                    ),
                    div(style = "flex:1 1 280px; min-width:280px;",
                        div(id = "camera_status", class = "alert alert-info", "Camera is idle. Click Start Session to begin."),
                        actionButton("stop_attendance_btn", "Stop Attendance",
                                     class = "btn btn-sm btn-outline-primary mb-2"),
                        uiOutput("live_face_summary")
                    )
                ),
                tags$canvas(id = "monitor_canvas", style = "display:none;")
            ),

            div(class = "ep-card",
                div(class = "ep-card-header", "Live Attendance"),
                DTOutput("table_live_attendance")
            ),

            fluidRow(
              column(4, div(class = "metric-card",
                            div(class = "metric-icon", "✅"),
                            div(class = "metric-value", textOutput("card_attendance")),
                            div(class = "metric-label", "Attendance")
              )),
              column(4, div(class = "metric-card",
                            div(class = "metric-icon", "👥"),
                            div(class = "metric-value", textOutput("card_present")),
                            div(class = "metric-label", "Students Present")
              ))
            ),

            shinyjs::hidden(div(
              id = "emotion_metrics_panel",

              fluidRow(
                column(3, div(class = "metric-card",
                              div(class = "metric-icon", "💡"),
                              div(class = "metric-value", textOutput("card_engagement")),
                              div(class = "metric-label", "Avg Engagement")
                )),
                column(3, div(class = "metric-card",
                              div(class = "metric-icon", "🎯"),
                              div(class = "metric-value", textOutput("card_focus")),
                              div(class = "metric-label", "Avg Focus")
                )),
                column(3, div(class = "metric-card",
                              div(class = "metric-icon", "❓"),
                              div(class = "metric-value", textOutput("card_confusion")),
                              div(class = "metric-label", "Confusion Rate")
                )),
                column(3, div(class = "metric-card",
                              div(class = "metric-icon", "😊"),
                              div(class = "metric-value", textOutput("card_dominant_emotion")),
                              div(class = "metric-label", "Dominant Emotion")
                ))
              ),

              div(class = "ep-card",
                  div(class = "ep-card-header", "🧠 Narrative Insights"),
                  div(style = "color:#94a3b8; font-size:0.9rem;", textOutput("narrative_insights"))
              ),

              fluidRow(
                column(6, div(class = "ep-card",
                              div(class = "ep-card-header", "📈 Engagement, Focus & Confusion Timeline"),
                              plotOutput("chart_timeline", height = "300px")
                )),
                column(6, div(class = "ep-card",
                              div(class = "ep-card-header", "🎭 Emotion Distribution"),
                              plotOutput("chart_emotions", height = "300px")
                ))
              )
            ))
          )),
          
          # ── Report ────────────────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_report",
            h1(class = "section-title", "📄 Student Emotion Report"),
            p(class = "section-sub", "Per-student emotion analysis for the selected lecture"),
            
            div(class = "ep-card mb-3",
                div(class = "ep-card-header", "Lecture Context"),
                fluidRow(
                  column(2, div(strong("Lecture:"),  br(), textOutput("report_lecture_name"))),
                  column(2, div(strong("Course:"),   br(), textOutput("report_course_name"))),
                  column(2, div(strong("Group:"),    br(), textOutput("report_group_name"))),
                  column(2, div(strong("Lecturer:"), br(), textOutput("report_lecturer_name"))),
                  column(2, div(strong("Date:"),     br(), textOutput("report_lecture_date"))),
                  column(2, div(strong("Time:"),     br(), textOutput("report_lecture_time")))
                )
            ),
            
            fluidRow(
              column(2, div(class = "metric-card", div(class="metric-icon","👥"), div(class="metric-value", textOutput("report_total_students")),   div(class="metric-label","Total Students"))),
              column(2, div(class = "metric-card", div(class="metric-icon","✅"), div(class="metric-value", textOutput("report_present_students")), div(class="metric-label","Present"))),
              column(2, div(class = "metric-card", div(class="metric-icon","❌"), div(class="metric-value", textOutput("report_absent_students")),  div(class="metric-label","Absent"))),
              column(2, div(class = "metric-card", div(class="metric-icon","💡"), div(class="metric-value", textOutput("report_avg_engagement")),   div(class="metric-label","Avg Engagement"))),
              column(2, div(class = "metric-card", div(class="metric-icon","🎯"), div(class="metric-value", textOutput("report_avg_focus")),        div(class="metric-label","Avg Focus"))),
              column(2, div(class = "metric-card", div(class="metric-icon","😊"), div(class="metric-value", textOutput("report_dominant_emotion")), div(class="metric-label","Dominant Emotion")))
            ),
            
            div(class = "ep-card",
                div(class = "ep-card-header", "📋 Student Report Table"),
                DTOutput("table_report")
            )
          )),
          
          # ── Graphs & Trends ───────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_graphs",
            h1(class = "section-title", "📊 Graphs & Trends"),
            p(class = "section-sub", "Detailed visualisations for lecture, student, and semester analytics"),
            
            h4(class = "sub-section", "🎓 Lecture Analysis"),
            fluidRow(
              column(6, div(class = "ep-card", div(class="ep-card-header","Confusion Timeline"),  plotOutput("chart_confusion_timeline",  height="280px"))),
              column(6, div(class = "ep-card", div(class="ep-card-header","Boredom Timeline"),    plotOutput("chart_boredom_timeline",    height="280px")))
            ),
            
            h4(class = "sub-section", "👤 Student Insights"),
            fluidRow(
              column(6, div(class = "ep-card", div(class="ep-card-header","Dominant Emotion by Student"),  plotOutput("chart_dominant_emotion",    height="280px"))),
              column(6, div(class = "ep-card", div(class="ep-card-header","Top 10 Most Engaged Students"), plotOutput("chart_engagement_ranking",  height="280px")))
            ),
            fluidRow(
              column(6, div(class = "ep-card", div(class="ep-card-header","Top 10 Most Confused Students"),plotOutput("chart_confusion_ranking",   height="280px"))),
              column(6, div(class = "ep-card", div(class="ep-card-header","Engagement vs Focus"),          plotOutput("chart_engagement_focus",    height="280px")))
            ),
            
            h4(class = "sub-section", "📅 Semester Trends"),
            fluidRow(
              column(6, div(class = "ep-card", div(class="ep-card-header","16-Week Engagement & Focus"),   plotOutput("chart_semester_engagement", height="280px"))),
              column(6, div(class = "ep-card", div(class="ep-card-header","16-Week Confusion & Boredom"),  plotOutput("chart_semester_confusion",  height="280px")))
            ),
            div(class = "ep-card", div(class="ep-card-header","Course Engagement Comparison"),  plotOutput("chart_course_comparison",  height="300px")),
            div(class = "ep-card", div(class="ep-card-header","Emotion Share Heatmap — All 16 Weeks"), plotOutput("chart_emotion_heatmap", height="320px"))
          )),
          
          # ── Confusion Alerts ──────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_confusion",
            h1(class = "section-title", "⚠️ Confusion Detection Spikes"),
            p(class = "section-sub", "Moments when more than 30% of students are confused"),
            div(class = "ep-card",
                div(class = "ep-card-header", "Confusion Events"),
                DTOutput("table_confusion_spikes")
            )
          )),
          
          # ── Groups ────────────────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_groups",
            h1(class = "section-title", "👥 Student Group Analysis"),
            p(class = "section-sub", "K-means clustering based on engagement, focus, and confusion patterns"),
            uiOutput("cluster_content")
          )),
          
          # ── Attendance ────────────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_attendance",
            h1(class = "section-title", "✅ Attendance & Focus"),
            p(class = "section-sub", "Student presence and focus metrics across lectures"),
            div(class = "ep-card",
                div(class = "ep-card-header", "Attendance & Focus Data"),
                DTOutput("table_attendance")
            )
          )),
          
          # ── Settings ──────────────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_settings",
            h1(class = "section-title", "⚙️ Settings"),
            p(class = "section-sub", "Application configuration and session information"),
            fluidRow(
              column(6, div(class = "ep-card",
                            div(class = "ep-card-header", "Session Information"),
                            div(class="mb-2", strong("Email:"),       br(), textOutput("info_username")),
                            div(class="mb-2", strong("Role:"),        br(), textOutput("info_role")),
                            div(class="mb-2", strong("Institution ID:"),     br(), textOutput("info_user_id")),
                            div(class="mb-2", strong("Name:"),        br(), textOutput("info_display_name")),
                            div(class="mb-2", strong("Selected Week:"),    br(), textOutput("info_selected_week")),
                            div(class="mb-2", strong("Selected Lecture:"), br(), textOutput("info_selected_lecture"))
              )),
              column(6, div(class = "ep-card",
                            div(class = "ep-card-header", "Change Password"),
                            p(style = "color: var(--muted); font-size:0.82rem; margin-bottom:1rem;",
                              "Change your password using your current password."),
                            actionButton("change_password_btn", "🔐 Change Password",
                                         class = "btn btn-warning btn-sm"),
                            div(id = "change_password_status", style = "margin-top:0.5rem; color:var(--muted); font-size:0.85rem;")
              ))
            ),
            fluidRow(
              column(6, div(class = "ep-card",
                            div(class = "ep-card-header", "About EduPulse AI"),
                            p("EduPulse AI is a classroom emotion detection and statistical analysis system."),
                            p("Data is stored in PostgreSQL with CSV file backups."),
                            p("Version: 0.3.0 — Full Database Integration"),
                            p("Stack: R · Shiny · PostgreSQL · ggplot2 · DT · shinyjs"),
                            hr(class = "ep-hr"),
                            div(class = "ep-card-header", "CSV Backup"),
                            p(style = "color: var(--muted); font-size:0.82rem;",
                              "CSV backups sync automatically every 10 minutes."),
                            actionButton("sync_csv_btn", "Sync Now",
                                         class = "btn btn-primary btn-sm"),
                            textOutput("sync_status")
              ))
            )
          )),
          
          # ── Change Password Modal (logged-in) ─────────────────────────────
          shinyjs::hidden(div(
            id = "change_password_modal",
            style = paste(
              "position:fixed; top:50%; left:50%; transform:translate(-50%, -50%);",
              "background:var(--surface); border:1px solid var(--border);",
              "border-radius:12px; padding:2rem; z-index:9999; width:90%; max-width:420px;",
              "box-shadow: 0 10px 40px rgba(0,0,0,0.3);"
            ),
            h3("🔐 Change Password", style = "margin-top:0; margin-bottom:1.5rem;"),
            div(id = "cp_inapp", style = "display:block;",
                p(style = "color:var(--muted); font-size:0.9rem;", "Enter your current password and choose a new password."),
                div(class = "mb-3",
                    tags$label("Current Password", class = "form-label"),
                    passwordInput("cp_old_password", NULL, value = "", placeholder = "Current password")
                ),
                div(class = "mb-3",
                    tags$label("New Password", class = "form-label"),
                    passwordInput("cp_new_password", NULL, value = "", placeholder = "8+ characters")
                ),
                div(class = "mb-3",
                    tags$label("Confirm New Password", class = "form-label"),
                    passwordInput("cp_new_password_confirm", NULL, value = "", placeholder = "Re-enter new password")
                ),
                actionButton("cp_change_inapp_btn", "Update Password",
                             class = "btn btn-primary w-100")
            ),
            div(id = "cp_message", style = "margin-top:1rem; padding:0.75rem; border-radius:6px; display:none; font-size:0.9rem;"),
            div(style = "display:flex; gap:0.5rem; margin-top:1.5rem; justify-content:flex-end;",
                actionButton("cp_cancel_btn", "Cancel",
                             class = "btn btn-secondary btn-sm")
            )
          )),
          div(id = "cp_modal_overlay", style = paste(
            "position:fixed; top:0; left:0; width:100%; height:100%;",
            "background:rgba(0,0,0,0.5); z-index:9998; display:none;"
          ))

        ) # end main-panel (.ep-main-scroll)
          ) # end ep-body-row
        ) # end ep-main-stack
      ) # end ep-shell-inner
    ) # end main_app
  ) # end hidden
)

# ── Server ──────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  
  is_logged_in <- reactiveVal(FALSE)

  # Show the actual DB init error in the UI (otherwise users only see "DB not available").
  db_init_notified <- reactiveVal(FALSE)
  observe({
    if (db_init_notified()) return()
    if (isTRUE(USE_DATABASE) && !isTRUE(.try_db_init)) {
      db_init_notified(TRUE)
      msg <- "Database init failed — using CSV fallback."
      if (!is.null(.db_init_error) && nzchar(.db_init_error)) {
        msg <- paste0(msg, " ", .db_init_error)
      }
      showNotification(msg, type = "error", duration = NULL)
    }
  })
  
  ALL_PANELS <- c("dashboard","monitor","report","graphs","confusion","groups","attendance","settings")
  
  show_panel <- function(name) {
    for (p in ALL_PANELS) shinyjs::hide(paste0("panel_", p))
    shinyjs::show(paste0("panel_", name))
  }
  
  # Unified nav: top pills + sidebar (same panels)
  NAV_BINDINGS <- list(
    list(ids = c("nav_dashboard", "sb_dashboard", "sb_new_analysis"), panel = "dashboard"),
    list(ids = c("nav_monitor", "sb_monitor"), panel = "monitor"),
    list(ids = c("nav_graphs", "sb_graphs"), panel = "graphs"),
    list(ids = c("nav_report", "sb_report"), panel = "report"),
    list(ids = c("nav_confusion", "sb_confusion"), panel = "confusion"),
    list(ids = c("nav_groups", "sb_groups"), panel = "groups"),
    list(ids = c("nav_attendance", "sb_attendance"), panel = "attendance"),
    list(ids = c("nav_settings", "sb_settings"), panel = "settings")
  )
  activate_panel <- function(panel) {
    if (!identical(panel, "monitor")) session$sendCustomMessage("stopCamera", list())
    show_panel(panel)
    session$sendCustomMessage("highlightSb", list(panel = panel))
  }
  for (b in NAV_BINDINGS) local({
    tgt <- b$panel
    idv <- b$ids
    for (one in idv) {
      local({
        idi <- one
        tgt2 <- tgt
        observeEvent(input[[idi]], {
          activate_panel(tgt2)
        }, ignoreInit = TRUE)
      })
    }
  })

  observeEvent(input$sidebar_help_btn, ignoreInit = TRUE, {
    showNotification(paste(
      "Overview: pick a week with W1–W16, filter by course/group,",
      "then use the schedule to start attendance, full monitor, or view a lecture."
    ), type = "message", duration = 8)
  })

  # ── Week button active styling (context rail + dashboard strip) ───────────
  update_week_buttons <- function(selected) {
    for (w in 1:16) {
      for (id in c(paste0("week_btn_", w), paste0("ep_week_strip_", w))) {
        if (w == selected) {
          shinyjs::runjs(sprintf("var el=document.getElementById('%s'); if(el) el.classList.add('active');", id))
        } else {
          shinyjs::runjs(sprintf("var el=document.getElementById('%s'); if(el) el.classList.remove('active');", id))
        }
      }
    }
  }
  
  # ── WEEK SELECTION — core fix ─────────────────────────────────────────────
  # Each week button fires Shiny.setInputValue('selected_week_click', w)
  # This single observer catches all 16 buttons reliably.
  observeEvent(input$selected_week_click, {
    w <- as.integer(input$selected_week_click)
    if (is.na(w) || w < 1L || w > 16L) return(invisible(NULL))
    if (w >= EDUPULSE_FIRST_LOCKED_WEEK) return(invisible(NULL))
    if (!is.null(app_data$user_role)) {
      app_data$selected_week <- w
      update_week_buttons(w)
    }
  })
  
  # ── Login ─────────────────────────────────────────────────────────────────
  observeEvent(input$login_btn, {
    user <- authenticate_user(
      trimws(input$login_email),
      input$login_password
    )
    
    if (!is.null(user)) {
      api_auth <- call_api(
        endpoint = "/auth/login",
        method = "POST",
        body = list(
          email = trimws(input$login_email),
          password = input$login_password
        )
      )
      if (is.null(api_auth$access_token) || !nzchar(api_auth$access_token)) {
        shinyjs::html("login_error", "Login failed: API authentication is unavailable.")
        shinyjs::show("login_error")
        return()
      }

      # Show progress dialog during data loading
      shinyjs::disable("login_btn")
      showNotification("Loading data...", id = "login_loading", type = "default", duration = NULL)
      
      is_logged_in(TRUE)
      app_data$user_role <- user$role
      app_data$user_id   <- user$user_id
      app_data$institution_id <- user$institution_id %||% user$user_id
      app_data$user_name <- user$name
      app_data$user_email <- user$email
      app_data$db_user_id <- if (!is.null(user$db_user_id)) user$db_user_id else NULL
      app_data$api_token <- api_auth$access_token
      app_data$selected_week <- EDUPULSE_ACTIVE_ACADEMIC_WEEK
      app_data$selected_lecture_id <- NULL
      session$sendCustomMessage("setApiToken", list(token = api_auth$access_token))

      # Update last login timestamp in DB
      if (.try_db_init && !is.null(user$db_user_id)) {
        tryCatch(update_last_login(user$db_user_id), error = function(e) NULL)
      }

      # Load & filter data with error handling
      tryCatch({
        app_data$all_data       <- edu_sanitize_postgres_frame(load_emotion_data())
        app_data$filtered_data  <- edu_sanitize_postgres_frame(
          filter_by_role(app_data$all_data, user$role, user$user_id)
        )
        raw_schedule            <- load_lecture_schedule()
        app_data$lecture_schedule <- filter_schedule_by_role(raw_schedule, user$role, user$user_id)
        app_data$semester_weeks <- load_semester_weeks()
      }, error = function(e) {
        # Hard fallback to CSV if DB fails unexpectedly
        message(paste("Login data load error:", e$message))
        USE_DATABASE <<- FALSE
        app_data$all_data       <- edu_sanitize_postgres_frame(load_emotion_data_csv())
        app_data$filtered_data  <- edu_sanitize_postgres_frame(
          filter_by_role(app_data$all_data, user$role, user$user_id)
        )
        raw_schedule            <- load_lecture_schedule_csv()
        app_data$lecture_schedule <- filter_schedule_by_role(raw_schedule, user$role, user$user_id)
        app_data$semester_weeks <- load_semester_weeks_csv()
        showNotification("Database unavailable — using CSV data.", type = "warning", duration = 5)
      })
      
      # Populate selects
      updateSelectInput(session, "filter_group",
                        choices = c("All", get_groups_from_data(app_data$filtered_data)))
      updateSelectInput(session, "filter_course_schedule",
                        choices = c("All", get_courses_from_data(app_data$lecture_schedule)))
      updateSelectInput(session, "filter_group_schedule",
                        choices = c("All", get_groups_from_data(app_data$lecture_schedule)))
      
      # Close auth modals (forgot-password overlay sits outside #main_app and can otherwise
      # leave a fullscreen dim layer after login).
      shinyjs::hide("auth_modal_overlay")
      shinyjs::hide("forgot_password_modal")
      shinyjs::hide("cp_modal_overlay")
      shinyjs::hide("change_password_modal")

      # Switch UI
      shinyjs::hide("login_overlay")
      shinyjs::show("main_app")
      shinyjs::hide("login_error")
      
      show_panel("dashboard")
      update_week_buttons(EDUPULSE_ACTIVE_ACADEMIC_WEEK)
      session$sendCustomMessage("highlightSb", list(panel = "dashboard"))

      removeNotification("login_loading")
      showNotification(paste0("Welcome, ", user$name, "!"), type = "message", duration = 3)
      
      shinyjs::enable("login_btn")
    } else {
      shinyjs::html("login_error", "Invalid email or password.")
      shinyjs::show("login_error")
    }
  })

  # ── Toggle between Login and Sign-up ─────────────────────────────────────
  observeEvent(input$show_signup, {
    shinyjs::hide("login_card")
    shinyjs::show("signup_card")
    shinyjs::hide("login_error")
  })

  observeEvent(input$show_login, {
    shinyjs::hide("signup_card")
    shinyjs::show("login_card")
    shinyjs::hide("signup_error")
    shinyjs::hide("signup_success")
  })

  # ── Lecturer signup: courses + weekly schedule ───────────────────────────
  output$signup_lecturer_setup <- renderUI({
    if (is.null(input$signup_role) || input$signup_role != "lecturer") return(NULL)

    if (!.try_db_init) {
      msg <- "Database not available — cannot configure lecturer courses."
      if (!is.null(.db_init_error) && nzchar(.db_init_error)) {
        msg <- paste0(msg, " (", .db_init_error, ")")
      }
      return(div(class = "mb-3", tags$small(msg)))
    }

    courses <- tryCatch(load_courses(), error = function(e) tibble::tibble())
    rooms   <- tryCatch(load_rooms(),   error = function(e) tibble::tibble())

    course_choices <- if (nrow(courses) > 0) {
      stats::setNames(
        as.character(courses$course_id),
        paste0(courses$course_code, " — ", courses$course_name)
      )
    } else {
      c()
    }

    room_choices <- if (nrow(rooms) > 0) {
      stats::setNames(
        as.character(rooms$room_id),
        ifelse(is.na(rooms$building) | rooms$building == "", rooms$room_number, paste0(rooms$room_number, " (", rooms$building, ")"))
      )
    } else {
      c()
    }

    tagList(
      div(class = "mb-3",
          tags$label("Courses you teach", class = "form-label"),
          selectizeInput(
            "signup_courses",
            NULL,
            choices = course_choices,
            multiple = TRUE,
            options = list(placeholder = "Select one or more courses")
          ),
          tags$small("For each selected course, set the group, day, time and room.", class = "text-muted")
      ),
      uiOutput("signup_courses_schedule_ui"),
      shinyjs::hidden(div(id = "signup_lecturer_error", class = "alert alert-warning mt-2 small mb-0", ""))
    )
  })

  output$signup_courses_schedule_ui <- renderUI({
    if (is.null(input$signup_role) || input$signup_role != "lecturer") return(NULL)
    if (is.null(input$signup_courses) || length(input$signup_courses) == 0) return(NULL)

    sem_id  <- tryCatch(get_active_semester_id(), error = function(e) "SPRING2026")
    courses <- tryCatch(load_courses(),          error = function(e) tibble::tibble())
    groups  <- tryCatch(load_groups(sem_id),     error = function(e) tibble::tibble())
    rooms   <- tryCatch(load_rooms(),           error = function(e) tibble::tibble())

    room_choices <- if (nrow(rooms) > 0) {
      stats::setNames(
        as.character(rooms$room_id),
        ifelse(is.na(rooms$building) | rooms$building == "", rooms$room_number, paste0(rooms$room_number, " (", rooms$building, ")"))
      )
    } else {
      c()
    }

    day_choices <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

    tagList(
      lapply(as.character(input$signup_courses), function(course_id_chr) {
        course_id <- suppressWarnings(as.integer(course_id_chr))
        g <- groups
        if (nrow(g) > 0 && !is.na(course_id)) {
          g <- g[g$course_id == course_id, , drop = FALSE]
        }

        group_choices <- if (nrow(g) > 0) {
          stats::setNames(as.character(g$group_id), paste0(g$group_code, " — ", g$group_name))
        } else {
          c()
        }

        div(
          class = "mb-3 p-2",
          style = "border: 1px solid rgba(0,0,0,0.1); border-radius: 8px;",
          tags$div(style = "font-weight:700; margin-bottom: 0.5rem;",
                   {
                     label <- course_id_chr
                     if (nrow(courses) > 0 && !is.na(course_id)) {
                       c_row <- courses[courses$course_id == course_id, , drop = FALSE]
                       if (nrow(c_row) > 0) {
                         label <- paste0(c_row$course_code[1], " — ", c_row$course_name[1])
                       }
                     }
                     paste0("Schedule: ", label)
                   }),
          div(class = "row",
              div(class = "col-12 col-md-6 mb-2",
                  tags$label("Group", class = "form-label"),
                  selectInput(paste0("signup_group_", course_id_chr), NULL, choices = group_choices)
              ),
              div(class = "col-12 col-md-6 mb-2",
                  tags$label("Day", class = "form-label"),
                  selectInput(paste0("signup_day_", course_id_chr), NULL, choices = day_choices, selected = "Monday")
              )
          ),
          div(class = "row",
              div(class = "col-6 col-md-3 mb-2",
                  tags$label("Start (HH:MM)", class = "form-label"),
                  textInput(paste0("signup_start_", course_id_chr), NULL, value = "10:00")
              ),
              div(class = "col-6 col-md-3 mb-2",
                  tags$label("End (HH:MM)", class = "form-label"),
                  textInput(paste0("signup_end_", course_id_chr), NULL, value = "11:30")
              ),
              div(class = "col-12 col-md-6 mb-2",
                  tags$label("Room", class = "form-label"),
                  selectInput(paste0("signup_room_", course_id_chr), NULL, choices = room_choices)
              )
          )
        )
      }),
      tags$small("Time format must be 24h HH:MM (e.g., 09:00).", class = "text-muted")
    )
  })

  # ── Sign-up handler ──────────────────────────────────────────────────────
  observeEvent(input$signup_btn, {
    shinyjs::hide("signup_success")

    # Basic client-side validation
    if (input$signup_password != input$signup_password_confirm) {
      shinyjs::html("signup_error", "Passwords do not match.")
      shinyjs::show("signup_error")
      return()
    }

    teaching_assignments <- NULL

    if (isTRUE(.try_db_init) && identical(input$signup_role, "lecturer")) {
      if (is.null(input$signup_courses) || length(input$signup_courses) == 0) {
        shinyjs::html("signup_lecturer_error", "Please select at least one course.")
        shinyjs::show("signup_lecturer_error")
        return()
      }

      # Build lecturer assignments table
      rows <- list()
      for (course_id_chr in as.character(input$signup_courses)) {
        group_val <- input[[paste0("signup_group_", course_id_chr)]]
        day_val   <- input[[paste0("signup_day_", course_id_chr)]]
        start_val <- input[[paste0("signup_start_", course_id_chr)]]
        end_val   <- input[[paste0("signup_end_", course_id_chr)]]
        room_val  <- input[[paste0("signup_room_", course_id_chr)]]

        if (is.null(group_val) || !nzchar(group_val)) {
          shinyjs::html("signup_lecturer_error", paste0("Please choose a group for course ", course_id_chr, "."))
          shinyjs::show("signup_lecturer_error")
          return()
        }

        time_ok <- function(x) is.character(x) && grepl("^\\d{2}:\\d{2}$", x)
        if (!time_ok(start_val) || !time_ok(end_val)) {
          shinyjs::html("signup_lecturer_error", paste0("Invalid time for course ", course_id_chr, ". Use HH:MM (e.g., 09:00)."))
          shinyjs::show("signup_lecturer_error")
          return()
        }

        rows[[length(rows) + 1]] <- data.frame(
          course_id  = as.integer(course_id_chr),
          group_id   = as.integer(group_val),
          day_name   = as.character(day_val),
          start_time = as.character(start_val),
          end_time   = as.character(end_val),
          room_id    = as.integer(room_val),
          stringsAsFactors = FALSE
        )
      }

      teaching_assignments <- dplyr::bind_rows(rows)
      shinyjs::hide("signup_lecturer_error")
    }

    if (.try_db_init) {
      result <- tryCatch({
        register_account_pg(
          email               = input$signup_email,
          password            = input$signup_password,
          full_name           = input$signup_name,
          role                = input$signup_role,
          institution_id      = input$signup_institution_id,
          teaching_assignments = teaching_assignments
        )
      }, error = function(e) {
        list(error = paste("Registration failed:", e$message))
      })
    } else {
      msg <- "Database not available. Cannot register."
      if (!is.null(.db_init_error) && nzchar(.db_init_error)) {
        msg <- paste0(msg, " (", .db_init_error, ")")
      }
      result <- list(error = msg)
    }

    if (!is.null(result$error)) {
      shinyjs::html("signup_error", result$error)
      shinyjs::show("signup_error")
    } else {
      # Success — show message and switch to login
      shinyjs::hide("signup_error")
      shinyjs::show("signup_success")
      updateTextInput(session, "login_email", value = input$signup_email)
      updateTextInput(session, "login_password", value = "")
      # Auto-switch to login after 2 seconds
      shinyjs::delay(2000, {
        shinyjs::hide("signup_card")
        shinyjs::show("login_card")
        shinyjs::hide("signup_success")
      })
      showNotification("Account created successfully! Please sign in.", type = "message", duration = 4)
    }
  })

  # ── Logout ────────────────────────────────────────────────────────────────
  observeEvent(input$logout_btn, {
    if (!is.null(app_data$api_token) && nzchar(app_data$api_token)) {
      tryCatch({
        call_api("/auth/logout", method = "POST", token = app_data$api_token)
      }, error = function(e) NULL)
    }
    session$sendCustomMessage("stopCamera", list())
    session$sendCustomMessage("setApiToken", list(token = NULL))
    shinyjs::hide("auth_modal_overlay")
    shinyjs::hide("forgot_password_modal")
    shinyjs::hide("cp_modal_overlay")
    shinyjs::hide("change_password_modal")
    is_logged_in(FALSE)
    app_data$user_role           <- NULL
    app_data$user_id             <- NULL
    app_data$institution_id      <- NULL
    app_data$user_name           <- NULL
    app_data$user_email          <- NULL
    app_data$api_token           <- NULL
    app_data$filtered_data       <- NULL
    app_data$selected_week       <- EDUPULSE_ACTIVE_ACADEMIC_WEEK
    app_data$selected_lecture_id <- NULL
    app_data$live_face_response  <- NULL
    app_data$live_attendance     <- NULL
    
    for (p in ALL_PANELS) shinyjs::hide(paste0("panel_", p))
    shinyjs::show("login_overlay")
    shinyjs::hide("main_app")
    updateTextInput(session,     "login_email", value = "")
    updateTextInput(session,     "login_password", value = "")
  })
  
  # ── Change Password: Open Modal ───────────────────────────────────────────
  observeEvent(input$change_password_btn, {
    shinyjs::show("cp_modal_overlay")
    shinyjs::show("change_password_modal")
    shinyjs::hide("cp_message")
    updateTextInput(session, "cp_old_password", value = "")
    updateTextInput(session, "cp_new_password", value = "")
    updateTextInput(session, "cp_new_password_confirm", value = "")
  })
  
  # ── Change Password: Logged-in (old + new) ────────────────────────────────
  observeEvent(input$cp_change_inapp_btn, {
    old_pw <- input$cp_old_password
    new_pw <- input$cp_new_password
    new_pw2 <- input$cp_new_password_confirm

    if (!nzchar(old_pw) || !nzchar(new_pw) || !nzchar(new_pw2)) {
      shinyjs::show("cp_message")
      shinyjs::html("cp_message", "Please fill in current password and the new password twice.")
      shinyjs::runjs("document.getElementById('cp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('cp_message').style.color = '#ef4444';")
      return()
    }
    if (!identical(new_pw, new_pw2)) {
      shinyjs::show("cp_message")
      shinyjs::html("cp_message", "New passwords do not match.")
      shinyjs::runjs("document.getElementById('cp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('cp_message').style.color = '#ef4444';")
      return()
    }
    if (nchar(new_pw) < 8) {
      shinyjs::show("cp_message")
      shinyjs::html("cp_message", "Password must be at least 8 characters.")
      shinyjs::runjs("document.getElementById('cp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('cp_message').style.color = '#ef4444';")
      return()
    }

    result <- tryCatch({
      call_api(
        "/auth/change-password",
        method = "POST",
        body = list(old_password = old_pw, new_password = new_pw),
        token = app_data$api_token
      )
    }, error = function(e) list(error = e$message))

    if (!is.null(result$error)) {
      shinyjs::show("cp_message")
      shinyjs::html("cp_message", paste("Error:", result$error))
      shinyjs::runjs("document.getElementById('cp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('cp_message').style.color = '#ef4444';")
    } else {
      shinyjs::show("cp_message")
      shinyjs::html("cp_message", "✓ Password changed successfully!")
      shinyjs::runjs("document.getElementById('cp_message').style.backgroundColor = 'rgba(34, 197, 94, 0.1)'; document.getElementById('cp_message').style.color = '#22c55e';")
      shinyjs::delay(1500, {
        shinyjs::hide("cp_modal_overlay")
        shinyjs::hide("change_password_modal")
      })
    }
  })

  # ── Forgot Password: Open modal from login ────────────────────────────────
  observeEvent(input$forgot_password_link, {
    shinyjs::show("auth_modal_overlay")
    shinyjs::show("forgot_password_modal")
    shinyjs::show("fp_step1")
    shinyjs::hide("fp_step2")
    shinyjs::hide("fp_message")
    updateTextInput(session, "fp_email", value = input$login_email %||% "")
    updateTextInput(session, "fp_code", value = "")
    updateTextInput(session, "fp_new_password", value = "")
  })

  observeEvent(input$fp_request_code_btn, {
    email <- trimws(input$fp_email)
    if (!nzchar(email)) {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", "Please enter your email address.")
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('fp_message').style.color = '#ef4444';")
      return()
    }

    result <- tryCatch({
      call_api("/auth/request-password-change", method = "POST", body = list(email = email))
    }, error = function(e) list(error = e$message))

    if (!is.null(result$error)) {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", paste("Error:", result$error))
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('fp_message').style.color = '#ef4444';")
    } else {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", "✓ Verification code sent to your email.")
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(34, 197, 94, 0.1)'; document.getElementById('fp_message').style.color = '#22c55e';")
      shinyjs::delay(800, {
        shinyjs::hide("fp_step1")
        shinyjs::show("fp_step2")
      })
    }
  })

  observeEvent(input$fp_verify_btn, {
    email <- trimws(input$fp_email)
    code <- trimws(input$fp_code)
    new_password <- input$fp_new_password

    if (!nzchar(code) || !nzchar(new_password)) {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", "Please enter both verification code and new password.")
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('fp_message').style.color = '#ef4444';")
      return()
    }
    if (nchar(new_password) < 8) {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", "Password must be at least 8 characters.")
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('fp_message').style.color = '#ef4444';")
      return()
    }

    result <- tryCatch({
      call_api(
        "/auth/verify-and-change-password",
        method = "POST",
        body = list(email = email, verification_code = code, new_password = new_password)
      )
    }, error = function(e) list(error = e$message))

    if (!is.null(result$error)) {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", paste("Error:", result$error))
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(239, 68, 68, 0.1)'; document.getElementById('fp_message').style.color = '#ef4444';")
    } else {
      shinyjs::show("fp_message")
      shinyjs::html("fp_message", "✓ Password reset successfully! You can now sign in.")
      shinyjs::runjs("document.getElementById('fp_message').style.backgroundColor = 'rgba(34, 197, 94, 0.1)'; document.getElementById('fp_message').style.color = '#22c55e';")
      shinyjs::delay(1500, {
        shinyjs::hide("forgot_password_modal")
        shinyjs::hide("auth_modal_overlay")
      })
    }
  })
  
  # ── Change Password: Close Modal ──────────────────────────────────────────
  observeEvent(input$cp_cancel_btn, {
    shinyjs::hide("cp_modal_overlay")
    shinyjs::hide("change_password_modal")
  })

  observeEvent(input$fp_cancel_btn, {
    shinyjs::hide("auth_modal_overlay")
    shinyjs::hide("forgot_password_modal")
  })
  

  # ── View lecture from schedule ────────────────────────────────────────────
  observeEvent(input$view_lecture_clicked, {
    req(input$view_lecture_clicked)
    app_data$selected_lecture_id <- input$view_lecture_clicked
    app_data$live_face_response <- NULL
    attendance <- call_api(paste0("/attendance/", input$view_lecture_clicked), token = app_data$api_token)
    app_data$live_attendance <- if (!is.null(attendance) && !isTRUE(attendance$error)) normalize_live_attendance(attendance$attendance) else NULL
    show_panel("monitor")
    showNotification(paste("Viewing:", input$view_lecture_clicked), type="message", duration=2)
  })
  
  # ── Start session from schedule (fully async — never blocks the UI) ────────
  observeEvent(input$start_session_clicked, {
    req(input$start_session_clicked)
    parts <- strsplit(input$start_session_clicked, "\\|")[[1]]
    lecture_id <- parts[1]
    session_mode <- if (length(parts) >= 2) parts[2] else "full"
    api_token  <- app_data$api_token

    app_data$session_mode <- session_mode
    app_data$selected_lecture_id <- lecture_id
    app_data$live_face_response <- NULL
    show_panel("monitor")
    showNotification(paste0("Starting ", session_mode, " session..."), type = "message", duration = 5)

    future({
      url <- paste0(API_BASE_URL, "/start-session/", lecture_id)
      resp <- httr::POST(url,
        body = list(mode = session_mode),
        encode = "form",
        add_headers(Authorization = paste("Bearer", api_token)),
        httr::timeout(15))
      if (httr::status_code(resp) >= 200 && httr::status_code(resp) < 300) {
        list(success = TRUE, data = jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8")))
      } else {
        body <- tryCatch(httr::content(resp, "text", encoding = "UTF-8"), error = function(e) "")
        list(success = FALSE, body = body)
      }
    }) %...>% (function(result) {
      if (isTRUE(result$success)) {
        showNotification(paste0("Session started (", session_mode, " mode)"), type = "message", duration = 3)
        app_data$live_attendance <- refresh_live_roster(lecture_id, api_token)
        shinyjs::delay(300, {
          session$sendCustomMessage("startCamera", list(lecture_id = lecture_id, mode = session_mode))
        })
      } else {
        showNotification(paste("Failed to start session:", result$body), type = "error", duration = 10)
      }
    }) %...!% (function(err) {
      showNotification(paste("Session error:", err$message), type = "error", duration = 10)
    })
  })

  observeEvent(app_data$session_mode, {
    if (app_data$session_mode == "full") {
      shinyjs::show("emotion_metrics_panel")
    } else {
      shinyjs::hide("emotion_metrics_panel")
    }
  })

  observeEvent(input$stop_attendance_btn, {
    lid <- app_data$selected_lecture_id
    if (is.null(lid) || !nzchar(lid)) {
      showNotification("Select a lecture before stopping attendance.", type = "warning", duration = 3)
      return()
    }
    result <- call_api(
      paste0("/stop-session/", lid),
      method = "POST",
      token = app_data$api_token
    )
    session$sendCustomMessage("stopCamera", list())
    if (!is.null(result) && !isTRUE(result$error)) {
      roster <- normalize_live_attendance(result$attendance)
      app_data$live_attendance <- if (!is.null(roster) && is.data.frame(roster) && nrow(roster) > 0)
        roster else refresh_live_roster(lid, app_data$api_token)
      showNotification(paste("Attendance stopped for lecture:", lid), type = "message", duration = 3)
    } else {
      showNotification("Failed to stop attendance session.", type = "error", duration = 5)
    }
  })
  
  # ── Reactive: data filtered by lecture + group ────────────────────────────
  filtered_data_reactive <- reactive({
    if (!is_logged_in() || is.null(app_data$filtered_data)) return(data.frame())
    data <- app_data$filtered_data
    
    lid <- app_data$selected_lecture_id
    if (!is.null(lid) && nchar(lid) > 0 && lid != "All")
      data <- data %>% filter(lecture_id == lid)
    
    grp <- input$filter_group
    if (!is.null(grp) && grp != "All")
      data <- data %>% filter(group_id == grp)
    
    data
  })

  # Simulated analysis for Weeks 1..(ACTIVE−1); real rows for ACTIVE week; locked weeks omitted.
  visualization_emotion_data <- reactive({
    req(is_logged_in())
    fc <- input$filter_course_schedule
    fg <- input$filter_group_schedule
    if (is.null(fc) || fc == "") fc <- "All"
    if (is.null(fg) || fg == "") fg <- "All"
    edu_sanitize_postgres_frame(edu_merge_prior_synthetic_weeks(
      app_data$filtered_data,
      app_data$lecture_schedule,
      fc,
      fg
    ))
  })

  dashboard_week_slice <- reactive({
    viz <- visualization_emotion_data()
    if (is.null(viz)) return(data.frame())
    dplyr::filter(viz, academic_week == app_data$selected_week)
  })
  
  # ── Reactive: weekly schedule ─────────────────────────────────────────────
  weekly_schedule_reactive <- reactive({
    if (is.null(app_data$lecture_schedule)) return(data.frame())
    sched <- filter_schedule_by_week(app_data$lecture_schedule, app_data$selected_week)
    
    cs <- input$filter_course_schedule
    if (!is.null(cs) && cs != "All") sched <- sched %>% filter(course_id == cs)
    
    gs <- input$filter_group_schedule
    if (!is.null(gs) && gs != "All") sched <- sched %>% filter(group_id == gs)
    
    sched
  })
  
  # ── Week info bar ─────────────────────────────────────────────────────────
  output$selected_week_display <- renderText({
    weeks <- load_semester_weeks()
    info  <- weeks %>% filter(academic_week == app_data$selected_week)
    if (nrow(info) > 0) {
      paste0("📅  Week ", app_data$selected_week, "  |  ",
             format(info$start_date[1], "%b %d"), " – ",
             format(info$end_date[1],   "%b %d, %Y"))
    } else {
      paste0("Week ", app_data$selected_week)
    }
  })
  
  # ── Weekly schedule DT ────────────────────────────────────────────────────
  output$table_weekly_schedule <- renderDT({
    sched <- weekly_schedule_reactive()
    if (nrow(sched) == 0) {
      return(datatable(data.frame(Message="No lectures scheduled for this week."),
                       options=list(dom="t"), rownames=FALSE))
    }
    
    display <- sched %>%
      mutate(
        StatusValue = if ("lecture_status" %in% names(.)) lecture_status else status,
        Actions = paste0(
          '<button class="btn btn-sm btn-success" style="font-size:0.72rem;padding:2px 8px;margin-right:4px;" ',
          'onclick="Shiny.setInputValue(\'start_session_clicked\',\'', lecture_id,
          '|attendance\',{priority:\'event\'})">Attendance</button>',
          '<button class="btn btn-sm btn-warning" style="font-size:0.72rem;padding:2px 8px;margin-right:4px;" ',
          'onclick="Shiny.setInputValue(\'start_session_clicked\',\'', lecture_id,
          '|full\',{priority:\'event\'})">Full Monitor</button>',
          '<button class="btn btn-sm btn-primary" style="font-size:0.72rem;padding:2px 10px;" ',
          'onclick="Shiny.setInputValue(\'view_lecture_clicked\',\'', lecture_id,
          '\',{priority:\'event\'})">▶ View</button>'
        )
      ) %>%
      select(Actions, Day=day_name, Date=lecture_date, Time=start_time,
             Course=course_code, CourseName=course_name, Group=group_name,
             Room=room, Students=expected_students, Status=StatusValue)
    
    datatable(display,
              escape    = FALSE,
              rownames  = FALSE,
              selection = "none",
              options   = list(
                pageLength = 10, dom = "ltip", scrollX = TRUE,
                columnDefs = list(list(className="dt-center", targets="_all"))
              )
    )
  }, server = FALSE)
  
  # ── Dashboard week metrics ────────────────────────────────────────────────
  output$card_week_lectures <- renderText({ nrow(weekly_schedule_reactive()) })
  
  output$card_week_engagement <- renderText({
    req(is_logged_in())
    d <- dashboard_week_slice()
    if (nrow(d)==0) return("—")
    round(mean(d$engagement_score, na.rm=TRUE), 2)
  })
  
  output$card_week_focus <- renderText({
    req(is_logged_in())
    d <- dashboard_week_slice()
    if (nrow(d)==0) return("—")
    round(mean(d$focus_score, na.rm=TRUE), 2)
  })
  
  output$card_week_confusion <- renderText({
    req(is_logged_in())
    d <- dashboard_week_slice()
    if (nrow(d)==0) return("0")
    nrow(compute_confusion_spikes(d))
  })

  output$dash_hero_line1 <- renderText({
    nm <- app_data$user_name
    if (is.null(nm) || !nzchar(nm)) nm <- ""
    greeting <- if (nzchar(nm)) paste0("Hello, ", nm) else "Teaching dashboard"
    sw <- suppressWarnings(as.integer(app_data$selected_week))
    if (!is.na(sw) && sw < EDUPULSE_ACTIVE_ACADEMIC_WEEK) {
      paste0(greeting, " · Week ", sw)
    } else {
      greeting
    }
  })

  output$dash_hero_line2 <- renderText({
    req(is_logged_in())
    w <- app_data$selected_week
    nlec <- nrow(weekly_schedule_reactive())
    fc <- input$filter_course_schedule
    fg <- input$filter_group_schedule
    parts <- c(
      paste0("Week ", w),
      paste0(nlec, if (isTRUE(nlec == 1)) " session scheduled" else " sessions scheduled")
    )
    if (!is.null(fc) && nzchar(fc) && fc != "All") parts <- c(parts, paste("Course:", fc))
    if (!is.null(fg) && nzchar(fg) && fg != "All") parts <- c(parts, paste("Group:", fg))
    paste(parts, collapse = " · ")
  })

  # ── Live Monitor cards ────────────────────────────────────────────────────
  output$card_engagement <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); round(m$avg_engagement,3)
  })
  output$card_focus <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); round(m$avg_focus,3)
  })
  output$card_attendance <- renderText({
    att <- app_data$live_attendance
    lf <- app_data$live_face_response
    if (!is.null(att) && is.data.frame(att) && nrow(att) > 0) {
      present <- attendance_present_count(att)
      denom <- nrow(att)
      if (denom > 0) return(paste0(round((present / denom) * 100, 1), "%"))
    }
    pc <- suppressWarnings(as.integer(lf$present_count))
    ex <- suppressWarnings(as.integer(lf$expected_students))
    if (length(pc) != 1L || length(ex) != 1L || is.na(pc) || is.na(ex) || ex <= 0L) {
      return({
        m <- compute_summary_metrics(filtered_data_reactive())
        paste0(round(m$attendance_rate * 100, 1), "%")
      })
    }
    paste0(round((pc / ex) * 100, 1), "%")
  })
  output$card_confusion <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); paste0(round(m$confusion_rate*100,1),"%")
  })
  output$card_present <- renderText({
    att <- app_data$live_attendance
    lf <- app_data$live_face_response
    if (!is.null(att) && is.data.frame(att) && nrow(att) > 0) {
      return(as.character(attendance_present_count(att)))
    }
    pc <- suppressWarnings(as.integer(lf$present_count))
    if (length(pc) != 1L || is.na(pc)) {
      m <- compute_summary_metrics(filtered_data_reactive())
      return(as.character(m$students_present))
    }
    as.character(pc)
  })
  output$card_dominant_emotion <- renderText({
    d <- filtered_data_reactive()
    if (nrow(d)==0) return("N/A")
    ec <- table(d$emotion); names(ec)[which.max(ec)]
  })
  
  output$narrative_insights <- renderText({
    compute_narrative_insights(filtered_data_reactive())
  })
  
  output$selected_lecture_display <- renderText({
    lid <- app_data$selected_lecture_id
    if (is.null(lid) || lid=="")
      "ℹ️  No lecture selected — go to Dashboard and click ▶ View on a lecture row."
    else
      paste0("▶  Viewing Lecture: ", lid)
  })
  
  observeEvent(input$live_face_response, {
    req(input$live_face_response)
    parsed <- tryCatch(
      fromJSON(input$live_face_response, simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (is.null(parsed)) return(invisible(NULL))

    parsed <- edu_normalize_live_frame_payload(parsed)

    lid <- app_data$selected_lecture_id
    tok <- app_data$api_token

    # Reload roster after every analyzed frame — same source counts as Postgres (fixes stale JSON vs DT/cards drift).
    if (!is.null(lid) && nzchar(as.character(lid)) && !is.null(tok) && nzchar(tok)) {
      refreshed <- tryCatch(call_api(paste0("/attendance/", lid), token = tok, timeout_sec = 30),
                            error = function(e) NULL)
      if (!is.null(refreshed) && !isTRUE(refreshed$error)) {
        roster_df <- normalize_live_attendance(refreshed$attendance)
        if (!is.null(roster_df) && is.data.frame(roster_df) && nrow(roster_df) > 0) app_data$live_attendance <- roster_df
        if (!is.null(refreshed$attendance)) parsed$attendance <- refreshed$attendance
        parsed$present_count <- refreshed$present_count %||% parsed$present_count
        parsed$absent_count <- refreshed$absent_count %||% parsed$absent_count
        parsed$expected_students <- refreshed$expected_students %||% parsed$expected_students
        parsed$session_status <- refreshed$session_status %||% parsed$session_status
      } else if (!is.null(parsed$attendance)) {
        app_data$live_attendance <- normalize_live_attendance(parsed$attendance)
      }
    } else if (!is.null(parsed$attendance)) {
      app_data$live_attendance <- normalize_live_attendance(parsed$attendance)
    }

    app_data$live_face_response <- parsed

    recognized <- parsed$recognized
    if (!inherits(recognized, "data.frame") || nrow(recognized) < 1L) return(invisible(NULL))
    tryCatch({
      for (i in seq_len(nrow(recognized))) {
        row <- as.list(recognized[i, , drop = FALSE])
        new_row <- build_emotion_flat_row(row, lid)
        if (!is.null(app_data$all_data) && inherits(app_data$all_data, "data.frame") &&
            nrow(app_data$all_data) > 0) {
          app_data$all_data <- edu_sanitize_postgres_frame(
            dplyr::bind_rows(app_data$all_data, new_row)
          )
          app_data$filtered_data <- edu_sanitize_postgres_frame(
            filter_by_role(app_data$all_data, app_data$user_role, app_data$user_id)
          )
        }
      }
    }, error = function(e) {
      message("Live telemetry append skipped: ", e$message)
    })
  })
  
  output$live_face_summary <- renderUI({
    res <- app_data$live_face_response
    if (is.null(res)) {
      HTML('<div style="color:#94a3b8;">No frame analyzed yet.</div>')
    } else if (!is.data.frame(res$recognized) || nrow(res$recognized) == 0) {
      msg <- ""
      if ("message" %in% names(res) && length(res$message)) {
        msg <- trimws(paste(as.character(res$message)[1], collapse = ""))
      }
      if (!nzchar(msg)) msg <- "No enrolled face matched (or backends returned recognized=false)."
      HTML(sprintf(
        '%s<div><strong>Recognized this frame:</strong> 0<br/><small style="color:#94a3b8;">Faces: %s · Unknown: %s</small></div>',
        ifelse(nzchar(msg), sprintf('<p style="margin:0 0 0.5rem 0;">%s</p>', htmltools::htmlEscape(msg)), ""),
        if (!is.null(res$total_faces)) as.character(res$total_faces) else "—",
        if (!is.null(res$unknown_count)) as.character(res$unknown_count) else "—"
      ))
    } else {
      rdf <- res$recognized
      rows <- character(nrow(rdf))
      co <- function(z) if (length(z)) trimws(paste(as.character(z[1]), collapse = "")) else ""
      for (i in seq_len(nrow(rdf))) {
        rw <- as.list(rdf[i, , drop = FALSE])
        nm <- suppressWarnings(htmlEscape(if (nzchar(co(rw[["student_name"]]))) co(rw[["student_name"]]) else ""))
        sid <- suppressWarnings(htmlEscape(co(rw[["student_id"]])))
        emv <- suppressWarnings(co(rw[["emotion"]]))
        emTxt <- ifelse(nzchar(emv), emv, "Neutral")
        fc <- suppressWarnings(as.numeric(co(rw[["face_confidence"]])))
        if (length(fc) != 1L || is.na(fc)) fc <- 0 else fc <- fc[1]
        rows[[i]] <- sprintf(
          '<div><strong>%s</strong> (%s) — %s, face %s%%</div>',
          nm, sid, suppressWarnings(htmlEscape(emTxt)),
          round(fc * 100, 1)
        )
      }
      HTML(paste0(
        '<div><strong>Recognized:</strong> ', nrow(res$recognized),
        '<br/><strong>Present:</strong> ', res$present_count %||% 0,
        ' / ', res$expected_students %||% 0,
        '<hr class="ep-hr"/>',
        paste(rows, collapse = ""),
        '</div>'
      ))
    }
  })

  output$table_live_attendance <- renderDT({
    att <- app_data$live_attendance
    if (is.null(att) || !is.data.frame(att) || nrow(att) == 0) {
      return(datatable(data.frame(Message = "Start attendance to see live roster status."),
                       options = list(dom = "t"), rownames = FALSE))
    }
    display <- att %>%
      select(
        StudentID = student_id,
        Student = student_name,
        Status = status,
        LastSeen = last_seen_at,
        AttendancePct = attendance_pct
      )
    datatable(display, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE, selection = "none")
  })
  
  # ── Charts (dark theme helper) ────────────────────────────────────────────
  dark_plot <- function(expr, bg = "#0b1220") {
    renderPlot({ expr }, bg = bg)
  }
  
  output$chart_timeline          <- renderPlot({ render_engagement_timeline(filtered_data_reactive()) },             bg="#0b1220")
  output$chart_emotions          <- renderPlot({ render_emotion_distribution(filtered_data_reactive()) },            bg="#0b1220")
  output$chart_confusion_timeline<- renderPlot({ render_confusion_timeline(filtered_data_reactive()) },             bg="#0b1220")
  output$chart_boredom_timeline  <- renderPlot({ render_boredom_timeline(filtered_data_reactive()) },               bg="#0b1220")
  output$chart_dominant_emotion  <- renderPlot({ render_dominant_emotion_by_student(filtered_data_reactive()) },    bg="#0b1220")
  output$chart_engagement_ranking<- renderPlot({ render_student_engagement_ranking(filtered_data_reactive(),10) },  bg="#0b1220")
  output$chart_confusion_ranking <- renderPlot({ render_confusion_rate_by_student(filtered_data_reactive(),10) },   bg="#0b1220")
  output$chart_engagement_focus  <- renderPlot({ render_engagement_vs_focus_scatter(filtered_data_reactive()) },    bg="#0b1220")
  output$chart_semester_engagement<-renderPlot({ render_semester_engagement_trend(visualization_emotion_data()) },        bg="#0b1220")
  output$chart_semester_confusion <- renderPlot({ render_semester_confusion_trend(visualization_emotion_data()) },        bg="#0b1220")
  output$chart_course_comparison  <- renderPlot({ render_course_engagement_comparison(visualization_emotion_data()) },    bg="#0b1220")
  
  # ── Emotion heatmap (new) ─────────────────────────────────────────────────
  output$chart_emotion_heatmap <- renderPlot({
    d <- visualization_emotion_data()
    if (is.null(d) || nrow(d)==0) {
      return(ggplot() +
               theme(plot.background=element_rect(fill="#0b1220",colour=NA),
                     panel.background=element_rect(fill="#0b1220",colour=NA)) +
               annotate("text",x=0.5,y=0.5,label="No data",colour="#64748b",size=6))
    }
    
    hm <- d %>%
      group_by(academic_week, emotion) %>%
      summarise(count=n(), .groups="drop") %>%
      group_by(academic_week) %>%
      mutate(pct=count/sum(count)) %>%
      ungroup()
    
    emotion_order <- c("Happy","Neutral","Confused","Bored")
    hm$emotion <- factor(hm$emotion, levels=rev(emotion_order))
    
    ggplot(hm, aes(x=academic_week, y=emotion, fill=pct)) +
      geom_tile(colour="#0b1220", linewidth=0.6) +
      geom_text(aes(label=scales::percent(pct,accuracy=1)),
                colour="white", size=3, fontface="bold") +
      scale_fill_gradientn(
        colours=c("#1e293b","#1a3a5c","#81aad9","#f59e0b"),
        labels=scales::percent, name="Share"
      ) +
      scale_x_continuous(breaks=1:16) +
      labs(title="Emotion Share Heatmap — 16 Weeks",
           subtitle="Weeks 1–12 modeled snapshots; Week 13 from records; Weeks 14–16 locked",
           x="Academic Week", y=NULL) +
      theme_minimal(base_size=12) +
      theme(
        plot.background  = element_rect(fill="#111a2d",colour=NA),
        panel.background = element_rect(fill="#0b1220",colour=NA),
        panel.grid       = element_blank(),
        text             = element_text(colour="#e2e8f0"),
        axis.text        = element_text(colour="#94a3b8"),
        legend.background= element_rect(fill="#111a2d",colour=NA),
        legend.text      = element_text(colour="#e2e8f0"),
        plot.title       = element_text(colour="#81aad9",face="bold"),
        plot.subtitle    = element_text(colour="#64748b"),
        plot.margin      = margin(10,10,10,10)
      )
  }, bg="#0b1220")
  
  # ── Confusion spikes table ────────────────────────────────────────────────
  output$table_confusion_spikes <- renderDT({
    spikes <- compute_confusion_spikes(filtered_data_reactive())
    if (nrow(spikes)==0) spikes <- data.frame(Message="No confusion spikes detected.")
    datatable(spikes, options=list(pageLength=10,scrollX=TRUE), rownames=FALSE, selection="none")
  })
  
  # ── Report ────────────────────────────────────────────────────────────────
  output$report_lecture_name <- renderText({
    lid <- app_data$selected_lecture_id
    if (is.null(lid)||lid=="") return("No lecture selected")
    d <- app_data$all_data %>% filter(lecture_id==lid)
    if (nrow(d)==0) "Unknown" else d$lecture_name[1]
  })
  output$report_course_name <- renderText({
    lid <- app_data$selected_lecture_id; if (is.null(lid)) return("")
    d <- app_data$all_data %>% filter(lecture_id==lid)
    if (nrow(d)==0) "" else paste0(d$course_code[1]," – ",d$course_name[1])
  })
  output$report_group_name <- renderText({
    lid <- app_data$selected_lecture_id; if (is.null(lid)) return("")
    d <- app_data$all_data %>% filter(lecture_id==lid)
    if (nrow(d)==0) "" else d$group_name[1]
  })
  output$report_lecturer_name <- renderText({
    lid <- app_data$selected_lecture_id; if (is.null(lid)) return("")
    d <- app_data$all_data %>% filter(lecture_id==lid)
    if (nrow(d)==0) "" else d$lecturer_name[1]
  })
  output$report_lecture_date <- renderText({
    lid <- app_data$selected_lecture_id; if (is.null(lid)) return("")
    s <- app_data$lecture_schedule %>% filter(lecture_id==lid)
    if (nrow(s)==0) "" else format(as.Date(s$lecture_date[1]),"%B %d, %Y")
  })
  output$report_lecture_time <- renderText({
    lid <- app_data$selected_lecture_id; if (is.null(lid)) return("")
    s <- app_data$lecture_schedule %>% filter(lecture_id==lid)
    if (nrow(s)==0) "" else paste0(s$start_time[1]," – ",s$end_time[1])
  })
  
  report_summary_reactive <- reactive({
    if (is.null(app_data$selected_lecture_id)) return(NULL)
    calculate_lecture_summary(app_data$all_data, app_data$selected_lecture_id)
  })
  
  output$report_total_students   <- renderText({ s<-report_summary_reactive(); if(is.null(s))"0" else s$total_students })
  output$report_present_students <- renderText({ s<-report_summary_reactive(); if(is.null(s))"0" else round(s$present_students,0) })
  output$report_absent_students  <- renderText({ s<-report_summary_reactive(); if(is.null(s))"0" else s$absent_students })
  output$report_avg_engagement   <- renderText({ s<-report_summary_reactive(); if(is.null(s))"0" else round(s$avg_engagement,3) })
  output$report_avg_focus        <- renderText({ s<-report_summary_reactive(); if(is.null(s))"0" else round(s$avg_focus,3) })
  output$report_dominant_emotion <- renderText({ s<-report_summary_reactive(); if(is.null(s))"N/A" else s$dominant_emotion })
  
  output$table_report <- renderDT({
    lid <- app_data$selected_lecture_id
    if (is.null(lid)||lid=="") {
      return(datatable(data.frame(Message="Select a lecture to view the student report."),
                       options=list(dom="t"), rownames=FALSE))
    }
    report <- calculate_lecture_report(app_data$all_data, lid)
    if (nrow(report)==0) {
      return(datatable(data.frame(Message="No data for this lecture."),
                       options=list(dom="t"), rownames=FALSE))
    }
    disp <- report %>% select(
      student_id, student_name, attendance_status,
      all_emotions, happy_count, neutral_count, confused_count, bored_count,
      dominant_emotion, avg_engagement, avg_focus,
      confusion_rate, boredom_rate, first_emotion, last_emotion, risk_flag
    )
    datatable(disp, options=list(pageLength=15,scrollX=TRUE), rownames=FALSE, selection="none")
  })
  
  # ── Clustering ────────────────────────────────────────────────────────────
  output$cluster_content <- renderUI({
    if (isTRUE(app_data$user_role=="Student")) {
      div(div(class="ep-card",
              div(class="ep-card-header","Your Cluster Profile"),
              textOutput("student_cluster_message")
      ))
    } else {
      list(
        div(class="ep-card",
            div(class="ep-card-header","Student Cluster Assignments"),
            DTOutput("table_clusters")
        ),
        div(class="ep-card mt-3",
            div(class="ep-card-header","Raw Data"),
            DTOutput("table_raw_data")
        )
      )
    }
  })
  
  output$table_clusters <- renderDT({
    cr <- perform_clustering(filtered_data_reactive())
    if (!is.null(cr$clusters)) {
      cl <- cr$clusters %>%
        select(student_id,student_name,group_id,avg_engagement,avg_focus,cluster) %>%
        arrange(cluster,student_name)
      datatable(cl, options=list(pageLength=10), rownames=FALSE, selection="none")
    } else {
      datatable(data.frame(Message="Insufficient data for clustering."),
                options=list(dom="t"), rownames=FALSE)
    }
  })
  
  output$student_cluster_message <- renderText({
    cr <- perform_clustering(filtered_data_reactive())
    if (!is.null(cr$clusters)) {
      mc <- cr$clusters %>% filter(student_id==app_data$user_id) %>% pull(cluster)
      if (length(mc)>0) paste0("You are in Cluster ",mc,". This reflects your engagement, focus, and behaviour pattern.")
      else "Cluster information not available."
    } else "Clustering analysis not available."
  })
  
  output$table_raw_data <- renderDT({
    d <- filtered_data_reactive()
    if (nrow(d)>0) {
      disp <- d %>% select(record_id,student_id,student_name,lecture_id,
                           timestamp,emotion,engagement_score,focus_score,is_present,group_id)
      datatable(disp, options=list(pageLength=10), rownames=FALSE, selection="none")
    } else {
      datatable(data.frame(Message="No data."), options=list(dom="t"), rownames=FALSE)
    }
  })
  
  # ── Attendance ────────────────────────────────────────────────────────────
  # One row per student × lecture (emotion rows are many per session); show mean engagement
  # and confusion as the share of readings where emotion == "Confused".
  output$table_attendance <- renderDT({
    d <- filtered_data_reactive()
    need <- c("student_id", "student_name", "lecture_id", "emotion", "engagement_score")
    if (nrow(d) < 1L || !all(need %in% names(d))) {
      return(datatable(data.frame(Message = "No data."), options = list(dom = "t"), rownames = FALSE))
    }
    d2 <- d
    if (!"attendance_status" %in% names(d2)) d2$attendance_status <- NA_character_
    if (!"is_present" %in% names(d2)) d2$is_present <- NA
    if (!"left_room" %in% names(d2)) d2$left_room <- NA
    if ("timestamp" %in% names(d2)) {
      d2 <- d2 %>% dplyr::arrange(.data$student_id, .data$lecture_id, dplyr::desc(.data$timestamp))
    }
    att <- d2 %>%
      dplyr::group_by(.data$student_id, .data$student_name, .data$lecture_id) %>%
      dplyr::summarise(
        .groups = "drop",
        Samples = dplyr::n(),
        `Avg engagement` = round(mean(as.numeric(.data$engagement_score), na.rm = TRUE), 3),
        `Pct readings confused` = round(
          100 * mean(tolower(trimws(as.character(.data$emotion))) == "confused", na.rm = TRUE),
          1
        ),
        `Attendance (latest)` = dplyr::first(trimws(as.character(.data$attendance_status))),
        `Present (any sample)` = any(as.logical(.data$is_present), na.rm = TRUE),
        `Left room (any sample)` = any(as.logical(.data$left_room), na.rm = TRUE)
      )
    disp <- att %>%
      dplyr::rename(`Student ID` = .data$student_id, Student = .data$student_name, Lecture = .data$lecture_id)
    datatable(disp, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE, selection = "none")
  })
  
  # ── Settings ──────────────────────────────────────────────────────────────
  output$role_badge       <- renderText({ if(is_logged_in()) app_data$user_role else "" })
  output$info_username    <- renderText({
    if(!is_logged_in()) return("Not logged in")
    app_data$user_email %||% "Unknown"
  })
  output$info_role         <- renderText({ if(is_logged_in()) app_data$user_role  else "Not logged in" })
  output$info_user_id      <- renderText({ if(is_logged_in()) app_data$institution_id %||% app_data$user_id else "Not logged in" })
  output$info_display_name <- renderText({ if(is_logged_in()) app_data$user_name  else "Not logged in" })
  output$info_selected_week <- renderText({
    if(is_logged_in()) paste("Week",app_data$selected_week) else "Not logged in"
  })
  output$info_selected_lecture <- renderText({
    if(!is_logged_in()) return("Not logged in")
    lid <- app_data$selected_lecture_id
    if(is.null(lid)||lid=="") "None" else lid
  })
  
  # ── Periodic CSV backup sync (every 10 minutes) ─────────────────────────
  csv_sync_timer <- reactiveTimer(600000)
  observe({
    csv_sync_timer()
    if (.try_db_init && is_logged_in()) {
      tryCatch({
        csv_backup_all()
        app_data$last_csv_sync <- Sys.time()
      }, error = function(e) {
        message(paste("Periodic CSV backup failed:", e$message))
      })
    }
  })

  # ── Manual CSV sync button ──────────────────────────────────────────────
  sync_status <- reactiveVal(NULL)
  observeEvent(input$sync_csv_btn, {
    if (.try_db_init) {
      tryCatch({
        csv_backup_all()
        sync_status(paste("Last sync:", format(Sys.time(), "%H:%M:%S")))
        showNotification("CSV backup synced successfully!", type = "message", duration = 3)
      }, error = function(e) {
        sync_status(paste("Sync failed:", e$message))
        showNotification(paste("CSV backup failed:", e$message), type = "error", duration = 5)
      })
    } else {
      sync_status("Database not available — cannot sync")
      showNotification("Database not available", type = "warning", duration = 3)
    }
  })
  output$sync_status <- renderText({ sync_status() })

  # ── CSV export ────────────────────────────────────────────────────────────
  output$download_data <- downloadHandler(
    filename = function() paste0("edupulse_export_",format(Sys.time(),"%Y%m%d_%H%M%S"),".csv"),
    content  = function(file) write.csv(filtered_data_reactive(), file, row.names=FALSE)
  )
}

shinyApp(ui, server)
