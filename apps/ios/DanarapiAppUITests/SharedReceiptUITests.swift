import XCTest

final class SharedReceiptUITests: XCTestCase {
    @MainActor func testShareSheetTextCreatesLocalDraftWithoutPosting() throws { try shareProof(format: "text", name: "Bukti teks.txt") }
    @MainActor func testShareSheetImageCreatesLocalDraftWithoutPosting() throws { try shareProof(format: "image", name: "Bukti-Uji-Share.png") }
    @MainActor func testShareSheetPDFCreatesLocalDraftWithoutPosting() throws { try shareProof(format: "pdf", name: "Bukti-Uji-Share.pdf") }
    @MainActor func testBankNativeImageCreatesDraft() throws { try shareProof(format: "native-image", name: "Bukti transaksi") }
    @MainActor func testBankImageWithCompanionLinkCreatesDraft() throws { try shareProof(format: "image-link", name: "Bukti transaksi") }

    @MainActor private func shareProof(format: String, name: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo", "--ui-testing-share"]
        if format != "text" { app.launchArguments.append("--ui-testing-share-" + format) }
        app.launch()
        let skip = app.buttons["Lewati tur"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10)); skip.tap()
        let source = app.buttons["share.testSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let target = app.cells.matching(NSPredicate(format: "label == %@", "Danarapi")).firstMatch
        let more = app.cells.matching(NSPredicate(format: "label == 'More' OR label == 'Lainnya'")).firstMatch
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if target.exists && target.isHittable { break }
            if more.exists && more.isHittable { more.tap(); break }
            let row = app.cells.matching(identifier: "shareCell").firstMatch
            row.swipeLeft()
        }
        let allTarget = target.exists ? target : app.buttons["Danarapi"].firstMatch
        XCTAssertTrue(allTarget.waitForExistence(timeout: 5))
        allTarget.tap()
        var surface = app
        if !app.buttons["share.save"].waitForExistence(timeout: 5) { surface = springboard }
        let save = surface.buttons["share.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), surface.debugDescription)
        XCTAssertTrue(save.isEnabled)
        let evidence = XCTAttachment(screenshot: surface.screenshot()); evidence.name = "Share \(format) sebelum simpan"; evidence.lifetime = .keepAlways; add(evidence)
        save.tap()
        XCTAssertTrue(surface.staticTexts["Bukti tersimpan"].waitForExistence(timeout: 10))
        surface.buttons["Selesai"].firstMatch.tap()
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        if app.buttons["Tutup"].exists { app.buttons["Tutup"].tap() }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Lewati tur"].waitForExistence(timeout: 10)); app.buttons["Lewati tur"].tap()
        XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 10)); app.buttons["home.reviews"].tap()
        XCTAssertTrue(app.buttons["reviews.sharedInbox"].waitForExistence(timeout: 5)); app.buttons["reviews.sharedInbox"].tap()
        let directImage = format == "native-image" || format == "image-link"
        let record = app.cells.containing(.staticText, identifier: directImage ? "Belum terikat akun" : name).firstMatch
        if record.waitForExistence(timeout: 5) { record.tap() }
        else {
            let candidate = app.cells.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(candidate.waitForExistence(timeout: 5), app.debugDescription); candidate.tap()
        }
        XCTAssertTrue(app.navigationBars["Tinjau bukti Share"].waitForExistence(timeout: 5))
        let amount = app.textFields["Nominal bukti Share"]
        XCTAssertTrue(amount.waitForExistence(timeout: 20))
        XCTAssertTrue((amount.value as? String)?.contains("150") == true, app.debugDescription)
        guard app.textFields["share.merchant"].value as? String == "KEDAI UJI SHARE" else { XCTFail("Bukti sintetis tidak terbaca"); return }
        XCTAssertTrue(app.buttons["Lihat bukti asli"].exists)
        XCTAssertFalse(app.buttons["share.readAI"].exists)
        if format == "text" {
            app.buttons["Lihat bukti asli"].tap()
            XCTAssertTrue(app.navigationBars["Bukti teks"].waitForExistence(timeout: 5))
            app.buttons["Selesai"].tap()
        }
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Draft lokal Share \(format)"; detail.lifetime = .keepAlways; add(detail)
        for _ in 0..<4 where !app.buttons["share.import"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["share.import"].exists)
        XCTAssertFalse(app.buttons["share.import"].isEnabled)
        app.buttons["nav.0"].tap()
        app.buttons["home.reviews"].tap()
        app.buttons["reviews.sharedInbox"].tap()
        let synthetic = directImage ? app.cells.containing(.staticText, identifier: "Belum terikat akun").firstMatch : app.cells.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(synthetic.waitForExistence(timeout: 5))
        synthetic.swipeLeft()
        app.buttons["Hapus lokal"].firstMatch.tap()
        let deletion = app.buttons["Hapus lokal"].firstMatch
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); deletion.tap()
    }
}
