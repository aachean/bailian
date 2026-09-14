# 百炼

横版关卡制 ARPG。城镇整备 → 闯关打怪 → 打 Boss → 掉装备 → 打造强化 → 变强 → 推进主线。

| | |
|---|---|
| 引擎 | Godot **4.7.x** |
| 平台 | PC（Windows） |
| 界面语言 | 中文（默认），主菜单可切换英文 |
| 现在能玩到 | 主菜单 → 城镇（**老铁匠会给你第一把剑** + **铁匠铺** + **舆图台**）→ 走近舆图台按 `P` 开舆图 → 进**砺场**（3 屏）→ 通关解锁**断淬渠**（4 屏）→ 再解锁**炉喉**（5 屏，第一章终点）：一条条多屏的路，一屏的怪**分三批陆续出来**，**打完一批才出下一批**，全清了才走得过去；最后一屏打 Boss（磨刀石守卫 / 石甲卫 / 炉心守卫）；**打完整个副本才回舆图**。8 种小怪（含 3 个精英变体）、3 个 Boss、7 个技能带 5 个、打怪掉装备（四部位词条 + 图标）、对话与主线；**死了弹二选一**（重新开始 / 返回城镇）。**等级上限 100**（经验走幂函数，前快后慢；每级成长递减 —— 等级是解锁内容的钥匙，不是战力轴）；**强化逐件做，按品质封顶**（普通 3 / 精良 5 / 稀有 8），成本递增、收益递减；**有声音了**（空挥 / 命中 / 受击 / 拾取四声）；**有设置了**（背景音乐 / 音效 / 语言，暂停菜单与主菜单共用一块面板） |

> **砺场已按新结构重切**（2026-09-14，粒度重定过**两次**，两次都是玩过之后给的反馈）。
> 第一章的结构是 **地图「淬火岭」→ 三个副本（砺场 / 断淬渠 / 炉喉）**，
> 而**副本 = 一条 3~4 屏的路**：进一次从头打到尾，清完一屏往右推进，最后一屏出 Boss。
> **一屏 960px**（比视口宽，相机跟着滚）；**没有可见的闸门** ——
> 没清完就是走不过去（造梦西游的做法），撞上去才给一句提示。
> 进副本的唯一入口是**安全区的舆图台**（`P`）。
>
> **三个副本都做完了**（2026-09-14）：砺场 3 屏 / 断淬渠 4 屏 / 炉喉 5 屏，
> 通关一个才解锁下一个。砺场那一版形态被定为模板，另两个照它切
> （断淬渠带**远程与重锤**两种新敌人、炉喉用**精英变体**造难度）。
> 副本场景由 `tools/gen_dungeon_scenes.py` 从一张规格表生成 ——
> **改副本内容改那张表，别手改 `.tscn`**。
>
> 旧的线性关卡 `level_2/3.tscn` 已删除（内容重切进新副本）；
> 门封印（`portal`）与复活点（`checkpoint`）**按 ADR-0008 的政策保留代码、不再摆放** ——
> 它们现在没有任何关卡在用。
> **设计与决策文档不在本仓库** —— 所以别在代码里找「为什么」。

---

## 怎么跑

1. 用 Godot 4.7.x 打开本目录下的 `project.godot`
2. 按 `F5` —— 进主菜单：开始游戏 / 继续游戏（有存档时）/ 语言切换 / 退出

**操作**：`A`/`D` 或 `←`/`→` 移动　·　`Space`/`W`/`↑` 跳跃　·　`J` 攻击 / **交谈**（连点三下是三段连招）　·　`K` 闪避　·　**`1`~`5` 放技能**（`L` 是 1 号格的别名）　·　`C` 角色面板　·　`B` 装备背包　·　`V` 技能面板　·　**`P` 打开舆图**（站在安全区的舆图台旁，或清空一个副本之后自动弹出）　·　`Esc` 暂停菜单
　　　倒下之后：`↑↓` 选「重新开始 / 返回城镇」，`J` 确认

**存档**：3 个存档槽（`user://save_1..3.cfg`）。写档时机是暂停菜单里的「保存游戏」与回主菜单。
当前记录：**已清空的副本**、玩家血量位置、**这一屏打到第几批**、
精铁与武器强化等级、等级与经验、**装备栏与背包**、**剧情进度标记**、**携带的技能**。

> 旧结构（三层之前）的档不会作废：等级 / 装备 / 精铁照旧带回，
> 但「打到第几关」会重来 —— 存档列表上标着「旧版 · 进度重来」。
>
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
godot --headless --path . res://tests/check_scenes.tscn              # 场景完整性（34 个场景，缺节点即红）
godot --headless --fixed-fps 60 --path . res://tests/test_m2.tscn    # 菜单 / 槽位存档 / 语言（6 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m3.tscn    # 相机 / 城镇入口 / 新怪（12 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m4.tscn    # 等级 / 蓝量 / 技能 / 受击 / 头像经验环 / 血蓝数值（17 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m5.tscn    # 装备掉落 / 穿戴 / 词条 / 图标 / 背包界面（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m6.tscn    # 对话框 / NPC / 主线推进（8 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m7.tscn    # 技能树 / 携带格 / 技能面板（15 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m9.tscn    # 更长屏 / 看不到的挡墙 / 分批出怪 / 死亡二选一（10 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m10.tscn   # 等级上限 / 经验幂函数 / 装备实例 / 逐件强化 / 软硬上限（19 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m11.tscn   # 音效四声：空挥 / 命中 / 受击 / 拾取（7 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m12.tscn   # 暂停菜单两项 + 设置面板（10 条）
godot --headless --fixed-fps 60 --path . res://tests/test_m13.tscn   # 断淬渠 / 炉喉：四步法 / 锯齿 / 配置变体 / 坐标系（11 条）
godot --headless --fixed-fps 60 --path . res://tests/probe_delivered.tscn   # 交付状态探针
```

截图（要开窗口，输出到 `build/shots/`）：

```
godot --path . res://tests/shot_atlas.tscn    # 舆图台 / 舆图 / 撞上看不见的墙 / 第二批淡入 / 推进到第 2 屏 / 死亡界面
godot --path . res://tests/shot_forge.tscn    # 铁匠铺：打开 / 强化成功 / 精铁不够 / 已到顶 / 角色面板的武器强化
godot --path . res://tests/shot_pause.tscn    # 暂停菜单五项 / 设置面板 / 静音那一行 / 主菜单（会重出 menu.png）
godot --path . res://tests/shot_dungeons.tscn # 断淬渠/炉喉：配色 / 精英 / 夹击阵型 / 两个 Boss 挥招的判定帧
```

节奏与曲线的量级随时可打，不用进游戏：

```bash
godot --headless --fixed-fps 60 --path . res://tools/probe_pacing.tscn       # 副本形状 + 实测 DPS + 预计清怪时间
python tools/gen_dungeon_scenes.py                                          # 改完副本规格表之后重新生成两个副本场景
godot --headless --path . --script res://tools/probe_progression.gd          # 成长曲线（上限 / 经验 / 每级增量）
```
```

> 跑带战斗的测试（`test_m1` / `test_m4` / `test_m11`）时，末尾可能有一行
> `WARNING: N ObjectDB instances were leaked at exit`。**已知且已排查**：
> 是引擎的退出顺序问题（SceneTree 先于 AudioServer 清理），只在退出时出现，
> 不影响运行。别重复查它 —— 排查过程写在 `scripts/core/audio.gd` 的 `stop_all()` 上。
>
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

### 三层结构（地图 → 副本 → 关卡）落在哪

> **砺场已按这套结构做完**：一条 2880 宽（三屏 × 960）的副本场景。
> 断淬渠、炉喉还没切 —— 它们本来就是「多屏连续推进、走到底打 Boss」的形态，
> 切起来主要是加屏分组、批次容器与挡墙，比砺场容易。

```
data/stages/map_quench_ridge.tres   地图：淬火岭 → 三个副本（顺序即解锁顺序）
data/stages/dungeon_*.tres          副本：砺场（三屏）/ 断淬渠 / 炉喉（后两个是空壳）
scripts/core/map_data.gd            MapData：find_dungeon / dungeon_after / dungeon_before
scripts/core/dungeon_data.gd        DungeonData：场景路径 + 屏数 + 推荐实力 + is_ready()
scripts/core/game_progress.gd       GameProgress（autoload）：**唯一**算「副本开没开」的地方，
                                    也是唯一把「内容结构」和「存档进度」凑起来的地方
scripts/core/save_manager.gd        cleared：已通关的副本列表（就这一张表）
scripts/core/stage.gd               副本根节点：**屏 / 批次 / 挡墙 / 通关 / 快照** 全在这
scenes/stages/lichang.tscn          砺场：Screen1/2/3 三个分组，每组下 Wave1/2/3 装各批的怪
scenes/ui/atlas.tscn + scripts/ui/atlas.gd  舆图界面（P 键 / 通关后自动弹出，一行一个副本）
scenes/ui/death_menu.tscn           倒下之后的二选一（重新开始 / 返回城镇）
scenes/core/atlas_pedestal.tscn     安全区的舆图台（走近 → 提示 → 按 P）
tools/gen_stage_data.gd             生成上面那些 .tres（**不手写**，见下）
```

六条一眼看不出、但少一条就出问题的规矩：

- **屏与批次靠分组找，不靠硬编码坐标**。场景里给屏挂 `screen` 组、给批次挂 `wave` 组，
  关卡根节点按 x 与**子节点声明顺序**自己认。加一屏 = 加一个分组，加一批 = 加一个 `Wave`。
- **挡墙是关卡根节点动态建的，不摆进场景**。位置从 `SCREEN_WIDTH` 推出来，
  改屏宽不用重摆；而且**它必须是看不见的** —— 看得见就退回了被神否掉的那一版。
  代价：撞上去要出提示，否则玩家只会觉得"这里卡住了"。
- **没轮到出场的那批怪必须"休眠"**：看不见 / 不跑逻辑 / 不参与碰撞 / **退出 `enemy` 组**。
  少一件都会静默泄漏，最坏的一种是**这一屏永远清不掉**（组里永远有活怪）。
- **清空判定按「批次归属」算，不按当前位置**。怪被引着跑到隔壁去，
  按当前位置算会把这一批判成「已经清了」——那墙就白开了。
- **小怪一律不重生**（`revive_delay = 0`）。清空才放行，会重生的怪让屏永远清不掉。
  重生能力保留在训练房，不再用于副本内。
- **读档复现尸体不能重放掉落**。`_on_died()` 拆成 `_dead_pose()`（摆尸）+
  「掉落 + 经验」，读档只走前半 —— **否则反复读档就能刷掉落**（副本可以反复进，危害更大）。

### 已退役、但**按政策保留代码**的两样

```
scripts/core/portal.gd       传送门：locked_by（被 Boss 封印）/ to_furthest（送到解锁到的最远那关）
scripts/core/checkpoint.gd   中途复活点：踩过就把「死后回到哪」推过去
scenes/core/portal.tscn / checkpoint.tscn
```

**它们现在没有任何关卡在用**（`level_2/3.tscn` 已随重切删除）。
保留而不是删掉，是 ADR-0008 定的政策：*「删掉就得重写，留着是零成本的可逆开关」*。
新关卡**不许再摆**（`test_m13 #9` 盯着）——抄旧关卡时最容易把这两样一起抄过来。

两条对它们仍然成立的规矩：

- **关底 Boss 不重生**。Boss 重生的话「通关」这件事根本不成立。
- **封印要学会复查**：门的解锁不能只靠 `Health.died` 信号。读档是关卡根在自己
  `_ready` 里把 Boss 摆成尸体的，信号早响过了，门会永远锁着。
- **地形要在跳跃预算之内**：抬升 ≤ 60px（跳跃高度约 73）。三个副本都是
  **连续地面 + 浮台**，没有断口 —— 跨屏的障碍是看不见的挡墙而不是沟。
  抬升由 `test_m13 #2` 盯着（相邻台面超过 60px 就是「看得见但上不去」，而且不报错）。
- **砺场每屏不做断口**：每屏是「平地 + 浮台」，跨屏的障碍是**看不见的挡墙**而不是沟。
  掉下去就是死（重开副本），收益远小于风险。屏加长到 960 之后这条可以重新评估，
  但断口仍然该留给地形本来就有落差的地段。

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

**第二条（2026-09-14 补）：只写「没超过某个上限」是不够的，还要写「确实到了该到的地方」。**
测「挡墙挡人」那条时把玩家起点放在 x=450，正好撞上 x=470 那只游荡者的车身 ——
他被物理推着只动了 3px，而断言当时只检查「x 有没有超过 620」，**居然算通过**。
修法有两步：把跑道清空（怪挪走），以及把断言改成两头都卡（`> 900 且 < 950`）。
推论：**摆测试起点时要避开怪的车身**（敌人层是会挡人的）。

**第三条（2026-09-14 再补）：测试跑超时，先怀疑 Parse Error。**
脚本编译失败 → 场景根节点没脚本 → 主循环空转，看起来像"卡死"，会被误当成"这组断言太慢"。
短跑一次就有答案：`timeout 70 <godot> --headless --fixed-fps 60 --path . res://tests/test_mX.tscn`。
同一天还栽了两次更基本的：`"a%d b%d" % (x, y)` 在 GDScript 里**不是元组**，
括号里带逗号会当场 Parse Error（要写成 `% [x, y]`）；`var b := 某个 Variant 的 and` 推不出类型。
**改完断言先跑 3 帧做编译检查，再跑完整组** —— 省下一小时。

**第四条（2026-09-14 三补）：`detail` 里的值要在**那一件事发生的时候**取，不能等到打印时再算。**
铁匠铺那条断言把「暂停了吗」直接写在 `_check` 的参数里，而参数是 Esc 之后才求值的 ——
于是明明「打开时暂停了」，detail 打出来的是「暂停=false」，一句与事实相反的话。
**读 detail 的人会照着它去查错方向。** 先存进局部变量，再拼字符串。

**第五条（同日）：测「组件不在场」的断言，别在 `queue_free()` 之后再读那个节点。**
释放之后 `get()` 会报「Cannot call method on a previously freed instance」——
不崩，但 detail 变成一句废话。**先取值，再释放。**

### 可视化回放（**已停用**）

2026-09-14 起不再用。曾经每轮附一段「脚本自己操作、自己录制」的录像，
交付改用**无头断言 + 截图** —— 覆盖更严、成本低一个量级，代价是可观看性丢了
（静态截图看不出「我确实跟它打了 40 秒」，这个取舍是明确认下的）。

`tests/demo_reel.*` 与合成脚本**保留但不再使用** —— 删了就得重写。
它怎么跑、踩过什么坑，记在技能 `godot-headless-testing` 里。

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
│   ├── enemies/     敌人与投射物
│   ├── core/        场景中的实体：传送门 / 铁砧 / NPC / 复活点
│   ├── components/  可复用部件：掉落物 / 血条
│   ├── skills/      技能产生的场景（剑气波）
│   ├── stages/      城镇、关卡、测试房间
│   └── ui/          HUD / 面板 / 对话框 / 主菜单
├── scripts/         脚本（.gd），与 scenes 同构
│   ├── core/        真相与服务：PlayerState / SaveManager / GameSettings / 各资源类
│   ├── components/  Health / Hitbox / Pickup / Projectile
│   ├── characters/  玩家状态机
│   ├── enemies/     敌人 AI（walker 一个脚本覆盖全部小怪与 Boss）
│   └── ui/          HUD / 图标绘制 / 对话框
├── data/            数据资源（.tres）← 内容都长在这里，脚本里不写魔法数字
│   ├── enemies/  items/  skills/  dialogue/
│   ├── i18n/        界面文案（csv 源文件 + 导入产物）
│   ├── progression.tres  成长曲线（等级上限 / 经验公式 / 每级增量 / 软上限）
│   └── forge.tres        强化（品质上限 / 成本递增 / 收益递减）
├── assets/          字体（含 OFL 授权）、CREDITS.md
├── addons/          第三方插件 + ai_bridge（AI 实时操控桥）
├── tools/           资源构建脚本（字体子集化等，不参与游戏运行）
└── tests/           自动验收 / 截图（不参与游戏运行）
```
