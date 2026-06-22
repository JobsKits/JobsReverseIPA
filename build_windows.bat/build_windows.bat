@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_ROOT=%%~fI"
cd /d "%PROJECT_ROOT%"

set "APP_NAME=IPA Reverse Analysis Tool"
set "SPEC_FILE=IPAReverseAnalysisTool.spec"
set "VENV_PYTHON=.venv\Scripts\python.exe"
set "APP_DIR=dist\%APP_NAME%"
set "APP_EXE=%APP_DIR%\%APP_NAME%.exe"
set "DOCTOR_EXE=dist\IPA环境体检.exe"

call :show_notice
call :check_environment || goto :error
call :prepare_python_environment || goto :error
call :clean_build_outputs || goto :error
call :build_main_app || goto :error
call :build_doctor || goto :error
call :show_result
pause
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
echo.
echo 构建流程：
echo   1. 在项目根目录创建或复用 .venv。
echo   2. 安装 requirements.txt 中的运行和构建依赖。
echo   3. 经 YES 确认后清理旧 build / dist。
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
echo [INFO] 安装运行和构建依赖...
"%VENV_PYTHON%" -m pip install -r requirements.txt
if errorlevel 1 exit /b 1
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
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
exit /b 0

:build_main_app
echo [INFO] 构建 Windows GUI 主程序...
"%VENV_PYTHON%" -m PyInstaller --noconfirm --clean "%SPEC_FILE%"
if errorlevel 1 exit /b 1
if not exist "%APP_EXE%" (
    echo [ERROR] 未找到主程序：%PROJECT_ROOT%\%APP_EXE%
    exit /b 1
)
exit /b 0

:build_doctor
echo [INFO] 构建 Windows 环境体检工具...
"%VENV_PYTHON%" -m PyInstaller --noconfirm --clean --onefile --console --name "IPA环境体检" --paths "%PROJECT_ROOT%" doctor\doctor_entry.py
if errorlevel 1 exit /b 1
if not exist "%DOCTOR_EXE%" (
    echo [ERROR] 未找到环境体检程序：%PROJECT_ROOT%\%DOCTOR_EXE%
    exit /b 1
)
copy /y "%DOCTOR_EXE%" "%APP_DIR%\IPA环境体检.exe" >nul
exit /b 0

:show_result
echo.
echo ============================================================
echo   Windows 构建完成
echo   主程序：%PROJECT_ROOT%\%APP_EXE%
echo   体检工具：%PROJECT_ROOT%\%APP_DIR%\IPA环境体检.exe
echo ============================================================
echo.
exit /b 0

:error
echo.
echo [ERROR] 构建失败，请检查上方输出。
pause
exit /b 1
