class_name DisassembleData
extends Resource
## 分解产量表（data/economy/disassemble.tres）：一件某档装备拆成哪些材料、各几个。
##
## 设计期唯一来源 = `docs/gear-v2/ECONOMY.md`「分解产量」表
## （由 `tools/apply_economy.py` 从设计期 JSON 生成，**别手改**）。
##
## ── 铁律：每档分解产量必须严格 < 该档打造成本 ─────────────────
## 否则「分解 → 重造」必赚，白嫖刷装。这条由 `tools/apply_economy.py`
## 每次落地都算一遍；改这边或改 crafting.tres 都要重跑它。
##
## ── 只按档次，不看强化 ───────────────────────────────────────
## 练到 +7 的传说拆出来和 +0 的传说一样多 —— 强化加成是「练上去花的精铁」，
## 拆的时候不返还。要是返还，强化就从「投资」变成「存款」，5.4 的驱动刷图就空了。
## 想回血精铁？卖掉（元宝）也是另一个去处 —— 卖与拆互不兑换（原则 5.1）。

## tier(int，字符串 key) → { 材料id: 数量 }
@export var yields: Dictionary = {}


## 拆一件某档装备得到什么。没登记的档次 = 空字典（调用方当「拆不出东西」处理）
func yield_for(tier: int) -> Dictionary:
	return (yields.get(str(tier), {}) as Dictionary)
