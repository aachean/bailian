#!/usr/bin/env python3
"""把装备 v2 的设计期产物落地进 `bailian/data`（ADR-0021 批 1）。

设计期唯一来源 = `docs/gear-v2/`（JSON 在 `data/`，导出的 `.tres` 在 `tres-out/`）。
本脚本**只做搬运与重写**，不产生任何数值 —— 数值改了要重跑 `data-gen/run_all.cjs`，
它最后一步 `export_tres.cjs` 会刷新 `tres-out/`，然后再跑本脚本。

做的事：
1. `tres-out/items/*.tres` → `data/items/`（先清掉旧的 9 件 v1 装备）
2. `data/i18n/ui.csv`：删掉旧 `ITEM_*`、把 4 个旧 `SLOT_*` 换成 8 个新槽、补 132 行装备名
3. `data/enemies/*.tres` 的 `drop_items`：按「档位池」重写（全部 4 种武器 + 防具饰品）

自检（任一条不过就非零退出，别把坏数据当成功）：
- 落地件数 = 132，且每件的 name_key 在 ui.csv 里有一行
- 掉落池引用的路径**全部存在**（引用不存在的资源 = 运行期静默不掉）
- 掉落池里**不出现极品及以上**（ADR-0016：那三档只出制书，不掉实物）

用法：
    python tools/apply_gear_v2.py            # 落地 + 自检
    python tools/apply_gear_v2.py --dry-run  # 只看报告，不写文件
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN = REPO.parent / "docs" / "gear-v2"
SRC_ITEMS = DESIGN / "tres-out" / "items"
SRC_MANIFEST = DESIGN / "tres-out" / "manifest.json"
DST_ITEMS = REPO / "data" / "items"
UI_CSV = REPO / "data" / "i18n" / "ui.csv"
ENEMY_DIR = REPO / "data" / "enemies"

# ── 槽位（v2 八槽）─────────────────────────────────────────────
SLOTS = [
    ("SLOT_WEAPON", "武器", "Weapon"),
    ("SLOT_HELM", "头盔", "Helm"),
    ("SLOT_CHEST", "胸甲", "Chest"),
    ("SLOT_LEGS", "护腿", "Legs"),
    ("SLOT_BOOTS", "靴子", "Boots"),
    ("SLOT_RING", "戒指", "Ring"),
    ("SLOT_NECKLACE", "项链", "Necklace"),
    ("SLOT_BRACELET", "手镯", "Bracelet"),
]

# 旧槽位 key（写完新槽后必须消失，否则界面沿用旧名）
RETIRED_SLOT_KEYS = {"SLOT_ARMOR", "SLOT_TRINKET"}

# ── 132 个中文名 → 英文名。界面走 tr(name_key)，这里只补 en 列 ────
EN_NAMES = {
    # 普通
    "铁剑": "Iron Sword", "制式剑": "Standard Sword",
    "铁刀": "Iron Blade", "环首刀": "Ring-Pommel Blade",
    "木弓": "Wooden Bow", "猎弓": "Hunter's Bow",
    "桃木杖": "Peachwood Staff", "学徒杖": "Apprentice Staff",
    "皮盔": "Leather Helm", "铁盔": "Iron Helm",
    "布衣": "Cloth Robe", "皮甲": "Leather Armor",
    "皮护腿": "Leather Leggings", "铁护腿": "Iron Leggings",
    "布鞋": "Cloth Shoes", "皮靴": "Leather Boots",
    "铜戒": "Copper Ring", "铁戒": "Iron Ring",
    "麻绳项链": "Hemp Cord Necklace", "骨坠": "Bone Pendant",
    "木镯": "Wooden Bracelet", "铁镯": "Iron Bracelet",
    # 精良
    "精钢剑": "Fine Steel Sword", "百炼剑": "Hundred-Forged Sword",
    "精钢刀": "Fine Steel Blade", "雁翎刀": "Goose-Feather Blade",
    "角弓": "Horn Bow", "铁胎弓": "Iron-Backed Bow",
    "白蜡杖": "White Wax Staff", "精钢法杖": "Fine Steel Staff",
    "精钢盔": "Fine Steel Helm", "链甲盔": "Chainmail Helm",
    "铁甲": "Iron Armor", "锁子甲": "Chainmail",
    "精钢护腿": "Fine Steel Leggings", "链甲护腿": "Chainmail Leggings",
    "铁靴": "Iron Boots", "精钢靴": "Fine Steel Boots",
    "精钢戒": "Fine Steel Ring", "玉石戒": "Jade Ring",
    "玉佩": "Jade Pendant", "银链": "Silver Chain",
    "银镯": "Silver Bracelet", "精钢镯": "Fine Steel Bracelet",
    # 优秀
    "玄铁剑": "Dark Iron Sword", "青霜剑": "Frostblue Sword",
    "玄铁刀": "Dark Iron Blade", "斩马刀": "Horse-Cleaver",
    "玄铁弓": "Dark Iron Bow", "穿云弓": "Cloudpiercer",
    "寒铁杖": "Cold Iron Staff", "紫晶杖": "Amethyst Staff",
    "玄铁盔": "Dark Iron Helm", "寒铁盔": "Cold Iron Helm",
    "玄铁甲": "Dark Iron Armor", "寒铁甲": "Cold Iron Armor",
    "玄铁护腿": "Dark Iron Leggings", "寒铁护腿": "Cold Iron Leggings",
    "玄铁靴": "Dark Iron Boots", "疾风靴": "Gale Boots",
    "玄铁戒": "Dark Iron Ring", "琥珀戒": "Amber Ring",
    "水晶项链": "Crystal Necklace", "玄玉坠": "Dark Jade Pendant",
    "玄铁镯": "Dark Iron Bracelet", "古玉镯": "Ancient Jade Bracelet",
    # 极品（只出制书，但名字仍要备好，制书界面会用到）
    "寒月剑": "Frostmoon Sword", "破军剑": "Army-Breaker Sword",
    "赤霄刀": "Red Sky Blade", "贪狼刀": "Wolf-Devourer",
    "流星弓": "Meteor Bow", "逐日弓": "Sun-Chaser Bow",
    "幽冥杖": "Netherworld Staff", "赤炎杖": "Blazing Staff",
    "寒霜盔": "Frost Helm", "赤铜盔": "Red Copper Helm",
    "玄武甲": "Black Tortoise Armor", "赤金甲": "Red Gold Armor",
    "玄武护腿": "Black Tortoise Leggings", "赤铜护腿": "Red Copper Leggings",
    "追云靴": "Cloud-Chaser Boots", "踏雪靴": "Snow-Treader Boots",
    "赤金戒": "Red Gold Ring", "幽蓝戒": "Deep Blue Ring",
    "灵犀坠": "Heartlink Pendant", "赤金锁": "Red Gold Chain",
    "赤金镯": "Red Gold Bracelet", "寒玉镯": "Cold Jade Bracelet",
    # 传说
    "龙渊剑": "Dragon Abyss Sword", "湛卢剑": "Zhanlu Sword",
    "屠龙刀": "Dragon Slayer Blade", "偃月刀": "Crescent Moon Blade",
    "后羿弓": "Houyi's Bow", "落日弓": "Sunset Bow",
    "朱雀杖": "Vermilion Bird Staff", "玄冥杖": "Dark Water Staff",
    "玄武盔": "Black Tortoise Helm", "天龙盔": "Sky Dragon Helm",
    "麒麟甲": "Qilin Armor", "应龙甲": "Yinglong Armor",
    "麒麟护腿": "Qilin Leggings", "天龙护腿": "Sky Dragon Leggings",
    "缩地靴": "Earth-Shrinker Boots", "凌波靴": "Wave-Stepper Boots",
    "龙纹戒": "Dragon-Pattern Ring", "凤鸣戒": "Phoenix-Cry Ring",
    "盘龙佩": "Coiled Dragon Pendant", "凤血玉": "Phoenix Blood Jade",
    "盘龙镯": "Coiled Dragon Bracelet", "凤翎镯": "Phoenix Plume Bracelet",
    # 至尊
    "诛仙剑": "Immortal-Slayer Sword", "轩辕剑": "Xuanyuan Sword",
    "开天刀": "World-Opener Blade", "苍穹刀": "Firmament Blade",
    "天狼弓": "Sirius Bow", "陨星弓": "Meteorite Bow",
    "混沌杖": "Chaos Staff", "太极杖": "Taiji Staff",
    "昆仑盔": "Kunlun Helm", "帝胄": "Imperial Casque",
    "天蚕甲": "Sky Silkworm Armor", "不灭金身": "Undying Golden Body",
    "昆仑护腿": "Kunlun Leggings", "帝胄护腿": "Imperial Greaves",
    "登仙靴": "Ascension Boots", "缩地金靴": "Golden Earth-Shrinker Boots",
    "混沌戒": "Chaos Ring", "乾坤戒": "Qiankun Ring",
    "星辰链": "Star Chain", "鸿蒙珠": "Primordial Orb",
    "乾坤镯": "Qiankun Bracelet", "混沌镯": "Chaos Bracelet",
}

# ── 掉落实物只到「优秀」（ADR-0016）。档位号 0..5 ────────────────
TIER_DROPABLE = {0, 1, 2}
TIER_ENUM = {"普通": 0, "精良": 1, "优秀": 2, "极品": 3, "传说": 4, "至尊": 5}

# ── 每个怪的掉落池用哪几档。批 5 会改成「逐副本加权池」，这里先给它一个
#    与 drop_by_dungeon.csv 量级一致的最小可用版本 ────────────────
POOL_BY_ENEMY = {
    # 小怪 → 普通
    "walker": [0], "walker_elite": [0], "dasher": [0], "dasher_elite": [0],
    "spearman": [0], "caster": [0], "brute": [0],
    # 精英 / 重甲 → 普通 + 精良
    "brute_elite": [0, 1], "brute_heavy": [0, 1],
    # 第一章 Boss → 精良
    "boss": [1], "boss2": [1], "boss_luhou": [1],
    # 第二章 Boss → 优秀
    "boss_canjian": [2], "boss_xiushi": [2], "boss_zhongxin": [2],
}


# ── v1 的 9 个装备路径 → v2 里语义最接近的那一件（按 display_name 查）──
# 为什么必须有这张表：**引用旧路径的不只是掉落池**，还有
#   ① `data/characters/*.tres` 的 starting_weapon（开局武器！）
#   ② `data/dialogue/smith_intro.tres` 的 give_item（老铁匠给的第一把武器）
#   ③ `data/shop.tres` 的 stock（整张货架）
# 漏一处就是「开局两手空空 / 商店永远空着」，而且都不报错。
OLD_ITEM_ALIAS = {
    "iron_sword": "铁剑",
    "wind_bow": "木弓",
    "flame_blade": "玄铁剑",
    "iron_helm": "铁盔",
    "leather_cap": "皮盔",
    "iron_armor": "铁甲",
    "cloth_robe": "布衣",
    "wood_charm": "木镯",
    "jade_talisman": "玄玉坠",
}

# ── 商店货架（v1 卖 7 件装备）。批 6 会换成「低阶材料 + 三档制书 + 消耗品」，
#    在那之前先摆出全档「普通」件，免得商店是一间空店 ──────────────
SHOP_STOCK_TIER = 0


def item_path_str(it: dict) -> str:
    return f'res://data/items/{it["path"].name}'


def read_text(path: Path) -> str:
    """读 .tres / .csv。带 BOM 的当没有 —— Godot 与编辑器写出来的都可能带"""
    return path.read_text(encoding="utf-8-sig")


def rewrite_old_refs(items: list[dict], en_files: list[Path], dry: bool) -> None:
    """把全仓库 `data/` 下对旧装备路径的引用换成 v2 的新路径。"""
    by_name = {it["display_name"]: item_path_str(it) for it in items}
    mapping: dict[str, str] = {}
    for stem, zh in OLD_ITEM_ALIAS.items():
        new = by_name.get(zh)
        if new is None:
            raise SystemExit(f"❌ 别名字典里的「{zh}」在 v2 数据里找不到对应件")
        mapping[f"res://data/items/{stem}.tres"] = new

    targets = sorted(REPO.glob("data/**/*.tres"))
    hit_files = 0
    hit_refs = 0
    for tres in targets:
        text = read_text(tres)
        if not text or "res://data/items/" not in text:
            continue
        if tres.parent == DST_ITEMS:
            continue                                  # 装备自己不算引用
        new_text = text
        for old, new in mapping.items():
            if old in new_text:
                hit_refs += new_text.count(old)
                new_text = new_text.replace(old, new)
        if new_text != text:
            hit_files += 1
            print(f"  {tres.relative_to(REPO)}：引用已改写")
            if not dry:
                with tres.open("w", encoding="utf-8", newline="\n") as fh:
                    fh.write(new_text)
    print(f"  旧路径引用改写：{hit_files} 个文件 / {hit_refs} 处")

    # 货架：每个武器类型 + 每个部位各摆一件「普通」—— 11 件，与 v1 货架（7 件）
    # 一个量级。批 6 会换成「低阶材料 + 三档制书 + 消耗品」
    picked: dict[str, str] = {}
    for it in items:
        if int(it["tier"]) != SHOP_STOCK_TIER:
            continue
        key = it.get("weapon_type") or ("slot" + str(it.get("slot")))
        picked.setdefault(key, item_path_str(it))
    stock = sorted(picked.values())
    shop = REPO / "data" / "shop.tres"
    text = read_text(shop)
    new_line = "stock = Array[String]([%s])" % ", ".join(f'"{p}"' for p in stock)
    if re.search(r"^stock = .*$", text, re.MULTILINE):
        text = re.sub(r"^stock = .*$", new_line, text, count=1, flags=re.MULTILINE)
    else:
        text = text.replace("[resource]", "[resource]\n" + new_line, 1)
    if not dry:
        with shop.open("w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    print(f"  shop.tres 货架：{len(stock)} 件（每种武器 + 每个部位各一件「普通」）")

    # 开局武器：按角色的 weapon_type 取该类型的「普通」武器 ——
    # 拿错了角色开局就挥不动自己的武器（can_equip 会拦住）。
    # **优先沿用 v1 那把**（铁剑 / 木弓）而不是「排序后的第一件」：
    # 让开局武器由字典顺序决定，改一次数据就可能悄悄换掉玩家的第一把剑
    by_type: dict[str, str] = {}
    for it in items:
        wt = it.get("weapon_type")
        if wt and int(it["tier"]) == 0:
            by_type.setdefault(wt, item_path_str(it))
    for stem, zh in OLD_ITEM_ALIAS.items():
        new = by_name[zh]
        for it in items:
            # **必须限定普通档** —— 别名字典里还有 flame_blade→玄铁剑（优秀档剑），
            # 不卡档位的话它会把「开局武器」写成一把 45 级的剑
            if item_path_str(it) == new and it.get("weapon_type") and int(it["tier"]) == 0:
                by_type[it["weapon_type"]] = new
    for path in sorted((REPO / "data" / "characters").glob("*.tres")):
        text = read_text(path)
        m = re.search(r'^weapon_type = &"([^"]+)"', text, re.MULTILINE)
        if not m:
            continue
        wt = m.group(1)
        new = by_type.get(wt)
        if new is None:
            raise SystemExit(f"❌ {path.stem}: 武器类型 {wt} 在 v2 里没有普通档武器")
        new_text = re.sub(r'^starting_weapon = ".*"$',
                          f'starting_weapon = "{new}"', text, count=1, flags=re.MULTILINE)
        if new_text != text:
            print(f"  {path.name}：开局武器 → {new.rsplit('/', 1)[-1]}（{wt}）")
            if not dry:
                with path.open("w", encoding="utf-8", newline="\n") as fh:
                    fh.write(new_text)

    # 老铁匠给的第一把武器：给剑士那把（剧情是「拿着，去练手」）
    dia = REPO / "data" / "dialogue" / "smith_intro.tres"
    if dia.exists():
        text = read_text(dia)
        new = by_type.get("sword")
        new_text = re.sub(r'^give_item = ".*"$', f'give_item = "{new}"',
                          text, count=1, flags=re.MULTILINE)
        if new_text != text:
            print(f"  smith_intro.tres：赠剑 → {new.rsplit('/', 1)[-1]}")
            if not dry:
                with dia.open("w", encoding="utf-8", newline="\n") as fh:
                    fh.write(new_text)

    # ── 全局自检：data/ 下任何一个装备引用都必须能落在磁盘上 ────────
    dangling = []
    for tres in targets:
        if tres.parent == DST_ITEMS:
            continue
        for ref in re.findall(r'"(res://data/items/[^"]+)"', read_text(tres)):
            if not (REPO / ref.removeprefix("res://")).exists():
                dangling.append((tres.relative_to(REPO).as_posix(), ref))
    if dangling:
        for f, r in dangling[:10]:
            print(f"  ❌ {f} → {r}")
        raise SystemExit(f"❌ data/ 下有 {len(dangling)} 处装备引用指向不存在的资源")
    print("  全局检查：data/ 下所有装备引用都存在 ✅")



def parse_item(tres: Path) -> dict:
    """只取自检要用的几个字段。不引 Godot —— 这是个纯搬运脚本。"""
    text = read_text(tres)
    out: dict = {"path": tres}
    for key in ("id", "name_key", "display_name", "slot", "tier", "weapon_type"):
        m = re.search(rf"^{key} = (.+)$", text, re.MULTILINE)
        if m:
            out[key] = m.group(1).strip().strip('"').strip('&"')
    return out


def build_ui_csv(items: list[dict], dry: bool) -> list[str]:
    """重写 ui.csv：换槽位 key、去旧装备名、补 132 行新装备名。"""
    lines = read_text(UI_CSV).splitlines()
    header = lines[0]
    body = lines[1:]

    kept: list[str] = []
    dropped: list[str] = []
    for line in body:
        if not line.strip():
            continue
        key = line.split(",", 1)[0].strip()
        if key.startswith("ITEM_"):
            dropped.append(key)
            continue
        if key in RETIRED_SLOT_KEYS:
            dropped.append(key)
            continue
        kept.append(line)

    # 槽位行插到原来的位置（紧跟第一条 SLOT_ 的位置；找不到就附加在末尾）
    anchor = next((i for i, l in enumerate(kept) if l.startswith("SLOT_")), len(kept))
    slot_rows = [f'{k},"{zh}","{en}"' for k, zh, en in SLOTS]

    new_items = []
    missing_en = []
    for it in sorted(items, key=lambda x: x["name_key"]):
        zh = it["display_name"]
        en = EN_NAMES.get(zh)
        if en is None:
            missing_en.append(zh)
            en = zh
        new_items.append(f'{it["name_key"]},"{zh}","{en}"')

    if missing_en:
        raise SystemExit(f"❌ 有中文名没有英文对照：{missing_en}")

    out_lines = [header]
    out_lines.extend(kept[:anchor])
    out_lines.extend(slot_rows)
    out_lines.extend(kept[anchor:])
    out_lines.extend(new_items)

    print(f"  ui.csv：删除 {len(dropped)} 行旧键（{', '.join(dropped[:6])}…）"
          f"，插入 {len(slot_rows)} 个槽位，追加 {len(new_items)} 行装备名")
    if not dry:
        UI_CSV.write_text("\r\n".join(out_lines) + "\r\n", encoding="utf-8-sig", newline="")
    return out_lines


def rebuild_enemy_pools(items: list[dict], dry: bool) -> None:
    """按档位池重写每个怪 drop_items —— 含 4 种武器，防具饰品也给上。"""
    by_tier: dict[int, list[str]] = {}
    for it in items:
        by_tier.setdefault(int(it["tier"]), []).append(
            f'"res://data/items/{it["path"].name}"'
        )
    for t in by_tier:
        by_tier[t].sort()

    touched = 0
    for tres in sorted(ENEMY_DIR.glob("*.tres")):
        stem = tres.stem
        tiers = POOL_BY_ENEMY.get(stem)
        if tiers is None:
            print(f"  ⚠️ {stem}: 没写进 POOL_BY_ENEMY，跳过（掉落池保持不变）")
            continue
        pool: list[str] = []
        for t in tiers:
            if t not in TIER_DROPABLE:
                raise SystemExit(f"❌ {stem}: 池里含档位 {t}，ADR-0016 规定极品及以上只出制书")
            pool.extend(by_tier.get(t, []))
        if not pool:
            raise SystemExit(f"❌ {stem}: 档位池算出来是空的")

        text = read_text(tres)
        new_line = "drop_items = Array[String]([%s])" % ", ".join(pool)
        if re.search(r"^drop_items = .*$", text, re.MULTILINE):
            text = re.sub(r"^drop_items = .*$", new_line, text, count=1, flags=re.MULTILINE)
        else:
            text = text.replace("[resource]", "[resource]\n" + new_line, 1)
        if not dry:
            with tres.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        touched += 1
        print(f"  {stem}: 池 = {len(pool)} 件（档位 {tiers}）")
    print(f"  掉落池重写：{touched} 个怪")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    src = sorted(SRC_ITEMS.glob("*.tres"))
    if len(src) != 132:
        raise SystemExit(f"❌ tres-out/items 里是 {len(src)} 件，应当是 132 件 —— 先跑 run_all.cjs")

    print("[1/4] 搬运 {n} 件 → {d}".format(n=len(src), d=DST_ITEMS.relative_to(REPO)))
    old = sorted(DST_ITEMS.glob("*.tres"))
    print(f"      清掉 v1 的 {len(old)} 件：{', '.join(p.stem for p in old)}")
    if not dry:
        for p in old:
            p.unlink()
        DST_ITEMS.mkdir(parents=True, exist_ok=True)
        for p in src:
            shutil.copy2(p, DST_ITEMS / p.name)

    items = [parse_item(p) for p in src]
    tiers = {}
    for it in items:
        tiers[int(it["tier"])] = tiers.get(int(it["tier"]), 0) + 1
    print(f"      档位分布：{ {k: tiers[k] for k in sorted(tiers)} }")

    print("[2/4] 重写 i18n")
    ui_lines = build_ui_csv(items, dry)

    print("[3/4] 重写掉落池")
    rebuild_enemy_pools(items, dry)

    print("[4/4] 改写旧装备引用（开局武器 / 赠剑 / 货架）+ 全局引用检查")
    rewrite_old_refs(items, [], dry)

    # ── 自检 ──────────────────────────────────────────────────
    print("\n自检：")
    dest = sorted(DST_ITEMS.glob("*.tres")) if not dry else src
    assert len(dest) == 132, f"落地件数 {len(dest)} != 132"
    print(f"  ① 落地 132 件 ✅（{'dry-run 用源目录' if dry else DST_ITEMS.name}）")

    csv_keys = set()
    for line in ui_lines[1:]:
        if line.strip():
            csv_keys.add(line.split(",", 1)[0].strip())
    missing = [it["name_key"] for it in items if it["name_key"] not in csv_keys]
    assert not missing, f"ui.csv 缺这些 key：{missing[:5]}"
    print("  ② 132 个 name_key 在 ui.csv 都有行 ✅")

    leaked = sorted(RETIRED_SLOT_KEYS & csv_keys)
    assert not leaked, f"旧槽位 key 没删干净：{leaked}"
    print("  ③ 旧槽位 key 已清 ✅")

    bad = []
    for tres in sorted(ENEMY_DIR.glob("*.tres")):
        m = re.search(r"^drop_items = Array\[String\]\(\[(.*)\]\)", read_text(tres), re.MULTILINE)
        for ref in re.findall(r'"(res://[^"]+)"', m.group(1) if m else ""):
            if not (REPO / ref.removeprefix("res://")).exists():
                bad.append((tres.stem, ref))
    assert not bad, f"掉落池引用了不存在的资源：{bad[:5]}"
    print("  ④ 掉落池引用的资源全部存在 ✅")

    print(f"\n{'（dry-run，未写任何文件）' if dry else '✅ 落地完成。'}"
          "接着跑：<godot> --headless --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
