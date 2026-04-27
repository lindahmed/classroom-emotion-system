# EduPulse AI System Architecture & Design

**Version:** 0.2.0 (Semester Dashboard with Lecture Selection Context)

This document describes the enhanced system architecture, data model, and UI structure that implements the comprehensive 16-week semester dashboard with per-lecture analysis.

## Architecture Overview (v0.2.0)

### User Flow

1. **Authentication** → Login with role (Admin/Lecturer/Student)
2. **Lecturer Dashboard** → View 16-week semester calendar
3. **Week Selection** → Click a week to see schedule
4. **Lecture Selection** → Click "View Analysis" to set active lecture context
5. **Analysis Tabs** → All views filter by selected lecture
6. **Export** → Download CSV of selected lecture data

### Data Structure

**Emotion Records** - Linked by `lecture_id` to schedule
- Each record includes student, lecture, course, group, engagement, focus, emotion, confidence
- ~29,000 records for weeks 1-5 (analyzed status)
- Can be extended to all 16 weeks in the future

**Lecture Schedule** - Full 16-week academic calendar
- 512 total lecture slots (16 weeks × 8 lecturer/group combos × 2 lectures/week × 2 parts)
- Currently weeks 1-5 marked as "analyzed" (have emotion data)
- Weeks 6-16 marked as "scheduled" (no data yet)

**Lookup Tables** - Reference data
- Semester weeks with start/end dates
- Courses and groups
- Lecturers and course assignments

### Role-Based Access

| User Role | Dashboard | Schedule View | Data Access | Selected Lecture? |
|---|---|---|---|---|
| Admin | All weeks/lectures | All data | All lectures | Can set any |
| Lecturer T01 | Only T01 weeks | Only T01 schedule | T01 lectures only | Only their own |
| Student S001 | Limited | Cannot access | Personal records only | Personal only |

---

## UI Design System - Stitch Matched

This package maintains the premium UI that matches the uploaded Stitch reference screens in both modes:

- `stitch_ai_classroom_sentiment_analytics/live_monitor/screen.png`
- `stitch_ai_classroom_sentiment_analytics/live_monitor_dark/screen.png`
- `stitch_ai_classroom_sentiment_analytics/lecture_insights/screen.png`
- `stitch_ai_classroom_sentiment_analytics/lecture_insights_dark/screen.png`
- `stitch_ai_classroom_sentiment_analytics/cohorts_comparisons_dark/screen.png`
- `education_analytics_system/DESIGN.md`
- `obsidian/DESIGN.md`

## North Star

A data-dense classroom analytics command center with two exact visual modes:

1. **Light Mode - Precision Analytics**
   - White fixed left sidebar
   - Cool gray page canvas
   - Teal active navigation and live states
   - Deep academic navy session cards
   - Compact cards with crisp borders

2. **Dark Mode - Obsidian**
   - Near-black fixed left sidebar and workspace
   - Zinc surfaces and border-based separation
   - Violet active navigation and live states
   - Violet gradient active-session cards
   - High-contrast, developer-grade dashboard density

## Theme Toggle

`ui_helpers.R` now includes:

```r
ui_theme_assets(default = "dark", auto_toggle = TRUE)
ui_theme_toggle(label = "Mode")
ui_set_theme("dark")
ui_set_theme("light")
```

`ui_theme_assets()` sets `data-theme="dark"` or `data-theme="light"` on the document, stores the choice in `localStorage`, and auto-mounts a toggle button in the topbar if the app does not render one manually.

## Layout

### Sidebar

- Width: `274px`
- Fixed left positioning
- Full viewport height
- Border-right separation
- Brand block at top
- Nav items match Stitch spacing: icon + text, 44-48px row height
- Active item behavior:
  - Light: slate active fill with teal left rail
  - Dark: zinc active fill with violet right rail

### Top Bar

- Height: `64px`
- Sticky/fixed visual treatment
- Glass-like light mode: `rgba(248,250,252,.86)` with blur
- Obsidian dark mode: `#09090b`
- Bottom border only, no heavy shadows
- Session text uses underlined teal/violet accent
- Live pill uses tinted accent background and pulse dot

### Content Canvas

- Light background: `#f7f9fb`
- Dark background: `#09090b`
- Main content is offset by sidebar width
- Page padding: `26px 28px`
- 24px grid gutters for cards and dashboard modules

## Colors

### Light Mode

| Token | Value | Usage |
|---|---:|---|
| Background | `#f7f9fb` | App canvas |
| Surface | `#ffffff` | Cards, panels, sidebar |
| Surface Hover | `#f1f5f9` | Nav and row hover |
| Text | `#191c1e` | Primary text |
| Muted Text | `#45464d` | Labels and metadata |
| Border | `#e2e8f0` | Cards, tables, topbar |
| Primary | `#006a61` | Active nav, engagement, links |
| Warning | `#b87500` | Confusion / warning states |
| Danger | `#ba1a1a` | Disinterest / critical states |

### Dark Mode

| Token | Value | Usage |
|---|---:|---|
| Background | `#09090b` | App canvas, sidebar, topbar |
| Surface | `#18181b` | Cards and panels |
| Surface Hover | `#27272a` | Hover / raised surfaces |
| Text | `#fafafa` | Primary text |
| Muted Text | `#a1a1aa` | Labels and metadata |
| Border | `#27272a` | Structural separation |
| Primary | `#a78bfa` | Active nav, engagement, links |
| Warning | `#fbbf24` | Confusion states |
| Danger | `#ff4d6d` | Disinterest / critical states |

## Typography

- Light mode prioritizes **Inter**, matching the `education_analytics_system` reference.
- Dark mode prioritizes **Geist**, matching the `obsidian` reference.
- Sidebar labels in light mode use uppercase tracking like the screenshots.
- Dark sidebar labels use regular title case and tighter spacing.
- Dashboard headings use heavy weight and negative tracking.

## Components

### Cards

- Light: pure white, 1px slate border, subtle shadow only on hover.
- Dark: zinc surface, 1px zinc border, no heavy shadow.
- Radius: `8px`.
- Headers use a subtle top container with bottom border.

### Narrative Insights

- Left accent rail matches mode accent.
- Icon tile uses tinted accent background.
- Badge uses compact tinted pill styling.

### Active Session

- Light: deep navy command-card block.
- Dark: violet gradient card matching the Stitch dark screenshot.
- Includes live engagement indicator with pulse dot.

### Charts

- Server-side `theme_edupulse()` supports both modes.
- Engagement line/fill uses teal in light and violet in dark.
- Gridlines and chart backgrounds match the active UI surface.
- Emotion donut colors are mode-aware.

### Tables

- Compact DataTables styling.
- Uppercase table headers.
- Low-contrast row separators.
- Active pagination uses primary accent.

## Helper Functions

| Function | Purpose |
|---|---|
| `ui_theme_assets(default, auto_toggle)` | Loads fonts/CSS, applies theme, mounts toggle |
| `ui_theme_toggle(label)` | Manual dark/light toggle button |
| `ui_set_theme(mode)` | Sets server-side chart palette |
| `ui_stitch_sidebar(active, brand, subtitle, version)` | Optional sidebar matching screenshots |
| `ui_stitch_topbar(title, session, live, user, show_toggle)` | Optional topbar matching screenshots |
| `ui_metric_card(title, value, icon, color)` | KPI card with Material icon |
| `render_stability_timeline(data, mode)` | Mode-aware engagement/confusion chart |
| `render_engagement_timeline(data, mode)` | Backward-compatible alias |
| `render_emotion_distribution(data, mode)` | Mode-aware donut chart |
| `ui_confusion_spikes(spike_df)` | Styled confusion spike list |
| `ui_key_takeaways(items)` | Styled takeaway list |
| `ui_narrative_box(headline, body, badge)` | Narrative Insights card |
| `ui_active_session_card(session_name, status)` | Active session card |
| `ui_cluster_badge(cluster_num)` | Cohort cluster pill |

## Implementation Notes

- `custom.css` deliberately targets common Shiny, Bootstrap, shinydashboard, bslib, DataTables, and project-specific classes so the uploaded app can change visually without requiring a full page rewrite.
- The toggle uses the `data-theme` attribute and `html.dark/html.light` classes, so it works with both custom CSS and Tailwind-like Stitch conventions.
- Default mode is dark to preserve the previous Obsidian direction. The user can immediately switch to light from the toggle.
