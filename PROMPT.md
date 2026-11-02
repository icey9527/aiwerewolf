# 开工提示词（把本文件整份发给新的 AI 窗口）

你要从零做一个**单机 Windows 游戏**：12 人狼人杀「圆桌审判」，Godot 4.4 + GDScript。
不要做 Web 页面，不要做 DSH 插件，不要接任何后端服务。玩家是**上帝视角观察者**，可切换跟随某个座位。

---

## 0. 项目主的硬需求（这几条不能改）

1. **三层严格解耦**：演出层只消费事件、不读逻辑层内部状态；逻辑层不依赖演出层与 AI 层；AI 层不碰场景。
2. **事件语义先定再写实现**，改协议先改文档。
3. **emotion 永不进入公共日志或任何 AI 上下文**——只走表现层通道。
4. **AI 输出必须过合法性校验**，非法返回走兜底策略（策略可配置）。
5. **座位数用配置和公式计算，不写死 12**（默认 12，板子以后会拓展）。
6. 引用其他玩家必须用**统一占位符**，禁止直接写名字或号码；模型自称用"我"。切换"位次/名字"显示模式时 AI 侧零改动。
7. **所有尺寸、时长、颜色、缓动参数集中管理**，不散落在组件里。
8. **先用占位资源把全流程跑通**，不为适配美术资源改逻辑。
9. 表现力优先：真 3D、弹丸论破式圆桌环绕镜头（旋转逻辑要有改编，不能太远太固定）；**不要小头像**；UI 按 DeepSeek 官方风格来做（深色、克制、主色 `#4D6BFE`）；界面与文案简体中文。

## 0.1 以下是**建议**，可以推翻（重要）

技术选型、工程结构、参数数值、事件命名、着色器写法——这些只是"上一轮试过、能跑通"的参考，不是规定。接手的 AI 完全可以重新设计；**换了方案就在本文件顶部写一句「决策变更 + 理由」**，别让下一个人猜。

建议（非强制）：

- Godot 4.4 + GDScript；**不用 `.tscn`**，全部代码建树（AI 看不到编辑器，`.tscn` 容易建出点不开的节点树）。
- 演出用"绝对虚拟时间 + 队列"驱动，不用 `await` 串状态——回放拖动（seek）才好做。
- 每完成一步就截图给项目主验收，不要一口气做完再给人看。

---

## 0.5 参考资产（本机路径，**开工前先看这些**）

### ① 2D 参考：装修/机位/演出节奏全都照它（最重要）

```
E:\ga_dr\                                  LÖVE 11.5 项目「舰船议会」，弹丸论破式 2D 圆桌审判
├─ src\core\camera.lua                     机位模型：6 标量(angle/distance/focal/height/pitch/roll)
│                                          + 就近转向 + 轨迹/漂移 —— 本文 §4 的镜头公式就出自这里
├─ src\scene_*.lua  src\ui_*.lua           讲台 / 立绘 / 底部字幕长条 / 警徽 / 投票箭头 的 2D 画法
├─ chr\        1051 张立绘 PNG             人物比例、站姿、朝向（**占位立绘可直接从这里挑**）
├─ face\       1130 张表情 PNG             情绪切图的命名与用法
├─ effect\      153 张特效 PNG             白闪 / 震屏 / 字幕爆点
├─ docs\  README.md  PLAN.md               设计说明与踩坑记录
└─ release\                                可运行的打包版
```

跑起来看（有 LOVE 就能直接跑）：

```powershell
& "C:\Program Files\LOVE\love.exe" E:\ga_dr
# 想抓指定时刻截图：& "C:\Program Files\LOVE\love.exe" E:\ga_dr --shots
# 截图落在 %APPDATA%\LOVE\trial_prototype\shots
```

### ② 早期镜头/投影参考（非必须，需要时再翻）

```
E:\ai_rts-main\                            RTS 视角、拾取、投影的简化实现
```

### ③ 狼人杀组件 / 立绘素材（由项目主提供）

```
[待填：狼人杀组件与素材目录]                  ← 路径待补；约定最终放到 res://assets/portraits/c01..c12/
```

### ④ 明确不要参考

```
F:\dsh-aiwerewolf\ 的旧 TypeScript / Three.js 代码
```

> 已清空、已废弃。只在需要考古旧参数时用 `git checkout c030216 -- .` 临时找回，**不要**把它当架构参考。
> 唯一值得抄的是旧仓库的 `docs\04-engine.md`（规则）、`docs\05-ai.md`（提示词），但那些内容本文 §6/§7 已经涵盖。

---

## 1. 目录结构（照建）

```
res://
├─ config.gd                 # 单例 Params：所有数字
├─ main.gd / main.tscn       # 装配：建 12 席、起一局、接 HUD
├─ world/  arena.gd table.gd seat.gd lights.gd portrait_face.gdshader
├─ camera/ camera_rig.gd shots.gd
├─ director/ director.gd beats.gd scheduler.gd
├─ game/   rules.gd roles.gd state.gd rng.gd
├─ ai/     deepseek.gd prompts.gd parse.gd fake_ai.gd
├─ ui/     hud.gd subtitle.gd theme.tres
└─ assets/ portraits/c01/idle.png … , fonts/NotoSansSC-*.ttf
```

---

## 2. 场景参数（写进 config.gd，直接用这些值）

```gdscript
# 尺度：人比桌子高得多，房间要够大 —— 否则只能俯视才装得下全桌（这是最容易做错的地方）
const TABLE_RADIUS := 3.0
const TABLE_TOP    := 0.22
const PODIUM_WIDTH := 2.9        # 讲台沿切向宽度
const PODIUM_DEPTH := 0.95
const PODIUM_HEIGHT := 1.05
const EDGE_GAP     := 0.55       # 相邻讲台净空
const PORTRAIT_H   := 2.45
const PORTRAIT_MAX_W := 1.70
const WALL_RADIUS  := 16.5
const WALL_HEIGHT  := 11.0
const FLOOR_RADIUS := 19.0

# 配色
const C_BG      := Color("#0E0F12")
const C_FLOOR_A := Color("#D8CFB2")   # 棋盘浅格
const C_FLOOR_B := Color("#14121A")   # 棋盘深格
const C_WALL    := Color("#4A0D16")
const C_WALL_RIB:= Color("#6B1420")
const C_GOLD    := Color("#9A7434")
const C_PODIUM  := Color("#5E1218")
const C_ACCENT  := Color("#4D6BFE")
const C_WOLF    := Color("#FF5A5F")
const C_SHERIFF := Color("#E8B45A")
const C_GOD     := Color("#4ECFA8")
```

**座位环半径必须由讲台宽度反推**（"围成一圈"不留缝）：

```gdscript
func seat_ring_radius(n: int) -> float:
    return (PODIUM_WIDTH + EDGE_GAP) / (2.0 * sin(PI / n))
    # 12 人 → 6.66 m
```

1 号座角 `-PI/2`（正对初始相机），逆时针递增；每个讲台/立绘**朝向桌心**（`look_at(Vector3.ZERO, Vector3.UP)`）。

---

## 3. 立绘（关键观感）

- 立绘是**固定朝向**的贴图面片，朝桌心；**背面必须是纯黑剪影**（可乘一点角色主色），不要永远转向相机。
- 长度 `PORTRAIT_H = 2.45`，底边贴讲台顶面（y = `PODIUM_HEIGHT`），视觉上像"人站在讲台后面"。
- 着色器要点：用 `dot(normalize(NORMAL), normalize(VIEW))` 判正反，背面 `mix` 到近黑；`cull_disabled`；`ALPHA_SCISSOR_THRESHOLD = 0.5`。
- **贴图是 sRGB 导入，不要再 pow(2.2)**（会二次压黑，人物变成一团剪影）。

开发期占位：直接从 `E:\ga_dr\chr\` 挑 12 张 PNG 裁成 1024×2048 透明底当占位（**只用于开发，正式素材由项目主提供**）。

素材约定（正式素材我以后会提供）：
```
assets/portraits/c01/idle.png   # 1024×2048 PNG，透明底
assets/portraits/c01/calm.png
assets/portraits/c01/think.png  angry  smug  hurt  shock
```
情绪 7 种：`idle calm think angry smug hurt shock`；`c01..c12` 对应座位 1..12。

---

## 4. 镜头（位姿 = 6 标量 + 注视点）

```gdscript
# radius 是「相机到 look_at 的距离」，不是到桌心的距离（搞错会贴脸）
func position_of(az, elev, radius, look_at) -> Vector3:
    var c := cos(elev)
    return look_at + Vector3(radius*c*cos(az), radius*sin(elev), radius*c*sin(az))
```

构图反解：`d = PORTRAIT_H / (2.0 * fill * tan(fov/2))`，然后 `radius = d`。

| shot | 仰角 | fov | 距离/构图 | 注视点 |
|---|---|---|---|---|
| establish 开场 | 18–22° | 50 | 环半径 +3.2 | 桌心 y=1.55 |
| orbit 环绕 | 8–12° | 40 | 环半径 +2.2 | 桌心 y=1.55 |
| speaker 特写 | 14–20° | 42 | fill 0.55 | **本人** |
| speaker_out 场外 | 6–10° | 42 | fill 0.45 | 本人 |
| speaker_side 三分线 | 10–16° | 42 | fill 0.32 | 本人 |
| vote_board 投票 | 44–48° | 50 | 环半径 +1.6 | 桌心 |
| execution 坠落 | -2–1° | 38 | fill 0.60 | 座位底 y=1.0 |
| nameplate 牌位 | 4–7° | 40 | fill 0.50 | 名牌 y=1.9 |
| dawn 天亮 | 10–13° | 46 | 环半径 +2.0 | 桌心 |
| badge 警徽 | 8–12° | 40 | fill 0.55 | 本人 |
| overview 总览 | 26–30° | 50 | 环半径 +5.0 | 桌心 |
| enter_character 入场 | 12° | 44 | 环半径 +2.0 | 本人 |

环绕角速度 `0.075 rad/s`，缓入 1.2s。转场：硬切 / 滑轨 900ms / 快速甩镜 600ms / 俯冲 900ms。

> **重要**：主视角一律在**桌面上方、低仰角**（r≈2–3、仰角 8–20°）。
> 不要用高空俯视装全桌——那会让人变成小图标、桌子变成一个甜甜圈（第一版就是这么废掉的）。

---

## 5. 演出 beat（毫秒）

- `execution` 坠落：0 切 execution + 开台 + 顶光收窄 → 700 台面开 → 1100 开始坠（重力 19.6）→ 1500 震屏 350 → 2400 合台 → 3200 回 orbit
- `dawn` 天亮：0 切 dawn + 白闪 180 → 600 回 orbit
- `sheriff_elected`：0 切 badge + 警徽飞向胸前 900 + 警灯亮
- `enter_character`：0 俯冲 1100 + 落地缓冲 300 → 1100 震屏 350
- `speak_start`：切 speaker + 灯亮 900 ／ `speak_end`：灯灭 600
- `vote_cast`：箭头从投票者讲台顶起飞，控制点抬高 2.1m 越过桌面，落点目标讲台顶

---

## 6. 规则（12 人标准局）

- 阵营：狼 4 / 神 4（**预言家、女巫、猎人、白痴**）/ 民 4
- 夜晚：**狼刀 → 预言家验 → 女巫（救或毒，二选一）→ 结算**
  - 女巫首夜可自救，之后不能自救
  - 猎人被刀或被投出可开枪；**被女巫毒死不能开枪**
  - 白痴被投出翻牌不死、失去投票权、仍可发言
- 白天：公布死讯 → 从死者下家顺序发言 → 全员投票 → 平票 PK 再投 → 出局
- 警长：首日竞选（上警/退水/警徽流），1.5 票，死亡可移交警徽或撕警徽
- 胜负：狼全死 → 好人胜；**屠边**（神全死 或 民全死）→ 狼胜
- 全部随机走固定 seed 的 `RandomNumberGenerator`，保证可回放

---

## 7. AI（直连 DeepSeek，不做后端）

- `POST https://api.deepseek.com/chat/completions`，`model=deepseek-chat`，`temperature=0.9`，`response_format={"type":"json_object"}`
- 每人一张人格卡（性格、口头禅、攻击性、抱团倾向），发言 1–3 句 / 60–120 字
- 信息不对称：狼人拿到队友与刀口，**允许并且应该撒谎**；好人只拿公开信息，不许上帝视角
- 输出契约：`{"say":"…","claim":"预言家|女巫|猎人|白痴|民|null","vote":7,"suspect":[6,9]}`
- 三层容错：直接解析 → 去 ```json 围栏/尾逗号/截首尾大括号 → 整段当 `say` 由规则层补默认
- **必须**有离线 `fake_ai.gd`：没填 key 或超时都能跑完整一局，绝不能卡流程
- 并发 ≤4，超时 20s，失败即降级

---

## 8. UI

- 顶部状态条：`● 第 N 天 · 白天发言` ｜ 右侧 `上帝 / 跟随03`、`1x 2x 4x`、暂停
- 底部字幕长条：圆角 16，深底，左侧 3px 身份色（狼红/警金黄/神绿/民灰），`03 周牧` + 正文打字机
- 字体 Noto Sans SC；正文 15px / 行高 1.7；字幕条宽 `min(760, 62vw)`
- 快捷键：`空格`暂停、`1–9`切镜头、`Tab`切跟随、`F`全屏

---

## 9. 交付顺序（每步截图验收）

1. 工程 + `config.gd` + 棋盘地面 + 红肋墙 + 中央圆台 → 能看到房间，60fps
2. 12 讲台按反推半径围一圈 + 占位立绘（固定朝向 + 背面黑）→ 截图无空档、背面是黑剪影
3. `camera_rig` + 全部 shot，数字键切换 → 构图正确、切换不卡
4. `scheduler` + 四套 beat（坠落/天亮/警徽/入场）→ 全程无跳变
5. 规则引擎 + 事件日志 → 无 AI 也能跑完一局
6. `deepseek.gd` + prompt + 容错 + fake_ai → 有 key 出真话、无网不卡
7. HUD + 字幕 + 投票箭头 + 控制条
8. 回放：同 seed 两次一致、可拖动 seek
9. `--export-release` 出 exe，双击即玩

---

## 10. 已知的坑（照躲）

| 坑 | 正解 |
|---|---|
| SVG 当立绘 | 一律 PNG |
| 贴图再 pow(2.2) | 会二次压黑，sRGB 导入后只乘亮度 |
| 着色器少声明 varying | 整材质编译失败 → 全黑 |
| 累加 dt 推进演出 | 低帧率下时钟比真实慢数倍；用绝对时间 |
| 同一帧灌一批 cue | 时间线打结；每帧最多推进一条转场 |
| `radius` 当成"到桌心距离" | 它是到 `look_at` 的距离 |
| 高空俯视装全桌 | 人变小图标；主视角在桌面上方低仰角 |
| 固定半径摆座位 | 人之间空一大截；半径由讲台宽度反推 |
| 逻辑写进节点 | 无法回放；逻辑只产事件 |

---

## 11. 一句话

先把「12 个讲台围成一圈 + 立绘固定朝向 + 低机位镜头 + 四套 beat」做出来给我看截图；
规则和 AI 放到第 5 步以后。**演出对了，这游戏就成了一半。**
