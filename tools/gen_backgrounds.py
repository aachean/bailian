"""生成场景背景（像素风，三层视差 + 天空渐变）。

    python tools/gen_backgrounds.py

## 结构（每套主题三张，放 assets/backgrounds/<theme>/）

    sky.png   640x360  天空渐变 —— 屏幕固定，不参与视差（拉伸铺满）
    far.png   960x360  远景剪影（山峦/岩壁）—— 视差 0.25，横向无缝平铺
    mid.png   960x360  中景剪影（树线/渠坝/岩柱/屋脊）—— 视差 0.5，横向无缝平铺

## 为什么横向必须无缝

far/mid 用 TILE 平铺，首尾差一个像素就是一整条竖缝。所以剪影全部由
**周期函数**（sin/cos 组合）生成，x=0 与 x=W 天然同值。

## 主题
    grass  砺场·清晨草坡      stone  断淬渠·冷渠      sand  炉喉·炽炉
    town   淬火岭城镇·黄昏    title  主菜单·暮色锻炉
"""

from PIL import Image, ImageDraw
import math
import os
import random

W_VIEW, H_VIEW = 640, 360
W_TILE = 960
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "backgrounds")


def hexc(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def band_gradient(w, h, top, bot, steps=12):
    """像素风的分色阶渐变：不做平滑插值，而是明确可见的色带。"""
    im = Image.new("RGB", (w, h), hexc(top))
    d = ImageDraw.Draw(im)
    ct, cb = hexc(top), hexc(bot)
    for i in range(steps):
        y0 = int(h * i / steps)
        y1 = int(h * (i + 1) / steps)
        k = i / max(steps - 1, 1)
        col = tuple(int(ct[j] + (cb[j] - ct[j]) * k) for j in range(3))
        d.rectangle([0, y0, w, y1], fill=col)
    return im


def ridge(w, h, base_y, amp, color, freq=3.0, phase=0.0, jag=0.0, seed=1):
    """周期性的山脊剪影：正弦叠加保证首尾无缝。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    pts = []
    for x in range(w + 1):
        t = x / w * math.tau
        y = base_y
        y -= amp * (0.62 * math.sin(t * freq + phase) + 0.28 * math.sin(t * freq * 2.3 + 1.1)
                    + 0.10 * math.sin(t * freq * 3.7 + 2.3))
        if jag:
            y -= rnd.uniform(0, jag) if x % 7 == 0 else 0.0
        pts.append((x, int(y)))
    d.polygon(pts + [(w, h), (0, h)], fill=color)
    return im


def treeline(w, h, base_y, color, tree_h=34, gap=26, seed=2):
    """树线剪影：树干 + 三角/圆树冠，横向周期排布（首尾同相位）。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    period = gap
    n = w // period
    for i in range(n + 1):
        x = i * period
        hh = tree_h + rnd.choice([-6, 0, 0, 4, 8])
        tw = period - 8
        d.rectangle([x + tw // 2 - 2, base_y - hh // 3, x + tw // 2 + 2, h], fill=color)
        d.polygon([(x + tw // 2, base_y - hh), (x + 1, base_y - hh // 3),
                   (x + tw - 1, base_y - hh // 3)], fill=color)
    d.rectangle([0, base_y, w, h], fill=color)
    return im


def pillars(w, h, base_y, color, count=9, seed=3):
    """岩柱/渠坝剪影：宽度不一的不规则竖柱 + 底座。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    step = w // count
    for i in range(count + 1):
        x = i * step
        pw = step - rnd.randint(14, 26)
        ph = rnd.randint(int(h * 0.25), int(h * 0.55))
        d.rectangle([x, base_y - ph, x + pw, h], fill=color)
        d.rectangle([x - 3, base_y - ph, x + pw + 3, base_y - ph + 5], fill=color)
    d.rectangle([0, base_y, w, h], fill=color)
    return im


def townline(w, h, base_y, color, seed=4):
    """城镇屋脊剪影：方屋 + 三角檐 + 烟囱，周期排布。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    period = 96
    for i in range(w // period + 1):
        x = i * period
        bh = 54 + rnd.choice([-10, 0, 6, 14])
        bw = period - 12
        d.rectangle([x + 6, base_y - bh, x + 6 + bw, h], fill=color)
        d.polygon([(x + bw // 2 + 6, base_y - bh - 26), (x + 2, base_y - bh),
                   (x + bw + 10, base_y - bh)], fill=color)
        d.rectangle([x + 6 + bw - 18, base_y - bh - 46, x + 6 + bw - 10, base_y - bh - 20],
                    fill=color)
    d.rectangle([0, base_y, w, h], fill=color)
    return im


def gate(w, h, base_y, color, seed=5):
    """山门剪影（主菜单）：门楼 + 双柱，居中一个大门洞。"""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = w // 2
    d.rectangle([cx - 180, base_y - 30, cx - 130, h], fill=color)     # 左柱
    d.rectangle([cx + 130, base_y - 30, cx + 180, h], fill=color)     # 右柱
    d.rectangle([cx - 220, base_y - 52, cx + 220, base_y - 26], fill=color)  # 横梁
    d.polygon([(cx - 260, base_y - 52), (cx + 260, base_y - 52), (cx + 235, base_y - 84),
               (cx - 235, base_y - 84)], fill=color)                  # 檐
    d.rectangle([0, base_y, w, h], fill=color)
    return im


# ── 主题表 ────────────────────────────────────────────────────
# far = (底色, 山脊幅度, 频率, 基准线, 锯齿)
THEMES = {
    "grass": dict(
        sky=("#7ec3e8", "#e2f4fb"),
        far=dict(color="#6d92ad", amp=62, freq=2.6, base=214, jag=3),
        mid=dict(kind="tree", color="#2f5a3a", base=268),
    ),
    "stone": dict(
        sky=("#5f7288", "#bcc9d6"),
        far=dict(color="#46586e", amp=48, freq=3.4, base=206, jag=4),
        mid=dict(kind="pillar", color="#28313f", base=274),
    ),
    "sand": dict(
        sky=("#6e2416", "#e2873c"),
        far=dict(color="#3a1f18", amp=74, freq=2.2, base=210, jag=6),
        mid=dict(kind="pillar", color="#22120f", base=276),
    ),
    "town": dict(
        sky=("#e8a468", "#fadfb4"),
        far=dict(color="#7d6c86", amp=54, freq=2.8, base=208, jag=2),
        mid=dict(kind="town", color="#3a2c33", base=276),
    ),
    "title": dict(
        sky=("#161a38", "#6a3a5c"),
        far=dict(color="#252a4e", amp=80, freq=2.0, base=200, jag=4),
        mid=dict(kind="gate", color="#10112a", base=282),
    ),
}


def _tile2(im):
    """横向复制一遍（周期不变，覆盖范围 ×2）。"""
    out = Image.new("RGBA", (im.width * 2, im.height), (0, 0, 0, 0))
    out.paste(im, (0, 0))
    out.paste(im, (im.width, 0))
    return out


def main():
    for theme, t in THEMES.items():
        d = os.path.join(OUT, theme)
        os.makedirs(d, exist_ok=True)
        band_gradient(W_VIEW, H_VIEW, *t["sky"]).save(os.path.join(d, "sky.png"))

        f = t["far"]
        far = ridge(W_TILE, H_VIEW, f["base"], f["amp"], hexc(f["color"]),
                    freq=f["freq"], jag=f["jag"], seed=hash(theme) & 0xFF)
        # 横向拼两遍：TextureRect 在 Node2D 下尺寸会被贴图宽度压回，
        # 单周期 960 在视差负偏移时左侧露黑洞 —— 两周期 1920 才够盖住
        far = _tile2(far)
        far.save(os.path.join(d, "far.png"))

        m = t["mid"]
        if m["kind"] == "tree":
            mid = treeline(W_TILE, H_VIEW, m["base"], hexc(m["color"]))
        elif m["kind"] == "pillar":
            mid = pillars(W_TILE, H_VIEW, m["base"], hexc(m["color"]))
        elif m["kind"] == "town":
            mid = townline(W_TILE, H_VIEW, m["base"], hexc(m["color"]))
        else:
            mid = gate(W_TILE, H_VIEW, m["base"], hexc(m["color"]))
        mid = _tile2(mid)
        mid.save(os.path.join(d, "mid.png"))
        print(f"{theme}: sky {W_VIEW}x{H_VIEW} / far / mid {W_TILE}x{H_VIEW}")


if __name__ == "__main__":
    main()
