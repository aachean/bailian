"""生成像素风 UI 素材（面板 / 技能格 / 血蓝条外壳）。

    python tools/gen_ui_pixel.py

## 为什么 UI 要统一到一套素材

在此之前 UI 是三套语言打架：面板是 AI 生成的手绘木板（`panel.png` + 棕色
modulate）、血蓝条是深灰 ColorRect、技能格是代码里的 StyleBoxFlat。
9 个 UI 场景全部引用同一个 `panel_style.tres`，所以**换掉 panel.png 与
stylebox 就能一次统一全部界面** —— 这是性价比最高的一处改动。

## 设计（中国风像素：深褐底 + 米金双线边 + 四角钉）

    外描边 #15100c  金边 #8a6a3a  内亮线 #d8b878  底 #2b211c
    底纹点 #332720  角饰 #f0dcab

全部按 9-slice 画（角与边不拉伸，只有中心被拉），所以同一张图能撑任意尺寸。
"""

from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ui")

EDGE_DARK = "#15100c"
GOLD = "#8a6a3a"
GOLD_HI = "#d8b878"
GOLD_TOP = "#f0dcab"
BG = "#2b211c"
BG_DOT = "#332720"
BG_DOT2 = "#241b16"


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def panel(size=48, margin=12, bg=BG, dot=BG_DOT, dot2=BG_DOT2, bright=True):
    """9-slice 面板：外描边 → 金边 → 内亮线 → 底 + 底纹点 + 四角钉。"""
    im = Image.new("RGBA", (size, size), hexc(bg))
    d = ImageDraw.Draw(im)

    # 底纹点（细碎深浅点，避免大面积死板）
    for y in range(margin, size - margin):
        for x in range(margin, size - margin):
            if (x + y) % 5 == 0:
                im.putpixel((x, y), hexc(dot))
            elif (x * 3 + y) % 11 == 0:
                im.putpixel((x, y), hexc(dot2))

    # 边框三层
    d.rectangle([0, 0, size - 1, size - 1], outline=hexc(EDGE_DARK))
    d.rectangle([1, 1, size - 2, size - 2], outline=hexc(GOLD))
    if bright:
        d.rectangle([2, 2, size - 3, size - 3], outline=hexc(GOLD_HI))
    d.rectangle([3, 3, size - 4, size - 4], outline=hexc(GOLD))

    # 四角钉（3x3 亮块 + 暗点，让边角有"铆钉"感）
    for cx, cy in [(4, 4), (size - 7, 4), (4, size - 7), (size - 7, size - 7)]:
        d.rectangle([cx, cy, cx + 2, cy + 2], fill=hexc(GOLD_TOP))
        d.point((cx + 2, cy + 2), fill=hexc(GOLD))
    return im


def slot(size=32, margin=8):
    """技能格：比面板更暗、边框更细，选中态靠外框高亮。"""
    im = Image.new("RGBA", (size, size), hexc("#1e1712"))
    d = ImageDraw.Draw(im)
    for y in range(margin, size - margin):
        for x in range(margin, size - margin):
            if (x + y) % 4 == 0:
                im.putpixel((x, y), hexc("#241c16"))
    d.rectangle([0, 0, size - 1, size - 1], outline=hexc(EDGE_DARK))
    d.rectangle([1, 1, size - 2, size - 2], outline=hexc(GOLD))
    d.rectangle([2, 2, size - 3, size - 3], outline=hexc("#5a4526"))
    return im


def bar_frame(w=20, h=14, margin=5):
    """血蓝条外壳：细金边 + 深底（内部留空给填充色）。"""
    im = Image.new("RGBA", (w, h), hexc("#120d0a"))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w - 1, h - 1], outline=hexc(EDGE_DARK))
    d.rectangle([1, 1, w - 2, h - 2], outline=hexc(GOLD))
    d.rectangle([2, 2, w - 3, h - 3], fill=hexc("#1a1310"))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    panel().save(os.path.join(OUT, "panel.png"))
    # 二级面板（提示条/弹窗）：底更亮一点，好和主面板区分
    panel(bg="#332620", dot="#3d2d26", dot2="#2b201a", bright=False).save(
        os.path.join(OUT, "panel_light.png"))
    slot().save(os.path.join(OUT, "slot.png"))
    bar_frame().save(os.path.join(OUT, "bar_frame.png"))
    print("panel.png / panel_light.png / slot.png / bar_frame.png 已生成")


if __name__ == "__main__":
    main()
