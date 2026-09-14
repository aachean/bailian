class_name ProgressionData
extends Resource
## 角色成长的全局参数：等级上限、经验曲线、每级给多少。
##
## ── 为什么单独做成一份资源 ────────────────────────────────────
## 这些数字原本散在两处：经验公式在 PlayerState.exp_needed（线性 20 + (等级-1)×15）、
## 生命/蓝量/攻击的每级增量写死在 player.gd 里（100 + (等级-1)×15 / 50 + (等级-1)×10 / 0.05）。
## 曲线形状一变就要改两个文件里的三行魔法数，还容易漏一处。
## 收进 .tres 之后：调曲线不改代码，也补齐了「数值的唯一真相在资源」这条硬规则
## （设计原则 4.4）—— 以前它是唯一一条例外。
##
## ── 等级为什么必须有上限（设计原则 3.2）──────────────────────
## 等级是「解锁内容」的钥匙，不是主要战力来源。无上限的等级必然导致数值膨胀，
## 后期只能靠压缩数值救 —— 那等于把所有前面的内容重做一遍。
## 上限还有一个下游作用：舆图上的「推荐等级」全靠它才有意义。
##
## ── 经验为什么走幂函数（设计原则 3.3）────────────────────────
## 前期快、后期长尾：早期给成就感，后期拉长生命周期。纯线性曲线玩到第 20 级
## 和第 5 级的手感一模一样，成长没有「越来越重」的体感。
## 配套的校验只有一条：**最后 10% 的等级不能吃掉 40% 以上的总时长** ——
## 见 tail_share()，它就是为了让这条可以被断言、而不是靠眼睛看。

## 等级天花板。到顶后不再累积经验（不是「继续攒但没用」），
## 免得满级玩家的经验条还在涨、HUD 上显示一个永远用不到的数字
@export var level_cap: int = 30

@export_group("经验曲线：升到下一级所需 = exp_base × 当前等级 ^ exp_exponent")
## 曲线基数
@export var exp_base: float = 20.0
## 曲线指数。1.0 = 线性，1.5 起是 RPG 的常见区间（指数越高后期越长尾）
@export var exp_exponent: float = 1.5

@export_group("每级成长")
## 生命上限每级 +点
@export var hp_per_level: int = 15
## 蓝量上限每级 +点
@export var mp_per_level: int = 10
## 攻击倍率每级 +比例（0.05 = +5%）
@export var atk_per_level: float = 0.05

@export_group("1 级时的基础值")
@export var base_hp: int = 100
@export var base_mp: int = 50

@export_group("软上限：加总类属性（设计原则 3.4）")
## knee 以内**全额**，超出部分才走饱和曲线 —— 总效果趋近 knee + cap，永远到不了。
##
## 为什么不做成「一上来就递减」（raw / (1 + raw/cap)）：那会让**单件装备**的
## 显示值当场对不上（面板写 +15%、实际生效 +13.9%），直接违反 4.1
## 「界面显示的加成必须等于打出的数字」。带 knee 的曲线在正常装备量级下无损，
## 只在堆叠过头时才开始压 —— 那才是「防止无限线性堆叠」真正要防的地方。
@export var soft_knee_atk: float = 1.0
@export var soft_cap_atk: float = 1.0
@export var soft_knee_hp: int = 300
@export var soft_cap_hp: int = 300


## 边际递减（设计原则 3.4）：knee 以内原样返回，超出部分按饱和曲线追加。
## 折到 knee 以内是刻意的 —— 见上面那段「为什么不做成一上来就递减」
func soften(raw: float, knee: float, cap: float) -> float:
	if raw <= knee or cap <= 0.0:
		return raw
	var over := raw - knee
	return knee + over / (1.0 + over / cap)


## 升到下一级需要多少经验。**满级返回 0** —— 用之前一律先问 is_max()，
## 拿 0 去和当前经验比较会让「够了就升级」的循环空转成死循环
func exp_needed(level: int) -> int:
	if is_max(level):
		return 0
	return int(round(exp_base * pow(float(maxi(level, 1)), exp_exponent)))


func is_max(level: int) -> bool:
	return level >= level_cap


func clamp_level(level: int) -> int:
	return clampi(level, 1, level_cap)


## 该等级的生命上限（不含装备词条）
func hp_at(level: int) -> int:
	return base_hp + (clamp_level(level) - 1) * hp_per_level


## 该等级的蓝量上限
func mp_at(level: int) -> int:
	return base_mp + (clamp_level(level) - 1) * mp_per_level


## 该等级贡献的攻击倍率加成（叠进那个唯一的伤害乘区，见设计原则 4.1）
func atk_bonus_at(level: int) -> float:
	return atk_per_level * float(clamp_level(level) - 1)


# ── 曲线自检（给断言和「调数值时看一眼」用）────────────────────

## 从某级练到满级需要的总经验
func total_exp_to_cap(from_level: int = 1) -> int:
	var total := 0
	for lv in range(maxi(from_level, 1), level_cap):
		total += exp_needed(lv)
	return total


## 最后 frac 比例的那几级占总经验的多少。设计原则 3.3 要求 < 0.4
func tail_share(frac: float = 0.1) -> float:
	var total := total_exp_to_cap()
	if total <= 0:
		return 0.0
	var levels := int(ceil(float(level_cap - 1) * frac))
	var tail := 0
	for lv in range(maxi(level_cap - levels, 1), level_cap):
		tail += exp_needed(lv)
	return float(tail) / float(total)
