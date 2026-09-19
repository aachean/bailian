# 素材来源与授权

**这份文件是授权凭据，不是文档 —— 它必须随游戏一起分发。**
每引入一份外部素材，在下面加一行。**没登记的素材不许进仓库。**

## 规则

- 只收 **CC0 / 公有领域 / 明确允许商用** 的素材。
  CC-BY / OGA-BY 也可以，但必须在这里写清署名要求，并且**游戏内要有一处玩家看得到署名的地方**。
- 每次登记写四项：**来源 URL / 作者 / 许可 / 用途**。缺一项就算没登记。
  这四项不是形式 —— 免费素材最大的坑不是钱，是**来源记不清导致整个包不能用**。
- 自己生成或程序化绘制的素材登记成「本项目原创」，不占授权额度。
- 商用可用性存疑的（比如"免费但不许商用"、"仅限非商业项目"）**一律不收**。
  这个项目现在不卖，但拦不住以后想卖。

## 已引入

| 素材 | 来源 | 作者 | 许可 | 用途 |
|---|---|---|---|---|
| **FREE - Knight 2D Pixel Art** | https://xzany.itch.io/free-knight-2d-pixel-art | Mattz Art | 自定义（要点见下） | **主角（剑客 · 铁衣）**：10 动画 56 帧 —— 三段攻击 / 走跑 / 防御 / 受伤 / 死亡 |
| **Goblin Corps (MV Platformer Set)** | https://opengameart.org/content/goblin-corps-mv-platformer-set | MoikMellah | **CC0 1.0** | **全部小怪与 Boss**（哥布林农民 / 甲士 / 武士 / 骑士 / 领主等 10 个变体） |
| **Villagers Sprite Sheets Pixel Art Pack** | https://opengameart.org/content/villagers-sprite-sheets-pixel-art-pack | CraftPix.net 2D Game Assets | **OGA-BY 3.0**（**强制署名**） | **NPC**：老铁匠（拄拐老人）/ 猎人（壮汉），48×48 横版 |
| **Ranger [Animated]** | https://opengameart.org/content/ranger-animated | DezrasDragons | **CC0 1.0** | **主角（弓手 · 逐风）**：idle / run / attack / jump / 死亡 共 22 帧 |
| **Samurai [Animated]** | https://opengameart.org/content/samurai-animated | DezrasDragons | **CC0 1.0** | **主角（刀手 · 断岳）**：idle / run / attack / jump / 死亡（与逐风同作者同族，1x 帧一致） |
| **Mr. Necromancer Man [Animated]** | https://opengameart.org/node/39285 | Disthron | **CC0 1.0** | **主角（法师 · 玄机）**：idle / run / attack / 死亡（Classic Hero 家族切片，源文件 YeOldyNecroGuy.png） |
| Kenney UI Pack Pixel Adventure（节选 1 张面板格 `assets/ui/panel.png`，压暗作九宫格底） | https://kenney.nl/assets/ui-pack-pixel-adventure | Kenney | **CC0 1.0** | 全部 UI 面板（铁匠铺 / 商店 / 背包 / 暂停 / 设置 / 舆图 / 死亡 / 对话） |
| Noto Sans SC（子集化） | https://github.com/google/fonts | Google | **SIL OFL 1.1**（`assets/fonts/OFL.txt` 随附） | 界面中文字体 |
| AI 生成 · 逐风 HUD 头像 | — | 本项目用生图工具生成（2026-09-16） | 工具生成，无第三方权利负担 | 弓手头像 |
| AI 生成 · 地形贴图（`assets/tiles/`，JRPG 赛璐璐风） | — | 本项目用生图工具生成（2026-09-15） | 工具生成 | 砺场 / 城镇草地、断淬渠石、炉喉沙的地形表面 / 底层 / 浮台（ADR-0015） |
| 程序化生成 · 背景三层视差（`tools/gen_backgrounds.py`） | — | 本项目原创 | 本项目原创 | 五处 + 剑冢三变体的天空 / 远景 / 中景 |
| 程序化生成 · 地形条带贴图（`tools/gen_terrain_tiles.py`） | — | 本项目原创 | 本项目原创 | 三主题地形（草地 / 石渠 / 炽沙） |
| 程序化生成 · 像素房屋与告示牌（`tools/gen_props_pixel.py`） | — | 本项目原创 | 本项目原创 | 城镇铁匠铺 / 民居 / 两块告示牌 |
| 程序化生成 · 音效四声（`scripts/core/audio.gd`） | — | 本项目原创（代码合成，不引素材） | 本项目原创 | 空挥 / 命中 / 受击 / 拾取 |
| 程序化生成 · 装备与技能图标 | — | 本项目原创（`item_icon.gd` / `skill_icon.gd` 画形状上色） | 本项目原创 | 装备图标 / 技能图标 |

### 许可原文要点（抄自各包内附文件 / 素材页，供日后核对）

- **Mattz Knight 2D Pixel Art**（包内 `License.txt` 原文）：

  > You can use this asset in any game project, personal or commercial.
  > DO NOT resell or redistribute AS A GAME ASSET, it has to be part of a project.
  > Credit is not required but it is appreciated.
  > Modify to suit your needs.
  > You are NOT allowed to turn any of my assets to an NFT.

  **对我们的约束**：可以商用；**不能把素材本身当素材包转售或再分发**（作为游戏的一部分没问题）；
  **不强制署名** —— 但作者写明 appreciated，我们照署（已列入下方清单）。

- **Goblin Corps**（作者原话）：「License is CC0 - do as you wish. Attribution not necessary
  (but always appreciated).」**对我们的约束**：无。仍署。
- **Ranger [Animated]**（OGA 页面）：CC0 1.0。原作者基于 Jason-Em 的 Classic Hero 与
  Disthron 的 Plucky Girl Adventurer 绘制 —— **整条链都是 CC0**。仍署。
- **Villagers**（OGA 页面）：**OGA-BY 3.0** —— 本仓库里**唯一带强制署名义务**的素材。
  要求：注明作者（CraftPix.net 2D Game Assets），并提供指向来源页的链接。

### 署名清单（**游戏内必须有一处玩家看得到的地方**）

```
像素素材：
  Mattz Art       — FREE - Knight 2D Pixel Art
  MoikMellah      — Goblin Corps (MV Platformer Set)
  CraftPix.net    — Villagers Sprite Sheets Pixel Art Pack   ← 强制署名（OGA-BY 3.0）
  DezrasDragons   — Ranger [Animated] ／ Samurai [Animated]
  Disthron        — Mr. Necromancer Man
界面：Kenney（CC0）　字体：Google Noto Sans SC（SIL OFL）
完整来源链接见本文件。
```

> **当前状态（2026-09-17）：游戏内还没有这块署名处 —— 这是待补的合规项。**
> 网页版 v0.1 已经上线，其中使用了上述素材。**补上是必须做的，不是可选项。**

## 候选（未引入 · 排期中）

| 类别 | 首选来源 | 许可 | 说明 |
|---|---|---|---|
| 音效 | [Kenney.nl](https://kenney.nl) 音效包 | CC0 | 现在四声是代码合成的；换素材只改 `audio.gd` 的 `_make_*()`，调用方一行不动 |
| BGM | 备选 freesound.org / Pixabay Music | 逐条核对 | 音乐最容易踩授权，逐条登记 |
| 地形 tile | [Kenney.nl](https://kenney.nl) 像素平台跳跃类素材包 | CC0 | 现在地形是程序化生成 + AI 贴图，够用；要换时注意需 **16×16** tile |

> **为什么首选 Kenney**：CC0 意味着**不需要署名、不需要随附许可文本、可商用**，
> 对 0 预算且不想处理授权链的项目是最省事的来源。备选 OpenGameArt / itch.io Free
> 里大量是 CC-BY / OGA-BY 或自定义许可，收之前要逐包读过（本文件上半部分那几个就是）。
