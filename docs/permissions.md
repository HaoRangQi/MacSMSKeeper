# 权限说明

## 为什么需要「完全磁盘访问权限」

短信数据在 `~/Library/Messages/chat.db`，这个目录受 macOS TCC（隐私保护）保护。
没有授权时，任何程序读取都会得到 `Operation not permitted`。

## 授权步骤

1. 打开「短信管家」
2. 左侧「设置与诊断」→ 点「打开系统设置」
3. 在 **隐私与安全性 › 完全磁盘访问权限** 中，点 `+` 添加 `短信管家.app`
4. 打开右侧开关
5. **完全退出 App**（⌘Q）后重新打开
6. 回到「设置与诊断」，点「连接系统短信库」

## 常见问题

**Q：已经加了 App，还是提示未授权？**

TCC 在进程启动时读取授权状态，必须完全退出再打开。仅关闭窗口不算退出。

**Q：授权列表里找不到 App？**

用「打开系统设置」按钮进入面板后，用 `+` 手动定位到 `build/短信管家.app`。

**Q：每次重新编译都要重新授权吗？**

ad-hoc 签名的二进制哈希会变，系统可能要求重新授权。开发阶段可以把
`build/短信管家.app` 固定放在同一路径，减少重复授权。

**Q：会不会修改我的短信？**

只有执行删除时才会写原库，且写入前会：退出「信息」App → 整库备份 → 记录被删行
→ 事务删除。不做任何其它修改。

## 数据位置

| 内容 | 路径 |
|---|---|
| 系统短信库（只读） | `~/Library/Messages/chat.db` |
| 备份 | `~/Library/Application Support/SMSKeeper/backups/` |
| 回收站存档 | `~/Library/Application Support/SMSKeeper/trash/` |
| 演示数据 | `~/Library/Application Support/SMSKeeper/demo/` |
