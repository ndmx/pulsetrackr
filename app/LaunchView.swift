import SwiftUI

struct OpeningSplashView: View {
    @State private var pulseOpacity: CGFloat = 0.42
    @State private var pulseScale: CGFloat = 0.92
    @State private var logoOpacity: CGFloat = 0
    @State private var logoScale: CGFloat = 0.86
    @State private var wordmarkOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .stroke(DS.Color.accent.opacity(0.20 - Double(index) * 0.04), lineWidth: 1.2)
                            .frame(width: 88 + CGFloat(index * 46), height: 88 + CGFloat(index * 46))
                            .scaleEffect(pulseScale + CGFloat(index) * 0.06)
                            .opacity(pulseOpacity)
                    }

                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 86, height: 86)
                        .background(DS.Color.accent.opacity(0.13), in: Circle())
                        .overlay(Circle().stroke(DS.Color.accent.opacity(0.30), lineWidth: 1.5))
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }

                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("Pulse")
                        .font(DS.Font.display(40, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                    Text("trackr")
                        .font(DS.Font.display(40, relativeTo: .largeTitle))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .tracking(-0.8)
                .opacity(wordmarkOpacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { runOpeningAnimation() }
    }

    private func runOpeningAnimation() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.18
            pulseOpacity = 0.10
        }

        withAnimation(.spring(response: 0.62, dampingFraction: 0.72).delay(0.08)) {
            logoOpacity = 1
            logoScale = 1
        }

        withAnimation(.easeOut(duration: 0.42).delay(0.42)) {
            wordmarkOpacity = 1
        }
    }
}

struct LaunchView: View {
    var onContinue: () -> Void

    @State private var pulseOpacity: CGFloat = 0.4
    @State private var pulseScale: CGFloat = 1.0
    @State private var iconOpacity: CGFloat = 0
    @State private var titleOpacity: CGFloat = 0
    @State private var featuresOpacity: CGFloat = 0
    @State private var buttonOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                pulseIcon
                    .padding(.bottom, 40)

                brandBlock
                    .padding(.bottom, 56)
                    .opacity(titleOpacity)

                featureList
                    .padding(.horizontal, 32)
                    .opacity(featuresOpacity)

                Spacer()

                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                    .opacity(buttonOpacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { runEntrance() }
    }

    private var pulseIcon: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(DS.Color.accent.opacity(0.18 - Double(i) * 0.05), lineWidth: 1)
                    .frame(width: 82 + CGFloat(i * 52), height: 82 + CGFloat(i * 52))
                    .scaleEffect(pulseScale + CGFloat(i) * 0.12)
                    .opacity(pulseOpacity)
            }

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 80, height: 80)
                .background(DS.Color.accent.opacity(0.13), in: Circle())
                .overlay(Circle().stroke(DS.Color.accent.opacity(0.28), lineWidth: 1.5))
                .opacity(iconOpacity)
        }
    }

    private var brandBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("Pulse")
                    .font(DS.Font.display(48, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                Text("trackr")
                    .font(DS.Font.display(48, relativeTo: .largeTitle))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .tracking(-1.0)

            Text("Know what's happening nearby\nbefore you head out.")
                .font(DS.Font.body())
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(
                icon: "map.fill",
                color: DS.Color.textSecondary,
                title: "Live incident map",
                description: "Real-time reports from your community"
            )
            FeatureRow(
                icon: "bell.and.waves.left.and.right.fill",
                color: DS.Color.accent,
                title: "Report what you see",
                description: "Photo, audio, or a quick note in under 20 seconds"
            )
            FeatureRow(
                icon: "location.circle.fill",
                color: DS.Color.positive,
                title: "Your location stays private",
                description: "The map shows areas only — never your exact spot"
            )
        }
    }

    private var ctaButton: some View {
        Button(action: onContinue) {
            Text("Open the map")
        }
        .buttonStyle(DSPrimaryButtonStyle())
    }

    private func runEntrance() {
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulseScale = 1.22
            pulseOpacity = 0.12
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            iconOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            titleOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.62)) {
            featuresOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.88)) {
            buttonOpacity = 1
        }
    }
}

private struct FeatureRow: View {
    var icon: String
    var color: Color
    var title: String
    var description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.body())
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(description)
                    .font(DS.Font.caption())
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    LaunchView { }
}
