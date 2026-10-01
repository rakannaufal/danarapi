import Foundation

public struct EqualParticipant: Equatable, Sendable {
    public let id: String
    public let included: Bool

    public init(id: String, included: Bool) {
        self.id = id
        self.included = included
    }
}

public struct PercentageParticipant: Equatable, Sendable {
    public let id: String
    public let basisPoints: Int

    public init(id: String, basisPoints: Int) {
        self.id = id
        self.basisPoints = basisPoints
    }
}

public enum SplitCalculator {
    public static func equal(total value: String, participants: [EqualParticipant]) throws -> [String: String] {
        let total = try Money.parse(value)
        let includedCount = participants.filter(\.included).count
        guard (2...20).contains(participants.count), includedCount > 0 else { throw ContractError.validation }

        let divisor = Int64(includedCount)
        let base = total / divisor
        var remainder = total % divisor
        var result: [String: String] = [:]
        for participant in participants {
            guard participant.included else {
                result[participant.id] = "0"
                continue
            }
            let extra: Int64 = remainder > 0 ? 1 : 0
            result[participant.id] = try Money.encode(base + extra)
            remainder -= extra
        }
        return result
    }

    public static func percentage(total value: String, participants: [PercentageParticipant]) throws -> [String: String] {
        let total = try Money.parse(value)
        guard (2...20).contains(participants.count),
              participants.allSatisfy({ (0...10_000).contains($0.basisPoints) }),
              participants.reduce(0, { $0 + $1.basisPoints }) == 10_000
        else { throw ContractError.validation }

        struct Row {
            let id: String
            let order: Int
            var amount: Int64
            let fractional: Int64
        }

        var rows = participants.enumerated().map { order, participant in
            let numerator = total * Int64(participant.basisPoints)
            return Row(id: participant.id, order: order, amount: numerator / 10_000, fractional: numerator % 10_000)
        }
        var remainder = total - rows.reduce(0, { $0 + $1.amount })
        let rankedIndexes = rows.indices.sorted {
            rows[$0].fractional == rows[$1].fractional
                ? rows[$0].order < rows[$1].order
                : rows[$0].fractional > rows[$1].fractional
        }
        var rank = 0
        while remainder > 0 {
            rows[rankedIndexes[rank]].amount += 1
            rank += 1
            remainder -= 1
        }
        return try Dictionary(uniqueKeysWithValues: rows.map { ($0.id, try Money.encode($0.amount)) })
    }
}

