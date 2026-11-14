import PadelStats
import SwiftUI

// Images for the share sheet (Instagram, WhatsApp, Fotos …). Always dark, always
// light text on dark ground, so they look right wherever they land.

private enum ShareStyle {
    static let width: CGFloat = 360
    static let background = LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.16), .black],
                                           startPoint: .top, endPoint: .bottom)
    static let text = Color.white
    static let muted = Color.white.opacity(0.65)
}

/// Profile as a 4:5 card: photo, name, level, numbers, invitation.
struct ProfileShareCard: View {
    let page: ProfilePage
    var photo: UIImage?

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Label("Pointcheck", systemImage: "tennisball.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ball)
                Spacer()
                Text("PADEL")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(3)
                    .foregroundStyle(ShareStyle.muted)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Text(String(page.displayName.prefix(1)).uppercased())
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(ShareStyle.text)
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(.circle)
            .overlay(Circle().stroke(Theme.ball, lineWidth: 3))

            VStack(spacing: 4) {
                Text(page.displayName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ShareStyle.text)
                if let username = page.username {
                    Text("@\(username)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(ShareStyle.muted)
                }
                if let club = page.homeClub, !club.isEmpty {
                    Label(club, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(ShareStyle.muted)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 0) {
                number(page.level.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", "Level")
                number(page.rating.map { Int($0.rounded()).formatted() } ?? "–", "Punkte")
                number(page.winRate?.percentText ?? "–", "Siegquote")
                number("\(page.ratedMatches ?? 0)", "Matches")
            }
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))

            Spacer(minLength: 0)

            Text("Folge mir in Pointcheck")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Theme.ball, in: .capsule)
        }
        .padding(28)
        .frame(width: ShareStyle.width, height: ShareStyle.width * 1.25)
        .background(ShareStyle.background)
    }

    private func number(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(ShareStyle.text)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(ShareStyle.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Post as a card: author, text, optional photo, optional result.
struct PostShareCard: View {
    let authorName: String
    var authorPhoto: UIImage?
    let text: String
    var photo: UIImage?
    var match: AttachedMatch?
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    if let authorPhoto {
                        Image(uiImage: authorPhoto).resizable().scaledToFill()
                    } else {
                        Text(String(authorName.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(ShareStyle.text)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(ShareStyle.text)
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(ShareStyle.muted)
                }
                Spacer()
                Image(systemName: "tennisball.fill").foregroundStyle(Theme.ball)
            }

            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(ShareStyle.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ShareStyle.width - 56, height: (ShareStyle.width - 56) * 0.75)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
            }

            if let match {
                let tint = match.authorWon ? Theme.me : Theme.opponent
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.authorWon ? "SIEG" : "NIEDERLAGE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5)
                            .foregroundStyle(tint)
                        Text(match.resultText)
                            .font(Theme.scoreFont(size: 24))
                            .foregroundStyle(ShareStyle.text)
                        Text([match.partnerName.map { "mit \($0)" }, match.opponentNames.map { "gegen \($0)" }]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(ShareStyle.muted)
                    }
                    Spacer()
                    Text("\(match.setsWon.me):\(match.setsWon.opponent)")
                        .font(Theme.scoreFont(size: 38))
                        .foregroundStyle(tint)
                }
                .padding(16)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 18, style: .continuous))
            }

            HStack {
                Spacer()
                Text("Pointcheck")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ShareStyle.muted)
            }
        }
        .padding(28)
        .frame(width: ShareStyle.width)
        .background(ShareStyle.background)
    }
}

// MARK: - Rendering

enum ShareRenderer {
    /// Renders a card to an image at 3x.
    @MainActor
    static func image<Content: View>(_ content: Content) -> Image? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }

    /// Downloads an image for embedding in a card (nil on failure).
    static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// Share button that prepares the card (loading photos first) and opens the share sheet.
struct ShareCardButton<Card: View, Label: View>: View {
    let title: String
    let makeCard: () async -> Card
    @ViewBuilder let label: Label
    @State private var image: Image?
    @State private var isPreparing = false

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview(title, image: image)) { label }
            } else {
                Button {
                    Task { await prepare() }
                } label: {
                    if isPreparing { ProgressView() } else { label }
                }
            }
        }
    }

    private func prepare() async {
        isPreparing = true
        let card = await makeCard()
        image = ShareRenderer.image(card)
        isPreparing = false
    }
}
