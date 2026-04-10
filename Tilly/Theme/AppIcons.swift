import SwiftUI

/// Centralized icon set for the entire app.
/// Uses SF Symbols 5 — curated for visual consistency.
/// Swap this file to rebrand the entire app's iconography.
enum AppIcons {

    // MARK: - Navigation & Sections
    static let sessions     = "message.fill"
    static let memories     = "brain.head.profile.fill"
    static let skills       = "wand.and.stars"
    static let credentials  = "lock.shield.fill"

    // MARK: - Chat
    static let user         = "person.crop.circle.fill"
    static let assistant    = "sparkle"
    static let send         = "arrow.up.circle.fill"
    static let stop         = "stop.circle.fill"
    static let newChat      = "plus.message.fill"

    // MARK: - Tools
    static let tool         = "wrench.and.screwdriver.fill"
    static let terminal     = "apple.terminal.fill"
    static let openApp      = "macwindow.badge.plus"
    static let readFile     = "doc.text.fill"
    static let writeFile    = "pencil.and.outline"
    static let listDir      = "folder.fill"
    static let webFetch     = "globe"
    static let webSearch    = "magnifyingglass.circle.fill"
    static let memory       = "brain.fill"
    static let skill        = "wand.and.stars"
    static let plan         = "checklist"
    static let notes        = "note.text"
    static let askUser      = "questionmark.bubble.fill"
    static let subAgent     = "person.2.fill"

    // MARK: - Memory Types
    static let memoryUser       = "person.crop.circle.fill"
    static let memoryFeedback   = "text.bubble.fill"
    static let memoryProject    = "folder.fill.badge.gearshape"
    static let memoryReference  = "link.circle.fill"

    // MARK: - Modes
    static let modeNormal       = "bolt.fill"
    static let modeDeepResearch = "globe.desk.fill"
    static let modePlan         = "map.fill"

    // MARK: - Actions
    static let attach       = "paperclip"
    static let attachImage  = "photo.on.rectangle.angled"
    static let copy         = "doc.on.doc"
    static let delete       = "trash.fill"
    static let settings     = "gearshape.fill"
    static let diagnostics  = "stethoscope"
    static let expand       = "chevron.down"
    static let collapse     = "chevron.up"
    static let external     = "arrow.up.right.square"
    static let finder       = "folder"
    static let preview      = "eye"
    static let previewOff   = "eye.slash"
    static let back         = "chevron.left"
    static let checkmark    = "checkmark.circle.fill"
    static let error        = "xmark.circle.fill"
    static let thinking     = "brain"

    // MARK: - File Types
    static let fileText     = "doc.text.fill"
    static let fileImage    = "photo.fill"
    static let fileVideo    = "film.fill"
    static let fileAudio    = "waveform.circle.fill"
    static let fileGeneric  = "doc.fill"
    static let filePDF      = "doc.richtext.fill"
    static let fileCode     = "curlybraces"
    static let fileMarkdown = "doc.text.fill"
}
