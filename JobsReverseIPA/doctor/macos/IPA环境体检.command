#!/bin/zsh
# 脚本自述：
# - 脚本名称：IPA环境体检.command
# - 核心用途：检查并修复 IPA 逆向分析工具所需的 Python 包、Apple CLT、Homebrew、radare2、Java、Ghidra 等环境。
# - 影响范围：可能安装或升级 Python 包、Homebrew 公式和 Xcode Command Line Tools；默认回车执行，输入 n 才跳过。
# - 运行提示：运行后会先打印内置自述；确认后在终端输出结果，不默认生成报告文件。
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

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
setopt NO_NOMATCH

SCRIPT_DIR="${${functions_source[jobs_intro_style]}:A:h}"
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
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：检查并修复 IPA 逆向分析工具所需环境。" | jobs_intro_style body
  warn_echo "影响范围：可能安装或升级 Python 包、Homebrew 公式和 Xcode Command Line Tools。" | jobs_intro_style body
  gray_echo "输出策略：结果直接打印在终端；不默认生成 doctor_report 文件。" | jobs_intro_style body
  gray_echo "执行策略：回车自动安装缺失项并升级已安装项；输入 n 才跳过。" | jobs_intro_style body
  print "环境：先更新或安装 Homebrew，再检查并修复兼容的 Python。" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  gray_echo "取消方式：按 Ctrl+C 终止，不会继续执行后续业务。" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
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
  print -r -- "$JOBS_PYTHON_BIN"
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
  jobs_python_prepare_venv "$VENV_DIR" 3.10 || return 1
  success_echo "项目 Python 虚拟环境可用：${VENV_DIR}"
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
  ensure_project_venv || exit 1
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
  success_echo "内置自检已更新并验证 Homebrew：${JOBS_HOMEBREW_BIN}"
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
# 在本脚本内部准备 Homebrew 与兼容的 Python。
prepare_python_runtime() {
  jobs_python_mark_confirmed || exit 1
  jobs_python_ensure 3.10 python@3.13 || exit 1
}
# 编排当前入口的业务步骤。
main() {
  show_script_intro_and_wait # 展示用途、影响范围和交互策略。
  ask_auto_fix_mode # 选择自动修复全部，或进入逐项确认模式。
  prepare_python_runtime # 内置功能更新 Homebrew、检查并修复 Python。
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
