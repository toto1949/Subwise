import PhotosUI
import SwiftUI
import UIKit

struct AppleSubscriptionImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var recognizedText = ""
    @State private var name = ""
    @State private var price = ""
    @State private var frequency: SubscriptionBillingFrequency = .monthly
    @State private var renewalDate = Date.now
    @State private var category: SubscriptionCategory = .other
    @State private var isTrial = false
    @State private var confidence: Double?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case name, price }
    private var decimalPrice: Decimal? { TrialTextParser().decimalPrice(from: price) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && decimalPrice.map { $0 > 0 } == true && !isProcessing }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple subscription screenshot") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(selectedPhoto == nil ? "Choose screenshot" : "Choose another screenshot", systemImage: "photo.badge.plus") }
                    if isProcessing { ProgressView("Extracting subscription details…") }
                    if let confidence { LabeledContent("Extraction confidence", value: confidence.formatted(.percent.precision(.fractionLength(0)))) }
                }
                Section("Confirm before saving") {
                    TextField("Service name", text: $name).textContentType(.organizationName).focused($focusedField, equals: .name).submitLabel(.next).onSubmit { focusedField = .price }
                    TextField("Price", text: $price).keyboardType(.decimalPad).focused($focusedField, equals: .price)
                    Picker("Billing cycle", selection: $frequency) { ForEach(SubscriptionBillingFrequency.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker(isTrial ? "Trial ends" : "Renewal date", selection: $renewalDate, displayedComponents: .date)
                    Picker("Category", selection: $category) { ForEach(SubscriptionCategory.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Free trial", isOn: $isTrial)
                    Text("OCR results are suggestions. Correct any field before saving; SubWise never silently adds screenshot data.").font(.footnote).foregroundStyle(.secondary)
                }
                if !recognizedText.isEmpty {
                    Section { DisclosureGroup("Recognized text") { Text(recognizedText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("Import subscription").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
            }
            .onChange(of: selectedPhoto) { _, value in if let value { process(value) } }
        }
    }

    private func process(_ item: PhotosPickerItem) {
        isProcessing = true; errorMessage = nil; focusedField = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let result = try await VisionOCRService().recognizeTrial(in: data)
                recognizedText = result.normalizedText; confidence = result.confidence
                if !result.merchant.isEmpty { name = result.merchant }
                if let value = result.renewalPrice { price = String(format: "%.2f", Double(value.cents) / 100) }
                if let value = result.trialEndDate { renewalDate = value }
                let text = result.normalizedText.lowercased()
                isTrial = text.contains("trial") || text.contains("free until")
                if text.contains("year") || text.contains("annual") { frequency = .yearly }
                else if text.contains("week") { frequency = .weekly }
                else { frequency = .monthly }
                if result.merchant.isEmpty || result.renewalPrice == nil { errorMessage = "Only part of the screenshot was recognized. Fill in the missing fields below."; focusedField = result.merchant.isEmpty ? .name : .price }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = "This screenshot could not be read automatically. You can still enter every field below."
                focusedField = .name
            }
            isProcessing = false
        }
    }

    private func save() {
        guard let value = decimalPrice, value > 0 else { return }
        let billed = Money(cents: NSDecimalNumber(decimal: value * 100).intValue)
        let monthly = frequency.monthlyEquivalent(billed)
        let confirmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let presentation = ServiceBrand.presentation(for: confirmedName)
        let subscription = Subscription(
            id: UUID(), name: confirmedName, plan: isTrial ? "Free trial" : frequency.rawValue,
            monthlyCost: monthly,
            renewalText: "\(isTrial ? "Trial ends" : "Renews") \(renewalDate.formatted(date: .abbreviated, time: .omitted))",
            category: category, status: isTrial ? .trial : .active,
            valueScore: SubscriptionValueScore.calculate(monthlyCost: monthly, usage: .unknown, isImportant: false, isTrial: isTrial),
            usage: .unknown, isImportant: false, billingSource: .appStore,
            billingAmount: billed, billingFrequency: frequency, renewalDate: renewalDate, paymentMethod: "Apple Account",
            discoverySource: .screenshot, symbol: presentation.symbol, colorName: presentation.color
        )
        Task {
            do {
                try await store.add(subscription)
                _ = try? await NotificationService.shared.requestAuthorization()
                try? await NotificationService.shared.scheduleRenewal(id: subscription.id, merchant: subscription.name, amount: subscription.chargedAmount, renewalDate: renewalDate)
                UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss()
            } catch { errorMessage = "The confirmed subscription could not be saved." }
        }
    }
}
