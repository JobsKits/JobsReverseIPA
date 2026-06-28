from __future__ import annotations

import platform
import shutil
import subprocess
import sys
from pathlib import Path


def app_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        executable_dir = Path(sys.executable).resolve().parent
        if platform.system() == "Darwin" and executable_dir.name == "MacOS":
            return executable_dir.parent / "Resources"
        return executable_dir
    return Path(__file__).resolve().parents[2]


def platform_tool_subdir() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == "darwin":
        return "macos-arm64" if machine in {"arm64", "aarch64"} else "macos-x86_64"
    if system == "windows":
        return "windows-x64"
    return "linux-x64"


def bundled_tools_dir() -> Path:
    return app_base_dir() / "tools" / platform_tool_subdir()


def executable_name(name: str) -> str:
    if platform.system() == "Windows" and not name.lower().endswith(".exe"):
        return f"{name}.exe"
    return name


def find_tool(name: str) -> str | None:
    exe_name = executable_name(name)
    bundled = bundled_tools_dir() / exe_name
    if bundled.exists() and bundled.is_file():
        return str(bundled)
    system_path = shutil.which(exe_name)
    if system_path:
        return system_path
    return None


def run_tool(name: str, args: list[str], timeout: int = 60) -> subprocess.CompletedProcess[str]:
    tool_path = find_tool(name)
    if not tool_path:
        raise RuntimeError(f"未找到工具：{name}，请安装或放入 tools 目录")
    return subprocess.run(
        [tool_path, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=timeout,
    )
