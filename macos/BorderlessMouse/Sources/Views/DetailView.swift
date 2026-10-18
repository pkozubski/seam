import SwiftUI

struct DetailView: View {
    let section: SidebarSection
    var openWindows: () -> Void = {}

    var body: some View {
        Group {
            switch section {
            case .connection: ConnectionPage(openWindows: openWindows)
            case .permissions: PermissionsPage()
            case .control: InputPage()
            case .audio: AudioPage()
            case .clipboard: ClipboardPage()
            case .windows: WindowsPage()
            case .settings: SettingsPage()
            case .log: LogPage()
            }
        }
        .id(section)
        .navigationTitle(section.title)
    }
}
