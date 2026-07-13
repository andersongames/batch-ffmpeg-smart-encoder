@echo off
chcp 65001 > nul
set "ORIGEM=E:\Downloads\Torrent\anime\input"
set "DESTINO=E:\Downloads\Torrent\anime\output"

:: CONTROLE DE PERFORMANCE HÍBRIDO:
set "THREADS=8"

:: MAXIMO DE TENTATIVAS DE AUTO-CORREÇÃO SE O OUTPUT FALHAR
set "MAX_TENTATIVAS=3"

:: Cria uma variável para monitorar se houve erros definitivos no processo
set "TEM_ERRO=0"

echo Processando:
echo ---------------------------------------------------

cd /d "%ORIGEM%"

:: Loop recursivo por subpastas buscando formatos comuns de mídia
for /R %%i in (*.mp4 *.mkv *.avi *.webm *.mov *.flv *.m4v) do (
    if exist "%%i" (
        call :PROCESSAR "%%i"
    )
)

echo.
if "%TEM_ERRO%"=="1" (
    echo ===================================================
    echo   ATENCAO: Ocorreram erros insubstituiveis no processo!
    echo   Verifique os arquivos que falharam apos 3 tentativas.
    echo ===================================================
    pause
    exit /b
) else (
    echo ===================================================
    echo   Processamento concluido com sucesso total!
    echo ===================================================
    pause
    exit /b
)

:PROCESSAR
set "CAMINHO_ABSOLUTO=%~1"
setlocal enabledelayedexpansion

echo %~nx1

set "DIRETORIO_ATUAL=%~dp1"
set "SUBPASTA=!DIRETORIO_ATUAL:%ORIGEM%=!"
set "PASTA_DESTINO=%DESTINO%!SUBPASTA!"
set "ARQUIVO_FINAL=!PASTA_DESTINO!%~n1_720p%~x1"

if not exist "!PASTA_DESTINO!" mkdir "!PASTA_DESTINO!"

:: 1. CAPTURA A DURAÇÃO DO ARQUIVO ORIGINAL (INPUT) VIA FFPROBE
set "DURACAO_ORIGINAL=0"
for /f "tokens=*" %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%CAMINHO_ABSOLUTO%" 2^>nul') do (
    set "DURACAO_ORIGINAL=%%a"
)

:: 2. VALIDAÇÃO PRÉVIA: O arquivo já existe e está íntegro no destino?
if exist "!ARQUIVO_FINAL!" (
    call :VALIDAR_INTEGRIDADE "!ARQUIVO_FINAL!" "%DURACAO_ORIGINAL%"
    if "!INTEGRO!"=="1" (
        echo   -^> [PULADO] Arquivo ja convertido e integro no destino.
        endlocal
        exit /b
    ) else (
        echo   -^> [AVISO] Arquivo existente falhou na validacao previa. Redundancia ativada...
        del /f /q "!ARQUIVO_FINAL!" >nul 2>&1
    )
)

:: 3. LOOP DE TENTATIVAS E AUTO-CORREÇÃO IMEDIATA
set "TENTATIVA=1"

:CONVERTER_LOOP
echo   -^> Tentativa !TENTATIVA! de %MAX_TENTATIVAS%...

:: Correção da captura real do erro: executamos um cmd interno sob o 'start /wait' que repassa o errorlevel real do ffmpeg
start /low /wait "" cmd /c "ffmpeg -i "%CAMINHO_ABSOLUTO%" -threads %THREADS% -map 0 -vf scale=-1:720 -c:v libx264 -crf 23 -c:a aac -c:s copy -strict -2 "!ARQUIVO_FINAL!" -y && exit 0 || exit 1"
set "FFMPEG_EXIT_CODE=%errorlevel%"

:: Verifica se o processo fechou com erro de execução bruto
if !FFMPEG_EXIT_CODE! gtr 0 (
    echo   -^> [ERRO] FFmpeg reportou falha critica na execucao.
    set "INTEGRO=0"
) else (
    :: Pós-Validação imediata se o processo finalizou sem erros aparentes
    call :VALIDAR_INTEGRIDADE "!ARQUIVO_FINAL!" "%DURACAO_ORIGINAL%"
)

:: Se passou na validação, finaliza com sucesso e vai para o próximo arquivo da fila principal
if "!INTEGRO!"=="1" (
    echo   -^> [SUCESSO] Confirmado e validado em 720p.
    endlocal
    exit /b
)

:: Se falhou, apaga o arquivo corrompido para não deixar lixo residual
if exist "!ARQUIVO_FINAL!" del /f /q "!ARQUIVO_FINAL!" >nul 2>&1

:: Lógica do limite de tentativas
if !TENTATIVA! ltr %MAX_TENTATIVAS% (
    set /a TENTATIVA+=1
    goto :CONVERTER_LOOP
)

:: Se estourou as 3 tentativas e continuou quebrando:
echo   -^> [FALHA DEFINITIVA] Arquivo nao pôde ser corrigido apos %MAX_TENTATIVAS% tentativas.
endlocal
set "TEM_ERRO=1"
exit /b


:VALIDAR_INTEGRIDADE
:: Subrotina de validação via FFprobe (Mede Altura e Duração)
set "ALVO=%~1"
set "DUR_ORIG=%~2"
set "INTEGRO=0"

set "ALTURA_ATUAL=0"
for /f "tokens=*" %%b in ('ffprobe -v error -select_streams v:0 -show_entries stream^=height -of default^=noprint_wrappers^=1:nokey^=1 "%ALVO%" 2^>nul') do (
    set "ALTURA_ATUAL=%%b"
)

set "DURACAO_ATUAL=0"
for /f "tokens=*" %%c in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%ALVO%" 2^>nul') do (
    set "DURACAO_ATUAL=%%c"
)

:: Compara se a altura é estritamente 720p e se as durações batem (considerando dízimas do ffmpeg)
if "!ALTURA_ATUAL!"=="720" (
    :: Transforma em inteiro básico para evitar problemas com pontos flutuantes no CMD do Windows
    for /f "delims=." %%d in ("!DUR_ORIG!") do set "DUR_ORIG_INT=%%d"
    for /f "delims=." %%e in ("!DURACAO_ATUAL!") do set "DUR_ATUAL_INT=%%e"
    
    if "!DUR_ORIG_INT!"=="!DUR_ATUAL_INT!" (
        set "INTEGRO=1"
    )
)
exit /b