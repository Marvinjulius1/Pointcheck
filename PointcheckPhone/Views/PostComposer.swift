import PadelStats
import PhotosUI
import SwiftUI

/// Write a post: text, optional photo, optional match (its result card as preview).
struct PostComposer: View {
    /// A match to attach (must already be uploaded; otherwise only text/photo).
    let match: MatchSummary?
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?
    @State private var attachMatch = true
    @State private var isPosting = false
    @State private var errorText: String?

    private var canAttachMatch: Bool {
        guard let match else { return false }
        return account.uploads[match.id] != nil || account.foreignIDs.contains(match.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ProfilePhoto(name: account.profile?.displayName ?? "", url: account.imageURL(account.profile?.avatarPath, bucket: .avatars), size: 40)
                        Text(account.profile?.displayName ?? "")
                            .font(.subheadline.weight(.semibold))
                    }

                    TextField("Was gibt's vom Platz?", text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(4...10)
                        .padding(14)
                        .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))

                    if let photoPreview {
                        photoPreview.resizable().scaledToFill()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4 / 3, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    photoItem = nil; photoData = nil; self.photoPreview = nil
                                } label: {
                                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                        .padding(8).background(.black.opacity(0.5), in: .circle)
                                }
                                .padding(8)
                                .accessibilityLabel("Foto entfernen")
                            }
                    }

                    if let match {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Ergebnis anhängen", isOn: $attachMatch)
                                .disabled(!canAttachMatch)
                            if attachMatch {
                                ShareCardView(match: match)
                                    .scaleEffect(0.55, anchor: .topLeading)
                                    .frame(width: 360 * 0.55, height: 450 * 0.55)
                                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            }
                            if !canAttachMatch {
                                Text("Trag das Match zuerst unter „Spielstärke“ ein, dann kannst du das Ergebnis anhängen.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoPreview == nil ? "Foto hinzufügen" : "Anderes Foto", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.quiet)

                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Theme.opponent)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Neuer Beitrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Posten") { Task { await post() } }
                        .disabled(isPosting || !hasContent)
                }
            }
            .onChange(of: photoItem) { _, item in Task { await loadPhoto(item) } }
            .onAppear { attachMatch = canAttachMatch }
        }
    }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil || (attachMatch && canAttachMatch)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photoData = image.resizedJPEG(maxSide: 1600, quality: 0.82)
        if let photoData, let preview = UIImage(data: photoData) { photoPreview = Image(uiImage: preview) }
    }

    private func post() async {
        isPosting = true
        errorText = nil
        defer { isPosting = false }
        do {
            try await account.createPost(text: text, image: photoData, matchID: attachMatch && canAttachMatch ? match?.id : nil)
            dismiss()
        } catch {
            errorText = "Der Beitrag konnte nicht gespeichert werden. Versuch es noch einmal."
        }
    }
}
