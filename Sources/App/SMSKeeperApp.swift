import SwiftUI

@main
struct SMSKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup("短信管家") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
                .task { await state.bootstrap() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .pasteboard) {
                Button(L.t("全选筛选结果")) {
                    state.selection = Set(state.filtered.map(\.id))
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandMenu(L.t("短信")) {
                Button(L.t("刷新数据")) {
                    Task { await state.load() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button(L.t("删除所选…")) {
                    state.requestDelete(state.selection)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.selection.isEmpty)

                Button(L.t("标记为已读")) {
                    state.markRead(state.selection)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(state.selection.isEmpty)

                Divider()

                Button(L.t("导出当前结果…")) {
                    _ = state.export(state.exportTargets)
                }
                .keyboardShortcut("e", modifiers: .command)

                Menu(L.t("导出为")) {
                    ForEach(ExportFormat.allCases) { f in
                        Button(f.title) { _ = state.export(state.exportTargets, format: f) }
                    }
                }
            }
        }
    }
}
