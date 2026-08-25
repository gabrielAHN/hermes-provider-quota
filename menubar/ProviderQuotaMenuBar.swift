import AppKit
import Foundation

struct QuotaPayload: Decodable {
    let generatedAt: String
    let providers: [QuotaProvider]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case providers
    }
}

struct QuotaProvider: Decodable {
    let provider: String
    let label: String
    let status: String
    let plan: String?
    let windows: [QuotaWindow]
    let details: [String]
    let message: String?
}

struct QuotaWindow: Decodable {
    let label: String
    let remainingPercent: Double?
    let remainingAmount: Double?
    let currency: String?
    let resetsAt: String?
    let detail: String?
    let warning: Bool

    enum CodingKeys: String, CodingKey {
        case label
        case remainingPercent = "remaining_percent"
        case remainingAmount = "remaining_amount"
        case currency
        case resetsAt = "resets_at"
        case detail
        case warning
    }
}

struct DesktopStatus {
    let running: Bool
    let mode: String
    let authMode: String
    let remoteURL: String?
    let signedIn: Bool
    let reachable: Bool
    let profile: String?
    let provider: String?
    let model: String?

    var connected: Bool {
        signedIn && reachable
    }
}

struct MenuSnapshot {
    let payload: QuotaPayload
    let desktop: DesktopStatus
}

struct ProviderActivityPayload: Decodable {
    let updatedAt: Double
    let instances: [ProviderActivityInstance]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case instances
    }
}

struct ProviderActivityInstance: Decodable, Equatable {
    let completedAt: Double?
    let key: String
    let model: String
    let profile: String
    let provider: String
    let providerColor: String
    let providerLabel: String
    let sessionId: String
    let startedAt: Double
    let status: String?
    let title: String

    var completed: Bool {
        status == "completed"
    }

    var sleeping: Bool {
        status == "sleeping"
    }

    var failed: Bool {
        status == "error" || status == "failed"
    }

    var activityRank: Int {
        switch status {
        case "error", "failed", "waiting", "working": return 0
        case "completed": return 1
        default: return 2
        }
    }
}

extension NSColor {
    convenience init?(activityHex value: String) {
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let number = Int(hex, radix: 16) else { return nil }
        self.init(
            deviceRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }

    // Hermes brand palette (mirrors the Desktop app's --ui-* / --theme-* CSS
    // variables) so this menu reads as part of Hermes. Blue is the primary accent
    // — matching the Desktop theme (--theme-primary #0053fd); provider brand
    // colours are used only as small secondary identity tints.
    static let hermesBlue = NSColor(activityHex: "0053fd")!        // --theme-primary / --ui-blue (primary accent)
    static let hermesGreen = NSColor(activityHex: "1f8a65")!       // --ui-green (connected / healthy)
    static let hermesOrange = NSColor(activityHex: "db704b")!      // --ui-orange (low / waiting)
    static let hermesRed = NSColor(activityHex: "cf2d56")!         // --ui-red (disconnected / error)
    static let hermesYellow = NSColor(activityHex: "c08532")!      // --ui-yellow (exhausted)
}

final class HoverGlowButton: NSButton {
    var glowColor: NSColor = .controlAccentColor {
        didSet {
            updateGlow()
        }
    }
    private var hoverArea: NSTrackingArea?
    private var hovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = false
        updateGlow()
    }

    override func updateTrackingAreas() {
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 7, cornerHeight: 7, transform: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateGlow()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateGlow()
    }

    private func updateGlow() {
        // Always-on glow (colored fill + border + soft shadow) that intensifies
        // on hover, so the buttons read as glowing Hermes chips at rest.
        layer?.backgroundColor = glowColor.withAlphaComponent(hovering ? 0.30 : 0.16).cgColor
        layer?.borderColor = glowColor.withAlphaComponent(hovering ? 1.0 : 0.6).cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = glowColor.cgColor
        layer?.shadowOpacity = hovering ? 0.95 : 0.55
        layer?.shadowRadius = hovering ? 10 : 6
        layer?.shadowOffset = .zero
    }
}

final class HoverGlowSwitch: NSSwitch {
    private var hoverArea: NSTrackingArea?
    private var hovering = false
    var glowEnabled = false {
        didSet {
            updateGlow()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false
        updateGlow()
    }

    override func updateTrackingAreas() {
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 11, cornerHeight: 11, transform: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateGlow()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateGlow()
    }

    private func updateGlow() {
        let color = glowEnabled ? NSColor.systemPurple : NSColor.secondaryLabelColor
        layer?.backgroundColor = color.withAlphaComponent(glowEnabled ? (hovering ? 0.22 : 0.11) : (hovering ? 0.055 : 0)).cgColor
        layer?.borderColor = color.withAlphaComponent(glowEnabled ? (hovering ? 0.82 : 0.48) : (hovering ? 0.2 : 0.08)).cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = color.cgColor
        layer?.shadowOpacity = glowEnabled ? (hovering ? 0.9 : 0.48) : (hovering ? 0.12 : 0)
        layer?.shadowRadius = glowEnabled ? (hovering ? 10 : 6) : (hovering ? 3 : 0)
        layer?.shadowOffset = .zero
    }
}

final class TransparentMenuEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.alphaValue = 0.94
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// A pet as Hermes ships it: discovered from ~/.hermes/pets/<id>/pet.json so the
// menu-bar adopts whatever pets Hermes has installed (not a hardcoded sprite).
struct PetInfo: Equatable {
    let id: String
    let displayName: String
    let spritesheetURL: URL
    let thumbnailURL: URL?
}

enum PetCatalog {
    static var petsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/pets")
    }
    // Pets downloaded via a REMOTE Hermes Desktop land on the gateway, not here;
    // the app syncs them into this cache so they show up locally.
    static var cacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/pets-cache")
    }

    static func installed() -> [PetInfo] {
        let fm = FileManager.default
        var pets: [PetInfo] = []
        var seen = Set<String>()
        // Local pets dir wins over the gateway cache (scanned first).
        for base in [petsDir, cacheDir] {
            guard let entries = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }
            for dir in entries {
                let name = dir.lastPathComponent
                if name.hasPrefix(".") { continue }
                let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                guard let data = try? Data(contentsOf: dir.appendingPathComponent("pet.json")),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let id = (obj["id"] as? String) ?? name
                if seen.contains(id) { continue }
                let sheet = dir.appendingPathComponent((obj["spritesheetPath"] as? String) ?? "spritesheet.webp")
                guard fm.fileExists(atPath: sheet.path) else { continue }
                seen.insert(id)
                let display = (obj["displayName"] as? String) ?? id.capitalized
                // Thumbnails: local catalog first, then a cached copy.
                let localThumb = petsDir.appendingPathComponent(".thumbs/\(id).png")
                let cacheThumb = dir.appendingPathComponent("thumbnail.png")
                let thumb = fm.fileExists(atPath: localThumb.path) ? localThumb
                    : (fm.fileExists(atPath: cacheThumb.path) ? cacheThumb : nil)
                pets.append(PetInfo(id: id, displayName: display, spritesheetURL: sheet, thumbnailURL: thumb))
            }
        }
        return pets.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // The active pet: the user's saved choice if still installed, else the first
    // installed pet (Hermes ships "nukey" by default).
    static func selected() -> PetInfo? {
        let all = installed()
        if let saved = UserDefaults.standard.string(forKey: "selectedPet"),
           let match = all.first(where: { $0.id == saved }) {
            return match
        }
        return all.first
    }
}

final class ActivityPetsView: NSView {
    static let tileWidth: CGFloat = 56
    static let tileHeight: CGFloat = 64
    static let tileGap: CGFloat = 5
    private var phase = 0
    private var animationTimer: Timer?
    private var dragDistance: CGFloat = 0
    private var lastDragLocation: NSPoint?
    private var toolTipTags: [NSView.ToolTipTag] = []
    // Hermes sprite frames are a fixed 192×208 (agent/pet/constants FRAME_W/H);
    // the column/row counts are derived from each sheet so any atlas shape fits
    // (8×9 Codex, 9×8 legacy, or the 8×11 sheets that add a sleep row 10).
    static let frameW: CGFloat = 192
    static let frameH: CGFloat = 208
    private var spritesheet: NSImage?
    private var thumbnail: NSImage?
    func setPet(_ pet: PetInfo?) {
        spritesheet = pet.flatMap { NSImage(contentsOf: $0.spritesheetURL) }
        thumbnail = pet?.thumbnailURL.flatMap { NSImage(contentsOf: $0) }
        needsDisplay = true
    }
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onSelect: ((ProviderActivityInstance) -> Void)?
    var instances: [ProviderActivityInstance] = [] {
        didSet {
            rebuildToolTips()
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            guard let self else { return }
            phase = (phase + 1) % 96
            needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        animationTimer?.invalidate()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragDistance = 0
        lastDragLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        guard let previous = lastDragLocation else { return }
        let deltaX = current.x - previous.x
        let deltaY = current.y - previous.y
        dragDistance += hypot(deltaX, deltaY)
        lastDragLocation = current
        onMove?(deltaX, deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        guard dragDistance < 4, let instance = instance(at: convert(event.locationInWindow, from: nil)) else { return }
        onSelect?(instance)
    }

    private func instance(at point: NSPoint) -> ProviderActivityInstance? {
        let step = Self.tileWidth + Self.tileGap
        let index = Int(point.x / step)
        guard instances.indices.contains(index) else { return nil }
        let tile = NSRect(x: CGFloat(index) * step, y: 0, width: Self.tileWidth, height: Self.tileHeight)
        return tile.contains(point) ? instances[index] : nil
    }

    private func rebuildToolTips() {
        toolTipTags.forEach(removeToolTip)
        toolTipTags = instances.indices.map { index in
            let x = CGFloat(index) * (Self.tileWidth + Self.tileGap)
            return addToolTip(NSRect(x: x, y: 0, width: Self.tileWidth, height: Self.tileHeight), owner: self, userData: nil)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let instance = instance(at: point) else { return "Hermes" }
        if instance.key == "needs-login" {
            return instance.profile == "No source"
                ? "Nothing enabled — enable Hermes or Local"
                : "\(instance.profile) disconnected — sign in to see quotas"
        }
        let state = instance.sleeping ? "Sleeping" : instance.completed ? "Completed" : instance.failed ? "Error" : instance.status == "waiting" ? "Waiting for input" : "Processing"
        let title = instance.title.isEmpty ? "Hermes session" : instance.title
        return "\(instance.profile) · \(title) · \(state)"
    }

    private func profileColor(_ profile: String) -> NSColor {
        var hash: UInt32 = 0
        for scalar in profile.unicodeScalars {
            hash = hash &* 31 &+ UInt32(scalar.value)
        }
        return NSColor(calibratedHue: CGFloat(hash % 360) / 360, saturation: 0.62, brightness: 0.94, alpha: 1)
    }

    private func drawNukey(_ instance: ProviderActivityInstance, in destination: NSRect) {
        var target = destination
        if instance.status == "waiting" {
            target.origin.y += CGFloat(sin(Double(phase) * .pi / 4)) * 1.5
        } else if instance.failed {
            target.origin.x += phase.isMultiple(of: 2) ? -1.8 : 1.8
        } else if instance.status == "working" {
            // Busy little bob while it "cooks".
            target.origin.y += CGFloat(sin(Double(phase) * .pi / 4)) * 1.1
        }
        if let image = spritesheet {
            let frameWidth = Self.frameW
            let frameHeight = Self.frameH
            let now = Date().timeIntervalSince1970 * 1000
            // Canonical Hermes/petdex row taxonomy (agent/pet/constants
            // CODEX_STATE_ROWS): every pet's sheet lays its rows out the same
            // way, so this mapping animates ANY pet correctly — nukey, cosmo, …
            //   0 idle · 1 running-right · 2 running-left · 3 waving
            //   4 jumping · 5 failed · 6 waiting · 7 running · 8 review
            let row: Int
            switch instance.status {
            case "working":            row = 7   // running → actively working
            case "waiting":            row = 6   // waiting → needs your input
            case "error", "failed":    row = 5   // failed → in trouble
            case "completed":
                // celebrate (jump) briefly, then settle back to idle
                row = (now - (instance.completedAt ?? now) < 1_800) ? 4 : 0
            case "sleeping":           row = 0   // dormant/idle → the pet's own idle
            default:                   row = 0   // idle
            }
            // Hermes steps FRAMES_PER_STATE (6) columns across the loop.
            let frame = phase / 2 % 6
            let source = NSRect(
                x: CGFloat(frame) * frameWidth,
                y: image.size.height - CGFloat(row + 1) * frameHeight,
                width: frameWidth,
                height: frameHeight
            )
            let previousInterpolation = NSGraphicsContext.current?.imageInterpolation
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: target, from: source, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            if let previousInterpolation {
                NSGraphicsContext.current?.imageInterpolation = previousInterpolation
            }
            return
        }
        thumbnail?.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawPet(_ instance: ProviderActivityInstance, tile: NSRect) {
        let working = instance.status == "working"
        let failed = instance.failed
        let petRect = NSRect(x: tile.minX + 2, y: tile.minY + 8, width: 52, height: 56.3)
        let halo = NSBezierPath(ovalIn: NSRect(x: petRect.minX + 4, y: petRect.minY + 5, width: petRect.width - 8, height: petRect.height - 10))
        // Hermes purple is the primary halo accent; status recolours it.
        let haloColor: NSColor = failed ? .hermesRed : instance.status == "waiting" ? .hermesOrange : instance.completed ? .hermesGreen : working ? .hermesBlue : .hermesBlue
        let haloPulse = CGFloat((sin(Double(phase) * .pi / 6) + 1) * 0.035)
        haloColor.withAlphaComponent((working || failed ? 0.17 : 0.09) + haloPulse).setFill()
        halo.fill()
        drawNukey(instance, in: petRect)

        if working {
            for index in 0..<3 {
                let active = index == phase % 3
                let size: CGFloat = active ? 4.5 : 3.4
                let x = tile.midX - 8 + CGFloat(index) * 8 - size / 2
                let dot = NSBezierPath(ovalIn: NSRect(x: x, y: tile.minY + 5, width: size, height: size))
                NSColor.hermesBlue.withAlphaComponent(active ? 1 : 0.45).setFill()
                dot.fill()
            }
        } else if instance.status == "waiting" || failed {
            let pulse = CGFloat((sin(Double(phase) * .pi / 4) + 1) * 1.2)
            let badge = NSBezierPath(ovalIn: NSRect(x: tile.maxX - 16 - pulse / 2, y: tile.minY + 2 - pulse / 2, width: 14 + pulse, height: 14 + pulse))
            (failed ? NSColor.hermesRed : NSColor.hermesOrange).setFill()
            badge.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            NSAttributedString(string: failed ? "!" : "?", attributes: attributes).draw(at: NSPoint(x: tile.maxX - (failed ? 10.6 : 12.3), y: tile.minY + 3.4))
        } else if instance.completed {
            let badge = NSBezierPath(ovalIn: NSRect(x: tile.maxX - 16, y: tile.minY + 2, width: 14, height: 14))
            NSColor.hermesGreen.setFill()
            badge.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: tile.maxX - 12.5, y: tile.minY + 9))
            check.line(to: NSPoint(x: tile.maxX - 9.7, y: tile.minY + 6))
            check.line(to: NSPoint(x: tile.maxX - 5, y: tile.minY + 11.5))
            NSColor.white.setStroke()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, instance) in instances.enumerated() {
            let x = CGFloat(index) * (Self.tileWidth + Self.tileGap)
            drawPet(instance, tile: NSRect(x: x, y: 0, width: Self.tileWidth, height: Self.tileHeight))
        }
    }
}

final class ActivityPetsPanel: NSPanel {
    private let petsView = ActivityPetsView(frame: .zero)
    private var placed = false
    var onSelect: ((ProviderActivityInstance) -> Void)? {
        didSet {
            petsView.onSelect = onSelect
        }
    }

    func setPet(_ pet: PetInfo?) {
        petsView.setPet(pet)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ActivityPetsView.tileWidth, height: ActivityPetsView.tileHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        contentView = petsView
        petsView.onMove = { [weak self] deltaX, deltaY in
            guard let self else { return }
            setFrameOrigin(NSPoint(x: frame.origin.x + deltaX, y: frame.origin.y + deltaY))
            UserDefaults.standard.set(frame.origin.x, forKey: "activityPetsX")
            UserDefaults.standard.set(frame.origin.y, forKey: "activityPetsY")
        }
    }

    private func constrainedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(origin) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
    }

    func show(_ instances: [ProviderActivityInstance]) {
        let visible = Array(instances.prefix(8))
        let width = CGFloat(visible.count) * ActivityPetsView.tileWidth + CGFloat(max(0, visible.count - 1)) * ActivityPetsView.tileGap
        let size = NSSize(width: width, height: ActivityPetsView.tileHeight)
        let previousOrigin = frame.origin
        petsView.frame = NSRect(origin: .zero, size: size)
        petsView.instances = visible
        setContentSize(size)
        let origin: NSPoint
        if placed {
            origin = previousOrigin
        } else if UserDefaults.standard.object(forKey: "activityPetsX") != nil {
            origin = NSPoint(
                x: UserDefaults.standard.double(forKey: "activityPetsX"),
                y: UserDefaults.standard.double(forKey: "activityPetsY")
            )
        } else if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            origin = NSPoint(x: frame.maxX - size.width - 18, y: frame.minY + 18)
        } else {
            origin = previousOrigin
        }
        let constrained = constrainedOrigin(origin, size: size)
        setFrameOrigin(constrained)
        UserDefaults.standard.set(constrained.x, forKey: "activityPetsX")
        UserDefaults.standard.set(constrained.y, forKey: "activityPetsY")
        placed = true
        orderFrontRegardless()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    // Sources: `.hermes` = the Hermes Desktop app's gateway session (via
    // hermes-desktop-quotas); `.local` = the locally-authenticated providers on
    // this Mac (via hermes-local-quotas). The user enables one or BOTH; when both
    // are enabled the menu shows each source's providers together (the same
    // provider, e.g. Claude, can appear once per source). No fallback.
    private enum GatewayKind: String { case hermes, local }
    // One entry per enabled source with the providers it returned (or synthetic
    // "Disconnected" rows if that source is down).
    private struct SourceQuota {
        let kind: GatewayKind
        let providers: [QuotaProvider]
        let connected: Bool
        let generatedAt: String?
    }
    private var sources: [SourceQuota] = []
    private var desktopStatus = DesktopStatus(running: false, mode: "unknown", authMode: "unknown", remoteURL: nil, signedIn: false, reachable: false, profile: nil, provider: nil, model: nil)
    private var refreshing = false
    private var timer: Timer?
    private var authRefreshTimers: [Timer] = []
    private var signalSource: DispatchSourceSignal?
    // Providers whose detail is expanded (collapsed by default → brief row with a
    // bar; click to expand for per-window info). Session-scoped.
    private var expandedProviders = Set<String>()
    // Last provider slug→label from a successful fetch, PER source, so a
    // disconnected (or freshly-switched) source lists only its own providers, and
    // disabling a source can drop its providers entirely.
    private var lastProvidersByKind: [String: [(slug: String, label: String)]] = {
        var out: [String: [(slug: String, label: String)]] = [:]
        for kind in ["hermes", "local"] {
            let slugs = UserDefaults.standard.stringArray(forKey: "lastProviderSlugs.\(kind)") ?? []
            let labels = UserDefaults.standard.stringArray(forKey: "lastProviderLabels.\(kind)") ?? []
            if !slugs.isEmpty { out[kind] = zip(slugs, labels).map { ($0, $1) } }
        }
        return out
    }()
    private var activityTimer: Timer?
    private let activityPanel = ActivityPetsPanel()
    private var activityPetsEnabled: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "activityPetsEnabled") == nil || defaults.bool(forKey: "activityPetsEnabled")
    }()

    private func sourceName(_ kind: GatewayKind) -> String {
        kind == .local ? "Local" : "Hermes"
    }

    // Any enabled source returned data.
    private var anyConnected: Bool {
        sources.contains { $0.connected }
    }

    private func hermesSource() -> SourceQuota? {
        sources.first { $0.kind == .hermes }
    }

    // Every enabled source is down (or none is enabled) — drives the "not
    // working" pet + a sign-in prompt.
    private var needsLogin: Bool {
        !enabledGateways().isEmpty && !anyConnected
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        activityPanel.onSelect = { [weak self] instance in
            self?.openHermesSession(instance)
        }
        activityPanel.setPet(PetCatalog.selected())
        syncPetsFromGateway()
        updateStatusItem()
        rebuildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
            self?.syncPetsFromGateway()  // pick up newly-installed gateway pets
        }
        refreshActivityPets()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshActivityPets()
        }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
        source.resume()
        signalSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTimer?.invalidate()
        activityPanel.orderOut(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        refreshDesktopStatus()
        syncPetsFromGateway()  // reflect a pet installed since the last open
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = statusDotsImage()
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = statusTooltip()
        button.setAccessibilityLabel("Provider quota status")
    }

    private func label(_ text: String, frame: NSRect, font: NSFont, color: NSColor = .labelColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func menuMaterialView(_ frame: NSRect) -> NSView {
        // Transparent container: let the native NSMenu vibrancy be the ONE
        // continuous background for the whole menu. Previously each section was
        // its own .sidebar NSVisualEffectView with a translucent tint, so the
        // materials stacked per-row and produced the patchy/"weird" banding.
        // Plain, uncoloured section container — the native NSMenu vibrancy is the
        // single seamless background. No per-section tint and no divider lines
        // (rebuildMenu no longer inserts separators), so the menu reads as one
        // clean translucent surface.
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    private func addView(_ view: NSView) {
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }

    private func titleView() -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 68))
        view.addSubview(label("Provider Quotas", frame: NSRect(x: 16, y: 39, width: 230, height: 20), font: .systemFont(ofSize: 15, weight: .semibold)))
        let connection = connectionSummary()
        view.addSubview(label(connection, frame: NSRect(x: 16, y: 20, width: 300, height: 17), font: .systemFont(ofSize: 11, weight: .medium), color: anyConnected ? .hermesGreen : .hermesRed))
        let generatedAt = sources.compactMap { $0.generatedAt }.first
        let updated = formattedRelativeDate(generatedAt).map { "Updated \($0)" } ?? "Provider quotas"
        view.addSubview(label(updated, frame: NSRect(x: 16, y: 4, width: 300, height: 16), font: .systemFont(ofSize: 10.5), color: .secondaryLabelColor))
        let image = NSImageView(frame: NSRect(x: 320, y: 28, width: 22, height: 22))
        image.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "Quotas")
        image.contentTintColor = .hermesBlue
        view.addSubview(image)
        return view
    }

    // Stable per-(source,provider) key so the same provider from two sources
    // expands independently.
    private func providerKey(_ kind: GatewayKind, _ slug: String) -> String { "\(kind.rawValue):\(slug)" }

    // Collapsed provider row: brief summary + a provider-coloured bar (overall
    // remaining). Click toggles the expanded per-window detail. `connected` is the
    // provider's SOURCE state (so a provider from a down source reads red even if
    // the other source is up).
    private func providerView(_ provider: QuotaProvider, kind: GatewayKind, connected: Bool) -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 48))
        let key = providerKey(kind, provider.provider)
        let expanded = expandedProviders.contains(key)
        let chevron = NSImageView(frame: NSRect(x: 13, y: 18, width: 12, height: 12))
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: expanded ? "Collapse" : "Expand")
        chevron.contentTintColor = .tertiaryLabelColor
        view.addSubview(chevron)
        let symbol = providerSymbolName(provider.provider)
        let image = NSImageView(frame: NSRect(x: 32, y: 25, width: 16, height: 16))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: provider.label)
        image.contentTintColor = connected && provider.status == "ok" ? providerBrandColor(provider) : providerIndicatorColor(provider, connected: connected)
        view.addSubview(image)
        view.addSubview(label(provider.label, frame: NSRect(x: 56, y: 26, width: 150, height: 18), font: .systemFont(ofSize: 13, weight: .semibold)))
        if let plan = provider.plan {
            view.addSubview(label(plan.uppercased(), frame: NSRect(x: 200, y: 28, width: 95, height: 15), font: .systemFont(ofSize: 9, weight: .medium), color: .tertiaryLabelColor, alignment: .right))
        }
        let statusImage = NSImageView(frame: NSRect(x: 322, y: 27, width: 14, height: 14))
        statusImage.image = providerDotImage(provider, size: 14, connected: connected)
        view.addSubview(statusImage)
        // Brief line: summary text + an overall provider-coloured bar.
        let summaryColor: NSColor = (connected && provider.status == "ok") ? .secondaryLabelColor : providerIndicatorColor(provider, connected: connected)
        view.addSubview(label(providerSummary(provider, connected: connected), frame: NSRect(x: 56, y: 7, width: 170, height: 15), font: .systemFont(ofSize: 10.5), color: summaryColor))
        if connected, provider.status == "ok", let minimum = providerMinimum(provider) {
            let track = NSView(frame: NSRect(x: 232, y: 11, width: 104, height: 6))
            track.wantsLayer = true
            track.layer?.cornerRadius = 3
            track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
            let fillWidth = 104 * max(0, min(100, minimum)) / 100
            let fill = NSView(frame: NSRect(x: 0, y: 0, width: fillWidth, height: 6))
            fill.wantsLayer = true
            fill.layer?.cornerRadius = 3
            fill.layer?.backgroundColor = barColor(for: provider, remainingPercent: minimum).cgColor
            track.addSubview(fill)
            view.addSubview(track)
        }
        let button = NSButton(frame: view.bounds)
        button.isBordered = false
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.target = self
        button.action = #selector(toggleProviderExpanded)
        button.toolTip = expanded ? "Collapse \(provider.label)" : "Expand \(provider.label)"
        view.addSubview(button)
        return view
    }

    // Small source header shown above a source's providers when >1 source is on.
    private func sourceHeaderView(_ source: SourceQuota) -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 22))
        let dot = NSImageView(frame: NSRect(x: 16, y: 6, width: 9, height: 9))
        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        dot.contentTintColor = source.connected ? .hermesGreen : .hermesRed
        view.addSubview(dot)
        view.addSubview(label(sourceName(source.kind).uppercased(), frame: NSRect(x: 32, y: 4, width: 200, height: 14),
                              font: .systemFont(ofSize: 9.5, weight: .semibold), color: .secondaryLabelColor))
        view.addSubview(label(source.connected ? "connected" : "disconnected", frame: NSRect(x: 214, y: 4, width: 128, height: 14),
                              font: .systemFont(ofSize: 9.5), color: source.connected ? .hermesGreen : .hermesRed, alignment: .right))
        return view
    }

    // Bar colour = the provider's brand colour, turning red only when exhausted.
    private func barColor(for provider: QuotaProvider, remainingPercent: Double?) -> NSColor {
        if let r = remainingPercent, r <= 0 { return .hermesRed }
        return providerBrandColor(provider)
    }

    // Synthetic provider rows for a disconnected source — from that source's
    // last-known provider list (or the default set if never connected).
    private func disconnectedProviders(for kind: GatewayKind) -> [QuotaProvider] {
        let cached = lastProvidersByKind[kind.rawValue] ?? []
        let base = cached.isEmpty
            ? [("openrouter", "OpenRouter"), ("anthropic", "Claude"), ("openai-codex", "Codex")]
            : cached.map { ($0.slug, $0.label) }
        return base.map { QuotaProvider(provider: $0.0, label: $0.1, status: "disconnected", plan: nil, windows: [], details: [], message: "Disconnected") }
    }


    private func providerMinimum(_ provider: QuotaProvider) -> Double? {
        provider.windows.compactMap(\.remainingPercent).min()
    }

    private func providerIsExhausted(_ provider: QuotaProvider) -> Bool {
        provider.status == "ok" && provider.windows.contains {
            ($0.remainingPercent.map { $0 <= 0 } ?? false) || ($0.remainingAmount.map { $0 <= 0 } ?? false)
        }
    }

    private func formattedAmount(_ amount: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private func providerSymbolName(_ provider: String) -> String {
        switch provider {
        case "openrouter":
            return "arrow.triangle.branch"
        case "anthropic":
            return "sparkles"
        default:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func providerBrandColor(_ provider: QuotaProvider) -> NSColor {
        providerBrandColor(provider.provider)
    }

    private func providerBrandColor(_ provider: String) -> NSColor {
        switch provider {
        case "openrouter":
            return NSColor(deviceRed: 142 / 255, green: 26 / 255, blue: 254 / 255, alpha: 1)
        case "anthropic":
            return NSColor(deviceRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
        default:
            return NSColor(deviceRed: 16 / 255, green: 163 / 255, blue: 127 / 255, alpha: 1)
        }
    }

    private func providerDotImage(_ provider: QuotaProvider, size: CGFloat, connected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let dot = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3))
        providerBrandColor(provider).setFill()
        dot.fill()
        let disconnected = !connected || provider.status != "ok"
        let exhausted = !disconnected && providerIsExhausted(provider)
        if disconnected || exhausted {
            (disconnected ? NSColor.hermesRed : NSColor.hermesYellow).setStroke()
            dot.lineWidth = 2
            dot.stroke()
        }
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = disconnected ? "\(provider.label) is not connected" : exhausted ? "\(provider.label) has no quota" : "\(provider.label) is active"
        return image
    }

    private func providerIndicatorColor(_ provider: QuotaProvider, connected: Bool) -> NSColor {
        guard connected else { return .hermesRed }
        // Blue accent for a healthy provider; a degraded one turns orange.
        return provider.status == "ok" ? .hermesBlue : .hermesOrange
    }

    // Shortest relative time until any of this provider's windows reset, e.g.
    // "in 6d". Used to surface the expiration in the collapsed provider row.
    private func soonestResetText(_ provider: QuotaProvider) -> String? {
        let dates = provider.windows.compactMap { parsedDate($0.resetsAt) }.filter { $0 > Date() }
        guard let soonest = dates.min() else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: soonest, relativeTo: Date())
    }

    private func providerSummary(_ provider: QuotaProvider, connected: Bool) -> String {
        // Per-provider status when the source is down, rather than repeating the
        // whole connection summary on every row.
        guard connected else { return "Disconnected" }
        guard provider.status == "ok" else {
            return provider.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if provider.provider == "openrouter",
           let account = provider.windows.first(where: { $0.label == "Account credits" }),
           let amount = account.remainingAmount {
            return "\(formattedAmount(amount, currency: account.currency)) available"
        }
        if let minimum = providerMinimum(provider) {
            let base = minimum <= 0 ? "No quota available" : "\(Int(minimum.rounded()))% left"
            if let reset = soonestResetText(provider) {
                return "\(base) · resets \(reset)"
            }
            return base
        }
        return "Quota available"
    }

    // Flattened (source, provider) pairs across all enabled sources.
    private func allEntries() -> [(kind: GatewayKind, connected: Bool, provider: QuotaProvider)] {
        sources.flatMap { source in source.providers.map { (source.kind, source.connected, $0) } }
    }

    private func statusDotsImage() -> NSImage {
        let entries = allEntries()
        let count = max(entries.count, 1)
        let image = NSImage(size: NSSize(width: CGFloat(count * 15 + 2), height: 15))
        image.lockFocus()
        if entries.isEmpty {
            let color = anyConnected ? NSColor.tertiaryLabelColor : NSColor.hermesRed
            color.setStroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 11, height: 11))
            dot.lineWidth = 2
            dot.stroke()
        }
        for (index, entry) in entries.enumerated() {
            let disconnected = !entry.connected || entry.provider.status != "ok"
            let exhausted = !disconnected && providerIsExhausted(entry.provider)
            let dot = NSBezierPath(ovalIn: NSRect(x: CGFloat(index * 15 + 2), y: 2, width: 11, height: 11))
            providerBrandColor(entry.provider.provider).setFill()
            dot.fill()
            if disconnected || exhausted {
                (disconnected ? NSColor.hermesRed : NSColor.hermesYellow).setStroke()
                dot.lineWidth = 2
                dot.stroke()
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func statusTooltip() -> String {
        let entries = allEntries()
        guard !entries.isEmpty else {
            if needsLogin || enabledGateways().isEmpty { return connectionSummary() }
            return refreshing ? "Loading provider quotas" : "Provider quotas unavailable"
        }
        let multi = sources.count > 1
        let providerText = entries.map { e in
            let prefix = multi ? "\(sourceName(e.kind)) " : ""
            return "\(prefix)\(e.provider.label): \(providerSummary(e.provider, connected: e.connected))"
        }.joined(separator: " · ")
        return "\(connectionSummary()) · \(providerText)"
    }

    // One-liner for the header / tooltips summarising the enabled sources.
    private func connectionSummary() -> String {
        let enabled = enabledGateways()
        if enabled.isEmpty { return "Nothing enabled — enable Hermes or Local" }
        if needsLogin {
            let names = enabled.map { sourceName($0) }.joined(separator: " and ")
            return "Sign in to \(names) to see quotas"
        }
        // Per-source status, e.g. "Hermes connected · Local disconnected".
        return enabled.map { kind in
            let connected = sources.first { $0.kind == kind }?.connected ?? false
            return "\(sourceName(kind)) \(connected ? "connected" : "disconnected")"
        }.joined(separator: " · ")
    }

    private func windowView(_ window: QuotaWindow, provider: QuotaProvider) -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 66))
        let value = window.remainingPercent ?? 0
        let hasValue = window.remainingPercent != nil || window.remainingAmount != nil
        // The progress bar carries the PROVIDER's brand colour (red when
        // exhausted); the value TEXT stays high-contrast, warming to orange when
        // the quota is low so it stands out.
        let low = window.remainingPercent.map { $0 <= 15 } ?? false
        let bar = hasValue ? barColor(for: provider, remainingPercent: window.remainingPercent) : NSColor.tertiaryLabelColor
        let valueColor: NSColor = hasValue ? (low ? NSColor.hermesOrange : NSColor.labelColor) : NSColor.tertiaryLabelColor
        view.addSubview(label(window.label, frame: NSRect(x: 28, y: 40, width: 170, height: 18), font: .systemFont(ofSize: 12, weight: .medium)))
        let displayValue: String
        if let amount = window.remainingAmount {
            displayValue = "\(formattedAmount(amount, currency: window.currency)) available"
        } else if let percent = window.remainingPercent {
            displayValue = "\(Int(percent.rounded()))% left"
        } else {
            displayValue = "Unavailable"
        }
        view.addSubview(label(displayValue, frame: NSRect(x: 190, y: 39, width: 150, height: 19), font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold), color: valueColor, alignment: .right))
        if window.remainingPercent != nil {
            let track = NSView(frame: NSRect(x: 28, y: 26, width: 312, height: 6))
            track.wantsLayer = true
            track.layer?.cornerRadius = 3
            track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
            let fillWidth = 312 * max(0, min(100, value)) / 100
            let fill = NSView(frame: NSRect(x: 0, y: 0, width: fillWidth, height: 6))
            fill.wantsLayer = true
            fill.layer?.cornerRadius = 3
            fill.layer?.backgroundColor = bar.cgColor
            track.addSubview(fill)
            view.addSubview(track)
        }
        let subtitle: String
        if let reset = formattedReset(window.resetsAt) {
            subtitle = "Resets \(reset)"
        } else if let detail = window.detail {
            subtitle = detail
        } else if window.remainingAmount != nil {
            subtitle = "Available to spend"
        } else {
            subtitle = "No reset time reported"
        }
        view.addSubview(label(subtitle, frame: NSRect(x: 28, y: 4, width: 312, height: 17), font: .systemFont(ofSize: 10.5), color: .secondaryLabelColor))
        return view
    }

    private func detailView(_ detail: String) -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 25))
        let image = NSImageView(frame: NSRect(x: 28, y: 6, width: 12, height: 12))
        image.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: nil)
        image.contentTintColor = .tertiaryLabelColor
        view.addSubview(image)
        view.addSubview(label(detail, frame: NSRect(x: 47, y: 4, width: 293, height: 17), font: .systemFont(ofSize: 10.5), color: .secondaryLabelColor))
        return view
    }

    private func messageView(_ message: String, color: NSColor = .secondaryLabelColor) -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 30))
        view.addSubview(label(message, frame: NSRect(x: 28, y: 6, width: 312, height: 18), font: .systemFont(ofSize: 11), color: color))
        return view
    }

    private func textActionButton(_ title: String, action: Selector, glowColor: NSColor = .hermesBlue) -> HoverGlowButton {
        let button = HoverGlowButton(title: title, target: self, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.glowColor = glowColor
        return button
    }

    private func iconActionButton(_ image: NSImage?, label: String, action: Selector, glowColor: NSColor = .hermesBlue) -> HoverGlowButton {
        let button = HoverGlowButton(title: "", target: self, action: action)
        button.controlSize = .small
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.glowColor = glowColor
        return button
    }

    // The sources are configured by the user: two enable chips — Hermes (the
    // gateway) and Local (locally-authenticated providers) — both OFF by default.
    // Enable one or BOTH; when both are on, both sources' providers are shown
    // together. No fallback. Disabling a chip drops that source's providers.
    private func gatewayRowView() -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 40))
        let enabled = enabledGateways()
        let icon = NSImageView(frame: NSRect(x: 16, y: 12, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        icon.contentTintColor = enabled.isEmpty ? .tertiaryLabelColor : (anyConnected ? .hermesBlue : .hermesRed)
        view.addSubview(icon)

        view.addSubview(label("Sources", frame: NSRect(x: 42, y: 12, width: 150, height: 16),
                              font: .systemFont(ofSize: 12, weight: .medium)))

        // Per-source enable chips (independent on/off; enable both to see both).
        for (kind, cx) in [(GatewayKind.hermes, CGFloat(210)), (GatewayKind.local, CGFloat(278))] {
            let name = sourceName(kind)
            let on = gatewayEnabled(kind)
            let connected = sources.first { $0.kind == kind }?.connected ?? false
            let glow: NSColor = !on ? .disabledControlTextColor : (connected ? .hermesGreen : .hermesRed)
            let chip = textActionButton(name, action: #selector(toggleGatewayEnabled(_:)), glowColor: glow)
            chip.frame = NSRect(x: cx, y: 7, width: 64, height: 26)
            chip.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
            chip.alphaValue = on ? 1.0 : 0.55
            chip.toolTip = on ? "Disable \(name) (removes its providers)" : "Enable \(name)"
            view.addSubview(chip)
        }
        return view
    }

    // Clickable row (shown when pets are on) that displays the current pet and,
    // on click, scrolls to the next installed pet.
    private func petCycleView() -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 40))
        let pets = PetCatalog.installed()
        let current = PetCatalog.selected()

        let icon = NSImageView(frame: NSRect(x: 16, y: 12, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)
        icon.contentTintColor = .hermesBlue
        view.addSubview(icon)

        var textX: CGFloat = 42
        if let url = current?.thumbnailURL, let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 24, height: 24)
            let thumb = NSImageView(frame: NSRect(x: 42, y: 8, width: 24, height: 24))
            thumb.image = img
            view.addSubview(thumb)
            textX = 72
        }
        view.addSubview(label("Pet: \(current?.displayName ?? "—")",
                              frame: NSRect(x: textX, y: 12, width: 170, height: 16),
                              font: .systemFont(ofSize: 12, weight: .medium)))
        let hint = pets.count > 1 ? "click to switch · \(pets.count)" : "1 installed"
        view.addSubview(label(hint, frame: NSRect(x: 214, y: 12, width: 128, height: 16),
                              font: .systemFont(ofSize: 10), color: .secondaryLabelColor, alignment: .right))

        if pets.count > 1 {
            let button = NSButton(frame: view.bounds)
            button.isBordered = false
            button.title = ""
            button.target = self
            button.action = #selector(cyclePet)
            button.toolTip = "Switch to the next installed pet"
            view.addSubview(button)
        }
        return view
    }

    private func actionBarView() -> NSView {
        let view = menuMaterialView(NSRect(x: 0, y: 0, width: 360, height: 42))
        // Laid out left→right by how often each control is used; Close is pinned
        // far right by convention (least used / destructive).
        var x: CGFloat = 16

        // 1) Refresh quotas — the most frequent action.
        let refresh = iconActionButton(NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil), label: "Refresh quotas", action: #selector(refreshAction), glowColor: .hermesBlue)
        refresh.frame = NSRect(x: x, y: 7, width: 28, height: 28)
        refresh.isEnabled = !refreshing
        view.addSubview(refresh)
        x += 34

        // 2) Open the Hermes app — only when Hermes is enabled and installed.
        if gatewayEnabled(.hermes), let appPath = gatewayAppURL()?.path {
            let appIcon = (NSWorkspace.shared.icon(forFile: appPath).copy() as? NSImage)
            appIcon?.size = NSSize(width: 16, height: 16)
            let openBtn = iconActionButton(appIcon, label: "Open Hermes", action: #selector(openGateway), glowColor: .hermesBlue)
            openBtn.frame = NSRect(x: x, y: 7, width: 28, height: 28)
            view.addSubview(openBtn)
            x += 34
        }

        // 3) Activity pets on/off — a glowing chip matching the other buttons:
        // blue glow when on, dim grey when off.
        let petsIcon = NSImage(systemSymbolName: activityPetsEnabled ? "pawprint.fill" : "pawprint", accessibilityDescription: nil)
        let petsBtn = iconActionButton(petsIcon,
                                       label: activityPetsEnabled ? "Hide activity pets" : "Show activity pets",
                                       action: #selector(togglePetsButton),
                                       glowColor: activityPetsEnabled ? .hermesBlue : .disabledControlTextColor)
        petsBtn.frame = NSRect(x: x, y: 7, width: 28, height: 28)
        view.addSubview(petsBtn)
        x += 34

        // 4) Login / Logout for the Hermes gateway session (Hermes has one;
        // Local providers authenticate via their own CLIs). Logout when the Hermes
        // source is connected, Login when it isn't.
        if gatewayEnabled(.hermes) {
            if hermesSource()?.connected == true {
                let logout = textActionButton("Logout", action: #selector(signOutGateway), glowColor: .hermesRed)
                logout.frame = NSRect(x: x, y: 7, width: 70, height: 28)
                logout.toolTip = "Log out of the Hermes gateway"
                view.addSubview(logout)
                x += 76
            } else {
                let login = textActionButton("Login", action: #selector(signInGateway), glowColor: .hermesGreen)
                login.frame = NSRect(x: x, y: 7, width: 70, height: 28)
                login.toolTip = "Log in to the Hermes gateway"
                view.addSubview(login)
                x += 76
            }
        }

        // 5) Setup — configure the Hermes gateway (opens its Desktop gateway page).
        // Shown whenever Hermes is enabled, so you can point/repair the gateway.
        if gatewayEnabled(.hermes) {
            let setup = iconActionButton(NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil), label: "Set up Hermes gateway", action: #selector(openGatewaySetup), glowColor: .hermesBlue)
            setup.frame = NSRect(x: x, y: 7, width: 28, height: 28)
            setup.toolTip = "Set up the Hermes gateway (opens the Hermes Desktop gateway page)"
            view.addSubview(setup)
            x += 34
        }

        // 6) Close — least used / destructive, pinned far right.
        let close = iconActionButton(NSImage(systemSymbolName: "xmark", accessibilityDescription: nil), label: "Close Provider Quotas", action: #selector(quit), glowColor: .hermesRed)
        close.frame = NSRect(x: 314, y: 7, width: 28, height: 28)
        view.addSubview(close)
        return view
    }

    private func rebuildMenu() {
        // No separators / divider lines — the sections are seamless.
        menu.removeAllItems()
        addView(titleView())
        addView(gatewayRowView())
        if sources.isEmpty {
            let message = enabledGateways().isEmpty
                ? "Enable Hermes or Local above"
                : (refreshing ? "Loading quotas…" : "Quota data unavailable")
            addView(messageView(message))
        } else {
            // One block per enabled source. With more than one source, a small
            // header labels each so the same provider from each is distinct.
            let showHeaders = sources.count > 1
            for source in sources {
                if showHeaders { addView(sourceHeaderView(source)) }
                for provider in source.providers {
                    addView(providerView(provider, kind: source.kind, connected: source.connected))
                    // Collapsed by default; expand to see per-window detail.
                    guard expandedProviders.contains(providerKey(source.kind, provider.provider)) else { continue }
                    if provider.windows.isEmpty {
                        addView(messageView(provider.message ?? provider.status.replacingOccurrences(of: "_", with: " "), color: .hermesOrange))
                    }
                    for window in provider.windows {
                        addView(windowView(window, provider: provider))
                    }
                    for detail in provider.details {
                        addView(detailView(detail))
                    }
                }
            }
        }
        // When pets are on, a clickable row shows the current pet and cycles
        // through the other installed pets on click.
        if activityPetsEnabled, PetCatalog.installed().count > 0 {
            addView(petCycleView())
        }
        addView(actionBarView())
    }

    private func parsedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func formattedRelativeDate(_ value: String?) -> String? {
        guard let date = parsedDate(value) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedReset(_ value: String?) -> String? {
        guard let date = parsedDate(value) else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let relativeText = relative.localizedString(for: date, relativeTo: Date())
        return "\(relativeText) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    @objc private func refreshAction() {
        refresh()
    }

    private func setActivityPets(_ enabled: Bool) {
        activityPetsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "activityPetsEnabled")
        if enabled {
            activityPanel.setPet(PetCatalog.selected())
            syncPetsFromGateway()
            refreshActivityPets()
        } else {
            activityPanel.orderOut(nil)
        }
        rebuildMenu()
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: "selectedPet")
        activityPanel.setPet(PetCatalog.selected())
        rebuildMenu()
    }

    @objc private func cyclePet() {
        let pets = PetCatalog.installed()
        guard pets.count > 1 else { return }
        let currentId = PetCatalog.selected()?.id
        let index = pets.firstIndex { $0.id == currentId } ?? -1
        let next = pets[(index + 1) % pets.count]
        UserDefaults.standard.set(next.id, forKey: "selectedPet")
        activityPanel.setPet(PetCatalog.selected())
        rebuildMenu()
    }

    @objc private func togglePetsButton() {
        setActivityPets(!activityPetsEnabled)
    }

    // Enable / disable a single source. sender.identifier is the kind's rawValue.
    @objc private func toggleGatewayEnabled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = GatewayKind(rawValue: raw) else { return }
        let nowOn = !gatewayEnabled(kind)
        setGatewayEnabled(kind, nowOn)
        if !nowOn {
            // Disabling a source removes ALL of its providers: drop it from the
            // live list AND its cached copy so nothing linked to it lingers.
            sources.removeAll { $0.kind == kind }
            lastProvidersByKind[kind.rawValue] = nil
            UserDefaults.standard.removeObject(forKey: "lastProviderSlugs.\(kind.rawValue)")
            UserDefaults.standard.removeObject(forKey: "lastProviderLabels.\(kind.rawValue)")
        }
        reloadAfterGatewayChange()
    }

    private func reloadAfterGatewayChange() {
        updateStatusItem()
        rebuildMenu()
        refresh()
        refreshActivityPets()
    }

    // Pull pets that were downloaded on the gateway (remote Desktop installs them
    // there, not on this Mac) into the local pets-cache so they appear in the
    // picker. Uses the same authenticated helper as the quota fetch.
    private func syncPetsFromGateway() {
        guard activityPetsEnabled else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let helper = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hermes-desktop-quotas").path
            guard fm.isExecutableFile(atPath: helper) else { return }
            guard let listData = Self.runHelper(helper, ["/api/plugins/provider-quota/pets"]),
                  let obj = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
                  let pets = obj["pets"] as? [[String: Any]] else { return }
            let localIds = Set(PetCatalog.installed().map { $0.id })
            var changed = false
            for pet in pets {
                guard let id = pet["id"] as? String, !localIds.contains(id) else { continue }
                let dir = PetCatalog.cacheDir.appendingPathComponent(id)
                let sheet = dir.appendingPathComponent("spritesheet.webp")
                if fm.fileExists(atPath: sheet.path) { continue }
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                _ = Self.runHelper(helper, ["/api/plugins/provider-quota/pets/\(id)/spritesheet", sheet.path])
                guard let data = try? Data(contentsOf: sheet), !data.isEmpty else {
                    try? fm.removeItem(at: dir); continue
                }
                let meta: [String: Any] = [
                    "id": id,
                    "displayName": pet["displayName"] as? String ?? id,
                    "spritesheetPath": "spritesheet.webp",
                ]
                if let md = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
                    try? md.write(to: dir.appendingPathComponent("pet.json"))
                }
                changed = true
            }
            // Prune cached pets that were deleted on the gateway (we only reach
            // here on a SUCCESSFUL list fetch, so an unreachable gateway never
            // wipes the cache). Local ~/.hermes/pets are left untouched.
            let gatewayIds = Set(pets.compactMap { $0["id"] as? String })
            if let cached = try? fm.contentsOfDirectory(at: PetCatalog.cacheDir, includingPropertiesForKeys: [.isDirectoryKey]) {
                for dir in cached where ((try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
                    && !gatewayIds.contains(dir.lastPathComponent) {
                    try? fm.removeItem(at: dir)
                    changed = true
                }
            }
            if changed {
                DispatchQueue.main.async {
                    self?.activityPanel.setPet(PetCatalog.selected())
                    self?.rebuildMenu()
                }
            }
        }
    }

    private static func runHelper(_ path: String, _ args: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return proc.terminationStatus == 0 ? data : nil
    }

    @objc private func toggleActivityPets(_ sender: NSSwitch) {
        setActivityPets(sender.state == .on)
    }

    @objc private func togglePetsCheckbox(_ sender: NSButton) {
        setActivityPets(sender.state == .on)
    }

    private func refreshActivityPets() {
        guard activityPetsEnabled else {
            activityPanel.orderOut(nil)
            return
        }
        let fallbackProfile = desktopStatus.profile ?? "Hermes"
        // Captured on the main thread. When every enabled source is disconnected
        // (or none is enabled) the pet shows a "not working" state.
        let disconnected = needsLogin
        let enabled = enabledGateways()
        let kindName = enabled.isEmpty ? "No source" : enabled.map { sourceName($0) }.joined(separator: " / ")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fetched = Self.fetchProviderActivity()
            DispatchQueue.main.async {
                guard let self else { return }
                let instances: [ProviderActivityInstance]
                if disconnected {
                    instances = [Self.needsLoginPlaceholder(gateway: kindName)]
                } else if fetched.isEmpty {
                    instances = [Self.sleepingPlaceholder(profile: fallbackProfile)]
                } else {
                    instances = fetched
                }
                self.activityPanel.show(instances)
            }
        }
    }

    // A "not working" pet: the error/struggling animation + red halo + "!" badge
    // (drawPet/drawNukey render status "failed" that way), signalling the active
    // gateway is disconnected and needs a sign-in.
    private static func needsLoginPlaceholder(gateway: String) -> ProviderActivityInstance {
        ProviderActivityInstance(
            completedAt: nil,
            key: "needs-login",
            model: "",
            profile: gateway,
            provider: "provider",
            providerColor: "#cf2d56",
            providerLabel: "",
            sessionId: "",
            startedAt: Date().timeIntervalSince1970,
            status: "failed",
            title: "Sign in"
        )
    }

    private static func sleepingPlaceholder(profile: String) -> ProviderActivityInstance {
        ProviderActivityInstance(
            completedAt: nil,
            key: "\(profile):profile",
            model: "Default model",
            profile: profile,
            provider: "provider",
            providerColor: "#8e8e93",
            providerLabel: "Hermes",
            sessionId: "",
            startedAt: Date().timeIntervalSince1970,
            status: "sleeping",
            title: profile == "Hermes" ? "Open Hermes" : profile
        )
    }

    private static func fetchProviderActivity() -> [ProviderActivityInstance] {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.nousresearch.hermes" || $0.executableURL?.lastPathComponent == "Hermes"
        }
        guard running else { return [] }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hermes/provider-activity.json")
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ProviderActivityPayload.self, from: data),
              Date().timeIntervalSince1970 * 1000 - payload.updatedAt < 12_000 else { return [] }
        let now = Date().timeIntervalSince1970 * 1000
        return payload.instances
            .filter { !$0.completed || now - ($0.completedAt ?? now) < 8_000 }
            .sorted {
                if $0.activityRank != $1.activityRank { return $0.activityRank < $1.activityRank }
                return $0.startedAt < $1.startedAt
            }
    }

    private func refreshDesktopStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let desktop = Self.fetchDesktopStatus()
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktopStatus = desktop
                self.updateStatusItem()
                self.rebuildMenu()
            }
        }
    }

    @objc private func toggleProviderExpanded(_ sender: NSButton) {
        guard let provider = sender.identifier?.rawValue else { return }
        if expandedProviders.contains(provider) {
            expandedProviders.remove(provider)
        } else {
            expandedProviders.insert(provider)
        }
        rebuildMenu()
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        updateStatusItem()
        rebuildMenu()
        let kinds = enabledGateways()   // fetch EVERY enabled source
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let desktop = Self.fetchDesktopStatus()
            let results: [(kind: GatewayKind, result: Result<QuotaPayload, Error>)] =
                kinds.map { ($0, Self.fetchPayload(kind: $0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                self.desktopStatus = desktop
                var built: [SourceQuota] = []
                for (kind, result) in results {
                    switch result {
                    case .success(let payload):
                        built.append(SourceQuota(kind: kind, providers: payload.providers, connected: true, generatedAt: payload.generatedAt))
                        // Remember this source's provider list for a later disconnect.
                        self.lastProvidersByKind[kind.rawValue] = payload.providers.map { ($0.provider, $0.label) }
                        UserDefaults.standard.set(payload.providers.map { $0.provider }, forKey: "lastProviderSlugs.\(kind.rawValue)")
                        UserDefaults.standard.set(payload.providers.map { $0.label }, forKey: "lastProviderLabels.\(kind.rawValue)")
                    case .failure:
                        // Source down → list its known providers as Disconnected.
                        built.append(SourceQuota(kind: kind, providers: self.disconnectedProviders(for: kind), connected: false, generatedAt: nil))
                    }
                }
                self.sources = built
                self.updateStatusItem()
                self.rebuildMenu()
            }
        }
    }

    // Fetch from the user's active source only — no cross-fallback. Hermes goes
    // through the Desktop gateway session; Local reads the providers directly from
    // this Mac's credentials. If that source is unavailable we return a failure so
    // the app shows the pet + a sign-in prompt rather than
    // substituting the other gateway's providers.
    private static func fetchPayload(kind: GatewayKind) -> Result<QuotaPayload, Error> {
        let helper = kind == .local ? "hermes-local-quotas" : "hermes-desktop-quotas"
        let result = runHelper(helper)
        if case .success(let payload) = result, payload.providers.isEmpty {
            let msg = kind == .local ? "Sign in to your local providers to see quotas" : "Sign in to Hermes to see quotas"
            return .failure(NSError(domain: "ProviderQuotaMenuBar", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        return result
    }

    private static func runHelper(_ name: String) -> Result<QuotaPayload, Error> {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let helper = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(name)").path
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            return .failure(NSError(domain: "ProviderQuotaMenuBar", code: 127, userInfo: [NSLocalizedDescriptionKey: "\(name) is not installed"]))
        }
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "exec \"$0\"", helper]
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(name) request failed"
                throw NSError(domain: "ProviderQuotaMenuBar", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
            return .success(try JSONDecoder().decode(QuotaPayload.self, from: data))
        } catch {
            return .failure(error)
        }
    }

    private static func fetchDesktopStatus() -> DesktopStatus {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.nousresearch.hermes" || $0.executableURL?.lastPathComponent == "Hermes"
        }
        let support = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Hermes")
        let connectionURL = support.appendingPathComponent("connection.json")
        let storageURL = support.appendingPathComponent("Local Storage/leveldb")
        let values = readDesktopStorage(at: storageURL)
        let profile = values["hermes-desktop-active-profile-v1"]
        let provider = values["hermes.desktop.composer.provider"]
        let model = values["hermes.desktop.composer.model"]
        guard let data = try? Data(contentsOf: connectionURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DesktopStatus(running: running, mode: "unknown", authMode: "unknown", remoteURL: nil, signedIn: false, reachable: false, profile: profile, provider: provider, model: model)
        }
        let globalMode = root["mode"] as? String ?? "local"
        let profiles = root["profiles"] as? [String: Any]
        let scoped = profile.flatMap { profiles?[$0] as? [String: Any] }
        let block = scoped ?? (root["remote"] as? [String: Any] ?? [:])
        let mode = scoped?["mode"] as? String ?? globalMode
        if mode == "local" {
            return DesktopStatus(running: running, mode: mode, authMode: "local", remoteURL: nil, signedIn: true, reachable: running, profile: profile, provider: provider, model: model)
        }
        let remoteURL = block["url"] as? String
        let authMode = block["authMode"] as? String ?? "token"
        let signedIn: Bool
        if mode == "ssh" {
            signedIn = block["host"] as? String != nil
        } else if authMode == "oauth" {
            signedIn = remoteURL.map { hasNativeOAuthSession(for: $0, support: support) } ?? false
        } else {
            let token = block["token"] as? [String: Any]
            signedIn = !(token?["value"] as? String ?? "").isEmpty
        }
        let reachable = remoteURL.map { gatewayIsReachable($0) } ?? (mode == "ssh" && signedIn)
        return DesktopStatus(running: running, mode: mode, authMode: authMode, remoteURL: remoteURL, signedIn: signedIn, reachable: reachable, profile: profile, provider: provider, model: model)
    }

    private static func readDesktopStorage(at directory: URL) -> [String: String] {
        let keys = ["hermes-desktop-active-profile-v1", "hermes.desktop.composer.provider", "hermes.desktop.composer.model"]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [:] }
        let candidates = files.filter { ["log", "ldb"].contains($0.pathExtension) }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        var result: [String: String] = [:]
        for file in candidates {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
            process.arguments = ["-a", file.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text.components(separatedBy: .newlines)
            for index in lines.indices {
                for key in keys where result[key] == nil && lines[index].hasPrefix(key) {
                    for valueIndex in lines.index(after: index)..<min(lines.count, index + 4) {
                        let value = lines[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            result[key] = value
                            break
                        }
                    }
                }
            }
            if result.count == keys.count { break }
        }
        return result
    }

    private static func hasNativeOAuthSession(for remoteURL: String, support: URL) -> Bool {
        let tokenURL = support.appendingPathComponent("native-oauth-tokens.json")
        guard let data = try? Data(contentsOf: tokenURL),
              let tokens = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let normalized = remoteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return tokens.keys.contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalized }
    }

    private static func gatewayIsReachable(_ remoteURL: String) -> Bool {
        guard var components = URLComponents(string: remoteURL) else { return false }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/api/status" : "/\(path)/api/status"
        guard let url = components.url else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 6
        var reachable = false
        let task = URLSession(configuration: configuration).dataTask(with: url) { _, response, _ in
            if let status = (response as? HTTPURLResponse)?.statusCode {
                reachable = (200..<500).contains(status)
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 7) == .timedOut {
            task.cancel()
        }
        return reachable
    }

    @objc private func openHermes() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Hermes.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    // The Hermes app to launch / sign into ("local" has no app).
    private func gatewayAppURL() -> URL? {
        let hermes = URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Hermes.app")
        return FileManager.default.fileExists(atPath: hermes.path) ? hermes
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.nousresearch.hermes")
    }

    // Sources are configured by the user, per source — nothing is hardcoded or
    // assumed present. Both default OFF; you enable Hermes and/or Local in the
    // menu and the app uses ALL the enabled ones.
    private func gatewayEnabled(_ kind: GatewayKind) -> Bool {
        UserDefaults.standard.bool(forKey: "gatewayEnabled.\(kind.rawValue)")
    }

    private func setGatewayEnabled(_ kind: GatewayKind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "gatewayEnabled.\(kind.rawValue)")
    }

    private func enabledGateways() -> [GatewayKind] {
        [.hermes, .local].filter { gatewayEnabled($0) }
    }

    @objc private func openGateway() {
        guard let url = gatewayAppURL() else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // Route to the Hermes Desktop gateway page to set up / repair the gateway.
    // Prefer the Desktop app's gateway settings deep link (Hermes is the handler
    // for hermes://), falling back to opening the app.
    @objc private func openGatewaySetup() {
        if let url = URL(string: "hermes://settings/gateway"),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            openHermes()
        }
    }

    private func openHermesSession(_ instance: ProviderActivityInstance) {
        guard !instance.sessionId.isEmpty else {
            openHermes()
            return
        }
        var components = URLComponents()
        components.scheme = "hermes"
        components.host = "session"
        components.path = "/\(instance.sessionId)"
        components.queryItems = [URLQueryItem(name: "profile", value: instance.profile)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func gatewayAuthURL(action: String) -> URL? {
        guard let remoteURL = desktopStatus.remoteURL else { return nil }
        var components = URLComponents()
        components.scheme = "hermes"
        components.host = "gateway-auth"
        components.path = "/\(action)"
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL)]
        return components.url
    }

    private func scheduleAuthRefresh() {
        authRefreshTimers.forEach { $0.invalidate() }
        authRefreshTimers = [2, 6, 15, 30, 60].map { delay in
            Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    // Sign in / out of the Hermes gateway via its OAuth deep-links. A local
    // Hermes backend with no remote URL just opens the app to sign in.
    @objc private func signInGateway() {
        guard let url = gatewayAuthURL(action: "login") else {
            openGateway()
            return
        }
        NSWorkspace.shared.open(url)
        scheduleAuthRefresh()
    }

    @objc private func signOutGateway() {
        guard let url = gatewayAuthURL(action: "logout") else {
            openGateway()
            return
        }
        NSWorkspace.shared.open(url)
        sources.removeAll { $0.kind == .hermes }
        updateStatusItem()
        rebuildMenu()
        scheduleAuthRefresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct ProviderQuotaMenuBarApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
