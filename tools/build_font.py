"""从上游重新生成游戏内嵌的中文字体（子集化）。

为什么要子集化：Noto Sans SC 完整可变字体 17.7 MB，一个原型项目扛不动。
这里把它实例化成 Regular(400)、再裁到「GB2312 + ASCII + 中文标点」，
压到 1 MB 级后入库。

用法（在仓库根目录）：
    <python> tools/build_font.py

来源与授权：
    上游仓库 https://github.com/google/fonts  →  ofl/notosanssc
    版权 Copyright 2014-2021 Adobe (http://www.adobe.com/)，
    以 Reserved Font Name 'Source' 发布 —— 保留字体名 "Noto Sans SC" 合规。
    许可 SIL Open Font License 1.1，全文随字体放在 assets/fonts/OFL.txt。
    子集化产物属于 OFL 定义的 Modified Version，同样受 OFL 约束。

重新生成后记得到 Godot 里跑一次资源导入，否则 .import 是旧的。
"""

from __future__ import annotations

import io
import pathlib
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
FONT_DIR = REPO / "assets" / "fonts"
SRC_CACHE = REPO / "build" / "font-src"          # 已被 .gitignore 忽略
OUT_NAME = "NotoSansSC-Regular-subset.ttf"

API = "https://api.github.com/repos/google/fonts/contents/ofl/notosanssc"
SRC_FILE = "NotoSansSC%5Bwght%5D.ttf"            # NotoSansSC[wght].ttf
INSTANCE_WEIGHT = 400


def _fetch(path: str, dest: pathlib.Path) -> bytes:
    """走 GitHub API 的 raw media type 取文件（本机 raw.githubusercontent 不通）。"""
    url = f"{API}/{path}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "bailian-font-build",
        "Accept": "application/vnd.github.v3.raw",
    })
    with urllib.request.urlopen(req, timeout=300) as r:
        data = r.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return data


def charset() -> set[int]:
    """要保留的码位。"""
    cps: set[int] = set()

    # ASCII 可打印 + 制表/换行
    cps.update(range(0x20, 0x7F))

    # 拉丁补充：西欧重音字母（将来做英文/欧洲语言 UI 会用上）
    cps.update(range(0xA0, 0x100))

    # 常用符号、破折号、引号、省略号等
    cps.update(range(0x2010, 0x2070))
    cps.update({0x20AC, 0x2122, 0x2190, 0x2191, 0x2192, 0x2193, 0x2212, 0x221E})
    cps.update({0x25A0, 0x25B2, 0x25B6, 0x25C0, 0x25CF, 0x2605, 0x2606, 0x2665})

    # CJK 符号与标点（、、。「」等）
    cps.update(range(0x3000, 0x3040))
    # 全角字符
    cps.update(range(0xFF00, 0xFFF0))

    # GB2312 全集：6763 个汉字 + 各区符号，覆盖现代汉语日常用法
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                cps.add(ord(bytes([hi, lo]).decode("gb2312")))
            except UnicodeDecodeError:
                pass

    return cps


def main() -> int:
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        print("缺 fonttools。装：pip install fonttools brotli", file=sys.stderr)
        return 1

    FONT_DIR.mkdir(parents=True, exist_ok=True)

    # 1) 授权文件（OFL 要求随字体分发）
    ofl = FONT_DIR / "OFL.txt"
    if not ofl.exists():
        _fetch("OFL.txt", ofl)
        print(f"取回授权  {ofl.relative_to(REPO)}")

    # 2) 源字体（大，缓存在 build/ 下，不入库）
    src = SRC_CACHE / "NotoSansSC-var.ttf"
    if not src.exists():
        print("下载上游可变字体 …")
        _fetch(SRC_FILE, src)
    print(f"源字体    {src.stat().st_size / 1e6:.1f} MB")

    # 3) 实例化成 Regular
    font = TTFont(src)
    if "fvar" in font:
        print(f"实例化 wght={INSTANCE_WEIGHT}")
        font = instancer.instantiateVariableFont(
            font, {"wght": INSTANCE_WEIGHT}, inplace=False, updateFontNames=True
        )

    # 4) 子集化
    cps = charset()
    print(f"保留码位  {len(cps)}")
    opts = subset.Options()
    opts.layout_features = ["*"]        # 保留 OpenType 特性表
    opts.name_IDs = ["*"]               # 保留版权等 name 记录（OFL 要求）
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]

    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(unicodes=cps)
    subsetter.subset(font)

    # 5) 写出
    out = FONT_DIR / OUT_NAME
    font.flavor = None
    font.save(out)
    print(f"产出      {out.relative_to(REPO)}  {out.stat().st_size / 1e6:.2f} MB")

    # 自检：确认关键字符真的在
    check = TTFont(out)
    cmap = check.getBestCmap()
    for ch in "百炼攻击闪避跳跃设置语言中文开始退出生命值伤害":
        if ord(ch) not in cmap:
            print(f"  缺字 {ch} (U+{ord(ch):04X})", file=sys.stderr)
            return 1
    print(f"自检通过  字形数 {len(cmap)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
