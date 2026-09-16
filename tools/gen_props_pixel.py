#!/usr/bin/env python3
"""程序化生成城镇场景道具（像素风）：房屋、告示牌。

为什么程序化而不是找素材：
  房屋是**特定尺寸**的（132x100 / 108x80，跟城镇布局绑定），素材包里的房子
  尺寸对不上，硬缩会糊。程序化生成能精确按显示尺寸出图，风格也与地形/UI 同族。
  规则和地形贴图一样：贴图尺寸 == 显示尺寸，1:1 不缩放。

    python tools/gen_props_pixel.py
"""
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "props")

# 像素格：2px 一格 —— 房子尺寸大（132 宽），1px 格会显得过于细碎，
# 和角色（原生 32~48 的帧）不成比例
P = 2


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def px(d, x, y, c):
    """按像素格画一个 P×P 方块（左上角格坐标）。"""
    d.rectangle([x * P, y * P, x * P + P - 1, y * P + P - 1], fill=c)


def rect(d, x0, y0, x1, y1, c):
    """格坐标的填充矩形（含端点）。"""
    d.rectangle([x0 * P, y0 * P, (x1 + 1) * P - 1, (y1 + 1) * P - 1], fill=c)


# ── 房屋 ──────────────────────────────────────────────────────────
HOUSE_PALETTES = {
    # 城镇主色：暖褐木屋（和背景层的深紫剪影拉开层次）
    "warm": dict(
        wall="#a2764c", wall_d="#7d5836", wall_l="#c39264",
        beam="#6b4a2d", roof="#8c4a3a", roof_d="#67342a", roof_l="#b0604c",
        door="#5a3a24", door_l="#7d5236", win="#f2d78c", win_d="#c9a95f",
        stone="#8b8177", stone_d="#6f665e",
    ),
    # 铁匠铺：偏冷的灰石 + 深瓦（和暖褐屋区分）
    "forge": dict(
        wall="#8d8579", wall_d="#6b655c", wall_l="#a9a094",
        beam="#4f463c", roof="#5d4a45", roof_d="#41322f", roof_l="#7a625c",
        door="#3f3229", door_l="#5c4a3c", win="#f0b45a", win_d="#c78c3e",
        stone="#7a7269", stone_d="#5e574f",
    ),
}


def make_house(w, h, pal_name="warm", sign=None, seed=7):
    """w = 总宽、h = 总高（都按像素算）。屋顶占上部 ~34%，墙占下部。"""
    t = HOUSE_PALETTES[pal_name]
    rnd = random.Random(seed)
    gw, gh = w // P, h // P                      # 格尺寸
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    roof_h = max(4, int(gh * 0.38))              # 屋顶格高
    wall_y0 = roof_h
    # 墙裙留一格檐口（屋顶出檐，比墙宽 2 格）
    eave = 3                                     # 檐口外伸（房子要「压」在墙上）

    # ── 墙 ──
    rect(d, 0, wall_y0, gw - 1, gh - 1, hexc(t["wall"]))
    # 砖缝（错缝），每 3 格一道
    for gy in range(wall_y0 + 3, gh, 3):
        d.line([(0, gy * P), (gw * P - 1, gy * P)], fill=hexc(t["wall_d"], 130))
        off = (gy // 3 % 2) * 4
        for gx in range(off, gw, 8):
            d.line([(gx * P, gy * P), (gx * P, min(gh * P - 1, (gy + 3) * P - 1))],
                   fill=hexc(t["wall_d"], 110))
    # 墙面噪点（3% 明暗），让大色块不呆
    for gy in range(wall_y0, gh):
        for gx in range(gw):
            r = rnd.random()
            if r < 0.03:
                px(d, gx, gy, hexc(t["wall_l"], 120))
            elif r < 0.06:
                px(d, gx, gy, hexc(t["wall_d"], 120))
    # 墙顶受光 / 底部压暗
    rect(d, 0, wall_y0, gw - 1, wall_y0, hexc(t["wall_l"]))
    rect(d, 0, gh - 1, gw - 1, gh - 1, hexc(t["wall_d"]))
    # 墙根投影（一格，压深）
    rect(d, 0, gh - 2, gw - 1, gh - 2, hexc(t["wall_d"], 170))

    # ── 屋顶（梯形：底边比墙宽 2*eave，顶边收成平脊）──
    ridge_w = max(6, int(gw * 0.52))             # 脊要宽，窄了像金字塔
    max_half = int(round(gw * 0.5 + eave))

    def roof_span(gy):
        """第 gy 行的左右边界（格）。gy=0 是屋脊（窄），roof_h-1 是檐口（最宽）。"""
        k = gy / max(1.0, roof_h - 1)
        half = max(int(round(max_half * k)), ridge_w // 2)
        return max(0, gw // 2 - half), min(gw - 1, gw // 2 + half - 1)

    for gy in range(roof_h):
        x0, x1 = roof_span(gy)
        x1 = max(x1, x0)                                # 脊部保底：至少一格宽
        col = t["roof_d"] if gy % 3 == 0 else t["roof"]  # 瓦片横纹
        rect(d, x0, gy, x1, gy, hexc(col))
        if gy == 0:
            rect(d, x0, 0, x1, 0, hexc(t["roof_l"]))     # 脊线受光
    # 瓦片竖缝（错缝）
    for gy in range(1, roof_h):
        x0, x1 = roof_span(gy)
        for gx in range(x0 + (gy % 2), x1, 3):
            px(d, gx, gy, hexc(t["roof_d"], 150))
    # 檐口投影（墙顶被屋檐压暗一格）
    rect(d, 0, wall_y0, gw - 1, wall_y0, hexc(t["roof_d"], 90))

    # ── 烟囱（靠右，穿出屋顶）──
    cx = int(gw * 0.72)
    ch_top = max(0, roof_h - 4)
    rect(d, cx, ch_top, cx + 2, roof_h + 1, hexc(t["stone"]))
    rect(d, cx, ch_top, cx + 2, ch_top, hexc(t["stone_d"]))
    px(d, cx, ch_top, hexc(t["stone_d"]))
    px(d, cx + 2, ch_top, hexc(t["stone_d"]))

    # ── 门（居中偏左，拱顶）──
    dw, dh = 7, int(gh * 0.26)
    dx0 = max(2, gw // 2 - dw - 2)
    dy0 = gh - dh
    rect(d, dx0, dy0, dx0 + dw - 1, gh - 1, hexc(t["door"]))
    rect(d, dx0, dy0, dx0 + dw - 1, dy0, hexc(t["door_l"]))     # 门楣亮
    rect(d, dx0, dy0, dx0, dy0, hexc(t["door_l"]))
    px(d, dx0 + dw - 2, dy0 + dh // 2, hexc("#e8c05a"))         # 门把手
    # 门框
    for gy in range(dy0, gh):
        px(d, dx0 - 1, gy, hexc(t["beam"]))
        px(d, dx0 + dw, gy, hexc(t["beam"]))
    # 门前台阶（一格石台，衬出门的位置）
    rect(d, dx0 - 1, gh - 1, dx0 + dw, gh - 1, hexc(t["stone_d"]))

    # ── 窗（门右侧，亮黄 + 十字框）──
    wx0 = dx0 + dw + 3
    wy0 = wall_y0 + 3                             # 窗在墙腰（别贴着门）
    rect(d, wx0, wy0, wx0 + 3, wy0 + 3, hexc(t["win"]))
    px(d, wx0 + 1, wy0 + 1, hexc("#fff4c2"))                    # 高光角
    d.line([(wx0 * P, (wy0 + 2) * P), ((wx0 + 4) * P - 1, (wy0 + 2) * P)],
           fill=hexc(t["win_d"]))
    d.line([((wx0 + 2) * P, wy0 * P), ((wx0 + 2) * P, (wy0 + 4) * P - 1)],
           fill=hexc(t["win_d"]))
    rect(d, wx0 - 1, wy0 - 1, wx0 + 4, wy0 - 1, hexc(t["beam"]))
    rect(d, wx0 - 1, wy0 - 1, wx0 - 1, wy0 + 4, hexc(t["beam"]))

    # ── 招牌（可选：挂在门上方）──
    if sign:
        sw = min(gw - 6, len(sign) * 3 + 4)
        sx0 = max(1, (gw - sw) // 2)
        sy0 = wall_y0 + 3
        rect(d, sx0, sy0, sx0 + sw - 1, sy0 + 3, hexc("#6b4a2d"))
        rect(d, sx0 + 1, sy0 + 1, sx0 + sw - 2, sy0 + 2, hexc("#c9a45f"))
        px(d, sx0, sy0, hexc("#3b2718"))
        px(d, sx0 + sw - 1, sy0, hexc("#3b2718"))
    return im


# ── 告示牌 ────────────────────────────────────────────────────────
def make_sign(w=32, h=52):
    """木告示牌：两根立柱 + 牌面（木纹 + 钉子）。**顶部留空，字由 Label 画**。"""
    gw, gh = w // P, h // P
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    post, post_l, post_d = "#5b3d24", "#7d5533", "#3e2816"
    board, board_l, board_d = "#b98a52", "#d8a86c", "#8a6134"

    # 立柱（两根，插到牌面下）
    board_h = 12                                   # 牌面格高（要放得下指引文字）
    board_y1 = board_h - 1
    for gx in (1, gw - 3):
        rect(d, gx, 1, gx + 1, gh - 1, hexc(post))
        for gy in range(1, gh):
            px(d, gx, gy, hexc(post_l))            # 左缘受光
            px(d, gx + 1, gy, hexc(post_d))
    # 牌面（比立柱宽，覆盖在上）
    rect(d, 0, 0, gw - 1, board_y1, hexc(board))
    rect(d, 0, 0, gw - 1, 0, hexc(board_l))        # 上缘受光
    rect(d, 0, board_y1, gw - 1, board_y1, hexc(board_d))
    rect(d, 0, 0, 0, board_y1, hexc(board_l))
    rect(d, gw - 1, 0, gw - 1, board_y1, hexc(board_d))
    # 木纹
    for gy in range(1, board_y1, 2):
        d.line([(2 * P, gy * P), ((gw - 3) * P, gy * P)], fill=hexc(board_d, 110))
    # 四角钉子
    for gx, gy in ((1, 1), (gw - 2, 1), (1, board_y1 - 1), (gw - 2, board_y1 - 1)):
        px(d, gx, gy, hexc("#e8d9a8"))
        px(d, gx, gy, hexc("#6b5a35", 200))
    return im


def main():
    out = os.path.normpath(OUT)
    os.makedirs(out, exist_ok=True)

    props = [
        # 铁匠铺（大，带招牌）
        ("house_forge.png", lambda: make_house(132, 100, "forge", sign="SMITH", seed=11)),
        # 民居（小）
        ("house_small.png", lambda: make_house(108, 80, "warm", seed=23)),
        # 告示牌
        ("signpost.png", lambda: make_sign(32, 52)),
    ]
    for name, fn in props:
        im = fn()
        im.save(os.path.join(out, name))
        print("%-20s %s" % (name, im.size))


if __name__ == "__main__":
    main()
