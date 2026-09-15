"""AI 生图素材后处理（ADR-0015 管线第 3 步）。

输入：纯色浅底 + 右下角水印的生图 PNG。
输出：透明底、去水印、裁到内容、统一高度的 PNG。

用法：
    python tools/process_art.py RAW_DIR OUT_DIR [--height 256] [--files a.png,b.png]

处理步骤（对齐 ADR-0015 §2.4）：
  1. 底色取样（四角中位数）
  2. 右下角水印区涂底色（角色居中，不会占到角）
  3. 按与底色的色距生成 alpha（色距 < 容差全透，2 倍容差内线性羽化）
  4. 裁内容 bbox
  5. 归一到目标高度（LANCZOS）
"""

import argparse
import os
import sys

from PIL import Image, ImageChops

TOLERANCE = 18          # 色距低于此值视为底色
FEATHER_FACTOR = 4      # alpha 斜率：色距 × 4 = 255 封顶
WATERMARK_FRACTION = (0.14, 0.08)   # 水印占宽/高比例（右下角）


def process_one(src: str, dst: str, target_h: int) -> None:
    img = Image.open(src).convert("RGBA")
    w, h = img.size

    # 1) 底色：四角各通道取中位数
    corners = [img.getpixel(p)[:3] for p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]]
    bg = tuple(sorted(c)[1] for c in zip(*corners))

    # 2) 右下角水印涂底色
    px = img.load()
    wm_w, wm_h = int(w * WATERMARK_FRACTION[0]), int(h * WATERMARK_FRACTION[1])
    for y in range(h - wm_h, h):
        for x in range(w - wm_w, w):
            px[x, y] = bg + (255,)

    # 3) 色距 → alpha（带羽化）
    diff = ImageChops.difference(img.convert("RGB"), Image.new("RGB", img.size, bg))
    alpha = diff.convert("L").point(
        lambda v: 0 if v < TOLERANCE else min(255, v * FEATHER_FACTOR))
    img.putalpha(alpha)

    # 4) 裁内容
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    # 5) 归一高度
    tw = max(1, round(img.width * target_h / img.height))
    img = img.resize((tw, target_h), Image.LANCZOS)
    img.save(dst)
    print(f"  {os.path.basename(src)} → {os.path.basename(dst)}  {img.size[0]}x{img.size[1]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--height", type=int, default=256)
    ap.add_argument("--files", default="", help="逗号分隔，缺省处理全部 png")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    names = (args.files.split(",") if args.files
             else sorted(f for f in os.listdir(args.raw_dir) if f.endswith(".png")))
    print(f"处理 {len(names)} 张 → {args.out_dir}（高 {args.height}px）")
    for name in names:
        process_one(os.path.join(args.raw_dir, name),
                    os.path.join(args.out_dir, name), args.height)


if __name__ == "__main__":
    sys.exit(main())
