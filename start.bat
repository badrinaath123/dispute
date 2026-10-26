@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   D3 - Dispute Intelligence Platform
echo ============================================
echo.

REM ── Check Python ────────────────────────────────────────────────
where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python was not found on PATH.
    echo Install Python 3.11 or newer from https://www.python.org/downloads/
    echo ^(tick "Add python.exe to PATH" during install^), then run this file again.
    echo.
    pause
    exit /b 1
)

REM ── Check Node.js ───────────────────────────────────────────────
where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Node.js was not found on PATH.
    echo Install the LTS version from https://nodejs.org/ then run this file again.
    echo.
    pause
    exit /b 1
)

REM ── .env ────────────────────────────────────────────────────────
if not exist "backend\.env" (
    if exist "backend\.env.example" (
        echo [WARNING] No .env file found - copying .env.example.
        echo AI features need real proxy credentials added to backend\.env to work.
        copy "backend\.env.example" "backend\.env" >nul
        echo.
    )
)

REM ── Python environment ──────────────────────────────────────────
REM Checked via a marker file written only after a successful install, not just
REM the venv folder existing - a venv can exist with a previous run's install
REM half-failed partway through, which would otherwise get silently skipped here
REM and fail confusingly later when the app actually tries to import something
REM that never got installed.
if not exist "backend\.venv\Scripts\python.exe" (
    echo Creating the Python virtual environment...
    python -m venv backend\.venv
)
call "backend\.venv\Scripts\activate.bat"

if not exist "backend\.venv\.deps_installed" (
    echo Installing Python dependencies - first run only, this can take a
    echo few minutes and needs an internet connection. Please wait...
    echo.
    python -m pip install --upgrade pip >nul
    pip install -e backend\
    if errorlevel 1 (
        echo.
        echo [ERROR] Python dependency install failed - see the messages above.
        pause
        exit /b 1
    )
    echo done > "backend\.venv\.deps_installed"
)

REM ── Frontend dependencies ───────────────────────────────────────
if not exist "frontend\node_modules" (
    echo.
    echo Installing frontend dependencies - first run only, this can take a
    echo few minutes. Please wait...
    echo.
    pushd frontend
    call npm install
    if errorlevel 1 (
        echo.
        echo [ERROR] npm install failed - see the messages above.
        popd
        pause
        exit /b 1
    )
    popd
)

REM ── Launch ───────────────────────────────────────────────────────
set KMP_DUPLICATE_LIB_OK=TRUE

echo.
echo Starting the mock external-systems server (port 8100)...
start "D3 - Mock Server (8100)" cmd /k "cd /d "%~dp0backend" && call .venv\Scripts\activate.bat && set KMP_DUPLICATE_LIB_OK=TRUE && python -m uvicorn mock_server.main:app --host 0.0.0.0 --port 8100"

echo Starting the API server (port 8000)...
start "D3 - API Server (8000)" cmd /k "cd /d "%~dp0backend" && call .venv\Scripts\activate.bat && set KMP_DUPLICATE_LIB_OK=TRUE && python -m uvicorn apps.api.main:app --host 0.0.0.0 --port 8000"

echo Starting the web app (port 5173)...
start "D3 - Web App (5173)" cmd /k "cd /d "%~dp0frontend" && npm run dev -- --port 5173"

echo.
echo Waiting for everything to come up...
timeout /t 10 /nobreak >nul

start "" "http://localhost:5173"

echo.
echo ============================================
echo D3 is starting in the three windows that just opened.
echo Keep those windows open - closing one stops that part of the app.
echo If the browser tab looks blank, wait a few seconds and refresh.
echo.
echo Login as:
echo   Issuer analyst   -  analyst / Analyst@123!
echo   Merchant analyst -  merchant_analyst / MerchantAnalyst@123!
echo   Admin            -  admin / Admin@12345!
echo ============================================
echo.
pause
