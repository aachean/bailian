# AiBridge —— 让 AI 实时操控这个游戏

一个跑在游戏进程里的 TCP 桥。外部程序（AI/脚本）连上来之后可以：注入按键、
逐帧读取角色内部状态、抓真实渲染画面、重载场景。默认关闭，不带 `--ai-bridge`
启动时零开销。

## 为什么不用模拟键鼠（pyautogui / SendInput）

模拟 OS 键鼠看起来更"真"，但作为主通道有三个致命问题：

1. **不可复现** —— 窗口焦点、DPI 缩放、键盘布局、窗口位置都会影响结果。
   同一段操作在这台机器能过，换台机器就崩。
2. **看不见内部状态** —— 只能拿到像素。"土狼计时还剩 0.017 秒"这种信息
   截图里没有，但它恰恰是判断手感对不对的关键。
3. **没法逐帧对齐** —— 改一行代码前后要对比，必须保证两次跑的时序完全一致。

本桥走引擎自己的输入管线（`Input.action_press`），对游戏逻辑而言与真人按键等价；
同时按物理帧推送状态、在正确的时机抓渲染结果。两个世界的好处都有。

OS 级注入仍然有用，但只用来验证一件事：**真键盘能不能驱动窗口**（输入映射有没有配错）。
那部分见仓库外的 `tools/ai_bridge/os_input.py`。

## 启动

```bash
# 带桥启动（会开正常窗口，因为要真实渲染）
Godot_v4.7.2-stable_win64_console.exe --path . -- --ai-bridge

# 换端口 / 换截图目录
... -- --ai-bridge --ai-bridge-port=4500 --ai-bridge-shots=res://build/ai
```

`--` 之后是给游戏自己的用户参数，Godot 不会解析它们。

## 协议

换行分隔的 JSON（JSON Lines），UTF-8，只监听 `127.0.0.1`。

### 客户端 → 服务端

```json
{"cmd":"hello"}                                    // 握手，回包带场景名和可用 action
{"cmd":"key","action":"move_right","pressed":true}
{"cmd":"tap","action":"jump","frames":3}           // 服务端精确按住 3 个物理帧
{"cmd":"release_all"}
{"cmd":"state"}                                    // 立刻回一份当前快照
{"cmd":"shot","name":"apex","scale":0.5}           // 截图落盘，回包给绝对路径
{"cmd":"record","count":60,"interval":6,"prefix":"run01"}   // 连续截图，不阻塞控制流
{"cmd":"park","x":200,"y":280,"settle":true}       // 瞬移（测试用），回包带新状态
{"cmd":"autopush","value":false}                   // 关掉每帧状态推送（省带宽）
{"cmd":"reset"}                                    // 重载当前场景
{"cmd":"quit"}
```

### 服务端 → 客户端

**状态快照** —— 默认每个物理帧推一份（60 Hz，约 200 字节）：

```json
{"frame":1234,"ms":20566,"fps":60,"scene":"TestRoom",
 "events":["jumped"],"keys":{"move_right":true},
 "player":{"x":200.0,"y":304.0,"vx":180.0,"vy":0.0,
           "on_floor":true,"on_wall":false,"on_ceiling":false,
           "facing":1,"coyote":0.1,"buffer":0.0,"collisions":1}}
```

- `frame` 是桥自己的物理帧计数，客户端用它对齐操作与观察。
- `events` 是这一帧产生的跳/落/离地事件，读一次就清空。
- `coyote` / `buffer` 是 player.gd 里的土狼计时和跳跃缓冲计时，单位秒。
  这两个值是从外部判断手感问题的唯一依据 —— 截图里看不到。

**回包** —— 带 `ok` 字段的都是回包（`hello` / `shot` / `park` / `ack` 等）。
客户端分流时按 `ok` 判断，别按 `frame`：回包里也有 `frame`。

**注意**：`is_on_floor()` 是上一帧 `move_and_slide()` 的结果。用瞬移或走出边缘
做判定时，必须多等一帧，否则会误判（这条踩过坑）。

## 客户端

仓库外的 `tools/ai_bridge/`：

| 文件 | 用途 |
| --- | --- |
| `client.py` | 协议客户端。`step(n)` = 推进 n 个物理帧，`wait_until(pred)` = 反应式等待 |
| `run.py` | 启动带桥的 Godot 并等它就绪 |
| `play_m1.py` | M1 验收：真实操作链 + 断言 + 报告 + 截图 |
| `agent.py` | 反应式 agent：逐帧观察、逐帧决策 |
| `os_input.py` | OS 级真键盘注入验证（另一条链路） |
