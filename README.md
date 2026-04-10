# Tilly

A native macOS AI agent harness with multi-provider LLM support, 36 tools, sub-agent delegation, persistent memory, a skill library, and an iOS companion app. Built entirely in SwiftUI with Swift 6.0 strict concurrency.

Think of it as an open, local-first Claude Code / Codex that runs natively on your Mac with full system access.

---

## Features

- **7 LLM Providers** &mdash; OpenRouter, Ollama (local), Alibaba Qwen, DeepSeek, Kimi (Moonshot), ZAI, ZAI Coding
- **36 Tools** &mdash; file I/O, shell, web search/fetch, git, browser, screenshot, clipboard, memory, skills, sub-agents, and more
- **3 Chat Modes** &mdash; Normal, Deep Research (multi-source parallel investigation), Plan (structured step-by-step execution)
- **Sub-Agent Delegation** &mdash; spawn independent child agents for parallel work, each with their own tool set and system prompt
- **Persistent Memory** &mdash; named memories by type (user, feedback, project, reference) with full-text search
- **Skill Library** &mdash; create, chain, test, and plan reusable workflows; auto-saved from complex tasks
- **iOS Companion** &mdash; real-time session sync, streaming display, and remote control via Firebase
- **Rich Chat UI** &mdash; markdown rendering (headings, tables, code blocks), thinking dropdowns, file chips with inline preview, turn-based message grouping
- **Auto-Embed** &mdash; long responses (2000+ chars) automatically saved as files and embedded as preview chips in chat
- **Context Management** &mdash; smart tool selection, tool result offloading, and token-aware prompt sizing
- **Keyboard Shortcuts** &mdash; Cmd+/- text scaling, Cmd+N new chat, Cmd+. stop generation

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Tilly.app (macOS)                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │ Sidebar  │  │ ChatView │  │   Detail Views   │   │
│  │ Sessions │  │ Turns    │  │ Memory/Skill/Cred│   │
│  │ Memory   │  │ Tools    │  │                  │   │
│  │ Skills   │  │ SubAgent │  │                  │   │
│  │ Creds    │  │ Modes    │  │                  │   │
│  └──────────┘  └──────────┘  └──────────────────┘   │
│                      │                                │
│               ┌──────┴──────┐                        │
│               │  AppState   │                        │
│               │ Agent Loop  │                        │
│               │ Streaming   │                        │
│               │ Mode Logic  │                        │
│               └──────┬──────┘                        │
└──────────────────────┼───────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
  ┌─────┴─────┐ ┌─────┴─────┐ ┌─────┴─────┐
  │ TillyCore │ │  Tilly    │ │  Tilly    │
  │  Models   │ │ Providers │ │  Storage  │
  │ Protocols │ │  7 LLMs   │ │ Memory    │
  │  Errors   │ │ Streaming │ │ Skills    │
  └───────────┘ └───────────┘ │ Sessions  │
                              │ Keychain  │
        ┌─────────────┐      └───────────┘
        │ TillyTools  │
        │  36 tools   │
        │ SubAgent    │
        │ ToolRegistry│
        └──────┬──────┘
               │
     ┌─────────┼─────────┐
     │         │         │
  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐
  │File │  │ Web │  │Agent│
  │Shell│  │Fetch│  │Deleg│
  │ Git │  │Srch │  │Plan │
  └─────┘  └─────┘  └─────┘
```

### Package Structure

The codebase is organized into 4 local Swift packages plus 2 app targets:

| Package | Purpose | Key Types |
|---------|---------|-----------|
| **TillyCore** | Shared models, protocols, errors | `Message`, `Session`, `ToolDefinition`, `LLMProvider`, `ProviderID` |
| **TillyProviders** | LLM provider implementations | `OpenAICompatibleProvider`, `ProviderFactory`, streaming via `URLSession.AsyncBytes` |
| **TillyStorage** | Persistence layer | `MemoryService`, `SkillService`, `SessionService`, `ScratchpadService`, `KeychainService` |
| **TillyTools** | 36 tool implementations | `ToolRegistry`, `SubAgentRunner`, `DelegateTaskTool`, `WebSearchTool` |
| **Tilly** | macOS app (SwiftUI) | `AppState`, `ChatView`, `InputBarView`, `ContentView` |
| **TillyRemote** | iOS companion app | Firebase relay, remote session viewer, streaming display |

### Agent Loop

```
User message
  → buildDynamicSystemPrompt() (injects memories, skills, scratchpad, mode instructions, $HOME)
  → buildChatMessages() (convert session to API format)
  → Smart tool selection (36 tools normally, 16 core tools when context > 40K tokens)
  → streamResponseWithRetry() (up to 3 retries with exponential backoff for 5xx/timeout)
  → Parallel tool execution (withTaskGroup)
  → Tool result offloading (>1500 chars → /tmp file)
  → Loop (max 50 rounds, checkpoint every 10)
  → autoEmbedLongResponse() (>2000 chars → file + TLDR summary)
  → Auto-generate session title
  → Firebase sync
```

### Context Management (3 layers)

1. **Tool Result Offloading** &mdash; results over 1500 chars saved to `/tmp/tilly-tool-*.txt`, replaced with preview + file path
2. **Smart Tool Selection** &mdash; when estimated tokens > 40K, only 16 core tools are sent to the LLM (vs all 36)
3. **System Prompt Diet** &mdash; only 3 most recent memories/skills injected; scratchpad capped at 800 chars

### LLM Retry

Transient errors (HTTP 500/502/503, 429 rate limits, timeouts) trigger automatic retry with exponential backoff (1s, 2s, 4s). Permanent errors (400, auth failures) fail immediately with a user-visible message.

---

## Tools (36)

### File Operations
| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_file` | Create/overwrite files (auto-embeds in chat) |
| `edit_file` | Surgical text replacement |
| `list_directory` | Directory listing with metadata |

### Code Execution
| Tool | Description |
|------|-------------|
| `execute_command` | Shell commands with configurable timeout (10s-900s) |
| `app_launcher` | Launch macOS applications |
| `background_task` | Non-blocking subprocess execution |

### Web & Network
| Tool | Description |
|------|-------------|
| `web_search` | Tavily API search with DuckDuckGo fallback |
| `web_fetch` | Full-page content extraction |
| `http_request` | Generic HTTP API calls |

### System
| Tool | Description |
|------|-------------|
| `screenshot` | Desktop/window capture |
| `clipboard` | Read/write system clipboard |
| `notification` | macOS notifications |
| `vision` | Image recognition |
| `audio` | Audio transcription/synthesis |

### Version Control
| Tool | Description |
|------|-------------|
| `git` | Full git operations |

### Memory
| Tool | Description |
|------|-------------|
| `memory_store` | Store named memories by type |
| `memory_search` | Full-text search across memories |
| `memory_list` | List all memories |
| `memory_delete` | Remove memories |

### Skills & Automation
| Tool | Description |
|------|-------------|
| `skill_create` | Create reusable workflow skills |
| `skill_run` | Execute a skill |
| `skill_list` | List all skills |
| `skill_delete` | Remove skills |
| `skill_chain` | Sequence multiple skills |
| `skill_test` | Test skill with validation |
| `skill_plan` | AI-powered skill chain planning |

### Planning & Notes
| Tool | Description |
|------|-------------|
| `scratchpad_write` | Session working memory |
| `scratchpad_read` | Read scratchpad |
| `plan_task` | Create structured step-by-step plans |

### Interaction
| Tool | Description |
|------|-------------|
| `ask_user` | Modal approval dialog with options |
| `delegate_task` | Spawn independent sub-agent |

### Advanced
| Tool | Description |
|------|-------------|
| `keychain_password` | Secure credential access (approval-gated) |
| `browser` | Headless browser automation |
| `mcp_client` | Model Context Protocol integration |
| `create_tool` | Define custom tools at runtime |

---

## Chat Modes

### Normal
Default mode. Full tool access, general-purpose agent behavior.

### Deep Research
Activates when you need thorough, multi-source investigation:
- Searches 5-10+ sources from multiple angles
- Spawns parallel sub-agents for different research threads
- Cross-references findings before synthesizing
- Produces comprehensive, cited reports saved as files

### Plan
Activates when you need structured, methodical execution:
- Creates a formal plan via `plan_task` before any action
- Tracks progress via scratchpad with step-by-step checkoffs
- Delegates independent sub-tasks to parallel sub-agents
- Summarizes accomplishments and remaining follow-ups

---

## Sub-Agent System

The `delegate_task` tool spawns independent child agents:

```
Main Agent (AppState)
  ├── delegate_task(role: "researcher", task: "...", allowed_tools: [...])
  │     └── SubAgentRunner (independent LLM loop, max 15 rounds)
  │           ├── web_search → web_fetch → scratchpad_write
  │           └── Returns final text result
  ├── delegate_task(role: "code reviewer", task: "...")
  │     └── SubAgentRunner
  │           ├── read_file → execute_command
  │           └── Returns final text result
  └── Collects all results in parallel (withTaskGroup)
```

Sub-agents:
- Have their own context window (cannot see parent conversation)
- Run with a restricted tool set (configurable per delegation)
- Execute tools in parallel within their own loop
- Return a string result to the parent agent
- Appear in their own collapsible purple dropdown in the UI (separate from regular tool calls)

---

## Firebase Sync (iOS Companion)

```
Firebase Realtime Database
  /users/{uid}/
    ├── profile/          (macOnline status, lastSeen)
    ├── settings/         (provider, model selection)
    ├── sessions/         (full session data, image-stripped)
    ├── sessionIndex/     (lightweight session list)
    └── relay/
        ├── ios_to_mac/   (commands: new chat, switch model)
        └── mac_to_ios/   (streaming tokens, notifications)
```

- **Auth**: Google Sign-In via Firebase Auth
- **Sync**: Sessions synced after streaming completes (not during)
- **Relay**: Ephemeral message channel for real-time commands/notifications
- **Image Stripping**: Binary image data removed before Firebase write for efficiency
- **iOS Features**: Real-time streaming display, session list, ask-user dialog relay

---

## UI Design

The chat interface follows ChatGPT/Claude/Codex design patterns:

- **Turn-based grouping** &mdash; assistant messages bundled with their tool calls into single turns
- **Tool operations dropdown** &mdash; collapsible orange block showing all tool calls with args and results
- **Sub-agent dropdown** &mdash; collapsible purple block showing delegated agents with role, task, and results
- **Thinking dropdown** &mdash; compact collapsible block for model reasoning (from `reasoningContent` or prefix detection)
- **File chips** &mdash; embedded file previews with eye toggle, open-in-app, and show-in-Finder buttons
- **Markdown rendering** &mdash; headings, bold, tables (proper grid), code blocks (dark theme with copy button)
- **Input bar** &mdash; large rounded card with text editor, paperclip/photo attach buttons, mode selector pill, and send button
- **Dynamic text scaling** &mdash; Cmd+/- adjusts all text via DynamicTypeSize (7 levels, persisted)

---

## Building

### Requirements

- macOS 15.0+
- Xcode 16+
- Swift 6.0
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

### Development

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project Tilly.xcodeproj -scheme Tilly -destination 'platform=macOS' build
```

### Release DMG

```bash
# Archive, sign with Developer ID, create DMG
bash scripts/build-release.sh
# Output: build/Tilly.dmg
```

The build script:
1. Archives with `xcodebuild archive`
2. Exports with Developer ID signing (automatic)
3. Falls back to ad-hoc signing if Developer ID export fails
4. Creates a DMG with drag-to-Applications layout

### Installing on Another Mac

```bash
# If Gatekeeper blocks the app:
xattr -cr /Applications/Tilly.app
```

---

## Configuration

### API Keys

API keys are stored in the macOS Keychain (service: `com.tilly.apikeys`). Add them via the Credentials section in the sidebar or through the Settings panel.

### Firebase (iOS Sync)

Place `GoogleService-Info.plist` in the `Tilly/` directory. Firebase Auth and Realtime Database are configured at app launch.

### Providers

Select providers and models via the model selector in the sidebar header. Selection persists across sessions and syncs to Firebase for iOS.

---

## Project Stats

| Metric | Value |
|--------|-------|
| Swift files | 102 |
| Lines of code | ~12,000 |
| SPM packages | 4 |
| App targets | 2 (macOS + iOS) |
| Tools | 36 |
| LLM providers | 7 |
| Chat modes | 3 |
| Deployment | macOS 15.0+, iOS 17.0+ |
| Swift version | 6.0 (strict concurrency) |

---

## License

MIT
