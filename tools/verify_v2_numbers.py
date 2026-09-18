#!/usr/bin/env python3
"""对着设计期的表核实际落地的数值 —— **只读**，不改任何文件。

回答一个问题：**「v2 的数值与伤害计算，到底按规划改好了没有？」**
设计期唯一来源 = `docs/gear-v2/data/*.csv`；实际 = `bailian/data/**.tres`。

    python tools/verify_v2_numbers.py            # 全部对账 + PASS/FAIL
    python tools/verify_v2_numbers.py --quiet    # 只列 FAIL 与结论

七条检查，每条都给设计值 / 实际值 / 偏差：
  ① 玩家 DPS 对账（装备表派生 → 设计的 player_dps）
  ② 玩家承受力对账（血 / 防 / 护甲系数 / EHP）
  ③ Boss 血量对账（B 机制分担口径 + 按 rec_level 插值）
  ④ 敌人单发对账（atk_flat × atk_mult + 技能自带伤害）
  ⑤ **跨章缩放对账**（小怪/精英的血量与伤害是否随章变化）
  ⑥ 遭遇时长对账（实际时长 vs 设计的 boss_s）
  ⑦ 红线（def ≤ 150 / 护甲系数 ≥ 0.4 / 不减到 1 点以下）

⚠️ 这个脚本**不替代** `tests/`（那些跑在引擎里、验行为）；它验的是「数据与设计表
对不对得上」，属于设计文档与仓库之间那层对账，跑在 Python 里更快也更全。
"""
from __future__ import annotations

import argparse
import csv
import io
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN = REPO.parent / "docs" / "gear-v2" / "data"

SLOTS = ["weapon", "helm", "chest", "legs", "boots", "ring", "necklace", "bracelet"]
DEF_SLOTS = ["helm", "chest", "legs", "boots", "bracelet"]   # 与 data-gen/stats.cjs 同口径
HP_SLOTS = ["helm", "chest", "legs", "boots", "necklace"]

## 每档的「代表章节 / 代表等级 / 预期强化进度」——取自 gen_enemy_scaling.cjs 的 STAGES
TIER_CH = {1: ("ch1", 20, 0.40), 2: ("ch2", 42, 0.55), 3: ("ch3", 64, 0.70),
           4: ("ch4", 80, 0.85), 5: ("ch5", 100, 1.00)}
TIER_NAME = {0: "普通", 1: "精良", 2: "优秀", 3: "极品", 4: "传说", 5: "至尊"}

BASE_COMBO, COMBO_S, UPTIME = 42.0, 1.15, 0.55
MAX_RED = 0.6

## 副本 → (章, 推荐等级)。与 apply_enemy_scaling.py 的 DUNGEONS 一致
DUNGEONS = {"lichang": ("ch1", 1), "duancuiqu": ("ch1", 12), "luhou": ("ch1", 25),
            "canjianlin": ("ch2", 30), "xiushi": ("ch2", 42), "zhongxin": ("ch2", 55)}

FAILS: list[str] = []


def txt(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig")


def fld(t: str, k: str, d: str | None = None) -> str | None:
    m = re.search(rf"^{k} = (.*)$", t, re.MULTILINE)
    return d if m is None else m.group(1).strip()


def num(s: str | None, d: float = 0.0) -> float:
    if s is None:
        return d
    return float(str(s).strip().strip('&"'))


def mid(lo: int, hi: int) -> float:
    return (lo + hi) / 2.0


def read_csv(p: Path) -> dict[str, dict[str, str]]:
    with io.open(p, encoding="utf-8-sig", newline="") as fh:
        return {r["stage"].split("·")[0]: r for r in csv.DictReader(fh)}


# ── 数据：装备 / 成长 / 敌人 / 副本 ─────────────────────────────
items: list[dict] = []
for p in sorted((REPO / "data" / "items").glob("*.tres")):
    t = txt(p)
    items.append(dict(
        slot=SLOTS[int(num(fld(t, "slot")))],
        tier=int(num(fld(t, "tier"))),
        atk=mid(int(num(fld(t, "atk_min"))), int(num(fld(t, "atk_max")))),
        hp=mid(int(num(fld(t, "hp_min"))), int(num(fld(t, "hp_max")))),
        df=mid(int(num(fld(t, "def_min"))), int(num(fld(t, "def_max")))),
        src=str(fld(t, "source")),
    ))

prog = txt(REPO / "data" / "progression.tres")
G_ATK, F_ATK = num(fld(prog, "atk_gain")), num(fld(prog, "atk_falloff"))
G_HP, F_HP = num(fld(prog, "hp_gain")), num(fld(prog, "hp_falloff"))
BASE_HP = num(fld(prog, "base_hp"))


def lv_pct(level: int) -> float:
    n = max(level - 1, 0)
    return 0.0 if n <= 0 else G_ATK * (1.0 - F_ATK ** n)


def hp_at(level: int) -> float:
    n = max(level - 1, 0)
    return BASE_HP + (0.0 if n <= 0 else G_HP * (1.0 - F_HP ** n))


def slot_avg(tier: int, slot: str, key: str) -> float:
    g = [r[key] for r in items if r["tier"] == tier and r["slot"] == slot]
    return sum(g) / len(g) if g else 0.0


def flat_atk(tier: int) -> float:
    return slot_avg(tier, "weapon", "atk") + slot_avg(tier, "ring", "atk")


def def_sum(tier: int) -> float:
    return sum(slot_avg(tier, s, "df") for s in DEF_SLOTS)


def hp_sum(tier: int) -> float:
    return sum(slot_avg(tier, s, "hp") for s in HP_SLOTS)


def armor_mult(de: float) -> float:
    return 1.0 - min(de / (100.0 + de), MAX_RED)


## `.tres` 里的相位参数 → 「打不到它」的时间占比。
## 与 `EnemyData.phase_ratio()` 同一个公式（那边是运行期唯一真相，这边只为对账）
def phase_ratio_of(text: str) -> float:
    frames = num(fld(text, "phase_frames"))
    if frames <= 0:
        return 0.0
    cycle = num(fld(text, "phase_warn_frames")) + frames + num(fld(text, "phase_interval_frames"))
    return 0.0 if cycle <= 0 else frames / cycle


def skill_damage(text: str) -> int:
    """怪这一次攻击**自带的**那份伤害（近战看技能表 / 纯远程看 projectile_damage）。"""
    if re.search(r"^attack_skill = null$", text, re.MULTILINE):
        return int(num(fld(text, "projectile_damage")))
    m = re.search(r'path="(res://data/skills/[^"]+)"', text)
    return int(num(fld(txt(REPO / m.group(1).removeprefix("res://")), "damage")))


enemies: dict[str, dict] = {}
for p in sorted((REPO / "data" / "enemies").glob("*.tres")):
    t = txt(p)
    enemies[p.stem] = dict(
        kind=str(fld(t, "kind")).strip('&"'),
        hp=int(num(fld(t, "max_hp"))),
        df=int(num(fld(t, "defense"))),
        af=int(num(fld(t, "atk_flat"))),
        mult=num(fld(t, "atk_mult")),
        sk=skill_damage(t),
    )

sc = read_csv(DESIGN / "enemy_scaling.csv")
df = read_csv(DESIGN / "combat_defense.csv")


def hr(title: str) -> None:
    print()
    print("=" * 100)
    print(title)
    print("=" * 100)


def check(ok: bool, label: str) -> None:
    print(f"  {'PASS ✅' if ok else 'FAIL ❌'}  {label}")
    if not ok:
        FAILS.append(label)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="只列 FAIL 与结论")
    args = ap.parse_args()
    q = args.quiet
    loud = (lambda *a: None) if q else print

    hr("① 攻击侧：设计的 player_dps vs 装备表派生出来的 DPS")
    loud(f"{'代表档':<8}{'章':<5}{'lv':>4}{'强化%':>7}{'flat_atk':>10}"
         f"{'设计DPS':>9}{'实算DPS':>9}{'偏差':>9}")
    for tier, (ch, level, forge) in TIER_CH.items():
        fa = flat_atk(tier)
        dps = (BASE_COMBO + 3 * fa) * (1 + lv_pct(level) + forge) / COMBO_S
        want = num(sc[ch]["player_dps"])
        dev = (dps - want) / want * 100
        loud(f"{TIER_NAME[tier]:<8}{ch:<5}{level:>4}{forge:>7.2f}{fa:>10.1f}"
             f"{want:>9.0f}{dps:>9.0f}{dev:>8.1f}%")
        check(abs(dev) <= 2.0, f"{TIER_NAME[tier]}档 flat_atk={fa:.1f}（设计 {num(sc[ch]['flat_atk'])}）"
                               f" → DPS 偏差 {dev:+.1f}%")
    print("  说明：差异若出现，先看 stats.cjs 的组成口径（武器+戒指 / 5 件防具 / 5 件含项链）")

    hr("② 受击侧：设计的玩家承受力 vs 装备表派生出来的承受力")
    loud(f"{'代表档':<8}{'lv':>4}{'血设计':>8}{'血实算':>8}{'防设计':>8}{'防实算':>8}"
         f"{'护甲系数':>10}{'EHP设计':>9}{'EHP实算':>9}")
    for tier, (ch, level, _) in TIER_CH.items():
        hp = hp_at(level) + hp_sum(tier)
        de = def_sum(tier)
        d_hp, d_de = num(df[ch]["max_hp"]), num(df[ch]["player_def"])
        loud(f"{TIER_NAME[tier]:<8}{level:>4}{d_hp:>8.0f}{hp:>8.0f}{d_de:>8.0f}{de:>8.1f}"
             f"{armor_mult(de):>10.2f}{d_hp / armor_mult(d_de):>9.0f}{hp / armor_mult(de):>9.0f}")
        check(abs(hp - d_hp) / d_hp <= 0.03, f"{TIER_NAME[tier]}档 血 {hp:.0f} vs 设计 {d_hp:.0f}")
        check(abs(de - d_de) <= 2, f"{TIER_NAME[tier]}档 防 {de:.0f} vs 设计 {d_de:.0f}")

    hr("③ Boss 血量：B 机制分担口径 + 按 rec_level 插值")
    loud(f"{'boss':<16}{'副本rec':>8}{'章锚HP':>8}{'插值后':>8}{'实际HP':>8}{'偏差':>8}")
    boss_rec = {"boss": ("ch1", 1), "boss2": ("ch1", 12), "boss_luhou": ("ch1", 25),
                "boss_canjian": ("ch2", 30), "boss_xiushi": ("ch2", 42), "boss_zhongxin": ("ch2", 55)}
    for eid, (ch, rec) in boss_rec.items():
        anchor, a_lv = num(sc[ch]["hp_boss_B"]), int(num(sc[ch]["level"]))
        want = anchor * (1 + lv_pct(rec)) / (1 + lv_pct(a_lv))
        got = enemies[eid]["hp"]
        dev = (got - want) / want * 100
        loud(f"{eid:<16}{rec:>8}{anchor:>8.0f}{want:>8.0f}{got:>8}{dev:>7.1f}%")
        check(abs(dev) <= 6, f"{eid} 血量随 rec_level 插值（{want:.0f} → {got}）")

    hr("④ 敌人单发：章目标 need_*_atk vs 实际（atk_flat × 个体倍率 + 技能自带）")
    loud(f"{'id':<16}{'kind':<7}{'章':>5}{'目标':>7}{'实际':>7}{'偏差':>8}   备注")
    chap_of = {e: "ch1" for e in enemies if not e.startswith("boss_c") and e not in
               ("boss_xiushi", "boss_zhongxin")}
    chap_of.update({"boss_canjian": "ch2", "boss_xiushi": "ch2", "boss_zhongxin": "ch2"})
    for eid, e in sorted(enemies.items()):
        ch = chap_of.get(eid, "ch1")
        key = {"trash": "need_trash_atk", "elite": "need_elite_atk", "boss": "need_boss_atk"}[e["kind"]]
        want = num(df[ch][key])
        got = round(e["af"] * e["mult"]) + e["sk"]
        dev = (got - want) / want * 100
        note = ""
        if e["mult"] != 1.0:
            note = f"个体倍率 ×{e['mult']}（设计表未含）"
        loud(f"{eid:<16}{e['kind']:<7}{ch:>5}{want:>7.0f}{got:>7}{dev:>7.1f}%   {note}")
        check(abs(dev) <= 20, f"{eid} 单发 {got} vs 章目标 {want:.0f}")

    hr("⑤ 跨章缩放：同一只怪在第二章是否跟上（设计表 ch2 行）")
    loud("  设计表的 ch2 行每个 kind 只有**一个**目标值，而数据里每只怪有**自己的相对手感**")
    loud("  （疾行者更快更脆、重甲怪更肉 —— v1 就验收过的比例，别抹平）。所以分两件事核：")
    loud("  ① 基准怪（相对系数 1.0：walker / brute_elite）的**绝对值**要对上设计表；")
    loud("  ② 其余怪**跟随基准**（相对比例不随章变化）。")
    ch_hp = num(fld(txt(REPO / "data" / "stages" / "dungeon_xiushi.tres"), "enemy_hp_chapter"), 1.0)
    ch_atk = num(fld(txt(REPO / "data" / "stages" / "dungeon_xiushi.tres"), "enemy_atk_chapter"), 1.0)
    ref = {"trash": "walker", "elite": "brute_elite"}
    loud(f"\n  基准怪（第二章生效值 = .tres 第一章基准 × 副本章差）")
    loud(f"  {'id':<16}{'kind':<7}{'ch1血':>7}{'ch2设计血':>10}{'实际血':>7}"
         f"{'ch1伤':>7}{'ch2设计伤':>10}{'实际伤':>7}")
    bad = []
    for kind, rid in ref.items():
        e = enemies[rid]
        key_hp = {"trash": "hp_trash", "elite": "hp_elite_B"}[kind]
        key_atk = {"trash": "need_trash_atk", "elite": "need_elite_atk"}[kind]
        eff_hp = e["hp"] * ch_hp
        eff_atk = (round(e["af"] * e["mult"]) + e["sk"]) * ch_atk
        loud(f"  {rid:<16}{kind:<7}{num(sc['ch1'][key_hp]):>7.0f}"
             f"{num(sc['ch2'][key_hp]):>10.0f}{eff_hp:>7.0f}"
             f"{num(df['ch1'][key_atk]):>7.0f}{num(df['ch2'][key_atk]):>10.0f}{eff_atk:>7.0f}")
        if abs(eff_hp - num(sc["ch2"][key_hp])) / num(sc["ch2"][key_hp]) > 0.15:
            bad.append(f"{rid} 血")
        if abs(eff_atk - num(df["ch2"][key_atk])) / num(df["ch2"][key_atk]) > 0.15:
            bad.append(f"{rid} 伤")
    check(not bad, f"基准怪跟上第二章（血 {ch_hp:.2f}× / 伤 {ch_atk:.2f}×）："
                   f"{'对得上' if not bad else '偏差 ' + str(bad)}")

    # ② 其余怪：相对基准的比例在第一章与第二章一致（章差是**统一**乘上去的）
    ref_ratio_bad = []
    for eid, e in sorted(enemies.items()):
        if e["kind"] == "boss" or eid == ref[e["kind"]]:
            continue
        base = enemies[ref[e["kind"]]]
        r1 = e["hp"] / base["hp"]
        r2 = (e["hp"] * ch_hp) / (base["hp"] * ch_hp)
        if abs(r1 - r2) > 1e-6:
            ref_ratio_bad.append(eid)
    check(not ref_ratio_bad,
          f"其余怪跟随基准（相对手感不随章变化）：{ref_ratio_bad or '全部一致'}")
    check(ch_hp > 1.0 and ch_atk > 1.0,
          f"第二章副本确实带章差（血 ×{ch_hp:.2f} / 伤 ×{ch_atk:.2f}；第一章恒 1.0）")

    hr("⑥ 遭遇时长：Boss 血条 × 相位能撑多久")
    loud(f"{'副本':<12}{'rec':>5}{'玩家DPS':>9}{'Boss血':>8}{'护甲系数':>9}"
         f"{'相位占比':>9}{'实际秒':>8}{'名义目标':>9}{'达成':>7}")
    for eid, (ch, rec) in boss_rec.items():
        did = {"boss": "lichang", "boss2": "duancuiqu", "boss_luhou": "luhou",
               "boss_canjian": "canjianlin", "boss_xiushi": "xiushi",
               "boss_zhongxin": "zhongxin"}[eid]
        ## **不能拿章锚点的 DPS 直接去算副本里的一战**：ch1 锚在 lv20，砺场的 rec 是 1。
        ## 用与 Boss 血量插值**完全对称**的办法：把章锚点的 DPS 按等级成长比缩到 rec。
        ## 两边同一个公式 → 比值才有意义，否则算出来的是「两种口径的差」而不是游戏里的差。
        anchor_lv = int(num(sc[ch]["level"]))
        dps = num(sc[ch]["player_dps"]) * (1 + lv_pct(rec)) / (1 + lv_pct(anchor_lv))
        t = txt(REPO / "data" / "enemies" / f"{eid}.tres")
        e = enemies[eid]
        ## 相位把「打不到它」的那一份真的做进游戏了（ADR-0023）：
        ## 实际时长 = 血 / (等效DPS × 占比) × 1/(1-相位占比)
        pr = phase_ratio_of(t)
        actual = e["hp"] / (dps * armor_mult(e["df"]) * UPTIME * (1.0 - pr))
        nominal = num(sc[ch]["boss_s"])
        loud(f"{did:<12}{rec:>5}{dps:>9.0f}{e['hp']:>8}{armor_mult(e['df']):>9.2f}"
             f"{pr:>9.2f}{actual:>8.0f}{nominal:>9.0f}{actual / nominal * 100:>6.0f}%")
        ## 相位占比必须等于 1 − boss_active（设计表那一列的物理落点）
        want_pr = 1.0 - num(sc[ch]["boss_active"])
        check(abs(pr - want_pr) <= 0.02,
              f"{did} 相位占比 {pr:.2f} = 1−boss_active({want_pr:.2f})")
        check(0.8 <= actual / nominal <= 1.2,
              f"{did} 实际 {actual:.0f}s / 名义 {nominal:.0f}s（±20%）")
    print("\n  「相位占比」= Boss 打不到的时间（旧口径里那个老板着一格「今天可达」的年代结束了）。")

    hr("⑦ 红线（ADR-0019 / design-principles 4.2）")
    worst = max(e["df"] for e in enemies.values())
    check(worst <= 150, f"敌人 def 最大 {worst} ≤ 150")
    check(armor_mult(worst) >= 0.4 - 1e-9, f"护甲系数最低 {armor_mult(worst):.2f} ≥ 0.4（没越过 0.6 减伤红线）")
    src_bad = [f"{TIER_NAME[r['tier']]}" for r in items if (r["src"] == '&"drop"') == (r["tier"] >= 3)]
    check(not src_bad, f"途径隔离：极品+ 只走 craft、普通~优秀 只走 drop（异常 {set(src_bad) or '无'}）")

    hr("结论")
    if FAILS:
        print(f"  {len(FAILS)} 条没过：")
        for f in FAILS:
            print(f"    ❌ {f}")
    else:
        print("  全部 PASS。")
    print()
    print("  公式形状（写死的事实，不是算出来的）：")
    print("    player.gd:571-572  attack_flat = Σ装备平铺攻击；damage_scale = 1 + 等级% + 强化%(已过 soften)")
    print("    hitbox.gd:114-115  (技能伤害 + attack_flat) × damage_scale")
    print("    projectile.gd:75   同上（远程走同一条）")
    print("    health.gd:83       减伤 = min(def/(100+def), 0.6) —— 比例曲线，不是减法（4.5）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
