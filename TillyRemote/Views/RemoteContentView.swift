import SwiftUI
import TillyCore
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Main Content View (ChatGPT-style sidebar drawer)

struct RemoteContentView: View {
    @Environment(AuthServiceIOS.self) private var authService
    @Environment(FirebaseRelayIOS.self) private var relay
    @State private var showSidebar = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Main chat area
            NavigationStack {
                Group {
                    if relay.currentSession != nil {
                        RemoteChatViewFirebase()
                    } else if relay.macOnline {
                        RemoteMacStatusPlaceholder()
                    } else {
                        RemoteMacStatusView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { withAnimation(.easeInOut(duration: 0.25)) { showSidebar.toggle() } } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            relay.createNewSession()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.title3)
                        }
                    }
                }
                .navigationTitle(relay.currentSession?.title ?? "Tilly")
                .navigationBarTitleDisplayMode(.inline)
            }

            // Dim overlay when sidebar is open
            if showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showSidebar = false }
                    }
            }

            // Sidebar drawer
            if showSidebar {
                SidebarDrawer(
                    relay: relay,
                    authService: authService,
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { showSidebar = false } }
                )
                .frame(width: 280)
                .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: Binding(
            get: { relay.showAskUser },
            set: { newValue in if !newValue { relay.showAskUser = false } }
        )) {
            RemoteAskUserFirebase()
                .environment(relay)
        }
    }
}

// MARK: - Sidebar Drawer

struct SidebarDrawer: View {
    let relay: FirebaseRelayIOS
    let authService: AuthServiceIOS
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Tilly")
                    .font(.title3.bold())
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // New chat button
            Button {
                relay.createNewSession()
                onClose()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                    Text("New Chat")
                        .font(.body)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()

            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(relay.sessions) { session in
                        Button {
                            relay.currentSession = Session(
                                id: session.id,
                                title: session.title,
                                providerID: session.providerID,
                                modelID: session.modelID
                            )
                            relay.selectSession(id: session.id)
                            onClose()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(relay.currentSession?.id == session.id ? .blue : .primary)
                                    Text(session.updatedAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if relay.currentSession?.id == session.id {
                                    Circle()
                                        .fill(.blue)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Account
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(authService.userName ?? "User")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(authService.userEmail ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign Out", role: .destructive) {
                    relay.stop()
                    authService.signOut()
                }
                .font(.caption)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Mac Status Placeholder (when online but no session selected)

struct RemoteMacStatusPlaceholder: View {
    @Environment(FirebaseRelayIOS.self) private var relay

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a chat or start a new one")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Chat View (Firebase) with file upload

struct RemoteChatViewFirebase: View {
    @Environment(FirebaseRelayIOS.self) private var relay
    @State private var inputText = ""
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let session = relay.currentSession {
                            ForEach(session.messages) { message in
                                RemoteMessageRow(message: message)
                                    .id(message.id)
                            }
                        }

                        if relay.isStreaming && !relay.streamingText.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .padding(.top, 2)
                                Text(relay.streamingText)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("streaming")
                        }

                        if relay.isStreaming {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("progress")
                        }
                    }
                }
                .onChange(of: relay.streamingText) {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: relay.currentSession?.messages.count) {
                    if let last = relay.currentSession?.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar with attachment button
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment menu
                Menu {
                    Button { showPhotoPicker = true } label: {
                        Label("Photo Library", systemImage: "photo")
                    }
                    Button { showFilePicker = true } label: {
                        Label("Browse Files", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }

                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: relay.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(relay.isStreaming ? .red : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !relay.isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { isInputFocused = true }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 5, matching: .images)
        .onChange(of: selectedPhotos) {
            for item in selectedPhotos {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Send as text description since we can't attach to Firebase relay
                        relay.sendMessage("[User attached an image (\(data.count / 1024)KB)]")
                    }
                }
            }
            selectedPhotos = []
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                let name = url.lastPathComponent
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                relay.sendMessage("[User attached file: \(name) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))]")
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        relay.sendMessage(text)
    }
}

// MARK: - Ask User (Firebase) with custom input

struct RemoteAskUserFirebase: View {
    @Environment(FirebaseRelayIOS.self) private var relay
    @Environment(\.dismiss) private var dismiss
    @State private var customInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)

                    Text(relay.askUserQuestion)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 10) {
                        ForEach(Array(relay.askUserOptions.enumerated()), id: \.offset) { index, option in
                            Button(action: {
                                let choice = option
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    relay.respondToAskUser(choice: choice)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill([Color.blue, .orange, .green][index % 3]))

                                    Text(option)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    VStack(spacing: 8) {
                        Text("Or type your own response:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Type here...", text: $customInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    guard !customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                    let text = customInput
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        relay.respondToAskUser(choice: text)
                                    }
                                }

                            Button {
                                let text = customInput
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    relay.respondToAskUser(choice: text)
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Tilly needs input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Message Row (with rich content + document preview)

struct RemoteMessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch message.role {
                case .user:
                    Image(systemName: "person.circle.fill").foregroundStyle(.blue)
                case .assistant:
                    Image(systemName: "sparkle").foregroundStyle(.purple)
                case .tool:
                    Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.orange)
                case .system:
                    Image(systemName: "gearshape.fill").foregroundStyle(.gray)
                }
            }
            .font(.caption)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : message.role == .assistant ? "Tilly" : message.role.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        if !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    case .image(let data, _):
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    case .fileReference(let file):
                        DocumentChipView(file: file)
                    }
                }

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { tc in
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.caption2).foregroundStyle(.orange)
                            Text(tc.function.name).font(.caption).fontWeight(.medium)
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(message.role == .assistant ? Color(.secondarySystemBackground).opacity(0.5) : .clear)
    }
}

// MARK: - Document Chip (tappable, shows preview/share)

struct DocumentChipView: View {
    let file: FileAttachment
    @State private var showPreview = false

    var body: some View {
        Button {
            showPreview = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconForMime(file.mimeType))
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPreview) {
            DocumentPreviewSheet(file: file)
        }
    }

    private func iconForMime(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("json") { return "curlybraces" }
        return "doc"
    }
}

// MARK: - Document Preview Sheet

struct DocumentPreviewSheet: View {
    let file: FileAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(file.fileName)
                    .font(.headline)

                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("This file is stored on your Mac. Open Tilly on your Mac to view the full document.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
