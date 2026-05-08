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

# Load helper functions
source("R/db_connect.R")
source("R/db_auth.R")
source("R/db_queries.R")
source("R/data_helpers.R")
source("R/analytics_helpers.R")
source("R/ui_helpers.R")
source("R/csv_backup.R")

# Initialize database pool on app start
# (conditional — falls back to CSV if DB unavailable)
.try_db_init <- tryCatch({
  get_db_pool()
  TRUE
}, error = function(e) {
  message(paste("Database not available, using CSV fallback:", e$message))
  source("R/generate_sample_data.R")
  FALSE
})

# Initialize app-level data
app_data <- reactiveValues(
  all_data = NULL,
  filtered_data = NULL,
  lecture_schedule = NULL,
  semester_weeks = NULL,
  user_role = NULL,
  user_id = NULL,
  user_name = NULL,
  user_username = NULL,
  db_user_id = NULL,
  selected_week = 1,
  selected_lecture_id = NULL,
  start_session_request = NULL,
  live_face_response = NULL
)

# Authenticate user via PostgreSQL (with CSV fallback)
authenticate_user <- function(username, password) {
  # Try database auth first
  if (.try_db_init) {
    user <- tryCatch({
      authenticate_user_pg(username, password)
    }, error = function(e) NULL)
    if (!is.null(user)) return(user)
  }

  # CSV fallback: hardcoded users for development
  USERS <- list(
    list(username = "admin",    password = "admin123",    role = "Admin",    user_id = "ADMIN", name = "Administrator"),
    list(username = "lecturer", password = "lecturer123", role = "Lecturer", user_id = "T01",   name = "Dr. Ahmed"),
    list(username = "student",  password = "student123",  role = "Student",  user_id = "S001",  name = "Student 1")
  )
  for (u in USERS) {
    if (u$username == username && u$password == password) return(u)
  }
  NULL
}

# API configuration
API_BASE_URL <- "http://localhost:8000"

# Function to call FastAPI with timeout
call_api <- function(endpoint, method = "GET", body = NULL) {
  url <- paste0(API_BASE_URL, endpoint)
  tryCatch({
    config <- timeout(3)  # 3 second timeout
    if (method == "POST") {
      response <- POST(url, body = body, encode = "json", config = config)
    } else {
      response <- GET(url, config = config)
    }
    if (status_code(response) == 200) {
      return(fromJSON(content(response, "text", encoding = "UTF-8")))
    } else {
      message(paste("API call failed with status:", status_code(response)))
      return(NULL)
    }
  }, error = function(e) {
    message(paste("API call error:", e$message))
    return(NULL)
  })
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
        --bg: #0b1220;
        --surface: #111a2d;
        --surface-alt: #0f172a;
        --text: #f1f5f9;
        --muted: #94a3b8;
        --accent: #81aad9;
        --accent-strong: #6b96c7;
        --border: #24344c;
        --border-strong: #81aad9;
        --panel-text: #81aad9;
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
        --navbar-bg: #0b1220;
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
      body { background-color: var(--bg) !important; color: var(--text) !important; font-family: 'Plus Jakarta Sans', 'Inter', sans-serif; margin:0; }
      .ep-navbar { background-color: var(--navbar-bg); border-bottom: 1px solid var(--border);
                   padding: 0.75rem 1.5rem; display: flex; align-items: center; gap: 0.75rem;
                   box-shadow: var(--shadow-card); flex-wrap: wrap; }
      .ep-brand  { color: var(--accent); font-weight: 800; font-size: 1.25rem; margin-right: auto; }
      .ep-nav-link { color: var(--navbar-link); background: none; border: none; cursor: pointer;
                     font-size: 0.85rem; padding: 4px 10px; border-radius: 10px;
                     transition: color 0.22s ease-out, background 0.22s ease-out; }
      .ep-nav-link:hover { color: var(--navbar-link-hover); background: rgba(129,170,217,0.08); }
      .sidebar { background-color: var(--surface); border-right: 1px solid var(--border);
                 min-height: calc(100vh - 56px); padding: 1.25rem; width: 220px; flex-shrink: 0; }
      .main-panel { background-color: var(--bg); padding: 1.5rem; flex-grow: 1; overflow-y: auto; }
      .ep-card { background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
                 padding: 1.25rem; margin-bottom: 1rem; box-shadow: var(--shadow-card); }
      .ep-card-header { color: var(--panel-text); font-weight: 700; font-size: 0.82rem;
                        text-transform: uppercase; letter-spacing: 0.07em; margin-bottom: 0.85rem; }
      .metric-card { background: var(--surface);
                     border: 1px solid var(--border); border-radius: 16px; padding: 1.1rem;
                     margin-bottom: 0.75rem; transition: border-color 0.22s ease-out, box-shadow 0.22s ease-out;
                     box-shadow: var(--shadow-card); }
      .metric-card:hover { border-color: var(--border-strong); box-shadow: var(--shadow-soft); }
      .metric-value { font-size: 1.8rem; font-weight: 700; color: var(--accent); line-height: 1.1; }
      .metric-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase;
                      letter-spacing: 0.09em; margin-top: 0.3rem; }
      .metric-icon  { font-size: 1.3rem; margin-bottom: 0.3rem; }
      .week-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 4px; }
      .week-btn { width:100%; background: var(--bg); border:1px solid var(--border); color: var(--muted);
                  border-radius:10px; padding:5px 2px; font-size:0.72rem; cursor:pointer;
                  transition:all 0.22s ease-out; line-height:1.2; }
      .week-btn:hover  { background: var(--surface); color: var(--text); border-color: var(--border-strong); }
      .week-btn.active { background: var(--accent-strong); border-color: var(--accent-strong); color:#fff; font-weight:700; }
      .section-title { color: var(--accent); font-size:1.4rem; font-weight:800; margin-bottom:0.2rem; }
      .section-sub   { color: var(--muted); font-size:0.88rem; margin-bottom:1.25rem; }
      .week-info-bar { background: var(--surface);
                       border:1px solid var(--border-strong); border-radius:14px;
                       padding:0.65rem 1.2rem; margin-bottom:1.1rem;
                       color: var(--accent); font-weight:700; font-size:0.95rem; }
      .badge-role { background: var(--surface); color: var(--accent); padding:3px 12px;
                   border-radius:24px; font-size:0.72rem; font-weight:700; border:1px solid var(--border); }
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
      .login-logo { color: var(--login-logo); font-size:1.9rem; font-weight:800; text-align:center; margin-bottom:0.2rem; }
      .login-sub  { text-align:center; color: var(--muted); font-size:0.88rem; margin-bottom:2rem; }
      .btn-primary { background-color: var(--accent-strong)!important; border-color: var(--accent-strong)!important; color:#fff!important; }
      .btn-primary:hover { background-color: var(--accent)!important; border-color: var(--accent)!important; }
      .btn-outline-primary { border-color: var(--border)!important; color: var(--muted)!important; background: var(--surface)!important; }
      .btn-outline-primary:hover { border-color: var(--accent)!important; color: var(--accent)!important; background: var(--surface)!important; }
      hr.ep-hr { border-color: var(--border); margin:0.9rem 0; }
      h4.sub-section { color: var(--accent-strong); font-size:1rem; font-weight:700;
                        margin-top:1.25rem; margin-bottom:0.75rem; }
      /* ── Theme Toggle Button ─────────────────────────────────────────────── */
      #toggle_theme {
        display: inline-flex !important;
        align-items: center;
        gap: 6px;
        height: 32px;
        min-width: 88px;
        padding: 0 12px !important;
        border-radius: 999px !important;
        border: 1px solid var(--border) !important;
        background: var(--surface) !important;
        color: var(--muted) !important;
        font-size: 12px !important;
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
      "var cameraStream = null;\n" ,
      "var cameraInterval = null;\n" ,
      "var currentLectureId = null;\n" ,
      "function startMonitorCamera(message) {\n" ,
      "  currentLectureId = message.lecture_id;\n" ,
      "  var video = document.getElementById('monitor_video');\n" ,
      "  var canvas = document.getElementById('monitor_canvas');\n" ,
      "  var status = document.getElementById('camera_status');\n" ,
      "  if (!video || !canvas || !status) return;\n" ,
      "  if (cameraStream) { stopMonitorCamera(); }\n" ,
      "  status.innerText = 'Requesting camera access...';\n" ,
      "  navigator.mediaDevices.getUserMedia({ video: true, audio: false })\n" ,
      "    .then(function(stream) {\n" ,
      "      cameraStream = stream;\n" ,
      "      video.srcObject = stream;\n" ,
      "      video.play();\n" ,
      "      status.innerText = 'Camera active. Capturing frames to backend.';\n" ,
      "      if (!cameraInterval) {\n" ,
      "        cameraInterval = setInterval(sendCaptureFrame, 2500);\n" ,
      "        sendCaptureFrame();\n" ,
      "      }\n" ,
      "    })\n" ,
      "    .catch(function(err) {\n" ,
      "      status.innerText = 'Camera unavailable: ' + err.message;\n" ,
      "    });\n" ,
      "}\n" ,
      "function stopMonitorCamera() {\n" ,
      "  if (cameraInterval) { clearInterval(cameraInterval); cameraInterval = null; }\n" ,
      "  if (cameraStream) { cameraStream.getTracks().forEach(function(track) { track.stop(); }); cameraStream = null; }\n" ,
      "  var status = document.getElementById('camera_status');\n      var video = document.getElementById('monitor_video');\n" ,
      "  if (status) status.innerText = 'Camera stopped.';\n" ,
      "  if (video) { video.pause(); video.srcObject = null; }\n" ,
      "}\n" ,
      "function sendCaptureFrame() {\n" ,
      "  if (!cameraStream || !currentLectureId) return;\n" ,
      "  var video = document.getElementById('monitor_video');\n" ,
      "  var canvas = document.getElementById('monitor_canvas');\n" ,
      "  var status = document.getElementById('camera_status');\n" ,
      "  if (!video || !canvas || !status) return;\n" ,
      "  canvas.width = video.videoWidth || 640;\n" ,
      "  canvas.height = video.videoHeight || 480;\n" ,
      "  var ctx = canvas.getContext('2d');\n" ,
      "  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);\n" ,
      "  canvas.toBlob(function(blob) {\n" ,
      "    if (!blob) return;\n" ,
      "    var data = new FormData();\n" ,
      "    data.append('file', blob, 'frame.jpg');\n" ,
      "    data.append('lecture_id', currentLectureId);\n" ,
      "    fetch('http://localhost:8000/analyze-attendance-frame', { method: 'POST', body: data })\n" ,
      "      .then(function(response) { return response.json(); })\n" ,
      "      .then(function(json) {\n" ,
      "        Shiny.setInputValue('live_face_response', JSON.stringify(json), { priority: 'event' });\n" ,
      "        var summary = document.getElementById('face_recognition_status');\n" ,
      "        if (summary) {\n" ,
      "          if (json.recognized === false) {\n" ,
      "            summary.innerHTML = '<strong>Face status:</strong> Not recognized';\n" ,
      "          } else {\n" ,
      "            summary.innerHTML = '<strong>Recognized:</strong> ' + json.student_name + ' (' + json.student_id + ')<br><strong>Emotion:</strong> ' + json.emotion + ' (' + Math.round(json.confidence * 100) + '%)';\n" ,
      "          }\n" ,
      "        }\n" ,
      "      })\n" ,
      "      .catch(function(err) {\n" ,
      "        if (status) status.innerText = 'Capture failed: ' + err.message;\n" ,
      "      });\n" ,
      "  }, 'image/jpeg', 0.7);\n" ,
      "}\n" ,
      "Shiny.addCustomMessageHandler('startCamera', function(message) { startMonitorCamera(message); });\n" ,
      "Shiny.addCustomMessageHandler('stopCamera', function(message) { stopMonitorCamera(); });\n" ,
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
          tags$label("Username", class = "form-label"),
          textInput("login_username", NULL, placeholder = "Enter username")
      ),
      div(class = "mb-4",
          tags$label("Password", class = "form-label"),
          passwordInput("login_password", NULL, placeholder = "Enter password")
      ),
      actionButton("login_btn", "Sign In", class = "btn btn-primary w-100",
                   style = "padding:0.6rem; font-weight:700; font-size:1rem;"
      ),
      shinyjs::hidden(
        div(id = "login_error", class = "alert alert-warning mt-3 small mb-0",
            "Invalid username or password.")
      ),
      div(style = "text-align:center; margin-top:1rem;",
          actionLink("show_signup", "Don't have an account? Sign Up",
                     style = "color: var(--accent-strong); font-weight:600; font-size:0.9rem; text-decoration:none;")
      ),
      div(class = "alert alert-info mt-3 small mb-0",
          tags$b("Demo credentials:"), br(),
          "admin / admin123", br(),
          "lecturer / lecturer123", br(),
          "student / student123"
      )
    ),
    # Sign-up card
    shinyjs::hidden(
      div(
        id = "signup_card",
        class = "login-card",
        div(class = "login-logo", "Sign Up"),
        div(class = "login-sub",  "Create a new student account"),
        div(class = "mb-3",
            tags$label("Full Name", class = "form-label"),
            textInput("signup_name", NULL, placeholder = "Enter your full name")
        ),
        div(class = "mb-3",
            tags$label("Student ID", class = "form-label"),
            textInput("signup_student_code", NULL, placeholder = "e.g., S121")
        ),
        div(class = "mb-3",
            tags$label("Username", class = "form-label"),
            textInput("signup_username", NULL, placeholder = "Choose a username")
        ),
        div(class = "mb-3",
            tags$label("Email", class = "form-label"),
            textInput("signup_email", NULL, placeholder = "Enter your email")
        ),
        div(class = "mb-3",
            tags$label("Password", class = "form-label"),
            passwordInput("signup_password", NULL, placeholder = "Min. 6 characters")
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
  
  # ── Main app (hidden until login) ──────────────────────────────────────────
  shinyjs::hidden(
    div(
      id = "main_app",
      
      # Navbar
      div(
        class = "ep-navbar",
        div(class = "ep-brand", "EduPulse AI"),
        actionButton("nav_dashboard",  "Dashboard",        class = "ep-nav-link"),
        actionButton("nav_monitor",    "Live Monitor",     class = "ep-nav-link"),
        actionButton("nav_report",     "Report",           class = "ep-nav-link"),
        actionButton("nav_graphs",     "Graphs & Trends",  class = "ep-nav-link"),
        actionButton("nav_confusion",  "Confusion Alerts", class = "ep-nav-link"),
        actionButton("nav_groups",     "Groups",           class = "ep-nav-link"),
        actionButton("nav_attendance", "Attendance",       class = "ep-nav-link"),
        actionButton("nav_settings",   "Settings",         class = "ep-nav-link"),
        div(class = "badge-role ms-1", textOutput("role_badge", inline = TRUE)),
        actionButton("toggle_theme", "☀️ Light",            class = "btn btn-sm btn-outline-primary ms-1"),
        actionButton("logout_btn", "Logout",
                     class = "btn btn-sm btn-outline-primary ms-1",
                     style = "font-size:0.75rem; padding:3px 12px;"
        )
      ),
      
      # Body
      div(
        style = "display:flex;",
        
        # Sidebar
        div(
          class = "sidebar",
          
          div(class = "ep-card-header mt-1", "📅 Select Week"),
          div(
            class = "week-grid",
            lapply(1:16, function(w) {
              tags$button(
                paste("W", w),
                id      = paste0("week_btn_", w),
                class   = "week-btn",
                onclick = sprintf(
                  "Shiny.setInputValue('selected_week_click', %d, {priority: 'event'});", w
                )
              )
            })
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
          class = "main-panel",
          
          # ── Lecturer Dashboard ────────────────────────────────────────────
          shinyjs::hidden(div(
            id = "panel_dashboard",
            h1(class = "section-title", "📊 Lecturer Dashboard"),
            p(class = "section-sub",   "16-Week Academic Semester Overview — select a week then click a lecture to analyse it"),
            
            div(class = "week-info-bar", textOutput("selected_week_display")),
            
            fluidRow(
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
            
            div(class = "ep-card",
                div(class = "ep-card-header", "📋 Weekly Schedule"),
                p(style = "color:#64748b; font-size:0.82rem; margin-bottom:0.75rem;",
                  "Click ▶ View to open a lecture in the Live Monitor."),
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
                        div(id = "face_recognition_status", class = "alert alert-secondary", "Waiting for recognition results..."),
                        uiOutput("live_face_summary")
                    )
                ),
                tags$canvas(id = "monitor_canvas", style = "display:none;")
            ),
            
            fluidRow(
              column(2, div(class = "metric-card",
                            div(class = "metric-icon", "💡"),
                            div(class = "metric-value", textOutput("card_engagement")),
                            div(class = "metric-label", "Avg Engagement")
              )),
              column(2, div(class = "metric-card",
                            div(class = "metric-icon", "🎯"),
                            div(class = "metric-value", textOutput("card_focus")),
                            div(class = "metric-label", "Avg Focus")
              )),
              column(2, div(class = "metric-card",
                            div(class = "metric-icon", "✅"),
                            div(class = "metric-value", textOutput("card_attendance")),
                            div(class = "metric-label", "Attendance")
              )),
              column(2, div(class = "metric-card",
                            div(class = "metric-icon", "❓"),
                            div(class = "metric-value", textOutput("card_confusion")),
                            div(class = "metric-label", "Confusion Rate")
              )),
              column(2, div(class = "metric-card",
                            div(class = "metric-icon", "👥"),
                            div(class = "metric-value", textOutput("card_present")),
                            div(class = "metric-label", "Students Present")
              )),
              column(2, div(class = "metric-card",
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
                            div(class="mb-2", strong("Username:"),    br(), textOutput("info_username")),
                            div(class="mb-2", strong("Role:"),        br(), textOutput("info_role")),
                            div(class="mb-2", strong("User ID:"),     br(), textOutput("info_user_id")),
                            div(class="mb-2", strong("Name:"),        br(), textOutput("info_display_name")),
                            div(class="mb-2", strong("Selected Week:"),    br(), textOutput("info_selected_week")),
                            div(class="mb-2", strong("Selected Lecture:"), br(), textOutput("info_selected_lecture"))
              )),
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
          ))
          
        ) # end main-panel
      ) # end body flex
    ) # end main_app
  ) # end hidden
)

# ── Server ──────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  
  is_logged_in <- reactiveVal(FALSE)
  
  ALL_PANELS <- c("dashboard","monitor","report","graphs","confusion","groups","attendance","settings")
  
  show_panel <- function(name) {
    for (p in ALL_PANELS) shinyjs::hide(paste0("panel_", p))
    shinyjs::show(paste0("panel_", name))
  }
  
  # Nav links
  observeEvent(input$nav_dashboard,  ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("dashboard") })
  observeEvent(input$nav_monitor,    ignoreInit=TRUE, show_panel("monitor"))
  observeEvent(input$nav_report,     ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("report") })
  observeEvent(input$nav_graphs,     ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("graphs") })
  observeEvent(input$nav_confusion,  ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("confusion") })
  observeEvent(input$nav_groups,     ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("groups") })
  observeEvent(input$nav_attendance, ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("attendance") })
  observeEvent(input$nav_settings,   ignoreInit=TRUE, { session$sendCustomMessage("stopCamera", list()); show_panel("settings") })
  
  # ── Week button active styling ────────────────────────────────────────────
  update_week_buttons <- function(selected) {
    for (w in 1:16) {
      id <- paste0("week_btn_", w)
      if (w == selected) {
        shinyjs::runjs(sprintf("var el=document.getElementById('%s'); if(el) el.classList.add('active');", id))
      } else {
        shinyjs::runjs(sprintf("var el=document.getElementById('%s'); if(el) el.classList.remove('active');", id))
      }
    }
  }
  
  # ── WEEK SELECTION — core fix ─────────────────────────────────────────────
  # Each week button fires Shiny.setInputValue('selected_week_click', w)
  # This single observer catches all 16 buttons reliably.
  observeEvent(input$selected_week_click, {
    w <- as.integer(input$selected_week_click)
    if (!is.na(w) && w >= 1 && w <= 16 && !is.null(app_data$user_role)) {
      app_data$selected_week <- w
      update_week_buttons(w)
    }
  })
  
  # ── Login ─────────────────────────────────────────────────────────────────
  observeEvent(input$login_btn, {
    user <- authenticate_user(
      trimws(input$login_username),
      input$login_password
    )
    
    if (!is.null(user)) {
      is_logged_in(TRUE)
      app_data$user_role <- user$role
      app_data$user_id   <- user$user_id
      app_data$user_name <- user$name
      app_data$user_username <- user$username
      app_data$db_user_id <- if (!is.null(user$db_user_id)) user$db_user_id else NULL
      app_data$selected_week <- 1
      app_data$selected_lecture_id <- NULL

      # Update last login timestamp in DB
      if (.try_db_init && !is.null(user$db_user_id)) {
        tryCatch(update_last_login(user$db_user_id), error = function(e) NULL)
      }

      # Load & filter data
      app_data$all_data       <- load_emotion_data()
      app_data$filtered_data  <- filter_by_role(app_data$all_data, user$role, user$user_id)
      raw_schedule            <- load_lecture_schedule()
      app_data$lecture_schedule <- filter_schedule_by_role(raw_schedule, user$role, user$user_id)
      app_data$semester_weeks <- load_semester_weeks()
      
      # Populate selects
      updateSelectInput(session, "filter_group",
                        choices = c("All", get_groups_from_data(app_data$filtered_data)))
      updateSelectInput(session, "filter_course_schedule",
                        choices = c("All", get_courses_from_data(app_data$lecture_schedule)))
      updateSelectInput(session, "filter_group_schedule",
                        choices = c("All", get_groups_from_data(app_data$lecture_schedule)))
      
      # Switch UI
      shinyjs::hide("login_overlay")
      shinyjs::show("main_app")
      shinyjs::hide("login_error")
      
      show_panel("dashboard")
      update_week_buttons(1)
      
      showNotification(paste0("Welcome, ", user$name, "!"), type = "message", duration = 3)
    } else {
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

  # ── Sign-up handler ──────────────────────────────────────────────────────
  observeEvent(input$signup_btn, {
    shinyjs::hide("signup_success")

    # Basic client-side validation
    if (input$signup_password != input$signup_password_confirm) {
      shinyjs::html("signup_error", "Passwords do not match.")
      shinyjs::show("signup_error")
      return()
    }

    if (.try_db_init) {
      result <- tryCatch({
        register_student_pg(
          username     = input$signup_username,
          email        = input$signup_email,
          password     = input$signup_password,
          full_name    = input$signup_name,
          student_code = input$signup_student_code
        )
      }, error = function(e) {
        list(error = paste("Registration failed:", e$message))
      })
    } else {
      result <- list(error = "Database not available. Cannot register.")
    }

    if (!is.null(result$error)) {
      shinyjs::html("signup_error", result$error)
      shinyjs::show("signup_error")
    } else {
      # Success — show message and switch to login
      shinyjs::hide("signup_error")
      shinyjs::show("signup_success")
      updateTextInput(session, "login_username", value = input$signup_username)
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
    session$sendCustomMessage("stopCamera", list())
    is_logged_in(FALSE)
    app_data$user_role           <- NULL
    app_data$user_id             <- NULL
    app_data$user_name           <- NULL
    app_data$filtered_data       <- NULL
    app_data$selected_week       <- 1
    app_data$selected_lecture_id <- NULL
    
    for (p in ALL_PANELS) shinyjs::hide(paste0("panel_", p))
    shinyjs::show("login_overlay")
    shinyjs::hide("main_app")
    updateTextInput(session,     "login_username", value = "")
    updateTextInput(session,     "login_password", value = "")
  })
  
  # ── View lecture from schedule ────────────────────────────────────────────
  observeEvent(input$view_lecture_clicked, {
    req(input$view_lecture_clicked)
    app_data$selected_lecture_id <- input$view_lecture_clicked
    show_panel("monitor")
    showNotification(paste("Viewing:", input$view_lecture_clicked), type="message", duration=2)
  })
  
  # ── Start session from schedule ────────────────────────────────────────────
  observeEvent(input$start_session_clicked, {
    req(input$start_session_clicked)
    lecture_id <- input$start_session_clicked
    app_data$start_session_request <- lecture_id  # Trigger reactive expression
  })
  
  # ── Handle start session API call ─────────────────────────────────────────
  observeEvent(app_data$start_session_request, {
    req(app_data$start_session_request)
    lecture_id <- app_data$start_session_request
    app_data$start_session_request <- NULL  # Reset
    
    # Show loading message
    showNotification("Starting session...", type = "message", duration = 2)
    
    result <- call_api(paste0("/start-session/", lecture_id), method = "POST")
    
    if (!is.null(result)) {
      showNotification(paste("Session started for lecture:", lecture_id), type = "success", duration = 3)
      app_data$selected_lecture_id <- lecture_id
      show_panel("monitor")
      session$sendCustomMessage("startCamera", list(lecture_id = lecture_id))
    } else {
      showNotification("Failed to start session. Check if FastAPI is running.", type = "error", duration = 5)
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
        Actions = paste0(
          '<button class="btn btn-sm btn-success" style="font-size:0.72rem;padding:2px 8px;margin-right:4px;" ',
          'onclick="Shiny.setInputValue(\'start_session_clicked\',\'', lecture_id,
          '\',{priority:\'event\'})">📹 Start Session</button>',
          '<button class="btn btn-sm btn-primary" style="font-size:0.72rem;padding:2px 10px;" ',
          'onclick="Shiny.setInputValue(\'view_lecture_clicked\',\'', lecture_id,
          '\',{priority:\'event\'})">▶ View</button>'
        )
      ) %>%
      select(Actions, Day=day_name, Date=lecture_date, Time=start_time,
             Course=course_code, CourseName=course_name, Group=group_name,
             Room=room, Students=expected_students, Status=status)
    
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
    if (is.null(app_data$filtered_data)) return("—")
    d <- app_data$filtered_data %>% filter(academic_week == app_data$selected_week)
    if (nrow(d)==0) return("—")
    round(mean(d$engagement_score, na.rm=TRUE), 2)
  })
  
  output$card_week_focus <- renderText({
    if (is.null(app_data$filtered_data)) return("—")
    d <- app_data$filtered_data %>% filter(academic_week == app_data$selected_week)
    if (nrow(d)==0) return("—")
    round(mean(d$focus_score, na.rm=TRUE), 2)
  })
  
  output$card_week_confusion <- renderText({
    if (is.null(app_data$filtered_data)) return("0")
    d <- app_data$filtered_data %>% filter(academic_week == app_data$selected_week)
    if (nrow(d)==0) return("0")
    nrow(compute_confusion_spikes(d))
  })
  
  # ── Live Monitor cards ────────────────────────────────────────────────────
  output$card_engagement <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); round(m$avg_engagement,3)
  })
  output$card_focus <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); round(m$avg_focus,3)
  })
  output$card_attendance <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); paste0(round(m$attendance_rate*100,1),"%")
  })
  output$card_confusion <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); paste0(round(m$confusion_rate*100,1),"%")
  })
  output$card_present <- renderText({
    m <- compute_summary_metrics(filtered_data_reactive()); m$students_present
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
    parsed <- tryCatch(fromJSON(input$live_face_response), error = function(e) NULL)
    if (!is.null(parsed)) {
      app_data$live_face_response <- parsed

      # Persist recognized face data to DB + CSV backup
      if (!is.null(parsed$recognized) && parsed$recognized != FALSE) {
        lid <- app_data$selected_lecture_id
        if (!is.null(lid) && nchar(lid) > 0) {
          tryCatch({
            # Write emotion record to DB + CSV
            insert_emotion_record(
              student_code = parsed$student_id,
              lecture_code = lid,
              recorded_at  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              emotion      = parsed$emotion %||% "Neutral",
              confidence   = as.numeric(parsed$confidence %||% 0),
              engagement_score = as.numeric(parsed$engagement_score %||% 0),
              focus_score  = as.numeric(parsed$focus_score %||% 0),
              is_present   = identical(parsed$attendance_status, "Present") || identical(parsed$attendance_status, "Returned"),
              left_room    = identical(parsed$attendance_status, "Left"),
              absence_duration_minutes = as.integer(parsed$absence_duration_minutes %||% 0),
              source       = "live_camera",
              model_name   = "EduPulse_v1.0"
            )

            # Upsert attendance to DB + CSV
            upsert_attendance_record(
              student_code = parsed$student_id,
              lecture_code = lid,
              status       = parsed$attendance_status %||% "Present"
            )

            # Check for confusion alert
            check_and_create_confusion_alert(lid)

            # Also write flat row to main CSV backup
            csv_append_emotion_record(parsed, lid)

            # Update in-memory data so charts refresh immediately
            new_row <- build_emotion_flat_row(parsed, lid)
            if (!is.null(app_data$all_data) && nrow(app_data$all_data) > 0) {
              app_data$all_data <- bind_rows(app_data$all_data, new_row)
              app_data$filtered_data <- filter_by_role(app_data$all_data, app_data$user_role, app_data$user_id)
            }
          }, error = function(e) {
            message(paste("Failed to persist live frame:", e$message))
          })
        }
      }
    }
  })
  
  output$live_face_summary <- renderUI({
    res <- app_data$live_face_response
    if (is.null(res)) {
      HTML('<div style="color:#94a3b8;">No frame analyzed yet.</div>')
    } else if (identical(res$recognized, FALSE)) {
      HTML('<div><strong>Face status:</strong> Not recognized</div>')
    } else {
      HTML(sprintf(
        '<div><strong>Student:</strong> %s (%s)<br/><strong>Emotion:</strong> %s<br/><strong>Confidence:</strong> %s%%<br/><strong>Attendance:</strong> %s</div>',
        res$student_name, res$student_id, res$emotion, round(as.numeric(res$confidence) * 100, 1), res$attendance_status
      ))
    }
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
  output$chart_semester_engagement<-renderPlot({ render_semester_engagement_trend(app_data$filtered_data) },        bg="#0b1220")
  output$chart_semester_confusion <- renderPlot({ render_semester_confusion_trend(app_data$filtered_data) },        bg="#0b1220")
  output$chart_course_comparison  <- renderPlot({ render_course_engagement_comparison(app_data$filtered_data) },    bg="#0b1220")
  
  # ── Emotion heatmap (new) ─────────────────────────────────────────────────
  output$chart_emotion_heatmap <- renderPlot({
    d <- app_data$filtered_data
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
           subtitle="Percentage of emotion records per academic week",
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
  output$table_attendance <- renderDT({
    d <- filtered_data_reactive()
    if (nrow(d)>0) {
      att <- d %>%
        select(student_id,student_name,lecture_id,attendance_status,
               is_present,left_room,absence_duration_minutes,focus_score) %>%
        distinct()
      datatable(att, options=list(pageLength=10,scrollX=TRUE), rownames=FALSE, selection="none")
    } else {
      datatable(data.frame(Message="No data."), options=list(dom="t"), rownames=FALSE)
    }
  })
  
  # ── Settings ──────────────────────────────────────────────────────────────
  output$role_badge       <- renderText({ if(is_logged_in()) app_data$user_role else "" })
  output$info_username    <- renderText({
    if(!is_logged_in()) return("Not logged in")
    app_data$user_username %||% "Unknown"
  })
  output$info_role         <- renderText({ if(is_logged_in()) app_data$user_role  else "Not logged in" })
  output$info_user_id      <- renderText({ if(is_logged_in()) app_data$user_id    else "Not logged in" })
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