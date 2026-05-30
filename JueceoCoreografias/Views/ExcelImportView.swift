import SwiftUI
import UniformTypeIdentifiers

struct ExcelImportView: View {
    @EnvironmentObject private var store: JudgingStore

    @State private var eventName = ""
    @State private var eventSlug = ""
    @State private var importSecret = ""
    @State private var selectedFileURL: URL?
    @State private var isPickingFile = false
    @State private var isUploading = false
    @State private var lastUpload: ExcelImportSummary?
    @State private var errorMessage: String?

    private var canUpload: Bool {
        store.hasRemoteConfiguration
            && selectedFileURL != nil
            && !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !importSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isUploading
    }

    private var excelTypes: [UTType] {
        [UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 22) {
                    uploadPanel
                    statusPanel
                }
            }
            .padding(30)
        }
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: excelTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Importar Excel")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text("Carga directa a Supabase")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount)
        }
    }

    private var uploadPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Evento")

            VStack(spacing: 12) {
                TextField("Nombre del evento", text: $eventName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: eventName) { oldValue, newValue in
                        if eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || eventSlug == slug(for: oldValue) {
                            eventSlug = slug(for: newValue)
                        }
                    }

                TextField("Slug", text: $eventSlug)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: eventSlug) { _, newValue in
                        let clean = slug(for: newValue)
                        if clean != newValue {
                            eventSlug = clean
                        }
                    }
            }
            .textFieldStyle(ImportTextFieldStyle())

            sectionTitle("Permisos")

            SecureField("Clave de importación", text: $importSecret)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textFieldStyle(ImportTextFieldStyle())

            sectionTitle("Archivo")

            Button {
                isPickingFile = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3.weight(.black))
                        .foregroundStyle(LevitTheme.pink)
                        .frame(width: 46, height: 46)
                        .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedFileURL?.lastPathComponent ?? "Seleccionar Excel")
                            .font(.headline.weight(.black))
                            .foregroundStyle(LevitTheme.ink)
                            .lineLimit(1)
                        Text(selectedFileURL.map(fileSizeText) ?? ".xlsx o .xls")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LevitTheme.muted)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.muted)
                }
                .padding(16)
                .background(LevitTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            Button {
                Task { await uploadSelectedFile() }
            } label: {
                HStack(spacing: 10) {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "icloud.and.arrow.up.fill")
                    }
                    Text(isUploading ? "Importando" : "Importar Excel")
                }
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(LevitTheme.pinkGradient, in: RoundedRectangle(cornerRadius: 17))
                .contentShape(RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(!canUpload)
            .opacity(canUpload ? 1 : 0.45)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.line))
        .shadow(color: .black.opacity(0.04), radius: 22, x: 0, y: 12)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Estado")

            ImportStatusRow(
                icon: store.hasRemoteConfiguration ? "checkmark.icloud.fill" : "icloud.slash",
                title: store.hasRemoteConfiguration ? "Supabase conectado" : "Modo local",
                detail: store.syncMessage ?? store.syncStatus.title,
                tint: store.hasRemoteConfiguration ? .green : LevitTheme.muted
            )

            ImportStatusRow(
                icon: selectedFileURL == nil ? "doc" : "doc.fill",
                title: selectedFileURL?.lastPathComponent ?? "Sin archivo",
                detail: selectedFileURL.map(fileSizeText) ?? "Pendiente",
                tint: selectedFileURL == nil ? LevitTheme.muted : LevitTheme.pink
            )

            if let lastUpload {
                ImportStatusRow(
                    icon: "checkmark.circle.fill",
                    title: lastUpload.eventName,
                    detail: "\(lastUpload.routineCount ?? 0) rutinas importadas",
                    tint: .green
                )
            }

            if let errorMessage {
                ImportStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "No se pudo importar",
                    detail: errorMessage,
                    tint: .red
                )
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 360, alignment: .topLeading)
        .frame(minHeight: 360, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.line))
        .shadow(color: .black.opacity(0.04), radius: 22, x: 0, y: 12)
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            let name = url.deletingPathExtension().lastPathComponent
            if eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                eventName = name
            }
            if eventSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                eventSlug = slug(for: name)
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func uploadSelectedFile() async {
        guard let selectedFileURL else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            lastUpload = try await store.uploadExcelImport(
                fileURL: selectedFileURL,
                eventName: eventName,
                eventSlug: eventSlug,
                importSecret: importSecret
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.black))
            .tracking(0.6)
            .foregroundStyle(LevitTheme.muted)
    }

    private func slug(for value: String) -> String {
        value.stableRemoteID
    }

    private func fileSizeText(for url: URL) -> String {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else {
            return "Excel seleccionado"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct ImportStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ImportTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.headline.weight(.bold))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .foregroundStyle(LevitTheme.ink)
            .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(LevitTheme.line))
    }
}
