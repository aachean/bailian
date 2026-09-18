#!/usr/bin/env python3
"""把设计期经济数据落成仓库里的 .tres（批 6）。

来源 = `docs/gear-v2/data/`：
- `materials.json`     —— 材料与制书的 id / 显示名
- `disassemble.json`   —— 分解产量（按档）
- `craft_recipes.json` —— 打造用料（66 条，用料按档统一 → 收敛成 3 行）
- `prices.json`        —— 制书买价 / 材料参考价 / 无套利铁律的原料

产出：
- `data/economy/crafting.tres`     —— 配方 + 制书买价 + 材料参考价
- `data/economy/disassemble.tres`  —— 分解产量表
（材料名进 `data/i18n/ui.csv` 的 MAT_* 行，由本脚本同步增删。）

⚠️ 两条铁律，落地时当场算（不达标直接拒绝写文件）：
1. 每档分解产量 < 该档打造成本（堵「分解→重造」白嫖）；
2. 无套利：可打造装备的卖价 ≤ 买齐材料的参考成本（打造不为刷钱）。

    python tools/apply_economy.py            # 落地 + 自检
    python tools/apply_economy.py --dry-run  # 只看报告
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN = REPO.parent / "docs" / "gear-v2" / "data"
ECON_DIR = REPO / "data" / "economy"
UI_CSV = REPO / "data" / "i18n" / "ui.csv"
SHOP_TRES = REPO / "data" / "shop.tres"

## 设计期档次名 → ItemData.Tier 枚举下标
TIER_NAMES = ["普通", "精良", "优秀", "极品", "传说", "至尊"]
## 材料显示名的 i18n key 前缀
MAT_KEY = "MAT_"


def load_json(name: str):
    return json.load(io.open(DESIGN / name, encoding="utf-8-sig"))


def tier_index(name: str) -> int:
    if name not in TIER_NAMES:
        raise SystemExit(f"❌ 不认识的档次名：{name}")
    return TIER_NAMES.index(name)


def gd_dict(d: dict[str, int]) -> str:
    """Godot tres 的 Dictionary 字面量（String key）。"""
    if not d:
        return "{}"
    items = ", ".join(f'"{k}": {v}' for k, v in sorted(d.items()))
    return "{%s}" % items


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    materials = load_json("materials.json")
    disassemble = load_json("disassemble.json")
    recipes = load_json("craft_recipes.json")
    prices = load_json("prices.json")

    mats = [m for m in materials if m.get("type") != "blueprint"]
    bps = [m for m in materials if m.get("type") == "blueprint"]
    mat_zh = {m["id"]: m["name"] for m in materials}

    # ── 分解表：tier → { mat_id: qty } ─────────────────────────
    yields: dict[str, dict[str, int]] = {}
    for row in disassemble:
        t = tier_index(row["tier"])
        yields[str(t)] = {y["material_id"]: int(y["qty"]) for y in row["yields"]}

    # ── 配方：66 条按档收敛（用料统一，抽某档任意一条核对一致性）──
    recipes_by_tier: dict[int, list[dict]] = {}
    for r in recipes:
        recipes_by_tier.setdefault(tier_index(r["tier"]), []).append(r)
    cost_by_tier: dict[str, dict[str, int]] = {}
    for t, rows in sorted(recipes_by_tier.items()):
        first = {m["material_id"]: int(m["qty"]) for m in rows[0]["materials"]}
        for r in rows[1:]:
            if {m["material_id"]: int(m["qty"]) for m in r["materials"]} != first:
                raise SystemExit(f"❌ 档 {TIER_NAMES[t]} 的用料在配方间不一致（{r['item_id']}）")
        cost_by_tier[str(t)] = first

    bp_price = {str(tier_index(k)): int(v) for k, v in prices["blueprint_buy"].items()}
    mat_value = {str(m["id"]): int(prices["material_value_ref"][m["name"]]) for m in mats}

    # 制书是**逐件**的（神裁定 2026-09-18）：66 本，名字就是装备名 ——
    # 不需要单独的数据文件：书 = 装备路径，价格按档走 blueprint_price。
    # 商店列表由 ShopPanel 从装备索引现拼，shop.tres 里不再存制书字段

    # ── 铁律 1：分解产量 < 打造成本（逐料，逐档）────────────────
    print("铁律 1：分解产量 < 同档打造成本（逐料）")
    for t in sorted(cost_by_tier, key=int):
        cost = cost_by_tier[t]
        yld = yields.get(t, {})
        bad = [mid for mid in cost if yld.get(mid, 0) >= cost[mid]]
        if bad:
            raise SystemExit(f"❌ 档 {TIER_NAMES[int(t)]}：{bad} 的分解产量 ≥ 打造成本，白嫖成立")
        print(f"  档 {TIER_NAMES[int(t)]}: " + " / ".join(
            f"{mat_zh[m]} {yld.get(m, 0)}<{cost[m]}" for m in cost) + " ✅")

    # ── 铁律 2：无套利（可打造装备卖价 ≤ 材料参考成本）──────────
    print("铁律 2：无套利（卖价 ≤ 买齐材料成本）")
    gear_price = prices["gear_price"]
    for t in sorted(cost_by_tier, key=int):
        cost = cost_by_tier[t]
        ref = sum(int(mat_value[m]) * q for m, q in cost.items())
        sell = int(gear_price[TIER_NAMES[int(t)]]) // 2
        if sell >= ref:
            raise SystemExit(f"❌ 档 {TIER_NAMES[int(t)]}：卖价 {sell} ≥ 材料成本 {ref}，套利成立")
        print(f"  档 {TIER_NAMES[int(t)]}: 卖 {sell} ≤ 料 {ref} ✅")

    # ── 材料名进 i18n ──────────────────────────────────────────
    mat_keys = {m["id"]: f"{MAT_KEY}{m['id'].removeprefix('mat_').upper()}" for m in mats}
    ui = read_text(UI_CSV)
    lines = ui.splitlines()
    keep = [l for l in lines if not l.startswith(MAT_KEY)]
    mat_lines = [f'{mat_keys[m["id"]]},{m["name"]},{m["name"]}' for m in mats]
    ui_new = "\n".join(keep + mat_lines) + "\n"
    print(f"i18n：材料名 {len(mat_lines)} 行（旧 {sum(1 for l in lines if l.startswith(MAT_KEY))} 行）")

    # ── 商店上架制书（改为：shop.tres 里**不再存制书**）──────────
    # 逐件制书（神裁定 2026-09-18）：66 本 = 可打造装备本身，列表由 ShopPanel
    # 从 `GameProgress.drop_pool` 现拼、价格按档取 crafting.tres。
    # 这里只负责把**残留的旧档位字段**从 shop.tres 清掉（幂等）
    shop = read_text(SHOP_TRES)
    if dry:
        print("\n（dry-run，未写文件）")
        return 0

    # crafting.tres / disassemble.tres
    ECON_DIR.mkdir(parents=True, exist_ok=True)
    craft = f'''[gd_resource type="Resource" script_class="CraftingData" format=3]

[ext_resource type="Script" path="res://scripts/core/crafting_data.gd" id="1_craft"]

[resource]
script = ExtResource("1_craft")
recipes = {gd_dict({k: 0 for k in cost_by_tier})}
'''
    # 嵌套结构 tres 写不了字典套字典的字面量？可以：Dictionary 里放 Dictionary。
    # 逐档手拼，保证可读：
    recipe_items = ", ".join(
        f'"{t}": {gd_dict(v)}' for t, v in sorted(cost_by_tier.items(), key=lambda x: int(x[0])))
    craft = craft.replace(
        f"recipes = {gd_dict({k: 0 for k in cost_by_tier})}",
        f"recipes = {{{recipe_items}}}")
    craft += f"blueprint_price = {gd_dict(bp_price)}\n"
    craft += f"material_value = {gd_dict(mat_value)}\n"
    mk = ", ".join(f'"{k}": &"{v}"' for k, v in mat_keys.items())
    craft += f"material_name_key = {{{mk}}}\n"
    (ECON_DIR / "crafting.tres").write_text(craft, encoding="utf-8", newline="\n")

    yield_items = ", ".join(
        f'"{t}": {gd_dict(v)}' for t, v in sorted(yields.items(), key=lambda x: int(x[0])))
    dis = f'''[gd_resource type="Resource" script_class="DisassembleData" format=3]

[ext_resource type="Script" path="res://scripts/core/disassemble_data.gd" id="1_dis"]

[resource]
script = ExtResource("1_dis")
yields = {{{yield_items}}}
'''
    (ECON_DIR / "disassemble.tres").write_text(dis, encoding="utf-8", newline="\n")
    print(f"✅ 写入 {ECON_DIR.relative_to(REPO)}/crafting.tres、disassemble.tres")

    # 清掉 shop.tres 里残留的档位制书字段（逐件化之前写的；没有就跳过）
    shop = re.sub(r"^blueprint_tiers = .*\n?", "", shop, count=1, flags=re.M)
    SHOP_TRES.write_text(shop, encoding="utf-8", newline="\n")
    print(f"✅ 刷新 {SHOP_TRES.relative_to(REPO)}（档位制书字段已清，逐件列表由面板现拼）")

    UI_CSV.write_text(ui_new, encoding="utf-8", newline="\n")
    print(f"✅ 写入 {UI_CSV.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
