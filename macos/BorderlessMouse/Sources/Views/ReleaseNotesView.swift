import SwiftUI

/// Release notes from the GitHub release body as one card per section.
struct ReleaseNotesView: View {
    let title: String
    let markdown: String
    var link: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let link {
                    Link(L10n.text("Wydanie na GitHubie ↗", "Release on GitHub ↗"), destination: link).font(.callout)
                }
            }
            .padding(.horizontal, 4)
            ForEach(ReleaseNotes.sections(from: markdown)) { section in
                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.title.isEmpty {
                            Text(verbatim: section.title).font(.headline)
                        }
                        ForEach(section.lines) { line in
                            switch line.kind {
                            case .bullet:
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(verbatim: "•").foregroundStyle(DesignTokens.accent)
                                    Text(ReleaseNotes.inline(line.text))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            case .text:
                                Text(ReleaseNotes.inline(line.text))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(16)
                }
            }
        }
    }
}

/// Minimal reader for the release body: `#` headings start sections, `-`/`*` lines are
/// bullets, other lines are paragraphs. The trailing install instructions are left out.
enum ReleaseNotes {
    struct Line: Identifiable {
        enum Kind { case bullet, text }
        let id: Int
        let kind: Kind
        let text: String
    }

    struct Section: Identifiable {
        let id: Int
        let title: String
        var lines: [Line] = []
    }

    /// Headings that explain how to install rather than what changed.
    private static let installHeadings: Set<String> = ["aktualizacja", "updating", "how to update"]

    static func sections(from markdown: String) -> [Section] {
        var sections: [Section] = []
        var current = Section(id: 0, title: "")
        var nextID = 1
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if !current.lines.isEmpty { sections.append(current) }
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if installHeadings.contains(title.lowercased()) { return tidy(sections) }
                current = Section(id: nextID, title: title)
                nextID += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                current.lines.append(Line(id: nextID, kind: .bullet, text: String(line.dropFirst(2))))
                nextID += 1
            } else if !line.isEmpty {
                current.lines.append(Line(id: nextID, kind: .text, text: line))
                nextID += 1
            }
        }
        if !current.lines.isEmpty { sections.append(current) }
        return tidy(sections)
    }

    /// With headings present the untitled intro is boilerplate; without any, it is the notes.
    private static func tidy(_ sections: [Section]) -> [Section] {
        sections.contains(where: { !$0.title.isEmpty }) ? sections.filter { !$0.title.isEmpty } : sections
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
