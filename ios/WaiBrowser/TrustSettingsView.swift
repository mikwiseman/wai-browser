import SwiftUI
struct TrustSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var settings: SiteSettings
    let currentHost: String?
    var onDone: (SiteSettings) -> Void
    @State private var input = ""
    @State private var error: String?
    @State private var changed = false
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Российские сертификаты", isOn: $settings.enabled).onChange(of: settings.enabled) { _,_ in changed = true }
                } footer: { Text("Только для сайтов из списка и их поддоменов. Только внутри Wai Browser.") }
                Section {
                    HStack {
                        TextField("Адрес сайта или ссылка", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).submitLabel(.done).onSubmit(add)
                        Button("Добавить", action: add).disabled(input.isEmpty)
                    }
                    if let host = currentHost, let site = SiteSettings.site(host), !settings.domains.contains(site) {
                        Button("Добавить \(site)") { input = site; add() }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    ForEach(settings.domains, id: \.self) { Text($0) }
                        .onDelete { indexes in settings.domains.remove(atOffsets: indexes); changed = true }
                } header: { Text("Сайты") } footer: { Text("Удалить сайт можно смахиванием влево.") }
                Section {
                    Link("Поддержка", destination: URL(string: "https://waiwai.is/browser/support")!)
                    Link("Конфиденциальность", destination: URL(string: "https://waiwai.is/browser/privacy")!)
                }
            }
            .navigationTitle("Сертификаты").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) { Button("Готово", action: done).keyboardShortcut("w", modifiers: .command) }
            }
            .alert("Применить настройки?", isPresented: $confirm) {
                Button("Применить и обновить") { onDone(settings) }
                Button("Отмена", role: .cancel) { }
            } message: { Text("Вкладки обновятся. Несохранённый текст может быть потерян. При отключении доверия некоторые сайты могут попросить войти снова.") }
        }
    }
    private func done() { if !input.isEmpty { add(); if !input.isEmpty { return } }; if changed { confirm = true } else { onDone(settings) } }
    private func add() {
        guard let site = SiteSettings.site(input) else { error = "Укажите адрес сайта, например https://rzd.ru"; return }
        if !settings.domains.contains(site) { settings.domains.append(site); changed = true }
        input = ""; error = nil
    }
}
