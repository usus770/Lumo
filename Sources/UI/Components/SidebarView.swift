import SwiftUI

/// Library sidebar with brand horizontal logo at top and brandGradient selection indicators.
struct SidebarView: View {
    @Environment(WindowManager.self) private var windowManager
    
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var hoveredSection: SidebarSection? = nil
    
    var body: some View {
        @Bindable var wm = windowManager
        
        VStack(spacing: 0) {
            // Horizontal Logo at top
            HStack {
                LumoHorizontalLogoView(height: 24)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Navigation Groups
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(SidebarGroup.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            // Group Header
                            HStack {
                                Text(group.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LumoTheme.textTertiary)
                                    .tracking(0.5)
                                
                                Spacer()
                                
                                if group == .playlists {
                                    Button {
                                        newPlaylistName = ""
                                        showNewPlaylistAlert = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(LumoTheme.accentPink)
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .help("New Playlist")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 2)
                            
                            // Group Items
                            ForEach(group.sections) { section in
                                let isSelected = wm.selectedSection == section
                                let isHovered = hoveredSection == section
                                
                                SidebarItemRow(
                                    section: section,
                                    isSelected: isSelected,
                                    isHovered: isHovered
                                ) {
                                    wm.selectedSection = section
                                }
                                .onHover { hovering in
                                    hoveredSection = hovering ? section : nil
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
            
            // Library Stats Footer
            VStack(spacing: 4) {
                Divider()
                    .background(LumoTheme.stroke)
                
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                    
                    if wm.filteredTrackCount == wm.totalTrackCount || wm.filteredTrackCount == 0 {
                        Text("\(wm.totalTrackCount) songs")
                            .font(LumoTheme.Typography.caption)
                    } else {
                        Text("\(wm.filteredTrackCount) of \(wm.totalTrackCount) songs")
                            .font(LumoTheme.Typography.caption)
                    }
                }
                .foregroundStyle(LumoTheme.textTertiary)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
        }
        .background(LumoTheme.bg0)
        .sheet(isPresented: $showNewPlaylistAlert) {
            NewPlaylistSheet(isPresented: $showNewPlaylistAlert) { _ in
                wm.selectedSection = .playlists
            }
        }
    }
}

private struct SidebarItemRow: View {
    let section: SidebarSection
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    
    private var iconColor: Color {
        if isSelected { return LumoTheme.accentPink }
        if isHovered { return LumoTheme.textPrimary }
        return LumoTheme.textSecondary
    }
    
    private var textColor: Color {
        if isSelected || isHovered { return LumoTheme.textPrimary }
        return LumoTheme.textSecondary
    }
    
    private var backgroundColor: Color {
        if isSelected { return LumoTheme.surfaceRaised }
        if isHovered { return LumoTheme.surfaceRaised.opacity(0.5) }
        return .clear
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isSelected {
                    Capsule()
                        .fill(LumoTheme.brandGradient)
                        .frame(width: 3.5, height: 18)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 3.5, height: 18)
                }
                
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                
                Text(section.rawValue)
                    .font(isSelected ? LumoTheme.Typography.body.weight(.semibold) : LumoTheme.Typography.body)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: LumoTheme.Radius.small)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
