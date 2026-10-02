import XCTest

final class DanarapiAppUITests: XCTestCase {
    @MainActor
    func testDemoOnboardingFullTourInLightAndDark() throws {
        XCUIDevice.shared.orientation = .portrait
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-auth", "-theme", theme]
            app.launch()
            let demo = app.buttons["Coba Demo tanpa akun"]
            XCTAssertTrue(demo.waitForExistence(timeout: 10))
            demo.tap()
            XCTAssertTrue(app.staticTexts["Struk jadi catatan"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["nav.scan"].exists)
            for title in ["Lanjut", "Lewati tur"] {
                let button = app.buttons[title]
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertLessThanOrEqual(button.frame.maxY, app.windows.firstMatch.frame.maxY)
            }
            retainScreenshot("Onboarding pertama \(theme)", in: app)
            app.buttons["Lanjut"].tap()
            XCTAssertTrue(app.staticTexts["Rencana lebih terarah"].isHittable)
            retainScreenshot("Onboarding kedua \(theme)", in: app)
            app.staticTexts["Rencana lebih terarah"].swipeRight()
            XCTAssertTrue(app.staticTexts["Struk jadi catatan"].isHittable)
            app.buttons["Lanjut"].tap()
            app.buttons["Lanjut"].tap()
            let start = app.buttons["Mulai mencatat"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Bagi tagihan, tanpa ribet"].isHittable)
            XCTAssertTrue(start.isHittable)
            XCTAssertGreaterThanOrEqual(start.frame.height, 44)
            retainScreenshot("Onboarding terakhir \(theme)", in: app)
            start.tap()
            XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["nav.scan"].isHittable)
            XCTAssertFalse(app.buttons["Lewati tur"].exists)
            XCTAssertFalse(app.alerts["Belum berhasil"].exists)
            retainScreenshot("Beranda setelah onboarding \(theme)", in: app)
            app.terminate()
        }
    }

    @MainActor
    func testDemoOnboardingSkipAndReentry() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        for _ in 0..<2 {
            app.launch()
            XCTAssertTrue(app.staticTexts["Struk jadi catatan"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Tambah catatan"].exists)
            app.buttons["Lewati tur"].tap()
            XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["auth.google"].exists)
            XCTAssertFalse(app.alerts["Belum berhasil"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testDemoOnboardingHelpReturnsToCurrentPage() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Lanjut"].waitForExistence(timeout: 10))
        app.buttons["Lanjut"].tap()
        app.buttons["Tentang & bantuan"].tap()
        XCTAssertTrue(app.buttons["Kebijakan privasi"].waitForExistence(timeout: 5))
        app.buttons["Kebijakan privasi"].tap()
        XCTAssertTrue(app.navigationBars["Kebijakan privasi"].waitForExistence(timeout: 5))
        retainScreenshot("Privasi dari onboarding demo", in: app)
        app.buttons["Selesai"].tap()
        XCTAssertTrue(app.staticTexts["Rencana lebih terarah"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rencana lebih terarah"].isHittable)
        app.buttons["Lewati tur"].tap()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testPublicHelpFromLogin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-auth"]
        app.launch()
        XCTAssertTrue(app.buttons["Tentang & bantuan"].waitForExistence(timeout: 8))
        app.buttons["Tentang & bantuan"].tap()
        app.buttons["Kebijakan privasi"].tap()
        XCTAssertTrue(app.navigationBars["Kebijakan privasi"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Penyedia layanan"].exists)
    }
    @MainActor
    func testStartupShowsLogoWithoutPrematureNetworkError() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-startup", "--ui-testing-auth"]
        app.launch()
        XCTAssertTrue(app.images["startup.logo"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Data belum dapat dimuat"].exists)
        XCTAssertFalse(app.buttons["Coba lagi"].exists)
        retainScreenshot("Logo pembuka", in: app)
        app.terminate()
        app.launchArguments = ["--ui-testing-auth"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.google"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.images["startup.logo"].exists)
    }

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
        app.navigationBars["Akun"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ringkasan keuangan"].waitForExistence(timeout: 5))
        let income = app.buttons["home.income"]
        XCTAssertTrue(income.waitForExistence(timeout: 5)); income.tap()
        XCTAssertTrue(app.navigationBars["Pemasukan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pemasukan · Bulan ini"].exists)
        app.navigationBars["Pemasukan"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ringkasan keuangan"].waitForExistence(timeout: 5))
        let expense = app.buttons["home.expense"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5)); expense.tap()
        XCTAssertTrue(app.navigationBars["Pengeluaran"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pengeluaran · Bulan ini"].exists)
        retainScreenshot("Beranda pengeluaran terfilter", in: app)
        app.navigationBars["Pengeluaran"].buttons.firstMatch.tap()
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
        XCTAssertTrue(app.navigationBars["Transaksi"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["DRAFT UI DEMO"].isHittable)
    }

    @MainActor
    func testOutsideTapDismissesKeyboardWithoutLosingInput() throws {
        let app = launchDemo()
        app.buttons["Tambah catatan"].tap()
        app.buttons["Pengeluaran"].tap()
        let amount = app.textFields["money.Nominal"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("5000")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars["Tambah transaksi"].staticTexts["Tambah transaksi"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "5.000")
        let merchant = app.textFields["Nama merchant"]
        merchant.tap()
        merchant.typeText("TOKO KEYBOARD")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        reveal(amount, in: app)
        amount.tap()
        let reopened = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        if !reopened { retainScreenshot("Keyboard saat berpindah input", in: app) }
        XCTAssertTrue(reopened, app.debugDescription)
        XCTAssertEqual(merchant.value as? String, "TOKO KEYBOARD")
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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        let category = app.textFields["Nama kategori baru"]
        reveal(category, in: app)
        retainScreenshot("Anggaran sebelum pindah input", in: app)
        category.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        retainScreenshot("Anggaran sesudah pindah input", in: app)
        category.typeText("Hobi UI")
        XCTAssertEqual(category.value as? String, "Hobi UI")
        let create = app.buttons["Buat kategori dan pilih"]
        reveal(create, in: app); create.tap()
        let save = app.buttons["Simpan anggaran"]
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.navigationBars["Tambah anggaran"].waitForNonExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Hobi UI"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testNewSplitBillStartsWithSelfAndUsesAddIconsInBothModes() throws {
        let app = launchDemo()
        app.buttons["Tambah catatan"].tap(); app.buttons["Split bill"].tap()
        let fields = app.textFields.matching(identifier: "Nama peserta")
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.firstMatch.value as? String, "Saya")
        let add = app.buttons["split.addPerson"]
        XCTAssertTrue(add.exists)
        XCTAssertEqual(add.label, "Tambah orang")
        XCTAssertGreaterThanOrEqual(add.frame.width, 44)
        XCTAssertFalse(add.isEnabled)
        let name = app.textFields["Nama orang"]
        name.tap(); name.typeText("Raka"); add.tap()
        XCTAssertEqual(fields.count, 2)
        dismissSplitKeyboard(in: app)
        retainScreenshot("Peserta split bill", in: app)
        app.buttons["Hapus peserta Raka"].tap()
        XCTAssertEqual(fields.count, 1)
        app.buttons["Bagi total saja (sama rata / manual)"].tap()
        let names = app.textFields.matching(identifier: "Nama")
        XCTAssertTrue(names.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(names.firstMatch.value as? String, "Saya")
        let addTotal = app.buttons["split.addParticipant"]
        reveal(addTotal, in: app); addTotal.tap()
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(names.element(boundBy: 1).value as? String, "Nama")
        retainScreenshot("Peserta pembagian total", in: app)
    }

    @MainActor
    func testItemSplitFromReceiptTextUsesSharedMenusAndProportionalFees() throws {
        let app = launchDemo()
        app.buttons["Tambah catatan"].tap(); app.buttons["Split bill"].tap()
        let title = app.textFields["Judul tagihan"]
        XCTAssertTrue(title.waitForExistence(timeout: 4)); title.tap(); title.typeText("Makan bersama UI")
        dismissSplitKeyboard(in: app)
        XCTAssertEqual(app.textFields.matching(identifier: "Nama peserta").count, 1)
        for person in ["Ani", "Budi"] {
            let name = app.textFields["Nama orang"]
            reveal(name, in: app); name.tap(); name.typeText(person)
            app.buttons["split.addPerson"].tap()
        }
        dismissSplitKeyboard(in: app)
        let paste = app.buttons["Tempel teks struk"]
        reveal(paste, in: app); paste.tap()
        let text = app.textViews["receipt.menu.text"]
        reveal(text, in: app); text.tap(); text.typeText("Nasi 4 x 25000\nMinum 2 x 15000")
        dismissSplitKeyboard(in: app)
        let read = app.buttons["Baca menu dari teks"]
        reveal(read, in: app); read.tap()
        for (person, item) in [("Saya", "Nasi"), ("Ani", "Nasi"), ("Budi", "Nasi"), ("Saya", "Minum"), ("Ani", "Minum")] {
            let owner = app.switches["\(person), pemesan \(item)"]
            reveal(owner, in: app)
            owner.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: owner)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
        }
        for (person, amount) in [("Saya", "55585"), ("Ani", "55583"), ("Budi", "38332")] {
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
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(withDescription: "System undo typing") { alert in
            guard alert.label == "Undo Typing", alert.buttons["Cancel"].exists else { return false }
            alert.buttons["Cancel"].tap()
            return true
        }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing-demo"]; app.launch()
        XCTAssertTrue(app.buttons["Lewati tur"].waitForExistence(timeout: 10))
        app.buttons["Lewati tur"].tap()
        XCTAssertTrue(app.buttons["Tambah catatan"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func dismissSplitKeyboard(in app: XCUIApplication) {
        let button = app.buttons["split.keyboardDone"].firstMatch
        if button.exists && button.isHittable { button.tap() }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            let typingAlert = app.alerts["Undo Typing"]
            if typingAlert.exists && typingAlert.buttons["Cancel"].isHittable {
                retainScreenshot("System undo typing interruption", in: app)
                typingAlert.buttons["Cancel"].tap()
            }
            let top = app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.frame.maxY }.max() ?? app.frame.minY
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = keyboard.exists
            let bottom = keyboardVisible ? keyboard.frame.minY : app.frame.maxY - 34
            let clearance: CGFloat = keyboardVisible ? 32 : 8
            if element.exists && element.isHittable && element.frame.minY > top + 8 && element.frame.maxY < bottom - clearance { return }
            let scrollDown = element.exists && element.frame.midY < top + 8
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.2 : 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.45 : 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Element not reachable: \(element)\n\(app.debugDescription)")
    }
}
