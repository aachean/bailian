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
└── addons/          第三方插件
```
