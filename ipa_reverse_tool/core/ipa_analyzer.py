from __future__ import annotations

import hashlib
import html
import json
import plistlib
import re
import shutil
import zipfile
from dataclasses import asdict, dataclass, field
from pathlib import Path


TEXT_SUFFIXES = {".txt", ".json", ".plist", ".xml", ".html", ".js", ".css", ".strings", ".conf", ".config"}
RESOURCE_GROUPS = {
    "images": {".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".pdf"},
    "plist": {".plist"},
    "json": {".json"},
    "sqlite": {".sqlite", ".sqlite3", ".db"},
    "frameworks": {".framework"},
    "dylib": {".dylib"},
    "certificates": {".cer", ".crt", ".der", ".p12", ".mobileprovision"},
    "web": {".html", ".htm", ".js", ".css"},
    "localization": {".strings", ".stringsdict"},
}
SENSITIVE_PATTERNS = {
    "url": re.compile(r"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"),
    "ip": re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),
    "jwt": re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"),
    "api_key": re.compile(r"(?i)\b(api[_-]?key|secret|token|access[_-]?key)\b.{0,80}"),
}
PRIVACY_KEYS = [
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSContactsUsageDescription",
    "NSCalendarsUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
    "NSUserTrackingUsageDescription",
]


@dataclass
class IpaAnalysisResult:
    ipa_path: str
    output_dir: str
    app_dir: str
    executable_path: str
    file_info: dict[str, object]
    app_info: dict[str, object]
    privacy: dict[str, object]
    resources: dict[str, list[str]] = field(default_factory=dict)
    strings: dict[str, list[str]] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clean_output_dir(output_dir: Path) -> None:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)


def extract_ipa(ipa_path: Path, work_dir: Path) -> Path:
    with zipfile.ZipFile(ipa_path) as archive:
        archive.extractall(work_dir)
    payload_dir = work_dir / "Payload"
    app_dirs = sorted(payload_dir.glob("*.app")) if payload_dir.exists() else []
    if not app_dirs:
        raise RuntimeError("未找到 Payload/*.app，请确认传入的是有效 ipa")
    return app_dirs[0]


def read_info_plist(app_dir: Path) -> dict[str, object]:
    plist_path = app_dir / "Info.plist"
    if not plist_path.exists():
        raise RuntimeError("未找到 Info.plist")
    with plist_path.open("rb") as handle:
        return plistlib.load(handle)


def find_executable(app_dir: Path, info_plist: dict[str, object]) -> Path:
    executable_name = str(info_plist.get("CFBundleExecutable") or "")
    if executable_name:
        candidate = app_dir / executable_name
        if candidate.exists():
            return candidate
    candidates = [item for item in app_dir.iterdir() if item.is_file() and not item.suffix]
    if not candidates:
        raise RuntimeError("未找到主 Mach-O 可执行文件")
    return candidates[0]


def collect_app_info(info_plist: dict[str, object]) -> dict[str, object]:
    keys = [
        "CFBundleIdentifier",
        "CFBundleName",
        "CFBundleDisplayName",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "MinimumOSVersion",
        "CFBundleExecutable",
        "LSApplicationQueriesSchemes",
        "CFBundleURLTypes",
        "NSAppTransportSecurity",
        "UIBackgroundModes",
        "com.apple.developer.associated-domains",
    ]
    return {key: info_plist.get(key) for key in keys if key in info_plist}


def analyze_privacy(info_plist: dict[str, object]) -> dict[str, object]:
    permissions = {key: info_plist.get(key) for key in PRIVACY_KEYS if key in info_plist}
    ats = info_plist.get("NSAppTransportSecurity", {})
    allows_http = bool(isinstance(ats, dict) and ats.get("NSAllowsArbitraryLoads"))
    return {
        "permissions": permissions,
        "ats_allows_arbitrary_loads": allows_http,
        "url_schemes": info_plist.get("CFBundleURLTypes", []),
        "query_schemes": info_plist.get("LSApplicationQueriesSchemes", []),
        "background_modes": info_plist.get("UIBackgroundModes", []),
    }


def classify_resources(app_dir: Path) -> dict[str, list[str]]:
    resources: dict[str, list[str]] = {name: [] for name in RESOURCE_GROUPS}
    for path in app_dir.rglob("*"):
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        for group, suffixes in RESOURCE_GROUPS.items():
            if suffix in suffixes or any(part.endswith(".framework") for part in path.parts):
                resources[group].append(str(path.relative_to(app_dir)))
                break
    return {key: sorted(value) for key, value in resources.items() if value}


def read_text_sample(path: Path, limit: int = 1024 * 512) -> str:
    try:
        data = path.read_bytes()[:limit]
    except OSError:
        return ""
    return data.decode("utf-8", errors="ignore")


def scan_strings(app_dir: Path) -> dict[str, list[str]]:
    findings: dict[str, set[str]] = {name: set() for name in SENSITIVE_PATTERNS}
    scanned_files: list[str] = []
    for path in app_dir.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES and path.stat().st_size > 1024 * 1024:
            continue
        text = read_text_sample(path)
        if not text:
            continue
        scanned_files.append(str(path.relative_to(app_dir)))
        for name, pattern in SENSITIVE_PATTERNS.items():
            findings[name].update(match.group(0)[:200] for match in pattern.finditer(text))
    result = {name: sorted(values) for name, values in findings.items() if values}
    result["scanned_files"] = scanned_files[:500]
    return result


def analyze_ipa(ipa_path: Path, output_dir: Path) -> IpaAnalysisResult:
    ipa_path = ipa_path.expanduser().resolve()
    if not ipa_path.exists() or ipa_path.suffix.lower() != ".ipa":
        raise RuntimeError(f"不是有效 ipa 文件：{ipa_path}")
    clean_output_dir(output_dir)
    work_dir = output_dir / "extracted"
    work_dir.mkdir(parents=True, exist_ok=True)
    app_dir = extract_ipa(ipa_path, work_dir)
    info_plist = read_info_plist(app_dir)
    executable = find_executable(app_dir, info_plist)
    result = IpaAnalysisResult(
        ipa_path=str(ipa_path),
        output_dir=str(output_dir),
        app_dir=str(app_dir),
        executable_path=str(executable),
        file_info={
            "name": ipa_path.name,
            "size": ipa_path.stat().st_size,
            "sha256": sha256_file(ipa_path),
        },
        app_info=collect_app_info(info_plist),
        privacy=analyze_privacy(info_plist),
        resources=classify_resources(app_dir),
        strings=scan_strings(app_dir),
    )
    write_analysis_files(output_dir, result)
    return result


def write_analysis_files(output_dir: Path, result: IpaAnalysisResult) -> None:
    app_info_dir = output_dir / "app_info"
    reports_dir = output_dir / "reports"
    app_info_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)
    payload = asdict(result)
    (app_info_dir / "app_summary.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (reports_dir / "reverse_report.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# IPA 逆向静态分析报告",
        "",
        f"- IPA：{result.ipa_path}",
        f"- 输出目录：{result.output_dir}",
        f"- App 目录：{result.app_dir}",
        f"- 主程序：{result.executable_path}",
        f"- SHA256：{result.file_info['sha256']}",
        "",
        "## App 基础信息",
        "",
    ]
    for key, value in result.app_info.items():
        lines.append(f"- {key}：`{value}`")
    lines.extend(["", "## 权限与隐私", ""])
    for key, value in result.privacy.items():
        lines.append(f"- {key}：`{value}`")
    lines.extend(["", "## 资源分类", ""])
    for group, items in result.resources.items():
        lines.append(f"- {group}：{len(items)} 个")
    lines.extend(["", "## 字符串扫描", ""])
    for group, items in result.strings.items():
        lines.append(f"- {group}：{len(items)} 条")
    (reports_dir / "reverse_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_html_report(reports_dir / "reverse_report.html", result)


def write_html_report(report_path: Path, result: IpaAnalysisResult) -> None:
    def rows(values: dict[str, object]) -> str:
        return "".join(
            f"<tr><th>{html.escape(str(key))}</th><td><pre>{html.escape(str(value))}</pre></td></tr>"
            for key, value in values.items()
        )

    resource_rows = "".join(
        f"<tr><th>{html.escape(group)}</th><td>{len(items)}</td></tr>" for group, items in result.resources.items()
    )
    string_rows = "".join(
        f"<tr><th>{html.escape(group)}</th><td>{len(items)}</td></tr>" for group, items in result.strings.items()
    )
    document = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>IPA 逆向静态分析报告</title>
  <style>
    body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #18212b; background: #f4f6f8; }}
    main {{ max-width: 1080px; margin: 0 auto; padding: 32px 24px 60px; }}
    h1 {{ font-size: 30px; margin: 0 0 8px; }}
    h2 {{ font-size: 20px; margin: 30px 0 10px; }}
    .meta {{ color: #566574; margin-bottom: 24px; }}
    table {{ width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #d9e0e6; }}
    th, td {{ padding: 11px 13px; border-bottom: 1px solid #e3e8ed; text-align: left; vertical-align: top; }}
    th {{ width: 30%; color: #31485c; background: #f8fafb; }}
    pre {{ white-space: pre-wrap; word-break: break-word; margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
  </style>
</head>
<body>
<main>
  <h1>IPA 逆向静态分析报告</h1>
  <div class="meta">{html.escape(str(result.file_info['name']))} · SHA256 {html.escape(str(result.file_info['sha256']))}</div>
  <h2>App 基础信息</h2><table>{rows(result.app_info)}</table>
  <h2>权限与隐私</h2><table>{rows(result.privacy)}</table>
  <h2>资源分类</h2><table>{resource_rows}</table>
  <h2>字符串扫描</h2><table>{string_rows}</table>
</main>
</body>
</html>
"""
    report_path.write_text(document, encoding="utf-8")
