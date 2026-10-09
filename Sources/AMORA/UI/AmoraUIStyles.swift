import SwiftUI

/// Reusable tactile button style providing gentle scale and opacity feedback on press.
public struct AmoraPressableButtonStyle: ButtonStyle {
    public var pressScale: CGFloat
    public var pressOpacity: Double

    public init(pressScale: CGFloat = 0.95, pressOpacity: Double = 0.8) {
        self.pressScale = pressScale
        self.pressOpacity = pressOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressOpacity : 1.0)
            .scaleEffect(configuration.isPressed ? pressScale : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Circular header control button with accessible touch target (28x28 min),
/// subtle hover state, and tactile press animation.
public struct AmoraHeaderCircleButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 26, minHeight: 26)
            .padding(4)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : (isHovered ? 0.15 : 0.08)))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.04 : 1.0))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Pill-shaped button style for actions, chips, and dialog buttons.
public struct AmoraPillButtonStyle: ButtonStyle {
    public var backgroundFill: Color
    public var foregroundColor: Color
    @State private var isHovered = false

    public init(backgroundFill: Color = Color.white.opacity(0.1), foregroundColor: Color = .white) {
        self.backgroundFill = backgroundFill
        self.foregroundColor = foregroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(backgroundFill.opacity(configuration.isPressed ? 0.7 : (isHovered ? 1.15 : 1.0)))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == AmoraPressableButtonStyle {
    public static var amoraPressable: AmoraPressableButtonStyle { AmoraPressableButtonStyle() }
    public static func amoraPressable(scale: CGFloat = 0.95, opacity: Double = 0.8) -> AmoraPressableButtonStyle {
        AmoraPressableButtonStyle(pressScale: scale, pressOpacity: opacity)
    }
}

extension ButtonStyle where Self == AmoraHeaderCircleButtonStyle {
    public static var amoraHeaderCircle: AmoraHeaderCircleButtonStyle { AmoraHeaderCircleButtonStyle() }
}

extension ButtonStyle where Self == AmoraPillButtonStyle {
    public static var amoraPill: AmoraPillButtonStyle { AmoraPillButtonStyle() }
    public static func amoraPill(fill: Color, foreground: Color = .white) -> AmoraPillButtonStyle {
        AmoraPillButtonStyle(backgroundFill: fill, foregroundColor: foreground)
    }
}

/// Standardized empty state view preventing plain unstyled empty text.
public struct AmoraEmptyStateView: View {
    public let iconName: String
    public let title: String
    public let subtitle: String

    public init(iconName: String, title: String, subtitle: String) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.32))

            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            Text(subtitle)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}

/// Status indicator that combines an SF Symbol and text label to avoid color-only status.
public struct AmoraAccessibleStatusBadge: View {
    public let text: String
    public let systemImage: String
    public let tintColor: Color

    public init(text: String, systemImage: String, tintColor: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tintColor)
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(tintColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tintColor.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }
}
