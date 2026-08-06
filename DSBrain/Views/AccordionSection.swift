import SwiftUI

/// Clickable section header that toggles disclosure of content below.
struct AccordionSection<Trailing: View, Content: View>: View {
    let title: String
    var badge: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))

                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            if isExpanded {
                Divider()
                content()
            }
        }
    }
}

extension AccordionSection where Trailing == EmptyView {
    init(
        title: String,
        badge: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.badge = badge
        self._isExpanded = isExpanded
        self.trailing = { EmptyView() }
        self.content = content
    }
}
