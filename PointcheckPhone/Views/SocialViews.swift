import PadelStats
import SwiftUI

// MARK: - 👏 and comments under a post / match

/// Clap button with count and a comment button, like the row under an Instagram post.
struct SocialBar: View {
    /// Post id for claps/comments, or nil for a bare match.
    var postID: UUID?
    /// Match id for comments on a confirmed match without a post.
    var matchID: UUID?
    @Environment(AccountService.self) private var account
    @State private var showsComments = false
    @State private var showsReactors = false
    @State private var bounce = 0

    private var target: UUID? { postID ?? matchID }
    private var summary: ReactionSummary? { postID.flatMap { account.reactions[$0] } }
    private var commentCount: Int { target.flatMap { account.commentCounts[$0] } ?? 0 }

    var body: some View {
        HStack(spacing: 18) {
            if let postID {
                Button {
                    bounce += 1
                    Task { await account.toggleClap(postID) }
                } label: {
                    HStack(spacing: 6) {
                        Text("👏")
                            .font(.system(size: 20))
                            .scaleEffect(summary?.clapped == true ? 1.1 : 1)
                            .keyframeAnimator(initialValue: 1.0, trigger: bounce) { view, scale in
                                view.scaleEffect(scale)
                            } keyframes: { _ in
                                SpringKeyframe(1.35, duration: 0.12)
                                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                            }
                        if let summary, summary.claps > 0 {
                            Text(summary.claps.formatted())
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .contentTransition(.numericText())
                                .foregroundStyle(summary.clapped ? Color.primary : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: bounce)
                .accessibilityLabel(summary?.clapped == true ? "Applaus zurücknehmen" : "Applaudieren")
                .simultaneousGesture(LongPressGesture().onEnded { _ in showsReactors = true })
            }

            Button {
                showsComments = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18, weight: .medium))
                    if commentCount > 0 {
                        Text(commentCount.formatted())
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kommentare")

            Spacer()
        }
        .animation(.snappy, value: summary)
        .sheet(isPresented: $showsComments) {
            CommentsSheet(postID: postID, matchID: matchID)
        }
        .sheet(isPresented: $showsReactors) {
            if let postID { ReactorsSheet(postID: postID) }
        }
    }
}

/// Comments with an input bar at the bottom.
struct CommentsSheet: View {
    var postID: UUID?
    var matchID: UUID?
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var text = ""
    @State private var isLoading = true
    @State private var isSending = false
    @FocusState private var focused: Bool

    private var target: UUID? { postID ?? matchID }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if isLoading && comments.isEmpty {
                                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                            } else if comments.isEmpty {
                                EmptyState(symbol: "bubble.right", title: "Noch keine Kommentare",
                                           message: "Schreib den ersten.")
                            } else {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment, canDelete: comment.authorID == account.userID) {
                                        Task {
                                            if let target { try? await account.deleteComment(comment.id, target: target) }
                                            comments.removeAll { $0.id == comment.id }
                                        }
                                    }
                                    .id(comment.id)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: comments.count) { _, _ in
                        if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    ProfilePhoto(name: account.profile?.displayName ?? "", url: account.imageURL(account.profile?.avatarPath, bucket: .avatars), size: 32)
                    TextField("Kommentar schreiben …", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Senden")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.background)
            }
            .background(Theme.background)
            .navigationTitle("Kommentare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .task {
                comments = await account.comments(post: postID, match: matchID)
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func send() async {
        let value = text
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await account.addComment(value, post: postID, match: matchID)
            text = ""
            comments = await account.comments(post: postID, match: matchID)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            // keep the text so nothing is lost
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(AccountService.self) private var account

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: comment.authorID) {
                ProfilePhoto(name: comment.authorName, url: account.imageURL(comment.authorAvatar, bucket: .avatars), size: 36)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.authorName).font(.subheadline.weight(.semibold))
                    Text(comment.createdAt.relativeShort).font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.text).font(.body).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contextMenu {
            if canDelete {
                Button("Kommentar löschen", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}

/// Who clapped.
struct ReactorsSheet: View {
    let postID: UUID
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var people: [PersonRow] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if people.isEmpty {
                    EmptyState(symbol: "hands.clap", title: "Noch kein Applaus", message: "Sei der Erste.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RowDivider(inset: 72) }
                            PersonListRow(person: person)
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Applaus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .task { people = await account.reactors(of: postID) }
            .profileNavigation()
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Mentions

/// Linked players of a match as tappable chips ("mit Lena · gegen Max & Tom").
struct MentionsRow: View {
    let players: [MentionedPlayer]
    let authorSide: String?

    private var partner: [MentionedPlayer] { players.filter { $0.side == authorSide } }
    private var opponents: [MentionedPlayer] { players.filter { $0.side != authorSide } }

    var body: some View {
        if !players.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(partner.filter { $0.slot != 1 }, id: \.stableID) { chip($0, prefix: "mit") }
                    ForEach(opponents, id: \.stableID) { chip($0, prefix: "vs.") }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ player: MentionedPlayer, prefix: String) -> some View {
        let label = HStack(spacing: 4) {
            Text(prefix).foregroundStyle(.secondary)
            Text(player.name ?? "Gast").fontWeight(.semibold)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface, in: .capsule)

        if let id = player.id {
            NavigationLink(value: id) { label }.buttonStyle(.pressScale)
        } else {
            label
        }
    }
}
