import SwiftUI
import AppKit

final class SettingsModel: ObservableObject {
    @Published var connecting = false
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = SettingsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("设置与诊断"))
                        .font(.system(size: Typo.s(22), weight: .bold))
                    Text(L.t("读取系统短信库需要「完全磁盘访问权限」，数据全程留在本机。"))
                        .font(.system(size: Typo.s(12)))
                        .foregroundStyle(.secondary)
                }

                permissionCard
                sourceCard
                languageCard
                appearanceCard
                diagnosticsCard
                backupCard
                aboutCard

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(L.t("设置与诊断"))
    }

    private var permissionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L.t("磁盘访问权限"))
                        .font(.system(size: Typo.s(13), weight: .semibold))
                    Spacer()
                    if state.isDemo {
                        StatusBadge(ok: false, text: L.t("演示模式"), warn: true)
                    } else {
                        StatusBadge(ok: state.realPermissionOK,
                                    text: state.realPermissionOK ? L.t("已授权") : L.t("未授权"))
                    }
                }

                infoLine(L.t("系统短信库"), Database.shared.realPath, mono: true)
                infoLine(L.t("权限状态"), state.realPermissionOK
                         ? L.t("已获得完全磁盘访问权限") : state.realPermissionDetail)
                infoLine(L.t("「信息」App"), DeleteService.shared.messagesRunning
                         ? L.t("正在运行（删除前会自动请求退出）") : L.t("已退出"))

                if !state.realPermissionOK {
                    Divider()
                    Text(L.t("如何授权"))
                        .font(.system(size: Typo.s(11.5), weight: .medium))
                    VStack(alignment: .leading, spacing: 5) {
                        step(1, L.t("点下方按钮打开「系统设置 › 隐私与安全性 › 完全磁盘访问权限」"))
                        step(2, L.t("点 + ，把「短信管家.app」加入列表"))
                        step(3, L.t("打开右侧开关，然后完全退出本 App 并重新打开"))
                        step(4, L.t("回到这里点「连接系统短信库」"))
                    }
                    HStack(spacing: 8) {
                        Button {
                            state.openFullDiskAccessSettings()
                        } label: {
                            Label(L.t("打开系统设置"), systemImage: "gearshape")
                        }
                        .controlSize(.small)

                        Button {
                            connect()
                        } label: {
                            Text(model.connecting ? L.t("连接中…") : L.t("连接系统短信库"))
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.connecting)
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("数据源"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                HStack(spacing: 8) {
                    Image(systemName: state.isDemo ? "flask" : "internaldrive")
                        .foregroundStyle(state.isDemo ? .orange : .green)
                    Text(state.isDemo ? L.t("演示数据（不会影响真实短信）") : L.t("系统短信库"))
                        .font(.system(size: Typo.s(12)))
                    Spacer()
                    Text(L.t("%d 条", state.all.count))
                        .font(.system(size: Typo.s(12)).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(L.t("刷新")) { Task { await state.load() } }
                        .controlSize(.small)
                    Button(L.t("使用演示数据")) { Task { await state.useDemo() } }
                        .controlSize(.small)
                    Button(L.t("连接系统短信库")) { connect() }
                        .controlSize(.small)
                        .disabled(model.connecting)
                    Spacer()
                }
            }
        }
    }

    private var languageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("语言"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                Picker(L.t("界面语言"), selection: $state.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(L.t("更改后立即生效，无需重启。"))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("外观"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                Picker(L.t("主题"), selection: $state.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(L.t(mode.label)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Text(L.t("背景不透明度"))
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 96, alignment: .leading)
                    Slider(value: $state.backgroundOpacity, in: 0.15...1.0)
                    Text("\(Int(state.backgroundOpacity * 100))%")
                        .font(.system(size: Typo.s(11)).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    /// 诊断卡：调试日志开关。默认关闭，出问题时打开复现，再把日志给人看。
    private var diagnosticsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L.t("诊断日志"))
                        .font(.system(size: Typo.s(13), weight: .semibold))
                    Spacer()
                    Toggle("", isOn: logBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }

                Text(L.t("出问题时打开此开关，重现一次操作，再把日志文件发给开发者。"))
                    .font(.system(size: Typo.s(11.5)))
                    .foregroundStyle(.secondary)

                // 隐私说明要写清楚，用户才知道打开它不会泄露短信
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: Typo.s(10)))
                        .foregroundStyle(.green)
                    Text(L.t("只记录操作步骤、错误信息和条数，绝不记录短信内容、号码或验证码。"))
                        .font(.system(size: Typo.s(11)))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Log.revealInFinder()
                    } label: {
                        Label(L.t("在访达中显示"), systemImage: "folder")
                    }
                    .controlSize(.small)

                    Button(role: .destructive) {
                        Log.clear()
                        state.toast = L.t("日志已清空")
                    } label: {
                        Label(L.t("清空日志"), systemImage: "trash")
                    }
                    .controlSize(.small)

                    Spacer()

                    Text(Log.logFileURL.path)
                        .font(.system(size: Typo.s(9.5), design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var logBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: Log.enabledKey) },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: Log.enabledKey)
                Log.refresh()
                state.toast = newValue
                    ? L.t("诊断日志已开启，路径：~/Library/Logs/SMSKeeper")
                    : L.t("诊断日志已关闭")
            }
        )
    }

    private var backupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L.t("数据库备份"))
                        .font(.system(size: Typo.s(13), weight: .semibold))
                    Spacer()
                    Text(L.t("保留最近 20 份"))
                        .font(.system(size: Typo.s(11)))
                        .foregroundStyle(.tertiary)
                }
                if state.backups.isEmpty {
                    Text(L.t("暂无备份。每次删除或还原前会自动生成一份。"))
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.backups.prefix(6)) { b in
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .font(.system(size: Typo.s(10)))
                                .foregroundStyle(.tertiary)
                            Text(b.name)
                                .font(.system(size: Typo.s(11), design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text("\(b.sizeMB, specifier: "%.1f") MB")
                                .font(.system(size: Typo.s(10.5)))
                                .foregroundStyle(.tertiary)
                            Button(L.t("在访达中显示")) {
                                NSWorkspace.shared.selectFile(b.path, inFileViewerRootedAtPath:
                                    (b.path as NSString).deletingLastPathComponent)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Text(L.t("备份目录：%@", DeleteService.shared.backupDir.path))
                    .font(.system(size: Typo.s(10)))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("关于"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                Text(L.t("短信管家 1.0 · 原生 SwiftUI 版本"))
                    .font(.system(size: Typo.s(11.5)))
                    .foregroundStyle(.secondary)
                Text(L.t("所有数据只在本机处理，不联网、不上传。软件仅监听本地数据库，不会修改未选中的短信。"))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        model.connecting = true
        Task {
            await state.connectReal()
            model.connecting = false
        }
    }

    private func infoLine(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k)
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(v)
                .font(.system(size: Typo.s(11.5), design: mono ? .monospaced : .default))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(n)")
                .font(.system(size: Typo.s(9.5), weight: .semibold))
                .frame(width: 15, height: 15)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StatusBadge: View {
    let ok: Bool
    let text: String
    var warn: Bool = false

    private var tint: Color { warn ? .orange : (ok ? .green : .red) }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(.system(size: Typo.s(11), weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
    }
}
