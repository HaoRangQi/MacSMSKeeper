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
- 界面文案统一走 `L.t("中文")`，并在 `Sources/Models/Localization.swift` 补英文词条。
- **词条 key 不能重复**：Swift 会把大字典字面量优化成 `uniqueKeysWithValues`，
  重复 key 会在运行时 `fatalError`。加词条后请检查重复。
- 任何写入 `chat.db` 的操作都必须先退出「信息」App 并备份。
- 提交信息建议使用 Conventional Commits（`feat:` / `fix:` / `docs:` / `refactor:`）。

## 提交 PR

1. Fork 并创建分支（`feat/xxx`）
2. 保持改动聚焦，避免混入无关格式化
3. 说明改动原因、影响范围、验证方式
