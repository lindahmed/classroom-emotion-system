# Restore a pg_dump custom-format backup (.dump) into an existing PostgreSQL database.
# Prerequisites: PostgreSQL client tools (pg_restore, psql) on PATH or under Program Files.
#
# Usage (PowerShell, from repo root):
#   $env:PGPASSWORD = 'your_password'
#   .\database\restore_edupulse_backup.ps1
#
# Optional parameters:
#   .\database\restore_edupulse_backup.ps1 -DumpPath "C:\path\to\file.dump" -DbName "EduPulse AI"
#
# Note: The restoring role must own the target database (or be superuser). Creating a *new*
# database requires a superuser (often `postgres`); restoring *into* an existing DB only
# needs a user with enough rights (e.g. owner of `EduPulse AI`).

param(
    [string]$DumpPath = (Join-Path $PSScriptRoot "backups\edupulse_backup_20260509_203812.dump"),
    [string]$DbName = "EduPulse AI",
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$DbUser = "admin"
)

$ErrorActionPreference = "Stop"

if (-not $env:PGPASSWORD) {
    Write-Host "Set PGPASSWORD first, e.g.: `$env:PGPASSWORD = 'your_password'" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path -LiteralPath $DumpPath)) {
    Write-Host "Dump file not found: $DumpPath" -ForegroundColor Red
    exit 1
}

$pgRestore = (Get-Command pg_restore -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $pgRestore) {
    $candidates = @(
        "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe",
        "C:\Program Files\PostgreSQL\17\bin\pg_restore.exe",
        "C:\Program Files\PostgreSQL\16\bin\pg_restore.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $pgRestore = $c; break }
    }
}
if (-not $pgRestore -or -not (Test-Path $pgRestore)) {
    Write-Host "pg_restore.exe not found. Install PostgreSQL client tools or add bin to PATH." -ForegroundColor Red
    exit 1
}

Write-Host "Restoring from:" $DumpPath -ForegroundColor Cyan
Write-Host "Target DB    :" $DbName " on " $DbHost ":" $DbPort " as " $DbUser
Write-Host "Using       :" $pgRestore

# Use -d so database names with spaces (e.g. "EduPulse AI") pass correctly.
& $pgRestore `
    "-h" $DbHost "-p" "$DbPort" "-U" $DbUser `
    "-d" $DbName `
    "--no-owner" "--clean" "--if-exists" "--verbose" `
    $DumpPath

$exit = $LASTEXITCODE
if ($exit -ne 0) {
    Write-Host "`npg_restore exited with code $exit. Some backups report warnings or FK ordering issues;" -ForegroundColor Yellow
    Write-Host "check counts with psql (users, students, emotion_records, lectures)." -ForegroundColor Yellow
}
exit $exit
