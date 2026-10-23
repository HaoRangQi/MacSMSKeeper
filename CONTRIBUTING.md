# 贡献指南

## 开发环境

- macOS 26+
- Command Line Tools（`xcode-select --install`）
- 不需要完整 Xcode

```bash
make build
make run
```

## 提交前自检

```bash
make clean && make build   # 必须零警告
make selftest              # 必须输出「结论 通过」
```

如果改动了界面，顺手跑 `make snapshot` 更新截图。

## 代码结构

| 目录 | 职责 |
|---|---|
| `Sources/App` | 应用入口、AppDelegate、开发期自检 |
| `Sources/Core` | 数据层：数据库、分类、搜索、删除、导出、演示数据 |
| `Sources/Models` | 数据模型、本地化词条 |
| `Sources/State` | 全局状态 `AppState` |
| `Sources/UI` | SwiftUI 视图与主题 |

## 约定

- **不要用 `@State`**：本机 Command Line Tools 缺少 SwiftUI 宏插件，`@State` 无法展开。
  局部状态请用 `ObservableObject` + `@StateObject`。
- **`L.t()` 的参数必须是单个完整字符串字面量**，不能用 `+` 拼接。拼接会让
  `check-localization.py` 抓到不完整 key、运行时查不到词条，英文模式回落中文。
- **`DatePicker` 不能放进 `Menu`**：macOS 会把菜单内的日期控件渲染成禁用状态，
  要用独立 `.popover`。
- **`ImageRenderer` 渲染不了 AppKit 控件**（`NSTableView`、`DatePicker` 的
  `nsImage` 会挂起），这类视图用自检逻辑验证，别写离屏渲染代码。
- **回收站批次 ID 必须带毫秒 + 序号**：秒级精度会让同一秒内的连续删除互相覆盖
  存档文件。批次文件要在删除提交并读回校验**之后**再写，否则事务内才收集得到的
  数据（如被清空的会话行）会漏存。
- **写 `chat.db` 前必须退出「信息」App**（`terminate()` 后轮询确认），并先整库备份。
  库内触发器会调用「信息」App 注册的私有 SQL 函数，命名没有规律，
  靠扫描 `sqlite_master` + `SELECT name()` 探测补齐，不要硬编码函数名。
- 界面文案统一走 `L.t("中文")`，并在 `Sources/Models/Localization.swift` 补英文词条。
- **词条 key 不能重复**：Swift 会把大字典字面量优化成 `uniqueKeysWithValues`，
  重复 key 会在运行时 `fatalError`。加词条后请检查重复。
- 任何写入 `chat.db` 的操作都必须先退出「信息」App 并备份。
- 提交信息建议使用 Conventional Commits（`feat:` / `fix:` / `docs:` / `refactor:`）。

## 提交 PR

1. Fork 并创建分支（`feat/xxx`）
2. 保持改动聚焦，避免混入无关格式化
3. 说明改动原因、影响范围、验证方式
