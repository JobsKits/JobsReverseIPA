from __future__ import annotations

import importlib.util
import json
import platform
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

from .tool_locator import find_tool


@dataclass
class CheckResult:
    name: str
    category: str
    status: str
    detail: str
    install_hint: str = ""
    path: str = ""
    version: str = ""


def _run_version(command: list[str], timeout: int = 10) -> tuple[str, str]:
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=timeout,
        )
    except Exception as exc:
        return "", str(exc)
    output = (result.stdout or result.stderr or "").strip().splitlines()
    return (output[0] if output else "", "") if result.returncode == 0 else ("", result.stderr.strip())


def check_python_package(import_name: str, package_name: str | None = None) -> CheckResult:
    package_name = package_name or import_name
    spec = importlib.util.find_spec(import_name)
    if not spec:
        return CheckResult(
            name=package_name,
            category="python-package",
            status="missing",
            detail=f"未找到 Python 包：{package_name}",
            install_hint=f"pip install {package_name}",
        )
    return CheckResult(
        name=package_name,
        category="python-package",
        status="ok",
        detail=f"Python 包可用：{package_name}",
        path=str(spec.origin or ""),
    )


def check_command(name: str, category: str, version_args: list[str] | None = None, install_hint: str = "") -> CheckResult:
    path = find_tool(name)
    if not path:
        return CheckResult(
            name=name,
            category=category,
            status="missing",
            detail=f"未找到命令：{name}",
            install_hint=install_hint,
        )
    version = ""
    if version_args:
        version, _ = _run_version([path, *version_args])
    return CheckResult(
        name=name,
        category=category,
        status="ok",
        detail=f"命令可用：{name}",
        path=path,
        version=version,
    )


def check_ghidra() -> CheckResult:
    candidates = [
        "analyzeHeadless",
        "/Applications/ghidra/support/analyzeHeadless",
        "/Applications/Ghidra.app/Contents/MacOS/support/analyzeHeadless",
    ]
    for candidate in candidates:
        path = find_tool(candidate) if "/" not in candidate else (candidate if Path(candidate).exists() else None)
        if path:
            return CheckResult(
                name="Ghidra",
                category="reverse-tool",
                status="ok",
                detail="Ghidra Headless 可用",
                path=str(path),
            )
    return CheckResult(
        name="Ghidra",
        category="reverse-tool",
        status="missing",
        detail="未找到 Ghidra Headless analyzeHeadless",
        install_hint="安装 Ghidra 后配置 analyzeHeadless 路径",
    )


def run_environment_checks() -> list[CheckResult]:
    checks = [
        CheckResult(
            name="Python runtime",
            category="runtime",
            status="ok",
            detail=f"Python {platform.python_version()}",
            path=sys.executable,
            version=platform.python_version(),
        ),
        check_python_package("macholib"),
        check_python_package("lief"),
        check_python_package("r2pipe"),
        check_python_package("jinja2"),
        check_python_package("rich"),
        check_python_package("PySide6"),
        check_command("radare2", "reverse-tool", ["-v"], "macOS: brew install radare2；Windows: 安装 radare2 或放入 tools/windows-x64"),
        check_command("rabin2", "reverse-tool", ["-v"], "跟随 radare2 安装"),
        check_ghidra(),
        check_command("java", "runtime", ["-version"], "安装 OpenJDK；macOS 可用 brew install openjdk"),
        check_command("jtool2", "reverse-tool", ["--help"], "安装 jtool2 或放入 tools 目录"),
    ]
    if platform.system() == "Darwin":
        checks.extend(
            [
                check_command("otool", "apple-clt", ["-h"], "xcode-select --install"),
                check_command("nm", "apple-clt", ["-h"], "xcode-select --install"),
                check_command("codesign", "apple-clt", ["-h"], "xcode-select --install"),
                check_command("plutil", "apple-clt", ["-help"], "xcode-select --install"),
                check_command("xcrun", "apple-clt", ["--version"], "xcode-select --install"),
            ]
        )
    return checks


def capability_summary(checks: list[CheckResult]) -> dict[str, str]:
    names = {item.name: item.status for item in checks}
    has = lambda name: names.get(name) == "ok"
    return {
        "IPA 解包": "可用",
        "Info.plist 分析": "可用",
        "资源提取": "可用",
        "字符串扫描": "可用",
        "Mach-O 基础分析": "可用" if has("lief") or has("macholib") else "部分可用",
        "Apple 符号辅助分析": "可用" if all(has(name) for name in ["otool", "nm"]) else "不可用或非 macOS",
        "radare2 深度分析": "可用" if has("radare2") and has("rabin2") else "不可用，请安装 radare2",
        "Ghidra 伪代码导出": "可用" if has("Ghidra") and has("java") else "不可用，请配置 Ghidra 和 Java",
    }


def write_doctor_reports(output_dir: Path, checks: list[CheckResult]) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "platform": {
            "system": platform.system(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "checks": [asdict(item) for item in checks],
        "capabilities": capability_summary(checks),
    }
    json_path = output_dir / "doctor_report.json"
    md_path = output_dir / "doctor_report.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# IPA 环境体检报告", "", f"- 生成时间：{payload['generated_at']}", f"- 系统：{platform.system()} {platform.machine()}", ""]
    lines.append("## 检查项")
    lines.append("")
    lines.append("| 状态 | 类别 | 名称 | 说明 |")
    lines.append("|---|---|---|---|")
    for item in checks:
        mark = "OK" if item.status == "ok" else "MISS"
        detail = item.detail.replace("|", "/")
        hint = f"；建议：{item.install_hint}" if item.install_hint and item.status != "ok" else ""
        lines.append(f"| {mark} | {item.category} | {item.name} | {detail}{hint} |")
    lines.append("")
    lines.append("## 可用能力")
    lines.append("")
    for name, status in capability_summary(checks).items():
        lines.append(f"- {name}：{status}")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, md_path


def run_doctor(output_dir: Path) -> tuple[list[CheckResult], Path, Path]:
    checks = run_environment_checks()
    json_path, md_path = write_doctor_reports(output_dir, checks)
    return checks, json_path, md_path
