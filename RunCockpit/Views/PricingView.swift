import SwiftUI

struct PricingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @State private var newAliasName = ""

    private let builtinAliases = ["fable", "sonnet", "haiku", "opus"]
    private let nonCalculable: [(alias: String, reason: String)] = [
        ("opusplan", "bimodal"),
        ("best", "provider-conditional"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(theme.bg)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(app.t("Model pricing")).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            Button { app.resetPricing() } label: {
                Text(app.t("Reset to defaults"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 54)
        .padding(.horizontal, 28)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(.init(app.t("Prices in dollars per million tokens. Costs for all sessions are recalculated instantly. Saved to ~/Library/Application Support/RunCockpit/pricing.json. Reference: [official Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing).")))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text2)
                    .lineSpacing(3)
                    .padding(.bottom, 20)

                table

                footerNote

                aliasSection
            }
            .frame(maxWidth: 840, alignment: .leading)
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            let keys = app.pricing.profiles.keys.sorted()
            ForEach(keys, id: \.self) { key in
                row(key)
                theme.border2.frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(app.t("Model"))
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            headerCell(app.t("Input"))
            headerCell(app.t("Output"))
            headerCell(app.t("5 min cache"))
            headerCell(app.t("1 h cache"))
            headerCell(app.t("Cache read"))
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(theme.bg2)
        .overlay(alignment: .bottom) { theme.border.frame(height: 1) }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func row(_ key: String) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.pricing.profiles[key]?.label ?? key)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(key)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.text3)
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            .padding(12)

            numericCell(bInput(key))
            numericCell(bOutput(key))
            numericCell(bCw5m(key))
            numericCell(bCw1h(key))
            numericCell(bRead(key))
        }
    }

    private func numericCell(_ binding: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text("$").font(.system(size: 11)).foregroundStyle(theme.text3)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 62)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg2))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 10)
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Tag(text: app.t("missing price"), fg: theme.stIdle, bg: theme.stIdleSoft, size: 10.5)
            Text(app.t("An unknown model is billed at 0 and flagged with this badge until configured. 1M aliases (e.g. opus-4-8[1m]) are mapped to the base profile."))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text2)
                .lineSpacing(2)
        }
        .padding(.top, 16)
    }

    // MARK: - Alias section

    private var aliasSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("Model aliases"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 6)
            Text(app.t("Claude Code aliases are resolved to a concrete model when a session closes. The resolved model is used for cost calculation."))
                .font(.system(size: 12.5))
                .foregroundStyle(theme.text2)
                .lineSpacing(3)
                .padding(.bottom, 16)

            aliasTable
        }
        .padding(.top, 32)
    }

    private var aliasTable: some View {
        let modelOptions = app.pricing.profiles.keys.sorted()
        let customAliases = app.pricing.aliasMap.keys
            .filter { !builtinAliases.contains($0) }
            .sorted()
        return VStack(spacing: 0) {
            aliasHeaderRow
            ForEach(builtinAliases, id: \.self) { alias in
                aliasRow(alias: alias, modelOptions: modelOptions, isBuiltin: true)
                theme.border2.frame(height: 1)
            }
            ForEach(nonCalculable, id: \.alias) { item in
                nonCalculableRow(alias: item.alias, reason: item.reason)
                theme.border2.frame(height: 1)
            }
            ForEach(customAliases, id: \.self) { alias in
                customAliasRow(alias: alias, modelOptions: modelOptions)
                theme.border2.frame(height: 1)
            }
            addAliasRow(modelOptions: modelOptions)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }

    private var aliasHeaderRow: some View {
        HStack(spacing: 0) {
            Text(app.t("Alias")).frame(width: 140, alignment: .leading)
            Text(app.t("Resolves to")).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(theme.bg2)
        .overlay(alignment: .bottom) { theme.border.frame(height: 1) }
    }

    private func aliasRow(alias: String, modelOptions: [String], isBuiltin: Bool) -> some View {
        HStack(spacing: 0) {
            Text(alias)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.text)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 16)
            Picker("", selection: bAlias(alias)) {
                ForEach(modelOptions, id: \.self) { key in
                    Text(app.pricing.profiles[key]?.label ?? key).tag(key)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    private func nonCalculableRow(alias: String, reason: String) -> some View {
        HStack(spacing: 0) {
            Text(alias)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.text3)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 16)
            Text("— \(app.t(reason))")
                .font(.system(size: 12))
                .foregroundStyle(theme.text3)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    private func customAliasRow(alias: String, modelOptions: [String]) -> some View {
        HStack(spacing: 0) {
            Text(alias)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(theme.text)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 16)
            Picker("", selection: bAlias(alias)) {
                ForEach(modelOptions, id: \.self) { key in
                    Text(app.pricing.profiles[key]?.label ?? key).tag(key)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            Button { app.pricing.aliasMap.removeValue(forKey: alias); app.savePricing() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
    }

    private func addAliasRow(modelOptions: [String]) -> some View {
        HStack(spacing: 8) {
            TextField(app.t("alias name"), text: $newAliasName)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(width: 128)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg2))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
            Button(app.t("Add")) {
                let name = newAliasName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, app.pricing.aliasMap[name] == nil,
                      let first = modelOptions.first else { return }
                app.pricing.aliasMap[name] = first
                app.savePricing()
                newAliasName = ""
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.text2)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
            .disabled(newAliasName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.bg2)
    }

    private func bAlias(_ key: String) -> Binding<String> {
        Binding(
            get: { app.pricing.aliasMap[key] ?? "" },
            set: { app.pricing.aliasMap[key] = $0; app.savePricing() }
        )
    }

    // MARK: - Bindings

    private func bInput(_ key: String) -> Binding<Double> {
        Binding(get: { app.pricing.profiles[key]?.input ?? 0 },
                set: { app.pricing.profiles[key]?.input = $0; app.savePricing() })
    }

    private func bOutput(_ key: String) -> Binding<Double> {
        Binding(get: { app.pricing.profiles[key]?.output ?? 0 },
                set: { app.pricing.profiles[key]?.output = $0; app.savePricing() })
    }

    private func bCw5m(_ key: String) -> Binding<Double> {
        Binding(get: { app.pricing.profiles[key]?.cw5m ?? 0 },
                set: { app.pricing.profiles[key]?.cw5m = $0; app.savePricing() })
    }

    private func bCw1h(_ key: String) -> Binding<Double> {
        Binding(get: { app.pricing.profiles[key]?.cw1h ?? 0 },
                set: { app.pricing.profiles[key]?.cw1h = $0; app.savePricing() })
    }

    private func bRead(_ key: String) -> Binding<Double> {
        Binding(get: { app.pricing.profiles[key]?.read ?? 0 },
                set: { app.pricing.profiles[key]?.read = $0; app.savePricing() })
    }
}
