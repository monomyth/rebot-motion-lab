import SwiftUI
import AppKit
import RobotCore

@main @MainActor struct ReBotMotionLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var typography = Typography.shared
    private let result: Result<AppModel, Error>
    init() { result = Result { try AppModel() } }
    private var model: AppModel? { try? result.get() }
    var body: some Scene {
        Window("ReBot Motion Lab", id: "main") {
            Group {
                switch result {
                case .success(let model): WorkspaceView(model: model)
                case .failure(let error): ContentUnavailableView("Resources could not load", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
                }
            }
            .frame(minWidth: 1080, minHeight: 720)
            .preferredColorScheme(.dark)
            .tint(.labAccent)
        }
        .defaultSize(width: 1380, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Trajectory…") { model?.importTrajectory() }.keyboardShortcut("o")
                Button("Export Trajectory…") { model?.exportTrajectory() }.keyboardShortcut("s")
                Divider()
                Button("Save Actuator Reference…") { model?.saveReference() }
            }
            CommandMenu("Robot") {
                Button("Play / Pause") { model?.playPause() }.keyboardShortcut(.return, modifiers: [.command])
                Button("Stop Motion") { model?.stop() }.keyboardShortcut(.escape, modifiers: [])
                Button("Reset Robot") { model?.reset() }.keyboardShortcut("r")
                Button("Add Current Pose") { model?.addWaypoint() }.keyboardShortcut("k")
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Increase Text Size") { typography.increase() }.keyboardShortcut("+")
                Button("Decrease Text Size") { typography.decrease() }.keyboardShortcut("-")
                Button("Actual Text Size") { typography.reset() }.keyboardShortcut("0")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--smoke-test") || arguments.contains("--performance-check") || arguments.contains("--mcp-integration-test") {
            NSApp.windows.forEach { $0.ignoresMouseEvents = true }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Color {
    static let labAccent = Color(red: 0.76, green: 0.91, blue: 0.35)
    static let labPanel = Color(red: 0.10, green: 0.12, blue: 0.11)
}
extension NSColor {
    static let labAccent = NSColor(srgbRed: 0.76, green: 0.91, blue: 0.35, alpha: 1)
}
extension View {
    func labLinkStyle() -> some View {
        buttonStyle(.plain).foregroundStyle(Color.labAccent)
    }
}

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var typography = Typography.shared
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").labFont(.system(size: 32)).foregroundStyle(Color.labAccent)
                    Text("ReBot").labFont(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("MOTION LAB").labFont(.system(size: 10, weight: .semibold)).tracking(3).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.top, 18)
                List(WorkspacePage.allCases, selection: Binding(get: { Optional(model.page) }, set: { if let value = $0 { model.page = value } })) { page in
                    Label(page.rawValue, systemImage: page.icon).labFont(.body).lineLimit(2).tag(page).padding(.vertical, 6)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("B601-DM", systemImage: "circle.fill").labFont(.caption.weight(.semibold)).foregroundStyle(Color.labAccent)
                    Text("6 axes + gripper\nNative · Offline").labFont(.caption).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(20)
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 205 * min(typography.scale, 1.2), max: 285)
        } detail: {
            Group {
                switch model.page {
                case .simulator: SimulatorView(model: model)
                case .actuators: ReferenceView(model: model)
                case .mcp: MCPControlView(control: model.mcpControl)
                case .about: AboutView(model: model)
                }
            }
            .background(Color.labPanel)
            .navigationTitle(model.page == .simulator ? "B601-DM Simulator" : model.page.rawValue)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.importTrajectory() } label: { Label("Import trajectory", systemImage: "square.and.arrow.down") }.help("Import a trajectory JSON file")
                Button { model.exportTrajectory() } label: { Label("Export trajectory", systemImage: "square.and.arrow.up") }.help("Export the waypoint sequence")
            }
        }
        .alert("Couldn’t complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { SmokeCheck.startIfRequested(model); PerformanceCheck.startIfRequested(model) }
        .environment(\.fontScale, typography.scale)
        .font(.system(size: 13 * typography.scale))
    }
}
