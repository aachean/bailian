# 百炼

横版关卡制 ARPG。城镇整备 → 闯关打怪 → 打 Boss → 掉装备 → 打造强化 → 变强 → 推进主线。

| | |
|---|---|
| 引擎 | Godot **4.7.x** |
| 平台 | PC（Windows） |
| 界面语言 | 中文（默认），主菜单可切换英文 |
| 现在能玩到 | 主菜单 → 城镇 Hub（**老铁匠 NPC 会给你第一把剑** + 铁砧 + 传送门进关卡）→ 3 屏关卡：相机跟随，三种小怪（游荡者 / 疾行者 / 掷矛手）+ Boss；**对话与主线**、升级加点、旋风斩、打怪掉装备（四部位词条 + 图标）、铁砧强化；存档记录离开时的血量位置、装备与背包、剧情进度 |

---

## 怎么跑

1. 用 Godot 4.7.x 打开本目录下的 `project.godot`
2. 按 `F5` —— 进主菜单：开始游戏 / 继续游戏（有存档时）/ 语言切换 / 退出

**操作**：`A`/`D` 或 `←`/`→` 移动　·　`Space`/`W`/`↑` 跳跃　·　`J` 攻击 / **交谈**（连点三下是三段连招）　·　`K` 闪避（可打断自己的攻击）　·　`L` 旋风斩　·　`C` 角色面板　·　`B` 装备背包　·　`Esc` 暂停菜单

**存档**：3 个存档槽（`user://save_1..3.cfg`）。写档时机是暂停菜单里的「保存游戏」与回主菜单。
当前记录：关卡进度、玩家血量位置、每只怪的血量位置、精铁与武器强化等级、
等级与经验、**装备栏与背包**、**剧情进度标记**。

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
godot --headless --path . res://tests/check_scenes.tscn              # 场景完整性（16 个场景，缺节点即红）
godot --headless --fixed-fps 60 --path . res://tests/test_m2.tscn    # 菜单 / 槽位存档 / 语言（6 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m3.tscn    # 相机 / 传送门 / 新怪（12 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m4.tscn    # 等级 / 蓝量 / 技能 / 受击（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m5.tscn    # 装备掉落 / 穿戴 / 词条 / 图标 / 背包界面（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m6.tscn    # 对话框 / NPC / 主线推进（8 条）
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
