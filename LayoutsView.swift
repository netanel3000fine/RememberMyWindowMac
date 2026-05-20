import SwiftUI
import MapKit

struct LayoutsView: View {
    @EnvironmentObject var manager: WindowManager
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        let hasSaved = !manager.store.snapshots.filter({ !$0.value.isAutoSave }).isEmpty
        if manager.liveRecords.isEmpty && !hasSaved {
            emptyState
        } else if let key = manager.selectedSnapshotKey {
            if key == WindowManager.liveKey {
                let fp = manager.currentFingerprint
                let liveSnap = LayoutSnapshot(
                    id: UUID(),
                    name: fp.readableName,
                    screenKey: fp.key,
                    readableScreenKey: fp.readableName,
                    records: manager.liveRecords,
                    createdAt: Date(),
                    updatedAt: Date(),
                    location: nil,
                    isAutoSave: true
                )
                SnapshotDetailView(snapshot: liveSnap, key: key)
            } else if let snapshot = manager.store.snapshots[key] {
                SnapshotDetailView(snapshot: snapshot, key: key)
            } else {
                Text("Select a layout to view details".localized(appLanguage))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("Select a layout to view details".localized(appLanguage))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            Text("No layouts saved yet".localized(appLanguage))
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Arrange your windows and click \"Save Layout\" to record their positions.\nThey'll be restored automatically whenever this screen configuration reconnects.".localized(appLanguage))
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Snapshot List View

struct SnapshotListView: View {
    @EnvironmentObject var manager: WindowManager
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var hoveredKey: String? = nil

    var liveSnapshot: (key: String, snapshot: LayoutSnapshot)? {
        guard !manager.liveRecords.isEmpty else { return nil }
        let fp = manager.currentFingerprint
        let snap = LayoutSnapshot(
            id: UUID(),
            name: fp.readableName,
            screenKey: fp.key,
            readableScreenKey: fp.readableName,
            records: manager.liveRecords,
            createdAt: Date(),
            updatedAt: Date(),
            location: nil,
            isAutoSave: true
        )
        return (key: WindowManager.liveKey, snapshot: snap)
    }

    var savedSnapshots: [(key: String, snapshot: LayoutSnapshot)] {
        return manager.store.snapshots
            .filter { !$0.value.isAutoSave }
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .map { (key: $0.key, snapshot: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // LIVE LAYOUT SECTION
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE LAYOUT".localized(appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                    
                    if let live = liveSnapshot {
                        snapshotRow(live.snapshot, key: live.key, isLive: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .liquidGlass(
                                isSelected: manager.selectedSnapshotKey == live.key,
                                prominent: true,
                                tint: themeColor.color ?? .green,
                                isHovered: hoveredKey == live.key
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered { hoveredKey = live.key }
                                else if hoveredKey == live.key { hoveredKey = nil }
                            }
                            .onTapGesture { manager.selectedSnapshotKey = live.key }
                    } else {
                        Text("No active layout for this screen config".localized(appLanguage))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                }

                // SAVED SESSIONS SECTION
                VStack(alignment: .leading, spacing: 8) {
                    Text("SAVED SESSIONS".localized(appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                    
                    if savedSnapshots.isEmpty {
                        Text("No saved sessions".localized(appLanguage))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    } else {
                        ForEach(savedSnapshots, id: \.key) { item in
                            snapshotRow(item.snapshot, key: item.key, isLive: false)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .liquidGlass(
                                    isSelected: manager.selectedSnapshotKey == item.key,
                                    prominent: false,
                                    tint: themeColor.color ?? .blue,
                                    isHovered: hoveredKey == item.key
                                )
                                .contentShape(Rectangle())
                                .onHover { isHovered in
                                    if isHovered { hoveredKey = item.key }
                                    else if hoveredKey == item.key { hoveredKey = nil }
                                }
                                .onTapGesture { manager.selectedSnapshotKey = item.key }
                                .contextMenu {
                                    Button("Restore") { manager.restore(key: item.key) }
                                        .disabled(!manager.canRestore(snapshot: item.snapshot))
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        manager.deleteSnapshot(key: item.key)
                                        if manager.selectedSnapshotKey == item.key { manager.selectedSnapshotKey = nil }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(12)
        }
        .navigationTitle("Remember")
    }

    func snapshotRow(_ snapshot: LayoutSnapshot, key: String, isLive: Bool) -> some View {
        let rowTint = isLive ? (themeColor.color ?? Color.accentColor) : (themeColor.color ?? Color.primary)
        return HStack(spacing: 12) {
            Image(systemName: isLive ? "display.2" : "display")
                .font(.system(size: 18))
                .foregroundStyle(isLive ? (themeColor.color ?? Color.accentColor) : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.displayName)
                        .font(.system(.headline, design: .rounded).weight(.medium))
                        .lineLimit(1)
                    if isLive {
                        Text("Live".localized(appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((themeColor.color ?? Color.accentColor).opacity(0.15))
                            .foregroundStyle(themeColor.color ?? Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                if isLive {
                    Text(ScreenFingerprint.from(key: snapshot.screenKey).readableName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(themeColor.color ?? Color.accentColor)
                        .lineLimit(1)
                }

                Text("\(snapshot.records.count) windows · \(snapshot.updatedAt.formatted(.relative(presentation: .named).locale(currentLocale)))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            ScreenLayoutThumbnail(
                screenKey: snapshot.screenKey,
                tint: rowTint,
                isLive: isLive
            )
        }
    }
}

// MARK: - Snapshot Detail View

struct SnapshotDetailView: View {
    @EnvironmentObject var manager: WindowManager
    @AppStorage("themeColor") private var themeColor: ThemeColor = .default
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    let snapshot: LayoutSnapshot
    let key: String

    var isPhysicalMismatch: Bool {
        let current = manager.currentFingerprint
        let snapFP = ScreenFingerprint.from(key: snapshot.screenKey)
        
        let currentUUIDs = Set(current.displays.compactMap { $0.uuid })
        let snapUUIDs = Set(snapFP.displays.compactMap { $0.uuid })
        
        // If models match (name + resolution) but physical units (UUIDs) differ
        return current.modelKey == snapFP.modelKey && currentUUIDs != snapUUIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.displayName)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                        Text(ScreenFingerprint.from(key: snapshot.screenKey).readableName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SCREEN ID".localized(appLanguage))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(snapshot.screenKey)
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 240)
                    }
                }

                HStack(spacing: 24) {
                    statPill(label: "Windows".localized(appLanguage), value: "\(snapshot.records.count)")
                    statPill(label: "Created".localized(appLanguage), value: snapshot.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: currentLocale)))
                    statPill(label: "Updated".localized(appLanguage), value: snapshot.updatedAt.formatted(.relative(presentation: .named).locale(currentLocale)))
                }
                
                if isPhysicalMismatch {
                    HStack(spacing: 10) {
                        Image(systemName: "display.and.arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("New monitor detected with the same name".localized(appLanguage))
                                .font(.system(size: 12, weight: .bold))
                            Text("This is a different physical unit than the one in this session.".localized(appLanguage))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                    }
                }

                if let location = snapshot.location, !snapshot.isAutoSave {
                    LocationBlock(snapshotID: key, location: location, isUpdated: snapshot.updatedAt.timeIntervalSince(snapshot.createdAt) > 1)
                }

                if !manager.canRestore(snapshot: snapshot) {
                    HStack(spacing: 10) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("External Screens Missing".localized(appLanguage))
                                .font(.subheadline.weight(.semibold))
                            Text("Connect the required displays to enable restoration of this session.".localized(appLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    }
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.04))

            Divider()

            // Window list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(snapshot.records) { record in
                        let isForeground = record.windowID.appBundleID == snapshot.foregroundBundleID
                        windowRow(record, isForeground: isForeground)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .liquidGlass(isSelected: isForeground, prominent: false, tint: themeColor.color, isHovered: false)
                    }

                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Returns true if this window was captured from a different Mission Control Space
    /// (i.e. it had no visible window on the current Space at capture time).
    /// Set precisely during capture — no false positives from Fill Screen / maximized windows.
    private func isEntireScreen(_ record: WindowRecord) -> Bool {
        record.isFullScreenMode
    }

    func windowRow(_ record: WindowRecord, isForeground: Bool) -> some View {
        let isFull = isEntireScreen(record)
        let rowTint = isFull ? Color.indigo : (themeColor.color ?? .accentColor)

        return HStack(spacing: 12) {
            // Icon: full-screen variant vs normal positioned preview
            if isFull {
                FullScreenPreviewIcon(tint: rowTint)
                    .frame(width: 52, height: 34)
            } else {
                WindowPreviewIcon(record: record, tint: rowTint)
                    .frame(width: 52, height: 34)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.windowID.appName ?? record.windowID.appBundleID)
                        .font(.system(.headline, design: .rounded).weight(.medium))
                    if isFull {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text("Full Screen".localized(appLanguage))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundStyle(Color.indigo)
                        .clipShape(Capsule())
                    }
                    if isForeground {
                        Image(systemName: "square.3.layers.3d.top.filled")
                            .font(.system(size: 10))
                            .foregroundStyle(themeColor.color ?? Color.accentColor)
                            .help("This app will be brought to the front upon restore")
                    }
                }

                HStack(spacing: 4) {
                    if let screenName = record.screenName {
                        Text(lz(screenName))
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(rowTint.opacity(0.1))
                            .foregroundStyle(rowTint)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if !record.windowID.windowTitle.isEmpty {
                        Text(record.windowID.windowTitle)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(record.globalFrame.width)) × \(Int(record.globalFrame.height))")
                    .font(.footnote.monospaced())
                Text("(\(Int(record.globalFrame.origin.x)), \(Int(record.globalFrame.origin.y)))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            let appID = record.windowID.appBundleID
            let appName = record.windowID.appName ?? appID

            Button {
                manager.setForegroundApp(key: key, bundleID: appID)
                manager.bringAppToFront(bundleID: appID)
            } label: {
                Label("Bring \"\(appName)\" to Front", systemImage: "square.3.layers.3d.top.filled")
            }

            Divider()

            Button {
                manager.restore(key: key)
                // Small delay so windows settle, then bring this app to top
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    manager.bringAppToFront(bundleID: appID)
                }
            } label: {
                Label("Restore Layout & Bring \"\(appName)\" to Front", systemImage: "arrow.counterclockwise")
            }
            .disabled(!manager.canRestore(snapshot: snapshot))

            if !snapshot.isAutoSave {
                Divider()

                Button(role: .destructive) {
                    manager.removeAppFromSnapshot(key: key, windowID: record.windowID)
                } label: {
                    Label("Remove from Session", systemImage: "trash")
                }
            }
        }
    }

    func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

}

struct LocationBlock: View {
    @EnvironmentObject var manager: WindowManager
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    let snapshotID: String
    let location: LocationInfo
    let isUpdated: Bool
    
    @State private var isEditing = false
    @State private var editedAddress: String = ""
    @FocusState private var isFocused: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Map Preview
            ZStack {
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))) {
                    Marker("", coordinate: coordinate)
                }
                .id(snapshotID) // Force recreation when switching layouts to ensure position updates
                .allowsHitTesting(false)
                
                Color.black.opacity(0.01)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let url = URL(string: "http://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=Saved%20Location")!
                        NSWorkspace.shared.open(url)
                    }
            }
            .frame(width: 120, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .fixedSize()
            
            VStack(alignment: .leading, spacing: 4) {
                Label((isUpdated ? "Saved&Updated At" : "Saved At").localized(appLanguage), systemImage: "location.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
                
                if isEditing {
                    TextField("Location Name", text: $editedAddress, onCommit: {
                        manager.updateLocationAddress(key: snapshotID, newAddress: editedAddress)
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .focused($isFocused)
                    .onAppear {
                        editedAddress = location.address ?? "\(location.latitude), \(location.longitude)"
                        isFocused = true
                    }
                } else {
                    Text(location.address ?? "\(location.latitude), \(location.longitude)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: 200, alignment: .leading)
                        .onTapGesture {
                            isEditing = true
                        }
                }
                
                if !isEditing {
                    Text("Click to rename".localized(appLanguage))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 200, alignment: .leading)
        }
        .padding(12)
        .frame(height: 104)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            VisualEffectView(material: .selection, blendingMode: .withinWindow)
                .opacity(0.4)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        }
    }
}
