import SwiftUI

/// First screen of the app. Nothing else is reachable until the person is signed in.
/// Step 1: name + e-mail → step 2: six-digit code from the e-mail.
struct WelcomeView: View {
    @Environment(AccountService.self) private var account
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var appeared = false
    @State private var mode: Mode = .signIn
    @FocusState private var focus: Field?

    private enum Field { case name, email, code }

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Anmelden", register = "Registrieren"
        var id: Self { self }
    }

    private var awaitingCode: String? {
        if case .awaitingCode(let email) = account.state { return email }
        return nil
    }

    var body: some View {
        ZStack {
            background
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
        .animation(.snappy, value: awaitingCode)
        .animation(.snappy, value: errorText)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Theme.me.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.opponent.opacity(0.35), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()
            // faint court lines
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

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.ball.gradient)
                    .frame(width: 92, height: 92)
                    .shadow(color: Theme.ball.opacity(0.5), radius: 24, y: 8)
                Image(systemName: "tennisball.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
            }
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
        VStack(spacing: 16) {
            if let awaitingCode {
                codeStep(email: awaitingCode)
            } else {
                signInStep
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
    }

    private var signInStep: some View {
        VStack(spacing: 14) {
            modePicker

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .register ? "Konto erstellen" : "Willkommen zurück")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Kein Passwort. Du bekommst einen Code per E-Mail.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if mode == .register {
                field("Dein Name", text: $name, symbol: "person", focused: .name)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            field("E-Mail-Adresse", text: $email, symbol: "envelope", focused: .email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await sendCode() } }

            if let errorText {
                errorLabel(errorText)
            }

            primaryButton(mode == .register ? "Registrieren" : "Anmelden", enabled: canSend) {
                Task { await sendCode() }
            }

            Button(mode == .register ? "Schon ein Konto? Anmelden" : "Neu hier? Konto erstellen") {
                withAnimation(.snappy) { mode = mode == .register ? .signIn : .register }
                errorText = nil
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .animation(.snappy, value: mode)
    }

    private var canSend: Bool {
        let validEmail = email.contains("@") && email.contains(".")
        return mode == .register ? validEmail && !name.trimmingCharacters(in: .whitespaces).isEmpty : validEmail
    }

    /// "Anmelden | Registrieren" switch in the card's own style.
    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { value in
                let selected = value == mode
                Button {
                    withAnimation(.snappy) { mode = value }
                    errorText = nil
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

    private func codeStep(email: String) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Code eingeben")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Wir haben einen 6-stelligen Code an \(email) geschickt. Schau auch im Spam-Ordner nach.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CodeBoxes(code: code, isFocused: focus == .code)
                .overlay {
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focus, equals: .code)
                        .opacity(0.02)
                        .onChange(of: code) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { code = digits }
                            if digits.count == 6 { Task { await verify() } }
                        }
                }
                .onTapGesture { focus = .code }
                .onAppear { focus = .code }

            if let errorText {
                errorLabel(errorText)
            }

            primaryButton("Anmelden", enabled: code.count == 6) { Task { await verify() } }

            Button("Andere E-Mail-Adresse") {
                code = ""
                errorText = nil
                account.cancelCode()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: Pieces

    private func field(_ placeholder: String, text: Binding<String>, symbol: String, focused: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                .foregroundStyle(.white)
                .focused($focus, equals: focused)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focus == focused ? Theme.ball.opacity(0.8) : .white.opacity(0.12), lineWidth: 1)
        )
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(Theme.opponent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    private var footer: some View {
        Text("Mit der Anmeldung erstellst du ein Pointcheck-Konto. Dein Profil ist zunächst privat – du entscheidest, wer dir folgen darf.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func sendCode() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        focus = nil
        defer { isWorking = false }
        do {
            try await account.sendCode(email: email, displayName: name, createAccount: mode == .register)
            code = ""
        } catch let error as AccountService.SignInError {
            errorText = error.localizedDescription
        } catch {
            errorText = "Der Code konnte nicht gesendet werden. Prüf die Adresse und versuch es in ein paar Minuten erneut."
        }
    }

    private func verify() async {
        guard !isWorking, code.count == 6 else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await account.verify(code: code)
        } catch {
            errorText = "Der Code stimmt nicht oder ist abgelaufen. Fordere bei Bedarf einen neuen an."
            code = ""
        }
    }
}

/// Six boxes showing the typed digits.
private struct CodeBoxes: View {
    let code: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let digit = index < code.count ? String(code[code.index(code.startIndex, offsetBy: index)]) : ""
                let active = isFocused && index == min(code.count, 5)
                Text(digit)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(active ? Theme.ball.opacity(0.9) : .white.opacity(0.12), lineWidth: active ? 2 : 1)
                    )
                    .contentTransition(.numericText())
            }
        }
        .animation(.snappy, value: code)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code, \(code.count) von 6 Ziffern eingegeben")
    }
}
