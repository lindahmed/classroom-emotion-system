# EduPulse AI - Quick Start Guide (Post-Fixes)

## 🚀 Quick Start

### Prerequisites
- R (version 4.0+)
- Python 3.8+
- PostgreSQL (optional, CSV fallback available)

### 1. Backend Setup (FastAPI)

```bash
cd backend

# Install Python dependencies
pip install -r requirements.txt --break-system-packages

# Start the backend API
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Backend will be available at: `http://localhost:8000`
- API docs: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/health`

### 2. Frontend Setup (R Shiny)

```bash
# Install R dependencies (one-time setup)
R -e "install.packages(c('shiny', 'bslib', 'dplyr', 'ggplot2', 'readr', 'tidyr', 'lubridate', 'DT', 'htmltools', 'scales', 'shinyjs', 'httr', 'jsonlite', 'openssl', 'promises', 'future'))"

# Start the Shiny app
R -e "shiny::runApp('app.R', port=3909, host='0.0.0.0')"
```

Frontend will be available at: `http://localhost:3909`

### 3. Access the Application

Open your browser and navigate to:
```
http://localhost:3909
```

---

## ✅ Verification Steps

### 1. Check Navbar
- [ ] All navigation items visible (Dashboard, Live Monitor, Analytics, Reports, Alerts, Groups, Attendance, Settings)
- [ ] Role badge displays correctly (Lecturer/Student/Admin)
- [ ] Theme toggle button works (☀️ Light / 🌙 Dark)
- [ ] Logout button visible and functional

### 2. Check Student Emotion Report
1. Navigate to **Reports** section
2. Select any lecture from the schedule
3. Verify these metrics display correctly (no errors):
   - ✅ Total Students (number)
   - ✅ Present (number, not error)
   - ✅ Absent (number)
   - ✅ Avg Engagement (decimal like 0.750)
   - ✅ Avg Focus (decimal like 0.650)
   - ✅ Dominant Emotion (text like "Happy")

### 3. Check API Connection
1. Navigate to **Live Monitor** section
2. Start a session for any lecture
3. Upload or capture a frame
4. Check browser console (F12):
   - ✅ No CORS errors
   - ✅ `/analyze-attendance-frame` returns 200 OK
   - ✅ Face recognition working

---

## 🔧 Configuration

### Environment Variables (Optional)

Create a `.env` file in the root directory:

```bash
# Database (PostgreSQL)
DATABASE_URL=postgresql://user:password@localhost:5432/edupulse

# CORS Origins (production)
EDUPULSE_CORS_ORIGINS=https://yourdomain.com,https://app.yourdomain.com

# API Base URL
EDUPULSE_API_BASE_URL=http://localhost:8000

# Logging
EDUPULSE_LOG_LEVEL=INFO
```

For development, defaults work fine (no .env needed).

---

## 🐛 Troubleshooting

### Navbar Cut Off
**Problem**: Navigation items are cut off or not visible  
**Solution**: 
- Clear browser cache (Ctrl+Shift+Delete)
- Hard refresh (Ctrl+F5)
- Check CSS loaded: `/www/custom.css`

### "Error: non-numeric argument to mathematical function"
**Problem**: Errors in PRESENT, AVG, or AVG FOCUS metrics  
**Solution**: 
- ✅ Already fixed in `/R/analytics_helpers.R`
- Ensure you're using the updated code
- Restart R session

### CORS 400 Bad Request
**Problem**: OPTIONS requests fail to `/analyze-attendance-frame`  
**Solution**: 
- ✅ Already fixed in `/backend/main.py`
- Restart backend server
- Check CORS origins in console

### Backend Won't Start
**Problem**: FastAPI errors on startup  
**Solution**:
```bash
# Check Python dependencies
pip install -r backend/requirements.txt --break-system-packages

# Check port availability
lsof -i :8000

# Try different port
uvicorn backend.main:app --reload --port 8001
```

### Frontend Won't Start
**Problem**: R Shiny errors on startup  
**Solution**:
```r
# Check R packages
pkgs <- c('shiny', 'bslib', 'dplyr', 'ggplot2', 'readr', 'tidyr', 
          'lubridate', 'DT', 'htmltools', 'scales', 'shinyjs', 
          'httr', 'jsonlite', 'openssl', 'promises', 'future')
install.packages(pkgs)

# Check database connection
# Set SKIP_DB_INIT=true to use CSV fallback
Sys.setenv(SKIP_DB_INIT = "true")
```

---

## 📊 Test Data

### Sample Lectures
The application includes sample data for testing:
- Week 13: Multiple lectures available
- Courses: CS101, MATH202, PHY301
- Groups: Group A, Group B, Group C

### Sample Students
- Student S001: Linda
- Student S002: Rawan
- Additional students in database

---

## 🎯 Common Workflows

### 1. View Semester Analytics
1. **Dashboard** → Select week (W1-W16)
2. Filter by course/group
3. View engagement and emotion trends

### 2. Monitor Live Lecture
1. **Live Monitor** → Start Session
2. Select lecture from schedule
3. Capture frames via camera
4. View real-time attendance and emotions

### 3. Generate Reports
1. **Reports** → Select lecture
2. View per-student emotion analysis
3. Export to CSV
4. Review dominant emotions and engagement

### 4. Check Alerts
1. **Alerts** → View confusion spikes
2. Filter by time threshold
3. Identify moments of high confusion

---

## 🔒 Security Notes

### Default Credentials
- **Admin**: Check database for initial setup
- Change default passwords immediately

### CORS Configuration
- Development: Allows localhost on any port
- Production: Set `EDUPULSE_CORS_ORIGINS` explicitly
- Never use `allow_origins=["*"]` in production

### API Authentication
- JWT tokens expire after configured time
- Tokens stored securely in database
- Logout revokes tokens immediately

---

## 📝 Logging

### Backend Logs
```bash
# View logs in console where uvicorn is running
# Or set log file:
uvicorn main:app --log-config logging.conf
```

### Frontend Logs
```r
# R console shows Shiny logs
# Check for errors in:
# - Database connections
# - API calls
# - Data processing
```

---

## 🆘 Need Help?

1. **Check Logs**: Backend console and R console
2. **Browser Console**: F12 → Console tab for JS errors
3. **Network Tab**: F12 → Network tab for API failures
4. **Documentation**: See `FIXES_APPLIED.md` for detailed fixes

---

## 📦 Project Structure

```
edupulse/
├── app.R                    # Main Shiny application
├── backend/
│   ├── main.py             # FastAPI backend (CORS fixed)
│   ├── requirements.txt    # Python dependencies
│   ├── auth.py             # Authentication
│   └── ...
├── R/
│   ├── analytics_helpers.R # Calculations (errors fixed)
│   ├── db_queries.R        # Database queries
│   └── ...
├── www/
│   └── custom.css          # Styles (navbar fixed)
├── data/                   # Sample data
├── database/               # DB migration scripts
├── FIXES_APPLIED.md        # Detailed fix documentation
└── QUICK_START.md          # This file
```

---

## ✨ What's New (Post-Fixes)

✅ **Navbar fully visible** - No more cut-off navigation items  
✅ **Report metrics working** - PRESENT, AVG, AVG FOCUS all fixed  
✅ **CORS issues resolved** - API calls work seamlessly  
✅ **Better error handling** - Graceful fallbacks for edge cases  
✅ **Improved styling** - Consistent icon and badge sizing  

---

**Version**: 1.0 (Fixed)  
**Last Updated**: May 10, 2026  
**Status**: ✅ Production Ready
