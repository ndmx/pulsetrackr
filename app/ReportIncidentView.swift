import CoreLocation
import SwiftUI

enum ReportInputMode: String, CaseIterable, Identifiable {
    case media
    case live
    case voice
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .media: "Photo"
        case .live: "Live"
        case .voice: "Voice"
        case .text: "Text"
        }
    }

    var icon: String {
        switch self {
        case .media: "camera.fill"
        case .live: "dot.radiowaves.left.and.right"
        case .voice: "mic.fill"
        case .text: "text.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .media: .purple
        case .live: .red
        case .voice: .blue
        case .text: .green
        }
    }

    var actionTitle: String {
        switch self {
        case .media: "Add photo/video details"
        case .live: "Prepare live report"
        case .voice: "Add voice details"
        case .text: "Describe what you see"
        }
    }
}

struct ReportIncidentView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @EnvironmentObject private var locationManager: LocationManager
    @State private var inputMode: ReportInputMode = .text
    @State private var title = ""
    @State private var summary = ""
    @State private var neighborhood = ""
    @State private var category: IncidentCategory = .security
    @State private var subtype: IncidentSubtype = .suspiciousActivity
    @State private var severity: IncidentSeverity = .medium
    @AppStorage(AppStorageKey.useApproximateLocation) private var useApproximateLocation = true
    @State private var hasVoiceNote = false
    @State private var hasMediaEvidence = false
    @State private var hasLiveSignal = false
    @State private var showManualOptions = false
    @State private var showSubmitted = false

    private var classification: IncidentClassification {
        IncidentClassifier.classify(title: title, summary: summary)
    }

    private var availableSubtypes: [IncidentSubtype] {
        IncidentSubtype.subtypes(for: category)
    }

    private var canSubmit: Bool {
        let hasDescription = title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 &&
            summary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
        return hasDescription || hasVoiceNote || hasMediaEvidence || hasLiveSignal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportHero(
                    locationStatus: locationStatus,
                    hasPrivateCoordinate: locationManager.currentCoordinate != nil
                )

                LauncherGrid(selectedMode: $inputMode)

                ReportComposer(
                    mode: inputMode,
                    title: $title,
                    summary: $summary,
                    neighborhood: $neighborhood,
                    hasVoiceNote: $hasVoiceNote,
                    hasMediaEvidence: $hasMediaEvidence,
                    hasLiveSignal: $hasLiveSignal
                )

                SuggestionPanel(
                    classification: classification,
                    category: showManualOptions ? category : classification.category,
                    subtype: showManualOptions ? subtype : classification.subtype,
                    severity: showManualOptions ? severity : classification.severity,
                    useSuggestion: applySuggestion
                )

                manualControls

                PrivacyPanel(locationStatus: locationStatus)

                Button {
                    submit()
                } label: {
                    Label("Report now", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canSubmit)
            }
            .padding(16)
        }
        .background(.black)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            locationManager.requestCurrentLocation()
        }
        .onChange(of: category) { _, newCategory in
            subtype = IncidentSubtype.defaultSubtype(for: newCategory)
        }
        .alert("Alert sent", isPresented: $showSubmitted) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("Nearby people see an approximate incident area. Your exact reporting location stays private to the app.")
        }
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    showManualOptions.toggle()
                }
            } label: {
                HStack {
                    Label("Change classification", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: showManualOptions ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline)
                .fontWeight(.bold)
            }
            .buttonStyle(.plain)

            if showManualOptions {
                VStack(spacing: 10) {
                    Picker("Category", selection: $category) {
                        ForEach(IncidentCategory.allCases) { category in
                            Label(category.label, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Type", selection: $subtype) {
                        ForEach(availableSubtypes) { subtype in
                            Label(subtype.label, systemImage: subtype.icon)
                                .tag(subtype)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Severity", selection: $severity) {
                        ForEach(IncidentSeverity.allCases) { severity in
                            Text(severity.rawValue).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .cardPanel(backgroundOpacity: 0.09)
    }

    private var locationStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.currentCoordinate == nil ? "Finding private location" : "Private location captured"
        case .notDetermined:
            "Location permission needed"
        case .denied, .restricted:
            "Private location unavailable"
        @unknown default:
            "Location status unknown"
        }
    }

    private func applySuggestion() {
        category = classification.category
        subtype = classification.subtype
        severity = classification.severity
        showManualOptions = true
    }

    private func submit() {
        let finalCategory = showManualOptions ? category : classification.category
        let finalSubtype = showManualOptions ? subtype : classification.subtype
        let finalSeverity = showManualOptions ? severity : classification.severity

        incidentStore.addIncident(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalSubtype.label : title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Immediate community report sent with limited details." : summary.trimmingCharacters(in: .whitespacesAndNewlines),
            category: finalCategory,
            subtype: finalSubtype,
            severity: finalSeverity,
            neighborhood: neighborhood.trimmingCharacters(in: .whitespacesAndNewlines),
            reporterCoordinate: locationManager.currentCoordinate,
            useApproximateLocation: useApproximateLocation
        )

        title = ""
        summary = ""
        neighborhood = ""
        category = .security
        subtype = .suspiciousActivity
        severity = .medium
        hasVoiceNote = false
        hasMediaEvidence = false
        hasLiveSignal = false
        inputMode = .text
        showManualOptions = false
        showSubmitted = true
    }
}

private struct ReportHero: View {
    var locationStatus: String
    var hasPrivateCoordinate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Report what is happening")
                        .font(.title2)
                        .fontWeight(.heavy)
                    Text("Show it, say it, or type it. Classification happens after.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Image(systemName: "plus.message.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.red, in: Circle())
            }

            Label(locationStatus, systemImage: hasPrivateCoordinate ? "location.circle.fill" : "location.slash.fill")
                .font(.caption)
                .fontWeight(.heavy)
                .foregroundStyle(hasPrivateCoordinate ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background((hasPrivateCoordinate ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        }
        .cardPanel(backgroundOpacity: 0.09)
    }
}

private struct LauncherGrid: View {
    @Binding var selectedMode: ReportInputMode

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ReportInputMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.title2)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.label)
                                .font(.headline)
                            Text(mode.actionTitle)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(13)
                    .frame(minHeight: 74)
                    .background(selectedMode == mode ? mode.color.opacity(0.24) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedMode == mode ? mode.color.opacity(0.78) : .white.opacity(0.06), lineWidth: 1)
                    )
                    .foregroundStyle(selectedMode == mode ? mode.color : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReportComposer: View {
    var mode: ReportInputMode
    @Binding var title: String
    @Binding var summary: String
    @Binding var neighborhood: String
    @Binding var hasVoiceNote: Bool
    @Binding var hasMediaEvidence: Bool
    @Binding var hasLiveSignal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(mode.actionTitle, systemImage: mode.icon)
                .font(.headline)
                .foregroundStyle(mode.color)

            switch mode {
            case .text:
                textFields
            case .voice:
                EvidenceAttachButton(
                    title: hasVoiceNote ? "Voice details added" : "Add voice details",
                    icon: hasVoiceNote ? "checkmark.circle.fill" : "mic.circle.fill",
                    color: mode.color
                ) {
                    hasVoiceNote.toggle()
                    fillIfNeeded(title: "Voice report", summary: "Reporter is sharing what is happening nearby.")
                }
            case .media:
                EvidenceAttachButton(
                    title: hasMediaEvidence ? "Photo/video details added" : "Add photo/video details",
                    icon: hasMediaEvidence ? "checkmark.circle.fill" : "camera.circle.fill",
                    color: mode.color
                ) {
                    hasMediaEvidence.toggle()
                    fillIfNeeded(title: "Media report", summary: "Reporter is adding visual details about what is happening nearby.")
                }
            case .live:
                EvidenceAttachButton(
                    title: hasLiveSignal ? "Live report prepared" : "Prepare live report",
                    icon: hasLiveSignal ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right",
                    color: mode.color
                ) {
                    hasLiveSignal.toggle()
                    fillIfNeeded(title: "Live report", summary: "Reporter is ready to share what is happening in real time.")
                }
            }
        }
        .cardPanel(backgroundOpacity: 0.09)
    }

    private var textFields: some View {
        VStack(spacing: 10) {
            DarkTextField(title: "Short title", text: $title)
            DarkTextField(title: "Neighborhood or landmark", text: $neighborhood)
            TextEditor(text: $summary)
                .frame(minHeight: 132)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if summary.isEmpty {
                        Text("What is happening? Use your own words.")
                            .foregroundStyle(.white.opacity(0.34))
                            .padding(.top, 17)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func fillIfNeeded(title newTitle: String, summary newSummary: String) {
        if title.isEmpty {
            title = newTitle
        }
        if summary.isEmpty {
            summary = newSummary
        }
    }
}

private struct DarkTextField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EvidenceAttachButton: View {
    var title: String
    var icon: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.16), in: Circle())

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct SuggestionPanel: View {
    var classification: IncidentClassification
    var category: IncidentCategory
    var subtype: IncidentSubtype
    var severity: IncidentSeverity
    var useSuggestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: subtype.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(category.color, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(subtype.label)
                        .font(.headline)
                    Text("\(category.label) • \(severity.rawValue)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()
            }

            Text(classification.reason)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))

            Button(action: useSuggestion) {
                Label("Use suggestion", systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
        }
        .cardPanel(backgroundOpacity: 0.09)
    }
}

private struct PrivacyPanel: View {
    var locationStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(locationStatus, systemImage: "location.circle.fill")
                .font(.subheadline)
                .fontWeight(.bold)
            Text("Exact reporter location stays private to the app. The public map shows an approximate incident area.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .cardPanel(backgroundOpacity: 0.09)
    }
}

#Preview {
    NavigationStack {
        ReportIncidentView()
            .environmentObject(IncidentStore())
            .environmentObject(LocationManager())
    }
}
