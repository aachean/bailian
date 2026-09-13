# 百炼

横版关卡制 ARPG。城镇整备 → 闯关打怪 → 打 Boss → 掉装备 → 打造强化 → 变强 → 推进主线。

| | |
|---|---|
| 引擎 | Godot **4.7.x** |
| 平台 | PC（Windows） |
| 界面语言 | 中文（默认），主菜单可切换英文 |
| 现在能玩到 | 主菜单 → 城镇 Hub（**老铁匠 NPC 会给你第一把剑** + 铁砧 + 传送门）→ **三关连成一条路**：第一关（3 屏 · 磨刀石守卫）→ 第二关（4.5 屏 · 重锤兵 / 掷火者 · 石甲卫）→ 第三关（5 屏 · 绝顶）。5 种小怪、2 个 Boss、7 个技能带 5 个、打怪掉装备（四部位词条 + 图标）、对话与主线；**关底 Boss 封着通往下一关的门**，中途有复活点，回城再出来直接送到你解锁到的最远那一关；存档记录离开时的血量位置、装备与背包、剧情进度 |

---

## 怎么跑

1. 用 Godot 4.7.x 打开本目录下的 `project.godot`
2. 按 `F5` —— 进主菜单：开始游戏 / 继续游戏（有存档时）/ 语言切换 / 退出

**操作**：`A`/`D` 或 `←`/`→` 移动　·　`Space`/`W`/`↑` 跳跃　·　`J` 攻击 / **交谈**（连点三下是三段连招）　·　`K` 闪避　·　**`1`~`5` 放技能**（`L` 是 1 号格的别名）　·　`C` 角色面板　·　`B` 装备背包　·　`V` 技能面板　·　`Esc` 暂停菜单

**存档**：3 个存档槽（`user://save_1..3.cfg`）。写档时机是暂停菜单里的「保存游戏」与回主菜单。
当前记录：关卡进度与**解锁到哪**、玩家血量位置与**复活点**、每只怪的血量位置、
精铁与武器强化等级、等级与经验、**装备栏与背包**、**剧情进度标记**、**携带的技能**。

> 测试会动存档槽（`test_m2` 要靠擦掉槽位来测隔离），所以测试跑之前会把三个槽
> 读进内存、跑完原样还回去（`tests/save_guard.gd`）。**没有这层保护的话，
> 跑一次回归 = 抹一次你自己的进度。**

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

它测不了「爽不爽」——那只能靠人玩；其余全部由它兜底。后续增量各自一组：

```
godot --headless --path . res://tests/check_scenes.tscn              # 场景完整性（24 个场景，缺节点即红）
godot --headless --fixed-fps 60 --path . res://tests/test_m2.tscn    # 菜单 / 槽位存档 / 语言（6 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m3.tscn    # 相机 / 传送门 / 新怪（12 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m4.tscn    # 等级 / 蓝量 / 技能 / 受击 / 头像经验环（16 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m5.tscn    # 装备掉落 / 穿戴 / 词条 / 图标 / 背包界面（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m6.tscn    # 对话框 / NPC / 主线推进（8 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m7.tscn    # 技能树 / 携带格 / 技能面板（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m8.tscn    # 第 2、3 关 / 门封印 / 复活点（14 条）
godot --headless --fixed-fps 60 --path . res://tests/probe_delivered.tscn   # 交付状态探针
```

> 新增带 `class_name` 的脚本后，第一次跑之前要先 `godot --headless --import`：
> 全局类缓存是在导入阶段写的，autoload 比它先加载，会报「Could not find type X」。

### 装备系统落在哪

```
data/items/*.tres          八件装备（部位 / 品质 / 三条词条），加装备不改代码
scripts/core/item_data.gd  ItemData：槽位与品质枚举、词条字段
scripts/core/player_state.gd  装备栏与背包（真相在这，玩家节点只是读者）+ 词条聚合缓存
scripts/characters/player.gd  _apply_upgrade() 把「强化 + 等级 + 装备」算成一个伤害倍率；
                              _refresh_blade() 让手里的光刃跟着武器换色换长
scripts/components/health.gd  damage_reduction：挨打侧减伤，上限 60%、保底 1 点
scripts/ui/item_icon.gd    程序化装备图标（按部位画形状、按品质上色，不引贴图）
scripts/ui/hud.gd          B 键装备背包（打开即暂停）+ C 键角色面板的装备概览
```

图标是**画的不是贴的**：16×16 的矢量形状，剑 / 盔 / 甲 / 坠四种轮廓，
颜色直接取品质色。同一件装备在 B 装备背包、C 角色面板、地上掉落物、
以及角色攻击时的光刃上**形状与颜色完全一致** —— 换了一件装备，四个地方一起变。
面板每行是代码建的 `[ItemIcon][Label]`；收文本做断言走 `hud.panel_texts()`，
布局怎么改都不用动断言。

### HUD 落在哪

```
scripts/ui/portrait_ring.gd  圆形角色头像 + 外层环形经验条（程序化自绘，不引贴图）
scripts/ui/hud.gd            血条蓝条等级 / 精铁计数 / 5 格技能栏 / 三个面板
scripts/ui/item_icon.gd      装备图标：形状 = 部位，颜色 = 品质
scripts/ui/skill_icon.gd     技能图标：每个技能一个手画形状 + 固定配色
```

三条写进设计规范的硬约束（改之前先看 `docs/design-conventions.md`）：

- **经验条是头像外圈的环，不是底部全屏细条** —— 底部那条永远在视野边缘，
  战斗中没人会把视线挪过去读它。省下来的一整条底部空间还给场景。
- **技能栏贴屏幕底边，单格 ≤ 40×30、横向 ≤ 240px**。
  第一版是 54×40，五格连起来横跨 286px（屏幕宽的 45%），把地面和怪都盖住了。
- **头像必须是场景里那个人**：配色直接取 `player.tscn` 的 Visuals。
  头像和角色不像，玩家会当成两个东西。

### 关卡推进落在哪

```
scenes/stages/level_1/2/3.tscn  三关连成一条路（3 屏 / 4.5 屏 / 5 屏）
data/enemies/*.tres             5 种小怪 + 2 个 Boss —— 新怪全是数据，不改代码
scripts/core/portal.gd          传送门：locked_by（被 Boss 封印）/ to_furthest（送到解锁到的最远那关）
scripts/core/checkpoint.gd      中途复活点：踩过就把「死后回到哪」推过去
scripts/core/save_manager.gd    unlock_level / furthest_level：把「解锁到哪」记进档
```

四条一眼看不出、但少一条就出问题的规矩：

- **关底 Boss 不重生**（`revive_delay = 0`）。小怪 2 秒站起来是对的，
  关底 Boss 重生的话「通关」这件事根本不成立。
- **读档复现尸体不能重放掉落**。`_on_died()` 拆成 `_dead_pose()`（摆尸）+
  「掉落 + 经验」，读档只走前半 —— 否则反复读档就能刷 Boss 掉落。
- **封印要学会复查**：门的解锁不能只靠 `Health.died` 信号。读档是关卡根在自己
  `_ready` 里把 Boss 摆成尸体的，信号早响过了，门会永远锁着。
- **地形要在跳跃预算之内**：抬升 ≤ 60px（跳跃高度约 73）、断口 ≤ 90px
  （跳跃距离约 113）。`test_m8 #14` 用**助跑跳实测**断口，算几何预算只是兜底 ——
  瞬移过对岸只能证明那边有地面，证明不了玩家跳得到。

### 剧情落在哪

```
data/dialogue/*.tres      一段对话：说话人 key + 若干句台词 key + 赠礼 + 进度 flag
scripts/core/dialogue_data.gd  DialogueData 资源类
scripts/ui/dialogue_box.gd     对话框（打字机 / J 推进 / 暂停世界 / 收起 HUD）
scripts/core/npc.gd            可交谈 NPC（走近按 J）
scripts/core/player_state.gd   flags：主线进度标记，进存档
```

**加一段剧情 = 加一个 `.tres` + 往 `data/i18n/ui.csv` 加几行**，不改代码。
「聊过没有」存在 `PlayerState.flags` 里而不是 NPC 身上 ——
切场景会重建 NPC，存在节点上的状态会丢（碎片那轮踩过这个坑）。

### 技能落在哪

```
data/skills/*.tres         技能表（含普攻 / 闪避 / 敌人招式），7 个玩家技能在里面
scripts/core/skill_data.gd SkillData：时序（按帧）+ 数值 + 效果字段
                            （heal_amount / guard_reduction / projectile_scene）
scripts/characters/player.gd   SKILL_PATHS 技能池；5 个槽位各带独立冷却；
                              _start_cast(slot) 走与普攻同一条「前摇→判定→后摇」
scripts/ui/skill_icon.gd   程序化技能图标（形状按技能 id）
scripts/ui/hud.gd          SkillBar 5 格 + V 键技能面板
scripts/core/player_state.gd  skill_slots（5 个槽的真相）+ skills_changed 信号
```

**加一个技能 = 加一个 `.tres` + `SKILL_PATHS` 加一行 + 往 csv 加名字 + 在
`skill_icon.gd` 里画个形状。** 解锁靠 `unlock_level`，升级时自动补进空槽；
槽满了换哪个由玩家在技能面板里决定（`docs/adr/0007`）。

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
