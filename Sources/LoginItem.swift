import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Shows up in System Settings → General → Login Items.
enum LoginItem {
    private static let didSetUpKey = "didSetUpLoginItem"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PulseBar: could not %@ login item: %@", enabled ? "register" : "unregister", "\(error)")
        }
    }

    /// Turns launch-at-login on the first time the app runs. After that, the user's choice sticks.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSetUpKey) else { return }
        defaults.set(true, forKey: didSetUpKey)
        setEnabled(true)
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
