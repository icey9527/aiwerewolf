# AI 狼人杀 · 圆桌审判 — 实现设计文档

> **本文档的性质：参考方案，不是规范。**
> 接手的 AI 有权重新设计——技术选型、工程结构、参数数值、事件命名、着色器写法、演出节奏，全都可以推翻。
> 唯一必须遵守的是**项目主需求文档里的硬需求**（分层 / emotion 隔离 / 输出校验 / 占位符 / 参数集中 / 座位数参数化 / 占位资源先跑通）。
> 本文的价值只有一条：**上一轮真的写出来、跑起来过，哪些地方会踩坑**。翻新的方案如果更好，就照你的来，顺手在文档顶部记一句「决策变更 + 理由」。
>
> 施工提示词见仓库根 `PROMPT.md`（怎么开工）；本文是"为什么我当初这么选"（可当反面教材读）。

---

## 0. 我的取舍记录（建议，可推翻）

原始需求写的是 **Vite + TS + Three.js**，并且 M4 要做 DSH 集成。上一轮 Web 原型试错后，我建议改成 **Godot 4 单机**，理由逐条记账——**这只是我的判断，不是规定**，下一位可以换回去，只要理由站得住：

| # | 原始需求 | 当前决策 | 理由 |
|---|---|---|---|
| 1 | Vite + TS + Three.js | **Godot 4.3+ / GDScript** | 演出是主体（镜头、灯光、缓动、后期），Godot 编辑器 + 纯代码场景的迭代成本远低于手写 Three.js 管线；旧 Web 原型已删 |
| 2 | M4 — DSH 集成 | **降级为可选项（M4 可选）** | 项目主要的是"真正游戏"；Godot Web 导出（wasm 数十 MB + 跨源隔离）很重，先做桌面单机 |
| 3 | 立绘 billboard 始终面向相机 | **立绘固定朝向 + 背面纯黑剪影** | 项目主明确要求：围成一圈、背对镜头的角色是黑的（模仿 2D 原作的背面处理），全部 billboard 会让整圈脸都朝镜头，很假 |
| 4 | 圆桌 + 座位 | **圆桌 + 讲台（podium）**，座位环半径由讲台宽度反推 | 讲台是弹丸论破的视觉锚点；半径公式见 §5.1 |
| 5 | 座位数不写死 12 | 保持：`seat_count` 参数化，所有布局/镜头/事件按 `n` 计算 | 板子以后会拓展 |
| 6 | 不参考 ga_dr 的小头像 | 保持：**无小头像** | — |
| 7 | UI 用 DeepSeek 官方风格 | 保持：深色、低饱和、细描边、等宽数字、无花哨渐变 | — |
| 8 | 主持人 = 确定性状态机，非 AI | 保持 | — |

**仍然有效的核心约束**（一条都不能丢）：三层严格解耦；emotion 永不进入任何日志/AI 上下文；AI 输出必须过校验且有兜底；引用玩家必须用占位符；所有尺寸/时长/缓动集中管理；占位资源先跑通全流程。

---

## 1. 分层与数据流

```
                    ┌──────────────────────────────┐
                    │  Logic（确定性状态机）        │
                    │  game_state.gd / rules.gd     │
                    └──────────┬───────────────────┘
                               │ Event（结构化，唯一跨层通道）
                               ▼
   ┌───────────────┐    ┌──────────────────┐    ┌──────────────────┐
   │ AI（LLM 决策）│───▶│  Director（总线） │───▶│ Stage（Godot 演出）│
   │ ai_*.gd       │    │  director.gd      │    │ seat/portrait/... │
   └───────┬───────┘    └──────────────────┘    └──────────────────┘
           │ 只发"我要发言/我要投票"这类**意图**，不碰场景
           └──────────────▶ Logic（先校验再落子）
```

规则：
- **Stage 只读事件，不读 Logic 内部字段**。要新信息 → 加事件，不改读取路径。
- **Logic 不 import Stage / AI**。它只吐事件、只接受"已校验的动作"。
- **AI 不碰场景**，输出的是文本 + 情绪编号 + 动作意图，由 Logic 校验、Director 播报。
- 事件对象统一带上 `t`（虚拟时间毫秒）、`seq`（递增）、`type`。

### 1.1 事件类型表（第一阶段必须实现）

| `type` | 关键字段 | Stage 反应 |
|---|---|---|
| `round_start` | `round` | 镜头归位、桌面提示环轮次 |
| `phase_change` | `phase`(`night`/`dawn`/`sheriff`/`discuss`/`vote`/`last_words`) | 灯光/环境色切换 |
| `discussion_start` | `round` | 镜头开始环绕转圈（缓入缓出） |
| `speech_start` | `seat`, `emotion`, `text`, `visible_to` | 该座位高亮、立绘切情绪、镜头推近、字幕条推入 |
| `speech_end` | `seat` | 字幕条退场、镜头拉回环绕 |
| `vote_result` | `votes[{from,to}]`, `eliminated`, `outcome`(`exile`/`pk`) | 坠落演出 + 投票箭头 + 牌位切换 |
| `night_kill_reveal` | `seats[]` | **不坠落**，天亮后直接切牌位 |
| `sheriff_signup` | `seat` | 该座位警灯渐亮 |
| `sheriff_withdraw` | `seat` | 警灯渐灭（渐暗/瞬灭可配置） |
| `sheriff_elected` | `seat`, `votes` | 警徽标记 + 一段聚光 |
| `badge_transfer` | `from`, `to` | 警徽飞行 + 落位 |
| `player_eliminated` | `seat`, `mode`(`fall`/`reveal`), `reason` | `fall`=完整坠落；`reveal`=只切牌位 |
| `game_over` | `winner`, `reason` | 结算演出 |
| `emotion` | `seat`, `emotion` | **只走这条私有通道**，永不写日志 |

`visible_to` 三档：`["all"]` / `["wolf"]` / `[3,5]`（座位号数组）。

---

## 2. 工程结构（Godot）

```
res://
├─ project.godot
├─ main.tscn / main.gd              # 唯一入口：建树、装配、启动
├─ core/
│  ├─ params.gd                     # ★ 所有数值常量（尺寸/时长/缓动/颜色）
│  ├─ director.gd                   # 事件总线 + 虚拟时间 + cue 派发（Autoload: Director）
│  ├─ event.gd                      # 事件构造/校验的静态工具
│  └─ util.gd                        # 缓动、角度、格式化
├─ stage/
│  ├─ arena.gd                       # 圆桌 + 讲台环 + 地面 + 墙面
│  ├─ seat.gd                        # 单个讲台：几何体、名牌、警灯、状态
│  ├─ portrait.gd                    # 立绘 Quad + ShaderMaterial + 情绪换图
│  ├─ nameplate.gd                   # 牌位（灰度立绘 + 遗像框）
│  ├─ camera_rig.gd                  # ★ 机位求解（见 §5.2）
│  ├─ lighting.gd                    # 主光/聚光/环境/glow
│  ├─ voting_arrows.gd               # 投票箭头弧线
│  └─ effects.gd                      # 白闪、震屏、坠落
├─ shaders/
│  ├─ portrait.gdshader              # 固定朝向 + 背面纯黑
│  └─ floor_ring.gdshader            # 桌面提示环
├─ logic/
│  ├─ game_state.gd                  # 状态机主体
│  ├─ rules.gd                       # 角色/板子/胜负（屠边）
│  ├─ roles.gd                       # 角色定义：预女猎守 + 狼王 + 平民 + 狼人
│  └─ validate.gd                    # 动作合法性校验
├─ ai/
│  ├─ agent.gd                       # 单个 AI：上下文拼装、请求、解析、重试
│  ├─ memory.gd                      # 结构化私有记忆
│  ├─ prompt.gd                      # system prompt 模板 + 占位符替换
│  ├─ deepseek.gd                    # HTTPRequest 客户端（可换 base_url/model）
│  └─ fallback.gd                    # 非法输出的兜底策略
├─ replay/
│  ├─ recorder.gd                    # 事件流 → JSON
│  └─ player.gd                      # JSON → 时间轴重放/拖动
├─ ui/
│  ├─ subtitle.gd                    # 底部字幕条（DeepSeek 风格）
│  ├─ roster.gd                      # 侧栏名单/状态（无小头像，只有色块+名字+状态点）
│  ├─ settings.gd                    # 称呼显示模式、视角、倍速
│  └─ theme/                         # 字体、色板、九宫格
├─ assets/
│  ├─ portraits/c01..c12/            # 立绘 + manifest.json（含 emotion 映射）
│  └─ fonts/
└─ content/
   ├─ boards/standard12.json         # 板子定义（角色配比、可扩展）
   └─ events/demo_events.json        # M1 用的手写事件流（无逻辑层也能演）
```

**硬规矩**：不写 `.tscn`（编辑器场景文件），全部 `Node.new()` 代码建树。理由：AI 看不到编辑器，`.tscn` 是 AI 的重灾区；纯代码产物只有 `.gd`，可 diff、可 grep、可回滚。

---

## 3. 参数集中管理（`core/params.gd`）

单一字典，全部 `const`，禁止散落在各组件里：

```gdscript
class_name Params
extends RefCounted

const SEAT := {
    "body_width": 2.90,      # 讲台正面宽度（米）
    "body_depth": 1.10,
    "body_height": 1.55,
    "gap": 0.55,             # 相邻讲台之间的净空隙
    "ring_y": 0.0,
}

const PORTRAIT := {
    "height": 3.20,          # 立绘高度（米）
    "width_ratio": 0.72,     # 宽 = 高 × 该比例（1024×2048 素材 ≈ 0.5，留白用 0.72）
    "lift": 0.55,            # 立绘底边离讲台顶的高度
    "back_tint": 0.012,      # 背面近纯黑
}

const TABLE := { "radius": 3.00, "thickness": 0.22, "y": -0.30 }

const CAMERA := {
    "fov": 40.0,
    "orbit_radius_pad": 2.20,   # 环外机位 = 座位环半径 + 该值
    "orbit_height": 4.20,
    "orbit_speed": 0.055,       # 圈/秒
    "speaker_distance": 5.00,   # ★ 到"焦点"的距离，不是到原点
    "speaker_height": 2.35,
    "speaker_fov": 40.0,
    "ease": 1.35,               # 秒
}

const TIMING := {
    "fall": 1.10, "fall_depth": 9.0, "fall_shrink": 0.55,
    "lamp_on": 0.55, "lamp_off": 0.35,
    "enter_seat": 0.95, "shake": 0.18,
    "subtitle_in": 0.22, "subtitle_out": 0.18,
}

const COLOR := {
    "bg": Color("#0b0d10"), "surface": Color("#14171c"),
    "line": Color("#2a2f37"), "text": Color("#e8eaed"),
    "muted": Color("#8b929c"), "accent": Color("#4d6bfe"),   # DeepSeek 蓝
    "wolf": Color("#c0563f"), "gold": Color("#d8b25a"),
}
```

改参数 → 重启即生效；不用改任何组件代码。

---

## 4. 逻辑层（确定性状态机）

### 4.1 状态机

```
PREPARE → NIGHT(狼刀→查验→用药→守护) → DAWN(公布死讯)
        → SHERIFF(上警→发言→投票→警徽)  ← 仅第 1 天
        → DISCUSS(按座位顺序发言)
        → VOTE(投票→平票 PK→再投)
        → EXILE(放逐) → LAST_WORDS(遗言)
        → CHECK_WIN(屠边) → 下一夜 / GAME_OVER
```

- 纯函数化核心：`step(state, action) -> (state', events[])`，不用信号做控制流，方便单测和回放重建。
- 随机性来自注入的 `seed`（`RandomNumberGenerator`），**同一 seed + 同一动作序列 ⇒ 同一结果**，这是回放一致性的前提。
- 胜负：屠边（狼人杀光神职 or 杀光平民 ⇒ 狼胜；狼全死 ⇒ 好人胜）。

### 4.2 输出

每步只吐事件数组，按 `seq` 递增。绝不直接改 Stage 节点。

---

## 5. 演出层

### 5.1 布局公式（决定一切视觉密度）

座位环半径由**讲台宽度**反推，保证讲台首尾相接、间隙恒定：

```
R(n) = (body_width + gap) / (2 · sin(π / n))
```

- n=12 → R ≈ 6.66 m（讲台宽 2.90，间隙 0.55）
- 立绘宽度上限 = `R · 2 · sin(π/n) · 0.78`，保证相邻立绘不重叠
- 座位角 `θ_i = -π/2 + 2π·i/n`（第 0 座在正对镜头处），讲台 `rotation.y = -θ_i`（正面朝圆心）

**验证方式**：改 `n`，讲台与立绘必须自动适配、不重叠、不悬空。

### 5.2 机位求解（`camera_rig.gd`）

三档机位，全部从公式算，不用固定机位表：

| 档 | 位置 | 朝向 | 触发 |
|---|---|---|---|
| `ORBIT` | 圆心为轴，半径 `R + orbit_pad`，高度 `orbit_height`，匀速绕行 | `look_at(圆心)` | `discussion_start` / `speech_end` |
| `SPEAKER` | 在"发言者→圆心"的反向延长线上，距**发言者** `speaker_distance`，高 `speaker_height` | `look_at(发言者头部)` | `speech_start`（+ 轻微推近） |
| `ENTER` | 从高位（高 12m、半径 R+6）沿贝塞尔弧下坠到 `SPEAKER` 位 | 全程 `look_at` 目标座位 | `player_eliminated(mode=fall)` 之前 / 手动"进入角色" |

**关键点（上次踩过的坑）**：`speaker_distance` 是到 **look_at 目标**的距离，不是到原点的距离。若按"到原点距离"算，n=12 时会被推到 R 外 12m 开外，人像缩成火柴棍。实现时先算 `focus = seat.head_position`，再 `pos = focus + dir.normalized() * distance`。

环绕速度与缓入缓出：`t` 用 smoothstep 包一层，避免起停顿挫。

### 5.3 立绘：固定朝向 + 背面纯黑（核心视觉）

不用 billboard。每个立绘是一个 `QuadMesh` 朝圆心，背对镜头的面显示近纯黑剪影（模拟 2D 原作"背面是黑的"）。

`shaders/portrait.gdshader`：

```glsl
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 back_tint : source_color = vec3(0.012);
uniform float exposure_time = 0.0;     // 情绪切换时的闪白

varying float facing;   // +1 正面朝相机，-1 背面朝相机

void vertex() {
    // 固定朝向由节点 rotation 决定，这里只算朝向系数
    vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    vec3 to_cam = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
    facing = dot(n, to_cam);
}

void fragment() {
    vec4 c = texture(tex, UV);
    float front = smoothstep(-0.15, 0.15, facing);   // 侧对镜头时柔和过渡
    vec3 col = mix(back_tint, c.rgb, front);
    float a = mix(1.0, c.a, front);
    ALBEDO = mix(col, vec3(1.0), exposure_time * 0.6);
    ALPHA = a;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
```

注意：`varying` 必须**声明**，`CAMERA_POSITION_WORLD` 在 Godot 4 spatial shader 里可直接用（旧三个 bug 之一就是漏声明 varying 导致编译失败并有文件报污点）。

### 5.4 12 拍演出表（M1 必须全跑通）

| 拍 | 内容 | 时长 |
|---|---|---|
| 1 | 开场：黑场淡入，灯从底部一盏盏亮起，镜头慢推 | 4.0s |
| 2 | 环绕：绕桌一周，桌面提示环呼吸 | 6.0s |
| 3 | 进入角色：GTA 式高位下坠到某座位，落地震屏 | 1.0s |
| 4 | 发言：镜头推到该座位，立绘切情绪，字幕条推入 | 2.0s/人 |
| 5 | 上警：座位警灯渐亮，一盏接一盏 | 0.55s/人 |
| 6 | 退水：灯灭 | 0.35s/人 |
| 7 | 警长当选：聚光 + 警徽落位 | 1.6s |
| 8 | 投票：一圈箭头沿弧线飞出，落点脉冲 | 1.2s |
| 9 | 坠落：讲台开合 → 聚光 → 下坠 + 缩 + 淡出 → 牌位浮现 | 1.1s |
| 10 | 夜间刀：天亮直接换牌位（**无坠落**） | 0.4s |
| 11 | 遗言：镜头回推，字幕条变暗色 | 2.0s |
| 12 | 结算：全场灯灭，只留胜方阵营色 | 3.0s |

### 5.5 座位几何（程序化，不用 2D 图）

- 讲台：`BoxMesh`（圆角用 `QuadMesh`+bevel 或直接薄圆柱）+ 顶部斜面（`PrismMesh` 或自建 `ArrayMesh`）。
- 名牌环：`TorusMesh` 半圈，自发光材质可开关（警灯）。
- 状态：`alive`（正常）/ `dead`（牌位）/ `sheriff`（警徽 + 金边）/ `signup`（灯亮）。
- 灯光：主 `DirectionalLight3D`（斜上方）+ 每个座位一个低强度 `OmniLight3D`（发言时提高 energy），坠落时一个 `SpotLight3D` 从顶部打下来。

### 5.6 投票箭头

`ImmediateMesh` 沿二次贝塞尔（`P0=投票者头顶, P1=中点抬高 1.2m, P2=被投者头顶`）生成薄管；多条箭头按 `i` 错开抬升高度 0.18m，颜色按投票者阵营着色（上帝视角）/ 统一灰色（单一视角）。

---

## 6. AI 层

### 6.1 角色 = 立绘组 + API 配置 + 角色提示词（跨局固定，按角色分目录）

```
assets/portraits/c01/
├─ manifest.json      # {"name":"...","emotions":{"calm":"calm.png","think":"think.png",...}}
├─ calm.png think.png surprised.png angry.png sad.png smug.png idle.png
└─ portrait_meta.json # 锚点、缩放、可选的逐情绪偏移
```

身份**不属于**角色，由 Logic 每局分配后拼进 system prompt。

### 6.2 system prompt（只在发身份时发一次）

```
{角色提示词}

你正在参与 AI 狼人杀。
你在本局游戏中的身份是{身份名}，请选择自己认为合适的打法，帮助{阵营}走向胜利。
{若该身份有特殊规则（如狼王被放逐可开枪），在此追加}

输出必须是一个 JSON 对象，不要任何额外文字：
{"say": "...", "emotion": 0-6, "action": {"type": "...", ...}}
引用其他玩家时写占位符 {P3}（3 号座位），不要写名字或号码，自称用"我"。
```

私有记忆中固定保留身份信息，防长对话遗忘。

### 6.3 情绪编号（与身份解耦）

`0 平静 / 1 思考 / 2 惊讶 / 3 愤怒 / 4 悲伤 / 5 得意 / 6 待机（出戏）`

- **只进表现层**：不进公共日志、不进任何 AI 上下文。观众看得到，桌上 AI 看不到。
- 由发言内容驱动，不由身份驱动；没有身份专属情绪。

### 6.4 引用占位符

- 语法：`{P<n>}`，`n ∈ [1, seat_count]`，正则可校验 `\{P(\d{1,2})\}`。
- 显示模式切换（位次 / 名字）由 Stage 在渲染字幕时替换，AI 侧零改动。
- 校验：越界座位号 → 视为非法输出，走兜底。

### 6.5 上下文 = system + 私有记忆 + 最近一轮公共发言 + 可见性隔离信息

**不维护全量对话历史**。私有记忆结构（GDScript Dictionary）：

```gdscript
{
  "self": {"role": "seer", "camp": "good"},          # 固定，永不丢
  "players": {                                        # 对每个玩家的认知
    3: {"claimed": "seer", "votes": [4,7], "suspicion": 0.62, "notes": "..."},
  },
  "trust": {3: 0.4, 5: 0.8},
  "night_log": [{"night": 1, "action": "check", "target": 5, "result": "wolf"}],
  "events": [{"round": 1, "kind": "death", "seats": [8]}],
}
```

更新以**规则驱动**为主（关键词抽取、角色声称、投票行为），不额外调 LLM；关键行动后可选择性加一次"反思"调用。

### 6.6 校验与兜底（`ai/fallback.gd`）

1. `JSON.parse_string` 失败 → 重试 1 次（把错误信息附进重试 prompt）
2. 解析成功但字段非法（emotion 越界 / action 非法 / 目标座位越界 / 占位符越界）→ 修正可修正项（如 emotion 夹到 0-6），不可修正 → 兜底
3. 兜底动作（可配置）：`弃票` 或 `随大流`（投当前票数最高者），emotion=6（待机），`say` 用模板文本
4. 网络失败：指数退避重试 2 次 → 兜底

---

## 7. 回放

- 事件流按 `seq` 存 JSON，**每条事件携带完整参数**（emotion、票型、发言全文、可见性）。
- `ReplayPlayer` 复用同一个 `Director`，只是时间源从"实时"换成"按时间戳派发"。
- **拖动语义（重要）**：seek 到 `t` 时，先 `reset_stage()` 到初始态，再把 `t` 之前的事件**以 instant 模式逐条应用**（不播动画、直接设终值），最后从 `t` 继续正常播放。
  - 反例（上次踩过）：把 `t` 之前的事件一次性批量塞给 Director，所有 cue 在同一帧触发，动画互相打架，画面全乱。
- 倍速：`time_scale` 乘到虚拟时钟上，动画时长自动缩放。

---

## 8. 观演模式与设置

- **上帝视角**：全身份、夜间行动、全情绪立绘、全投票箭头。
- **单一视角**：锁一个角色，只显示其可见事件（按 `visible_to` 过滤）；情绪立绘只对该角色可见的发言生效。
- **切换动画**：镜头拉出（0.35s）→ 遮罩 120ms → 推入新视角（0.35s），中间帧用纯色遮罩掩盖跳变。
- 存活/出局/警长标记：所有视角可见。
- 设置项：称呼显示（位次/名字）、视角、倍速、退水灭灯（渐暗/瞬灭）、箭头显示范围、API（base_url/model/key）。

---

## 9. 里程碑与验收

| 阶段 | 内容 | 验收（可执行） |
|---|---|---|
| **M1** | Godot 演出原型：`content/events/demo_events.json` 驱动，12 拍全跑通 | 双击运行，12 拍无报错；改 `seat_count` 为 9/15 布局仍正确；截图 8 张关键帧 |
| **M2** | 逻辑层：12 人标准局完整流程，输出事件流 | headless 跑 100 局无异常；同 seed 两跑事件流字节一致；屠边判定覆盖测试 |
| **M3** | AI 层对接 + 校验 + 兜底 | 非法输出 20 种样本全部走兜底；情绪不入日志的断言；占位符替换在两种显示模式下正确 |
| **M4（可选）** | 导出 Windows exe / 或 DSH 集成评估 | 导出可运行；DSH 路径写评估结论 |
| **M5** | 美术替换与调优 | — |

headless 测试入口：`godot --headless --script tests/run_tests.gd`（自写断言，不引第三方框架）。

---

## 10. 待定项（默认值先定死，改时只改一处）

| 项 | 默认值 | 位置 |
|---|---|---|
| 退水灭灯 | 渐暗 0.35s | `TIMING.lamp_off` |
| 牌位形态 | 灰度立绘 + 遗像框（3D 墓碑备选） | `nameplate.gd` |
| 投票箭头范围 | 只显示本轮 | `params.COLOR` 附近 |
| 玩家是否上桌 | 不上桌（纯观演） | — |
| 音频 | 留 `AudioStreamPlayer` 接口，M1 不接 | `effects.gd` |
| 项目命名 | `ai-werewolf-trial`（避开 `dsh-werewolf`） | `project.godot` |
| 美术资源 | 开发期用 `E:\ga_dr\chr\` 挑 12 张占位 | `assets/portraits/` |

---

## 11. 自查清单（参考，非强制）

> 前 5 条来自项目主需求（真硬），后面几条是我的建议。方案改了的话，按新方案自己列清单。

- [ ] Stage 没有 `get_node("../logic")` 这类越层读取
- [ ] Logic 没有 `import res://stage/*`
- [ ] 任何日志/记忆/AI 上下文里搜不到 `emotion`
- [ ] 所有数值来自 `params.gd`，组件里无裸数字
- [ ] `seat_count` 改成 9 / 15 能跑
- [ ] AI 输出必经 `validate.gd`，非法有兜底
- [ ] 引用玩家用 `{P<n>}`，没有硬写名字
- [ ] 仓库里没有 `.tscn`
- [ ] 回放 seek 走"reset + 逐条 instant 应用"，不是批量塞
