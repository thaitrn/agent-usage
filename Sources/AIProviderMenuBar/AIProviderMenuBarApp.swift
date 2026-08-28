import AppKit
import SwiftUI
import UsageCore

@main
struct AIProviderMenuBarApp: App {
    @State private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenu(store: store)
        } label: {
            Image(nsImage: BrandIcon.image(for: store.groups.severity))
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var groups: [UsageGroup] = []
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var isLoading = false
    private var timer: Timer?
    private let alerts = UsageAlerts()

    init() {
        alerts.requestAuthorization()
        // 60s: Anthropic 429s its usage endpoint under tighter polling.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        // Only the very first fetch shows the loading state; later polls update in place.
        isLoading = groups.isEmpty
        defer { isLoading = false }
        async let claude = ClaudeUsageReader.load()
        async let codex = CodexUsageReader.loadAll()
        async let zai = ZaiUsageReader.load()
        async let grok = OmpUsageReader.loadGrok()
        let fetched = await [claude].compactMap { $0 } + codex + [zai, grok].compactMap { $0 }

        // A failed fetch (429, offline, expired token) keeps the previous numbers
        // on screen instead of making the section vanish.
        var merged = fetched
        for old in groups where !fetched.contains(where: { $0.id == old.id }) { merged.append(old) }
        groups = merged.sorted { $0.id < $1.id }
        refreshedAt = Date()
        alerts.process(groups)
    }
}

struct UsageMenu: View {
    @ObservedObject var store: UsageStore
    /// Bars grow from zero every time the popup opens, the way Claude's does.
    @State private var revealed = false
    @State private var loginItemEnabled = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuSeparator()
            if store.groups.isEmpty {
                if store.isLoading {
                    SkeletonSection()
                } else {
                    Text("No signed-in agents found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            ForEach(store.groups) { group in
                MenuSectionTitle(group.header)
                VStack(spacing: 14) {
                    ForEach(group.limits) { limit in
                        MenuMeterRow(title: limit.title,
                                     trailing: ["\(limit.percent)%", limit.resetLabel].compactMap { $0 }.joined(separator: " · "),
                                     fraction: revealed ? Double(limit.percent) / 100 : 0,
                                     tint: tint(for: limit.severity),
                                     isLoading: store.isLoading)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                MenuSeparator()
            }
            MenuActionRow(title: "Refresh", badge: refreshBadge, isBusy: store.isLoading) { Task { await store.refresh() } }
            if LoginItem.isAvailable {
                MenuActionRow(title: "Open at Login", checked: loginItemEnabled) {
                    LoginItem.toggle()
                    loginItemEnabled = LoginItem.isEnabled
                }
            }
            MenuActionRow(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 8)
        .frame(width: 300)
        .onAppear {
            // Animate what is already loaded; the background poll keeps it current.
            revealed = false
            loginItemEnabled = LoginItem.isEnabled
            DispatchQueue.main.async { revealed = true }
        }
    }

    private func tint(for severity: Severity) -> Color {
        switch severity {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Agent Usage").font(.system(size: 13, weight: .semibold))
            Text(store.groups.isEmpty ? "Checking signed-in agents…" : "\(store.groups.count) agents signed in")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var refreshBadge: String? {
        guard let refreshedAt = store.refreshedAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(refreshedAt) / 60)
        return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
    }
}

/// Label + right-aligned value with a thin progress track underneath (Claude-style meter).
struct MenuMeterRow: View {
    let title: String
    let trailing: String
    let fraction: Double
    var tint: Color = .accentColor
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                        .animation(.easeOut(duration: 0.5), value: fraction)
                }
                .shimmer(active: isLoading)
            }
            .frame(height: 6)
        }
    }
}

struct MenuSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.bottom, 8)
    }
}

struct MenuSeparator: View {
    var body: some View { Divider().padding(.horizontal, 14).padding(.bottom, 10) }
}

/// Menu item with the hover highlight AppKit menus give for free but MenuBarExtra(.window) does not.
struct MenuActionRow: View {
    let title: String
    var badge: String? = nil
    var checked = false
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12))
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                if isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                }
                Spacer()
                if let badge, !isBusy {
                    Text(badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 6)
    }
}

/// Claude-style loading: a highlight sweeping left to right, used on the meter
/// fills during a refresh and on the skeleton rows before the first result.
struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.45)
                        .offset(x: phase * geometry.size.width * 1.45)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .onAppear {
                    phase = -1
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
        .clipShape(Capsule())
    }
}

extension View {
    func shimmer(active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

/// Placeholder meters shown while the first fetch is still in flight.
struct SkeletonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(.quaternary).frame(width: 92, height: 9).shimmer(active: true)
                    Capsule().fill(.quaternary).frame(height: 6).shimmer(active: true)
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }
}
