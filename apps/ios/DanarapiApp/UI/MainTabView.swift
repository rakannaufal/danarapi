import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var selection = 0
    @State private var visitedTabs: Set<Int> = [0]
    @State private var showAdd = false
    @State private var showScan = false
    private let navigationHeight: CGFloat = 68
    private let scanLift: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if !app.network.isOnline && app.mode == .authenticated {
                Label("Offline — \(app.pendingOutboxCount) perubahan menunggu sinkronisasi", systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7).background(Color.danarapiPeach)
            }
            ZStack {
                tabContent(0) { HomeView(onAdd: { showAdd = true }) }
                tabContent(1) { TransactionsView() }
                tabContent(3) { ReportsView() }
                tabContent(4) { SettingsView() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomNavigation }
        .tint(.danarapiPrimary)
        .sheet(isPresented: $showAdd) { AddMenuView().presentationDragIndicator(.visible).presentationCornerRadius(24) }
        .fullScreenCover(isPresented: $showScan) { ScanHubView() }
        .onChange(of: selection) { _, value in visitedTabs.insert(value) }
        .onChange(of: app.network.isOnline) { _, online in
            if online { Task { await app.syncOutbox() } }
        }
    }

    private var bottomNavigation: some View {
        HStack(alignment: .bottom, spacing: 0) {
            navigationItem("Beranda", icon: "house", selectedIcon: "house.fill", tag: 0)
            navigationItem("Transaksi", icon: "list.bullet.rectangle", selectedIcon: "list.bullet.rectangle.fill", tag: 1)
            Button { showScan = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "viewfinder").font(.system(size: 27, weight: .semibold))
                        .frame(width: 60, height: 60).background(Color.danarapiPrimary, in: Circle())
                        .foregroundStyle(Color.danarapiOnPrimary)
                        .overlay { Circle().stroke(Color.danarapiSurface, lineWidth: 5) }
                        .shadow(color: Color.danarapiInk.opacity(0.12), radius: 6, y: 3)
                    Text("Scan").font(.caption2.weight(.medium)).foregroundStyle(Color.danarapiPrimary)
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, minHeight: navigationHeight + scanLift, alignment: .bottom)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Scan struk atau QRIS").accessibilityIdentifier("nav.scan")
            navigationItem("Laporan", icon: "chart.bar", selectedIcon: "chart.bar.fill", tag: 3)
            navigationItem("Pengaturan", icon: "gearshape", selectedIcon: "gearshape.fill", tag: 4)
        }
        .padding(.horizontal, 8)
        .background {
            VStack(spacing: 0) {
                Color.clear.frame(height: scanLift)
                Color.danarapiSurface
                    .overlay(alignment: .top) { Rectangle().fill(Color.danarapiBorder).frame(height: 0.5) }
            }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func tabContent<Content: View>(_ tag: Int, @ViewBuilder content: () -> Content) -> some View {
        if visitedTabs.contains(tag) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selection == tag ? 1 : 0)
                .allowsHitTesting(selection == tag)
                .accessibilityHidden(selection != tag)
                .zIndex(selection == tag ? 1 : 0)
        }
    }

    private func navigationItem(_ title: String, icon: String, selectedIcon: String, tag: Int) -> some View {
        Button { selection = tag } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == tag ? selectedIcon : icon).font(.system(size: 21, weight: .regular)).frame(height: 28)
                Text(title).font(.caption2.weight(selection == tag ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(selection == tag ? Color.danarapiPrimary : Color.danarapiMuted)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, minHeight: navigationHeight, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier("nav.\(tag)")
        .accessibilityAddTraits(selection == tag ? .isSelected : [])
    }
}

private struct AddMenuView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var destination: AddDestination?

    var body: some View {
        NavigationStack {
            List {
                Section("Catat") {
                    row("Pengeluaran", "minus.circle.fill", .transaction(.expense), .danarapiPeach)
                    row("Pemasukan", "plus.circle.fill", .transaction(.income), .danarapiMint)
                    row("Anggaran", "chart.pie.fill", .budget, .danarapiSky)
                        .disabled(app.mode == .authenticated && !app.network.isOnline)
                    row("Target", "target", .goal, .danarapiMint)
                        .disabled(app.mode == .authenticated && !app.network.isOnline)
                    row("Split bill", "person.3.fill", .splitBill, .danarapiLavender)
                        .disabled(app.mode == .authenticated && !app.network.isOnline)
                }
                Section("Impor") {
                    row("Pindai QRIS", "qrcode.viewfinder", .scanner, .danarapiMint)
                    row("Impor bukti", "square.and.arrow.down", .importer, .danarapiSun)
                }
                .disabled(app.mode == .authenticated && !app.network.isOnline)
                if app.mode == .authenticated && !app.network.isOnline {
                    Section { Text("Anggaran, target, split bill, dan impor memerlukan koneksi.") }
                }
            }
            .navigationTitle("Tambah").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
            .navigationDestination(item: $destination) { target in
                switch target {
                case let .transaction(kind): TransactionFormView(kind: kind) { dismiss() }
                case .transfer: TransferFormView { dismiss() }
                case .budget: BudgetEditorView(budget: nil, onSaved: { dismiss() })
                case .goal: GoalEditorView(goal: nil, onSaved: { dismiss() })
                case .splitBill: ItemSplitFormView { dismiss() }
                case .scanner: ScanHubView(initialMode: .qris)
                case .importer: ImportView { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ icon: String, _ target: AddDestination, _ color: Color) -> some View {
        Button { destination = target } label: {
            Label { Text(title).foregroundStyle(Color.danarapiInk) } icon: {
                Image(systemName: icon).foregroundStyle(Color.danarapiInk).frame(width: 34, height: 34).background(color, in: RoundedRectangle(cornerRadius: 10))
            }.frame(minHeight: 46)
        }
    }
}

private enum AddDestination: Hashable, Identifiable {
    case transaction(TransactionKind), transfer, budget, goal, splitBill, scanner, importer
    var id: String { String(describing: self) }
}
