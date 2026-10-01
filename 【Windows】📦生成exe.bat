@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%JobsReverseIPA") do set "PROJECT_ROOT=%%~fI"
cd /d "%PROJECT_ROOT%"

set "APP_NAME=IPA Reverse Analysis Tool"
set "SPEC_FILE=IPAReverseAnalysisTool.spec"
set "VENV_PYTHON=.venv\Scripts\python.exe"
set "DIST_ROOT=%SCRIPT_DIR%dist"
set "DIST_DIR=%DIST_ROOT%"
set "APP_DIR=%DIST_DIR%\%APP_NAME%"
set "APP_EXE=%APP_DIR%\%APP_NAME%.exe"
set "DOCTOR_EXE=%DIST_DIR%\IPA环境体检.exe"

call :show_notice
call :check_environment || goto :error
call :prepare_python_environment || goto :error
call :clean_build_outputs || goto :error
call :build_main_app || goto :error
call :build_doctor || goto :error
call :show_result
if not exist "%APP_EXE%" goto :error
"%VENV_PYTHON%" scripts\artifact_shortcuts.py --root "%SCRIPT_DIR%." "%APP_EXE%" "%DOCTOR_EXE%" || goto :error
start "" explorer.exe "%DIST_DIR%"
start "" /D "%APP_DIR%" "%APP_EXE%"
exit /b 0

:show_notice
cls
echo.
echo ============================================================
echo       IPA Reverse Analysis Tool - Windows 打包脚本
echo ============================================================
echo.
echo 当前文件：%~f0
echo 项目目录：%PROJECT_ROOT%
echo 用途：从 Python 源码构建 Windows GUI 主程序和环境体检 exe。
echo Output: dist\YYYY.MM.DD HH-mm-ss\ using local build time, shared by all artifacts.
echo.
echo 构建流程：
echo   1. 在内层 JobsReverseIPA 目录创建或复用 .venv。
echo   2. 安装 JobsReverseIPA\requirements.txt 中的运行和构建依赖。
echo   3. 经 YES 确认后清理 JobsReverseIPA\build / dist。
echo   4. 使用统一 spec 构建 Windows GUI 程序目录。
echo   5. 构建 IPA环境体检.exe 并复制到主程序目录。
echo.
echo 输出位置：
echo   %APP_EXE%
echo   %APP_DIR%\IPA环境体检.exe
echo.
echo 按回车继续；按 Ctrl+C 取消。
set /p "__build_start=>>> 按回车开始构建 Windows 版："
echo.
exit /b 0

:check_environment
where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] 未找到 python，请先安装 Python 3 并加入 PATH。
    exit /b 1
)
if not exist "%SPEC_FILE%" (
    echo [ERROR] 缺少打包配置：%PROJECT_ROOT%\%SPEC_FILE%
    exit /b 1
)
if not exist "requirements.txt" (
    echo [ERROR] 缺少依赖文件：%PROJECT_ROOT%\requirements.txt
    exit /b 1
)
if not exist "ipa_reverse_tool\gui_main.py" (
    echo [ERROR] 缺少 GUI 入口：%PROJECT_ROOT%\ipa_reverse_tool\gui_main.py
    exit /b 1
)
exit /b 0

:prepare_python_environment
echo [INFO] 创建或复用虚拟环境：%PROJECT_ROOT%\.venv
python -m venv .venv
if errorlevel 1 exit /b 1
"%VENV_PYTHON%" -c "import PySide6.QtWidgets, PyInstaller, macholib, lief, r2pipe, jinja2, rich" >nul 2>nul
if errorlevel 1 (
  call :confirm_required_install "Missing project dependencies" || exit /b 1
  "%VENV_PYTHON%" -m pip install -r requirements.txt || exit /b 1
  "%VENV_PYTHON%" -c "import PySide6.QtWidgets, PyInstaller, macholib, lief, r2pipe, jinja2, rich" || exit /b 1
)
exit /b 0

:clean_build_outputs
echo.
echo [WARN] 即将删除旧的 build 和 dist 构建目录。
set "__clean_confirm="
set /p "__clean_confirm=必须输入 YES 后回车才会继续："
if /i not "%__clean_confirm%"=="YES" (
    echo [WARN] 未收到 YES，已取消构建。
    exit /b 1
)
"%VENV_PYTHON%" scripts\artifact_shortcuts.py --root "%SCRIPT_DIR%." --clear || exit /b 1
if exist build rmdir /s /q build
fsutil reparsepoint query "%DIST_ROOT%" >nul 2>nul
if not errorlevel 1 goto :error
if exist "%DIST_ROOT%" rmdir /s /q "%DIST_ROOT%"
if exist "%DIST_ROOT%" exit /b 1
set "BUILD_STAMP="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy.MM.dd HH-mm-ss'"') do set "BUILD_STAMP=%%T"
if not defined BUILD_STAMP exit /b 1
set "DIST_DIR=%DIST_ROOT%\%BUILD_STAMP%"
echo Build time (YYYY.MM.DD HH-mm-ss): %BUILD_STAMP%
set "APP_DIR=%DIST_DIR%\%APP_NAME%"
set "APP_EXE=%APP_DIR%\%APP_NAME%.exe"
set "DOCTOR_EXE=%DIST_DIR%\IPA环境体检.exe"
exit /b 0

:build_main_app
echo [INFO] 构建 Windows GUI 主程序...
"%VENV_PYTHON%" -m PyInstaller --noconfirm --clean --distpath "%DIST_DIR%" "%SPEC_FILE%"
if errorlevel 1 exit /b 1
if not exist "%APP_EXE%" (
    echo [ERROR] 未找到主程序：%APP_EXE%
    exit /b 1
)
exit /b 0

:build_doctor
echo [INFO] 构建 Windows 环境体检工具...
"%VENV_PYTHON%" -m PyInstaller --noconfirm --clean --distpath "%DIST_DIR%" --onefile --console --name "IPA环境体检" --paths "%PROJECT_ROOT%" doctor\doctor_entry.py
if errorlevel 1 exit /b 1
if not exist "%DOCTOR_EXE%" (
    echo [ERROR] 未找到环境体检程序：%DOCTOR_EXE%
    exit /b 1
)
copy /y "%DOCTOR_EXE%" "%APP_DIR%\IPA环境体检.exe" >nul
exit /b 0

:show_result
echo.
echo ============================================================
echo   Windows 构建完成
echo   主程序：%APP_EXE%
echo   体检工具：%PROJECT_ROOT%\%APP_DIR%\IPA环境体检.exe
echo ============================================================
echo.
exit /b 0

:error
echo.
echo [ERROR] 构建失败，请检查上方输出。
echo Build clears old dist. On success, reveal output and launch the packaged app.
pause
exit /b 1

:confirm_required_install
rem ReadLine 保留空格，并把 EOF 当成取消。
powershell -NoProfile -Command "[Console]::Write('%~1 (Enter to install; any character to cancel): '); $answer = [Console]::ReadLine(); if ($null -eq $answer -or $answer.Length -gt 0) { exit 1 }; exit 0"
if errorlevel 1 (
  echo Dependency installation cancelled. Stopping current task.
  exit /b 1
)
exit /b 0
