import SwiftUI
import AppKit

// MARK: - 字号

enum Typo {
    /// 全局字号增量：用户要求整体放大一号
    static let bump: CGFloat = 1

    static func s(_ size: CGFloat) -> CGFloat { size + bump }
}

// MARK: - 外观模式

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L.t("跟随系统")
        case .light: return L.t("浅色")
        case .dark: return L.t("深色")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// 交给 SwiftUI 的 preferredColorScheme，环境色才会真正切换
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 统一背景

/// 整个窗口共用的一层背景：主题渐变 + 玻璃材质，
/// 透明度由滑块控制，避免「有的透明、有的纯白」的割裂感。
struct AppBackground: View {
    let opacity: Double
    @Environment(\.colorScheme) private var scheme

    private var top: Color {
        scheme == .dark ? Color(hex: 0x24272F) : Color(hex: 0xFBFCFE)
    }

    private var bottom: Color {
        scheme == .dark ? Color(hex: 0x14161B) : Color(hex: 0xE9EDF5)
    }

    var body: some View {
        ZStack {
            // 玻璃层：让桌面透进来，形成沉浸感
            Rectangle().fill(.ultraThinMaterial)

            // 主题底色：不透明度越高越"实"
            LinearGradient(colors: [top, bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(min(max(opacity, 0.15), 1.0))
        }
        .ignoresSafeArea()
    }
}

// MARK: - 窗口配置

/// 把窗口改成透明、标题栏融入内容，实现视觉一体化
struct WindowConfigurator: NSViewRepresentable {
    var appearance: AppearanceMode = .system

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            // 已存在的窗口不会继承 NSApp.appearance，必须直接设
            window.appearance = appearance.nsAppearance
        }
    }
}

// MARK: - 外观控件

struct AppearanceControls: View {
    @EnvironmentObject var state: AppState
    @StateObject private var popover = PopoverBox()

    var body: some View {
        HStack(spacing: 8) {
            Picker(L.t("主题"), selection: $state.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Image(systemName: mode.symbol)
                        .help(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 108)
            .help(L.t("切换主题"))

            Button {
                popover.show.toggle()
            } label: {
                Image(systemName: "circle.dotted")
            }
            .buttonStyle(.borderless)
            .help(L.t("背景不透明度"))
            .popover(isPresented: $popover.show, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("背景不透明度"))
                        .font(.system(size: Typo.s(12), weight: .semibold))
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                        Slider(value: $state.backgroundOpacity, in: 0.15...1.0)
                            .frame(width: 150)
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(state.backgroundOpacity * 100))%")
                        .font(.system(size: Typo.s(11)).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(width: 220)
            }
        }
    }
}

final class PopoverBox: ObservableObject {
    @Published var show = false
}
