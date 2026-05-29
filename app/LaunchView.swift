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
                            .stroke(Color.red.opacity(0.20 - Double(index) * 0.04), lineWidth: 1.2)
                            .frame(width: 88 + CGFloat(index * 46), height: 88 + CGFloat(index * 46))
                            .scaleEffect(pulseScale + CGFloat(index) * 0.06)
                            .opacity(pulseOpacity)
                    }

                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(.red)
                        .frame(width: 86, height: 86)
                        .background(Color.red.opacity(0.13), in: Circle())
                        .overlay(Circle().stroke(Color.red.opacity(0.30), lineWidth: 1.5))
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }

                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("Pulse")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("trackr")
                        .font(.system(size: 38, weight: .thin, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                }
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
                    .stroke(Color.red.opacity(0.18 - Double(i) * 0.05), lineWidth: 1)
                    .frame(width: 82 + CGFloat(i * 52), height: 82 + CGFloat(i * 52))
                    .scaleEffect(pulseScale + CGFloat(i) * 0.12)
                    .opacity(pulseOpacity)
            }

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.red)
                .frame(width: 80, height: 80)
                .background(Color.red.opacity(0.13), in: Circle())
                .overlay(Circle().stroke(Color.red.opacity(0.28), lineWidth: 1.5))
                .opacity(iconOpacity)
        }
    }

    private var brandBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("Pulse")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("trackr")
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Text("See what's happening in your area\nbefore you leave home.")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 22) {
            FeatureRow(
                icon: "map.fill",
                color: .blue,
                title: "Live incident map",
                description: "Active reports from your community, updated in real time"
            )
            FeatureRow(
                icon: "bell.and.waves.left.and.right.fill",
                color: .red,
                title: "Report what you see",
                description: "Snap a photo, record audio, or type — takes under 20 seconds"
            )
            FeatureRow(
                icon: "location.circle.fill",
                color: .green,
                title: "Your location stays private",
                description: "The map shows areas only — your exact spot is never shared"
            )
        }
    }

    private var ctaButton: some View {
        Button(action: onContinue) {
            Text("Open the map")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    LaunchView { }
}
