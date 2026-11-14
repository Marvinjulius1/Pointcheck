import EventKit
import SwiftUI

// MARK: - Propose a rematch

struct RematchSheet: View {
    let opponentID: UUID
    let opponentName: String
    var matchID: UUID?
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
    @State private var note = ""
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            FormScreen(title: "Revanche", subtitle: "\(opponentName) sieht den Vorschlag unter Aktivität und kann zusagen oder ablehnen.",
                       symbol: "arrow.trianglehead.2.clockwise.rotate.90") {
                FormGroup(title: "Vorschlag") {
                    DateRow(title: "Wann?", date: $date, range: Date.now...)
                    RowDivider()
                    InputRow(label: "Nachricht", placeholder: "optional", text: $note, symbol: "text.bubble.fill",
                             axis: .vertical, lineLimit: 1...3)
                }
                if let errorText { FormError(text: errorText) }
            } footer: {
                FormActionBar(title: "Revanche vorschlagen", isWorking: isSending) { Task { await send() } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await account.proposeRematch(to: opponentID, matchID: matchID, at: date, note: note)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorText = "Der Vorschlag konnte nicht gesendet werden. Versuch es noch einmal."
        }
    }
}

// MARK: - Rematch row (Aktivität)

struct RematchRow: View {
    let request: RematchRequest
    @Environment(AccountService.self) private var account
    @State private var isWorking = false
    @State private var calendarMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                NavigationLink(value: request.incoming ? request.fromID : request.toID) {
                    ProfilePhoto(name: request.otherName, url: account.imageURL(request.otherAvatar, bucket: .avatars))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.incoming ? "\(request.otherName) will eine Revanche" : "Revanche an \(request.otherName)")
                        .font(.body.weight(.semibold))
                    Text(request.proposedAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let note = request.note, !note.isEmpty {
                        Text("„\(note)“").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if request.status != .pending {
                    Text(request.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(request.status == .accepted ? Theme.me : .secondary)
                }
            }
            if request.incoming, request.status == .pending {
                HStack(spacing: 10) {
                    Button("Zusagen") { act { try await account.respondRematch(request, accept: true) } }
                        .buttonStyle(.accent)
                    Button("Ablehnen") { act { try await account.respondRematch(request, accept: false) } }
                        .buttonStyle(.quiet)
                }
            } else if request.status == .accepted {
                Button {
                    Task { await addToCalendar() }
                } label: {
                    Label(calendarMessage ?? "In Kalender eintragen", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.quiet)
            } else if !request.incoming, request.status == .pending {
                Button("Zurückziehen") { act { try await account.withdrawRematch(request) } }
                    .buttonStyle(.quiet)
            }
        }
        .disabled(isWorking)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            try? await work()
            isWorking = false
        }
    }

    private func addToCalendar() async {
        let result = await CalendarExport.add(title: "Padel: Revanche mit \(request.otherName)", start: request.proposedAt, notes: request.note)
        calendarMessage = result
    }
}

// MARK: - Calendar export

enum CalendarExport {
    /// Adds a 90-minute event. Returns a short message for the UI.
    static func add(title: String, start: Date, notes: String? = nil, location: String? = nil) async -> String {
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return "Kalenderzugriff abgelehnt" }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = start.addingTimeInterval(90 * 60)
            event.notes = notes
            event.location = location
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return "Im Kalender"
        } catch {
            return "Kalender nicht verfügbar"
        }
    }
}
