//
//  RecordShareView.swift
//  Out for Delivery
//
//  Per-record sharing controls, presented as a sheet for one share root: a Baby
//  (its feeds travel with it) or the per-user LaborLog (its contractions travel with
//  it). Shows who the record is shared with, a prominent invite call to action, and
//  Stop sharing / Leave. Inviting, removing, and changing permissions all happen in
//  Apple's system share sheet (presented by ShareLink), so this stays a friendly,
//  read-mostly view with a single primary action.
//
//  This is content-layer UI: a standard List with standard materials. Liquid Glass
//  is reserved for the floating control layer; the one exception is the prominent
//  invite button, the screen's single primary action.
//

import SwiftUI
import CoreData
import CloudKit

/// Identifies a shareable record for the share sheet: its objectID and a friendly
/// title for the system share UI and navigation.
struct ShareTarget: Identifiable {
    let objectID: NSManagedObjectID
    let title: String
    var id: NSManagedObjectID { objectID }
}

struct RecordShareView: View {
    let target: ShareTarget

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var currentShare: CKShare?

    // Drives a gentle success haptic when a NEW caregiver appears while the screen
    // is open — a quiet moment of delight, never on routine actions. `previousCount`
    // is nil until the first load, so the haptic never fires on initial appearance.
    @State private var previousCount: Int?
    @State private var celebrate = 0
    @State private var isOwner = true
    @State private var actionError: String?

    enum Phase: Equatable {
        case loading
        case solo
        case shared([Caregiver])
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(target.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await load() }
                .sensoryFeedback(.success, trigger: celebrate)
                .alert("Sharing", isPresented: .constant(actionError != nil)) {
                    Button("OK") { actionError = nil }
                } message: {
                    Text(actionError ?? "")
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .solo:
            soloState
                .transition(.opacity)
        case .shared(let caregivers):
            roster(caregivers)
                .transition(.opacity)
        }
    }

    // MARK: - Solo (not shared yet)

    private var soloState: some View {
        ContentUnavailableView {
            Label("Just you for now", systemImage: "person.crop.circle")
        } description: {
            Text("Invite a partner or caregiver so you both see and add the same entries for \(target.title), each on your own device.")
        } actions: {
            ShareLink(item: shareItem, preview: SharePreview(target.title)) {
                Label("Invite a caregiver", systemImage: "person.badge.plus")
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - Shared roster

    private func roster(_ caregivers: [Caregiver]) -> some View {
        List {
            Section {
                ForEach(caregivers) { caregiver in
                    CaregiverRowView(caregiver: caregiver)
                }
            } header: {
                Text("Shared with")
            } footer: {
                Text("Everyone here sees and can add entries for \(target.title). Invite more people, change access, or stop sharing from the share sheet.")
            }

            Section {
                ShareLink(item: shareItem, preview: SharePreview(target.title)) {
                    Label("Invite or manage caregivers", systemImage: "person.2.badge.gearshape")
                }
            }

            Section {
                if isOwner {
                    Button(role: .destructive) {
                        Task { await stopSharing() }
                    } label: {
                        Label("Stop sharing", systemImage: "person.2.slash")
                    }
                } else {
                    Button(role: .destructive) {
                        Task { await leaveShare() }
                    } label: {
                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } footer: {
                Text(isOwner
                     ? "Stops sharing for everyone. Your data stays on this device."
                     : "Removes this from your device. The other caregivers keep their copy.")
            }
        }
        .refreshable { await load() }
    }

    private func stopSharing() async {
        do {
            try await SharingManager.shared.stopSharing(objectID: target.objectID)
            await load()
        } catch {
            actionError = "Could not stop sharing. \(error.localizedDescription)"
        }
    }

    private func leaveShare() async {
        do {
            try await SharingManager.shared.leaveShare(objectID: target.objectID)
            dismiss()
        } catch {
            actionError = "Could not leave. \(error.localizedDescription)"
        }
    }

    // MARK: - Loading

    /// Builds the ShareLink payload. When a share already exists we pass it so the
    /// system sheet opens in management mode; otherwise nil drives the create path.
    private var shareItem: CKShareItem {
        CKShareItem(objectID: target.objectID, title: target.title, existingShare: currentShare)
    }

    private func load() async {
        let share = try? SharingManager.shared.existingShare(forObjectID: target.objectID)
        currentShare = share
        isOwner = SharingManager.shared.isOwner(ofObjectID: target.objectID)

        let caregivers = (share?.participants ?? [])
            .filter { $0.acceptanceStatus != .removed }
            .map(Self.caregiver(from:))
            .sorted { ($0.isOwner ? 0 : 1, $0.name) < ($1.isOwner ? 0 : 1, $1.name) }

        if let previousCount, caregivers.count > previousCount { celebrate += 1 }
        previousCount = caregivers.count

        withAnimation(.smooth) {
            phase = caregivers.isEmpty ? .solo : .shared(caregivers)
        }
    }
}

/// A view-model row built from a CKShare participant on the main actor.
struct Caregiver: Identifiable, Equatable {
    let id: String
    let name: String
    let roleText: String
    let statusText: String
    let isOwner: Bool
    let initials: String
    let hue: Double
}

extension RecordShareView {
    // MARK: - Participant mapping

    static func caregiver(from participant: CKShare.Participant) -> Caregiver {
        let name = displayName(participant)
        let isOwner = participant.role == .owner
        return Caregiver(
            id: participantID(participant, fallback: name),
            name: name,
            roleText: isOwner ? "Owner" : "Caregiver",
            statusText: participant.acceptanceStatus == .pending ? "Invited" : "Active",
            isOwner: isOwner,
            initials: initials(from: name),
            hue: stableHue(name)
        )
    }

    private static func displayName(_ participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber { return phone }
        return "Caregiver"
    }

    private static func participantID(_ participant: CKShare.Participant, fallback: String) -> String {
        participant.userIdentity.userRecordID?.recordName ?? fallback
    }

    private static func initials(from name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// A stable hue per name so each caregiver keeps the same avatar color across
    /// launches (Swift's String.hashValue is per-process, so we sum scalars instead).
    private static func stableHue(_ name: String) -> Double {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360.0
    }
}

/// One caregiver row: a tinted initials avatar, name, role, and acceptance status.
struct CaregiverRowView: View {
    let caregiver: Caregiver

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hue: caregiver.hue, saturation: 0.45, brightness: 0.85))
                Text(caregiver.initials)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(caregiver.name)
                    .font(.body)
                Text(caregiver.roleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(caregiver.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(caregiver.statusText == "Invited" ? .orange : .green)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caregiver.name), \(caregiver.roleText), \(caregiver.statusText)")
    }
}
