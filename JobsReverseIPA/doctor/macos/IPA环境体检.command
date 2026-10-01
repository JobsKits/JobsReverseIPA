#!/bin/zsh
# 脚本自述：
# - 脚本名称：IPA环境体检.command
# - 核心用途：检查并修复 IPA 逆向分析工具所需的 Python 包、Apple CLT、Homebrew、radare2、Java、Ghidra 等环境。
# - 影响范围：可能安装或升级 Python 包、Homebrew 公式和 Xcode Command Line Tools；默认回车执行，输入 n 才跳过。
# - 运行提示：运行后会先打印内置自述；确认后在终端输出结果，不默认生成报告文件。
setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
VENV_PYTHON="${VENV_DIR}/bin/python"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

PYTHON_PACKAGES=(macholib lief r2pipe jinja2 rich PySide6)
BREW_FORMULAS=(radare2 openjdk)
AUTO_FIX_ALL=0

# 记录终端输出并同步写入日志。
log() { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出说明信息。
note_echo() { log "\033[1;35m➤ $1\033[0m"; }
# 输出警告信息。
warn_echo() { log "\033[1;33m⚠ $1\033[0m"; }
# 输出成功信息。
success_echo() { log "\033[1;32m✔ $1\033[0m"; }
# 输出错误信息。
error_echo() { log "\033[1;31m✖ $1\033[0m"; }
# 输出高亮标题。
highlight_echo() { log "\033[1;36m$1\033[0m"; }
# 输出次要信息。
gray_echo() { log "\033[0;90m$1\033[0m"; }
# 打印脚本内置自述，并等待用户确认。
show_script_intro_and_wait() {
  clear
  highlight_echo "============================== 脚本自述 =============================="
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：检查并修复 IPA 逆向分析工具所需环境。"
  warn_echo "影响范围：可能安装或升级 Python 包、Homebrew 公式和 Xcode Command Line Tools。"
  gray_echo "输出策略：结果直接打印在终端；不默认生成 doctor_report 文件。"
  gray_echo "执行策略：回车自动安装缺失项并升级已安装项；输入 n 才跳过。"
  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "取消方式：按 Ctrl+C 终止，不会继续执行后续业务。"
  highlight_echo "======================================================================="
  echo ""
  read -r "?已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 缺失依赖回车安装，任意字符或 EOF 取消整个体检流程。
confirm_required_install() {
  local answer=""
  IFS= read -r "?${1}（直接回车安装；输入任意字符后回车取消）：" answer || exit 1
  [[ -z "$answer" ]] || { error_echo "已取消依赖安装，停止当前流程。"; exit 1; }
}
# 已有依赖的可选升级与修复沿用体检器现有策略。
ask_any_to_run() {
  if [[ "$AUTO_FIX_ALL" == "1" ]]; then
    return 0
  fi
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车执行；输入 n 后回车跳过）：" answer
  [[ "$answer" != "n" && "$answer" != "N" ]]
}
# Homebrew 自身更新属于全局刷新，默认跳过，输入任意字符才执行。
ask_any_to_update_homebrew() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车更新）：" answer
  [[ -n "$answer" ]]
}
# 询问是否自动安装缺失项并升级已安装项。
ask_auto_fix_mode() {
  echo ""
  warn_echo "本脚本可以自动安装缺失项，并升级已安装项。"
  gray_echo "直接回车会自动执行本轮所有安装 / 升级；输入 n 才进入逐项确认模式。"
  local answer=""
  read -r "answer?直接回车自动修复全部；输入 n 后回车进入逐项确认模式：" answer
  if [[ "$answer" == "n" || "$answer" == "N" ]]; then
    AUTO_FIX_ALL=0
    gray_echo "已进入逐项确认模式：每项直接回车执行，输入 n 跳过。"
  else
    AUTO_FIX_ALL=1
    success_echo "已启用自动修复：缺失项会安装，已存在项会升级。"
  fi
}
# 查找可用 Python 解释器。
find_python() {
  if command -v python3 >/dev/null 2>&1; then
    print -r -- "$(command -v python3)"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    print -r -- "$(command -v python)"
    return 0
  fi
  return 1
}
# 查找 Homebrew 命令，兼容 Apple Silicon 和 Intel。
find_brew() {
  if command -v brew >/dev/null 2>&1; then
    print -r -- "$(command -v brew)"
    return 0
  fi
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    print -r -- "/opt/homebrew/bin/brew"
    return 0
  fi
  if [[ -x "/usr/local/bin/brew" ]]; then
    print -r -- "/usr/local/bin/brew"
    return 0
  fi
  return 1
}
# 等待其它 Homebrew 安装、升级或更新任务结束，避免下载锁冲突。
wait_for_brew_idle() {
  local waited_seconds=0
  while pgrep -f "/brew.rb (install|upgrade|update)" >/dev/null 2>&1; do
    warn_echo "检测到其它 Homebrew 安装 / 升级 / 更新任务仍在运行，等待 10 秒后重试。"
    sleep 10
    waited_seconds=$((waited_seconds + 10))
    if (( waited_seconds >= 300 )); then
      error_echo "等待 Homebrew 空闲超时。请等当前 brew 任务结束后重新运行本脚本。"
      return 1
    fi
  done
}
# 执行 Homebrew 命令，并保留原始退出码。
run_brew_command() {
  local brew_bin="$1"
  shift
  wait_for_brew_idle || return 1
  "$brew_bin" "$@" 2>&1 | tee -a "$LOG_FILE"
  return "${pipestatus[1]}"
}
# 获取当前 Mac 对应的内置工具目录。
get_bundled_tool_dir() {
  if [[ "$(uname -m)" == "arm64" ]]; then
    print -r -- "${PROJECT_DIR}/tools/macos-arm64"
  else
    print -r -- "${PROJECT_DIR}/tools/macos-x86_64"
  fi
}
# 从常见安装位置查找 Ghidra Headless。
find_ghidra_headless() {
  local candidate=""
  if command -v analyzeHeadless >/dev/null 2>&1; then
    print -r -- "$(command -v analyzeHeadless)"
    return 0
  fi
  for candidate in \
    "/Applications/Ghidra.app/Contents/MacOS/support/analyzeHeadless" \
    "/Applications/ghidra/support/analyzeHeadless" \
    "/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless" \
    "/usr/local/opt/ghidra/libexec/support/analyzeHeadless" \
    /opt/homebrew/Caskroom/ghidra/*/ghidra_*/support/analyzeHeadless \
    /usr/local/Caskroom/ghidra/*/ghidra_*/support/analyzeHeadless; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 把 Ghidra Headless 软链接到项目 tools 目录，方便主程序定位。
link_ghidra_headless() {
  local ghidra_path="$1"
  local tool_dir=""
  tool_dir="$(get_bundled_tool_dir)"
  mkdir -p "$tool_dir"
  ln -sf "$ghidra_path" "${tool_dir}/analyzeHeadless"
  success_echo "已链接：${tool_dir}/analyzeHeadless -> ${ghidra_path}"
}
# 从 PATH 和项目 tools 目录查找 jtool2。
find_jtool2() {
  local tool_dir=""
  tool_dir="$(get_bundled_tool_dir)"
  if command -v jtool2 >/dev/null 2>&1; then
    print -r -- "$(command -v jtool2)"
    return 0
  fi
  if [[ -x "${tool_dir}/jtool2" ]]; then
    print -r -- "${tool_dir}/jtool2"
    return 0
  fi
  return 1
}
# 创建或复用项目虚拟环境，避免污染 Homebrew 管理的系统 Python。
ensure_project_venv() {
  local python_bin=""
  python_bin="$(find_python)" || {
    error_echo "缺失：Python。请先安装 Python 3，再重新运行本脚本。"
    return 1
  }
  if [[ -x "$VENV_PYTHON" ]]; then
    success_echo "已存在：项目 Python 虚拟环境 -> ${VENV_DIR}"
  else
    warn_echo "缺失：项目 Python 虚拟环境 -> ${VENV_DIR}"
    if confirm_required_install "是否创建项目 Python 虚拟环境"; then
      "$python_bin" -m venv "$VENV_DIR" 2>&1 | tee -a "$LOG_FILE"
    fi
  fi
  if [[ ! -x "$VENV_PYTHON" ]]; then
    error_echo "项目虚拟环境不可用，跳过 Python 包安装。"
    return 1
  fi
  "$VENV_PYTHON" -m pip install --upgrade pip setuptools wheel 2>&1 | tee -a "$LOG_FILE"
}
# 检查 Python 是否可用，不可用时给出安装提示。
check_python_runtime() {
  local python_bin=""
  python_bin="$(find_python)" || {
    error_echo "缺失：Python。请先安装 Python 3，再重新运行本脚本。"
    note_echo "下载地址：https://www.python.org/downloads/"
    return 1
  }
  success_echo "已安装：Python -> ${python_bin}"
  "$python_bin" --version 2>&1 | tee -a "$LOG_FILE"
  return 0
}
# 检查并修复 Python 包，存在则询问升级，缺失则询问安装。
check_python_packages() {
  ensure_project_venv || return 1
  highlight_echo "============================== Python 包 =============================="
  for package_name in "${PYTHON_PACKAGES[@]}"; do
    if "$VENV_PYTHON" -c "import ${package_name}" >/dev/null 2>&1; then
      success_echo "已安装：${package_name}"
      if ask_any_to_run "是否升级 Python 包 ${package_name}"; then
        "$VENV_PYTHON" -m pip install --upgrade "$package_name" 2>&1 | tee -a "$LOG_FILE"
      fi
    else
      warn_echo "缺失：${package_name}"
      if confirm_required_install "需要安装 Python 包 ${package_name}"; then
        "$VENV_PYTHON" -m pip install "$package_name" 2>&1 | tee -a "$LOG_FILE" || return 1
        "$VENV_PYTHON" -c "import ${package_name}" || return 1
      fi
    fi
  done
}
# 检查并修复 Xcode Command Line Tools。
check_xcode_command_line_tools() {
  highlight_echo "=========================== Apple CLT 工具 ==========================="
  if xcode-select -p >/dev/null 2>&1; then
    success_echo "已安装：Xcode Command Line Tools -> $(xcode-select -p)"
  else
    warn_echo "缺失：Xcode Command Line Tools"
    if confirm_required_install "需要打开 Xcode Command Line Tools 安装器"; then
      xcode-select --install 2>&1 | tee -a "$LOG_FILE"
    fi
  fi
  for command_name in otool nm codesign plutil xcrun; do
    if command -v "$command_name" >/dev/null 2>&1; then
      success_echo "已安装：${command_name} -> $(command -v "$command_name")"
    else
      warn_echo "缺失：${command_name}，通常由 Xcode Command Line Tools 提供。"
    fi
  done
}
# 检查并修复 Homebrew，不存在时询问安装，存在时询问更新自身。
check_homebrew() {
  highlight_echo "============================== Homebrew =============================="
  local brew_bin=""
  if brew_bin="$(find_brew)"; then
    success_echo "已安装：Homebrew -> ${brew_bin}"
    "$brew_bin" --version 2>&1 | head -n 1 | tee -a "$LOG_FILE"
    if ask_any_to_update_homebrew "是否更新 Homebrew 自身索引"; then
      run_brew_command "$brew_bin" update
    fi
    return 0
  fi
  warn_echo "缺失：Homebrew"
  if confirm_required_install "需要安装 Homebrew"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOG_FILE"
  fi
}
# 检查并修复 Homebrew 公式，存在则询问升级，缺失则询问安装。
check_brew_formulas() {
  local brew_bin=""
  brew_bin="$(find_brew)" || {
    warn_echo "跳过 Homebrew 公式检查：未找到 brew。"
    return 0
  }
  highlight_echo "============================ 逆向外源工具 ============================"
  for formula_name in "${BREW_FORMULAS[@]}"; do
    if "$brew_bin" list --formula "$formula_name" >/dev/null 2>&1; then
      success_echo "已安装：${formula_name}"
      if ask_any_to_run "是否升级 ${formula_name}"; then
        run_brew_command "$brew_bin" upgrade "$formula_name"
      fi
    else
      warn_echo "缺失：${formula_name}"
      if confirm_required_install "需要安装 ${formula_name}"; then
        run_brew_command "$brew_bin" install "$formula_name"
      fi
    fi
  done
}
# 检查 radare2 组件命令是否进入 PATH。
check_radare2_commands() {
  highlight_echo "============================ radare2 命令 ============================"
  for command_name in radare2 rabin2; do
    if command -v "$command_name" >/dev/null 2>&1; then
      success_echo "可用：${command_name} -> $(command -v "$command_name")"
      "$command_name" -v 2>&1 | head -n 1 | tee -a "$LOG_FILE"
    else
      warn_echo "不可用：${command_name}。如果刚安装完成，请重新打开终端或检查 PATH。"
    fi
  done
}
# 检查并修复 Ghidra。
check_ghidra() {
  local brew_bin=""
  local ghidra_path=""
  if ghidra_path="$(find_ghidra_headless)"; then
    success_echo "可用：Ghidra analyzeHeadless -> ${ghidra_path}"
    link_ghidra_headless "$ghidra_path"
    brew_bin="$(find_brew)" || return 0
    if "$brew_bin" list --formula ghidra >/dev/null 2>&1; then
      if ask_any_to_run "是否升级 Ghidra"; then
        run_brew_command "$brew_bin" upgrade ghidra
        ghidra_path="$(find_ghidra_headless)" && link_ghidra_headless "$ghidra_path"
      fi
    fi
    return 0
  fi
  warn_echo "缺失：Ghidra analyzeHeadless"
  brew_bin="$(find_brew)" || {
    warn_echo "未找到 Homebrew，无法自动安装 Ghidra。"
    return 0
  }
  if confirm_required_install "需要通过 Homebrew 安装 Ghidra"; then
    run_brew_command "$brew_bin" install ghidra
    ghidra_path="$(find_ghidra_headless)" && link_ghidra_headless "$ghidra_path"
  fi
}
# 检查 jtool2，并尝试 Homebrew Cask；如果源已禁用则给出明确说明。
check_jtool2() {
  local brew_bin=""
  local jtool2_path=""
  if jtool2_path="$(find_jtool2)"; then
    success_echo "可用：jtool2 -> ${jtool2_path}"
    return 0
  fi
  warn_echo "缺失：jtool2"
  brew_bin="$(find_brew)" || {
    warn_echo "未找到 Homebrew，无法尝试自动安装 jtool2。"
    return 0
  }
  if confirm_required_install "需要通过 Homebrew Cask 安装 jtool2"; then
    if ! run_brew_command "$brew_bin" install --cask jtool2; then
      warn_echo "jtool2 的 Homebrew Cask 当前已 discontinued / disabled，无法可靠自动安装。"
      note_echo "可手动下载 jtool2 后放到：$(get_bundled_tool_dir)/jtool2，并执行 chmod +x。"
    fi
  fi
}
# 检查 Ghidra 和 jtool2 这类可选逆向工具。
check_optional_reverse_tools() {
  highlight_echo "============================ 可选逆向工具 ============================"
  check_ghidra
  check_jtool2
}
# 输出本轮体检和修复的结束提示。
show_finish_message() {
  highlight_echo "============================== 处理完成 =============================="
  success_echo "环境体检和可选修复流程已结束。"
  gray_echo "终端上方就是本轮结果；不默认生成 doctor_report 文件。"
  gray_echo "分析 IPA 建议使用：${VENV_PYTHON} -m ipa_reverse_tool.main analyze /path/to/App.ipa --output output/latest"
  gray_echo "完整终端日志备份：${LOG_FILE}"
}
# 编排脚本自述、环境检查和修复流程。
main() {
  show_script_intro_and_wait # 展示用途、影响范围和交互策略。
  ask_auto_fix_mode # 选择自动修复全部，或进入逐项确认模式。
  check_python_runtime # 确认 Python 解释器可用。
  check_python_packages # 安装缺失 Python 包，并按需升级已存在包。
  check_xcode_command_line_tools # 检查 Apple CLT 及其内置命令。
  check_homebrew # 检查 Homebrew，并按需安装或更新。
  check_brew_formulas # 安装缺失 Homebrew 公式，并按需升级已存在公式。
  check_radare2_commands # 确认 radare2 和 rabin2 命令是否可直接调用。
  check_optional_reverse_tools # 检查 Ghidra 和 jtool2 等可选工具。
  show_finish_message # 汇总结束提示和日志位置。
}

main "$@"
