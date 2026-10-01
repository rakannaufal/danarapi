import Foundation

enum ExportService {
    static func exportCSVs(snapshot: DashboardSnapshot) -> [String: String] {
        [
            "personal_expenses.csv": "\u{FEFF}" + personalExpensesCSV(snapshot),
            "cash_flow.csv": "\u{FEFF}" + cashFlowCSV(snapshot),
            "split_bills.csv": "\u{FEFF}" + splitBillsCSV(snapshot),
            "split_members.csv": "\u{FEFF}" + splitMembersCSV(snapshot),
            "split_settlements.csv": "\u{FEFF}" + splitSettlementsCSV(snapshot),
            "split_resolutions.csv": "\u{FEFF}" + splitResolutionsCSV(snapshot)
        ]
    }
    static func createDemoArchive(snapshot: DashboardSnapshot) throws -> URL {
        let files: [(String, Data)] = try [
            ("data-v1.json", JSONSerialization.data(withJSONObject: snapshotJSON(snapshot), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])),
            ("personal_expenses.csv", csvData(personalExpensesCSV(snapshot))),
            ("cash_flow.csv", csvData(cashFlowCSV(snapshot))),
            ("split_bills.csv", csvData(splitBillsCSV(snapshot))),
            ("split_members.csv", csvData(splitMembersCSV(snapshot))),
            ("split_settlements.csv", csvData(splitSettlementsCSV(snapshot))),
            ("split_resolutions.csv", csvData(splitResolutionsCSV(snapshot)))
        ]
        let manifest: [String: Any] = [
            "schema_version": "1.0.0",
            "synthetic": true,
            "created_at": ISO8601DateFormatter().string(from: .now),
            "file_count": files.count,
            "total_size_bytes": String(files.reduce(0) { $0 + $1.1.count }),
            "files": files.map { ["name": $0.0, "size_bytes": String($0.1.count), "checksum_crc32": String(format: "%08x", CRC32.checksum($0.1))] }
        ]
        var archiveFiles = files
        archiveFiles.append(("manifest.json", try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])))
        let url = FileManager.default.temporaryDirectory.appending(path: "Danarapi-Export-\(UUID().uuidString).zip")
        try StoredZIP.write(files: archiveFiles, to: url)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        return url
    }

    private static func personalExpensesCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["event_id,source_bill_id,occurred_at,type,amount,category,merchant,is_non_cash"]
        for item in snapshot.transactions where !item.deleted && item.kind == .expense {
            rows.append(row([item.id, "", iso(item.occurredAt), item.kind.rawValue, String(item.amount), categoryName(item.categoryID, snapshot), item.merchant ?? "", "false"], numericColumns: [4]))
        }
        for bill in snapshot.splitBills where !bill.deleted {
            rows.append(row([bill.id, bill.id, iso(bill.occurredAt), "split_personal_share", String(bill.selfShare), categoryName(bill.categoryID, snapshot), bill.title, "false"], numericColumns: [4]))
            for event in bill.resolutions where !event.reversed && event.kind == .receivableWriteoff {
                rows.append(row([event.id, bill.id, iso(event.occurredAt), event.kind.rawValue, String(event.amount), categoryName(bill.categoryID, snapshot), bill.title, "true"], numericColumns: [4]))
            }
        }
        return csv(rows)
    }

    private static func cashFlowCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["event_id,source_bill_id,occurred_at,type,amount,account,note"]
        for item in snapshot.transactions where !item.deleted {
            let signed = item.kind == .income ? item.amount : -item.amount
            rows.append(row([item.id, "", iso(item.occurredAt), item.kind.rawValue, String(signed), accountName(item.accountID, snapshot), item.note ?? ""], numericColumns: [4]))
        }
        for transfer in snapshot.transfers where !transfer.deleted {
            rows.append(row([transfer.id + "-out", "", iso(transfer.occurredAt), "transfer_out", String(-transfer.amount), accountName(transfer.fromAccountID, snapshot), transfer.note ?? ""], numericColumns: [4]))
            rows.append(row([transfer.id + "-in", "", iso(transfer.occurredAt), "transfer_in", String(transfer.amount), accountName(transfer.toAccountID, snapshot), transfer.note ?? ""], numericColumns: [4]))
        }
        for bill in snapshot.splitBills where !bill.deleted {
            if case let .selfPaid(accountID) = bill.payer {
                rows.append(row([bill.id, bill.id, iso(bill.occurredAt), "split_bill_paid", String(-bill.total), accountName(accountID, snapshot), bill.title], numericColumns: [4]))
            }
            for event in bill.settlements where !event.reversed {
                let signed = event.direction == .incoming ? event.amount : -event.amount
                rows.append(row([event.id, bill.id, iso(event.occurredAt), "split_settlement_\(event.direction.rawValue)", String(signed), accountName(event.accountID, snapshot), event.note ?? ""], numericColumns: [4]))
            }
        }
        return csv(rows)
    }

    private static func splitBillsCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["source_bill_id,occurred_at,title,total,payer,self_share,status,remaining"]
        for bill in snapshot.splitBills where !bill.deleted {
            let payer = switch bill.payer { case .selfPaid: "Saya"; case let .other(memberID): bill.members.first(where: { $0.id == memberID })?.displayName ?? "" }
            rows.append(row([bill.id, iso(bill.occurredAt), bill.title, String(bill.total), payer, String(bill.selfShare), bill.status.rawValue, String(bill.remainingAmount)], numericColumns: [3, 5, 7]))
        }
        return csv(rows)
    }

    private static func splitMembersCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["source_bill_id,member_id,display_name,is_self,share_amount,settled_amount,resolved_amount,remaining_amount"]
        for bill in snapshot.splitBills where !bill.deleted {
            for member in bill.members {
                let remaining = bill.obligationMembers.contains(where: { $0.id == member.id }) ? member.remainingAmount : 0
                rows.append(row([bill.id, member.id, member.displayName, String(member.isSelf), String(member.shareAmount), String(member.settledAmount), String(member.resolvedAmount), String(remaining)], numericColumns: [4, 5, 6, 7]))
            }
        }
        return csv(rows)
    }

    private static func splitSettlementsCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["event_id,source_bill_id,member_id,direction,account,amount,occurred_at,reversed,note"]
        for bill in snapshot.splitBills where !bill.deleted {
            for event in bill.settlements {
                rows.append(row([event.id, bill.id, event.memberID, event.direction.rawValue, accountName(event.accountID, snapshot), String(event.amount), iso(event.occurredAt), String(event.reversed), event.note ?? ""], numericColumns: [5]))
            }
        }
        return csv(rows)
    }

    private static func splitResolutionsCSV(_ snapshot: DashboardSnapshot) -> String {
        var rows = ["event_id,source_bill_id,member_id,kind,amount,occurred_at,reversed,reason"]
        for bill in snapshot.splitBills where !bill.deleted {
            for event in bill.resolutions {
                rows.append(row([event.id, bill.id, event.memberID, event.kind.rawValue, String(event.amount), iso(event.occurredAt), String(event.reversed), event.reason], numericColumns: [4]))
            }
        }
        return csv(rows)
    }

    private static func snapshotJSON(_ snapshot: DashboardSnapshot) -> [String: Any] {
        [
            "schema_version": "1.0.0", "currency": "IDR", "synthetic": true,
            "overview": ["account_balance": String(snapshot.overview.accountBalance), "receivables": String(snapshot.overview.receivables), "payables": String(snapshot.overview.payables), "net_position": String(snapshot.overview.netPosition), "personal_income": String(snapshot.overview.personalIncome), "personal_expense": String(snapshot.overview.personalExpense)],
            "accounts": snapshot.accounts.map { ["id": $0.id, "name": $0.name, "kind": $0.kind.rawValue, "opening_balance": String($0.openingBalance), "balance": String($0.balance), "opened_at": iso($0.openedAt), "archived": $0.archived, "version": $0.version] },
            "categories": snapshot.categories.map { ["id": $0.id, "name": $0.name, "kind": $0.kind.rawValue, "archived": $0.archived, "sort_order": $0.sortOrder, "version": $0.version] },
            "transactions": snapshot.transactions.map { ["id": $0.id, "kind": $0.kind.rawValue, "amount": String($0.amount), "account_id": $0.accountID, "category_id": $0.categoryID, "occurred_at": iso($0.occurredAt), "merchant": jsonValue($0.merchant), "note": jsonValue($0.note), "source": $0.source, "version": $0.version] },
            "transfers": snapshot.transfers.map { ["id": $0.id, "from_account_id": $0.fromAccountID, "to_account_id": $0.toAccountID, "amount": String($0.amount), "occurred_at": iso($0.occurredAt), "note": jsonValue($0.note), "version": $0.version] },
            "split_bills": snapshot.splitBills.map { bill -> [String: Any] in
                let payer: [String: Any] = switch bill.payer {
                case let .selfPaid(accountID): ["kind": "self", "account_id": accountID]
                case let .other(memberID): ["kind": "other", "member_id": memberID]
                }
                return [
                    "id": bill.id, "title": bill.title, "total": String(bill.total), "category_id": bill.categoryID,
                    "payer": payer, "occurred_at": iso(bill.occurredAt), "note": jsonValue(bill.note), "version": bill.version,
                    "item_split": bill.itemSplit.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder.danarapi.encode($0)) } ?? NSNull(),
                    "members": bill.members.map { ["id": $0.id, "display_name": $0.displayName, "is_self": $0.isSelf, "share_amount": String($0.shareAmount), "settled_amount": String($0.settledAmount), "resolved_amount": String($0.resolvedAmount), "sort_order": $0.sortOrder] },
                    "settlements": bill.settlements.map { ["id": $0.id, "member_id": $0.memberID, "direction": $0.direction.rawValue, "account_id": $0.accountID, "amount": String($0.amount), "occurred_at": iso($0.occurredAt), "note": jsonValue($0.note), "reversed": $0.reversed, "version": $0.version] },
                    "resolutions": bill.resolutions.map { ["id": $0.id, "member_id": $0.memberID, "kind": $0.kind.rawValue, "amount": String($0.amount), "occurred_at": iso($0.occurredAt), "reason": $0.reason, "reversed": $0.reversed, "version": $0.version] }
                ]
            },
            "review_items": snapshot.reviewItems.map { ["id": $0.id, "source": $0.source.rawValue, "status": $0.status.rawValue, "amount": jsonValue($0.amount.value), "merchant": jsonValue($0.merchant.value), "date": jsonValue($0.date.value), "attachment_name": jsonValue($0.attachmentName), "created_at": iso($0.createdAt)] },
            "merchant_rules": snapshot.merchantRules.map { ["id": $0.id, "match_type": $0.matchType.rawValue, "normalized_pattern": $0.normalizedPattern, "category_id": $0.categoryID, "priority": $0.priority, "version": $0.version] },
            "budgets": snapshot.budgets.map { ["id": $0.id, "category_id": $0.categoryID, "month": iso($0.month), "limit_amount": String($0.limitAmount), "spent_amount": String($0.spentAmount)] },
            "goals": (snapshot.goals ?? []).map { ["id": $0.id, "name": $0.name, "target_amount": String($0.targetAmount), "saved_amount": String($0.savedAmount), "target_date": $0.targetDate.map(iso) as Any? ?? NSNull(), "version": $0.version] }
        ]
    }

    private static func categoryName(_ id: String, _ snapshot: DashboardSnapshot) -> String { snapshot.categories.first(where: { $0.id == id })?.name ?? "" }
    private static func accountName(_ id: String, _ snapshot: DashboardSnapshot) -> String { snapshot.accounts.first(where: { $0.id == id })?.name ?? id }
    private static func jsonValue(_ value: String?) -> Any { value ?? NSNull() as Any }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func csvData(_ value: String) -> Data { Data(("\u{FEFF}" + value).utf8) }
    private static func csv(_ rows: [String]) -> String { rows.joined(separator: "\r\n") + "\r\n" }
    private static func row(_ values: [String], numericColumns: Set<Int> = []) -> String {
        values.enumerated().map { index, value in
            if numericColumns.contains(index), DecimalString.isDecimal(value), Int64(value) != nil { return "\"" + value + "\"" }
            return safe(value)
        }.joined(separator: ",")
    }
    private static func safe(_ value: String) -> String {
        var escaped = value
        if let first = escaped.first, "=+-@\t\r".contains(first) { escaped = "'" + escaped }
        return "\"" + escaped.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private enum StoredZIP {
    static func write(files: [(String, Data)], to url: URL) throws {
        var output = Data()
        var central = Data()
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let offset = UInt32(output.count)
            let crc = CRC32.checksum(data)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800)); output.appendLE(UInt16(0))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(crc); output.appendLE(UInt32(data.count)); output.appendLE(UInt32(data.count))
            output.appendLE(UInt16(nameData.count)); output.appendLE(UInt16(0)); output.append(nameData); output.append(data)
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0x0800)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(crc); central.appendLE(UInt32(data.count)); central.appendLE(UInt32(data.count))
            central.appendLE(UInt16(nameData.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt32(0)); central.appendLE(offset); central.append(nameData)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(files.count)); output.appendLE(UInt16(files.count))
        output.appendLE(UInt32(central.count)); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        try output.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
