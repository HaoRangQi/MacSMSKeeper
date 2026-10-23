# 排查指南

## 诊断日志

默认**关闭**。打开方式：「设置与诊断 › 诊断日志」。

打开后重现一次问题，然后点「在访达中显示」，把日志文件发给开发者。
日志按天分文件：`~/Library/Logs/SMSKeeper/smskeeper-YYYY-MM-DD.log`。

### 日志记录什么

操作步骤、错误信息、SQLite 错误码、条数、耗时、表名、SQL 模板、备份文件名。

### 日志绝不记录什么

**短信正文、验证码、发件人号码、guid 内容、附件数据。**

这不是承诺，是代码里强制执行的：`Sources/Core/Logger.swift` 内置字段黑名单
（`text` / `body` / `sender` / `guid` / `content` / `handle` / `code` …），
命中黑名单的字段一律替换为 `[按隐私策略省略]`，超长值截断到 160 字符。
即使将来有人误传，也落不到磁盘上。

日志只在本地，不联网上传。

## 已知问题与修复

### `no such function: after_delete_message_plugin`

**现象**：点删除后弹窗「数据库错误：no such function: after_delete_message_plugin」。

**原因**：macOS 的「信息」App 打开 `chat.db` 时，会用 `sqlite3_create_function`
注册一批私有 SQL 函数；库里的触发器（`after_delete_message` 等）在增删消息时
调用它们。我们的程序自己打开数据库，连接上没有这些函数，`DELETE` 就失败了。
用 `sqlite3` 命令行直接删也会报同样的错——这不是本工具的问题，是 chat.db 的结构。

**修复**：写连接建立时，扫描 `sqlite_master` 里全部触发器，提取出引用的
`*_plugin` 函数名，连同内置的 6 个已知函数一起，注册成空实现。触发器因此能正常
走完。删除前仍会退出「信息」App 并做整库备份，所以跳过这些函数是安全的。

**如果日志里出现别的函数名**（比如系统升级后新增的），把日志发给开发者，
在 `Sources/Core/Database.swift` 的 `knownPluginFuncs` 里加一行即可。

### `database is locked`

「信息」App 没有完全退出。删除前程序会自动请求它退出；如果失败会中止操作。
手动 ⌘Q 退出「信息」后重试。

### 提示未授权 / 读不到短信

见 [permissions.md](permissions.md)。注意：授权后必须**完全退出**本 App 再打开，
只关窗口不算退出。

## 出问题时请提供

1. 日志文件（`~/Library/Logs/SMSKeeper/` 下当天那个）
2. 弹窗的完整文字
3. macOS 版本（「关于本机」）
4. 当时在做什么操作（点了哪个清理规则 / 删了多少条）

日志里已有条数、错误码和 SQL 错误原文，通常足够定位。
