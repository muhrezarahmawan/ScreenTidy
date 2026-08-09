import SwiftUI
import UIKit

// MARK: - Create / Rename collection (WhatsApp-style emoji + name)

struct CollectionEditorSheet: View {
    enum Mode {
        case create
        case rename(ContextCollectionID)

        var title: String {
            switch self {
            case .create: "New Collection"
            case .rename: "Edit Collection"
            }
        }

        var confirmTitle: String {
            switch self {
            case .create: "Create"
            case .rename: "Save"
            }
        }
    }

    let mode: Mode
    var initialTitle: String = ""
    var initialEmoji: String = "📁"
    var initialBadgeColor: String? = nil
    var onCancel: () -> Void
    /// name, emoji, badgeColorHex
    var onSave: (String, String?, String?) async -> Void

    @State private var name: String = ""
    @State private var emoji: String = "📁"
    @State private var badgeColorHex: String = STCollectionBadgePalette.default.hex
    @State private var isSaving = false
    @State private var showBadgeEditor = false
    @FocusState private var nameFocused: Bool

    private let avatarSize: CGFloat = 120

    private var displayEmoji: String {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "📁" : trimmed
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: STSpacing.md) {
                    emojiAvatar
                    Button {
                        showBadgeEditor = true
                    } label: {
                        Text("Edit")
                            .font(STTypography.button)
                            .foregroundStyle(STColor.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit emoji")
                }
                .padding(.top, STSpacing.xxl)

                nameField
                    .padding(.horizontal, STSpacing.page)
                    .padding(.top, STSpacing.xl)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(STColor.background.ignoresSafeArea())
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                .stHideSharedBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmTitle, action: save)
                        .disabled(!canSave)
                }
                .stHideSharedBackground()
            }
            .onAppear {
                name = initialTitle
                emoji = STCollectionEmojiValidator.normalizedSingleEmoji(
                    initialEmoji.isEmpty ? "📁" : initialEmoji
                )
                if emoji.isEmpty { emoji = "📁" }
                badgeColorHex = STCollectionBadgePalette.swatch(forHex: initialBadgeColor).hex
                nameFocused = true
            }
            .fullScreenCover(isPresented: $showBadgeEditor) {
                CollectionBadgeEditorSheet(
                    initialEmoji: emoji,
                    initialColorHex: badgeColorHex,
                    onCancel: { showBadgeEditor = false },
                    onSave: { newEmoji, colorHex in
                        emoji = newEmoji
                        badgeColorHex = colorHex
                        showBadgeEditor = false
                    }
                )
            }
        }
        .presentationBackground(STColor.background)
    }

    private var emojiAvatar: some View {
        Button {
            showBadgeEditor = true
        } label: {
            ZStack {
                Circle()
                    .fill(STCollectionBadgePalette.color(forHex: badgeColorHex))

                Text(displayEmoji)
                    .font(.system(size: avatarSize * 0.42))
                    .minimumScaleFactor(0.5)
                    .accessibilityHidden(true)
            }
            .frame(width: avatarSize, height: avatarSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit collection emoji")
    }

    private var nameField: some View {
        HStack(spacing: STSpacing.sm) {
            TextField("Collection name", text: $name)
                .focused($nameFocused)
                .font(STTypography.search)
                .foregroundStyle(STColor.label)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit {
                    if canSave { save() }
                }

            if !name.isEmpty {
                Button {
                    name = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(STColor.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear name")
            }
        }
        .padding(.horizontal, STSpacing.lg)
        .padding(.vertical, STSpacing.md)
        .background(STColor.pocket)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: STRadius.button, style: .continuous)
                .strokeBorder(STColor.hairline, lineWidth: 0.5)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isSaving else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            isSaving = true
            await onSave(
                trimmedName,
                trimmedEmoji.isEmpty ? nil : trimmedEmoji,
                badgeColorHex
            )
            isSaving = false
        }
    }
}

// MARK: - WhatsApp-style emoji + background editor

struct CollectionBadgeEditorSheet: View {
    var initialEmoji: String
    var initialColorHex: String
    var onCancel: () -> Void
    var onSave: (String, String) -> Void

    @State private var emoji: String = ""
    @State private var emojiDraft: String = ""
    @State private var selectedSwatch: STCollectionBadgePalette.Swatch = STCollectionBadgePalette.default
    @State private var showTextNotSupported = false
    @State private var emojiFieldFocused = false

    private let previewSize: CGFloat = 168

    private var canConfirm: Bool {
        !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: STSpacing.xl)

                ZStack {
                    Circle()
                        .fill(selectedSwatch.color)

                    Text(emoji.isEmpty ? "" : emoji)
                        .font(.system(size: previewSize * 0.42))
                        .minimumScaleFactor(0.5)
                        .allowsHitTesting(false)

                    // UIKit field prefers the system emoji keyboard on focus.
                    STEmojiKeyboardField(
                        text: $emojiDraft,
                        fontSize: previewSize * 0.42,
                        isFocused: emojiFieldFocused
                    )
                    .onChange(of: emojiDraft) { _, newValue in
                        handleEmojiDraftChange(newValue)
                    }
                }
                .frame(width: previewSize, height: previewSize)
                .contentShape(Circle())
                .onTapGesture {
                    emojiFieldFocused = true
                }

                Spacer(minLength: STSpacing.xxl)

                colorPicker
                    .padding(.horizontal, STSpacing.page)
                    .padding(.bottom, STSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(STColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(STColor.label)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(STColor.backgroundSecondary))
                    }
                    .accessibilityLabel("Close")
                }
                .stHideSharedBackground()
                ToolbarItem(placement: .principal) {
                    Text("Emoji")
                        .font(STTypography.button)
                        .foregroundStyle(STColor.label)
                        .padding(.horizontal, STSpacing.lg)
                        .padding(.vertical, STSpacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(STColor.pocket)
                        )
                }
                .stHideSharedBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard canConfirm else { return }
                        onSave(emoji, selectedSwatch.hex)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canConfirm ? Color.white : STColor.tertiaryLabel)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(canConfirm ? STColor.primary : STColor.backgroundSecondary)
                            )
                    }
                    .disabled(!canConfirm)
                    .accessibilityLabel("Save emoji")
                }
                .stHideSharedBackground()
            }
            .alert("Text not supported", isPresented: $showTextNotSupported) {
                Button("OK", role: .cancel) {
                    // Bounce focus so the emoji keyboard comes back after ABC.
                    emojiFieldFocused = false
                    DispatchQueue.main.async {
                        emojiFieldFocused = true
                    }
                }
            } message: {
                Text("Only emoji can be used for the collection icon.")
            }
            .onAppear {
                let seed = STCollectionEmojiValidator.normalizedSingleEmoji(
                    initialEmoji.isEmpty ? "📁" : initialEmoji
                )
                emoji = seed.isEmpty ? "📁" : seed
                emojiDraft = emoji
                selectedSwatch = STCollectionBadgePalette.swatch(forHex: initialColorHex)
                DispatchQueue.main.async {
                    emojiFieldFocused = true
                }
            }
        }
        .presentationBackground(STColor.background)
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text(selectedSwatch.name)
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)

            HStack(spacing: STSpacing.sm) {
                ForEach(STCollectionBadgePalette.swatches) { swatch in
                    Button {
                        selectedSwatch = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if selectedSwatch.id == swatch.id {
                                    Circle()
                                        .strokeBorder(STColor.label.opacity(0.55), lineWidth: 2)
                                        .padding(1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(selectedSwatch.id == swatch.id ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func handleEmojiDraftChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emoji = ""
            emojiDraft = ""
            return
        }
        if STCollectionEmojiValidator.isEmojiOnly(trimmed) {
            let single = STCollectionEmojiValidator.normalizedSingleEmoji(trimmed)
            emoji = single
            if emojiDraft != single {
                emojiDraft = single
            }
            return
        }
        // Revert invalid text and show WhatsApp-style alert.
        emojiDraft = emoji
        showTextNotSupported = true
    }
}

// MARK: - Emoji keyboard (UIKit) — prefers system emoji input mode

/// Prefers the system emoji keyboard when becoming first responder.
private final class STEmojiPreferringTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes where mode.primaryLanguage == "emoji" {
            return mode
        }
        return super.textInputMode
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            reloadInputViews()
        }
        return became
    }
}

/// Invisible caret field that opens the emoji keyboard by default.
private struct STEmojiKeyboardField: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> STEmojiPreferringTextField {
        let field = STEmojiPreferringTextField()
        field.delegate = context.coordinator
        field.text = text
        field.textAlignment = .center
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = UIColor.white.withAlphaComponent(0.85)
        field.font = .systemFont(ofSize: fontSize)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.keyboardType = .default
        field.returnKeyType = .done
        field.accessibilityLabel = "Collection emoji"
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ uiView: STEmojiPreferringTextField, context: Context) {
        context.coordinator.text = $text
        if uiView.text != text {
            uiView.text = text
        }
        if abs((uiView.font?.pointSize ?? 0) - fontSize) > 0.5 {
            uiView.font = .systemFont(ofSize: fontSize)
        }
        if isFocused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - Delete collection dual path

struct DeleteCollectionSheet: View {
    let collectionTitle: String
    let screenshotCount: Int
    var onCancel: () -> Void
    var onDeleteCollectionOnly: () -> Void
    var onDeleteCollectionAndScreenshots: () -> Void

    @State private var confirmPhotosDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: STSpacing.lg) {
                    Text("Delete “\(collectionTitle)”?")
                        .font(STTypography.sectionTitle)
                        .foregroundStyle(STColor.label)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Choose what happens to the screenshots in this collection")
                        .font(STTypography.aiLine)
                        .foregroundStyle(STColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onDeleteCollectionOnly()
                    } label: {
                        VStack(alignment: .leading, spacing: STSpacing.xs) {
                            Text("Delete Collection Only")
                                .font(STTypography.rowTitle)
                                .foregroundStyle(STColor.label)
                            Text(collectionOnlyDescription)
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(STSpacing.lg)
                        .background(STColor.pocket)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        confirmPhotosDelete = true
                    } label: {
                        VStack(alignment: .leading, spacing: STSpacing.xs) {
                            Text("Delete Collection & Remove Screenshots")
                                .font(STTypography.rowTitle)
                                .foregroundStyle(STColor.destructive)
                            Text(photosDeleteDescription)
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(STSpacing.lg)
                        .background(STColor.pocket)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(screenshotCount == 0)
                }
                .padding(STSpacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(STColor.background.ignoresSafeArea())
            .navigationTitle("Delete Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                .stHideSharedBackground()
            }
            .alert(
                "Remove Collection & \(screenshotCount) Screenshots from ScreenTidy?",
                isPresented: $confirmPhotosDelete
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Remove \(screenshotCount) Screenshots", role: .destructive) {
                    onDeleteCollectionAndScreenshots()
                }
            } message: {
                Text("This only removes ScreenTidy metadata. Your Photos library is unchanged. Real Photos deletion is not available in this sprint.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(STColor.background)
    }

    private var collectionOnlyDescription: String {
        if screenshotCount == 1 {
            return "Delete this collection, but keep this screenshot in ScreenTidy (and Photos)"
        }
        return "Delete this collection, but keep all \(screenshotCount) screenshots in ScreenTidy (and Photos)"
    }

    private var photosDeleteDescription: String {
        if screenshotCount == 1 {
            return "Delete this collection and remove this screenshot from ScreenTidy only — Photos is unchanged"
        }
        return "Delete this collection and remove all \(screenshotCount) screenshots from ScreenTidy only — Photos is unchanged"
    }
}

// MARK: - Collection assignment picker (Move / Add)

enum CollectionAssignmentMode: Equatable {
    /// Exclusive reassignment — all prior memberships replaced.
    case move
    /// Additive membership — keeps other Collections.
    case add
}

struct MoveScreenshotsSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    /// Current gallery Collection when known (excluded from Move destinations). Nil from Search.
    let sourceContextID: ContextCollectionID?
    let screenshotIDs: Set<ScreenshotMemoryID>
    var mode: CollectionAssignmentMode = .move
    var onFinished: (_ destinationTitle: String, _ undoToken: MockUndoToken) -> Void
    var onCancel: () -> Void

    @State private var destinations: [ContextCollection] = []
    @State private var showNewCollection = false
    @State private var isWorking = false

    private var navigationTitle: String {
        let count = screenshotIDs.count
        switch mode {
        case .move:
            return count == 1 ? "Move Screenshot" : "Move \(count) Screenshots"
        case .add:
            return count == 1 ? "Add to Collection" : "Add \(count) to Collection"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if destinations.isEmpty {
                        Text(mode == .add ? "No other Collections to add to." : "No Collections available.")
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                    } else {
                        ForEach(destinations) { context in
                            Button {
                                Task { await assign(to: context) }
                            } label: {
                                HStack(spacing: STSpacing.md) {
                                    Text(context.kind == .unassigned ? "✨" : (context.badgeEmoji ?? "📁"))
                                    Text(STNeedsReviewCopy.displayTitle(for: context))
                                        .foregroundStyle(STColor.label)
                                    Spacer()
                                    Text("\(context.memberCount)")
                                        .font(STTypography.rowMeta)
                                        .foregroundStyle(STColor.secondaryLabel)
                                }
                            }
                        }
                    }
                }

                if mode == .move {
                    Section {
                        Button {
                            showNewCollection = true
                        } label: {
                            Label("New Collection", systemImage: "plus")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(STColor.background.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                .stHideSharedBackground()
            }
            .task { await reload() }
            .sheet(isPresented: $showNewCollection) {
                CollectionEditorSheet(
                    mode: .create,
                    onCancel: { showNewCollection = false },
                    onSave: { title, emoji, badgeColor in
                        do {
                            let created = try await dependencies.memoryStore.createContext(
                                title: title,
                                badgeEmoji: emoji,
                                badgeColor: badgeColor
                            )
                            showNewCollection = false
                            await assign(to: created)
                        } catch {
                            AppLog.ui.error(
                                "Create collection failed: \(error.localizedDescription, privacy: .public)"
                            )
                            showNewCollection = false
                        }
                    }
                )
                .presentationBackground(STColor.background)
            }
            .disabled(isWorking)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(STColor.background)
    }

    private func reload() async {
        switch mode {
        case .move:
            destinations = (try? await dependencies.memoryStore.fetchContextsForPicker(
                excluding: sourceContextID
            )) ?? []
        case .add:
            destinations = (try? await dependencies.memoryStore.fetchContextsForAddPicker(
                screenshotIDs: screenshotIDs,
                excluding: sourceContextID
            )) ?? []
        }
    }

    private func assign(to destination: ContextCollection) async {
        isWorking = true
        do {
            let token: MockUndoToken
            switch mode {
            case .move:
                token = try await dependencies.memoryStore.moveScreenshots(
                    ids: screenshotIDs,
                    to: destination.id
                )
            case .add:
                token = try await dependencies.memoryStore.addScreenshots(
                    ids: screenshotIDs,
                    to: destination.id
                )
            }
            isWorking = false
            onFinished(STNeedsReviewCopy.displayTitle(for: destination), token)
        } catch {
            isWorking = false
            AppLog.ui.error(
                "Collection assignment failed: \(error.localizedDescription, privacy: .public)"
            )
            dependencies.feedback.show("Couldn’t update Collections", style: .error)
        }
    }
}
