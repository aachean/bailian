#!/usr/bin/env python3
"""一次跑完全部验收场景，打印汇总表。 

    python tools/run_tests.py            # 跑 tests/test_*.tscn
    python tools/run_tests.py m5 m16     # 只跑名字里带 m5 / m16 的

为什么要有它：`tests/` 下面现在有十几个场景，一个一个手敲太慢，
而且**漏跑一个等于没跑**（红的那组可能正好是刚改坏的那块）。汇总表让「哪些组挂了」
一眼可见，省得回头翻 log。

退出码 = 失败的组数，可以直接接进 CI 或提交前检查。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GODOT = Path("D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe")
LOG_DIR = REPO / "build" / "testlogs"

## 「═══ 13 通过 ／ 2 失败 ═══」
SUMMARY = re.compile(r"通过\s*[／/]\s*(\d+)\s*失败")
COUNT = re.compile(r"(\d+)\s*通过\s*[／/]\s*(\d+)\s*失败")
TIMEOUT_S = 120


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("filters", nargs="*", help="只跑名字含这些片段的组")
    args = ap.parse_args()

    scenes = sorted((REPO / "tests").glob("test_*.tscn"))
    if args.filters:
        scenes = [s for s in scenes if any(f in s.stem for f in args.filters)]
    if not scenes:
        print("没有匹配的测试场景")
        return 1

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, int, int, int]] = []
    for scene in scenes:
        log = LOG_DIR / (scene.stem + ".log")
        # --fixed-fps 必加（见 docs/engineering-notes.md）。
        # 超时单列一档：**测试卡住十有八九是 Parse Error**（脚本编译不过，
        # 场景里的协程永远等不到下一帧），所以别把它当成「跑得慢」
        try:
            proc = subprocess.run(
                [str(GODOT), "--headless", "--fixed-fps", "60", "--path", str(REPO),
                 f"res://tests/{scene.name}"],
                cwd=REPO, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=TIMEOUT_S,
            )
            out = (proc.stdout or "") + (proc.stderr or "")
            code = proc.returncode
        except subprocess.TimeoutExpired as exc:
            out = ((exc.stdout or b"").decode("utf-8", "replace")
                   if isinstance(exc.stdout, bytes) else (exc.stdout or ""))
            out += "\n<<超时 %ds 未结束>>\n" % TIMEOUT_S
            code = -9
        log.write_text(out, encoding="utf-8")
        m = COUNT.search(out)
        if m:
            ok, bad = int(m.group(1)), int(m.group(2))
        else:
            # 没打出汇总 = 脚本根本没跑完（Parse Error / 崩了 / 卡住）
            ok, bad = 0, -1
        # **脚本报错但汇总仍然全绿**是真实发生过的一种假绿：
        # 断言所在的函数中途抛错 → 那句 _check 根本没执行 → 汇总里少一条却显示 0 失败。
        # 所以凡是日志里有 SCRIPT ERROR 的组，一律降级为「可疑」
        noisy = "SCRIPT ERROR" in out
        rows.append((scene.stem, ok, bad, code, noisy))

    print("")
    print("╔══════════════════════════════════════════")
    failed = 0
    for name, ok, bad, code, noisy in rows:
        if bad < 0:
            mark, note = "💥", "没跑完（Parse Error / 崩了）—— 看 build/testlogs/%s.log" % name
            failed += 1
        elif bad > 0:
            mark, note = "❌", "%d 通过 ／ %d 失败" % (ok, bad)
            failed += 1
        elif noisy:
            mark, note = "⚠️", "%d 通过，但日志里有 SCRIPT ERROR（可能有断言被跳过）" % ok
            failed += 1
        else:
            mark, note = "✅", "%d 通过" % ok
        print("║ %s %-12s %s" % (mark, name, note))
    print("╚══════════════════════════════════════════")
    print("共 %d 组，不合格 %d 组" % (len(rows), failed))
    if failed:
        print("日志在 build/testlogs/")
    return failed


if __name__ == "__main__":
    sys.exit(main())
