import SwiftUI

/// How a list is ordered: by amount (bytes) or by date, ascending or descending.
struct ListOrder: Equatable, RawRepresentable {
    enum Key: String, CaseIterable, Identifiable {
        case amount, date
        var id: String { rawValue }
        var title: String { self == .amount ? "Usage" : "Date" }
    }

    var key: Key
    var ascending: Bool

    init(key: Key = .amount, ascending: Bool = false) {
        self.key = key
        self.ascending = ascending
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".")
        guard parts.count == 2, let key = Key(rawValue: String(parts[0])) else { return nil }
        self.init(key: key, ascending: parts[1] == "asc")
    }

    var rawValue: String { "\(key.rawValue).\(ascending ? "asc" : "desc")" }

    /// Sorts by amount or date; items without a date go last.
    func sorted<T>(_ items: [T], amount: (T) -> Int64, date: (T) -> Date?) -> [T] {
        items.sorted { lhs, rhs in
            switch key {
            case .amount:
                let a = amount(lhs), b = amount(rhs)
                return ascending ? a < b : a > b
            case .date:
                switch (date(lhs), date(rhs)) {
                case let (a?, b?): return ascending ? a < b : a > b
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return amount(lhs) > amount(rhs)
                }
            }
        }
    }
}

/// One row: sort key on the left, direction arrow on the right.
struct ListOrderRow: View {
    @Binding var order: ListOrder

    var body: some View {
        HStack(spacing: 12) {
            Picker("Sort by", selection: $order.key) {
                ForEach(ListOrder.Key.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                order.ascending.toggle()
            } label: {
                Image(systemName: order.ascending ? "arrow.up" : "arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(order.ascending ? "Ascending" : "Descending")
        }
        .sensoryFeedback(.selection, trigger: order)
    }
}

/// While the keyboard is up, the first downward swipe only hides it; the next swipe scrolls
/// (or closes the sheet) as usual.
struct KeyboardFirstSwipe: ViewModifier {
    @Binding var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scrollDisabled(isFocused)
            .interactiveDismissDisabled(isFocused)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { value in
                    if isFocused, value.translation.height > 12 {
                        isFocused = false
                    }
                }
            )
    }
}

extension View {
    func keyboardFirstSwipe(_ isFocused: Binding<Bool>) -> some View {
        modifier(KeyboardFirstSwipe(isFocused: isFocused))
    }
}
