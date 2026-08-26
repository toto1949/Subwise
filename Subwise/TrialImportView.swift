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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case merchant, price }

    private var parsedPrice: Decimal? { TrialTextParser().decimalPrice(from: price) }
    private var canSave: Bool { !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedPrice.map { $0 > 0 } == true && !isProcessing }

    var body: some View {
        NavigationStack {
            Form {
                Section("Screenshot") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(selectedPhoto == nil ? "Choose screenshot" : "Choose another screenshot", systemImage: "photo.badge.plus") }
                    if isProcessing { ProgressView("Recognizing trial details…") }
                    if let candidate { LabeledContent("Extraction confidence", value: candidate.confidence.formatted(.percent.precision(.fractionLength(0)))) }
                }
                Section("Confirm details") {
                    TextField("Service name", text: $merchant)
                        .textContentType(.organizationName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .merchant)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .price }
                    TextField("Renewal price", text: $price)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .price)
                    DatePicker("Trial ends", selection: $trialEndDate, displayedComponents: .date)
                    Text("Extracted values are suggestions. You can always replace the service name, price, or date before saving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let candidate, !candidate.normalizedText.isEmpty {
                    Section {
                        DisclosureGroup("Recognized text") {
                            Text(candidate.normalizedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section { Text("Subwise never creates OCR-derived subscription data until you review and confirm it.").font(.footnote).foregroundStyle(.secondary) }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("Import Trial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly).disabled(!canSave) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
            }
            .onChange(of: selectedPhoto) { _, item in guard let item else { return }; process(item) }
        }
    }

    private func process(_ item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil
        focusedField = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let result = try await VisionOCRService().recognizeTrial(in: data)
                candidate = result
                if !result.merchant.isEmpty { merchant = result.merchant }
                if let renewalPrice = result.renewalPrice { price = String(format: "%.2f", Double(renewalPrice.cents) / 100) }
                if let endDate = result.trialEndDate { trialEndDate = endDate }
                if result.merchant.isEmpty || result.renewalPrice == nil {
                    errorMessage = "Only part of the screenshot was recognized. Fill in or correct the details below."
                    focusedField = result.merchant.isEmpty ? .merchant : .price
                }
            } catch {
                candidate = nil
                errorMessage = "This screenshot could not be read automatically. You can still enter the details below."
                focusedField = merchant.isEmpty ? .merchant : .price
            }
            isProcessing = false
        }
    }

    private func save() {
        guard let decimal = parsedPrice, decimal > 0 else { return }
        let confirmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cost = Money(cents: NSDecimalNumber(decimal: decimal * 100).intValue)
        let score = SubscriptionValueScore.calculate(monthlyCost: cost, usage: .unknown, isImportant: false, isTrial: true)
        let subscription = Subscription(id: UUID(), name: confirmedMerchant, plan: "Free trial", monthlyCost: cost, renewalText: "Trial ends \(trialEndDate.formatted(date: .abbreviated, time: .omitted))", category: .other, status: .trial, valueScore: score, usage: .unknown, isImportant: false, symbol: "clock.badge.exclamationmark.fill", colorName: "orange")
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
