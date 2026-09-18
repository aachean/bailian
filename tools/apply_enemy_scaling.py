#!/usr/bin/env python3
"""把敌人 v2 数值从设计期表落地进 `bailian/data/enemies/`（ADR-0019 / ADR-0020，批 4）。

设计期唯一来源 = `docs/gear-v2/data/`：
- `enemy_scaling.csv`   —— 攻击侧：血量（B 机制分担口径）+ `boss_def`
- `combat_defense.csv`  —— 受击侧：`need_trash_atk / need_elite_atk / need_boss_atk`

本脚本把这两张表按「怪的 kind + 所属章节」折算成每只怪的
`max_hp / defense / atk_flat / atk_mult`，**写进 `.tres`**。
运行期只读 `.tres`（设计原则 4.4：数值的唯一真相在资源）。

    python tools/apply_enemy_scaling.py            # 落地 + 自检
    python tools/apply_enemy_scaling.py --dry-run  # 只看报告

⚠️ 两条红线（自检会拦）：
1. **`def` 不许越过 150** —— 护甲曲线 `def/(100+def)` 在 150 就到 0.6 封顶，
   再堆只是把红线的余量吃掉，不会让怪更肉（ADR-0019）。
2. **「别只堆血」** —— 血走 B 口径（比 A 纯堆血少一半上下），
   难度靠 def + 相位机制分担（design-principles 4.3）。
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

# ── 计划表：每只怪属于哪一类、吃哪一章的阶段值、它的相对血量与个体倍率 ──
#
# 元组 = (kind, chapter, hp_rel, atk_mult, level_ref)
#
# - `hp_rel`：同类之内的相对血量（现值的比例）。**表里给的是阶段基准**，
#   而 dasher 比 walker 脆、brute 比 walker 肉是手感的一部分 ——
#   直接抹平会让「疾行者更快更脆」这条断言（test_m3 #4）变成谎话。
#   只对**小怪/精英**生效（`level_ref = 0`）。
# - `atk_mult`：同类之内的单发倍率。快攻怪低（0.85）、重甲怪高（1.2）。
# - `level_ref`：**这只怪所在副本的推荐等级**（`DungeonData.rec_level`）。
#   非 0 时血量按「该等级的玩家战力 ÷ 章节锚点等级的战力」缩放。
#   为什么 Boss 必须走这条：一张 chapter 行只有一个 `level` 锚点（ch1 = lv20），
#   而 ch1 横跨 lv1（砺场）到 lv25（炉喉）—— 拿 lv20 的值给**第一个** Boss 会让它
#   血量翻到 11 倍、变成一场 80 秒的拉锯。小怪/精英跨章共用同一份 data，
#   没法逐副本插值，所以先按章节基准，逐副本变体见批 4b。
PLAN: dict[str, tuple[str, str, float, float, int]] = {
    # id:            (kind,   chapter, hp_rel, atk_mult, level_ref)
    "walker":        ("trash", "ch1", 1.00, 1.00, 0),
    "dasher":        ("trash", "ch1", 0.60, 0.85, 0),   # 快、脆
    "spearman":      ("trash", "ch1", 0.73, 0.90, 0),   # 远程，靠走位施压
    "caster":        ("trash", "ch1", 0.87, 0.90, 0),
    "brute":         ("trash", "ch1", 2.13, 1.20, 0),   # 重甲慢

    "walker_elite":  ("elite", "ch1", 0.44, 1.00, 0),
    "dasher_elite":  ("elite", "ch1", 0.28, 0.85, 0),
    "brute_elite":   ("elite", "ch1", 1.00, 1.20, 0),
    "brute_heavy":   ("elite", "ch1", 0.87, 1.15, 0),

    # Boss：rec_level 取自 drop_by_dungeon.csv（砺场 1 / 断淬渠 12 / 炉喉 25 /
    # 残剑林 30 / 锈蚀甬道 42 / 冢心 55）
    "boss":          ("boss", "ch1", 1.0, 1.00, 1),
    "boss2":         ("boss", "ch1", 1.0, 1.05, 12),
    "boss_luhou":    ("boss", "ch1", 1.0, 1.10, 25),

    "boss_canjian":  ("boss", "ch2", 1.0, 1.00, 30),
    "boss_xiushi":   ("boss", "ch2", 1.0, 1.05, 42),
    "boss_zhongxin": ("boss", "ch2", 1.0, 1.10, 55),
}

## 精英吃半个 Boss 档的护甲压力。表里只给了 `boss_def`，
## 这条是**本脚本补的档位**（写在这里而不是藏进代码）：小怪 0 → 精英半档 → Boss 满档
ELITE_DEF_RATIO = 0.5

MAX_DEFENSE = 150           # 护甲曲线到 0.6 的那个点，超过无意义
MIN_ARMOR_FACTOR = 0.4      # = 1 − 0.6，护甲系数不许比它更低

## 成长曲线的唯一真相（等级%）。**不在这儿抄一份数字** —— 从 .tres 读
PROGRESSION = REPO / "data" / "progression.tres"

## ── 副本 → (章节, 推荐等级) ──────────────────────────────────
## 写 `DungeonData.enemy_atk_scale` 用。`rec_level` 要与 `data/stages/*.tres`
## 里的值一致（自检 ⑥ 盯着）；砺场那份连 rec_level 都省了（默认 1），照样对得上
DUNGEONS: dict[str, tuple[str, int]] = {
    "lichang":    ("ch1", 1),
    "duancuiqu":  ("ch1", 12),
    "luhou":      ("ch1", 25),
    "canjianlin": ("ch2", 30),
    "xiushi":     ("ch2", 42),
    "zhongxin":   ("ch2", 55),
}
STAGE_DIR = REPO / "data" / "stages"


def lv_pct(level: int, gain: float, falloff: float) -> float:
    """该等级贡献的攻击百分比，与 `ProgressionData.growth()` 同一个公式。

    只用它当**玩家战力的代理**（等级是成长的主轴，装备那一份在各章内部近似恒定）。
    拿它给 Boss 血量按副本等级插值：同一章里靠后的副本，玩家更强，Boss 也该更厚。
    """
    n = max(level - 1, 0)
    if n <= 0:
        return 0.0
    return gain * (1.0 - falloff ** n)


def player_hp_at(level: int, hp_gain: float, hp_falloff: float, base_hp: float) -> float:
    """该等级的玩家裸血上限（不含装备词条），与 `ProgressionData.hp_at()` 同公式。

    「玩家承受力」的代理 —— `combat_defense.csv` 的 `need_*_atk` 就是按
    「这一级的玩家要挨多少下」定出来的，所以伤害跨等级缩放必须用它，
    而不是用攻击力（那会把「怪打人有多疼」跟「玩家打怪有多疼」锁死在一起）。
    """
    n = max(level - 1, 0)
    growth = 0.0 if n <= 0 else hp_gain * (1.0 - hp_falloff ** n)
    return base_hp + growth


def read_csv(path: Path) -> dict[str, dict[str, str]]:
    """按**章节前缀**建索引：表里 `stage` 写的是 `ch1·淬火岭`，脚本里只认 `ch1`。"""
    with io.open(path, encoding="utf-8-sig", newline="") as fh:
        out = {}
        for row in csv.DictReader(fh):
            out[str(row["stage"]).split("·")[0].strip()] = row
        return out


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def field(text: str, key: str) -> str | None:
    m = re.search(rf"^{key} = (.*)$", text, re.MULTILINE)
    return None if m is None else m.group(1).strip()


def set_field(text: str, key: str, value: str, after: str) -> str:
    """有就改、没有就插在 `after` 那行后面（保持人读起来顺的字段顺序）。"""
    line = f"{key} = {value}"
    if re.search(rf"^{key} = .*$", text, re.MULTILINE):
        return re.sub(rf"^{key} = .*$", line, text, count=1, flags=re.MULTILINE)
    m = re.search(rf"^{after} = .*$", text, re.MULTILINE)
    if m is None:
        raise SystemExit(f"❌ 插入点 `{after}` 找不到，无法插入 {key}")
    return text[: m.end()] + "\n" + line + text[m.end():]


def skill_damage(text: str) -> int:
    """这只怪「一次攻击自带的基准伤害」。

    近战看 `attack_skill.damage`；**纯远程怪 `attack_skill = null`**（掷矛手 / 术士
    用的是 spearman.gd 的投掷管线），它的整份伤害都在 `projectile_damage` 里。
    两种都只代表「这一招自带的份」，整体重标的那一份由 `atk_flat` 补 ——
    所以这里必须减掉它，否则同一档里技能越重的怪总伤害越高得没道理。
    """
    if re.search(r"^attack_skill = null$", text, re.MULTILINE):
        d = field(text, "projectile_damage")
        if d is None:
            raise SystemExit("❌ 纯远程怪却没有 projectile_damage")
        return int(d)
    m = re.search(r'path="(res://data/skills/[^"]+)"', text)
    if m is None:
        raise SystemExit("❌ 找不到 attack_skill 引用")
    sp = REPO / m.group(1).removeprefix("res://")
    d = field(read_text(sp), "damage")
    if d is None:
        raise SystemExit(f"❌ {sp.name} 里没有 damage")
    return int(d)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    dry = args.dry_run

    scaling = read_csv(DESIGN_DATA / "enemy_scaling.csv")
    defense = read_csv(DESIGN_DATA / "combat_defense.csv")

    prog = read_text(PROGRESSION)
    atk_gain = float(field(prog, "atk_gain") or 2.1)
    atk_falloff = float(field(prog, "atk_falloff") or 0.96)
    hp_gain = float(field(prog, "hp_gain") or 750.0)
    hp_falloff = float(field(prog, "hp_falloff") or 0.97)
    base_hp = float(field(prog, "base_hp") or 100.0)
    print(f"成长曲线（读自 progression.tres）：atk_gain={atk_gain} "
          f"falloff={atk_falloff}｜hp_gain={hp_gain:.0f} base={base_hp:.0f}")

    files = sorted(ENEMY_DIR.glob("*.tres"))
    missing = [f.stem for f in files if f.stem not in PLAN]
    if missing:
        raise SystemExit(f"❌ 这些怪没被分到类：{missing} —— 补进 PLAN 再跑")
    extra = [k for k in PLAN if not (ENEMY_DIR / f"{k}.tres").exists()]
    if extra:
        raise SystemExit(f"❌ PLAN 里有不存在的怪：{extra}")

    print(f"设计期表：{len(scaling)} 章 / {len(defense)} 行；落地 {len(files)} 只怪\n")
    rows: list[dict] = []
    for f in files:
        kind, chap, hp_rel, atk_mult, level_ref = PLAN[f.stem]
        text = read_text(f)
        sc, df = scaling[chap], defense[chap]

        # ── 血量：B 机制分担口径（不是 hp_boss_A 的纯堆血）──
        hp_base = {"trash": int(sc["hp_trash"]),
                   "elite": int(sc["hp_elite_B"]),
                   "boss": int(sc["hp_boss_B"])}[kind]
        if level_ref > 0:
            anchor = int(sc["level"])
            hp = int(round(hp_base
                           * (1.0 + lv_pct(level_ref, atk_gain, atk_falloff))
                           / (1.0 + lv_pct(anchor, atk_gain, atk_falloff))))
        else:
            hp = int(round(hp_base * hp_rel))

        # ── 防御：小怪 0 / 精英半档 / Boss 满档 ──
        if kind == "trash":
            defense_v = 0
        elif kind == "elite":
            defense_v = int(round(float(sc["boss_def"]) * ELITE_DEF_RATIO))
        else:
            defense_v = int(sc["boss_def"])

        # ── 攻击：先定「这一档的单发目标」，再减掉技能自带的那一份 ──
        need = {"trash": int(df["need_trash_atk"]),
                "elite": int(df["need_elite_atk"]),
                "boss": int(df["need_boss_atk"])}[kind]
        sk = skill_damage(text)
        atk_flat = at_least_zero(need - sk)

        old_hp = int(field(text, "max_hp") or 0)
        new = set_field(text, "kind", f'&"{kind}"', "display_name")
        new = set_field(new, "max_hp", str(hp), "kind")
        new = set_field(new, "defense", str(defense_v), "hurt_stun_frames")
        new = set_field(new, "atk_flat", str(atk_flat), "defense")
        new = set_field(new, "atk_mult", num(atk_mult), "atk_flat")
        if not dry:
            with f.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write(new)

        eff = int(round(float(atk_flat) * atk_mult)) + sk
        rows.append(dict(id=f.stem, kind=kind, chap=chap, hp=hp, old_hp=old_hp,
                         defense=defense_v, atk_flat=atk_flat, sk=sk,
                         need=need, eff=eff, mult=atk_mult, lv=level_ref))

    # ── 副本倍率：写 DungeonData.enemy_atk_scale ────────────────
    # 一张章节行只锚定一个等级（ch1 = lv20），而 ch1 横跨 lv1（砺场）到 lv25（炉喉）。
    # 共用的 walker.tres 只能存锚点值，「这个副本该多疼」由副本这一层的倍率补 ——
    # 敌人运行时把它乘进 Hitbox.damage_scale（见 walker.gd / spearman.gd）
    stage_scales: dict[str, float] = {}
    print("\n副本攻击倍率（承受力比 = 玩家血量(rec) ÷ 玩家血量(章锚点)）：")
    for did, (chap, rec) in DUNGEONS.items():
        anchor = int(scaling[chap]["level"])
        hp_rec = player_hp_at(rec, hp_gain, hp_falloff, base_hp)
        hp_anchor = player_hp_at(anchor, hp_gain, hp_falloff, base_hp)
        scale = round(hp_rec / hp_anchor, 3)
        stage_scales[did] = scale
        print(f"  {did:<12} rec={rec:<3} 锚={anchor:<3} 倍率 {scale}")
        if dry:
            continue
        f = STAGE_DIR / f"dungeon_{did}.tres"
        if not f.exists():
            raise SystemExit(f"❌ 副本数据不存在：{f}")
        text = read_text(f)
        text = set_field(text, "enemy_atk_scale", num(scale), "scene_path")
        # rec_level 也顺手补齐：砺场那份靠默认值 1 撑着，别的工具（舆图上色）读它
        if field(text, "rec_level") is None:
            text = set_field(text, "rec_level", str(rec), "scene_path")
        with f.open("w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    # ── 报告 ──────────────────────────────────────────────────
    print(f"{'id':<15}{'类':<7}{'章':<5}{'lv':>4}{'血量':>7}{'（原）':>8}{'def':>5}"
          f"{'锐伤':>5}{'单发':>6}{'目标':>6}{'倍率':>6}")
    for r in rows:
        print(f"{r['id']:<15}{r['kind']:<7}{r['chap']:<5}{r['lv'] or '-':>4}"
              f"{r['hp']:>7}{r['old_hp']:>8}"
              f"{r['defense']:>5}{r['atk_flat']:>5}{r['eff']:>6}{r['need']:>6}{r['mult']:>6.2f}")

    # ── 自检 ──────────────────────────────────────────────────
    print("\n自检：")
    bad = [r["id"] for r in rows if abs(r["atk_flat"] + r["sk"] - r["need"]) > 1]
    assert not bad, f"基准单发对不上目标：{bad}"
    print("  ① 每只怪的「atk_flat + 技能伤害」都落在阶段目标上 ✅")

    over = [r["id"] for r in rows if r["defense"] > MAX_DEFENSE]
    assert not over, f"def 越过 {MAX_DEFENSE} 红线：{over}"
    worst = max(r["defense"] for r in rows)
    assert 100.0 / (100.0 + worst) >= MIN_ARMOR_FACTOR - 1e-9, "护甲系数低于 0.4"
    print(f"  ② def 最大 {worst} ≤ {MAX_DEFENSE}，护甲系数最低 "
          f"{100.0 / (100.0 + worst):.2f} ≥ {MIN_ARMOR_FACTOR}（没越 0.6 红线）✅")

    trash_min = min(r["eff"] for r in rows if r["kind"] == "trash")
    elite_min = min(r["eff"] for r in rows if r["kind"] == "elite")
    boss_min = min(r["eff"] for r in rows if r["kind"] == "boss")
    assert trash_min < elite_min and trash_min < boss_min, "伤害阶梯不是「小怪最轻」"
    print(f"  ③ 伤害阶梯：小怪最轻 {trash_min} < 精英 {elite_min}／Boss {boss_min} ✅")

    drift = [r["id"] for r in rows if r["kind"] == "trash"
             and not (0.8 <= r["hp"] / max(r["old_hp"], 1) <= 1.25)]
    assert not drift, f"小怪血量偏离现值太多（会动手感）：{drift}"
    print("  ④ 小怪血量与现值同量级（手感不动）✅")

    # Boss 血量必须**随副本推荐等级单调上升**：第一个副本的 Boss 是最薄的，
    # 章末那个最厚。这条挡的是「插值写反 / level_ref 填错」——
    # 那种错会让新玩家在第一个 Boss 面前被一根 11 倍的血条劝退
    bosses = sorted((r for r in rows if r["kind"] == "boss"), key=lambda r: r["lv"])
    ladder = [r["hp"] for r in bosses]
    assert ladder == sorted(ladder) and len(set(ladder)) == len(ladder), \
        f"Boss 血量没随 rec_level 递增：{[(r['id'], r['lv'], r['hp']) for r in bosses]}"
    print("  ⑤ Boss 血量随 rec_level 递增："
          + " → ".join(f"{r['lv']}级{r['hp']}" for r in bosses) + " ✅")

    # ⑥ 第一个副本不能是地狱。lv1 的玩家（100 血）在小怪手下至少挨 10 下 ——
    #    v1 的手感基线（8 点 / 12 下）。这条挡的是「忘了把伤害按副本等级缩放」：
    #    那种错测试抓不到（没有谁断言砺场有多疼），只有玩的人会撞上
    trash_need = int(defense["ch1"]["need_trash_atk"])
    lichang_hit = round(trash_need * stage_scales["lichang"])
    assert lichang_hit <= 10, f"砺场小怪单发 {lichang_hit} 点，lv1 玩家挨不了 10 下"
    print(f"  ⑥ 砺场（lv1）小怪单发 ≈{lichang_hit} 点 ≤ 10 "
          f"（100 血挨 10 下+，v1 手感保住）✅")

    print(f"\n{'（dry-run，未写文件）' if dry else '✅ 已写入 data/enemies/*.tres。'}"
          "接着跑：<godot> --headless --import")
    return 0


def at_least_zero(v: int) -> int:
    return v if v > 0 else 0


def num(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else repr(round(v, 3))


if __name__ == "__main__":
    sys.exit(main())
