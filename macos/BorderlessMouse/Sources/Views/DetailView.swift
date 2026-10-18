import SwiftUI

struct DetailView: View {
    let section: SidebarSection
    var openWindows: () -> Void = {}

    var body: some View {
        Group {
            switch section {
            case .connection: ConnectionPage(openWindows: openWindows)
            case .permissions: PermissionsPage()
            case .control: ControlPage()
            case .audio: ControlPage(initialCategory: .audio)
            case .clipboard: ControlPage(initialCategory: .clipboard)
            case .windows: ControlPage(initialCategory: .display)
            case .settings: SettingsPage()
            case .log: LogPage()
            }
        }
        .id(section)
        .navigationTitle(section.title)
    }
}
