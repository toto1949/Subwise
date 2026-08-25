import PhotosUI
import SwiftUI

struct TrialImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var candidate: TrialCandidate?
    @State private var merchant = ""
    @State private var price = ""
    @State private var trialEndDate = Date.now
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Screenshot") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(selectedPhoto == nil ? "Choose screenshot" : "Choose another screenshot", systemImage: "photo.badge.plus") }
                    if isProcessing { ProgressView("Recognizing trial details…") }
                    if let candidate { LabeledContent("Extraction confidence", value: candidate.confidence.formatted(.percent.precision(.fractionLength(0)))) }
                }
                if candidate != nil {
                    Section("Confirm details") {
                        TextField("Service", text: $merchant)
                        TextField("Renewal price", text: $price).keyboardType(.decimalPad)
                        DatePicker("Trial ends", selection: $trialEndDate, displayedComponents: .date)
                    }
                    Section { Text("Subwise never creates OCR-derived subscription data until you review and confirm it.").font(.footnote).foregroundStyle(.secondary) }
                }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("Import Trial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly).disabled(candidate == nil || merchant.isEmpty || Decimal(string: price) == nil) }
            }
            .onChange(of: selectedPhoto) { _, item in guard let item else { return }; process(item) }
        }
    }

    private func process(_ item: PhotosPickerItem) {
        isProcessing = true; errorMessage = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let result = try await VisionOCRService().recognizeTrial(in: data)
                candidate = result; merchant = result.merchant; price = result.renewalPrice.map { String(format: "%.2f", Double($0.cents) / 100) } ?? ""; trialEndDate = result.trialEndDate ?? .now
            } catch { errorMessage = "This screenshot could not be read. Try a clearer image or add the trial manually." }
            isProcessing = false
        }
    }

    private func save() {
        guard let decimal = Decimal(string: price) else { return }
        let subscription = Subscription(id: UUID(), name: merchant, plan: "Free trial", monthlyCost: Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue), renewalText: "Trial ends \(trialEndDate.formatted(date: .abbreviated, time: .omitted))", category: .other, status: .trial, valueScore: 45, symbol: "clock.badge.exclamationmark.fill", colorName: "orange")
        Task {
            do {
                try await store.add(subscription)
                _ = try? await NotificationService.shared.requestAuthorization()
                try? await NotificationService.shared.scheduleRenewal(id: subscription.id, merchant: subscription.name, amount: subscription.monthlyCost, renewalDate: trialEndDate)
                dismiss()
            } catch { errorMessage = "The confirmed trial could not be saved." }
        }
    }
}
