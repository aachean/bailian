# 百炼

横版关卡制 ARPG。城镇整备 → 闯关打怪 → 打 Boss → 掉装备 → 打造强化 → 变强 → 推进主线。

| | |
|---|---|
| 引擎 | Godot **4.7.x** |
| 平台 | PC（Windows） |
| 界面语言 | 中文（默认）；英文文案已就绪，设置界面待 M2 |
| 现在能玩到 | 一个色块角色：左右跑、跳、落地（含土狼时间与跳跃缓冲）；三段连招、闪避（带无敌帧）；一个不还手、打死会满血重生的训练靶子；一种会巡逻、追击、挥击的近战小怪——挨打会硬直，死亡在出生点满血重来 |

---

## 怎么跑

1. 用 Godot 4.7.x 打开本目录下的 `project.godot`
2. 按 `F5`

**操作**：`A`/`D` 或 `←`/`→` 移动　·　`Space`/`W`/`↑` 跳跃　·　`J` 攻击（连点三下是三段连招）　·　`K` 闪避（可打断自己的攻击）

---

## 界面语言

界面文字一律走 Godot 内置的翻译系统，**任何地方都不写死人话**：

```
data/i18n/ui.csv        翻译源文件：一行一个 key，一列一种语言
data/i18n/*.translation 导入产物（由上面的 csv 生成，已入库，运行时不需要编辑器）
scripts/core/game_settings.gd   GameSettings（autoload）：set_language() / language_changed
```

- **默认固定中文，不跟随系统语言。** 中文是原作、英文是译件，两者完成度不对等；
  语言由玩家在设置里主动选（设置界面属于 M2，现在只留了接口）。
- 代码里用 `tr("KEY")`，场景里不写文案。新增一条文案 = csv 加一行。
- 加一种语言 = csv 加一列 + `GameSettings.SUPPORTED` 加一项。

### 中文字体

`assets/fonts/NotoSansSC-Regular-subset.ttf`（2.47 MB，SIL OFL 1.1，`OFL.txt` 随附）。
上游 17.7 MB 的可变字体，实例化成 Regular 后再裁到 GB2312 + ASCII + 中文标点。
**不要手动往仓库塞字体**，重新生成走脚本：

```
python tools/build_font.py      # 从上游重新拉取、子集化，末尾自带字形自检
```

改完字体要在 Godot 里过一遍资源导入，否则 `.import` 是旧的。字体缺字**不会报错**，
只会画空白 —— 所以有 `tests/shot_i18n.tscn` 截图兜底：

```
godot --path . res://tests/shot_i18n.tscn    # 中英各截一张到 build/shots/
```

---

## 自动验收

改完任何东西（尤其是手感数值）先跑这一条。它不开窗口，逐帧注入输入、测量物理量，
对 M1 验收清单逐条断言。**退出码 0 = 全通过。**

```
godot --headless --fixed-fps 60 --path . res://tests/test_m1.tscn
```

它测不了「爽不爽」——那只能靠人玩；其余全部由它兜底。

### 断言纪律（别破）

凡是用「瞬移角色」做的断言，只证明了碰撞盒和数值存在，**证明不了玩家做得到**。
所以断言里至少留一条走完整操作链的：真的助跑、真的按跳、真的落上去（见 `#12`）。
这条纪律是踩过坑补的：`#10` 把角色瞬移到台上自由落体，全绿，但当时「助跑跳上高台」
这个玩家真会做的动作其实没人验证过。

### 可视化回放（demo reel）

同一批机制的「可观看版」：脚本自己注入按键、自己打字幕、把 `on_floor` / `coyote` /
`buffer` / `velocity` 实时打在画面上，再录成视频。不需要人在场，也不需要装插件。

```
# 1. 录制（窗口模式；会在屏幕上开一个窗口，录完自动退出）
godot --path . --write-movie build/reel/frames.png --fixed-fps 60 res://tests/demo_reel.tscn

# 2. 合成 mp4（土狼/缓冲那两段 0.1 秒的窗口会被放慢 5×，否则肉眼看不出计时器在倒数）
python "%USERPROFILE%\.workbuddy\skills\godot-headless-testing\scripts\reel_assemble.py" --reel build/reel
```

> 合成脚本属于开发工具，不在本仓库里；它随技能 `godot-headless-testing` 走。
> 帧号对齐：录下的第 N 帧（从 0 起算）对应脚本里的 `tick = N + 1`
> —— 已用画面上的 `tick=` 读数核对过。录制尾部会多出约 24 帧（收尾等待期），
> 合成脚本按 `reel_meta.json` 里的总帧数裁掉。

画面截图（窗口模式，输出到 `build/shots/`，该目录不入库）：

```
godot --path . res://tests/screenshot.tscn
```

---

## 目录结构

```
res://
├── scenes/          场景（.tscn）
│   ├── characters/  角色
│   ├── enemies/     敌人
│   ├── stages/      关卡与测试房间
│   └── ui/          界面
├── scripts/         脚本（.gd）
│   ├── core/        核心服务：状态机、存档、事件总线、RNG
│   ├── components/  可复用组件：Hitbox / Hurtbox / Health / Skill
│   └── characters/  角色逻辑
├── data/            数据资源（.tres）← 内容都长在这里，脚本里不写魔法数字
│   ├── characters/  enemies/  equipment/  skills/  stages/
│   └── i18n/        界面文案（csv 源文件 + 导入产物）
├── assets/          sprites / audio / fonts（中文字体见上）
├── addons/          第三方插件 + ai_bridge（AI 实时操控桥，见上）
├── tools/           资源构建脚本（字体子集化等，不参与游戏运行）
└── tests/           自动验收 / 可视化回放 / 截图（不参与游戏运行）
```
