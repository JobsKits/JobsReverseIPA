from __future__ import annotations

from pathlib import Path

from ipa_reverse_tool.core.environment_doctor import run_doctor


def main() -> int:
    output_dir = Path.cwd() / "output" / "diagnostics"
    checks, json_path, md_path = run_doctor(output_dir)
    ok_count = sum(1 for item in checks if item.status == "ok")
    missing_count = len(checks) - ok_count
    print(f"环境体检完成：可用 {ok_count} 项，缺失 {missing_count} 项")
    print(f"JSON 报告：{json_path}")
    print(f"Markdown 报告：{md_path}")
    input("按回车退出...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
