# AMS database backup helper (operators).
# Requires: Supabase CLI linked to the project, or PostgreSQL client tools + DATABASE_URL.
# Usage (from repo root):
#   .\scripts\backup-ams.ps1
# Env:
#   SUPABASE_DB_URL — optional; if set, uses pg_dump instead of supabase db dump.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $root "backups"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$outFile = Join-Path $outDir "ams-db-$stamp.sql"

if ($env:SUPABASE_DB_URL) {
  $pgDump = Get-Command pg_dump -ErrorAction SilentlyContinue
  if (-not $pgDump) {
    Write-Error "SUPABASE_DB_URL is set but pg_dump was not found on PATH. Install PostgreSQL client tools or use Supabase CLI path below."
  }
  & pg_dump --dbname=$env:SUPABASE_DB_URL --no-owner --no-acl -f $outFile
  Write-Host "Wrote $outFile"
  exit 0
}

$supabase = Get-Command supabase -ErrorAction SilentlyContinue
if ($supabase) {
  & supabase db dump -f $outFile
  Write-Host "Wrote $outFile (via supabase db dump)"
  exit 0
}

Write-Host @"
No backup method available:
  1) Install Supabase CLI and run from a linked project: supabase link
  2) Or set SUPABASE_DB_URL and install pg_dump (PostgreSQL bin on PATH)

Dashboard backups: Project Settings -> Database -> Backups (hosted Supabase).
"@
