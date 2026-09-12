# 百炼

横版关卡制 ARPG。城镇整备 → 闯关打怪 → 打 Boss → 掉装备 → 打造强化 → 变强 → 推进主线。

| | |
|---|---|
| 引擎 | Godot **4.7.x** |
| 平台 | PC（Windows） |
| 现在能玩到 | 一个色块角色：左右跑、跳、落地（含土狼时间与跳跃缓冲） |

---

## 怎么跑

1. 用 Godot 4.7.x 打开本目录下的 `project.godot`
2. 按 `F5`

**操作**：`A`/`D` 或 `←`/`→` 移动　·　`Space`/`W`/`↑` 跳跃　·　`J` 攻击（未实现）　·　`K` 闪避（未实现）

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
python tools/reel_assemble.py --reel build/reel
```

> `tools/reel_assemble.py` 在仓库外（`D:\workbuddy_projects\tools\`）——它属于开发工具，
> 不是游戏本体。

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
├── assets/          sprites / audio / fonts
├── addons/          第三方插件
└── tests/           自动验收 / 可视化回放 / 截图（不参与游戏运行）
```
