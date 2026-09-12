import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var updating = false
    @Published private(set) var message = ""

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
        switch status {
        case .enabled: message = "登录 Mac 后自动在菜单栏运行"
        case .requiresApproval: message = "请在系统登录项中允许 MacBook Duo"
        case .notRegistered: message = "登录自动启动已关闭"
        case .notFound: message = "找不到登录项，请从固定位置重新打开应用"
        @unknown default: message = "无法读取登录项状态"
        }
    }

    func setEnabled(_ value: Bool) {
        guard !updating else { return }
        updating = true
        Task { @MainActor in
            defer { updating = false }
            do {
                if value {
                    if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    try await SMAppService.mainApp.unregister()
                }
                refresh()
            } catch {
                refresh()
                message = "登录项设置失败：\(error.localizedDescription)"
            }
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
