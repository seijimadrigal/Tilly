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
        VStack(spacing: 6) {
            // Attachment previews
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
                }
                .frame(height: 60)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                Menu {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Attach File", systemImage: "doc")
                    }

                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Attach Image", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)

                // Text input
                TextEditor(text: $inputText)
                    .font(.body)
                    .focused($isInputFocused)
                    .frame(minHeight: 36, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
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

                // Send / Stop button
                if appState.isStreaming {
                    Button {
                        appState.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generation")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    .help("Send message")
                }
            }

            Text("Enter to send · Shift+Enter new line · Drop files to attach")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            isInputFocused = true
        }
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
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
