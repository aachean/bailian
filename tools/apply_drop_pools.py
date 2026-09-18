#!/usr/bin/env python3
"""把设计期的**装备掉落档次池**写进副本数据（`DungeonData.drop_tiers`，批 5）。

设计期唯一来源 = `docs/gear-v2/data/drop_by_dungeon.csv` 的 `drop_physical` 列：
砺场「普通」→ 断淬渠「普通:精良」→ 炉喉「精良」→ 残剑林「精良:优秀」→
锈蚀甬道 / 冢心「优秀」。怪身上不挂池（`EnemyData.drop_items` 只是
无副本语境时的回落 —— 测试房间用），因为同一只 walker 跨副本共用一份 data。

    python tools/apply_drop_pools.py            # 落地 + 自检
    python tools/apply_drop_pools.py --dry-run  # 只看报告

⚠️ 途径隔离（docs/adr/0016）：**极品及以上只应来自打造，不进任何实物掉落池**。
设计表现在只有 0-2 档（普通/精良/优秀），自检会拦任何 ≥3 的档次混进实物池 ——
ch3 起「极品@0.01」是**制书**（打造图纸）的掉率，不是实物，批 6 再处理。
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
STAGE_DIR = REPO / "data" / "stages"
ITEM_DIR = REPO / "data" / "items"

## 设计期表用中文名写档次；下标 = `ItemData.Tier` 枚举值
TIER_NAMES = ["普通", "精良", "优秀", "极品", "传说", "至尊"]

## 副本中文名 → 仓库里的 id（与 data/stages/dungeon_*.tres 对应）
DUNGEON_IDS = {
    "砺场": "lichang",
    "断淬渠": "duancuiqu",
    "炉喉": "luhou",
    "残剑林": "canjianlin",
    "锈蚀甬道": "xiushi",
    "冢心": "zhongxin",
}

MAX_PHYSICAL_TIER = 2      # 途径隔离：实物掉落最高「优秀」（ADR-0016）
DROP_FILE = DESIGN_DATA / "drop_by_dungeon.csv"

## 稀有材料的掉落概率：materials 列里第 i 个非精铁料 → 这个概率。
## 精铁走 EnemyData.drop_shards（保底），不进这张表
MAT_DROP_CHANCE = [0.15, 0.06, 0.03, 0.015]
MAT_IDS = {
    "玄铁": "mat_black_iron",
    "天晶": "mat_sky_crystal",
    "龙魂": "mat_dragon_soul",
    "太乙精金": "mat_taichu",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def field(text: str, key: str) -> str | None:
    m = re.search(rf"^{key} = (.*)$", text, re.MULTILINE)
    return None if m is None else m.group(1).strip()


def set_field(text: str, key: str, value: str, after: str) -> str:
    line = f"{key} = {value}"
    if re.search(rf"^{key} = .*$", text, re.MULTILINE):
        return re.sub(rf"^{key} = .*$", line, text, count=1, flags=re.MULTILINE)
    m = re.search(rf"^{after} = .*$", text, re.MULTILINE)
    if m is None:
        raise SystemExit(f"❌ 插入点 `{after}` 找不到，无法插入 {key}")
    return text[: m.end()] + "\n" + line + text[m.end():]


def tier_index(name: str) -> int:
    if name not in TIER_NAMES:
        raise SystemExit(f"❌ 设计表里的档次名不认识：{name}（已知 {TIER_NAMES}）")
    return TIER_NAMES.index(name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    with io.open(DROP_FILE, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))

    plans: dict[str, list[int]] = {}
    mat_plans: dict[str, dict[str, float]] = {}
    for row in rows:
        if str(row["status"]).strip() != "已建":
            continue                      # ch3-5 的行留着，副本没建不落
        name = str(row["dungeon"]).strip()
        did = DUNGEON_IDS.get(name)
        if did is None:
            raise SystemExit(f"❌ 设计表里的副本没有对应 id：{name}")
        raw = str(row["drop_physical"]).strip()
        if raw in ("", "-"):
            tiers: list[int] = []
        else:
            tiers = [tier_index(x) for x in raw.split(":") if x.strip()]
        plans[did] = tiers
        # 稀有材料掉落（materials 列除精铁）：第 i 个 → MAT_DROP_CHANCE[i]
        mats = [MAT_IDS[x] for x in str(row["materials"]).split(":")
                if x.strip() in MAT_IDS]
        mat_plans[did] = {m: MAT_DROP_CHANCE[i] for i, m in enumerate(mats)
                          if i < len(MAT_DROP_CHANCE)}

    # 设计表矛盾处理：断淬渠行 materials 列只写「精铁」，但同一行 note 明说
    # 「玄铁此本起零星掉」、materials.json 也标玄铁解锁章=1（ch1末）—— 以 note 为准
    if "duancuiqu" in mat_plans and "mat_black_iron" not in mat_plans["duancuiqu"]:
        mat_plans["duancuiqu"]["mat_black_iron"] = MAT_DROP_CHANCE[0]

    # ── 落地 ──────────────────────────────────────────────────
    print("副本掉落档次池（读自 drop_by_dungeon.csv）：")
    for did, tiers in plans.items():
        f = STAGE_DIR / f"dungeon_{did}.tres"
        if not f.exists():
            raise SystemExit(f"❌ 副本数据不存在：{f}")
        if not dry:
            text = read_text(f)
            arr = "Array[int]([])" if not tiers else \
                "Array[int]([%s])" % ", ".join(str(t) for t in tiers)
            text = set_field(text, "drop_tiers", arr, "scene_path")
            # 稀有材料掉落表（精铁走 EnemyData.drop_shards，不进这张表）
            mat_str = ", ".join(f'"{k}": {v}'
                                for k, v in sorted(mat_plans.get(did, {}).items()))
            text = set_field(text, "material_drops", "{%s}" % mat_str, "drop_tiers")
            with f.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        names = " / ".join(TIER_NAMES[t] for t in tiers) if tiers else "（无）"
        mats = "、".join(f"{k.split('_')[1]}{v}" for k, v
                         in sorted(mat_plans.get(did, {}).items())) or "—"
        print(f"  {did:<12} → {names}｜稀有料：{mats}")

    # ── 自检 ──────────────────────────────────────────────────
    print("\n自检：")

    # ① 途径隔离：实物池不许出现极品及以上（那些只能从打造来）
    over = {d: t for d, ts in plans.items() for t in ts if t > MAX_PHYSICAL_TIER}
    assert not over, f"途径隔离被踩：{over} —— 极品及以上只能来自打造（ADR-0016）"
    print(f"  ① 途径隔离：6 个副本的实物池全部 ≤ {TIER_NAMES[MAX_PHYSICAL_TIER]} ✅")

    # ② 每个已用档次的装备索引非空：池里写了一个档，档里却一件装备都没有，
    #    roll_drop 会一直落空 —— 怪明明「掉了」但地上什么都没有（静默失败）
    for did, tiers in plans.items():
        for t in tiers:
            n = len(list(ITEM_DIR.glob(f"*.tres")))
            # 按文件名数不出档次（档次在资源内部），这里只验「目录非空」；
            # 档次逐件校验在 Godot 侧的测试断言里做（test_m14 #9 同款思路）
            assert n > 0, "data/items 里一件装备都没有"
            _ = did, t
    n_items = len(list(ITEM_DIR.glob("*.tres")))
    print(f"  ② 装备索引源：{ITEM_DIR.relative_to(REPO)} 共 {n_items} 件（非空）✅")

    # ③ 六个已建副本都被覆盖：设计表里「已建」的行，一个都不能漏 ——
    #    漏的那个副本会静默回落到怪身上的固定池，档次就乱了
    built = [str(r["dungeon"]).strip() for r in rows if str(r["status"]).strip() == "已建"]
    missing = [n for n in built if DUNGEON_IDS.get(n) not in plans]
    assert not missing, f"这些已建副本没落池：{missing}"
    print(f"  ③ 覆盖全部已建副本：{len(built)} 个 ✅")

    print(f"\n{'（dry-run，未写文件）' if dry else '✅ 已写入 data/stages/dungeon_*.tres。'}"
          "接着跑：<godot> --headless --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
