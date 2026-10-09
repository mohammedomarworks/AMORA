import SwiftUI
import Observation

enum IslandPage: CaseIterable {
    case home
    case aiTalk
    case timer
    case clipboard
    case notes
    case fileShelf
    case automations
    case github
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .aiTalk: return "bubble.left.and.text.bubble.right.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .fileShelf: return "tray.and.arrow.down"
        case .automations: return "bolt.badge.clock"
        case .github: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    var label: String {
        switch self {
        case .home: return "Home"
        case .aiTalk: return "AI Talk"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .fileShelf: return "File Shelf"
        case .automations: return "Automations"
        case .github: return "GitHub"
        }
    }
}

@Observable @MainActor
final class IslandNavigationModel {
    static let shared = IslandNavigationModel()
    
    var selectedPage: IslandPage = .home
    var isQuickMenuOpen: Bool = false
    
    func navigateTo(_ page: IslandPage) {
        selectedPage = page
        isQuickMenuOpen = false
    }
    
    func nextPage() {
        let allCases = IslandPage.allCases
        guard let currentIndex = allCases.firstIndex(of: selectedPage) else { return }
        let nextIndex = currentIndex + 1
        if nextIndex < allCases.count {
            selectedPage = allCases[nextIndex]
        }
    }
    
    func previousPage() {
        let allCases = IslandPage.allCases
        guard let currentIndex = allCases.firstIndex(of: selectedPage) else { return }
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            selectedPage = allCases[prevIndex]
        }
    }
    
    func toggleQuickMenu() {
        isQuickMenuOpen.toggle()
    }
}

@MainActor
struct IslandNavBar: View {
    var topInset: CGFloat = 0
    @Bindable var nav = IslandNavigationModel.shared
    
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var settings: SettingsStore { AppState.shared.settings }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Group in left ear
            HStack(spacing: 8) {
                NavBarButton(
                    page: .home,
                    isSelected: nav.selectedPage == .home,
                    palette: palette
                ) {
                    nav.navigateTo(.home)
                }
                
                NavBarButton(
                    page: .aiTalk,
                    isSelected: nav.selectedPage == .aiTalk,
                    palette: palette
                ) {
                    nav.navigateTo(.aiTalk)
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        nav.toggleQuickMenu()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(nav.isQuickMenuOpen ? palette.accent : .white.opacity(0.65))
                        .frame(width: 32, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(nav.isQuickMenuOpen ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Quick Actions")
                .accessibilityLabel("Quick Actions")
            }
            .padding(.leading, 14)
            
            Spacer()
            
            // Right Group in right ear
            HStack(spacing: 8) {
                Button(action: {
                    WindowManager.shared.showSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 32, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Open Settings")
                
                Button(action: {
                    settings.soundEnabled.toggle()
                    if settings.soundEnabled {
                        SoundService.shared.play(.success)
                    }
                }) {
                    Image(systemName: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(settings.soundEnabled ? .white.opacity(0.75) : .white.opacity(0.4))
                        .frame(width: 32, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(settings.soundEnabled ? "Mute Sound" : "Enable Sound")
                .accessibilityLabel(settings.soundEnabled ? "Mute Sound" : "Enable Sound")
            }
            .padding(.trailing, 14)
        }
        .frame(height: max(topInset, 34))
    }
}

@MainActor
struct NavBarButton: View {
    let page: IslandPage
    let isSelected: Bool
    let palette: ThemePalette
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: page.icon)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : (isHovered ? .white.opacity(0.9) : .white.opacity(0.6)))
                .frame(width: 34, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.20) : (isHovered ? Color.white.opacity(0.09) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(page.label)
        .accessibilityLabel(page.label)
    }
}

@MainActor
struct IslandQuickMenu: View {
    @Bindable var nav = IslandNavigationModel.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }
    
    let menuPages: [IslandPage] = [.timer, .clipboard, .notes, .fileShelf, .automations, .github]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(menuPages, id: \.self) { page in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        nav.navigateTo(page)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16, alignment: .center)
                        
                        Text(page.label)
                            .font(.system(size: 12, weight: .medium))
                        
                        Spacer()
                        
                        if nav.selectedPage == page {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(palette.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .foregroundColor(nav.selectedPage == page ? palette.accent : .white.opacity(0.8))
                }
                .buttonStyle(.amoraPressable)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(width: 140)
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
    }
}
