import PadelStats
import PhotosUI
import SwiftUI

/// Write a post, Threads-style: avatar with a thread line, free text, photo and
/// the result as a small card. Tools live in a bar above the keyboard.
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
    @FocusState private var focused: Bool
    @State private var posted = 0

    private let limit = 500

    private var canAttachMatch: Bool {
        guard let match else { return false }
        return account.uploads[match.id] != nil || account.foreignIDs.contains(match.id)
    }

    /// A placeholder that changes per sheet, so the field never feels like a template.
    private let promptIndex = Int.random(in: 0..<3)
    private var prompt: String { prompts[promptIndex % prompts.count] }

    private var prompts: [String] {
        if let match {
            return match.winner == .me
                ? ["Wie lief der Sieg?", "Was hat heute den Unterschied gemacht?"]
                : ["Was nimmst du aus dem Match mit?", "Nächstes Mal …"]
        }
        return ["Was gibt's vom Platz?", "Wen suchst du fürs nächste Match?", "Dein bester Punkt diese Woche?"]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 6) {
                            ProfilePhoto(name: account.profile?.displayName ?? "",
                                         url: account.imageURL(account.profile?.avatarPath, bucket: .avatars), size: 42)
                            Rectangle().fill(Theme.hairline).frame(width: 2)
                                .frame(maxHeight: .infinity)
                            Image(systemName: "tennisball.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.lime)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(account.profile?.displayName ?? "")
                                .font(.subheadline.weight(.semibold))
                            TextField(prompt, text: $text, axis: .vertical)
                                .font(.body)
                                .lineLimit(3...12)
                                .focused($focused)
                                .onChange(of: text) { _, new in
                                    if new.count > limit { text = String(new.prefix(limit)) }
                                }

                            if let photoPreview {
                                photoPreview.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(4 / 3, contentMode: .fill)
                                    .clipShape(.rect(cornerRadius: Theme.Radius.inner, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            withAnimation(.snappy) { photoItem = nil; photoData = nil; self.photoPreview = nil }
                                        } label: {
                                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                                .padding(8).background(.black.opacity(0.55), in: .circle)
                                        }
                                        .padding(8)
                                        .accessibilityLabel("Foto entfernen")
                                    }
                                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }

                            if let match, attachMatch, canAttachMatch {
                                attachedResult(match)
                                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }

                            if let match, !canAttachMatch {
                                FormNote(text: "Trag das Match zuerst unter „Spielstärke“ ein, dann kannst du das Ergebnis \(match.resultText) anhängen.")
                            }

                            if let errorText {
                                FormError(text: errorText)
                            }
                        }
                    }
                    .padding(Theme.Spacing.page)
                    .animation(.snappy, value: attachMatch)
                    .animation(.snappy, value: photoPreview == nil)
                }
                .scrollDismissesKeyboard(.interactively)

                toolbar
            }
            .background(Theme.background)
            .navigationTitle("Neuer Beitrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .onChange(of: photoItem) { _, item in Task { await loadPhoto(item) } }
            .ballDrop(trigger: posted)
            .onAppear {
                attachMatch = canAttachMatch
                focused = true
            }
        }
    }

    /// Photo, result toggle, counter and the lime post button.
    private var toolbar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: photoPreview == nil ? "photo" : "photo.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Theme.surfaceRaised, in: .circle)
                }
                .buttonStyle(.pressScale)
                .foregroundStyle(photoPreview == nil ? Color.primary : Theme.lime)
                .accessibilityLabel(photoPreview == nil ? "Foto hinzufügen" : "Anderes Foto")

                if match != nil {
                    Button {
                        withAnimation(.snappy) { attachMatch.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tennisball.fill")
                            Text("Ergebnis")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(attachMatch && canAttachMatch ? Theme.onAccent : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(attachMatch && canAttachMatch ? Theme.lime : Theme.surfaceRaised, in: .capsule)
                    }
                    .buttonStyle(.pressScale)
                    .disabled(!canAttachMatch)
                    .opacity(canAttachMatch ? 1 : 0.4)
                    .accessibilityLabel(attachMatch ? "Ergebnis nicht anhängen" : "Ergebnis anhängen")
                }

                Spacer()

                Text("\(limit - text.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(limit - text.count < 40 ? Theme.opponent : .tertiary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: text.count)

                Button {
                    Task { await post() }
                } label: {
                    HStack(spacing: 8) {
                        if isPosting { BallLoader(size: 12) }
                        Text("Posten").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Theme.accent, in: .capsule)
                }
                .buttonStyle(.pressScale)
                .disabled(isPosting || !hasContent)
                .opacity(hasContent ? 1 : 0.4)
                .animation(.snappy, value: hasContent)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
    }

    /// Compact result card inside the post.
    private func attachedResult(_ match: MatchSummary) -> some View {
        let won = match.winner == .me
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(won ? "SIEG" : "NIEDERLAGE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.4)
                    .foregroundStyle(won ? Theme.lime : Theme.opponent)
                Text(match.resultText)
                    .font(Theme.scoreFont(size: 22))
                Text(match.startDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                .font(Theme.scoreFont(size: 34))
                .foregroundStyle(won ? Theme.lime : Theme.opponent)
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.inner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil || (attachMatch && canAttachMatch)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photoData = image.resizedJPEG(maxSide: 1600, quality: 0.82)
        if let photoData, let preview = UIImage(data: photoData) {
            withAnimation(.snappy) { photoPreview = Image(uiImage: preview) }
        }
    }

    private func post() async {
        isPosting = true
        errorText = nil
        defer { isPosting = false }
        do {
            try await account.createPost(text: text, image: photoData, matchID: attachMatch && canAttachMatch ? match?.id : nil)
            posted += 1
            focused = false
            try? await Task.sleep(for: .milliseconds(850))
            dismiss()
        } catch {
            errorText = "Der Beitrag konnte nicht gespeichert werden. Versuch es noch einmal."
        }
    }
}
