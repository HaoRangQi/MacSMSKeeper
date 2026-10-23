# 架构说明

## 总览

```
┌──────────────────────────────────────────────┐
│                    UI 层                      │
│  SwiftUI Views (NavigationSplitView / List)  │
└───────────────────┬──────────────────────────┘
                    │ @EnvironmentObject
┌───────────────────▼──────────────────────────┐
│                AppState（状态层）              │
│  筛选条件 · 选中集 · 统计 · 载入进度 · 语言/外观 │
└───────────────────┬──────────────────────────┘
                    │
┌───────────────────▼──────────────────────────┐
│                 Core（数据层）                 │
│  Database · Classifier · SearchEngine         │
│  DeleteService · Exporter · DemoData          │
└───────────────────┬──────────────────────────┘
                    │ SQLite3 C API
┌───────────────────▼──────────────────────────┐
│           ~/Library/Messages/chat.db          │
└──────────────────────────────────────────────┘
```

单向依赖：UI → State → Core → 数据库。Core 不引用任何 SwiftUI 类型（`Export` 除外，
它只用 Foundation），因此可被自检模式直接驱动。

## 模块职责

| 文件 | 职责 |
|---|---|
| `Core/Database.swift` | SQLite 轻量封装、Apple 时间戳转换、`attributedBody` 文本提取、权限检测 |
| `Core/Classifier.swift` | 打分制分类引擎，输出类别 + 置信度 + 命中理由 |
| `Core/SearchEngine.swift` | 查询语法解析与过滤排序 |
| `Core/DeleteService.swift` | 备份、回收站存档、事务删除、还原、清理规则匹配 |
| `Core/Exporter.swift` | Markdown / 纯文本 / CSV 生成 |
| `Core/DemoData.swift` | 生成同构演示库，无权限时保证界面可用 |
| `State/AppState.swift` | 全局状态与业务编排 |
| `Models/Localization.swift` | 以中文原文为 key 的轻量 i18n |

## 关键设计决策

### 1. 只读副本 + 写时直连

读取时以 `SQLITE_OPEN_READONLY` 打开原库；若因 WAL 权限打不开，则把
`chat.db` / `-wal` / `-shm` 复制到临时目录再读。

写入（删除）时才以读写模式打开原库，并且必须满足：**「信息」App 已退出**。

### 2. 删除的四层保护

```
退出 Messages → 整库快照(VACUUM INTO) → 被删行存档(JSON) → 事务删除 + checkpoint
```

- 备份用 `VACUUM INTO` 生成一致性快照，失败回退文件复制
- 存档保留原始行（含 `attributedBody` 的 base64），可逐条还原
- 删除按 400 条分块，规避 SQLite 变量数上限
- 任何一步失败都回滚，且界面不会误报成功

### 3. 分类：打分而非关键词命中

每个类别累加信号分（强关键词 +0.34、弱关键词 +0.14、正则特征 +0.1~0.2），
取最高分；低于 0.34 归为「其他」。验证码有额外规则：先扫描 4~8 位连续数字，
再排除年份、金额、订单号，命中强关键词才锁定。

选择打分而非 if-else 的原因：真实短信常常同时命中多类（例如「银行验证码」），
打分能表达优先级，也方便输出「命中理由」给用户看。

### 4. 性能：避开 Swift 字符串的坑

首版 1 万条分类耗时 **11 秒**，定位到三个问题：

| 问题 | 处理 | 收益 |
|---|---|---|
| `String.contains` 走字符簇比较，中文极慢 | 改用 `Data.range(of:)` 字节匹配，关键词预编译成 `Data` | ~7× |
| 验证码用 `NSRegularExpression` | 改为手工扫描 ASCII 数字串 | 显著 |
| `DateFormatter` 在统计循环里逐条调用 | 改用时间戳整数做 key，格式化器全局复用 | ~0.5s |

最终 1 万条：读取 150ms + 分类 1.4s + 统计 20ms。

分类按 500 条分块并 `Task.yield()`，配合独立的 `LoadStatus` 对象，
进度刷新只重绘遮罩层，不会带着整个页面重绘。

### 5. 列表不用 `List(selection:)`

SwiftUI 的 `List(selection:)` 在「Section + badge + 行内按钮」组合下，
点击会返回 `nil`，导致侧边栏点不动（实测复现）。

改为自行处理点击：`List {}` + `.onTapGesture` + `.listRowBackground` 自绘高亮，
行为完全确定。代价是失去方向键导航，⌘A / ⌘⌫ 等菜单快捷键仍在。

侧边栏同理，改为普通 `Button` 行，不依赖 List 的选择机制。

### 6. 本地化：中文原文作 key

```swift
L.t("验证码")            // zh → "验证码"，en → "Codes"
L.t("共 %d 条", n)       // en → "%d messages"
```

好处是不用改动任何中文文案，缺翻译时自动回落中文，不会出现空白。

`L.code` 使用 `nonisolated(unsafe) static var`，因为 `Category.label` 这类
非 MainActor 计算属性也要读取它。

> 注意：Swift 会把大字典字面量优化为 `Dictionary(uniqueKeysWithValues:)`，
> **重复 key 会在运行时 `fatalError`**。新增词条后务必查重。

### 7. 外观：一体化背景

- 窗口 `isOpaque = false`、`titlebarAppearsTransparent = true`、`fullSizeContentView`
- `.containerBackground(for: .window)` 铺一层「材质 + 主题渐变」
- 所有面板透明，列表 `scrollContentBackground(.hidden)`
- 不透明度滑块控制渐变浓度，实现从「实心」到「沉浸」的连续过渡

## 为什么不用 Xcode 工程 / SPM

- 目标机器只装了 Command Line Tools，没有完整 Xcode
- SPM 的 executable target 无法直接产出带 `Info.plist` 和资源的 `.app`

因此用 `swiftc` 直接编译 + 脚本组装 bundle，`make build` 一条命令完成。

副作用：Command Line Tools 缺少 SwiftUI 宏插件，**`@State` 不可用**，
局部状态统一用 `ObservableObject` + `@StateObject`。

## 数据表关系

```
message ──< chat_message_join >── chat
   │
   └──< message_attachment_join >── attachment
   │
   └── handle（发件人）
```

读取时只取 `item_type = 0`（普通消息），并按 `ROWID` 去重（同一条消息可能属于多个会话）。

## 已知限制

- 只处理已同步到 Mac 的短信
- 分类基于中文语境与国内服务号习惯，英文短信识别率较低
- 未做公证，分发时用户需要手动允许
