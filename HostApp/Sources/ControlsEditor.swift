// Editor for the on-screen touch controls. It saves to UserDefaults as you edit (debounced); the in-game overlay (glfw_ios.m)
// reads "zom.touchLayout" when the game starts.
import SwiftUI
import UIKit

// MARK: - Touch layout model

struct TouchItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case stick, aimstick, key, mouse, keyboard, hide, mode }
    var id: String
    var kind: Kind
    var label: String
    var code: Int            // GLFW key code, or mouse button (0 left, 1 right, 2 middle)
    var x: Double            // centre, as a fraction of the screen
    var y: Double
    var size: Double         // points
    var locked: Bool { kind == .hide || kind == .mode }
    var isStick: Bool { kind == .stick || kind == .aimstick }   // HIDE and PAD/TCH can't be removed, or you could lose the controls
}

struct TouchLayout: Codable, Equatable {
    var opacity: Double = 1
    var items: [TouchItem]
}

enum TouchLayoutStore {
    static let key = "zom.touchLayout"

    static func load() -> TouchLayout {
        if let s = UserDefaults.standard.string(forKey: key), let d = s.data(using: .utf8),
           let l = try? JSONDecoder().decode(TouchLayout.self, from: d), !l.items.isEmpty { return l }
        return defaultLayout
    }
    static func save(_ l: TouchLayout) {
        if let d = try? JSONEncoder().encode(l), let s = String(data: d, encoding: .utf8) { UserDefaults.standard.set(s, forKey: key) }
    }
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    static let migratedKey = "zom.aimstickMigrated"

    /// The aiming stick: a second joystick on the right that aims the character (holds the aim button and points the cursor around the player).
    static var aimStickItem: TouchItem {
        TouchItem(id: "aimstick", kind: .aimstick, label: "", code: 0, x: (956.0 - 20 - 75) / 956.0, y: (440.0 - 14 - 75) / 440.0, size: 130)
    }

    /// The default layout (positions worked out for a 956x440 pt screen).
    static var defaultLayout: TouchLayout {
        let W = 956.0, H = 440.0, L = 20.0, R = 20.0, B = 14.0, T = 10.0
        func item(_ id: String, _ kind: TouchItem.Kind, _ label: String, _ code: Int, _ px: Double, _ py: Double, _ size: Double) -> TouchItem {
            TouchItem(id: id, kind: kind, label: label, code: code, x: px / W, y: py / H, size: size)
        }
        let shift = 150.0       // the action buttons move left to leave the right edge to the aiming stick
        return TouchLayout(items: [
            item("stick", .stick, "", 0, L + 70, H - B - 70, 130),
            aimStickItem,
            item("atk", .mouse, "ATK", 0, W - R - 40 - shift, H - B - 44, 62),
            item("aim", .mouse, "AIM", 1, W - R - 112 - shift, H - B - 36, 62),
            item("e", .key, "E", 69, W - R - 40 - shift, H - B - 116, 62),
            item("run", .key, "RUN", 340, W - R - 112 - shift, H - B - 108, 62),
            item("spc", .key, "SPC", 32, W - R - 184 - shift, H - B - 44, 62),
            item("ctrl", .key, "CTRL", 341, W - R - 184 - shift, H - B - 116, 62),
            item("tab", .key, "TAB", 258, W - R - 28 - 3 * 52, T + 26, 44),
            item("esc", .key, "ESC", 256, W - R - 28 - 2 * 52, T + 26, 44),
            item("kb", .keyboard, "KB", 0, W - R - 28 - 52, T + 26, 44),
            item("hide", .hide, "HIDE", 0, W - R - 28, T + 26, 44),
            item("mode", .mode, "PAD", 0, W - R - 28 - 4 * 52, T + 26, 44),
        ])
    }

    /// Run when the launcher opens, so the game always has a saved layout to read: the default if there is none, and for a layout saved before the
    /// aiming stick existed, the stick is added once (move it or delete it in the editor).
    static func ensureSaved() {
        let d = UserDefaults.standard
        if d.string(forKey: key) == nil { save(defaultLayout); d.set(true, forKey: migratedKey); return }
        guard !d.bool(forKey: migratedKey) else { return }
        var l = load()
        if !l.items.contains(where: { $0.kind == .aimstick }) { l.items.append(aimStickItem); save(l) }
        d.set(true, forKey: migratedKey)
    }
}

// MARK: - Key catalogue

enum KeyCatalog {
    static let letters: [(String, Int)] = (0..<26).map { (String(UnicodeScalar(65 + $0)!), 65 + $0) }
    static let numbers: [(String, Int)] = (0..<10).map { (String($0), 48 + $0) }
    static let modifiers: [(String, Int)] = [("Shift", 340), ("Ctrl", 341), ("Alt", 342)]
    static let special: [(String, Int)] = [("Space", 32), ("Tab", 258), ("Esc", 256), ("Enter", 257), ("Backspace", 259),
                                           ("Up", 265), ("Down", 264), ("Left", 263), ("Right", 262)]
    static let function: [(String, Int)] = (1...12).map { ("F\($0)", 289 + $0) }
    static let punctuation: [(String, Int)] = [(",", 44), (".", 46), ("/", 47), (";", 59), ("'", 39), ("[", 91), ("]", 93), ("-", 45), ("=", 61), ("`", 96)]
    static let groups: [(String, [(String, Int)])] = [("Letters", letters), ("Numbers", numbers), ("Modifiers", modifiers),
                                                      ("Special", special), ("Function", function), ("Punctuation", punctuation)]
    static let mouse: [(String, Int)] = [("Left click", 0), ("Right click", 1), ("Middle click", 2)]

    static func name(key code: Int) -> String {
        for (_, list) in groups { if let n = list.first(where: { $0.1 == code }) { return n.0 } }
        return "Key \(code)"
    }
    /// Short text for a button face.
    static func shortLabel(key code: Int) -> String {
        let n = name(key: code)
        let map = ["Space": "SPC", "Shift": "SHF", "Backspace": "BKSP", "Enter": "ENT", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→"]
        return (map[n] ?? n).uppercased()
    }
}

// MARK: - Touch layout editor

struct TouchLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout = TouchLayoutStore.load()
    @State private var selected: String?
    @State private var panelOffset = CGSize.zero
    @State private var panelDrag = CGSize.zero
    @State private var saveItem: DispatchWorkItem?

    private var selectedIndex: Int? { layout.items.firstIndex { $0.id == selected } }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                Color(white: 0.055).ignoresSafeArea()
                // the screen as the game will see it
                RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1).padding(6).ignoresSafeArea()
                Text("Drag controls where you want them. Tap one to edit.").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.35))
                    .position(x: W / 2, y: H - 14)

                ForEach($layout.items) { $item in
                    // gesture goes on before .position, so each control's touch area is the control itself, not the whole screen
                    Chip(item: $item, selected: selected == item.id, opacity: layout.opacity)
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas")).onChanged { v in
                            if selected != item.id { selected = item.id }
                            let r = item.size / 2
                            item.x = min(max(v.location.x, r), W - r) / W
                            item.y = min(max(v.location.y, r), H - r) / H
                        })
                        .position(x: item.x * W, y: item.y * H)
                }
                panel
                    .frame(width: min(360, W * 0.42))
                    .offset(x: panelOffset.width + panelDrag.width, y: panelOffset.height + panelDrag.height)
            }
            .coordinateSpace(name: "canvas")
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onChange(of: layout) { _, l in      // debounced: encoding on every frame of a drag made the editor sluggish
            saveItem?.cancel()
            let work = DispatchWorkItem { TouchLayoutStore.save(l) }
            saveItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        .onDisappear { saveItem?.cancel(); TouchLayoutStore.save(layout) }
    }

    // MARK: panel

    private var panel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Touch Controls").font(.system(size: 15, weight: .bold))
                Spacer()
                Image(systemName: "line.3.horizontal").foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { panelDrag = $0.translation }.onEnded { v in
                panelOffset.width += v.translation.width; panelOffset.height += v.translation.height; panelDrag = .zero
            })

            HStack(spacing: 8) {
                Menu {
                    Button("Key button") { add(.key, label: "E", code: 69) }
                    Button("Mouse button") { add(.mouse, label: "CLK", code: 0) }
                    if !layout.items.contains(where: { $0.kind == .stick }) { Button("Joystick") { add(.stick, label: "", code: 0, size: 130) } }
                    if !layout.items.contains(where: { $0.kind == .aimstick }) { Button("Aim joystick") { add(.aimstick, label: "", code: 0, size: 130) } }
                    if !layout.items.contains(where: { $0.kind == .keyboard }) { Button("Keyboard toggle") { add(.keyboard, label: "KB", code: 0, size: 44) } }
                } label: { pill("Add", system: "plus") }
                Button { layout = TouchLayoutStore.defaultLayout; TouchLayoutStore.save(layout); selected = nil } label: { pill("Reset", system: "arrow.counterclockwise") }
                Button { dismiss() } label: { pill("Done", system: "checkmark", filled: true) }
            }

            HStack {
                Text("Opacity").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Slider(value: $layout.opacity, in: 0.3...1).tint(.white)
            }

            if let i = selectedIndex { inspector(i) }
        }
        .padding(14)
        .background(Color(white: 0.11).opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private func inspector(_ i: Int) -> some View {
        let item = layout.items[i]
        Divider().overlay(Color.white.opacity(0.12))
        VStack(alignment: .leading, spacing: 8) {
            Text(item.kind == .stick ? "Joystick" : item.kind == .aimstick ? "Aim joystick" : item.label.isEmpty ? "Control" : item.label).font(.system(size: 13, weight: .semibold))
            if item.kind == .key || item.kind == .mouse {
                HStack {
                    Text("Sends").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Menu {
                        ForEach(KeyCatalog.groups, id: \.0) { group in
                            Menu(group.0) {
                                ForEach(group.1, id: \.1) { entry in
                                    Button(entry.0) { setOutput(i, kind: .key, code: entry.1, label: KeyCatalog.shortLabel(key: entry.1)) }
                                }
                            }
                        }
                        Menu("Mouse") {
                            ForEach(KeyCatalog.mouse, id: \.1) { entry in
                                Button(entry.0) { setOutput(i, kind: .mouse, code: entry.1, label: entry.0.prefix(1).uppercased() + "CLK") }
                            }
                        }
                    } label: {
                        Text(item.kind == .mouse ? KeyCatalog.mouse.first { $0.1 == item.code }?.0 ?? "Mouse" : KeyCatalog.name(key: item.code))
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 28)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                }
                HStack {
                    Text("Label").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    TextField("Label", text: Binding(get: { layout.items[i].label }, set: { layout.items[i].label = String($0.prefix(5)).uppercased() }))
                        .multilineTextAlignment(.center).font(.system(size: 13, weight: .semibold)).frame(width: 80, height: 28)
                        .background(Color.white.opacity(0.12), in: Capsule()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
            }
            HStack {
                Text("Size").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Slider(value: Binding(get: { layout.items[i].size }, set: { layout.items[i].size = $0 }), in: (item.isStick ? 90.0 : 36.0)...(item.isStick ? 200.0 : 110.0)).tint(.white)
            }
            if !item.locked {
                Button(role: .destructive) { layout.items.remove(at: i); selected = nil } label: {
                    Text("Delete control").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 30)
                        .background(Color.red.opacity(0.18), in: Capsule()).foregroundStyle(Color.red)
                }.buttonStyle(.plain)
            }
        }
    }

    private func pill(_ title: String, system: String, filled: Bool = false) -> some View {
        Label(title, systemImage: system).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 32)
            .background(filled ? Color.white : Color.white.opacity(0.12), in: Capsule()).foregroundStyle(filled ? Color.black : .white)
    }

    private func setOutput(_ i: Int, kind: TouchItem.Kind, code: Int, label: String) {
        layout.items[i].kind = kind; layout.items[i].code = code; layout.items[i].label = String(label.prefix(5))
    }

    private func add(_ kind: TouchItem.Kind, label: String, code: Int, size: Double = 62) {
        let item = TouchItem(id: UUID().uuidString, kind: kind, label: label, code: code, x: 0.5, y: 0.78, size: size)
        layout.items.append(item); selected = item.id
    }
}

/// How one control looks in the editor; mirrors the in-game overlay.
private struct Chip: View {
    @Binding var item: TouchItem
    let selected: Bool
    let opacity: Double
    var body: some View {
        ZStack {
            Circle().fill(item.kind == .aimstick ? Color(red: 0.35, green: 0.08, blue: 0.06).opacity(0.45) : Color(white: 0.1).opacity(0.45))
            Circle().stroke(item.kind == .aimstick ? Color(red: 1, green: 0.55, blue: 0.5).opacity(0.7) : Color.white.opacity(0.6), lineWidth: 2)
            if item.isStick {
                Circle().fill(item.kind == .aimstick ? Color(red: 1, green: 0.6, blue: 0.55).opacity(0.6) : Color.white.opacity(0.55)).frame(width: item.size * 0.38, height: item.size * 0.38)
                if item.kind == .aimstick { Image(systemName: "scope").font(.system(size: item.size * 0.2)).foregroundStyle(.white.opacity(0.8)) }
            } else {
                Text(item.label).font(.system(size: item.size > 50 ? 15 : 12, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .frame(width: item.size, height: item.size)
        .opacity(opacity)
        .overlay(Circle().stroke(Color.white, lineWidth: selected ? 3 : 0).padding(-5))
    }
}

#Preview("Touch editor", traits: .fixedLayout(width: 956, height: 440)) { TouchLayoutEditor() }
