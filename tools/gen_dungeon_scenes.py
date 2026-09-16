#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成淬火岭后两个副本的场景：断淬渠（4 屏）/ 炉喉（5 屏）。

    cd <项目根> && python tools/gen_dungeon_scenes.py

── 为什么要生成，不用手写 ──────────────────────────────────────
一个副本 = 4~5 屏 × 3 批 = 十几个波次、三四十只怪、十几块地形。
手写 .tscn 的嵌套 `parent` 路径写错一层，Godot **只发一行 WARNING 就把节点丢掉** ——
界面缺一块、脚本引用炸，却没有任何硬错误（`check_scenes` 就是为这个而生的）。
这里的规格表（`SCREENS`）是**可读的设计意图**：一眼看得出每屏每批放什么、
难度怎么起伏。改内容改这张表，重跑一次。

── 形态与砺场一致（砺场那版已被神定为模板）──────────────────────
· 一屏 960px（比视口 640 宽，相机跟着滚），屏 = `screen` 分组的节点
· 每屏 3 批，批 = 屏下的 `wave` 分组容器，**一批全灭才出下一批**
· 只能向右推进，挡墙由关卡根节点动态建（场景里没有墙）
· 最后一屏的最后一波放 Boss
· 地形：**连续地面**（不留断口）+ 浮台。相邻台面的抬升 ≤ 60px ——
  超了就是「看得见但上不去」的台子，而那不报错（见 design-conventions 的地形预算）

── 难度怎么排（这一版新做进去的）──────────────────────────────
· **四步法**（2.5）：新敌人先在**低威胁**的一波里单独出场（引入），
  下一屏与熟面孔混编（练习），再下一屏制造夹击（转折），最后一屏考核（Boss）
· **锯齿**（2.6）：每副本至少一处**喘息** —— 一批只放两只散开的小怪，
  不是「一路越来越难」
· **敌人变强靠配置**（4.3）：断淬渠靠**新敌人**（掷火者远程 + 重锤兵），
  炉喉靠**精英变体**（同一套 AI，更早发现、追得更紧、出手更密）——
  血量只小幅重标，不靠把血条拉长制造难度
"""

import io
import os

OUT_DIR = os.path.join("scenes", "stages")

# ── 敌人：键 → (场景路径, 在 tscn 里的 ext_resource id)────────────────
ENEMY_SCENES = {
    "walker":        "res://scenes/enemies/walker.tscn",
    "dasher":        "res://scenes/enemies/dasher.tscn",
    "spearman":      "res://scenes/enemies/spearman.tscn",
    "brute":         "res://scenes/enemies/brute.tscn",
    "brute_heavy":   "res://scenes/enemies/brute_heavy.tscn",
    "caster":        "res://scenes/enemies/caster.tscn",
    "boss":          "res://scenes/enemies/boss.tscn",
    "boss2":         "res://scenes/enemies/boss2.tscn",
    "walker_elite":  "res://scenes/enemies/walker_elite.tscn",
    "dasher_elite":  "res://scenes/enemies/dasher_elite.tscn",
    "brute_elite":   "res://scenes/enemies/brute_elite.tscn",
    "boss_luhou":    "res://scenes/enemies/boss_luhou.tscn",
}

# ── 坐标系：规格表用**绝对坐标**，落盘转成**屏内相对坐标** ────────
# 两者差一个坑的距离：砺场里 `Screen2` 摆在 x=960，它下面的怪写的是 480（屏内相对）。
# 规格表如果也写相对坐标，读到「第 3 屏的 1200」得心算 +1920 才知道在哪儿；
# 所以**表里一律写绝对**（「第 3 屏在 1920~2880，这只放 2200」），
# 落盘时减掉屏偏移。两套坐标叠起来用过一次 —— 表现是「怪全跑到后面几屏去了」
SCREEN_W = 960.0
GROUND_TOP = 320.0          # 地面顶面（中心 y=332，厚 24）
ENEMY_Y = 288.0             # 小怪站位：站上去会落一点点，与砺场一致
PLAT_Y = (268.0, 240.0)     # 两档浮台。抬升 52 / 28（都在 60 的预算内）


# ── 地形贴图（M4 美术接入，Kenney New Platformer Pack，CC0）────
# role → assets/tiles/ 下的文件名。断淬渠石 / 炉喉沙；浮台统一木板。
# 调色板颜色保留（背景等仍在用），地形视觉不再用它
TILES = {
    "grass": {"ground": "grass_top", "step": "grass_center", "plat": "grass_plat", "plat_s": "grass_plat"},
    "stone": {"ground": "stone_top", "step": "stone_center", "plat": "stone_plat", "plat_s": "stone_plat"},
    "sand": {"ground": "sand_top", "step": "sand_center", "plat": "sand_plat", "plat_s": "sand_plat"},
}


def _terrain(palette, screens):
    """地形规格。返回 [(名字, 中心x, 中心y, 宽, 高, 色, 用哪个 shape)]。

    **只留连续地面**（不留断口）+ 浮台。砺场就是这么摆的，也过了地形预算；
    断口是另一件事（要单独验助跑跳），这一版不引入。
    """
    out = [("Ground", SCREEN_W * screens / 2.0, 332.0, SCREEN_W * screens, 24.0,
            palette["ground"], "ground")]
    # 第一屏一个台阶（抬升 48）
    out.append(("Step1", 300.0, 292.0, 160.0, 40.0, palette["step"], "step"))
    # 每隔一屏摆两块浮台：一块矮（262 顶）、一块高（234 顶）。
    # 相邻抬升 10 / 28 —— 逐级上去，不是一步登天
    for i in range(screens):
        base = SCREEN_W * i + 620.0
        out.append(("Plat%da" % (i + 1), base, PLAT_Y[0], 120.0, 12.0,
                    palette["plat"], "plat"))
        out.append(("Plat%db" % (i + 1), base + 260.0, PLAT_Y[1], 110.0, 12.0,
                    palette["plat_s"], "plat_s"))
    return out


def _emit(spec):
    palette = spec["palette"]
    tiles = TILES[spec.get("tiles", "grass")]
    screens = spec["screens"]
    screen_count = len(screens)
    terrain = _terrain(palette, screen_count)

    # 这一关用到哪几种敌人 → 分配 ext_resource id
    used = []
    for scr in screens:
        for wave in scr:
            for key, _x in wave:
                if key not in used:
                    used.append(key)

    ext = []
    ext.append(('Script', "res://scripts/core/stage.gd", "1_stage"))
    ext.append(('Resource', "res://data/stages/dungeon_%s.tres" % spec["id"], "2_dungeon"))
    ext.append(('PackedScene', "res://scenes/characters/player.tscn", "3_player"))
    enemy_ids = {}
    for i, key in enumerate(used):
        rid = "4_%s" % key
        enemy_ids[key] = rid
        ext.append(('PackedScene', ENEMY_SCENES[key], rid))
    if spec.get("npc"):
        # npc 元组 = (名字 key, x, y, 对话资源名)
        ext.append(('PackedScene', "res://scenes/core/npc.tscn", "8_npc"))
        ext.append(('Resource', "res://data/dialogue/%s.tres" % spec["npc"][3], "9_dialogue"))

    # 地形用的 shape：ground / step / plat / plat_s 四种尺寸各一个
    shapes = {}
    sizes = {"ground": (SCREEN_W * screen_count, 24.0), "step": (160.0, 40.0),
             "plat": (120.0, 12.0), "plat_s": (110.0, 12.0)}
    for name, size in sizes.items():
        shapes[name] = "RectangleShape2D_%s" % name

    parts = []
    parts.append("[gd_scene load_steps=%d format=3]\n" % (len(ext) + len(shapes) + 1))
    tile_ids = {}
    for role, fname in tiles.items():
        rid = "tile_%s" % role
        tile_ids[role] = rid
        ext.append(('Texture2D', "res://assets/tiles/%s.png" % fname, rid))

    for kind, path, rid in ext:
        parts.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
    parts.append("")
    for name, size in sizes.items():
        parts.append('[sub_resource type="RectangleShape2D" id="%s"]' % shapes[name])
        parts.append("size = Vector2(%s, %s)\n" % (_num(size[0]), _num(size[1])))

    parts.append('[node name="%s" type="Node2D"]' % spec["node"])
    parts.append('script = ExtResource("1_stage")')
    parts.append('dungeon_data = ExtResource("2_dungeon")')
    parts.append("bounds = Rect2(0, 0, %s, 360)\n" % _num(SCREEN_W * screen_count))

    for name, cx, cy, w, h, color, shape in terrain:
        parts.append('[node name="%s" type="StaticBody2D" parent="."]' % name)
        parts.append("position = Vector2(%s, %s)" % (_num(cx), _num(cy)))
        parts.append("collision_layer = 4")
        parts.append("collision_mask = 0\n")
        parts.append('[node name="Visual" type="TextureRect" parent="%s"]' % name)
        parts.append("offset_left = %s" % _num(-w / 2.0))
        parts.append("offset_top = %s" % _num(-h / 2.0))
        parts.append("offset_right = %s" % _num(w / 2.0))
        # 视觉向下加厚：碰撞面不动（还能照原样踩），只是把体积画出来 ——
        # 12px 薄板在黑底上看不见，是「能跳上去但看不到」的直接原因
        _vis_extra = {"ground": 20.0, "step": 4.0, "plat": 10.0, "plat_s": 10.0}.get(shape, 0.0)
        parts.append("offset_bottom = %s" % _num(h / 2.0 + _vis_extra))
        parts.append("mouse_filter = 2")
        # 贴图按**显示尺寸**生成（tools/gen_terrain_tiles.py）：
        # ground/step 44px、plat 22px，TILE 平铺 1:1 不缩放
        parts.append("texture = ExtResource(\"%s\")" % tile_ids[shape])
        parts.append("stretch_mode = 1")
        parts.append("")
        parts.append('[node name="CollisionShape2D" type="%s" parent="%s"]' % ("CollisionShape2D", name))
        parts.append('shape = SubResource("%s")\n' % shapes[shape])

    # ── 屏 → 批 → 怪 ──────────────────────────────────────────
    for si, scr in enumerate(screens):
        sname = "Screen%d" % (si + 1)
        parts.append('[node name="%s" type="Node2D" parent="." groups=["screen"]]' % sname)
        if si > 0:
            parts.append("position = Vector2(%s, 0)" % _num(SCREEN_W * si))
        parts.append("")
        if si == spec.get("npc_screen", -1) and spec.get("npc"):
            nkey, nx, ny, dlg = spec["npc"]
            parts.append('[node name="%s" parent="%s" instance=ExtResource("8_npc")]' % ("Hunter", sname))
            parts.append("position = Vector2(%s, %s)" % (
                _num(nx - SCREEN_W * si), _num(ny)))
            parts.append('name_key = &"%s"' % nkey)
            parts.append('dialogue = ExtResource("9_dialogue")\n')
        for wi, wave in enumerate(scr):
            wname = "Wave%d" % (wi + 1)
            parts.append('[node name="%s" type="Node2D" parent="%s" groups=["wave"]]' % (wname, sname))
            parts.append("")
            for key, x in wave:
                nname = "%s%d" % (_camel(key), x)
                parts.append('[node name="%s" parent="%s/%s" instance=ExtResource("%s")]'
                             % (nname, sname, wname, enemy_ids[key]))
                parts.append("position = Vector2(%s, %s)\n" % (
                    _num(float(x) - SCREEN_W * si), _num(ENEMY_Y)))

    parts.append('[node name="Player" parent="." instance=ExtResource("3_player")]')
    parts.append("position = Vector2(60, 280)")
    return "\n".join(parts) + "\n"


def _num(v):
    """整数就不写小数点 —— 手写的 .tscn 都是这个风格，diff 才像人写的"""
    f = float(v)
    return str(int(f)) if f == int(f) else ("%g" % f)


def _camel(key):
    return "".join(p.capitalize() for p in key.split("_"))


# ── 规格表（改内容改这里）──────────────────────────────────────

# 断淬渠：4 屏。新内容 = **掷火者（远程）** 与 **重锤兵**。
# 四步法：屏1 掷火者单独出场 → 屏2 重锤兵 + 混编 → 屏3 双远程夹击、重锤改用 Boss 的碎地
#        → 屏4 石甲卫（考核）
# 锯齿：屏2 第 2 批是**喘息点**（两只散开的游荡者）
DUANCUIQU = {
    "id": "duancuiqu",
    "node": "Duanququ",
    "npc": None,
    "palette": {
        # 水渠：冷灰蓝
        "ground": "0.25, 0.28, 0.31, 1",
        "step": "0.31, 0.35, 0.39, 1",
        "plat": "0.3, 0.34, 0.38, 1",
        "plat_s": "0.28, 0.32, 0.36, 1",
    },
    "tiles": "stone",
    "screens": [
        # 屏 1 —— 引入：熟面孔开道，第三批让掷火者**单独**站远一点，先看清它会远程
        [
            [("walker", 500), ("walker", 660), ("walker", 800)],
            [("dasher", 480), ("dasher", 640), ("caster", 900)],
            [("walker", 520), ("caster", 860), ("dasher", 700), ("spearman", 560)],
        ],
        # 屏 2 —— 练习：重锤兵首次出现（一批只有一只，压力低）；第 2 批是喘息点
        [
            [("brute", 1260), ("walker", 1460), ("walker", 1600)],
            [("walker", 1180), ("walker", 1440)],                    # ← 喘息
            [("brute", 1240), ("spearman", 1400), ("dasher", 1560), ("dasher", 1700)],
        ],
        # 屏 3 —— 转折：两只掷火者分站两处（逼你来回跑），
        # 碎地重锤出场 —— 它挥的就是屏 4 那只 Boss 的招式（**教学屏**）
        [
            [("caster", 2200), ("caster", 2700)],
            [("brute_heavy", 2360), ("brute_heavy", 2620)],
            [("walker", 2120), ("dasher", 2300), ("spearman", 2480), ("caster", 2760)],
        ],
        # 屏 4 —— 考核：石甲卫 + 掷火者（远程与近身同时压）
        [
            [("walker", 3000), ("caster", 3120), ("walker", 3260)],
            [("brute", 3080), ("dasher", 3300), ("dasher", 3460)],
            [("caster", 3560), ("boss2", 3660)],
        ],
    ],
}

# 炉喉：5 屏。最终副本 —— 全类型 + **精英变体**（4.3 的落点）。
# 锯齿：屏1 开场就是喘息（全是小怪），屏4 再给一次喘息；峰值在屏 3
LUHOU = {
    "id": "luhou",
    "node": "Luhou",
    # 猎人的收尾对话。⚠️ 文案是线性时代写的（「都不成气候了」），
    # 放在最终副本前面已经对不上了 —— 留给神重写，见 acceptance/M3.md
    "npc": ("NPC_HUNTER", 3720.0, 300.0, "hunter_outro"),
    "npc_screen": 3,                     # 屏 4（0 起算），最后一屏之前
    "palette": {
        # 炉心：暖黑褐
        "ground": "0.3, 0.24, 0.22, 1",
        "step": "0.38, 0.29, 0.26, 1",
        "plat": "0.37, 0.28, 0.25, 1",
        "plat_s": "0.34, 0.26, 0.23, 1",
    },
    "tiles": "sand",
    "screens": [
        # 屏 1 —— 喘息：开场略低于实力，全是熟悉的种类
        [
            [("walker_elite", 500), ("walker_elite", 660), ("walker_elite", 820)],
            [("dasher_elite", 520), ("spearman", 720), ("dasher_elite", 880)],
            [("walker_elite", 560), ("spearman", 760), ("caster", 900)],
        ],
        # 屏 2 —— 练习：精英重锤 + 远程；第 2 批是**第二个喘息点**
        [
            [("brute_elite", 1560), ("caster", 1880)],
            [("walker_elite", 1420), ("walker_elite", 1640)],         # ← 喘息
            [("brute_elite", 1480), ("dasher_elite", 1700), ("dasher_elite", 1860)],
        ],
        # 屏 3 —— 转折（压力峰值）：双远程 + 双精英重锤
        [
            [("caster", 2140), ("caster", 2500)],
            [("brute_elite", 2200), ("brute_elite", 2450)],
            [("dasher_elite", 2380), ("spearman", 2560), ("brute_elite", 2680), ("caster", 2860)],
        ],
        # 屏 4 —— 喘息 + 收尾准备；猎人在这一屏等着
        [
            [("walker_elite", 3200), ("spearman", 3400)],
            [("dasher_elite", 3320), ("caster", 3560), ("dasher_elite", 3480)],
            [("brute_elite", 3380), ("spearman", 3520), ("caster", 3780)],
        ],
        # 屏 5 —— 考核：炉心守卫
        [
            [("walker_elite", 4280), ("brute_elite", 4380), ("caster", 4240)],
            [("dasher_elite", 4360), ("spearman", 4460), ("dasher_elite", 4520)],
            [("caster", 4600), ("brute_elite", 4560), ("boss_luhou", 4680)],
        ],
    ],
}

SPECS = [DUANCUIQU, LUHOU]


def _check_placement(spec):
    """怪必须落在自己那一屏的 x 区间里。

    写规格表时最容易犯的错：把「屏内相对坐标」（第 3 屏的第 1200）当成绝对坐标
    写下去 —— 于是那一屏的怪全挤在别处。按分组数怪的断言**完全看不出来**
    （分组是对的、数量是对的），只有截图或者真的玩才发现。
    """
    bad = []
    for si, scr in enumerate(spec["screens"]):
        lo, hi = SCREEN_W * si, SCREEN_W * (si + 1)
        for wi, wave in enumerate(scr):
            for key, x in wave:
                if not (lo <= float(x) < hi):
                    bad.append("第%d屏第%d批 %s@%s（应在 %.0f~%.0f）" % [
                        si + 1, wi + 1, key, x, lo, hi])
    return bad


def main():
    problems = 0
    for spec in SPECS:
        for msg in _check_placement(spec):
            print("  ✗ %s %s" % (spec["id"], msg))
            problems += 1
    if problems:
        raise SystemExit("规格表里有 %d 只怪长到了别人的屏里，先修再生成" % problems)
    for spec in SPECS:
        path = os.path.join(OUT_DIR, "%s.tscn" % spec["id"])
        text = _emit(spec)
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        screens = len(spec["screens"])
        waves = sum(len(s) for s in spec["screens"])
        mobs = sum(len(w) for s in spec["screens"] for w in s)
        print("  %-34s %d 屏 / %d 批 / %d 只" % (path, screens, waves, mobs))


if __name__ == "__main__":
    main()
