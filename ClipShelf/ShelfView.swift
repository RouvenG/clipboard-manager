import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @Bindable var model: ShelfViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            header
            ZStack(alignment: .top) {
                cards
                if model.mode != .browse {
                    MenuOverlay(model: model)
                }
            }
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .onAppear { searchFocused = true }
        .onChange(of: model.store.revision) { model.reload() }
        .onChange(of: model.mode) { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(model.tabs, id: \.self) { tab in
                    TabDropTarget(model: model, tab: tab)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: model.mode == .browse ? "magnifyingglass" : "wand.and.stars")
                    .foregroundStyle(.secondary)
                TextField(model.placeholder, text: $model.activeQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 360)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(ClipFilter.allCases) { filter in
                    Button(filter.title) { model.filter = filter }
                        .buttonStyle(TabButtonStyle(isSelected: model.filter == filter))
                        .help("\(filter.title) (\(filter.shortcut))")
                }
            }
        }
    }

    private var cards: some View {
        let items = model.visibleItems
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item, index: index, isSelected: index == model.selectedIndex)
                            .id(item.id)
                            .onTapGesture(count: 2) { model.onPaste(item, false) }
                            .onTapGesture { model.selectedIndex = index }
                            .onDrag {
                                model.selectedIndex = index
                                model.draggedItemID = item.id
                                return DragProvider.provider(for: item)
                            }
                            .contextMenu { contextMenu(for: item, index: index) }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .overlay {
                if items.isEmpty { emptyState }
            }
            .onChange(of: model.selectedIndex) {
                if let item = model.selectedItem {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(item.id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem, index: Int) -> some View {
        Button("Paste") { model.onPaste(item, false) }
        Button("Paste as Plain Text") { model.onPaste(item, true) }
        Button("Copy") { model.onCopy(item) }
        Divider()
        Button("Transform…") { model.selectedIndex = index; model.openTransforms() }
        Button("Pinboards…") { model.selectedIndex = index; model.openPinboardPicker() }
        Divider()
        Button("Delete", role: .destructive) { model.store.delete(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clipboard").font(.title)
            Text(model.query.isEmpty ? "Nothing here yet. Copy something." : "No matches for \"\(model.query)\"")
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let status = model.status {
                Label(status, systemImage: model.isRunningScript ? "hourglass" : "info.circle")
                    .foregroundStyle(.primary)
            }
            Spacer()
            Group {
                Text("↩ paste")
                Text("⇧↩ plain")
                Text("⌘1-9 quick")
                Text("⌘K transform")
                Text("⌘P pin")
                Text("drag to board, ⌥ copies")
                Text("⇥ boards")
                Text("⌘⌫ delete")
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

/// A board tab that also accepts cards dragged from the shelf.
private struct TabDropTarget: View {
    let model: ShelfViewModel
    let tab: ShelfTab
    @State private var isTargeted = false

    var body: some View {
        Button(model.title(of: tab)) { model.tab = tab }
            .buttonStyle(TabButtonStyle(isSelected: model.tab == tab, isDropTarget: isTargeted))
            .onDrop(of: [.item], isTargeted: $isTargeted) { _ in
                guard model.draggedItemID != nil else { return false }
                let copy = NSEvent.modifierFlags.contains(.option)
                return model.dropDraggedItem(on: tab, copy: copy)
            }
            .help(tab == .history ? "Drop a card here to take it off its pinboard"
                                  : "Drop a card here to move it, hold ⌥ to keep it in the current board too")
    }
}

enum DragProvider {
    /// Gives other apps the clip's content, so cards can also be dragged out of the shelf.
    static func provider(for item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .image:
            if let data = item.imageData {
                return NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
            }
        case .file:
            if let url = item.fileURLs.first, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
        case .link:
            if let text = item.text, let url = URL(string: text) {
                return NSItemProvider(object: url as NSURL)
            }
        case .text, .richText:
            break
        }
        return NSItemProvider(object: (item.text ?? "") as NSString)
    }
}

private struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool
    var isDropTarget = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected || isDropTarget ? AnyShapeStyle(.tint.opacity(isDropTarget ? 0.5 : 0.25)) : AnyShapeStyle(.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 2 : 0))
            .scaleEffect(isDropTarget ? 1.08 : 1)
            .animation(.easeOut(duration: 0.1), value: isDropTarget)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

private struct MenuOverlay: View {
    @Bindable var model: ShelfViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.mode == .transforms {
                let options = model.visibleTransforms
                if options.isEmpty {
                    Text("No transform matches").foregroundStyle(.secondary).padding(8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, transform in
                                row(title: transform.name, detail: transform.detail,
                                    icon: transform.id.hasPrefix("script.") ? "curlybraces" : "wand.and.stars",
                                    selected: index == model.menuIndex)
                                    .id(index)
                                    .onTapGesture {
                                        if let item = model.selectedItem { model.apply(transform, to: item) }
                                    }
                            }
                        }
                    }
                    .onChange(of: model.menuIndex) { proxy.scrollTo(model.menuIndex) }
                }
            } else {
                let options = model.visibleBoards
                let item = model.selectedItem
                ForEach(Array(options.enumerated()), id: \.element.id) { index, board in
                    let contains = item.map { item in board.items.contains { $0.id == item.id } } ?? false
                    row(title: board.name, detail: contains ? "Pinned, Return removes" : "\(board.items.count) items",
                        icon: contains ? "pin.fill" : "pin", selected: index == model.menuIndex)
                        .onTapGesture { model.choosePinboard(at: index) }
                }
                let newName = model.menuQuery.trimmingCharacters(in: .whitespaces)
                row(title: newName.isEmpty ? "New pinboard: type a name" : "New pinboard \"\(newName)\"",
                    detail: "", icon: "plus", selected: model.menuIndex == options.count)
                    .onTapGesture { model.choosePinboard(at: options.count) }
            }
        }
        .padding(8)
        .frame(width: 420)
        .frame(maxHeight: 230)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12)
    }

    private func row(title: String, detail: String, icon: String, selected: Bool) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
