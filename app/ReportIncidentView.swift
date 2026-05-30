import CoreLocation
import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct ReportIncidentView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @EnvironmentObject private var locationManager: LocationManager
    @FocusState private var focusedField: ReportField?
    @State private var title = ""
    @State private var summary = ""
    @State private var neighborhood = ""
    @State private var category: IncidentCategory = .security
    @State private var subtype: IncidentSubtype = .suspiciousActivity
    @State private var severity: IncidentSeverity = .medium
    @AppStorage(AppStorageKey.useApproximateLocation) private var useApproximateLocation = true
    @State private var hasVoiceNote = false
    @State private var hasMediaEvidence = false
    // Ongoing → Active (top priority); already-happened → Watching.
    @State private var isOngoing = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isLoadingPhoto = false
    @StateObject private var voiceRecorder = VoiceNoteRecorder()
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
        return hasReportLocation && (hasDescription || hasVoiceNote || hasMediaEvidence)
    }

    private var reportCoordinate: CLLocationCoordinate2D? {
        locationManager.currentCoordinate ?? LocationManager.lastKnownCoordinate
    }

    private var hasReportLocation: Bool {
        reportCoordinate != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportHero(
                    locationStatus: locationStatus,
                    hasPrivateCoordinate: hasReportLocation
                )

                ReportComposer(
                    title: $title,
                    summary: $summary,
                    neighborhood: $neighborhood,
                    hasVoiceNote: $hasVoiceNote,
                    hasMediaEvidence: $hasMediaEvidence,
                    isOngoing: $isOngoing,
                    selectedPhotoItem: $selectedPhotoItem,
                    selectedPhotoData: $selectedPhotoData,
                    isLoadingPhoto: isLoadingPhoto,
                    voiceRecorder: voiceRecorder,
                    focusedField: $focusedField
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
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
            }
            .padding(DS.Space.lg)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissKeyboard)
        }
        .background(DS.Color.background)
        .scrollDismissesKeyboard(.interactively)
        .background(KeyboardDismissInstaller(onDismiss: dismissKeyboard))
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.requestCurrentLocation()
        }
        .onChange(of: category) { _, newCategory in
            subtype = IncidentSubtype.defaultSubtype(for: newCategory)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadPhoto(from: newItem)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
            }
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
            if locationManager.currentCoordinate != nil {
                locationManager.accuracyAuthorization == .reducedAccuracy
                    ? "Approximate location captured"
                    : "Private location captured"
            } else if LocationManager.lastKnownCoordinate != nil {
                "Using last known location"
            } else {
                "Finding private location"
            }
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
        dismissKeyboard()

        let finalCategory = showManualOptions ? category : classification.category
        let finalSubtype = showManualOptions ? subtype : classification.subtype
        let finalSeverity = showManualOptions ? severity : classification.severity
        let evidenceNotes = reportEvidenceNotes
        let evidenceAttachments = reportEvidenceAttachments
        let baseSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary: String
        if baseSummary.isEmpty {
            finalSummary = evidenceNotes.isEmpty ? "Incident report submitted with available details." : evidenceNotes.joined(separator: " ")
        } else if evidenceNotes.isEmpty {
            finalSummary = baseSummary
        } else {
            finalSummary = ([baseSummary] + evidenceNotes).joined(separator: "\n\n")
        }

        incidentStore.addIncident(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalSubtype.label : title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: finalSummary,
            category: finalCategory,
            subtype: finalSubtype,
            severity: finalSeverity,
            neighborhood: neighborhood.trimmingCharacters(in: .whitespacesAndNewlines),
            reporterCoordinate: reportCoordinate,
            useApproximateLocation: useApproximateLocation,
            status: isOngoing ? .active : .watching,
            evidenceUpdates: evidenceNotes,
            evidenceAttachments: evidenceAttachments
        )

        title = ""
        summary = ""
        neighborhood = ""
        category = .security
        subtype = .suspiciousActivity
        severity = .medium
        hasVoiceNote = false
        hasMediaEvidence = false
        isOngoing = true
        selectedPhotoItem = nil
        selectedPhotoData = nil
        voiceRecorder.reset()
        showManualOptions = false
        showSubmitted = true
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var reportEvidenceNotes: [String] {
        var notes: [String] = []
        if let selectedPhotoData {
            let size = ByteCountFormatter.string(fromByteCount: Int64(selectedPhotoData.count), countStyle: .file)
            notes.append("Photo evidence was attached by the reporter (\(size)).")
        }
        if voiceRecorder.recordingURL != nil {
            notes.append("Voice note was recorded by the reporter (\(voiceRecorder.formattedRecordedDuration)).")
        }
        if isOngoing {
            notes.append("Reporter marked this as a live/ongoing incident and may add updates as the situation changes.")
        } else {
            notes.append("Reporter marked this as an incident that already happened (not ongoing).")
        }
        return notes
    }

    private var reportEvidenceAttachments: [IncidentEvidenceAttachment] {
        var attachments: [IncidentEvidenceAttachment] = []
        if let selectedPhotoData {
            attachments.append(IncidentEvidenceAttachment(
                kind: .photo,
                filename: "incident-photo.jpg",
                contentType: "image/jpeg",
                data: selectedPhotoData,
                durationSeconds: nil
            ))
        }
        if let recordingURL = voiceRecorder.recordingURL,
           let voiceData = try? Data(contentsOf: recordingURL) {
            attachments.append(IncidentEvidenceAttachment(
                kind: .voice,
                filename: "incident-voice.m4a",
                contentType: "audio/mp4",
                data: voiceData,
                durationSeconds: voiceRecorder.recordedDuration
            ))
        }
        return attachments
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else {
            selectedPhotoData = nil
            hasMediaEvidence = false
            return
        }

        isLoadingPhoto = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                selectedPhotoData = data
                hasMediaEvidence = data != nil
                isLoadingPhoto = false
                // Attaching a photo must NOT write into the visible text fields.
                // The photo evidence note is added at submit time (see
                // reportEvidenceNotes), not into the user's description.
            }
        }
    }
}

private enum ReportField: Hashable {
    case title
    case neighborhood
    case summary
}

private struct ReportHero: View {
    var locationStatus: String
    var hasPrivateCoordinate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Report what is happening")
                .font(DS.Font.display(30, relativeTo: .title2))
                .foregroundStyle(DS.Color.textPrimary)
            Text("Show it, say it, or type it. Classification happens after.")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)

            let ok = hasPrivateCoordinate
            Label(locationStatus, systemImage: ok ? "location.fill" : "location.slash.fill")
                .font(DS.Font.label())
                .foregroundStyle(ok ? DS.Color.positive : DS.Color.alert)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background((ok ? DS.Color.positive : DS.Color.alert).opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke((ok ? DS.Color.positive : DS.Color.alert).opacity(0.3), lineWidth: 1))
        }
        .pulsePanel()
    }
}

private struct ReportComposer: View {
    @Binding var title: String
    @Binding var summary: String
    @Binding var neighborhood: String
    @Binding var hasVoiceNote: Bool
    @Binding var hasMediaEvidence: Bool
    @Binding var isOngoing: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var selectedPhotoData: Data?
    var isLoadingPhoto: Bool
    @ObservedObject var voiceRecorder: VoiceNoteRecorder
    var focusedField: FocusState<ReportField?>.Binding

    // One form: describe it, say whether it's ongoing, and optionally add a photo
    // and/or a voice note — all submitted together.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            section(title: "Describe what you see", icon: "text.alignleft") {
                textFields
            }

            Divider().overlay(DS.Color.hairline)

            section(title: "Is this still happening?", icon: "dot.radiowaves.left.and.right") {
                statusControls
            }

            Divider().overlay(DS.Color.hairline)

            section(title: "Add a photo", icon: "camera", optional: true) {
                photoControls
            }

            Divider().overlay(DS.Color.hairline)

            section(title: "Add a voice note", icon: "mic", optional: true) {
                voiceControls
            }
        }
        .pulsePanel()
    }

    @ViewBuilder
    private func section<Content: View>(
        title: LocalizedStringKey,
        icon: String,
        optional: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSSectionHeader(title: title, systemImage: icon, optional: optional)
            content()
        }
    }

    private var statusControls: some View {
        HStack(spacing: DS.Space.md) {
            StatusPill(title: "Happening now", icon: "dot.radiowaves.left.and.right", color: DS.Color.alert, isSelected: isOngoing) {
                isOngoing = true
            }
            StatusPill(title: "Already happened", icon: "clock.arrow.circlepath", color: DS.Color.textSecondary, isSelected: !isOngoing) {
                isOngoing = false
            }
        }
    }

    private var textFields: some View {
        VStack(spacing: DS.Space.md) {
            LabeledReportField(
                label: "Summary",
                placeholder: "What's happening in this photo?",
                hint: "e.g. Fallen tree blocking both lanes",
                text: $title,
                focus: focusedField,
                field: .title,
                submitLabel: .next,
                onSubmit: { focusedField.wrappedValue = .neighborhood }
            )

            LabeledReportField(
                label: "Neighborhood or landmark",
                placeholder: "e.g. Allen Avenue, Ikeja",
                text: $neighborhood,
                focus: focusedField,
                field: .neighborhood,
                submitLabel: .next,
                onSubmit: { focusedField.wrappedValue = .summary }
            )

            LabeledReportField(
                label: "Describe in detail",
                placeholder: "Provide more details about what you see and what is happening nearby.",
                text: $summary,
                focus: focusedField,
                field: .summary,
                multiline: true
            )
        }
    }

    private var photoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedPhotoData, let image = UIImage(data: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.selectedPhotoData = nil
                            selectedPhotoItem = nil
                            hasMediaEvidence = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.black.opacity(0.75), .white)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                EvidenceAttachLabel(
                    title: selectedPhotoData == nil ? "Choose photo" : "Change photo",
                    subtitle: isLoadingPhoto ? "Loading selected image..." : "Adds a photo evidence note to this report",
                    icon: selectedPhotoData == nil ? "photo.badge.plus" : "checkmark.circle.fill",
                    color: selectedPhotoData == nil ? DS.Color.textSecondary : DS.Color.positive
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            EvidenceAttachButton(
                title: voiceRecorder.isRecording ? "Stop recording" : (voiceRecorder.recordingURL == nil ? "Record voice note" : "Record again"),
                subtitle: voiceRecorder.statusText,
                icon: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill",
                color: voiceRecorder.isRecording ? DS.Color.alert : DS.Color.textSecondary
            ) {
                if voiceRecorder.isRecording {
                    voiceRecorder.stop()
                    hasVoiceNote = voiceRecorder.recordingURL != nil
                } else {
                    // Recording a voice note must NOT write into the visible text
                    // fields. The voice evidence note is added at submit time (see
                    // reportEvidenceNotes), not into the user's description.
                    voiceRecorder.start()
                }
            }

            if voiceRecorder.recordingURL != nil {
                Button {
                    voiceRecorder.reset()
                    hasVoiceNote = false
                } label: {
                    Label("Remove voice note", systemImage: "trash")
                        .font(DS.Font.body())
                        .fontWeight(.bold)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            if let permissionMessage = voiceRecorder.permissionMessage {
                Text(permissionMessage)
                    .font(DS.Font.caption())
                    .foregroundStyle(.orange)
            }
        }
    }

}

private struct StatusPill: View {
    var title: LocalizedStringKey
    var icon: String
    var color: Color
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(DS.Font.bodyStrong())
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? color.opacity(0.16) : DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.6) : DS.Color.hairline, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : DS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// Labeled report field: a small caption label on top, a prominent placeholder /
/// value, and an optional example hint below — wrapped in the standard input
/// surface. Single-line by default; `multiline` grows for long descriptions.
private struct LabeledReportField: View {
    var label: LocalizedStringKey
    var placeholder: LocalizedStringKey
    var hint: LocalizedStringKey? = nil
    @Binding var text: String
    var focus: FocusState<ReportField?>.Binding
    var field: ReportField
    var submitLabel: SubmitLabel = .return
    var multiline: Bool = false
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(label)
                .font(DS.Font.bodyStrong())
                .foregroundStyle(DS.Color.textPrimary)

            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(4...10)
                } else {
                    TextField(placeholder, text: $text)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                }
            }
            .font(.system(.title3, weight: .regular))
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .focused(focus, equals: field)

            if let hint {
                Text(hint)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
    }
}

private struct EvidenceAttachButton: View {
    var title: String
    var subtitle: String? = nil
    var icon: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            EvidenceAttachLabel(title: title, subtitle: subtitle, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }
}

private struct EvidenceAttachLabel: View {
    var title: String
    var subtitle: String?
    var icon: String
    var color: Color

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.cardTitle())
                    .foregroundStyle(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
    }
}

private struct SuggestionPanel: View {
    var classification: IncidentClassification
    var category: IncidentCategory
    var subtype: IncidentSubtype
    var severity: IncidentSeverity
    var useSuggestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: subtype.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)
                    .frame(width: 46, height: 46)
                    .background(category.color.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(category.color.opacity(0.3), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(subtype.label)
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(category.label)
                        .font(DS.Font.label())
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Spacer()

                DSSeverityBadge(severity: severity)
            }

            Text(classification.reason)
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)

            Button(action: useSuggestion) {
                Label("Use suggestion", systemImage: "wand.and.stars")
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
        .pulsePanel()
    }
}

private struct PrivacyPanel: View {
    var locationStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label(locationStatus, systemImage: "lock.shield")
                .font(DS.Font.bodyStrong())
                .foregroundStyle(DS.Color.textPrimary)
            Text("Exact reporter location stays private to the app. The public map shows an approximate incident area.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
        }
        .pulsePanel()
    }
}

private final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingURL: URL?
    @Published var recordedDuration: TimeInterval = 0
    @Published var permissionMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    var formattedRecordedDuration: String {
        Self.formatDuration(recordedDuration)
    }

    var statusText: String {
        if isRecording {
            return "Recording \(Self.formatDuration(recordedDuration))"
        }
        if recordingURL != nil {
            return "Recorded \(formattedRecordedDuration)"
        }
        return "Records an audio evidence note on this device"
    }

    func start() {
        requestPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.beginRecording()
            } else {
                self.permissionMessage = "Microphone access is needed to record a voice note."
            }
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stop()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        recordedDuration = 0
        permissionMessage = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        timer?.invalidate()
        timer = nil
        if flag {
            recordingURL = recorder.url
            recordedDuration = max(recordedDuration, recorder.currentTime)
        }
    }

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    private func beginRecording() {
        reset()
        permissionMessage = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("incident-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()

            self.recorder = recorder
            recordingURL = url
            recordedDuration = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let recorder = self.recorder else { return }
                self.recordedDuration = recorder.currentTime
            }
        } catch {
            permissionMessage = "Could not start recording. Check microphone access and try again."
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct KeyboardDismissInstaller: UIViewControllerRepresentable {
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(on: uiViewController.view.window)
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var installedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func installIfNeeded(on window: UIWindow?) {
            guard let window, installedWindow !== window else { return }
            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            installedWindow = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.isTextInputOrControl
        }

        @objc private func handleTap() {
            onDismiss()
        }
    }
}

private extension UIView {
    var isTextInputOrControl: Bool {
        if self is UIControl || self is UITextView || self is UITextField {
            return true
        }
        return superview?.isTextInputOrControl ?? false
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ReportIncidentView()
            .environmentObject(IncidentStore.preview)
            .environmentObject(LocationManager())
    }
}
#endif
