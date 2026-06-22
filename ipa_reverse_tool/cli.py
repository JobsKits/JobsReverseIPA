from __future__ import annotations

import argparse
from pathlib import Path

from .core.environment_doctor import run_doctor
from .core.ipa_analyzer import analyze_ipa


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ipa-reverse-tool", description="IPA 静态逆向分析与环境体检工具")
    subparsers = parser.add_subparsers(dest="command", required=True)
    doctor = subparsers.add_parser("doctor", help="运行环境体检并生成报告")
    doctor.add_argument("--output", default="output/diagnostics", help="体检报告输出目录")
    subparsers.add_parser("gui", help="启动图形界面")
    analyze = subparsers.add_parser("analyze", help="分析一个 ipa 文件并生成报告")
    analyze.add_argument("ipa", help="ipa 文件路径，支持终端拖入路径")
    analyze.add_argument("--output", default="output/latest", help="分析输出目录")
    return parser


def run_doctor_command(output: str) -> int:
    checks, json_path, md_path = run_doctor(Path(output))
    ok_count = sum(1 for item in checks if item.status == "ok")
    missing_count = len(checks) - ok_count
    print(f"环境体检完成：可用 {ok_count} 项，缺失 {missing_count} 项")
    print(f"JSON 报告：{json_path}")
    print(f"Markdown 报告：{md_path}")
    return 0


def run_analyze_command(ipa: str, output: str) -> int:
    result = analyze_ipa(Path(ipa), Path(output))
    print("IPA 分析完成")
    print(f"App：{result.app_info.get('CFBundleDisplayName') or result.app_info.get('CFBundleName') or '未知'}")
    print(f"Bundle ID：{result.app_info.get('CFBundleIdentifier', '未知')}")
    print(f"输出目录：{result.output_dir}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "doctor":
        return run_doctor_command(args.output)
    if args.command == "gui":
        from .gui import run_gui

        return run_gui()
    if args.command == "analyze":
        return run_analyze_command(args.ipa, args.output)
    parser.print_help()
    return 2
