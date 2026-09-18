extends Node
## 音效（autoload）：**空挥 / 命中 / 受击 / 拾取 / 护罩** 五声。
##
## 第五声「护罩」（2026-09-18，ADR-0023）：Boss 相位期间玩家砍上去是打不动的，
## 而**「打不动」必须有声音** —— 否则玩家只会以为「我明明砍中了却没伤害」。
## 它和命中的区别就是「这游戏有没有在骗我」，所以两声的色系刻意拉开：
## 命中是短促的「咔」，护罩是更高更长的金属「铛」。
##
## 整体音量归 `GameSettings` 的「音效」总线管（设置界面那条）；本文件里的
## `VOLUME_DB` 只管**这几声彼此之间的比例**。两件事分开，互不干扰。
##
## ── 为什么先做这几声 ──────────────────────────────────────────
## 设计原则 6.1 是条 **[硬]** 规则：「有效命中至少给两项反馈」。
## 而在此之前整个游戏**只有顿帧一项**，而且**全程静音**。
## 音效是所有反馈里**最便宜的一层**，也是**首响应最快的一层** ——
## 它不需要等美术，一个字节的波形就能让「打中了」当场有回音（对应 6.2 的 100ms 首响应）。
##
## ── 为什么是程序化合成，不是引素材 ────────────────────────────
## 项目现在是 0 预算 + 色块阶段，音效素材要等 Kenney（CC0）那一轮。
## 但「三声」这件事**与素材质量无关** —— 值的部分是
## 「哪三个动作该响、什么时候响、响了给多大音量」。先把接口与触发点搭对，
## 素材来了只换 `_make_*()` 的返回值，**调用方一行不改**。
##
## 合成用的是**确定性算法**（噪声走哈希而不是 randi），
## 所以同一个音每次生成都逐字节一样 —— 断言能拿它当基准。
##
## ── 为什么是播放池，不是一个 player ───────────────────────────
## 同一瞬间可能「打中敌人的同时挨打」。共用一个 `AudioStreamPlayer`
## 会互相打断（后一个把前一个顶掉），于是最该听见的那声没了。
## 池子按轮转取，最简单，也不会漏。

## 采样率。**够用就行**：三声都不到 0.2 秒，44.1k 只是白白多一倍内存
const SAMPLE_RATE := 22050
## 同时最多几声响。8 够覆盖「连招 + 挨打 + 同时捡两件东西」
const POOL_SIZE := 8

## 同一声音的最小间隔（秒）。连招一次挥砍可能逐帧命中，
## 不节流会叠成一团噪声 —— 这不是「静默失败」，是听感上的必要处理
const MIN_GAP := 0.045

## 每声的响度（dB）。**按「响得多频繁」排** —— 越频繁的越轻，
## 否则连招一打起来全是兵器声，最该听见的那声反而被淹没：
##   空挥（每次出招都响，无论打没打到）＜ 命中 ＜ 护罩 ＜ 拾取 ＜ 受击。
## **空挥必须比命中低**：打中时两声是叠着放的，空挥要是压过命中，
## 就变成「打中了听起来跟空挥一样」—— 那正是这一版要解决的问题。
## **护罩比命中响一档**：它不常响（相位期间才会响），而且它是「你打不动」这条
## 信息的唯一载体 —— 听不清就白做了
const VOLUME_DB := {
	&"swing": -11.0, &"hit": -7.0, &"clang": -6.0, &"hurt": -4.0, &"pickup": -5.0,
}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}
var _last_at: Dictionary = {}
## 「有人要求播」的次数（自动验收用）。**节流不影响它** ——
## 否则断言会被节流骗过去：明明触发了，计数却不涨
var _requests: Dictionary = {}


func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		# 挂到「音效」总线：设置里那条音量条管的就是它。
		# 总线不存在时退回 Master —— 不静默失败到「整条音轨都没了」，
		# 而是退化成「音量条暂时管不着」。GameSettings 先于本节点启动，
		# 正常情况下总线一定在
		p.bus = GameSettings.SFX_BUS \
			if AudioServer.get_bus_index(GameSettings.SFX_BUS) != -1 else &"Master"
		add_child(p)
		_players.append(p)
	_streams = {
		&"swing": _make_swing(),
		&"hit": _make_hit(),
		&"clang": _make_clang(),
		&"hurt": _make_hurt(),
		&"pickup": _make_pickup(),
	}


## 播一声。名字不认识就**静默返回** —— 调用点只有三个，写错名字是编码期的事，
## 但工程上不该因为一个拼错的名字让游戏崩
func play(name: StringName) -> void:
	if not _streams.has(name):
		return
	_requests[name] = int(_requests.get(name, 0)) + 1
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - float(_last_at.get(name, -99.0)) < MIN_GAP:
		return                       # 太密就跳过播这一声，但上面已经记过一笔
	_last_at[name] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[name]
	p.volume_db = float(VOLUME_DB.get(name, -6.0))
	p.play()


## 全部停掉并释放引用。
##
## ── 一个**已排查过、决定接受**的现象（别再查一遍）──────────
## 播过音效之后，进程退出时会报
## 「Leaked instance: AudioStreamWAV / AudioStreamPlaybackWAV」（实测 2~4 个），
## 而且**只有 `--verbose` 看得出具体是什么**，普通输出里就是一行 WARNING。
##
## 排查结论：**这是引擎的退出顺序问题**（SceneTree 先于 AudioServer 清理），
## 不是接线错误。证据三条：
##   1. 在任何地方调这个 `stop_all()`（包括 `quit()` 之前 + 等两帧）都消不掉；
##   2. `test_m4` 在音效接进玩家**之前**没有这个 WARNING，之后有了 —— 它也播音了；
##   3. 泄漏数只与「退出那一刻有几种音刚播过」有关，与代码写法无关。
##
## 影响：仅退出时一行 WARNING，不影响运行（玩家看不到控制台）。
## 留着这个方法是因为它本身有用（切换场景/静音时要把在播的清掉）。
func stop_all() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _exit_tree() -> void:
	stop_all()


## 某个音被要求播过几次（自动验收用）
func play_count(name: StringName) -> int:
	return int(_requests.get(name, 0))


func reset_counts() -> void:
	_requests.clear()
	_last_at.clear()


## 三声的长度（秒）—— 断言与「以后换素材」都要用到
func duration_of(name: StringName) -> float:
	var s := _streams.get(name) as AudioStreamWAV
	return 0.0 if s == null else s.get_length()


# ── 合成 ───────────────────────────────────────────────────────
#
# 三声都遵守同一条形状：**指数包络**（`exp(-t × 衰减率)`）。
# 衰减率决定「这声有多干脆」：越大越短促，越小越拖。
# 音色靠「噪声 + 正弦」的配比与频率区分。

## 空挥：剑切过空气的「嗖」。
##
## **与命中是两层独立的声音**，不是「命中音的空版本」：
## 出招那一刻响这一声，砍到东西了再叠一声「命中」。
## 所以「空 A」= 只有空挥，「打中」= 空挥 + 命中，后者比前者亮 ——
## 玩家不看飘字也分得出这两件事，这正好补上 6.1 要的第二项反馈。
##
## 音色三处刻意跟命中拉开：**软起音**（噪声由小到大，像挥过去的加速度）、
## **下行扫频**（700 → 320Hz，音高往下走 = 划过去）、
## 衰减慢（26，是命中的一半）—— 拖一点尾才像「划过空气」，
## 命中那声（55）则是要干脆结束的
func _make_swing() -> AudioStreamWAV:
	return _synth(0.13, _swing_sample)


func _swing_sample(t: float) -> float:
	const DUR := 0.13
	const F0 := 700.0
	const F1 := 320.0
	# 软起音：前 22ms 渐入。**这一条是它跟命中最大的区别** ——
	# 命中的包络是「一开始就最大」，挥砍是「划过去」，起音必须有个坡
	var attack := minf(t / 0.022, 1.0)
	var env := attack * exp(-t * 26.0)
	var sweep := F0 + (F1 - F0) * (t / DUR)
	return (_noise(t) * 0.6 + sin(TAU * sweep * t) * 0.12) * env


## 命中：短促的「咔」。噪声为主 + 一点 220Hz 的实体感，
## 衰减最快（55）—— 打中的那一下必须**干净地结束**，拖尾会让连招听起来糊
func _make_hit() -> AudioStreamWAV:
	return _synth(0.085, _hit_sample)


func _hit_sample(t: float) -> float:
	var env := exp(-t * 55.0)
	return (_noise(t) * 0.75 + sin(TAU * 220.0 * t) * 0.35) * env


## 受击：闷的「咚」。低频（110Hz）为主、噪声只占一点，
## 衰减慢得多（22）—— 挨打是负反馈，它得比命中「更重、更沉」
func _make_hurt() -> AudioStreamWAV:
	return _synth(0.14, _hurt_sample)


func _hurt_sample(t: float) -> float:
	var env := exp(-t * 22.0)
	var body := sin(TAU * 110.0 * t) * 0.85
	return (body + _noise(t) * 0.18) * env


## 护罩：金属的「铛」（相位的无敌段，ADR-0023）。
##
## ── 与命中（咔）/ 拾取（叮）怎么分开 ────────────────────────────
## 三处刻意拉开，缺一处就听成同一个东西：
##   ① **两个不谐和的高频**（1240 / 1870Hz，不是整数倍）——
##      整数倍的和声听成乐音，不谐和的拍频才是金属。这是「铛」与「叮」的根本差别
##   ② **更长**（0.18s，命中是 0.085）—— 金属会响一会儿，不是「咔」一下就没
##   ③ **起音掺 12ms 的噪声冲击** —— 那是刀砍在罩子上的接触声
func _make_clang() -> AudioStreamWAV:
	return _synth(0.18, _clang_sample)


func _clang_sample(t: float) -> float:
	var metal := sin(TAU * 1240.0 * t) * 0.5 + sin(TAU * 1870.0 * t) * 0.35
	var strike := 1.0 + 0.6 * maxf(1.0 - t / 0.012, 0.0)
	var env := exp(-t * 24.0)
	return (metal + _noise(t) * 0.25 * strike) * env * 0.9


## 拾取：亮的「叮」。**上行扫频**（880 → 1320Hz）——
## 音高往上走天然带「得到」的感觉，往下走听起来像失去。
## 相位按积分算（f0×t + ½kt²），不然扫频会跑调
func _make_pickup() -> AudioStreamWAV:
	return _synth(0.16, _pickup_sample)


func _pickup_sample(t: float) -> float:
	const DUR := 0.16
	const F0 := 880.0
	const F1 := 1320.0
	var k := (F1 - F0) / DUR
	var phase := F0 * t + 0.5 * k * t * t
	var env := exp(-t * 14.0)
	return (sin(TAU * phase) * 0.9 + sin(TAU * phase * 2.0) * 0.2) * env


## 把采样函数渲染成 16-bit 单声道 WAV
func _synth(seconds: float, sample_fn: Callable) -> AudioStreamWAV:
	var frames := int(float(SAMPLE_RATE) * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(SAMPLE_RATE)
		var v: float = clampf(float(sample_fn.call(t)), -1.0, 1.0)
		data.encode_s16(i * 2, int(round(v * 32000.0)))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.stereo = false
	s.data = data
	return s


## 确定性噪声（白噪）。
## **不用 randi()**：那会让每次生成的波形都不一样，断言没法拿它当基准，
## 而且同一个音在两次运行里听感可能不同 —— 调音时最怕这个。
## 这里用「t 的哈希」：同一个 t 永远得到同一个 [-1, 1) 的值
func _noise(t: float) -> float:
	var x := sin(t * 12345.6789) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0
