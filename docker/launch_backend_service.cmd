@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
pushd "%PROJECT_DIR%" >nul || (
    echo Failed to enter project directory: "%PROJECT_DIR%" 1>&2
    exit /b 1
)

if /I "%~1"=="-h" (
    call :usage
    popd >nul
    exit /b 0
)
if /I "%~1"=="--help" (
    call :usage
    popd >nul
    exit /b 0
)

call :setup_env "%~1"
if errorlevel 1 (
    popd >nul
    exit /b 1
)

if /I "%~1"=="__ensure_deepdoc_resources" (
    call :ensure_deepdoc_resources
    set "EXIT_CODE=!ERRORLEVEL!"
    popd >nul
    exit /b !EXIT_CODE!
)
if /I "%~1"=="__run_task_executor" (
    call :run_task_executor "%~2"
    set "EXIT_CODE=!ERRORLEVEL!"
    popd >nul
    exit /b !EXIT_CODE!
)
if /I "%~1"=="__run_ragflow" (
    call :run_server
    set "EXIT_CODE=!ERRORLEVEL!"
    popd >nul
    exit /b !EXIT_CODE!
)
if /I "%~1"=="__run_admin" (
    call :run_admin_server
    set "EXIT_CODE=!ERRORLEVEL!"
    popd >nul
    exit /b !EXIT_CODE!
)
if /I "%~1"=="__run_data_sync" (
    call :run_data_sync
    set "EXIT_CODE=!ERRORLEVEL!"
    popd >nul
    exit /b !EXIT_CODE!
)

set "START_RAGFLOW=0"
set "START_TASK_EXECUTOR=0"
set "START_ADMIN=0"
set "START_DATA_SYNC=0"

if "%~1"=="" (
    set "START_RAGFLOW=1"
    set "START_TASK_EXECUTOR=1"
) else (
    call :parse_args %*
    if errorlevel 1 (
        popd >nul
        exit /b 1
    )
)

if "%START_RAGFLOW%"=="1" (
    call :ensure_deepdoc_resources
    if errorlevel 1 (
        popd >nul
        exit /b 1
    )
) else if "%START_TASK_EXECUTOR%"=="1" (
    call :ensure_deepdoc_resources
    if errorlevel 1 (
        popd >nul
        exit /b 1
    )
)

if "%START_RAGFLOW%"=="1" (
    call :ensure_db_init
    if errorlevel 1 (
        popd >nul
        exit /b 1
    )
    call :run_mysql_migrations
    if errorlevel 1 (
        popd >nul
        exit /b 1
    )
)

if "%START_TASK_EXECUTOR%"=="1" (
    set /a LAST_TASK=%WS%-1
    for /L %%I in (0,1,!LAST_TASK!) do (
        echo Launching task_executor.py for task %%I in a new cmd window.
        start "RAGFlow task_executor %%I" cmd /k ""%~f0" __run_task_executor %%I"
    )
)

if "%START_RAGFLOW%"=="1" (
    echo Launching RAGFlow server in a new cmd window.
    start "RAGFlow server" cmd /k ""%~f0" __run_ragflow"
)

if "%START_ADMIN%"=="1" (
    echo Launching Admin server in a new cmd window.
    start "RAGFlow admin" cmd /k ""%~f0" __run_admin"
)

if "%START_DATA_SYNC%"=="1" (
    echo Launching data sync in a new cmd window.
    start "RAGFlow data_sync" cmd /k ""%~f0" __run_data_sync"
)

echo.
echo Services launched. Use Ctrl+C in each child cmd window to stop them.
popd >nul
exit /b 0

:usage
echo Usage: %~nx0 [ragflow^|task_executor^|admin^|data_sync^|all]...
echo.
echo Without arguments, starts ragflow and task_executor.
echo Available service types:
echo   ragflow         Start RAGFlow server based on API_PROXY_SCHEME
echo   task_executor   Start rag\svr\task_executor.py workers
echo   admin           Start Admin server based on API_PROXY_SCHEME
echo   data_sync       Start rag\svr\sync_data_source.py
echo.
echo Examples:
echo   %~nx0
echo   %~nx0 ragflow
echo   %~nx0 task_executor
echo   %~nx0 admin
echo   %~nx0 data_sync
exit /b 0

:parse_args
if "%~1"=="" exit /b 0
if /I "%~1"=="ragflow" (
    set "START_RAGFLOW=1"
) else if /I "%~1"=="server" (
    set "START_RAGFLOW=1"
) else if /I "%~1"=="webserver" (
    set "START_RAGFLOW=1"
) else if /I "%~1"=="task_executor" (
    set "START_TASK_EXECUTOR=1"
) else if /I "%~1"=="task-executor" (
    set "START_TASK_EXECUTOR=1"
) else if /I "%~1"=="taskexecutor" (
    set "START_TASK_EXECUTOR=1"
) else if /I "%~1"=="admin" (
    set "START_ADMIN=1"
) else if /I "%~1"=="admin_server" (
    set "START_ADMIN=1"
) else if /I "%~1"=="admin-server" (
    set "START_ADMIN=1"
) else if /I "%~1"=="data_sync" (
    set "START_DATA_SYNC=1"
) else if /I "%~1"=="data-sync" (
    set "START_DATA_SYNC=1"
) else if /I "%~1"=="datasync" (
    set "START_DATA_SYNC=1"
) else if /I "%~1"=="all" (
    set "START_RAGFLOW=1"
    set "START_TASK_EXECUTOR=1"
    set "START_ADMIN=1"
    set "START_DATA_SYNC=1"
) else if /I "%~1"=="-h" (
    call :usage
    exit /b 1
) else if /I "%~1"=="--help" (
    call :usage
    exit /b 1
) else (
    echo Unknown service type: %~1 1>&2
    call :usage
    exit /b 1
)
shift
goto :parse_args

:setup_env
call :load_env_file

set "http_proxy="
set "https_proxy="
set "no_proxy="
set "HTTP_PROXY="
set "HTTPS_PROXY="
set "NO_PROXY="

set "PYTHONPATH=%CD%"
set "NLTK_DATA=.\nltk_data"

if exist ".venv\Scripts\python.exe" (
    set "PY=%CD%\.venv\Scripts\python.exe"
    set "PATH=%CD%\.venv\Scripts;%PATH%"
) else (
    set "PY=python"
)

call :prompt_worker_count "%~1"

if not defined WS set "WS=1"
for /F "delims=0123456789" %%W in ("%WS%") do set "WS=1"
if %WS% LSS 1 set "WS=1"

if not defined MAX_RETRIES set "MAX_RETRIES=5"
if /I "%DEVICE%"=="gpu" (
    if defined CUDA_PATH (
        set "PATH=%CUDA_PATH%\bin;%PATH%"
    )
    if not defined RAGFLOW_AUTO_INSTALL_TORCH set "RAGFLOW_AUTO_INSTALL_TORCH=0"
    if not defined OCR_GPU_MEM_LIMIT_MB set "OCR_GPU_MEM_LIMIT_MB=4096"
)
if defined HF_ENDPOINT (
    echo HF_ENDPOINT=%HF_ENDPOINT%
) else (
    echo HF_ENDPOINT is not set; using https://huggingface.co for direct model downloads.
)
echo DEVICE=%DEVICE%
exit /b 0

:prompt_worker_count
if not "%~1"=="" exit /b 0
if defined WS exit /b 0
echo.
choice /C 123456789 /N /T 5 /D 1 /M "Task worker count [1-9] (default 1 in 5s): "
if errorlevel 9 set "WS=9" & exit /b 0
if errorlevel 8 set "WS=8" & exit /b 0
if errorlevel 7 set "WS=7" & exit /b 0
if errorlevel 6 set "WS=6" & exit /b 0
if errorlevel 5 set "WS=5" & exit /b 0
if errorlevel 4 set "WS=4" & exit /b 0
if errorlevel 3 set "WS=3" & exit /b 0
if errorlevel 2 set "WS=2" & exit /b 0
set "WS=1"
exit /b 0

:load_env_file
set "ENV_FILE=%SCRIPT_DIR%.env"
if not exist "%ENV_FILE%" (
    echo Warning: .env file not found at: %ENV_FILE%
    exit /b 0
)

echo Loading environment variables from: %ENV_FILE%
for /F "usebackq tokens=1* delims==" %%A in ("%ENV_FILE%") do (
    set "ENV_KEY=%%~A"
    set "ENV_VALUE=%%~B"
    call :load_env_line
)
exit /b 0

:load_env_line
call :trim_var ENV_KEY
if not defined ENV_KEY exit /b 0
if "!ENV_KEY:~0,1!"=="#" exit /b 0

call :strip_inline_comment ENV_VALUE
call :trim_var ENV_VALUE
call :resolve_default_expr ENV_VALUE
call :expand_known_env_refs ENV_VALUE

set "!ENV_KEY!=!ENV_VALUE!"
exit /b 0

:trim_var
for /F "tokens=* delims= " %%T in ("!%~1!") do set "%~1=%%T"
:trim_var_tail
if defined %~1 if "!%~1:~-1!"==" " (
    set "%~1=!%~1:~0,-1!"
    goto :trim_var_tail
)
exit /b 0

:strip_inline_comment
for /F "tokens=1 delims=#" %%T in ("!%~1!") do set "%~1=%%T"
exit /b 0

:resolve_default_expr
set "TMP_VALUE=!%~1!"
if not "!TMP_VALUE:~0,2!"=="${" exit /b 0
if not "!TMP_VALUE:~-1!"=="}" exit /b 0

set "TMP_VALUE=!TMP_VALUE:~2,-1!"
set "DEFAULT_NAME="
set "DEFAULT_VALUE="
for /F "tokens=1* delims=:" %%A in ("!TMP_VALUE!") do (
    set "DEFAULT_NAME=%%~A"
    set "DEFAULT_VALUE=%%~B"
)
if not defined DEFAULT_VALUE exit /b 0
if not "!DEFAULT_VALUE:~0,1!"=="-" exit /b 0
if "!DEFAULT_VALUE:~0,1!"=="-" set "DEFAULT_VALUE=!DEFAULT_VALUE:~1!"
if defined !DEFAULT_NAME! (
    call set "%~1=%%%DEFAULT_NAME%%%"
) else (
    set "%~1=!DEFAULT_VALUE!"
)
exit /b 0

:expand_known_env_refs
set "TMP_VALUE=!%~1!"
set "TMP_VALUE=!TMP_VALUE:${DOC_ENGINE}=%DOC_ENGINE%!"
set "TMP_VALUE=!TMP_VALUE:${DEVICE}=%DEVICE%!"
set "TMP_VALUE=!TMP_VALUE:${COMPOSE_PROFILES}=%COMPOSE_PROFILES%!"
set "TMP_VALUE=!TMP_VALUE:${OCEANBASE_PASSWORD}=%OCEANBASE_PASSWORD%!"
set "TMP_VALUE=!TMP_VALUE:${OB_MEMORY_LIMIT}=%OB_MEMORY_LIMIT%!"
set "TMP_VALUE=!TMP_VALUE:${OB_SYSTEM_MEMORY}=%OB_SYSTEM_MEMORY%!"
set "TMP_VALUE=!TMP_VALUE:${OB_DATAFILE_SIZE}=%OB_DATAFILE_SIZE%!"
set "TMP_VALUE=!TMP_VALUE:${OB_LOG_DISK_SIZE}=%OB_LOG_DISK_SIZE%!"
set "TMP_VALUE=!TMP_VALUE:${TEI_MODEL}=%TEI_MODEL%!"
set "%~1=!TMP_VALUE!"
exit /b 0

:ensure_db_init
echo Initializing database tables...
"%PY%" -c "from api.db.db_models import init_database_tables as init_web_db; init_web_db()"
if errorlevel 1 exit /b 1
echo Database tables initialized.
exit /b 0

:ensure_deepdoc_resources
echo Checking DeepDoc resources in rag\res\deepdoc...
if not exist "rag\res\deepdoc" mkdir "rag\res\deepdoc"

set "HF_BASE=%HF_ENDPOINT%"
if not defined HF_BASE set "HF_BASE=https://huggingface.co"

call :download_hf_file "InfiniFlow/deepdoc" "det.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "rec.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "layout.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "layout.manual.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "layout.paper.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "layout.laws.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "tsr.onnx"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/deepdoc" "ocr.res"
if errorlevel 1 exit /b 1
call :download_hf_file "InfiniFlow/text_concat_xgb_v1.0" "updown_concat_xgb.model"
if errorlevel 1 exit /b 1

echo DeepDoc resources ok.
if /I "%DEVICE%"=="gpu" (
    call :ensure_gpu_runtime
    if errorlevel 1 exit /b 1
)
exit /b 0

:ensure_gpu_runtime
echo Checking ONNXRuntime CUDA provider...
"%PY%" -c "import os, onnxruntime as ort; cuda_path=os.environ.get('CUDA_PATH'); print('onnxruntime', ort.__version__, ort.get_available_providers()); assert 'CUDAExecutionProvider' in ort.get_available_providers(), 'CUDAExecutionProvider is not available'; ort.preload_dlls(cuda=True, cudnn=True, msvc=True, directory=os.path.join(cuda_path, 'bin') if cuda_path else None) if hasattr(ort, 'preload_dlls') else None; sess=ort.InferenceSession(os.path.join('rag','res','deepdoc','det.onnx'), providers=['CUDAExecutionProvider']); print('CUDA session providers:', sess.get_providers())"
if errorlevel 1 (
    echo GPU runtime check failed. Ensure CUDA_PATH points to a CUDA 12.x toolkit with cuDNN 9 DLLs in %%CUDA_PATH%%\bin. 1>&2
    exit /b 1
)
exit /b 0

:download_hf_file
set "HF_REPO=%~1"
set "HF_FILE=%~2"
set "HF_DEST=rag\res\deepdoc\%HF_FILE%"
set "HF_PART=%HF_DEST%.download"
set "HF_URL=%HF_BASE%/%HF_REPO%/resolve/main/%HF_FILE%"

if exist "%HF_DEST%" (
    echo Found %HF_DEST%
    exit /b 0
)

echo Downloading %HF_REPO%/%HF_FILE%...
curl.exe -L --fail --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 30 --speed-limit 1024 --speed-time 120 -C - -o "%HF_PART%" "%HF_URL%"
if errorlevel 1 (
    echo Failed to download %HF_URL% 1>&2
    echo You can set HF_ENDPOINT to another reachable endpoint and rerun this script. 1>&2
    exit /b 1
)
move /Y "%HF_PART%" "%HF_DEST%" >nul
exit /b 0

:run_mysql_migrations
echo Running model provider table migrations...
"%PY%" tools\scripts\mysql_migration.py ^
    --stages tenant_model_provider,tenant_model_instance,tenant_model,model_id_config ^
    --config conf\service_conf.yaml ^
    --execute ^
    --database-version "v0.26.1" ^
    --mark-database-version-on-success
if errorlevel 1 exit /b 1
echo Model provider table migrations completed.
exit /b 0

:run_task_executor
set "TASK_ID=%~1"
if not defined TASK_ID set "TASK_ID=0"
set "RETRY_COUNT=0"

:task_executor_loop
if %RETRY_COUNT% GEQ %MAX_RETRIES% (
    echo task_executor.py for task %TASK_ID% failed after %MAX_RETRIES% attempts. Exiting... 1>&2
    exit /b 1
)
set /a ATTEMPT=%RETRY_COUNT%+1
echo Starting task_executor.py for task %TASK_ID% ^(Attempt %ATTEMPT%^)
"%PY%" rag\svr\task_executor.py -i "%TASK_ID%"
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
    echo task_executor.py for task %TASK_ID% exited successfully.
    exit /b 0
)
echo task_executor.py for task %TASK_ID% failed with exit code %EXIT_CODE%. Retrying... 1>&2
set /a RETRY_COUNT+=1
timeout /t 2 /nobreak >nul
goto :task_executor_loop

:run_server
if /I "%API_PROXY_SCHEME%"=="go" (
    call :prepare_for_go "bin\ragflow_server.exe" "bin\ragflow_server"
    if errorlevel 1 exit /b 1
    if exist "bin\ragflow_server.exe" (
        call :retry_command ragflow_server "bin\ragflow_server.exe"
    ) else (
        call :retry_command ragflow_server "bin\ragflow_server"
    )
) else (
    call :retry_command ragflow_server.py "%PY%" "api\ragflow_server.py"
)
exit /b %ERRORLEVEL%

:run_admin_server
if /I "%API_PROXY_SCHEME%"=="go" (
    call :prepare_for_go "bin\admin_server.exe" "bin\admin_server"
    if errorlevel 1 exit /b 1
    if exist "bin\admin_server.exe" (
        call :retry_command admin_server "bin\admin_server.exe"
    ) else (
        call :retry_command admin_server "bin\admin_server"
    )
) else (
    call :retry_command admin_server.py "%PY%" "admin\server\admin_server.py"
)
exit /b %ERRORLEVEL%

:run_data_sync
call :retry_command sync_data_source.py "%PY%" "rag\svr\sync_data_source.py"
exit /b %ERRORLEVEL%

:prepare_for_go
if exist "%~1" exit /b 0
if exist "%~2" exit /b 0
echo API_PROXY_SCHEME=go requires a Windows Go binary, but neither "%~1" nor "%~2" exists. 1>&2
echo The Linux resource preparation step from launch_backend_service.sh is not available in cmd. 1>&2
exit /b 1

:retry_command
set "SERVICE_NAME=%~1"
set "CMD_ONE=%~2"
set "CMD_TWO=%~3"
set "RETRY_COUNT=0"

:retry_command_loop
if %RETRY_COUNT% GEQ %MAX_RETRIES% (
    echo %SERVICE_NAME% failed after %MAX_RETRIES% attempts. Exiting... 1>&2
    exit /b 1
)
set /a ATTEMPT=%RETRY_COUNT%+1
echo Starting %SERVICE_NAME% ^(Attempt %ATTEMPT%^)
if "%CMD_TWO%"=="" (
    "%CMD_ONE%"
) else (
    "%CMD_ONE%" "%CMD_TWO%"
)
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" (
    echo %SERVICE_NAME% exited successfully.
    exit /b 0
)
echo %SERVICE_NAME% failed with exit code %EXIT_CODE%. Retrying... 1>&2
set /a RETRY_COUNT+=1
timeout /t 2 /nobreak >nul
goto :retry_command_loop
