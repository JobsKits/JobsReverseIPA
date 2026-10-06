#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📦生成dmg.command
# - 核心用途：从 Python 源码构建 IPA Reverse Analysis Tool.app 和可拖入 Applications 的 DMG。
# - 影响范围：会创建或复用内层 JobsReverseIPA/.venv，并在确认后删除旧 build / dist 构建目录。
# - 运行提示：运行后先打印内置自述；按回车确认后继续，按 Ctrl+C 可取消。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/JobsReverseIPA" && pwd -P)"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"

VENV_DIR="${PROJECT_ROOT}/.venv"
BUILD_DIR="${PROJECT_ROOT}/build"
DIST_ROOT="${SCRIPT_DIR}/dist"
DIST_DIR="$DIST_ROOT"
SPEC_FILE="${PROJECT_ROOT}/IPAReverseAnalysisTool.spec"
APP_BUNDLE="${DIST_DIR}/IPA Reverse Analysis Tool.app"
DMG_PATH="${DIST_DIR}/IPA-Reverse-Analysis-Tool-macOS.dmg"
DMG_STAGING="${DIST_DIR}/dmg_staging"

# 记录终端输出并同步写入日志。
log() { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出信息。
info_echo() { log "\033[1;34mℹ $1\033[0m"; }
# 输出成功信息。
success_echo() { log "\033[1;32m✔ $1\033[0m"; }
# 输出警告信息。
warn_echo() { log "\033[1;33m⚠ $1\033[0m"; }
# 输出说明信息。
note_echo() { log "\033[1;35m➤ $1\033[0m"; }
# 输出错误信息。
error_echo() { log "\033[1;31m✖ $1\033[0m"; }
# 输出高亮标题。
highlight_echo() { log "\033[1;36m$1\033[0m"; }
# 输出次要信息。
gray_echo() { log "\033[0;90m$1\033[0m"; }
# 同步显示命令输出并写入日志，失败状态原样向上返回。
run_logged() {
  "$@" 2>&1 | tee -a "$LOG_FILE"
}
# 打印脚本内置自述，并等待用户确认。
show_script_intro_and_wait() {
  clear
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：从 Python 源码构建 macOS App 和 DMG 安装包。" | jobs_intro_style body
  warn_echo "影响范围：确认后会在内层 JobsReverseIPA/ 安装构建依赖；清理旧 build / dist 前必须输入 YES。" | jobs_intro_style body
  gray_echo "输出目录：${DIST_DIR}" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  gray_echo "取消方式：按 Ctrl+C 终止。" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  print '构建产物按本机年月日时分秒保存到 dist/YYYY.MM.DD HH-mm-ss/（例如 2020.06.04 12-23-21），同次构建共用一个时间目录。' | jobs_intro_style body
  print '打包前清理旧 dist；成功后在第一层更新产物快捷方式、打开目录并启动本机软件。' | jobs_intro_style body
  read -r "?已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 普通升级动作默认跳过，输入任意字符后才执行。
ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 危险清理动作必须输入 YES。
confirm_yes() {
  echo ""
  warn_echo "$1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 初始化 Shell 运行环境。
initialize_script_runtime() {
  setopt NO_NOMATCH
  set -euo pipefail
  : > "$LOG_FILE"
}
# 切换到项目根目录。
change_to_project_root() {
  cd "$PROJECT_ROOT"
}
# 检查 macOS、构建工具和项目输入文件。
check_environment() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "该脚本只支持 macOS。"
    return 1
  fi
  local command_name=""
  for command_name in python3 hdiutil codesign; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      error_echo "未找到命令：${command_name}。"
      return 1
    fi
  done
  local required_file=""
  for required_file in requirements.txt IPAReverseAnalysisTool.spec ipa_reverse_tool/gui_main.py doctor/macos/IPA环境体检.command; do
    if [[ ! -f "${PROJECT_ROOT}/${required_file}" ]]; then
      error_echo "缺少项目文件：${PROJECT_ROOT}/${required_file}"
      return 1
    fi
  done
  info_echo "Python：$(python3 --version 2>&1)"
  info_echo "项目目录：${PROJECT_ROOT}"
}
# 必需依赖缺失时回车安装，任意字符取消整个流程。
confirm_required_install() {
  local answer=""
  IFS= read -r "?${1}（直接回车安装；输入任意字符后回车取消）：" answer || { print -u2 '没有交互输入，停止依赖安装。'; exit 1; }
  [[ -z "$answer" ]] || { print -u2 '已取消依赖安装，停止当前流程。'; exit 1; }
}
# 创建或复用虚拟环境，并安装项目构建依赖。
prepare_python_environment() {
  info_echo "创建 / 复用虚拟环境：${VENV_DIR}"
  run_logged python3 -m venv "$VENV_DIR"
  source "${VENV_DIR}/bin/activate"
  if ask_any_to_run "是否升级虚拟环境中的 pip？"; then
    run_logged python -m pip install --upgrade pip setuptools wheel
  else
    gray_echo "已跳过 pip 升级。"
  fi
  if ! python -c 'import PySide6.QtWidgets, PyInstaller, macholib, lief, r2pipe, jinja2, rich' >/dev/null 2>&1; then
    confirm_required_install "需要联网补齐工程依赖"
    run_logged python -m pip install -r "${PROJECT_ROOT}/requirements.txt"
    python -c 'import PySide6.QtWidgets, PyInstaller, macholib, lief, r2pipe, jinja2, rich' || return 1
  fi
}
# 清理旧构建目录，避免旧产物污染本次结果。
clean_build_outputs() {
  [[ ! -L "$DIST_ROOT" ]] || { error_echo "拒绝清理符号链接 dist"; return 1; }
  if ! confirm_yes "即将删除旧构建目录：${BUILD_DIR} 和 ${DIST_ROOT}"; then
    warn_echo "未收到 YES，已取消本次构建。"
    return 1
  fi
  run_logged python "${PROJECT_ROOT}/scripts/artifact_shortcuts.py" --root "$SCRIPT_DIR" --clear
  rm -rf -- "$BUILD_DIR" "$DIST_ROOT"
  BUILD_STAMP="$(date "+%Y.%m.%d %H-%M-%S")"
  DIST_DIR="${DIST_ROOT}/${BUILD_STAMP}"
  APP_BUNDLE="${DIST_DIR}/IPA Reverse Analysis Tool.app"
  DMG_PATH="${DIST_DIR}/IPA-Reverse-Analysis-Tool-macOS.dmg"
  DMG_STAGING="${DIST_DIR}/dmg_staging"
  info_echo "构建时间（年月日时分秒）：${BUILD_STAMP}"
}
# 使用统一 spec 构建 macOS App Bundle。
build_macos_app() {
  info_echo "开始构建 macOS App。"
  run_logged pyinstaller --noconfirm --clean --distpath "$DIST_DIR" "$SPEC_FILE"
  if [[ ! -d "$APP_BUNDLE" ]]; then
    error_echo "未找到 App Bundle：${APP_BUNDLE}"
    return 1
  fi
  run_logged codesign --force --deep --sign - "$APP_BUNDLE"
  run_logged codesign --verify --deep --strict "$APP_BUNDLE"
  success_echo "macOS App 构建完成：${APP_BUNDLE}"
}
# 生成包含 App、环境体检工具和 Applications 快捷入口的 DMG。
build_dmg_installer() {
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  cp "${PROJECT_ROOT}/doctor/macos/IPA环境体检.command" "$DMG_STAGING/IPA环境体检.command"
  chmod +x "$DMG_STAGING/IPA环境体检.command"
  ln -s /Applications "$DMG_STAGING/Applications"
  run_logged hdiutil create \
    -volname "IPA Reverse Analysis Tool" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  rm -rf -- "$DMG_STAGING"
  success_echo "macOS DMG 构建完成：${DMG_PATH}"
}
# 汇总构建产物和日志位置。
show_build_result() {
  echo ""
  highlight_echo "============================== 构建完成 =============================="
  success_echo "App：${APP_BUNDLE}"
  success_echo "DMG：${DMG_PATH}"
  warn_echo "当前为本地 ad-hoc 签名；正式分发仍需 Developer ID 签名和 notarization。"
  info_echo "完整日志：${LOG_FILE}"
  highlight_echo "========================================================================"
  run_logged python "${PROJECT_ROOT}/scripts/artifact_shortcuts.py" --root "$SCRIPT_DIR" "$APP_BUNDLE" "$DMG_PATH"
  open "$DIST_DIR" || return 1
  open "$APP_BUNDLE" || return 1
}
# 编排 macOS App 和 DMG 构建流程。
main() {
  show_script_intro_and_wait # 展示脚本用途、影响范围和取消方式。
  initialize_script_runtime # 启用严格模式并初始化日志。
  change_to_project_root # 切换到 Python 项目根目录。
  check_environment # 检查 macOS 构建环境和项目输入文件。
  prepare_python_environment # 创建虚拟环境并安装运行与打包依赖。
  clean_build_outputs # 经 YES 确认后清理旧构建产物。
  build_macos_app # 使用 PyInstaller 构建并验证 App Bundle。
  build_dmg_installer # 生成可拖入 Applications 的 DMG。
  show_build_result # 输出构建产物和日志位置。
}

main "$@"
