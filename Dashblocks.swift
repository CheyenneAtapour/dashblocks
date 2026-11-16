// Dashblocks: a small floating block that shows what you planned for this time
// of day. Drag it anywhere, resize it from its edges, and double-click it (or
// right-click it) to edit the blocks.
import AppKit
import SwiftUI

// MARK: - Blocks

struct Block: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// Fill colour, as #RRGGBB.
    var color: String
    /// Minutes after midnight. A block may run past midnight (its end before its start).
    var start: Int
    var end: Int

    func contains(_ minute: Int) -> Bool {
        if start == end { return false }
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}

/// The colour shown when no block covers the time.
let freeColor = "#EDEDED"

/// Pastel fills offered to new blocks, in turn.
let palette = ["#B1D6FA", "#FBEBA5", "#C0F0C0", "#F3C4D6", "#D9C8F5", "#FBD3B0", "#B8EDE6"]

final class Store: ObservableObject {
    @Published var blocks: [Block] { didSet { save() } }
    @Published var keepOnTop: Bool { didSet { if persists { UserDefaults.standard.set(keepOnTop, forKey: "keepOnTop") } } }
    /// Whether nothing had been saved yet when the app started.
    let firstRun: Bool
    private let persists: Bool

    /// The blocks from the sketch Dashblocks was drawn from, at sample times.
    static let examples = [
        Block(name: "Meetings", color: "#B1D6FA", start: 9 * 60, end: 11 * 60),
        Block(name: "Heavy Code", color: "#FBEBA5", start: 11 * 60, end: 14 * 60),
        Block(name: "Review", color: "#C0F0C0", start: 14 * 60, end: 16 * 60),
        Block(name: "Finalize PRs", color: "#F3C4D6", start: 16 * 60, end: 18 * 60),
    ]

    /// - Parameter persists: false keeps everything in memory, as the screenshots do.
    init(persists: Bool = true) {
        self.persists = persists
        let saved = persists ? UserDefaults.standard.data(forKey: "blocks") : nil
        firstRun = saved == nil
        blocks = saved.flatMap { try? JSONDecoder().decode([Block].self, from: $0) } ?? Store.examples
        keepOnTop = persists ? UserDefaults.standard.object(forKey: "keepOnTop") as? Bool ?? true : true
        save()
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(blocks) else { return }
        UserDefaults.standard.set(data, forKey: "blocks")
    }

    /// The block covering `date`: where blocks overlap, the one higher in the list.
    func block(at date: Date) -> Block? {
        let minute = minuteOfDay(date)
        return blocks.first { $0.contains(minute) }
    }

    /// The next block to start after `date`, and how many minutes until it does.
    func next(after date: Date) -> (block: Block, minutes: Int)? {
        let minute = minuteOfDay(date)
        return blocks.filter { $0.start != $0.end }
            .map { ($0, ($0.start - minute + 1440) % 1440) }
            .filter { $0.1 > 0 }
            .min { $0.1 < $1.1 }
    }

    /// The line under the block's name: when it ends, or, between blocks, what is next.
    func caption(at date: Date) -> String {
        if let block = block(at: date) { return "until \(clockTime(block.end))" }
        if let next = next(after: date) { return "next: \(next.block.name) at \(clockTime(next.block.start))" }
        return "nothing planned"
    }
}

func minuteOfDay(_ date: Date) -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

/// `minute` (after midnight) as a time of day in your locale's style, e.g. 2:00 PM.
func clockTime(_ minute: Int) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: dateToday(at: minute))
}

func dateToday(at minute: Int) -> Date {
    Calendar.current.date(bySettingHour: minute / 60 % 24, minute: minute % 60, second: 0, of: Date()) ?? Date()
}

extension Color {
    /// A colour from #RRGGBB.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xEDEDED
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// The colour as #RRGGBB.
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

// MARK: - The widget

let ink = Color(white: 0.12)
let hand = "Chalkboard SE"

/// A rounded box with a doubled, slightly crooked outline, as if drawn by hand.
struct SketchBox: View {
    let fill: Color

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) * 0.16
            ZStack {
                RoundedRectangle(cornerRadius: radius).fill(fill)
                RoundedRectangle(cornerRadius: radius).stroke(ink, lineWidth: 2.6)
                RoundedRectangle(cornerRadius: radius * 1.06)
                    .stroke(ink.opacity(0.7), lineWidth: 1.3)
                    .rotationEffect(.degrees(0.4))
                    .offset(x: 0.9, y: -0.7)
            }
        }
    }
}

struct WidgetView: View {
    @ObservedObject var store: Store
    /// A fixed time to show, for the screenshots; nil for now.
    var at: Date?

    var body: some View {
        if let at {
            face(at)
        } else {
            TimelineView(.periodic(from: .now, by: 10)) { context in face(context.date) }
        }
    }

    func face(_ date: Date) -> some View {
        let block = store.block(at: date)
        return GeometryReader { geometry in
            ZStack {
                SketchBox(fill: Color(hex: block?.color ?? freeColor))
                VStack(spacing: geometry.size.height * 0.03) {
                    Text(block?.name ?? "Free")
                        .font(.custom(hand, size: 200).weight(.bold))
                        .minimumScaleFactor(0.02)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxHeight: geometry.size.height * 0.36)
                    Text(store.caption(at: date))
                        .font(.custom(hand, size: 200))
                        .minimumScaleFactor(0.02)
                        .lineLimit(1)
                        .opacity(0.6)
                        .frame(maxHeight: geometry.size.height * 0.12)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, geometry.size.width * 0.1)
            }
            .padding(5)
        }
    }
}

/// Lies over the widget and turns the mouse into moving and resizing it: drag
/// anywhere to move it, drag an edge or corner to resize it, double-click to
/// edit the blocks, right-click for the menu.
final class Handle: NSView {
    var onDoubleClick: () -> Void = {}
    var menuForWidget: () -> NSMenu = { NSMenu() }
    static let edge: CGFloat = 10
    static let smallest = NSSize(width: 110, height: 70)
    private var resizing: (left: Bool, right: Bool, top: Bool, bottom: Bool)?
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// Which edges `point` is near; none in the middle.
    func edges(at point: NSPoint) -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
        let e = Handle.edge
        return (point.x < e, point.x > bounds.width - e, point.y > bounds.height - e, point.y < e)
    }

    override func mouseMoved(with event: NSEvent) {
        let near = edges(at: convert(event.locationInWindow, from: nil))
        if (near.left || near.right) && (near.top || near.bottom) {
            NSCursor.crosshair.set()
        } else if near.left || near.right {
            NSCursor.resizeLeftRight.set()
        } else if near.top || near.bottom {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.openHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick(); return }
        let near = edges(at: convert(event.locationInWindow, from: nil))
        guard near.left || near.right || near.top || near.bottom, let window else {
            NSCursor.closedHand.set()
            window?.performDrag(with: event)
            NSCursor.openHand.set()
            return
        }
        resizing = near
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resizing, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        let small = Handle.smallest
        var frame = startFrame
        if resizing.right { frame.size.width = max(small.width, startFrame.width + dx) }
        if resizing.left {
            frame.size.width = max(small.width, startFrame.width - dx)
            frame.origin.x = startFrame.maxX - frame.width
        }
        if resizing.top { frame.size.height = max(small.height, startFrame.height + dy) }
        if resizing.bottom {
            frame.size.height = max(small.height, startFrame.height - dy)
            frame.origin.y = startFrame.maxY - frame.height
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) { resizing = nil }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuForWidget(), with: event, for: self)
    }
}

// MARK: - Editing the blocks

struct ConfigView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time blocks").font(.title2.bold())
            Text("The widget shows the block covering the current time. Where blocks overlap, the one higher in the list wins; drag rows to reorder them. A block can run past midnight.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(store.blocks) { block in
                    BlockRow(block: binding(for: block.id)) {
                        store.blocks.removeAll { $0.id == block.id }
                    }
                }
                .onMove { store.blocks.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Button { add() } label: { Label("Add block", systemImage: "plus") }
                Button("Sort by start time") { store.blocks.sort { $0.start < $1.start } }
                Spacer()
                Toggle("Keep on top", isOn: $store.keepOnTop)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 380)
    }

    /// A binding to the block with `id` that survives the block being deleted.
    func binding(for id: UUID) -> Binding<Block> {
        Binding(
            get: { store.blocks.first { $0.id == id } ?? Block(name: "", color: freeColor, start: 0, end: 0) },
            set: { new in
                if let i = store.blocks.firstIndex(where: { $0.id == id }) { store.blocks[i] = new }
            })
    }

    /// Adds an hour-long block after the last one ends.
    func add() {
        let start = store.blocks.map(\.end).max() ?? 9 * 60
        let color = palette[store.blocks.count % palette.count]
        store.blocks.append(Block(name: "New block", color: color, start: start % 1440, end: (start + 60) % 1440))
    }
}

struct BlockRow: View {
    @Binding var block: Block
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("Colour", selection: Binding(get: { Color(hex: block.color) }, set: { block.color = $0.hex }),
                        supportsOpacity: false)
                .labelsHidden()
            TextField("Name", text: $block.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150)
            DatePicker("From", selection: time(\.start), displayedComponents: .hourAndMinute)
                .fixedSize()
            DatePicker("to", selection: time(\.end), displayedComponents: .hourAndMinute)
                .fixedSize()
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this block")
        }
        .padding(.vertical, 2)
    }

    /// A start or end time, as today's date at that time for the picker.
    func time(_ key: WritableKeyPath<Block, Int>) -> Binding<Date> {
        Binding(get: { dateToday(at: block[keyPath: key]) }, set: { block[keyPath: key] = minuteOfDay($0) })
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var widget: NSWindow!
    var config: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        // On every Space, and over full-screen apps.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = store.keepOnTop ? .floating : .normal

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        let face = NSHostingView(rootView: WidgetView(store: store))
        face.sizingOptions = []
        face.frame = container.bounds
        face.autoresizingMask = [.width, .height]
        let handle = Handle(frame: container.bounds)
        handle.autoresizingMask = [.width, .height]
        handle.onDoubleClick = { [weak self] in self?.openConfig() }
        handle.menuForWidget = { [weak self] in self?.menu() ?? NSMenu() }
        container.addSubview(face)
        container.addSubview(handle)
        window.contentView = container

        // Where you last left it; the first time, near the top-right corner of the screen.
        if !window.setFrameUsingName("DashblocksWidget"), let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: screen.maxX - 280, y: screen.maxY - 200))
        }
        window.setFrameAutosaveName("DashblocksWidget")
        window.orderFrontRegardless()
        widget = window

        if store.firstRun { openConfig() }
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit Blocks…", action: #selector(openConfig), keyEquivalent: ",").target = self
        let onTop = menu.addItem(withTitle: "Keep on Top", action: #selector(toggleOnTop), keyEquivalent: "")
        onTop.target = self
        onTop.state = store.keepOnTop ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dashblocks", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc func toggleOnTop() {
        store.keepOnTop.toggle()
        widget.level = store.keepOnTop ? .floating : .normal
    }

    @objc func openConfig() {
        if config == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Dashblocks"
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: ConfigView(store: store))
            host.sizingOptions = []
            window.contentView = host
            window.contentMinSize = NSSize(width: 620, height: 380)
            window.center()
            window.setFrameAutosaveName("DashblocksConfig")
            config = window
        }
        NSApp.activate(ignoringOtherApps: true)
        config?.makeKeyAndOrderFront(nil)
        // The Keep on Top toggle may have changed from the settings.
        widget.level = store.keepOnTop ? .floating : .normal
    }
}

// MARK: - Screenshots

/// `Dashblocks --screenshots <dir>` draws the widget and the settings offscreen
/// into PNGs for the README, with the example blocks. No screen capture is involved.
enum Screenshots {
    /// Draws `view` in an offscreen window (titled `title`, or borderless and
    /// transparent if nil) and saves it as a PNG.
    static func save<V: View>(_ view: V, title: String?, size: NSSize, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: title == nil ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        if let title { window.title = title } else {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        // The frame view includes the title bar.
        let frame = window.contentView!.superview!
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(persists: false)
        save(WidgetView(store: store, at: dateToday(at: 12 * 60 + 30)), title: nil, size: NSSize(width: 300, height: 200),
             to: dir.appendingPathComponent("widget.png"))
        // One widget per block, plus the free time between them.
        let times = [10 * 60, 12 * 60 + 30, 15 * 60, 17 * 60, 19 * 60]
        let row = HStack(spacing: 18) {
            ForEach(times, id: \.self) { minute in
                VStack(spacing: 6) {
                    WidgetView(store: store, at: dateToday(at: minute)).frame(width: 190, height: 130)
                    Text(clockTime(minute)).font(.custom(hand, size: 15)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        save(row, title: nil, size: NSSize(width: 1090, height: 210), to: dir.appendingPathComponent("through-the-day.png"))
        save(ConfigView(store: store), title: "Dashblocks", size: NSSize(width: 680, height: 420),
             to: dir.appendingPathComponent("settings.png"))
    }
}

let app = NSApplication.shared
if let flag = CommandLine.arguments.firstIndex(of: "--screenshots"), CommandLine.arguments.count > flag + 1 {
    app.setActivationPolicy(.accessory)
    Screenshots.run(into: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
