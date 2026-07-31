import Foundation

public enum ReactionKind: String, CaseIterable, Codable, Sendable {
    case composite
    case hybrid
    case biochemical
}

public enum ReactionSecurityBand: String, CaseIterable, Codable, Sendable {
    case lowSecurity
    case nullSecurityOrWormhole
}

public enum ReactionPlanningMode: String, Codable, Sendable {
    case neutralBase
    case modified
}

public struct ReactionFacilityRule: Equatable, Codable, Sendable {
    public let typeID: Int64
    public let timeMultiplierBasisPoints: Int64

    public init(typeID: Int64, timeMultiplierBasisPoints: Int64) {
        self.typeID = typeID
        self.timeMultiplierBasisPoints = timeMultiplierBasisPoints
    }
}

public struct ReactionReactorRule: Equatable, Codable, Sendable {
    public let typeID: Int64
    public let kind: ReactionKind

    public init(typeID: Int64, kind: ReactionKind) {
        self.typeID = typeID
        self.kind = kind
    }
}

public struct ReactionRigRule: Equatable, Codable, Sendable {
    public let typeID: Int64
    public let supportedKinds: [ReactionKind]
    public let timeBonusBasisPoints: Int64
    public let materialBonusBasisPoints: Int64
    public let lowSecurityBonusMultiplierPermille: Int64
    public let nullSecurityBonusMultiplierPermille: Int64

    public init(
        typeID: Int64,
        supportedKinds: [ReactionKind],
        timeBonusBasisPoints: Int64,
        materialBonusBasisPoints: Int64,
        lowSecurityBonusMultiplierPermille: Int64,
        nullSecurityBonusMultiplierPermille: Int64
    ) {
        self.typeID = typeID
        self.supportedKinds = supportedKinds.sorted {
            $0.rawValue < $1.rawValue
        }
        self.timeBonusBasisPoints = timeBonusBasisPoints
        self.materialBonusBasisPoints = materialBonusBasisPoints
        self.lowSecurityBonusMultiplierPermille =
            lowSecurityBonusMultiplierPermille
        self.nullSecurityBonusMultiplierPermille =
            nullSecurityBonusMultiplierPermille
    }
}

public struct ReactionRuleProfile: Equatable, Codable, Sendable {
    public static let currentVersion = 1
    public static let materialFormulaVersion = 1
    public static let timeFormulaVersion = 1

    public let version: Int
    public let materialFormulaVersion: Int
    public let timeFormulaVersion: Int
    public let catalogBuildNumber: Int
    public let catalogContentSHA256: String
    public let verificationStatus: IndustryRuleVerificationStatus
    public let verifiedAt: Date
    public let sourceURLs: [String]
    public let formulaGroupKinds: [Int64: ReactionKind]
    public let facilities: [ReactionFacilityRule]
    public let reactors: [ReactionReactorRule]
    public let rigs: [ReactionRigRule]
    public let reactionsSkillTypeID: Int64
    public let skillTimeBonusBasisPointsPerLevel: Int64

    public init(
        version: Int = Self.currentVersion,
        materialFormulaVersion: Int = Self.materialFormulaVersion,
        timeFormulaVersion: Int = Self.timeFormulaVersion,
        catalogBuildNumber: Int,
        catalogContentSHA256: String,
        verificationStatus: IndustryRuleVerificationStatus,
        verifiedAt: Date,
        sourceURLs: [String],
        formulaGroupKinds: [Int64: ReactionKind],
        facilities: [ReactionFacilityRule],
        reactors: [ReactionReactorRule],
        rigs: [ReactionRigRule],
        reactionsSkillTypeID: Int64,
        skillTimeBonusBasisPointsPerLevel: Int64
    ) {
        self.version = version
        self.materialFormulaVersion = materialFormulaVersion
        self.timeFormulaVersion = timeFormulaVersion
        self.catalogBuildNumber = catalogBuildNumber
        self.catalogContentSHA256 = catalogContentSHA256
        self.verificationStatus = verificationStatus
        self.verifiedAt = verifiedAt
        self.sourceURLs = sourceURLs.sorted()
        self.formulaGroupKinds = formulaGroupKinds
        self.facilities = facilities.sorted { $0.typeID < $1.typeID }
        self.reactors = reactors.sorted { $0.typeID < $1.typeID }
        self.rigs = rigs.sorted { $0.typeID < $1.typeID }
        self.reactionsSkillTypeID = reactionsSkillTypeID
        self.skillTimeBonusBasisPointsPerLevel =
            skillTimeBonusBasisPointsPerLevel
    }
}

public struct ReactionPlanningContext: Equatable, Codable, Sendable {
    public let mode: ReactionPlanningMode
    public let facilityTypeID: Int64?
    public let reactorTypeID: Int64?
    public let rigTypeIDs: [Int64]
    public let securityBand: ReactionSecurityBand?
    public let reactionsSkillLevel: Int
    public let ruleVersion: Int
    public let catalogBuildNumber: Int
    public let catalogContentSHA256: String

    public init(
        mode: ReactionPlanningMode,
        facilityTypeID: Int64?,
        reactorTypeID: Int64?,
        rigTypeIDs: [Int64],
        securityBand: ReactionSecurityBand?,
        reactionsSkillLevel: Int,
        ruleVersion: Int,
        catalogBuildNumber: Int,
        catalogContentSHA256: String
    ) {
        self.mode = mode
        self.facilityTypeID = facilityTypeID
        self.reactorTypeID = reactorTypeID
        self.rigTypeIDs = rigTypeIDs.sorted()
        self.securityBand = securityBand
        self.reactionsSkillLevel = reactionsSkillLevel
        self.ruleVersion = ruleVersion
        self.catalogBuildNumber = catalogBuildNumber
        self.catalogContentSHA256 = catalogContentSHA256
    }

    public static func neutral(
        profile: ReactionRuleProfile
    ) -> ReactionPlanningContext {
        ReactionPlanningContext(
            mode: .neutralBase,
            facilityTypeID: nil,
            reactorTypeID: nil,
            rigTypeIDs: [],
            securityBand: nil,
            reactionsSkillLevel: 0,
            ruleVersion: profile.version,
            catalogBuildNumber: profile.catalogBuildNumber,
            catalogContentSHA256: profile.catalogContentSHA256
        )
    }
}

public enum ReactionCalculationError: Error, Equatable, Sendable {
    case unsupportedRuleVersion(Int)
    case unsupportedMaterialFormulaVersion(Int)
    case unsupportedTimeFormulaVersion(Int)
    case rulesNeedReview
    case catalogVersionMismatch
    case unknownFormulaGroup(Int64)
    case invalidBaseQuantity(Int64)
    case invalidRuns(Int64)
    case invalidBaseTime(Int64)
    case invalidNeutralContext
    case missingFacility
    case unknownFacility(Int64)
    case missingReactor
    case unknownReactor(Int64)
    case wrongReactor(expected: ReactionKind, actual: ReactionKind)
    case missingSecurityBand
    case invalidSkillLevel(Int)
    case unknownRig(Int64)
    case incompatibleRig(typeID: Int64, kind: ReactionKind)
    case duplicateRig(Int64)
    case multipleMaterialRigs
    case multipleTimeRigs
    case arithmeticOverflow
    case inconsistentPersistedValues
}

public struct ReactionResolvedModifiers: Equatable, Codable, Sendable {
    public let facilityTimeFactorBasisPoints: Int64
    public let skillTimeFactorBasisPoints: Int64
    public let rigTimeFactorBasisPoints: Int64
    public let rigMaterialFactorBasisPoints: Int64
    public let securityBonusMultiplierPermille: Int64

    public init(
        facilityTimeFactorBasisPoints: Int64,
        skillTimeFactorBasisPoints: Int64,
        rigTimeFactorBasisPoints: Int64,
        rigMaterialFactorBasisPoints: Int64,
        securityBonusMultiplierPermille: Int64
    ) {
        self.facilityTimeFactorBasisPoints =
            facilityTimeFactorBasisPoints
        self.skillTimeFactorBasisPoints = skillTimeFactorBasisPoints
        self.rigTimeFactorBasisPoints = rigTimeFactorBasisPoints
        self.rigMaterialFactorBasisPoints =
            rigMaterialFactorBasisPoints
        self.securityBonusMultiplierPermille =
            securityBonusMultiplierPermille
    }
}

public enum ReactionRuleValidator {
    public static func preflight(
        profile: ReactionRuleProfile,
        catalogBuildNumber: Int,
        catalogContentSHA256: String
    ) -> IndustryPreflightResult {
        guard profile.version == ReactionRuleProfile.currentVersion,
              profile.materialFormulaVersion
                == ReactionRuleProfile.materialFormulaVersion,
              profile.timeFormulaVersion
                == ReactionRuleProfile.timeFormulaVersion,
              profile.catalogBuildNumber == catalogBuildNumber,
              profile.catalogContentSHA256 == catalogContentSHA256,
              !profile.catalogContentSHA256.isEmpty,
              !profile.sourceURLs.isEmpty,
              profile.reactionsSkillTypeID > 0,
              profile.skillTimeBonusBasisPointsPerLevel == -400,
              !profile.formulaGroupKinds.isEmpty,
              Set(profile.formulaGroupKinds.values)
                == Set(ReactionKind.allCases),
              profile.formulaGroupKinds.keys.allSatisfy({ $0 > 0 }),
              Set(profile.reactors.map(\.kind))
                == Set(ReactionKind.allCases),
              profile.reactors.count == ReactionKind.allCases.count,
              Set(profile.reactors.map(\.typeID)).count
                == profile.reactors.count,
              profile.reactors.allSatisfy({ $0.typeID > 0 }),
              Set(profile.facilities.map(\.typeID)).count
                == profile.facilities.count,
              !profile.facilities.isEmpty,
              profile.facilities.allSatisfy({
                  $0.typeID > 0
                      && (1...10_000).contains(
                          $0.timeMultiplierBasisPoints
                      )
              }),
              profile.rigs.allSatisfy({
                  $0.typeID > 0
                      && !$0.supportedKinds.isEmpty
                      && Set($0.supportedKinds).count
                          == $0.supportedKinds.count
                      && $0.timeBonusBasisPoints <= 0
                      && $0.materialBonusBasisPoints <= 0
                      && 10_000 + $0.timeBonusBasisPoints > 0
                      && 10_000 + $0.materialBonusBasisPoints > 0
                      && $0.lowSecurityBonusMultiplierPermille > 0
                      && $0.nullSecurityBonusMultiplierPermille > 0
              }),
              Set(profile.rigs.map(\.typeID)).count
                == profile.rigs.count else {
            return .fail
        }
        guard profile.verificationStatus == .verified else {
            return .needsReview
        }
        return .pass
    }

    public static func reactionKind(
        formulaGroupID: Int64,
        profile: ReactionRuleProfile
    ) throws -> ReactionKind {
        guard let kind = profile.formulaGroupKinds[formulaGroupID] else {
            throw ReactionCalculationError
                .unknownFormulaGroup(formulaGroupID)
        }
        return kind
    }

    public static func resolve(
        context: ReactionPlanningContext,
        kind: ReactionKind,
        profile: ReactionRuleProfile
    ) throws -> ReactionResolvedModifiers {
        guard profile.version == ReactionRuleProfile.currentVersion else {
            throw ReactionCalculationError
                .unsupportedRuleVersion(profile.version)
        }
        guard profile.materialFormulaVersion
                == ReactionRuleProfile.materialFormulaVersion else {
            throw ReactionCalculationError
                .unsupportedMaterialFormulaVersion(
                    profile.materialFormulaVersion
                )
        }
        guard profile.timeFormulaVersion
                == ReactionRuleProfile.timeFormulaVersion else {
            throw ReactionCalculationError
                .unsupportedTimeFormulaVersion(
                    profile.timeFormulaVersion
                )
        }
        guard profile.catalogBuildNumber == context.catalogBuildNumber,
              profile.catalogContentSHA256
                == context.catalogContentSHA256,
              context.ruleVersion == profile.version else {
            throw ReactionCalculationError.catalogVersionMismatch
        }
        guard profile.verificationStatus == .verified else {
            throw ReactionCalculationError.rulesNeedReview
        }
        guard preflight(
            profile: profile,
            catalogBuildNumber: context.catalogBuildNumber,
            catalogContentSHA256: context.catalogContentSHA256
        ) == .pass else {
            throw ReactionCalculationError.rulesNeedReview
        }
        guard (0...5).contains(context.reactionsSkillLevel) else {
            throw ReactionCalculationError
                .invalidSkillLevel(context.reactionsSkillLevel)
        }
        if context.mode == .neutralBase {
            guard context.facilityTypeID == nil,
                  context.reactorTypeID == nil,
                  context.rigTypeIDs.isEmpty,
                  context.securityBand == nil,
                  context.reactionsSkillLevel == 0 else {
                throw ReactionCalculationError.invalidNeutralContext
            }
            return ReactionResolvedModifiers(
                facilityTimeFactorBasisPoints: 10_000,
                skillTimeFactorBasisPoints: 10_000,
                rigTimeFactorBasisPoints: 10_000,
                rigMaterialFactorBasisPoints: 10_000,
                securityBonusMultiplierPermille: 1_000
            )
        }

        guard let facilityTypeID = context.facilityTypeID else {
            throw ReactionCalculationError.missingFacility
        }
        guard let facility = profile.facilities.first(where: {
            $0.typeID == facilityTypeID
        }) else {
            throw ReactionCalculationError.unknownFacility(facilityTypeID)
        }
        guard let reactorTypeID = context.reactorTypeID else {
            throw ReactionCalculationError.missingReactor
        }
        guard let reactor = profile.reactors.first(where: {
            $0.typeID == reactorTypeID
        }) else {
            throw ReactionCalculationError.unknownReactor(reactorTypeID)
        }
        guard reactor.kind == kind else {
            throw ReactionCalculationError.wrongReactor(
                expected: kind,
                actual: reactor.kind
            )
        }
        guard let securityBand = context.securityBand else {
            throw ReactionCalculationError.missingSecurityBand
        }

        var timeRigs = 0
        var materialRigs = 0
        var timeBonus: Int64 = 0
        var materialBonus: Int64 = 0
        var seenRigs = Set<Int64>()
        var securityMultiplier: Int64 = 1_000
        for typeID in context.rigTypeIDs {
            guard seenRigs.insert(typeID).inserted else {
                throw ReactionCalculationError.duplicateRig(typeID)
            }
            guard let rig = profile.rigs.first(where: {
                $0.typeID == typeID
            }) else {
                throw ReactionCalculationError.unknownRig(typeID)
            }
            guard rig.supportedKinds.contains(kind) else {
                throw ReactionCalculationError.incompatibleRig(
                    typeID: typeID,
                    kind: kind
                )
            }
            let multiplier = securityBand == .lowSecurity
                ? rig.lowSecurityBonusMultiplierPermille
                : rig.nullSecurityBonusMultiplierPermille
            securityMultiplier = multiplier
            if rig.timeBonusBasisPoints != 0 {
                timeRigs += 1
                timeBonus = try scaledBonus(
                    rig.timeBonusBasisPoints,
                    multiplier: multiplier
                )
            }
            if rig.materialBonusBasisPoints != 0 {
                materialRigs += 1
                materialBonus = try scaledBonus(
                    rig.materialBonusBasisPoints,
                    multiplier: multiplier
                )
            }
        }
        guard timeRigs <= 1 else {
            throw ReactionCalculationError.multipleTimeRigs
        }
        guard materialRigs <= 1 else {
            throw ReactionCalculationError.multipleMaterialRigs
        }
        let skillBonus = Int64(context.reactionsSkillLevel)
            * profile.skillTimeBonusBasisPointsPerLevel
        return ReactionResolvedModifiers(
            facilityTimeFactorBasisPoints:
                facility.timeMultiplierBasisPoints,
            skillTimeFactorBasisPoints: 10_000 + skillBonus,
            rigTimeFactorBasisPoints: 10_000 + timeBonus,
            rigMaterialFactorBasisPoints: 10_000 + materialBonus,
            securityBonusMultiplierPermille: securityMultiplier
        )
    }

    private static func scaledBonus(
        _ bonus: Int64,
        multiplier: Int64
    ) throws -> Int64 {
        let product = bonus.multipliedReportingOverflow(by: multiplier)
        guard !product.overflow else {
            throw ReactionCalculationError.arithmeticOverflow
        }
        return product.partialValue / 1_000
    }
}

public struct ReactionMaterialCalculation:
    Equatable,
    Codable,
    Sendable
{
    public let formulaVersion: Int
    public let baseQuantityPerRun: Int64
    public let requiredRuns: Int64
    public let rawQuantity: Int64
    public let materialFactorBasisPoints: Int64
    public let effectiveQuantity: Int64
    public let savedQuantity: Int64
    public let context: ReactionPlanningContext

    public init(
        baseQuantityPerRun: Int64,
        requiredRuns: Int64,
        context: ReactionPlanningContext,
        modifiers: ReactionResolvedModifiers,
        formulaVersion: Int = ReactionRuleProfile.materialFormulaVersion
    ) throws {
        guard formulaVersion
                == ReactionRuleProfile.materialFormulaVersion else {
            throw ReactionCalculationError
                .unsupportedMaterialFormulaVersion(formulaVersion)
        }
        guard baseQuantityPerRun > 0 else {
            throw ReactionCalculationError
                .invalidBaseQuantity(baseQuantityPerRun)
        }
        guard requiredRuns > 0 else {
            throw ReactionCalculationError.invalidRuns(requiredRuns)
        }
        let raw = baseQuantityPerRun.multipliedReportingOverflow(
            by: requiredRuns
        )
        guard !raw.overflow else {
            throw ReactionCalculationError.arithmeticOverflow
        }
        let effective = try Self.ceilingMultiply(
            raw.partialValue,
            byBasisPoints: modifiers.rigMaterialFactorBasisPoints
        )
        self.formulaVersion = formulaVersion
        self.baseQuantityPerRun = baseQuantityPerRun
        self.requiredRuns = requiredRuns
        self.rawQuantity = raw.partialValue
        self.materialFactorBasisPoints =
            modifiers.rigMaterialFactorBasisPoints
        self.effectiveQuantity = effective
        self.savedQuantity = raw.partialValue - effective
        self.context = context
    }

    public func validatedCopy() throws -> ReactionMaterialCalculation {
        let modifiers = ReactionResolvedModifiers(
            facilityTimeFactorBasisPoints: 10_000,
            skillTimeFactorBasisPoints: 10_000,
            rigTimeFactorBasisPoints: 10_000,
            rigMaterialFactorBasisPoints: materialFactorBasisPoints,
            securityBonusMultiplierPermille: 1_000
        )
        let canonical = try ReactionMaterialCalculation(
            baseQuantityPerRun: baseQuantityPerRun,
            requiredRuns: requiredRuns,
            context: context,
            modifiers: modifiers,
            formulaVersion: formulaVersion
        )
        guard canonical.rawQuantity == rawQuantity,
              canonical.effectiveQuantity == effectiveQuantity,
              canonical.savedQuantity == savedQuantity else {
            throw ReactionCalculationError.inconsistentPersistedValues
        }
        return canonical
    }

    fileprivate static func ceilingMultiply(
        _ value: Int64,
        byBasisPoints factor: Int64
    ) throws -> Int64 {
        guard value >= 0, factor > 0 else {
            throw ReactionCalculationError.arithmeticOverflow
        }
        let product = value.multipliedReportingOverflow(by: factor)
        guard !product.overflow else {
            throw ReactionCalculationError.arithmeticOverflow
        }
        let quotient = product.partialValue / 10_000
        let remainder = product.partialValue % 10_000
        return quotient + (remainder == 0 ? 0 : 1)
    }

    private enum CodingKeys: String, CodingKey {
        case formulaVersion
        case baseQuantityPerRun
        case requiredRuns
        case rawQuantity
        case materialFactorBasisPoints
        case effectiveQuantity
        case savedQuantity
        case context
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try ReactionMaterialCalculation(
            baseQuantityPerRun: container.decode(
                Int64.self,
                forKey: .baseQuantityPerRun
            ),
            requiredRuns: container.decode(
                Int64.self,
                forKey: .requiredRuns
            ),
            context: container.decode(
                ReactionPlanningContext.self,
                forKey: .context
            ),
            modifiers: ReactionResolvedModifiers(
                facilityTimeFactorBasisPoints: 10_000,
                skillTimeFactorBasisPoints: 10_000,
                rigTimeFactorBasisPoints: 10_000,
                rigMaterialFactorBasisPoints: container.decode(
                    Int64.self,
                    forKey: .materialFactorBasisPoints
                ),
                securityBonusMultiplierPermille: 1_000
            ),
            formulaVersion: container.decode(
                Int.self,
                forKey: .formulaVersion
            )
        )
        let rawQuantity = try container.decode(
            Int64.self,
            forKey: .rawQuantity
        )
        let effectiveQuantity = try container.decode(
            Int64.self,
            forKey: .effectiveQuantity
        )
        let savedQuantity = try container.decode(
            Int64.self,
            forKey: .savedQuantity
        )
        guard decoded.rawQuantity == rawQuantity,
              decoded.effectiveQuantity == effectiveQuantity,
              decoded.savedQuantity == savedQuantity else {
            throw ReactionCalculationError.inconsistentPersistedValues
        }
        self = decoded
    }
}

public struct ReactionTimeCalculation:
    Equatable,
    Codable,
    Sendable
{
    public let formulaVersion: Int
    public let baseTimeSeconds: Int64
    public let requiredRuns: Int64
    public let baseDurationSeconds: Int64
    public let skillFactorBasisPoints: Int64
    public let facilityFactorBasisPoints: Int64
    public let rigFactorBasisPoints: Int64
    public let effectiveDurationSeconds: Int64
    public let context: ReactionPlanningContext

    public init(
        baseTimeSeconds: Int64,
        requiredRuns: Int64,
        context: ReactionPlanningContext,
        modifiers: ReactionResolvedModifiers,
        formulaVersion: Int = ReactionRuleProfile.timeFormulaVersion
    ) throws {
        guard formulaVersion == ReactionRuleProfile.timeFormulaVersion else {
            throw ReactionCalculationError
                .unsupportedTimeFormulaVersion(formulaVersion)
        }
        guard baseTimeSeconds >= 0 else {
            throw ReactionCalculationError.invalidBaseTime(baseTimeSeconds)
        }
        guard requiredRuns > 0 else {
            throw ReactionCalculationError.invalidRuns(requiredRuns)
        }
        let base = baseTimeSeconds.multipliedReportingOverflow(
            by: requiredRuns
        )
        guard !base.overflow else {
            throw ReactionCalculationError.arithmeticOverflow
        }
        var effective = base.partialValue
        effective = try ReactionMaterialCalculation.ceilingMultiply(
            effective,
            byBasisPoints: modifiers.skillTimeFactorBasisPoints
        )
        effective = try ReactionMaterialCalculation.ceilingMultiply(
            effective,
            byBasisPoints: modifiers.facilityTimeFactorBasisPoints
        )
        effective = try ReactionMaterialCalculation.ceilingMultiply(
            effective,
            byBasisPoints: modifiers.rigTimeFactorBasisPoints
        )
        self.formulaVersion = formulaVersion
        self.baseTimeSeconds = baseTimeSeconds
        self.requiredRuns = requiredRuns
        self.baseDurationSeconds = base.partialValue
        self.skillFactorBasisPoints =
            modifiers.skillTimeFactorBasisPoints
        self.facilityFactorBasisPoints =
            modifiers.facilityTimeFactorBasisPoints
        self.rigFactorBasisPoints = modifiers.rigTimeFactorBasisPoints
        self.effectiveDurationSeconds = effective
        self.context = context
    }

    public func validatedCopy() throws -> ReactionTimeCalculation {
        let modifiers = ReactionResolvedModifiers(
            facilityTimeFactorBasisPoints:
                facilityFactorBasisPoints,
            skillTimeFactorBasisPoints: skillFactorBasisPoints,
            rigTimeFactorBasisPoints: rigFactorBasisPoints,
            rigMaterialFactorBasisPoints: 10_000,
            securityBonusMultiplierPermille: 1_000
        )
        let canonical = try ReactionTimeCalculation(
            baseTimeSeconds: baseTimeSeconds,
            requiredRuns: requiredRuns,
            context: context,
            modifiers: modifiers,
            formulaVersion: formulaVersion
        )
        guard canonical.baseDurationSeconds == baseDurationSeconds,
              canonical.effectiveDurationSeconds
                == effectiveDurationSeconds else {
            throw ReactionCalculationError.inconsistentPersistedValues
        }
        return canonical
    }

    private enum CodingKeys: String, CodingKey {
        case formulaVersion
        case baseTimeSeconds
        case requiredRuns
        case baseDurationSeconds
        case skillFactorBasisPoints
        case facilityFactorBasisPoints
        case rigFactorBasisPoints
        case effectiveDurationSeconds
        case context
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try ReactionTimeCalculation(
            baseTimeSeconds: container.decode(
                Int64.self,
                forKey: .baseTimeSeconds
            ),
            requiredRuns: container.decode(
                Int64.self,
                forKey: .requiredRuns
            ),
            context: container.decode(
                ReactionPlanningContext.self,
                forKey: .context
            ),
            modifiers: ReactionResolvedModifiers(
                facilityTimeFactorBasisPoints: container.decode(
                    Int64.self,
                    forKey: .facilityFactorBasisPoints
                ),
                skillTimeFactorBasisPoints: container.decode(
                    Int64.self,
                    forKey: .skillFactorBasisPoints
                ),
                rigTimeFactorBasisPoints: container.decode(
                    Int64.self,
                    forKey: .rigFactorBasisPoints
                ),
                rigMaterialFactorBasisPoints: 10_000,
                securityBonusMultiplierPermille: 1_000
            ),
            formulaVersion: container.decode(
                Int.self,
                forKey: .formulaVersion
            )
        )
        let baseDuration = try container.decode(
            Int64.self,
            forKey: .baseDurationSeconds
        )
        let effectiveDuration = try container.decode(
            Int64.self,
            forKey: .effectiveDurationSeconds
        )
        guard decoded.baseDurationSeconds == baseDuration,
              decoded.effectiveDurationSeconds == effectiveDuration else {
            throw ReactionCalculationError.inconsistentPersistedValues
        }
        self = decoded
    }
}
