import SwiftUI
import TillyCore
import UniformTypeIdentifiers

struct InputBarView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var attachments: [AttachmentItem] = []
    @State private var showFilePicker = false
    @State private var showImagePicker = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main input container — large rounded card
            VStack(spacing: 0) {
                // Attachment previews (inside the card)
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { attachment in
                                AttachmentChip(attachment: attachment) {
                                    attachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }

                // Text editor
                TextEditor(text: $inputText)
                    .font(.body)
                    .focused($isInputFocused)
                    .frame(minHeight: 60, maxHeight: 180)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.top, attachments.isEmpty ? 14 : 8)
                    .padding(.bottom, 4)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            return .ignored
                        }
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty {
                            send()
                        }
                        return .handled
                    }
                    .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                        handleDrop(providers)
                        return true
                    }

                // Bottom toolbar row
                HStack(spacing: 6) {
                    // Attach file
                    Button { showFilePicker = true } label: {
                        Image(systemName: AppIcons.attach)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file")

                    // Attach image
                    Button { showImagePicker = true } label: {
                        Image(systemName: AppIcons.attachImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")

                    // Mode selector
                    ModeSelectorView()

                    Spacer()

                    // Send / Stop button
                    if appState.isStreaming {
                        Button {
                            appState.stopStreaming()
                        } label: {
                            Image(systemName: AppIcons.stop)
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop generation")
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: AppIcons.send)
                                .font(.title2)
                                .foregroundStyle(canSend ? Color.accentColor : Color.gray.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .help("Send message")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear { isInputFocused = true }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image, .movie, .audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let currentAttachments = attachments
        inputText = ""
        attachments = []

        let state = appState
        Task { @MainActor in
            await state.sendMessageWithAttachments(text, attachments: currentAttachments)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            if let item = AttachmentItem.from(url: url) {
                attachments.append(item)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            if let item = AttachmentItem.from(url: url) {
                                attachments.append(item)
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data as? Data {
                        Task { @MainActor in
                            attachments.append(AttachmentItem(
                                id: UUID(),
                                name: "Pasted Image",
                                type: .image,
                                data: data,
                                mimeType: "image/png",
                                fileSize: Int64(data.count)
                            ))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Attachment Types

struct AttachmentItem: Identifiable {
    let id: UUID
    let name: String
    let type: AttachmentType
    let data: Data
    let mimeType: String
    let fileSize: Int64
    var filePath: String?

    enum AttachmentType {
        case image
        case video
        case audio
        case file

        var icon: String {
            switch self {
            case .image: return "photo"
            case .video: return "film"
            case .audio: return "waveform"
            case .file: return "doc"
            }
        }
    }

    static func from(url: URL) -> AttachmentItem? {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        guard let data = try? Data(contentsOf: url) else { return nil }

        let type: AttachmentType
        let mimeType: String

        switch ext {
        case "jpg", "jpeg":
            type = .image; mimeType = "image/jpeg"
        case "png":
            type = .image; mimeType = "image/png"
        case "gif":
            type = .image; mimeType = "image/gif"
        case "webp":
            type = .image; mimeType = "image/webp"
        case "heic":
            type = .image; mimeType = "image/heic"
        case "mp4", "mov", "m4v":
            type = .video; mimeType = "video/mp4"
        case "mp3", "m4a", "wav":
            type = .audio; mimeType = "audio/mpeg"
        default:
            type = .file; mimeType = "application/octet-stream"
        }

        return AttachmentItem(
            id: UUID(),
            name: name,
            type: type,
            data: data,
            mimeType: mimeType,
            fileSize: Int64(data.count),
            filePath: url.path
        )
    }
}

// MARK: - Attachment Chip View

struct AttachmentChip: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.type == .image, let nsImage = NSImage(data: attachment.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: attachment.type.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Mode Selector

struct ModeSelectorView: View {
    @Environment(AppState.self) private var appState
    @State private var showMenu = false

    var body: some View {
        Menu {
            ForEach(AppState.ChatMode.allCases, id: \.self) { mode in
                Button {
                    appState.chatMode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.rawValue)
                        if appState.chatMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.chatMode.icon)
                    .font(.system(size: 11))
                Text(appState.chatMode.shortLabel)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundStyle(appState.chatMode == .normal ? .secondary : appState.chatMode.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(appState.chatMode == .normal ? Color.gray.opacity(0.1) : appState.chatMode.color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(appState.chatMode == .normal ? Color.clear : appState.chatMode.color.opacity(0.25), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Chat mode: \(appState.chatMode.rawValue)")
    }
}
