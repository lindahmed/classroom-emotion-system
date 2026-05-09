# EduPulse AI Startup Guide

This project has two parts:

- Python FastAPI backend for face recognition, emotion detection, and attendance APIs.
- R Shiny dashboard for the classroom analytics UI.

Run them in two separate terminals.

## URLs

- Dashboard: http://127.0.0.1:3838
- Backend health check: http://127.0.0.1:8000/health
- Backend API docs: http://127.0.0.1:8000/docs

The Shiny app expects the backend at `http://localhost:8000`. If you change the backend port, update `API_BASE_URL` in `app.R`.

## Prerequisites

Install these first:

- Python 3.10 or newer
- R 4.0 or newer
- Git

Linux users may also need system build libraries for R packages:

```bash
sudo apt update
sudo apt install -y build-essential libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev
```

Windows users should install:

- R from https://cran.r-project.org/bin/windows/base/
- Rtools from https://cran.r-project.org/bin/windows/Rtools/ if R asks to compile packages from source

## First-Time Setup On Linux

From the project root:

```bash
cd /path/to/classroom-emotion-system

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r backend/requirements.txt
```

Install the R packages:

```bash
Rscript -e 'install.packages(c("shiny", "bslib", "dplyr", "ggplot2", "readr", "tidyr", "lubridate", "DT", "htmltools", "shinyjs", "scales", "httr", "jsonlite"), repos="https://cloud.r-project.org")'
```

## First-Time Setup On Windows

Open PowerShell in the project root:

```powershell
cd C:\path\to\classroom-emotion-system

py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
```

If PowerShell blocks virtual environment activation, run this in the same PowerShell window and retry activation:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Install the R packages:

```powershell
Rscript -e "install.packages(c('shiny', 'bslib', 'dplyr', 'ggplot2', 'readr', 'tidyr', 'lubridate', 'DT', 'htmltools', 'shinyjs', 'scales', 'httr', 'jsonlite'), repos='https://cloud.r-project.org')"
```

## PostgreSQL Database (Optional)

The dashboard can read from PostgreSQL or fall back to CSV files. Set the environment variables below before starting the app:

```text
EDUPULSE_USE_DB=true
EDUPULSE_DB_HOST=localhost
EDUPULSE_DB_PORT=5432
EDUPULSE_DB_NAME=edupulse_ai
EDUPULSE_DB_USER=admin
EDUPULSE_DB_PASSWORD=your_password_here
AUTH_SECRET=replace_with_a_long_random_secret
TOKEN_EXPIRY_MINUTES=60
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_FROM_EMAIL=your_email@gmail.com
SMTP_FROM_NAME=EduPulse AI
SMTP_USE_TLS=true
```

To create the database with the correct owner (example using psql):

```sql
CREATE USER admin WITH PASSWORD 'your_password_here';
CREATE DATABASE edupulse_ai OWNER admin;
```

If you want CSV-only mode, set `EDUPULSE_USE_DB=false`.

## Start On Linux

Terminal 1, backend:

```bash
cd /path/to/classroom-emotion-system/backend
env -u PYTHONPATH DEEPFACE_HOME="$(cd .. && pwd)" ../.venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Terminal 2, dashboard:

```bash
cd /path/to/classroom-emotion-system
Rscript -e 'shiny::runApp(appDir=".", host="127.0.0.1", port=3838, launch.browser=FALSE)'
```

Open http://127.0.0.1:3838 in your browser.

## Start On Windows

Terminal 1, backend:

```powershell
cd C:\path\to\classroom-emotion-system\backend
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
$env:DEEPFACE_HOME = (Resolve-Path ..).Path
..\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Terminal 2, dashboard:

```powershell
cd C:\path\to\classroom-emotion-system
Rscript -e "shiny::runApp(appDir='.', host='127.0.0.1', port=3838, launch.browser=FALSE)"
```

Open http://127.0.0.1:3838 in your browser.

## Verify The Backend

Linux:

```bash
curl http://127.0.0.1:8000/health
```

Windows PowerShell:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

## Account Setup

Use real accounts instead of demo credentials:

1. Open the dashboard login page.
2. Click **Sign Up** and create a user with a valid email + password.
3. Sign in using that email/password.

## Known Face Images

The backend reads known faces from:

```text
backend/known_faces/
```

Folder names should use this format:

```text
S001_StudentName
```

Put `.jpg`, `.jpeg`, or `.png` files inside each student folder.

## Troubleshooting

If port `8000` is already in use, stop the other process or choose another port. If you choose another backend port, update `API_BASE_URL` in `app.R`.

If port `3838` is already in use, change only the dashboard port:

```bash
Rscript -e 'shiny::runApp(appDir=".", host="127.0.0.1", port=3839, launch.browser=FALSE)'
```

DeepFace may download model weights on first use. Keep the internet connection available the first time you call face recognition or emotion analysis.

TensorFlow may print CPU/GPU warnings at startup. These are usually informational. The app can run on CPU.

On Linux, if `opencv-python` fails with `libGL.so.1` missing, install:

```bash
sudo apt install -y libgl1 libglib2.0-0
```

On Linux, if an R package fails with `uv.h: No such file or directory`, install:

```bash
sudo apt install -y libuv1-dev
```
