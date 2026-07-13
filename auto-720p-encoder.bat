@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

set "CONFIG_FILE=%~dp0config.cfg"
set "LOG_FILE=%~dp0log.txt"

:: 1. AUTO-CREATION OF CONFIG.CFG IF MISSING
if not exist "%CONFIG_FILE%" (
    :: Get script current directory and strip trailing backslash safely
    set "CURRENT_RUN_DIR=%~dp0"
    if "!CURRENT_RUN_DIR:~-1!"=="\" set "CURRENT_RUN_DIR=!CURRENT_RUN_DIR:~0,-1!"

    (
        echo :: ===================================================
        echo :: USER CONFIGURATION FILE
        echo :: ===================================================
        echo.
        echo :: Absolute path for raw source media files
        echo SOURCE=!CURRENT_RUN_DIR!
        echo.
        echo :: Absolute path for processed 720p outputs
        echo DESTINATION=!CURRENT_RUN_DIR!
        echo.
        echo :: Maximum CPU threads allocated to FFmpeg
        echo THREADS=6
        echo.
        echo :: Maximum auto-correction attempts per file
        echo MAX_ATTEMPTS=3
        echo.
        echo :: Allowed duration difference in seconds between input and output files
        echo TOLERANCE=2
    ) > "%CONFIG_FILE%"

    echo ===================================================
    echo  [NOTICE] config.cfg was missing and has been created.
    echo  Default paths point to the script's current folder.
    echo ===================================================
    echo [%time%] NOTICE: config.cfg was automatically generated pointing to execution folder. >> "%LOG_FILE%"
)

:: 2. LOAD CONFIGURATION VIA SAFE LINE-BY-LINE PARSING
for /f "usebackq tokens=1* delims=" %%A in ("%CONFIG_FILE%") do (
    set "LINE=%%A"
    :: Ignore comments starting with ';' or ':' or '#'
    if not "!LINE:~0,1!"==":" if not "!LINE:~0,1!"==";" if not "!LINE:~0,1!"=="#" (
        for /f "tokens=1,2 delims==" %%B in ("%%A") do (
            set "KEY=%%B"
            set "VALUE=%%C"
            :: Remove trailing/leading spaces if any
            for /f "tokens=*" %%D in ("!VALUE!") do set "!KEY!=%%D"
        )
    )
)

:: 3. CONFIGURATION VALIDATION LAYER
set "CONFIG_ERRORS=0"

if "%SOURCE%"=="" (
    echo [VALIDATION ERROR] SOURCE variable cannot be empty in config.cfg.
    set "CONFIG_ERRORS=1"
) else if not exist "%SOURCE%" (
    echo [VALIDATION ERROR] SOURCE directory does not exist: "%SOURCE%"
    set "CONFIG_ERRORS=1"
)

if "%DESTINATION%"=="" (
    echo [VALIDATION ERROR] DESTINATION variable cannot be empty in config.cfg.
    set "CONFIG_ERRORS=1"
) else if not exist "%DESTINATION%" (
    echo [VALIDATION ERROR] DESTINATION directory does not exist: "%DESTINATION%"
    set "CONFIG_ERRORS=1"
)

:: Numeric validation using a Batch arithmetic trick
set /a TEST_THREADS=THREADS 2>nul
if !TEST_THREADS! leq 0 (
    echo [VALIDATION ERROR] THREADS must be a valid number greater than 0. Current: "%THREADS%"
    set "CONFIG_ERRORS=1"
)

set /a TEST_ATTEMPTS=MAX_ATTEMPTS 2>nul
if !TEST_ATTEMPTS! leq 0 (
    echo [VALIDATION ERROR] MAX_ATTEMPTS must be a valid number greater than 0. Current: "%MAX_ATTEMPTS%"
    set "CONFIG_ERRORS=1"
)

set /a TEST_TOLERANCE=TOLERANCE 2>nul
if !TEST_TOLERANCE! lss 0 (
    echo [VALIDATION ERROR] TOLERANCE must be a valid non-negative number of 0 or higher. Current: "%TOLERANCE%"
    set "CONFIG_ERRORS=1"
)

:: If validation failed, log it and halt execution
if "%CONFIG_ERRORS%"=="1" (
    echo =================================================== >> "%LOG_FILE%"
    echo [%time%] CRITICAL: Script execution halted due to config.cfg validation errors. >> "%LOG_FILE%"
    echo =================================================== >> "%LOG_FILE%"
    echo.
    echo Script halted. Please fix the errors in config.cfg above.
    pause
    exit /b
)

:: Variable to monitor if definitive errors occurred during the process
set "HAS_ERROR=0"

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
    echo   Check the files that failed after %MAX_ATTEMPTS% attempts.
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
set "FILE_NAME=%~nx1"
set "FILE_BASE_NAME=%~n1"
set "FILE_EXT=%~x1"
set "CURRENT_DIR=%~dp1"

:: Safely resolves the relative output path using local variables.
set "SUBFOLDER=%CURRENT_DIR%"
set "SUBFOLDER=!SUBFOLDER:%SOURCE%=!"
set "TARGET_DIR=%DESTINATION%%SUBFOLDER%"
if not "!TARGET_DIR:~-1!"=="\" set "TARGET_DIR=!TARGET_DIR!\"
set "FINAL_FILE=!TARGET_DIR!!FILE_BASE_NAME!_720p!FILE_EXT!"

if not exist "!TARGET_DIR!" mkdir "!TARGET_DIR!"

echo !FILE_NAME!

:: 1. SAFE DURATION CAPTURE (Uses "-v quiet" to avoid log clutter and dangerous characters in the console)
set "ORIGINAL_DURATION=0"
for /f "tokens=*" %%a in ('ffprobe -v quiet -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%ABSOLUTE_PATH%"') do (
    set "ORIGINAL_DURATION=%%a"
)

:: If ffprobe fails completely to read the original file
if "%ORIGINAL_DURATION%"=="" set "ORIGINAL_DURATION=0"

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

:: 3. LOOP DE TENTATIVAS
set "ATTEMPT=1"

:CONVERSION_LOOP
echo   -^> Attempt !ATTEMPT! of %MAX_ATTEMPTS%...
echo [!time!]   -^> Starting Attempt !ATTEMPT! via FFmpeg... >> "%LOG_FILE%"

:: Run FFmpeg directly without exposing the line to expansion issues
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

:: If validation fails, deletes the generated corrupted file.
if exist "!FINAL_FILE!" del /f /q "!FINAL_FILE!" >nul 2>&1

if !ATTEMPT! lss %MAX_ATTEMPTS% (
    set /a ATTEMPT+=1
    goto :CONVERSION_LOOP
)

echo   -^> [DEFINITIVE FAILURE] File could not be fixed after %MAX_ATTEMPTS% attempts.
echo [!time!]   -^> CRITICAL: File failed in all %MAX_ATTEMPTS% attempts. >> "%LOG_FILE%"
set "LOCAL_HAS_ERROR=1"

:END_PROCESS_FILE
:: Safely propagates the global error signal out of the local scope.
endlocal & if "%LOCAL_HAS_ERROR%"=="1" (set "HAS_ERROR=1") else (set "HAS_ERROR=%HAS_ERROR%")
exit /b


:VALIDATE_INTEGRITY
set "TARGET=%~1"
set "ORIG_DUR=%~2"
set "IS_INTEGRAL=0"

set "CURRENT_HEIGHT=0"
:: Silently collects height to avoid freezes.
for /f "tokens=*" %%b in ('ffprobe -v quiet -select_streams v:0 -show_entries stream^=height -of default^=noprint_wrappers^=1:nokey^=1 "%TARGET%"') do (
    set "CURRENT_HEIGHT=%%b"
)

set "CURRENT_DURATION=0"
:: Silently collects duration data
for /f "tokens=*" %%c in ('ffprobe -v quiet -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%TARGET%"') do (
    set "CURRENT_DURATION=%%c"
)

if "%CURRENT_HEIGHT%"=="720" (
    :: Extracts the integer part of the seconds.
    for /f "delims=." %%d in ("%ORIG_DUR%") do set "ORIG_DUR_INT=%%d"
    for /f "delims=." %%e in ("%CURRENT_DURATION%") do set "CURRENT_DUR_INT=%%e"
    
    :: If the durations come back empty for any reason, assume it failed.
    if "!ORIG_DUR_INT!"=="" exit /b
    if "!CURRENT_DUR_INT!"=="" exit /b

    :: Calculates the absolute difference between the original and converted seconds.
    set /a DIFF=ORIG_DUR_INT - CURRENT_DUR_INT
    if !DIFF! lss 0 set /a DIFF=-DIFF

    :: Accepts the file as intact if the difference is at most the configured tolerance limit.
    if !DIFF! leq !TOLERANCE! (
        set "IS_INTEGRAL=1"
    ) else (
        echo   -^> [VALIDATION FAILED] Duration mismatch. Original: !ORIG_DUR_INT!s, Processed: !CURRENT_DUR_INT!s - Diff: !DIFF!s, Allowed Tolerance: !TOLERANCE!s
    )
)
exit /b