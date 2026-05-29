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
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canSubmit)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissKeyboard)
        }
        .background(.black)
        .scrollDismissesKeyboard(.interactively)
        .background(KeyboardDismissInstaller(onDismiss: dismissKeyboard))
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
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
                fillIfNeeded(title: "Photo report", summary: "Reporter attached a photo and is describing what is happening nearby.")
            }
        }
    }

    private func fillIfNeeded(title newTitle: String, summary newSummary: String) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = newTitle
        }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = newSummary
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
        VStack(alignment: .leading, spacing: 18) {
            section(title: "Describe what you see", icon: "text.bubble.fill", color: .green) {
                textFields
            }

            Divider().background(.white.opacity(0.07))

            section(title: "Is this still happening?", icon: "dot.radiowaves.left.and.right", color: .red) {
                statusControls
            }

            Divider().background(.white.opacity(0.07))

            section(title: "Add a photo (optional)", icon: "camera.fill", color: .purple) {
                photoControls
            }

            Divider().background(.white.opacity(0.07))

            section(title: "Add a voice note (optional)", icon: "mic.fill", color: .blue) {
                voiceControls
            }
        }
        .cardPanel(backgroundOpacity: 0.09)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            content()
        }
    }

    private var statusControls: some View {
        HStack(spacing: 10) {
            StatusPill(title: "Happening now", icon: "dot.radiowaves.left.and.right", color: .red, isSelected: isOngoing) {
                isOngoing = true
            }
            StatusPill(title: "Already happened", icon: "clock.arrow.circlepath", color: .orange, isSelected: !isOngoing) {
                isOngoing = false
            }
        }
    }

    private var textFields: some View {
        VStack(spacing: 10) {
            DarkTextField(title: "Short title", text: $title)
                .focused(focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit {
                    focusedField.wrappedValue = .neighborhood
                }
            DarkTextField(title: "Neighborhood or landmark", text: $neighborhood)
                .focused(focusedField, equals: .neighborhood)
                .submitLabel(.next)
                .onSubmit {
                    focusedField.wrappedValue = .summary
                }
            TextEditor(text: $summary)
                .focused(focusedField, equals: .summary)
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
                    color: .purple
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
                color: .blue
            ) {
                if voiceRecorder.isRecording {
                    voiceRecorder.stop()
                    hasVoiceNote = voiceRecorder.recordingURL != nil
                } else {
                    voiceRecorder.start()
                    fillIfNeeded(title: "Voice report", summary: "Reporter is sharing what is happening nearby.")
                }
            }

            if voiceRecorder.recordingURL != nil {
                Button {
                    voiceRecorder.reset()
                    hasVoiceNote = false
                } label: {
                    Label("Remove voice note", systemImage: "trash")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            if let permissionMessage = voiceRecorder.permissionMessage {
                Text(permissionMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

}

private struct StatusPill: View {
    var title: String
    var icon: String
    var color: Color
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? color.opacity(0.22) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isSelected ? color.opacity(0.7) : .white.opacity(0.10), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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
