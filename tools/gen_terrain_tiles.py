"""生成三主题地形条带贴图（像素风）。

    python tools/gen_terrain_tiles.py

## 为什么必须「按显示尺寸」生成，而不是拿整块纹理去平铺

游戏里的地形视觉是**窄条**：
    · Ground / Step：43~44px 高（可站立面）
    · Plat：22px 高（浮空平台）
之前塞的是 256×256 的整块手绘纹理，`stretch_mode = TILE` 只显示贴图**顶部**
那一小条 —— 恰好是草叶尖/暗色区，于是「平台能踩但看不见」，
地面上也只剩一条平色（神实测：站在地板下面的感觉）。

所以这里直接按**显示尺寸**画：横向 96px 无缝平铺，纵向按用途定高。
顶面第一行必须是高亮线 —— 可站立面要一眼认出来，这是可玩性不是装饰。

## 文件名与旧资源保持一致（town.tscn 等手写场景直接受益）
    grass_top / grass_center / grass_plat（+ stone_ / sand_ 同理）
"""

from PIL import Image, ImageDraw
import os
import random

W = 96            # 横向平铺宽度
H_GROUND = 44     # 地面条高
H_PLAT = 22       # 平台条高
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "tiles")


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


# ── 主题调色板 ────────────────────────────────────────────────
# 每个主题：亮（顶面高光）/ 表（表面层）/ 深（表面暗部）/ 内1 内2（下方填充）/ 点（噪点）
THEMES = {
    "grass": dict(
        hi="#d4f58c", face="#6cc24a", face_d="#4a9432",
        in1="#7a5236", in2="#5d3d28", dot="#8a6a4a",
        accent="#2f6b28", style="grass",
    ),
    "stone": dict(
        hi="#aab2c6", face="#8b93a6", face_d="#5a6172",
        in1="#4a5162", in2="#383e4c", dot="#2a2e38",
        accent="#c8d0e0", style="stone",
    ),
    "sand": dict(
        hi="#f5cf8a", face="#e0a860", face_d="#b87840",
        in1="#a86c34", in2="#8a5628", dot="#c98a44",
        accent="#6b3d18", style="sand",
    ),
}


def make_ground(t):
    """地面 / 台阶条：顶面高光 + 表面层 + 内部填充。"""
    im = Image.new("RGBA", (W, H_GROUND), hexc(t["in1"]))
    d = ImageDraw.Draw(im)
    rnd = random.Random(hash(t["face"]) & 0xFFFF)

    # 内部填充：两段色 + 噪点（上浅下深，营造体积）
    d.rectangle([0, 18, W, 30], fill=hexc(t["in1"]))
    d.rectangle([0, 30, W, H_GROUND], fill=hexc(t["in2"]))
    for _ in range(90):
        x, y = rnd.randrange(W), rnd.randrange(20, H_GROUND)
        d.point((x, y), fill=hexc(t["dot"], 160))

    # 表面层（4~18px）
    d.rectangle([0, 4, W, 18], fill=hexc(t["face"]))
    d.rectangle([0, 14, W, 18], fill=hexc(t["face_d"]))
    # 表面与内部的过渡暗线
    d.rectangle([0, 18, W, 19], fill=hexc(t["accent"], 120))

    if t["style"] == "grass":
        # 草叶锯齿：顶部伸出的尖
        for x in range(0, W, 4):
            h = 3 + (x * 7 % 5)
            d.rectangle([x, 4 - h, x + 1, 5], fill=hexc(t["face"]))
            d.point((x + 1, 4 - h), fill=hexc(t["hi"]))
        for _ in range(10):
            x = rnd.randrange(W)
            d.point((x, rnd.randrange(7, 13)), fill=hexc(t["face_d"], 70))
    elif t["style"] == "stone":
        # 砖缝：横向砖 + 交错竖缝
        for y in (4, 11):
            d.line([(0, y), (W, y)], fill=hexc(t["face_d"], 170))
        for i, x in enumerate(range(0, W, 24)):
            off = 0 if i % 2 == 0 else 12
            d.line([(x + off, 4), (x + off, 11)], fill=hexc(t["face_d"], 150))
        for _ in range(20):
            x, y = rnd.randrange(W), rnd.randrange(5, 11)
            d.point((x, y), fill=hexc(t["hi"], 120))
    else:  # sand
        # 砂岩层理：横向细纹
        for y in (7, 10, 13, 16):
            d.line([(0, y), (W, y)], fill=hexc(t["face_d"], 110))
        for _ in range(16):
            x, y = rnd.randrange(W), rnd.randrange(5, 17)
            d.point((x, y), fill=hexc(t["hi"], 130))

    # 顶面高光：可站立面一眼可见
    d.rectangle([0, 0, W, 3], fill=hexc(t["hi"]))
    d.line([(0, 4), (W, 4)], fill=hexc(t["accent"], 90))
    return im


def make_plat(t):
    """浮空平台条：顶面高光 + 板体 + 底部暗边 + 下方投影（悬空感）。"""
    # 平台统一木质：浮空平台是木板结构，跟着主题变绿/变沙反而怪
    t = dict(face="#9a6a42", hi="#c89468", face_d="#6b4628",
             in1="#5a3a20", in2="#402815", dot="#7a5236", style="wood")
    im = Image.new("RGBA", (W, H_PLAT), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(hash(t["face"]) + 7 & 0xFFFF)

    body_top, body_bot = 2, 15
    d.rectangle([0, body_top, W, body_bot], fill=hexc(t["face"]))
    d.rectangle([0, body_bot - 4, W, body_bot], fill=hexc(t["face_d"]))

    if t["style"] == "wood":
        # 木板：竖木纹 + 缝
        for x in range(0, W, 16):
            d.line([(x, body_top), (x, body_bot)], fill=hexc(t["in1"], 200))
            d.line([(x + 1, body_top), (x + 1, body_bot)], fill=hexc(t["dot"], 120))
        for _ in range(18):
            x, y = rnd.randrange(W), rnd.randrange(body_top + 2, body_bot - 2)
            d.point((x, y), fill=hexc(t["in2"], 120))
    elif t["style"] == "stone":
        for x in range(0, W, 24):
            d.line([(x, body_top), (x, body_bot)], fill=hexc(t["in2"], 190))
        d.line([(0, 8), (W, 8)], fill=hexc(t["in2"], 120))
    else:
        for y in (6, 10):
            d.line([(0, y), (W, y)], fill=hexc(t["face_d"], 140))
        for _ in range(14):
            x, y = rnd.randrange(W), rnd.randrange(body_top + 2, body_bot - 2)
            d.point((x, y), fill=hexc(t["hi"], 110))

    # 顶面高光 + 底部投影
    d.rectangle([0, 0, W, 2], fill=hexc(t["hi"]))
    d.rectangle([0, body_bot + 1, W, body_bot + 3], fill=(0, 0, 0, 90))
    d.rectangle([0, body_bot + 4, W, body_bot + 6], fill=(0, 0, 0, 45))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for theme, t in THEMES.items():
        # 文件名保持与旧资源一致：town.tscn 等手写场景零改动受益
        make_ground(t).save(os.path.join(OUT, f"{theme}_top.png"))
        make_ground(t).save(os.path.join(OUT, f"{theme}_center.png"))
        make_plat(t).save(os.path.join(OUT, f"{theme}_plat.png"))
        print(f"{theme}: top/center {W}x{H_GROUND}  plat {W}x{H_PLAT}")


if __name__ == "__main__":
    main()
