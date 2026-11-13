import SwiftUI

/// First screen of the app. Nothing else is reachable until the person is signed in.
/// Sign in with e-mail + password, or register with name, e-mail + password.
struct WelcomeView: View {
    @Environment(AccountService.self) private var account
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var appeared = false
    @FocusState private var focus: Field?

    enum Field { case name, email, password }

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Anmelden", register = "Registrieren"
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            WelcomeBackground()
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    card
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 48)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
        .animation(.snappy, value: mode)
        .animation(.snappy, value: errorText)
        .animation(.snappy, value: infoText)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            WelcomeBall()
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text("Pointcheck")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Zähl auf der Watch. Teile vom Handy.\nSpiel um deine Spielstärke.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 14) {
            modePicker

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .register ? "Konto erstellen" : "Willkommen zurück")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(mode == .register ? "Dauert eine halbe Minute." : "Schön, dass du wieder da bist.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if mode == .register {
                WelcomeField(placeholder: "Dein Name", text: $name, symbol: "person", field: .name, focus: $focus)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            WelcomeField(placeholder: "E-Mail-Adresse", text: $email, symbol: "envelope", field: .email, focus: $focus)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
            WelcomeField(placeholder: mode == .register ? "Passwort (mind. 8 Zeichen)" : "Passwort",
                         text: $password, symbol: "lock", field: .password, focus: $focus,
                         isSecure: !showsPassword, onToggleSecure: { showsPassword.toggle() })
                .textContentType(mode == .register ? .newPassword : .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }

            if let errorText {
                WelcomeNotice(text: errorText, isError: true)
            }
            if let infoText {
                WelcomeNotice(text: infoText, isError: false)
            }

            WelcomePrimaryButton(title: mode == .register ? "Konto erstellen" : "Anmelden",
                                 enabled: canSubmit, isWorking: isWorking) {
                Task { await submit() }
            }

            HStack {
                if mode == .signIn {
                    Button("Passwort vergessen?") { Task { await forgotPassword() } }
                        .disabled(!(email.contains("@") && email.contains(".")) || isWorking)
                }
                Spacer()
                Button(mode == .register ? "Schon ein Konto? Anmelden" : "Neu hier? Registrieren") {
                    mode = mode == .register ? .signIn : .register
                    errorText = nil
                    infoText = nil
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
    }

    private var canSubmit: Bool {
        let validEmail = email.contains("@") && email.contains(".")
        let validPassword = password.count >= (mode == .register ? 8 : 1)
        let validName = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return validEmail && validPassword && validName
    }

    /// "Anmelden | Registrieren" switch in the card's own style.
    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { value in
                let selected = value == mode
                Button {
                    mode = value
                    errorText = nil
                    infoText = nil
                } label: {
                    Text(value.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .black : .white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background { if selected { Capsule().fill(Theme.ball.gradient) } }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.white.opacity(0.1), in: .capsule)
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var footer: some View {
        Text("Dein Profil ist zunächst privat – du entscheidest, wer dir folgen darf.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func submit() async {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        errorText = nil
        infoText = nil
        focus = nil
        defer { isWorking = false }
        do {
            if mode == .register {
                try await account.register(email: email, password: password, displayName: name)
            } else {
                try await account.signIn(email: email, password: password)
            }
        } catch let error as AccountService.SignInError {
            errorText = error.localizedDescription
        } catch {
            errorText = "Das hat nicht geklappt. Prüf deine Internetverbindung und versuch es noch einmal."
        }
    }

    private func forgotPassword() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await account.requestPasswordReset(email: email)
            infoText = "Wir haben dir eine E-Mail geschickt. Tipp auf den Link darin, dann kannst du hier ein neues Passwort setzen."
        } catch {
            errorText = "Die E-Mail konnte nicht gesendet werden. Prüf die Adresse und versuch es gleich noch einmal."
        }
    }
}

// MARK: - New password (after the reset link)

struct NewPasswordView: View {
    @Environment(AccountService.self) private var account
    @State private var password = ""
    @State private var repeated = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var errorText: String?
    @FocusState private var focus: WelcomeView.Field?

    private var canSave: Bool { password.count >= 8 && password == repeated }

    var body: some View {
        ZStack {
            WelcomeBackground()
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        WelcomeBall()
                        Text("Neues Passwort")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Wähle ein Passwort mit mindestens 8 Zeichen.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    VStack(spacing: 14) {
                        WelcomeField(placeholder: "Neues Passwort", text: $password, symbol: "lock", field: .password, focus: $focus,
                                     isSecure: !showsPassword, onToggleSecure: { showsPassword.toggle() })
                            .textContentType(.newPassword)
                        WelcomeField(placeholder: "Passwort wiederholen", text: $repeated, symbol: "lock", field: .name, focus: $focus,
                                     isSecure: !showsPassword)
                            .textContentType(.newPassword)
                        if let errorText {
                            WelcomeNotice(text: errorText, isError: true)
                        } else if !repeated.isEmpty, password != repeated {
                            WelcomeNotice(text: "Die Passwörter stimmen nicht überein.", isError: true)
                        }
                        WelcomePrimaryButton(title: "Passwort speichern", enabled: canSave, isWorking: isWorking) {
                            Task { await save() }
                        }
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focus = .password }
    }

    private func save() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await account.setNewPassword(password)
        } catch let error as AccountService.SignInError {
            errorText = error.localizedDescription
        } catch {
            errorText = "Das Passwort konnte nicht gespeichert werden. Fordere bei Bedarf einen neuen Link an."
        }
    }
}

// MARK: - Shared pieces

struct WelcomeBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Theme.me.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.opponent.opacity(0.35), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()
            GeometryReader { proxy in
                Path { path in
                    let w = proxy.size.width, h = proxy.size.height
                    path.move(to: CGPoint(x: 0, y: h * 0.62)); path.addLine(to: CGPoint(x: w, y: h * 0.62))
                    path.move(to: CGPoint(x: w / 2, y: h * 0.62)); path.addLine(to: CGPoint(x: w / 2, y: h))
                }
                .stroke(.white.opacity(0.08), lineWidth: 2)
            }
            .ignoresSafeArea()
        }
    }
}

struct WelcomeBall: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.ball.gradient)
                .frame(width: 92, height: 92)
                .shadow(color: Theme.ball.opacity(0.5), radius: 24, y: 8)
            Image(systemName: "tennisball.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .accessibilityHidden(true)
    }
}

struct WelcomeField: View {
    let placeholder: String
    @Binding var text: String
    let symbol: String
    let field: WelcomeView.Field
    var focus: FocusState<WelcomeView.Field?>.Binding
    var isSecure = false
    var onToggleSecure: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                }
            }
            .foregroundStyle(.white)
            .focused(focus, equals: field)
            if let onToggleSecure {
                Button(action: onToggleSecure) {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSecure ? "Passwort anzeigen" : "Passwort verbergen")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focus.wrappedValue == field ? Theme.ball.opacity(0.8) : .white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct WelcomePrimaryButton: View {
    let title: String
    let enabled: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.black) }
                Text(title).font(.headline)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.ball.gradient, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isWorking)
        .opacity(enabled ? 1 : 0.5)
        .sensoryFeedback(.impact(weight: .light), trigger: isWorking)
    }
}

struct WelcomeNotice: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(isError ? Theme.opponent : Theme.me)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
    }
}
