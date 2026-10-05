import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ScanMode: String, CaseIterable, Identifiable {
    case receipt = "Struk", qris = "QRIS"
    var id: String { rawValue }
}

struct ScanHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: ScanMode
    @State private var photo: PhotosPickerItem?
    @State private var showPDF = false
    @State private var showGallery = false
    @State private var denied = false
    @State private var capture = 0
    @State private var images: [UIImage] = []
    @State private var attachment: ReviewAttachment?
    @State private var processing = false
    @State private var message: String?
    @State private var reviewID: String?
    @State private var showReviews = false
    @State private var showSignIn = false
    let existingReviewID: String?
    let onReread: (() -> Void)?
    let onClose: (() -> Void)?

    init(initialMode: ScanMode = .receipt, existingReviewID: String? = nil, onReread: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        _mode = State(initialValue: initialMode); self.existingReviewID = existingReviewID; self.onReread = onReread
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if existingReviewID == nil { Picker("Jenis scan", selection: $mode) {
                    ForEach(ScanMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
                .disabled(processing).accessibilityIdentifier("scan.mode") }
                if mode == .qris {
                    QRScannerView(onSaved: {}, onCreated: { reviewID = $0 }, cameraActive: scenePhase == .active && reviewID == nil && !showReviews)
                } else {
                    receiptScanner
                }
            }
            .background(Color.danarapiCanvas).navigationTitle(existingReviewID == nil ? "Scan" : "Baca ulang struk")
            .navigationBarTitleDisplayMode(.inline)
            .danarapiMainHeader(enabled: onClose != nil && existingReviewID == nil)
            .toolbar {
                if onClose == nil || existingReviewID != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Tutup") { if let onClose { onClose() } else { dismiss() } }.disabled(processing) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showReviews = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tray").font(.system(size: 19))
                            if !app.snapshot.reviewItems.isEmpty { Text("\(app.snapshot.reviewItems.count)").font(.caption.weight(.semibold)) }
                        }.frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(processing).accessibilityLabel("Tinjauan").accessibilityIdentifier("scan.reviews")
                }
            }
            .navigationDestination(isPresented: $showReviews) { ReviewListView(embedded: true) }
            .navigationDestination(item: $reviewID) { ReviewDetailView(itemID: $0) }
            .fileImporter(isPresented: $showPDF, allowedContentTypes: [.pdf]) { result in Task { await loadPDF(result) } }
            .photosPicker(isPresented: $showGallery, selection: $photo, matching: .images)
            .onChange(of: photo) { _, value in Task { await loadPhoto(value) } }
            .onChange(of: mode) { _, _ in images = []; attachment = nil; photo = nil; message = nil }
        }
        .tint(.danarapiPrimary)
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                AuthView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { showSignIn = false } } }
            }
        }
        .onChange(of: app.mode) { _, value in
            if value == .authenticated { showSignIn = false }
        }
    }

    private var receiptScanner: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !images.isEmpty {
                    ForEach(images.indices, id: \.self) { index in
                        Image(uiImage: images[index]).resizable().scaledToFit().frame(maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel("Foto struk halaman \(index + 1)")
                    }
                    Button("Foto ulang", systemImage: "camera") { images = []; attachment = nil; message = nil; denied = false }
                        .frame(minHeight: 44).disabled(processing)
                } else if denied {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.system(size: 36)).foregroundStyle(Color.danarapiMuted)
                        Text("Kamera tidak tersedia").font(.headline)
                        Text("Pilih galeri atau PDF. Izin kamera dapat diubah di Pengaturan.")
                            .font(.subheadline).foregroundStyle(Color.danarapiMuted).multilineTextAlignment(.center)
                        Button("Buka Pengaturan") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.frame(minHeight: 44)
                        Button("Coba kamera lagi") { denied = false }.frame(minHeight: 44)
                    }.frame(maxWidth: .infinity).frame(minHeight: 300).danarapiCard()
                } else if processing {
                    ProgressView("Menyiapkan struk…").frame(maxWidth: .infinity).frame(height: 340)
                } else if scenePhase == .active, reviewID == nil, !showReviews, !showPDF, !showGallery {
                    ReceiptCameraView(capture: capture, onPhoto: { image in
                        do {
                            let compressed = try ImportService.compressedReceipt(image)
                            guard let data = Data(base64Encoded: compressed.0.data) else { throw AppError.validation("Foto tidak dapat disiapkan.") }
                            images = [compressed.1]
                            attachment = ReviewAttachment(name: "struk.jpg", mimeType: "image/jpeg", data: data)
                        } catch { message = (error as? AppError)?.message ?? "Foto tidak dapat dibaca." }
                    }, onDenied: { denied = true }, onFailure: { message = $0 })
                    .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .top) {
                        Text("Posisikan seluruh struk dalam bingkai").font(.caption.weight(.medium))
                            .padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                    }
                    .overlay(alignment: .bottom) {
                        Button { capture += 1 } label: {
                            Circle().fill(.white).frame(width: 54, height: 54)
                                .padding(5).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain).padding(18).accessibilityLabel("Ambil foto struk").accessibilityIdentifier("scan.capture")
                    }
                }
                HStack(spacing: 12) {
                    Button { showGallery = true } label: {
                        Label("Galeri", systemImage: AppSymbol.gallery.rawValue).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .background(Color.danarapiSurface, in: RoundedRectangle(cornerRadius: 12))
                    Button { showPDF = true } label: {
                        Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity, minHeight: 48)
                    }.background(Color.danarapiSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                .font(.subheadline.weight(.medium)).disabled(processing)
                if existingReviewID != nil { Text("Foto ini untuk membaca ulang draft. Bukti asli tidak diganti.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                if let message { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.danarapiExpense).frame(maxWidth: .infinity, alignment: .leading) }
                if !images.isEmpty {
                    Button {
                        if app.mode == .demo && app.cloudReceiptScanConfigured && !ProcessInfo.processInfo.arguments.contains("--local-receipt-scan") {
                            showSignIn = true
                        } else { Task { await readReceipt() } }
                    } label: {
                        HStack { if processing { ProgressView().tint(.danarapiOnPrimary) }; Text(processing ? "Membaca struk…" : "Baca struk") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(processing)
                }
            }
            .padding(20)
        }
    }

    private func loadPhoto(_ value: PhotosPickerItem?) async {
        guard let value else { return }
        processing = true; message = nil
        defer { processing = false; photo = nil }
        do {
            guard let data = try await value.loadTransferable(type: Data.self) else { throw AppError.validation("Foto tidak dapat dibuka.") }
            let image = try ImportService.receiptImage(from: data)
            let compressed = try ImportService.compressedReceipt(image)
            guard let bytes = Data(base64Encoded: compressed.0.data) else { throw AppError.validation("Foto tidak dapat disiapkan.") }
            images = [compressed.1]; attachment = ReviewAttachment(name: "struk.jpg", mimeType: "image/jpeg", data: bytes)
        } catch { message = (error as? AppError)?.message ?? "Foto tidak dapat dibuka. Pilih foto lain." }
    }

    private func loadPDF(_ result: Result<URL, Error>) async {
        processing = true; message = nil
        defer { processing = false }
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            images = try ImportService.receiptImagesFromPDF(data)
            attachment = ReviewAttachment(name: url.lastPathComponent, mimeType: "application/pdf", data: data)
        } catch { message = (error as? AppError)?.message ?? "PDF tidak dapat dibuka. Pilih berkas lain." }
    }

    private func readReceipt() async {
        guard !images.isEmpty, let attachment else { return }
        processing = true; message = nil
        defer { processing = false }
        do {
            let source: ReviewSource = attachment.mimeType == "application/pdf" ? .pdfText : .image
            let item = try await ImportService.readReceipt(images: images, source: source, attachmentName: attachment.name, cloudScan: { try await app.scanReceipt(images: $0) })
            if let existingReviewID {
                guard let existing = app.snapshot.reviewItems.first(where: { $0.matchesID(existingReviewID) }), let receipt = item.receipt else { throw AppError.validation("Draft tidak lagi tersedia atau rincian belum terbaca.") }
                var updated = ImportService.reviewFromReceipt(receipt, source: existing.source, existing: existing)
                updated.amount.confidence = item.amount.confidence
                updated.merchant.confidence = item.merchant.confidence
                updated.rawReference = item.rawReference
                if await app.updateReview(updated) { onReread?(); dismiss() }
                else { message = app.errorMessage ?? "Hasil belum tersimpan. Coba lagi." }
            } else if await app.addReview(item, attachment: attachment) { images = []; self.attachment = nil; reviewID = item.id }
            else { message = app.errorMessage ?? "Draft belum tersimpan. Coba lagi." }
        } catch { message = (error as? AppError)?.message ?? "Struk belum dapat dibaca. Foto tetap tersedia; coba lagi atau pilih foto lain." }
    }
}

struct QRScannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    var onCreated: ((String) -> Void)? = nil
    var cameraActive = true
    @State private var scannedValue: String?
    @State private var permissionDenied = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedAttachment: ReviewAttachment?
    @State private var processing = false
    @State private var showGallery = false
    @State private var message: String?

    var body: some View {
        ScrollView { VStack(spacing: 16) {
            if permissionDenied {
                ContentUnavailableView(
                    "Kamera tidak tersedia",
                    systemImage: "camera.fill",
                    description: Text("Izinkan kamera di Pengaturan, atau pilih gambar QRIS.")
                )
            } else if let scannedValue {
                QRPreview(raw: scannedValue) { Task { await save(scannedValue) } }
                    .disabled(processing)
                Button("Scan ulang", systemImage: "arrow.clockwise") { self.scannedValue = nil; selectedAttachment = nil; message = nil }.frame(minHeight: 44).disabled(processing)
            } else if cameraActive && !processing && !showGallery {
                CameraQRView(onCode: { scannedValue = $0 }, onDenied: { permissionDenied = true })
                    .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        Text("Arahkan kamera ke QRIS merchant")
                            .font(.caption.weight(.medium))
                            .padding(12)
                            .background(.thickMaterial, in: Capsule())
                            .padding()
                    }
                    .padding(.horizontal, 20)
            }

            Button { showGallery = true } label: {
                Label("Galeri QRIS", systemImage: AppSymbol.gallery.rawValue)
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.danarapiSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20).disabled(processing)
            .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in Task { await parseImage(item) } }

            if processing { ProgressView("Memeriksa QRIS…").font(.subheadline) }
            if let message { Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.danarapiExpense).padding(.horizontal, 20) }

            Text("QRIS untuk pencatatan, bukan pembayaran.")
                .font(.footnote)
                .foregroundStyle(Color.danarapiMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }.padding(.vertical, 8) }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func parseImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        processing = true; message = nil
        defer { processing = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= 5 * 1_024 * 1_024,
                  let image = UIImage(data: data) else { throw AppError.validation("Gambar tidak valid atau melebihi 5 MB.") }
            let values = try await ImportService.qrStrings(in: image)
            guard let first = values.first(where: { (try? QRISParser.parse($0)) != nil }) else { throw AppError.validation("QRIS tidak ditemukan atau tidak valid. Pilih foto QRIS lain.") }
            selectedAttachment = try makeImageAttachment(data: data, baseName: "qris-image")
            scannedValue = first
        } catch { message = (error as? AppError)?.message ?? "Gambar tidak dapat dipindai." }
    }

    private func save(_ raw: String) async {
        guard !processing else { return }
        processing = true; message = nil
        defer { processing = false }
        do {
            let item = try ImportService.reviewFromQR(raw, attachmentName: selectedAttachment?.name)
            if await app.addReview(item, attachment: selectedAttachment) {
                if let onCreated { scannedValue = nil; pickerItem = nil; selectedAttachment = nil; onCreated(item.id) }
                else { onSaved(); dismiss() }
            }
        } catch { message = (error as? AppError)?.message ?? "QR tidak dapat dibaca." }
    }
}

private struct QRPreview: View {
    let raw: String
    let save: () -> Void
    @State private var payload: QRISPayload?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(Color.danarapiPrimary)
            if let payload {
                Text(payload.merchant ?? "Merchant tidak terbaca").font(.title2.bold())
                if let city = payload.city { Text(city).foregroundStyle(Color.danarapiMuted) }
                if let amount = payload.amount { MoneyText(amount: amount, style: .title.bold()) }
                else { Label("Jumlah belum terbaca. Isi nominal sebelum menyimpan.", systemImage: "exclamationmark.triangle").foregroundStyle(Color.danarapiExpense) }
                Button("Simpan sebagai draft") { save() }.buttonStyle(PrimaryButtonStyle())
            } else if let message {
                Label(message, systemImage: "xmark.octagon").foregroundStyle(Color.danarapiExpense)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .danarapiCard(.danarapiMint)
        .padding()
        .task {
            do { payload = try QRISParser.parse(raw) }
            catch { message = (error as? AppError)?.message ?? "QR tidak didukung." }
        }
    }
}

private struct CameraQRView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> CameraController {
        let controller = CameraController()
        controller.delegate = context.coordinator
        Task {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            await MainActor.run {
                if granted { controller.start(onUnavailable: onDenied) } else { onDenied() }
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: CameraController, coordinator: Coordinator) {
        uiViewController.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered, let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
            delivered = true
            onCode(code)
        }
    }
}

private final class CameraController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    private let runner = CaptureSessionRunner()
    private var session: AVCaptureSession { runner.session }
    private var hasStopped = false
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func start(onUnavailable: () -> Void) {
        guard !hasStopped else { return }
        guard session.inputs.isEmpty, let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { onUnavailable(); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onUnavailable(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        runner.start()
    }

    func stop() {
        hasStopped = true
        runner.stop()
    }
}

private final class CaptureSessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "id.danarapi.camera-session", qos: .userInitiated)
    func start() { queue.async { self.session.startRunning() } }
    func stop() { queue.async { self.session.stopRunning() } }
}

private struct ReceiptCameraView: UIViewControllerRepresentable {
    let capture: Int
    let onPhoto: (UIImage) -> Void
    let onDenied: () -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> ReceiptCameraController {
        let controller = ReceiptCameraController()
        controller.onPhoto = onPhoto; controller.onFailure = onFailure
        Task { @MainActor in
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            if granted { controller.start(onUnavailable: onDenied) } else { onDenied() }
        }
        return controller
    }

    func updateUIViewController(_ controller: ReceiptCameraController, context: Context) {
        controller.takePhoto(trigger: capture)
    }

    static func dismantleUIViewController(_ controller: ReceiptCameraController, coordinator: ()) { controller.stop() }
}

private final class ReceiptCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onPhoto: ((UIImage) -> Void)?
    var onFailure: ((String) -> Void)?
    private let runner = CaptureSessionRunner()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastTrigger = 0
    private var stopped = false
    private var capturing = false
    private var ready = false

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }

    func start(onUnavailable: () -> Void) {
        guard !stopped else { return }
        let session = runner.session
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input), session.canAddOutput(output) else {
            onUnavailable(); return
        }
        session.beginConfiguration(); session.sessionPreset = .photo
        session.addInput(input); session.addOutput(output); session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
        view.layer.addSublayer(layer); preview = layer; ready = true; runner.start()
    }

    func takePhoto(trigger: Int) {
        guard trigger != lastTrigger else { return }
        lastTrigger = trigger
        guard ready, !stopped, !capturing, runner.session.isRunning else { return }
        capturing = true
        let settings = AVCapturePhotoSettings(); settings.flashMode = .off
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            self.capturing = false
            guard let data, let image = UIImage(data: data) else { self.onFailure?("Foto gagal diambil. Coba lagi."); return }
            self.onPhoto?(image)
        }
    }

    func stop() { stopped = true; runner.stop() }
}

struct ImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showPhotoCamera = false
    @State private var processing = false

    var body: some View {
        Form {
            Section("Tempel teks") {
                TextEditor(text: $text).frame(minHeight: 150).accessibilityLabel("Teks bukti")
                Button("Buat draft dari teks") { Task { await add(ImportService.reviewFromText(text)) } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Pilih berkas") {
                Button { Task { await openPhotoCamera() } } label: { Label("Ambil foto bukti", systemImage: "camera") }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Pilih gambar", systemImage: AppSymbol.gallery.rawValue)
                }
                .onChange(of: pickerItem) { _, item in Task { await importImage(item) } }
                Button { showFiles = true } label: { Label("Pilih PDF", systemImage: "doc.richtext") }
            }
            Section {
                Text("Bukti perlu diperiksa sebelum disimpan.")
                    .font(.footnote)
                    .foregroundStyle(Color.danarapiMuted)
            }
        }
        .overlay { if processing { ProgressView("Memeriksa berkas…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .danarapiListSurface()
        .navigationTitle("Impor")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(processing)
        .sheet(isPresented: $showPhotoCamera) {
            PhotoCameraPicker { image in
                showPhotoCamera = false
                guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return }
                Task { await importImageData(data) }
            }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            Task { await importPDF(result) }
        }
    }

    private func importImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw AppError.validation("Gambar tidak dapat dibaca.") }
            await importImageData(data)
        } catch { app.errorMessage = "Gambar tidak dapat diimpor." }
    }

    private func openPhotoCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            app.errorMessage = "Kamera tidak tersedia. Pilih gambar atau tempel teks untuk membuat draft."; return
        }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        if granted { showPhotoCamera = true }
        else { app.errorMessage = "Izin kamera tidak tersedia. Pilih gambar atau izinkan Kamera melalui Pengaturan iOS." }
    }

    private func importImageData(_ data: Data) async {
        processing = true
        defer { processing = false }
        do {
            guard data.count <= 5 * 1_024 * 1_024,
                  let image = UIImage(data: data) else { throw AppError.validation("Gambar tidak valid atau melebihi 5 MB.") }
            let attachment = try makeImageAttachment(data: data, baseName: "imported-image")
            if let raw = try await ImportService.qrStrings(in: image).first {
                await add(try ImportService.reviewFromQR(raw, attachmentName: attachment.name), attachment: attachment)
            } else {
                let item = try await ImportService.readReceipt(images: [image], source: .image, attachmentName: attachment.name, cloudScan: { try await app.scanReceipt(images: $0) })
                await add(item, attachment: attachment)
            }
        } catch { app.errorMessage = (error as? AppError)?.message ?? "Gambar tidak dapat diimpor." }
    }

    private func importPDF(_ result: Result<[URL], Error>) async {
        processing = true
        defer { processing = false }
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let attachment = ReviewAttachment(name: url.lastPathComponent, mimeType: "application/pdf", data: data)
            let images = try ImportService.receiptImagesFromPDF(data)
            let item = try await ImportService.readReceipt(images: images, source: .pdfText, attachmentName: attachment.name, cloudScan: { try await app.scanReceipt(images: $0) })
            await add(item, attachment: attachment)
        } catch { app.errorMessage = (error as? AppError)?.message ?? "PDF tidak dapat diimpor." }
    }

    private func add(_ item: ReviewItem, attachment: ReviewAttachment? = nil) async {
        if await app.addReview(item, attachment: attachment) { onSaved(); dismiss() }
    }
}

struct PhotoCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

private func makeImageAttachment(data: Data, baseName: String) throws -> ReviewAttachment {
    let bytes = [UInt8](data.prefix(12))
    if bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xd8, bytes[2] == 0xff {
        return ReviewAttachment(name: "\(baseName).jpg", mimeType: "image/jpeg", data: data)
    }
    let png: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    if bytes.count >= png.count, Array(bytes.prefix(png.count)) == png {
        return ReviewAttachment(name: "\(baseName).png", mimeType: "image/png", data: data)
    }
    if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp",
       let brand = String(bytes: bytes[8..<12], encoding: .ascii), ["heic", "heix", "hevc", "hevx", "mif1"].contains(brand) {
        return ReviewAttachment(name: "\(baseName).heic", mimeType: "image/heic", data: data)
    }
    throw AppError.validation("Format gambar harus JPEG, PNG, atau HEIC.")
}
