@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul
set "SOURCE=E:\Downloads\Torrent\anime\input"
set "DESTINATION=E:\Downloads\Torrent\anime\output"

:: HYBRID PERFORMANCE CONTROL:
set "THREADS=6"

:: MAXIMUM AUTO-CORRECTION ATTEMPTS IF THE OUTPUT FAILS
set "MAX_ATTEMPTS=3"

:: Variable to monitor if definitive errors occurred during the process
set "HAS_ERROR=0"

:: Defines the log file path in the same directory as the .bat file
set "LOG_FILE=%~dp0log.txt"

echo =================================================== >> "%LOG_FILE%"
echo SESSION STARTED ON: %date% AT !time! >> "%LOG_FILE%"
echo =================================================== >> "%LOG_FILE%"

echo Processing:
echo ---------------------------------------------------

cd /d "%SOURCE%"

:: Recursive loop through subfolders looking for common media formats
for /R %%i in (*.mp4 *.mkv *.avi *.webm *.mov *.flv *.m4v) do (
    if exist "%%i" (
        echo [!time!] PROCESSING: %%~nxi >> "%LOG_FILE%"
        call :PROCESS_FILE "%%i"
        echo [!time!] CONTEXT FINISHED: %%~nxi >> "%LOG_FILE%"
    )
)

echo.
if "%HAS_ERROR%"=="1" (
    echo [!time!] SESSION FINISHED WITH DEFINITIVE ERRORS >> "%LOG_FILE%"
    echo ===================================================
    echo   ATTENTION: Unrecoverable errors occurred during the process!
    echo   Check the files that failed after 3 attempts.
    echo   See log.txt for details.
    echo ===================================================
    pause
    exit /b
) else (
    echo [!time!] SESSION FINISHED WITH TOTAL SUCCESS >> "%LOG_FILE%"
    echo ===================================================
    echo   Processing completed with total success!
    echo ===================================================
    pause
    exit /b
)

:PROCESS_FILE
setlocal
set "ABSOLUTE_PATH=%~1"

echo %~nx1

set "CURRENT_DIR=%~dp1"

:: Robust normalization of paths and subfolders
set "SUBFOLDER=!CURRENT_DIR:%SOURCE%=!"
set "TARGET_DIR=%DESTINATION%!SUBFOLDER!"

:: Ensures it ends with a backslash properly
if not "!TARGET_DIR:~-1!"=="\" set "TARGET_DIR=!TARGET_DIR!\"

set "FINAL_FILE=!TARGET_DIR!%~n1_720p%~x1"

if not exist "!TARGET_DIR!" mkdir "!TARGET_DIR!"

:: 1. CAPTURE THE ORIGINAL FILE DURATION (INPUT) VIA FFPROBE
set "ORIGINAL_DURATION=0"
for /f "tokens=*" %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%ABSOLUTE_PATH%" 2^>nul') do (
    set "ORIGINAL_DURATION=%%a"
)

:: 2. PRE-VALIDATION
if exist "!FINAL_FILE!" (
    call :VALIDATE_INTEGRITY "!FINAL_FILE!" "%ORIGINAL_DURATION%"
    if "!IS_INTEGRAL!"=="1" (
        echo   -^> [SKIPPED] File already converted and healthy at destination.
        echo [!time!]   -^> SKIPPED: Healthy file detected at destination. >> "%LOG_FILE%"
        goto :END_PROCESS_FILE
    ) else (
        echo   -^> [WARNING] Existing file failed pre-validation. Redundancy activated...
        echo [!time!]   -^> WARNING: Corrupted or incomplete file detected at destination. Deleting... >> "%LOG_FILE%"
        del /f /q "!FINAL_FILE!" >nul 2>&1
    )
)

:: 3. ATTEMPTS LOOP AND IMMEDIATE AUTO-CORRECTION
set "ATTEMPT=1"

:CONVERSION_LOOP
echo   -^> Attempt %ATTEMPT% of %MAX_ATTEMPTS%...
echo [!time!]   -^> Starting Attempt %ATTEMPT% via FFmpeg... >> "%LOG_FILE%"

:: Direct and Safe Execution (without unstable 'start')
ffmpeg -i "%ABSOLUTE_PATH%" -threads %THREADS% -map 0 -vf scale=-1:720 -c:v libx264 -crf 23 -c:a aac -c:s copy -strict -2 "!FINAL_FILE!" -y
set "FFMPEG_EXIT_CODE=%errorlevel%"

if %FFMPEG_EXIT_CODE% gtr 0 (
    echo   -^> [ERROR] FFmpeg reported a critical failure during execution. Code: %FFMPEG_EXIT_CODE%
    echo [!time!]   -^> ERROR: FFmpeg failed with code: %FFMPEG_EXIT_CODE% >> "%LOG_FILE%"
    set "IS_INTEGRAL=0"
) else (
    call :VALIDATE_INTEGRITY "!FINAL_FILE!" "%ORIGINAL_DURATION%"
)

if "!IS_INTEGRAL!"=="1" (
    echo   -^> [SUCCESS] Confirmed and validated at 720p.
    echo [!time!]   -^> SUCCESS: File validated at 720p with correct duration. >> "%LOG_FILE%"
    goto :END_PROCESS_FILE
)

:: If it failed, clean up the residual file
if exist "!FINAL_FILE!" del /f /q "!FINAL_FILE!" >nul 2>&1

if %ATTEMPT% ltr %MAX_ATTEMPTS% (
    set /a ATTEMPT+=1
    goto :CONVERSION_LOOP
)

echo   -^> [DEFINITIVE FAILURE] File could not be fixed after %MAX_ATTEMPTS% attempts.
echo [!time!]   -^> CRITICAL: File failed in all %MAX_ATTEMPTS% attempts. >> "%LOG_FILE%"
set "HAS_ERROR=1"

:END_PROCESS_FILE
endlocal & set "HAS_ERROR=%HAS_ERROR%"
exit /b


:VALIDATE_INTEGRITY
set "TARGET=%~1"
set "ORIG_DUR=%~2"
set "IS_INTEGRAL=0"

set "CURRENT_HEIGHT=0"
for /f "tokens=*" %%b in ('ffprobe -v error -select_streams v:0 -show_entries stream^=height -of default^=noprint_wrappers^=1:nokey^=1 "%TARGET%" 2^>nul') do (
    set "CURRENT_HEIGHT=%%b"
)

set "CURRENT_DURATION=0"
for /f "tokens=*" %%c in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%TARGET%" 2^>nul') do (
    set "CURRENT_DURATION=%%c"
)

if "%CURRENT_HEIGHT%"=="720" (
    for /f "delims=." %%d in ("%ORIG_DUR%") do set "ORIG_DUR_INT=%%d"
    for /f "delims=." %%e in ("%CURRENT_DURATION%") do set "CURRENT_DUR_INT=%%e"
    
    if "!ORIG_DUR_INT!"=="!CURRENT_DUR_INT!" (
        set "IS_INTEGRAL=1"
        exit /b
    )
)
exit /b