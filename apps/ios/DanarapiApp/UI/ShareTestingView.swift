#if DEBUG
import PDFKit
import SwiftUI

// Synthetic proofs only; this entry point exists exclusively in UI-test launches.
struct ShareTestingView: View {
    @State private var sharing = false
    var body: some View {
        Button("Bagikan bukti uji") { sharing = true }
            .accessibilityIdentifier("share.testSource")
            .sheet(isPresented: $sharing) { TestActivityController() }
    }
}

private struct TestActivityController: UIViewControllerRepresentable {
    private let text = "BSI · BUKTI UJI SINTETIS\nTransfer Berhasil\nNominal Transfer: Rp 150.000,00\nBiaya Admin: Rp 2.500,00\nSaldo: Rp 9.000.000,00\nNama Penerima: KEDAI UJI SHARE\nTanggal: 05/10/2026 09:30:00"
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let arguments = ProcessInfo.processInfo.arguments
        var items: [Any] = [text]
        if arguments.contains("--ui-testing-share-native-image") || arguments.contains("--ui-testing-share-image-link") || arguments.contains("--ui-testing-share-image") {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 800), format: format).image { renderer in
                UIColor.white.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 900, height: 800))
                (text as NSString).draw(in: CGRect(x: 40, y: 40, width: 820, height: 720), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bukti-Uji-Share.png")
            try? image.pngData()?.write(to: url, options: [.atomic, .completeFileProtection])
            if arguments.contains("--ui-testing-share-native-image") { items = [image] }
            else if arguments.contains("--ui-testing-share-image-link") { items = [image, URL(string: "https://bank.example.invalid/proof")!] }
            else { items = [url] }
        } else if arguments.contains("--ui-testing-share-pdf") {
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
            let data = renderer.pdfData { context in
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 30, y: 30, width: 540, height: 740), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bukti-Uji-Share.pdf")
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
            items = [url]
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
