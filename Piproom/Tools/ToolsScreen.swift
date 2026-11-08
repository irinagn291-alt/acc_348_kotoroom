import SwiftUI
import SafariServices
import UniformTypeIdentifiers

enum DeskTool: String, Hashable {
    case generatePassword, generateNames, checkPassword, checkEmail
    var title: String {
        switch self {
        case .generatePassword: "Password generator"
        case .generateNames: "Email name ideas"
        case .checkPassword: "Check a password"
        case .checkEmail: "Check an email"
        }
    }
    var icon: String {
        switch self {
        case .generatePassword: "key"
        case .generateNames: "at"
        case .checkPassword: "lock.shield"
        case .checkEmail: "envelope.badge"
        }
    }
    var subtitle: String {
        switch self {
        case .generatePassword: "Roll a new password on this iPhone"
        case .generateNames: "Find a name for your next sign-up"
        case .checkPassword: "Look for a password in known leaks"
        case .checkEmail: "Find breaches involving your address"
        }
    }
}

struct ToolsScreen: View {
    var body: some View {
        ToolPage(title: "Tools", folio: "The pocket desk") {
            PaperCard {
                HStack { SmallPrint("01 / Create offline"); Spacer(); Die().frame(width: 32, height: 32) }
                Text("Make something new").font(.system(.title2, design: .serif))
                ForEach([DeskTool.generatePassword, .generateNames], id: \.self) { tool in
                    NavigationLink(value: Page.tool(tool)) {
                        HStack {
                            Image(systemName: tool.icon).frame(width: 25)
                            Text(tool.title).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier(tool.rawValue)
                }
            }
            SmallPrint("02 / Check online").foregroundStyle(Color.faded).padding(.top, 6)
            ForEach([DeskTool.checkPassword, .checkEmail], id: \.self) { tool in
                NavigationLink(value: Page.tool(tool)) {
                    MenuRow(title: tool.title, note: tool.subtitle, icon: tool.icon)
                }.accessibilityIdentifier(tool.rawValue)
                Divider().overlay(Color.faded.opacity(0.35))
            }
        }
    }
}

private struct ToolPage<Content: View>: View {
    let title: String
    let folio: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SmallPrint("KOTOROOM / " + folio).foregroundStyle(Color.faded)
                Text(title).font(.system(.largeTitle, design: .serif).weight(.medium)).accessibilityAddTraits(.isHeader)
                content()
            }.padding(20).frame(maxWidth: 600, alignment: .leading)
        }.frame(maxWidth: .infinity).background(Felt()).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
    }
}

private func copyLocally(_ value: String) {
    UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: value]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
}

struct PasswordMaker: View {
    @State private var recipe = PasswordRecipe()
    @State private var value = ""
    @State private var copied = false
    @Environment(\.scenePhase) private var phase
    #if DEBUG
    init() {
        if StoreCaptureLaunch.isEnabled { _value = State(initialValue: "pR7!mK9#vT4@nW6$yE8+") }
    }
    #endif
    var body: some View {
        ToolPage(title: DeskTool.generatePassword.title, folio: "Offline / 01") {
            PaperCard {
                HStack { SmallPrint("Freshly rolled"); Spacer(); Image(systemName: "die.face.5") }
                Text(verbatim: phase == .active ? value : "••••••••")
                    .font(.system(.title3, design: .monospaced)).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .privacySensitive().accessibilityIdentifier("generatedPassword")
                Button { roll() } label: { PrimaryLabel(text: "Roll password", icon: "dice") }.accessibilityIdentifier("rollPassword")
                Button { copyLocally(value); copied = true } label: {
                    Label(copied ? "Copied" : "Copy password", systemImage: copied ? "checkmark" : "doc.on.doc").frame(minHeight: 44)
                }.disabled(value.isEmpty)
            }
            Stepper("Length: \(recipe.length)", value: $recipe.length, in: PasswordRecipe.lengths)
            Toggle("Include numbers", isOn: $recipe.digits)
            Toggle("Include symbols", isOn: $recipe.symbols)
            Toggle("Exclude similar characters", isOn: $recipe.omitSimilar)
            Divider()
            Text("Checking sends the first five characters of the password hash to Have I Been Pwned.")
                .font(.footnote).foregroundStyle(Color.faded)
            LookupControls(mode: .checkPassword, input: value, buttonTitle: "Check this password")
        }.onAppear { if value.isEmpty { roll() } }
            .onChange(of: recipe) { _, _ in roll() }
            .onChange(of: phase) { _, new in
                if new == .background { value = ""; copied = false }
                if new == .active && value.isEmpty { roll() }
            }
    }
    private func roll() { value = recipe.generate(); copied = false }
}

struct EmailNameMaker: View {
    @State private var seed = ""
    @State private var style = NameStyle.business
    @State private var names = EmailNames.suggestions(base: "", style: .business)
    @State private var choice = 0
    @State private var domainChoice = "Name only"
    @State private var customDomain = ""
    @State private var copied: String?
    private var domain: String? { EmailNames.domain(domainChoice == "Custom" ? customDomain : domainChoice) }

    var body: some View {
        ToolPage(title: DeskTool.generateNames.title, folio: "Offline / 02") {
            TextField("Base name (optional)", text: $seed).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Color.table, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("nameSeed").onSubmit(roll)
            Picker("Style", selection: $style) {
                ForEach(NameStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            PaperCard {
                HStack { SmallPrint("Name ideas"); Spacer(); Image(systemName: "at") }
                ForEach(names.indices, id: \.self) { i in
                    Button { choice = i; copied = nil } label: {
                        HStack {
                            Image(systemName: choice == i ? "checkmark.circle.fill" : "circle")
                            Text(verbatim: names[i]).font(.system(.body, design: .monospaced))
                            Spacer()
                        }.frame(minHeight: 40).contentShape(Rectangle())
                    }.accessibilityAddTraits(choice == i ? .isSelected : [])
                        .accessibilityIdentifier("nameIdea-\(i)")
                }
                Button(action: roll) { PrimaryLabel(text: "Roll names", icon: "dice") }.accessibilityIdentifier("rollNames")
            }
            Picker("Preview domain", selection: $domainChoice) {
                ForEach(["Name only", "gmail.com", "outlook.com", "Custom"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
            if domainChoice == "Custom" {
                TextField("Domain, e.g. example.com", text: $customDomain).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder)
                if !customDomain.isEmpty && domain == nil { Text("Enter a valid domain.").font(.caption) }
            }
            if let domain { Text(verbatim: names[choice] + "@" + domain).font(.system(.body, design: .monospaced)) }
            HStack {
                Button("Copy name") { copyLocally(names[choice]); copied = "Name copied" }.buttonStyle(.bordered)
                if let domain {
                    Button("Copy address") { copyLocally(names[choice] + "@" + domain); copied = "Address copied" }.buttonStyle(.bordered)
                }
            }
            if let copied { Text(copied).font(.caption) }
            Text("These are ideas for signing up. Your email provider checks availability during registration.")
                .font(.footnote).foregroundStyle(Color.faded)
        }.onChange(of: style) { _, _ in roll() }
            .onChange(of: seed) { _, _ in roll() }
            .onChange(of: domainChoice) { _, _ in copied = nil }
            .onChange(of: customDomain) { _, _ in copied = nil }
    }
    private func roll() {
        names = EmailNames.suggestions(base: seed, style: style)
        choice = 0; copied = nil
    }
}

struct BreachScreen: View {
    let mode: DeskTool
    @State private var input = ""
    @State private var website = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ToolPage(title: mode.title, folio: "Breach checks") {
            if mode == .checkEmail && BreachClient.live.emailRelay == nil {
                PaperCard {
                    SmallPrint("Email exposure")
                    Text("Search Have I Been Pwned").font(.system(.title2, design: .serif))
                    Text("Enter your email on the official site to see which known breaches include it.").font(.subheadline)
                    Button { website = true } label: { PrimaryLabel(text: "Open HIBP email search", icon: "safari") }
                        .accessibilityIdentifier("websiteLookup")
                }
            } else {
                Text(mode == .checkPassword ? "Only the first five characters of the password hash are sent to Pwned Passwords. The match is checked on this iPhone."
                     : "Only the first six characters of the email hash are sent through KOTOROOM’s relay. Your iPhone finds the matching breaches.")
                    .font(.subheadline).foregroundStyle(Color.faded)
                Group {
                    if mode == .checkPassword {
                        SecureField("Password to check", text: $input).privacySensitive()
                    } else {
                        TextField("Your email address", text: $input).keyboardType(.emailAddress)
                    }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().padding(14)
                    .background(Color.table, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("lookupInput")
                LookupControls(mode: mode, input: input, buttonTitle: mode == .checkEmail ? "Check email" : "Check password")
                if mode == .checkEmail {
                    Button("Use the official HIBP website") { website = true }.font(.footnote).frame(minHeight: 44)
                }
            }
        }.sheet(isPresented: $website) { HIBPWebsite().ignoresSafeArea() }
            .onChange(of: phase) { _, new in if new == .background { input = "" } }
    }
}

private struct HIBPWebsite: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: BreachClient.website) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private enum LookupOutcome {
    case password(Int), email([Exposure]), failed(String)
}
private struct LookupControls: View {
    let mode: DeskTool
    let input: String
    let buttonTitle: String
    @State private var task: Task<Void, Never>?
    @State private var outcome: LookupOutcome?
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: check) {
                Label(buttonTitle, systemImage: "magnifyingglass").font(.headline)
                    .frame(maxWidth: .infinity).padding(13).foregroundStyle(Color.ink)
                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 12))
            }.disabled(input.isEmpty || task != nil).accessibilityIdentifier("submitLookup")
            if task != nil { ProgressView("Checking…") }
            if let outcome {
                switch outcome {
                case .failed(let message): Label(message, systemImage: "exclamationmark.circle").accessibilityIdentifier("lookupFailed")
                case .password(let count):
                    if count > 0 {
                        Text("Password found in leaks").font(.headline).accessibilityIdentifier("passwordFound")
                        Text("Seen \(count) times in the available data. Replace it wherever you use it and enable two-factor authentication.")
                    } else { noMatch }
                case .email(let breaches):
                    if breaches.isEmpty { noMatch }
                    else {
                        Text("Known breaches: \(breaches.count)").font(.headline)
                        ForEach(breaches) { breach in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: breach.title).bold()
                                if let date = breach.date { Text(verbatim: date).font(.caption.monospacedDigit()) }
                                if !breach.classes.isEmpty { Text(verbatim: breach.classes.joined(separator: ", ")).font(.caption) }
                            }
                        }
                        Text("Change any reused passwords and enable two-factor authentication.")
                    }
                }
            }
            Link("Data from Have I Been Pwned", destination: BreachClient.website).font(.footnote).underline()
        }.font(.subheadline).onChange(of: input) { _, _ in clear() }.onDisappear(perform: clear)
    }
    private var noMatch: some View { Text("No matches found in the available data.").font(.headline).accessibilityIdentifier("noMatch") }
    private func clear() {
        generation = UUID(); task?.cancel(); task = nil; outcome = nil
    }
    private func check() {
        clear()
        let token = generation, value = input
        task = Task { @MainActor in
            defer { if generation == token { task = nil } }
            do {
                let result: LookupOutcome
                if mode == .checkPassword { result = .password(try await BreachClient.live.passwordCount(value)) }
                else { result = .email(try await BreachClient.live.emailBreaches(value)) }
                if !Task.isCancelled && generation == token { outcome = result }
            } catch {
                if !Task.isCancelled && generation == token { outcome = .failed(error.localizedDescription) }
            }
        }
    }
}
