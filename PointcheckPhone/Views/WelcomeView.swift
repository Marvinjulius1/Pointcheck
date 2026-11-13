import SwiftUI

/// First screen of the app. Nothing else is reachable until the person is signed in.
/// Minimal, in the app's own style: system background, one card, one button.
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
    @FocusState private var focus: Field?

    enum Field { case name, email, password, repeated }

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Anmelden", register = "Registrieren"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in errorText = nil; infoText = nil }

                form

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

                if mode == .signIn {
                    Button("Passwort vergessen?") { Task { await forgotPassword() } }
                        .font(.subheadline.weight(.medium))
                        .disabled(!(email.contains("@") && email.contains(".")) || isWorking)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .animation(.snappy, value: mode)
        .animation(.snappy, value: errorText)
        .animation(.snappy, value: infoText)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "tennisball.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.ball)
                .frame(width: 64, height: 64)
                .background(Theme.surface, in: .rect(cornerRadius: 18, style: .continuous))
            Text("Pointcheck")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(mode == .register ? "Erstelle dein Konto." : "Schön, dass du wieder da bist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var form: some View {
        Card {
            if mode == .register {
                WelcomeField(placeholder: "Name", text: $name, symbol: "person", field: .name, focus: $focus)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                RowDivider(inset: 50)
            }
            WelcomeField(placeholder: "E-Mail-Adresse", text: $email, symbol: "envelope", field: .email, focus: $focus)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focus = .password }
            RowDivider(inset: 50)
            WelcomeField(placeholder: mode == .register ? "Passwort (mind. 8 Zeichen)" : "Passwort",
                         text: $password, symbol: "lock", field: .password, focus: $focus,
                         isSecure: !showsPassword, onToggleSecure: { showsPassword.toggle() })
                .textContentType(mode == .register ? .newPassword : .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
        }
    }

    private var canSubmit: Bool {
        let validEmail = email.contains("@") && email.contains(".")
        let validPassword = password.count >= (mode == .register ? 8 : 1)
        let validName = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return validEmail && validPassword && validName
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
            infoText = "E-Mail ist unterwegs. Tipp auf den Link darin, dann kannst du ein neues Passwort setzen."
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
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.me)
                        .frame(width: 64, height: 64)
                        .background(Theme.surface, in: .rect(cornerRadius: 18, style: .continuous))
                    Text("Neues Passwort")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Mindestens 8 Zeichen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Card {
                    WelcomeField(placeholder: "Neues Passwort", text: $password, symbol: "lock", field: .password, focus: $focus,
                                 isSecure: !showsPassword, onToggleSecure: { showsPassword.toggle() })
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .onSubmit { focus = .repeated }
                    RowDivider(inset: 50)
                    WelcomeField(placeholder: "Passwort wiederholen", text: $repeated, symbol: "lock", field: .repeated, focus: $focus,
                                 isSecure: !showsPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .onSubmit { Task { await save() } }
                }
                if let errorText {
                    WelcomeNotice(text: errorText, isError: true)
                } else if !repeated.isEmpty, password != repeated {
                    WelcomeNotice(text: "Die Passwörter stimmen nicht überein.", isError: true)
                }
                WelcomePrimaryButton(title: "Passwort speichern", enabled: canSave, isWorking: isWorking) {
                    Task { await save() }
                }
                Button("Abbrechen") { Task { await account.cancelPasswordReset() } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
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

// MARK: - Pieces

struct WelcomeField: View {
    let placeholder: String
    @Binding var text: String
    let symbol: String
    let field: WelcomeView.Field
    var focus: FocusState<WelcomeView.Field?>.Binding
    var isSecure = false
    var onToggleSecure: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(focus.wrappedValue == field ? Theme.me : .secondary)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .focused(focus, equals: field)
            if let onToggleSecure {
                Button(action: onToggleSecure) {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSecure ? "Passwort anzeigen" : "Passwort verbergen")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(.rect)
        .onTapGesture { focus.wrappedValue = field }
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
                if isWorking { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.me.gradient, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isWorking)
        .opacity(enabled ? 1 : 0.45)
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

// MARK: - Change password (settings)

struct ChangePasswordSheet: View {
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var saved = false
    @FocusState private var focus: WelcomeView.Field?

    private var canSave: Bool { password.count >= 8 && password == repeated }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Card {
                        WelcomeField(placeholder: "Neues Passwort (mind. 8 Zeichen)", text: $password, symbol: "lock",
                                     field: .password, focus: $focus,
                                     isSecure: !showsPassword, onToggleSecure: { showsPassword.toggle() })
                            .textContentType(.newPassword)
                            .submitLabel(.next)
                            .onSubmit { focus = .repeated }
                        RowDivider(inset: 50)
                        WelcomeField(placeholder: "Passwort wiederholen", text: $repeated, symbol: "lock",
                                     field: .repeated, focus: $focus, isSecure: !showsPassword)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .onSubmit { Task { await save() } }
                    }
                    if let errorText {
                        WelcomeNotice(text: errorText, isError: true)
                    } else if !repeated.isEmpty, password != repeated {
                        WelcomeNotice(text: "Die Passwörter stimmen nicht überein.", isError: true)
                    } else if saved {
                        WelcomeNotice(text: "Passwort geändert.", isError: false)
                    }
                    WelcomePrimaryButton(title: "Passwort speichern", enabled: canSave && !saved, isWorking: isWorking) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Passwort ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(saved ? "Fertig" : "Abbrechen") { dismiss() } }
            }
            .onAppear { focus = .password }
        }
    }

    private func save() async {
        guard canSave, !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await account.updatePassword(password)
            saved = true
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        } catch let error as AccountService.SignInError {
            errorText = error.localizedDescription
        } catch {
            errorText = "Das Passwort konnte nicht geändert werden. Versuch es noch einmal."
        }
    }
}
