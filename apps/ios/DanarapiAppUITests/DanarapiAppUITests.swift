import XCTest

final class DanarapiAppUITests: XCTestCase {
    @MainActor
    func testGoogleOnlyLoginInLightAndDark() throws {
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-auth", "-theme", theme]
            app.launch()
            let google = app.buttons["auth.google"]
            XCTAssertTrue(google.waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["auth.apple"].exists)
            XCTAssertTrue(google.isEnabled)
            XCTAssertEqual(google.label, "Lanjutkan dengan Google")
            XCTAssertGreaterThanOrEqual(google.frame.height, 56)
            XCTAssertGreaterThan(google.frame.width, 200)
            XCTAssertLessThanOrEqual(google.frame.maxX, app.windows.firstMatch.frame.maxX)
            retainScreenshot("Login provider \(theme)", in: app)
            app.terminate()
        }
    }

    @MainActor
    func testHomeBalanceIncomeExpenseNavigateToMatchingPages() throws {
        let app = launchDemo()
        let accounts = app.buttons["home.accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 5)); accounts.tap()
        XCTAssertTrue(app.navigationBars["Akun"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Tambah akun"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let income = app.buttons["home.income"]
        XCTAssertTrue(income.waitForExistence(timeout: 5)); income.tap()
        XCTAssertTrue(app.navigationBars["Pemasukan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pemasukan · Bulan ini"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let expense = app.buttons["home.expense"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        XCTAssertTrue(app.navigationBars["Pengeluaran"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pengeluaran · Bulan ini"].exists)
        retainScreenshot("Beranda pengeluaran terfilter", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ringkasan keuangan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCenterScannerDefaultsToReceiptAndOffersQRISGalleryAndPDF() throws {
        let app = launchDemo()
        let scan = app.buttons["nav.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(scan.frame.width, 44)
        XCTAssertGreaterThanOrEqual(scan.frame.height, 44)
        XCTAssertLessThan(scan.frame.minY, app.buttons["nav.1"].frame.minY)
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.staticTexts["Demo · data contoh"].exists)
        XCTAssertLessThanOrEqual(scan.frame.maxY, app.windows.firstMatch.frame.maxY)
        let add = app.buttons["Tambah catatan"]
        XCTAssertLessThan(add.frame.maxY, scan.frame.minY)
        for identifier in ["nav.0", "nav.1", "nav.scan", "nav.3", "nav.4"] {
            XCTAssertFalse(add.frame.intersects(app.buttons[identifier].frame))
        }
        retainScreenshot("Beranda dan navbar", in: app)
        scan.tap()
        let mode = app.segmentedControls["scan.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.buttons["Struk"].isSelected)
        XCTAssertTrue(app.buttons["Galeri"].exists)
        XCTAssertTrue(app.buttons["PDF"].exists)
        XCTAssertFalse(app.switches["Baca struk otomatis"].exists)
        XCTAssertFalse(app.staticTexts["Privasi foto"].exists)
        XCTAssertFalse(app.staticTexts["Demo · data contoh"].exists)
        retainScreenshot("Scan struk", in: app)
        mode.buttons["QRIS"].tap()
        XCTAssertTrue(app.buttons["Galeri QRIS"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["PDF"].exists)
        retainScreenshot("Scan QRIS", in: app)
        mode.buttons["Struk"].tap()
        app.buttons["scan.reviews"].tap()
        XCTAssertTrue(app.navigationBars["Tinjauan"].waitForExistence(timeout: 3))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoCoreNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Ringkasan keuangan"].waitForExistence(timeout: 8))
        app.buttons["nav.1"].tap()
        XCTAssertTrue(app.navigationBars["Transaksi"].waitForExistence(timeout: 3))
        app.buttons["nav.0"].tap()
        app.buttons["home.reviews"].tap()
        XCTAssertTrue(app.navigationBars["Tinjauan"].waitForExistence(timeout: 3))
        app.buttons["nav.3"].tap()
        XCTAssertTrue(app.navigationBars["Laporan"].waitForExistence(timeout: 3))
        app.buttons["nav.4"].tap()
        XCTAssertTrue(app.navigationBars["Pengaturan"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCreateDemoExpense() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 8))
        app.buttons["Tambah catatan"].tap()
        app.buttons["Pengeluaran"].tap()
        let amount = app.textFields["money.Nominal"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("25000")
        XCTAssertEqual(amount.value as? String, "25.000")
        app.buttons["Catat pengeluaran"].tap()
        XCTAssertTrue(app.staticTexts["Tersimpan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTextImportCreatesReviewNotPostedTransaction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 8))
        app.buttons["Tambah catatan"].tap()
        app.buttons["Impor bukti"].tap()
        let text = app.textViews["Teks bukti"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap()
        text.typeText("DRAFT UI DEMO\nTotal: Rp75.000\n30/09/2026")
        app.buttons["Buat draft dari teks"].tap()
        XCTAssertTrue(app.buttons["home.reviews"].waitForExistence(timeout: 5))
        app.buttons["home.reviews"].tap()
        XCTAssertTrue(app.staticTexts["DRAFT UI DEMO"].waitForExistence(timeout: 3))
        app.buttons["nav.1"].tap()
        XCTAssertFalse(app.staticTexts["DRAFT UI DEMO"].exists)
    }

    @MainActor
    func testGoalCreationFromDashboard() throws {
        let app = launchDemo()
        let goals = app.buttons["home.goals"]
        reveal(goals, in: app); goals.tap()
        let adding = app.buttons["Tambah target"]
        reveal(adding, in: app); adding.tap()
        let name = app.textFields["Nama target"]
        XCTAssertTrue(name.waitForExistence(timeout: 4)); name.tap(); name.typeText("Sepeda UI")
        let target = app.textFields["money.Target tabungan"]
        target.tap(); target.typeText("2000000")
        XCTAssertEqual(target.value as? String, "2.000.000")
        let save = app.buttons["Simpan target"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.staticTexts["Sepeda UI"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testGoalProgressPostsExpenseAndReportAllocation() throws {
        let app = launchDemo()
        let goals = app.buttons["home.goals"]
        reveal(goals, in: app); goals.tap()
        let progress = app.buttons["goal.progress.demo-goal"]
        reveal(progress, in: app); XCTAssertTrue(progress.waitForExistence(timeout: 4)); progress.tap()
        let amount = app.textFields["money.Nominal"]
        XCTAssertTrue(amount.waitForExistence(timeout: 4)); amount.tap(); amount.typeText("500000")
        XCTAssertEqual(amount.value as? String, "500.000")
        let save = app.buttons["Catat pengeluaran"]
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 6))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["nav.3"].tap()
        let allocation = app.staticTexts["Alokasi pengeluaran"]
        reveal(allocation, in: app); XCTAssertTrue(allocation.waitForExistence(timeout: 5))
        let goalAllocation = app.staticTexts["Target · Laptop impian"]
        reveal(goalAllocation, in: app); XCTAssertTrue(goalAllocation.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "goal-report-allocation"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testBudgetCreatesAndSelectsNewCategory() throws {
        let app = launchDemo()
        let budgets = app.buttons["home.budgets"]
        reveal(budgets, in: app); budgets.tap()
        XCTAssertTrue(app.navigationBars["Anggaran"].waitForExistence(timeout: 4))
        let adding = app.buttons["Tambah anggaran"]
        reveal(adding, in: app); adding.tap()
        let limit = app.textFields["money.Limit bulanan"]
        XCTAssertTrue(limit.waitForExistence(timeout: 4)); limit.tap(); limit.typeText("500000")
        XCTAssertEqual(limit.value as? String, "500.000")
        let category = app.textFields["Nama kategori baru"]
        reveal(category, in: app); category.tap(); category.typeText("Hobi UI")
        let create = app.buttons["Buat kategori dan pilih"]
        reveal(create, in: app); create.tap()
        let save = app.buttons["Simpan anggaran"]
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["Hobi UI"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testItemSplitFromReceiptTextUsesPerPersonQuantities() throws {
        let app = launchDemo()
        app.buttons["Tambah catatan"].tap(); app.buttons["Split bill"].tap()
        let title = app.textFields["Judul tagihan"]
        XCTAssertTrue(title.waitForExistence(timeout: 4)); title.tap(); title.typeText("Makan bersama UI")
        app.buttons["Selesai"].tap()
        let paste = app.buttons["Tempel teks struk"]
        reveal(paste, in: app); paste.tap()
        let text = app.textViews["receipt.menu.text"]
        reveal(text, in: app); text.tap(); text.typeText("Nasi 4 x 25000\nMinum 2 x 15000")
        app.buttons["Selesai"].tap()
        let read = app.buttons["Baca menu dari teks"]
        reveal(read, in: app); read.tap()
        for (person, item, count) in [("Saya", "Nasi", 1), ("Ani", "Nasi", 2), ("Budi", "Nasi", 1), ("Saya", "Minum", 1), ("Ani", "Minum", 1)] {
            let increase = app.buttons["allocation.plus.\(item).\(person)"]
            reveal(increase, in: app)
            for _ in 0..<count { increase.tap() }
        }
        let calculate = app.buttons["Hitung pengeluaran per orang"]
        reveal(calculate, in: app); calculate.tap()
        for (person, amount) in [("Saya", "40000"), ("Ani", "65000"), ("Budi", "25000")] {
            let share = app.descendants(matching: .any).matching(identifier: "split.share.\(person)").firstMatch
            reveal(share, in: app)
            XCTAssertEqual(share.value as? String, "\(amount) Rupiah", app.debugDescription)
        }
        let save = app.buttons["Simpan tagihan"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testReportCanSelectPreviousMonth() throws {
        let app = launchDemo()
        app.buttons["nav.3"].tap()
        XCTAssertTrue(app.buttons["Bulan sebelumnya"].waitForExistence(timeout: 4))
        app.buttons["Bulan sebelumnya"].tap()
        XCTAssertTrue(app.navigationBars["Laporan"].exists)
        XCTAssertTrue(app.buttons["Bulan berikutnya"].exists)
    }

    @MainActor
    private func retainScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing-demo"]; app.launch()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            let scrollDown = element.exists && element.frame.maxY > 0 && element.frame.maxY < app.frame.minY + 120
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.2 : 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.45 : 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Element not reachable: \(element)\n\(app.debugDescription)")
    }
}
