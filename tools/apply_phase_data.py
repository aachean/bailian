#!/usr/bin/env python3
"""相位的数值落地（ADR-0019 的 B 口径 / ADR-0023）。

把设计表的 **`boss_active`**（每章一个数）翻译成 `.tres` 里的相位帧数，
写进 `bailian/data/enemies/*.tres`。运行期只读 `.tres`（设计原则 4.4）。

    python tools/apply_phase_data.py            # 落地 + 自检
    python tools/apply_phase_data.py --dry-run  # 只看报告

## 两边的关系

`enemy_scaling.csv` 的 Boss 血量是这么算的：

    hp_boss_B = 等效DPS × UPTIME(0.55) × **boss_active** × 目标秒数

那个 `boss_active` 就是「**玩家能打到它的时间占比**」。它的另一半
（`1 - boss_active`）必须由游戏里的机制兑现 —— 否则血量按「有一段时间打不到」
配好了，实际却一直在挨打，Boss 会死得比设计快 15%~35%。这条机制就是相位。

所以本脚本**只做一件事**：给定「要占多少比例」和「一次相位想持续多久」，
反推出 `phase_frames` 与 `phase_interval_frames`：

    cycle = warn + frames + interval
    frames / cycle = 1 - boss_active      ← 反推 interval

`warn`（架势）算进周期的分母：它虽然可以打，但它占的是「还没进入下一轮」的时间，
少算它比例会偏高。

## 谁有相位

- **6 只 Boss**：按各自章节的 `boss_active`（ch1 0.85 → ch5 0.65）。
- **2 只教学精英**（`walker_elite` / `brute_heavy`）：一个**短而简单**的相位。
  设计原则 2.5 的四步法要求「引入 → 练习 → 转折 → 考核」——
  Boss 的招式必须先在它之前的屏里出现过，这两只就是那个「教学屏」的载体
  （它们已经是碎地重锤那条教学链上的一环）。教学相位**只亮护罩、不位移**。
- **小怪一律没有**（自检拦）：时长预算是按 Boss/精英算的，
  给小怪加相位会毁掉「一批怪打多久」的手感。
"""
from __future__ import annotations

import argparse
import csv
import io
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN_DATA = REPO.parent / "docs" / "gear-v2" / "data"
ENEMY_DIR = REPO / "data" / "enemies"

FPS = 60

## 章节 → 相位参数。`phase_s` 是**一次相位持续几秒**（手感值，不是比例——
## 比例由 boss_active 定）；`warn` 随章递增（Boss 越大，给玩家读的时间越长）
CHAPTERS = [
    # 章          一次相位(秒) 架势(帧)  位移方式（0=原地 1=后撤）
    ("ch1", 1.2, 18, 0),
    ("ch2", 1.5, 20, 0),
    ("ch3", 1.8, 22, 1),
    ("ch4", 2.2, 24, 1),
    ("ch5", 2.5, 26, 1),
]

## Boss → 章
BOSS_CHAPTER = {
    "boss": "ch1", "boss2": "ch1", "boss_luhou": "ch1",
    "boss_canjian": "ch2", "boss_xiushi": "ch2", "boss_zhongxin": "ch2",
}

## 教学精英：短、简单、只亮护罩（原地）。**不按章分** ——
## 它们跨章共用一份 data，而且「引入」这件事本来就该长一个样
TEACHERS = ["walker_elite", "brute_heavy"]
TEACH_PHASE_S = 0.8
TEACH_RATIO = 0.12
TEACH_WARN = 14

## 收招窗口 = 相位时长的这个比例（读招成功的人该拿到的输出时间）
RECOVER_RATIO = 0.25
RECOVER_MIN = 18
## 相位间隔的上限（帧）。超过 10 秒玩家会忘掉「它还会无敌」这件事
MAX_INTERVAL = 10 * FPS

## 比例对账的容差（取整带来的误差）
RATIO_TOL = 0.005


def read_csv(path: Path) -> dict[str, dict[str, str]]:
    with io.open(path, encoding="utf-8-sig", newline="") as fh:
        return {r["stage"].split("·")[0]: r for r in csv.DictReader(fh)}


def txt(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig")


def fld(t: str, k: str, d: str | None = None) -> str | None:
    m = re.search(rf"^{k} = (.*)$", t, re.MULTILINE)
    return d if m is None else m.group(1).strip()


def num(s: str | None, d: float = 0.0) -> float:
    if s is None:
        return d
    return float(str(s).strip().strip('&"'))


def set_field(text: str, key: str, value: str, after: str) -> str:
    """有就改、没有就插在 `after` 那行后面（保持人读起来顺的字段顺序）。"""
    line = f"{key} = {value}"
    if re.search(rf"^{key} = .*$", text, re.MULTILINE):
        return re.sub(rf"^{key} = .*$", line, text, count=1, flags=re.MULTILINE)
    m = re.search(rf"^{after} = .*$", text, re.MULTILINE)
    if m is None:
        raise SystemExit(f"❌ 插入点 `{after}` 找不到，无法插入 {key}")
    return text[: m.end()] + "\n" + line + text[m.end():]


def phase_params(phase_s: float, ratio: float, warn: int, move: int) -> dict:
    """反推相位帧数。见模块顶部的公式。"""
    frames = int(round(phase_s * FPS))
    cycle = int(round(float(frames) / ratio))
    interval = cycle - warn - frames
    if interval < 1:
        raise SystemExit(f"❌ 反推出的间隔为 {interval}（比例 {ratio} 与时长 {phase_s}s 不兼容）")
    recover = max(RECOVER_MIN, int(round(float(frames) * RECOVER_RATIO)))
    return dict(phase_frames=frames, phase_interval_frames=interval,
                phase_warn_frames=warn, phase_recover_frames=recover,
                phase_move=move)


def achieved_ratio(p: dict) -> float:
    cycle = p["phase_warn_frames"] + p["phase_frames"] + p["phase_interval_frames"]
    return float(p["phase_frames"]) / float(cycle)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    sc = read_csv(DESIGN_DATA / "enemy_scaling.csv")

    # ── 先算全表（含还没建的 ch3-5，未来直接用）──────────────────
    plan: dict[str, dict] = {}
    print(f"{'章':<5}{'boss_active':>12}{'目标占比':>9}{'相位帧':>7}{'架势':>6}"
          f"{'间隔':>7}{'收招':>6}{'实际占比':>9}{'位移':>5}")
    for chap, phase_s, warn, move in CHAPTERS:
        active = num(sc[chap]["boss_active"])
        ratio = 1.0 - active
        p = phase_params(phase_s, ratio, warn, move)
        got = achieved_ratio(p)
        print(f"{chap:<5}{active:>12.2f}{ratio:>9.2f}{p['phase_frames']:>7}"
              f"{p['phase_warn_frames']:>6}{p['phase_interval_frames']:>7}"
              f"{p['phase_recover_frames']:>6}{got:>9.3f}"
              f"{'后撤' if move else '原地':>5}")
        plan[chap] = dict(p, ratio=ratio, active=active)

    teach = phase_params(TEACH_PHASE_S, TEACH_RATIO, TEACH_WARN, 0)
    print(f"\n教学精英（{', '.join(TEACHERS)}）：1 次 {TEACH_PHASE_S}s，占比 {TEACH_RATIO:.0%}，"
          f"原地 → {teach['phase_frames']} 帧 / 间隔 {teach['phase_interval_frames']}")

    files = sorted(ENEMY_DIR.glob("*.tres"))
    unknown = [f.stem for f in files
               if f.stem not in BOSS_CHAPTER and f.stem not in TEACHERS]
    print(f"\n落地 {len(files)} 只怪：6 只 Boss + {len(TEACHERS)} 只教学精英 + "
          f"{len(unknown)} 只小怪（无相位）\n")

    written: list[dict] = []
    for f in files:
        t = txt(f)
        kind = str(fld(t, "kind")).strip('&"')
        if f.stem in BOSS_CHAPTER:
            p = plan[BOSS_CHAPTER[f.stem]]
        elif f.stem in TEACHERS:
            p = teach
        else:
            # 小怪 / 非教学精英：**明确清零**而不是「不动它」——
            # 「没写」和「写了 0」读起来一样，但前者在下一个人眼里是「忘了配」
            p = dict(phase_frames=0, phase_interval_frames=0,
                     phase_warn_frames=0, phase_recover_frames=0, phase_move=0)
        new = t
        for k, v in p.items():
            if k in ("ratio", "active"):
                continue
            new = set_field(new, k, str(int(v)), "atk_mult")
        if not dry and new != t:
            f.write_text(new, encoding="utf-8", newline="\n")
        written.append(dict(id=f.stem, kind=kind, **{k: v for k, v in p.items()
                                                     if k in ("phase_frames", "phase_interval_frames")}))

    # ── 自检 ─────────────────────────────────────────────────────
    # --dry-run 下没写文件，① 就对着「本来会写进去的值」核（written），
    # 否则它会去读旧文件、必然报错 —— 那种报错会让人以为脚本坏了
    got_frames = {w["id"]: int(w["phase_frames"]) for w in written} if dry else {
        eid: int(num(fld(txt(ENEMY_DIR / f"{eid}.tres"), "phase_frames")))
        for eid in BOSS_CHAPTER}
    print("自检：")
    bad = [f"{eid}:{got_frames[eid]}≠{plan[chap]['phase_frames']}"
           for eid, chap in BOSS_CHAPTER.items()
           if got_frames[eid] != plan[chap]["phase_frames"]]
    assert not bad, f"Boss 相位帧数没写对：{bad}"
    print("  ① 6 只 Boss 的 phase_frames 与设计表一致 ✅")

    bad = []
    for chap, p in plan.items():
        if abs(achieved_ratio(p) - (1.0 - p["active"])) > RATIO_TOL:
            bad.append(chap)
    assert not bad, f"实际占比偏离 1-boss_active 超过 {RATIO_TOL}：{bad}"
    print(f"  ② 实际占比 = 1 − boss_active（误差 ≤ {RATIO_TOL}）✅")

    over = [eid for eid, p in plan.items() if p["phase_interval_frames"] > MAX_INTERVAL]
    assert not over, f"相位间隔超过 {MAX_INTERVAL // FPS} 秒（玩家会忘掉这条机制）：{over}"
    print(f"  ③ 相位间隔 ≤ {MAX_INTERVAL // FPS}s（不会长到玩家忘掉）✅")

    trash = []
    for f in files:
        t = txt(f)
        if str(fld(t, "kind")).strip('&"') == "trash" and num(fld(t, "phase_frames")) > 0:
            trash.append(f.stem)
    assert not trash, f"小怪不许有相位（会毁掉「一批怪多久」的手感）：{trash}"
    print("  ④ 小怪一律无相位（时长预算只算 Boss / 精英）✅")

    out = [f"{w['id']}" for w in written if w["phase_frames"] > 0]
    print(f"\n带相位的怪（{len(out)}）：{', '.join(out)}")
    print(f"\n{'（dry-run，未写文件）' if dry else '✅ 已写入 data/enemies/*.tres。'}"
          "接着跑：<godot> --headless --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
