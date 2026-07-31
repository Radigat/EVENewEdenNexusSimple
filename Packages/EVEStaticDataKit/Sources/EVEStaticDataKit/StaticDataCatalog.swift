import Foundation

public enum StaticIndustryActivity: String, CaseIterable, Codable, Sendable {
    case copying
    case invention
    case manufacturing
    case reaction
    case researchMaterial = "research_material"
    case researchTime = "research_time"
}

public enum StaticDataConsumptionType: String, Codable, Sendable {
    case consumed
}

public struct StaticItemCategorySnapshot: Equatable, Sendable {
    public let externalID: Int64
    public let name: String
    public let published: Bool

    public init(externalID: Int64, name: String, published: Bool) {
        self.externalID = externalID
        self.name = name
        self.published = published
    }
}

public struct StaticItemGroupSnapshot: Equatable, Sendable {
    public let externalID: Int64
    public let categoryExternalID: Int64
    public let name: String
    public let published: Bool

    public init(
        externalID: Int64,
        categoryExternalID: Int64,
        name: String,
        published: Bool
    ) {
        self.externalID = externalID
        self.categoryExternalID = categoryExternalID
        self.name = name
        self.published = published
    }
}

public struct StaticItemTypeSnapshot: Equatable, Sendable {
    public let externalID: Int64
    public let groupExternalID: Int64
    public let categoryExternalID: Int64
    public let marketGroupExternalID: Int64?
    public let name: String
    public let description: String?
    public let volume: Double?
    public let packagedVolume: Double?
    public let basePrice: Double?
    public let portionSize: Int64
    public let published: Bool
    public let iconExternalID: Int64?

    public init(
        externalID: Int64,
        groupExternalID: Int64,
        categoryExternalID: Int64,
        marketGroupExternalID: Int64?,
        name: String,
        description: String?,
        volume: Double?,
        packagedVolume: Double?,
        basePrice: Double?,
        portionSize: Int64,
        published: Bool,
        iconExternalID: Int64?
    ) {
        self.externalID = externalID
        self.groupExternalID = groupExternalID
        self.categoryExternalID = categoryExternalID
        self.marketGroupExternalID = marketGroupExternalID
        self.name = name
        self.description = description
        self.volume = volume
        self.packagedVolume = packagedVolume
        self.basePrice = basePrice
        self.portionSize = portionSize
        self.published = published
        self.iconExternalID = iconExternalID
    }
}

public struct StaticBlueprintMaterialSnapshot: Equatable, Sendable {
    public let itemTypeID: Int64
    public let typeIsResolved: Bool
    public let quantity: Int64
    public let consumptionType: StaticDataConsumptionType
    public let sortOrder: Int

    public init(
        itemTypeID: Int64,
        typeIsResolved: Bool = true,
        quantity: Int64,
        consumptionType: StaticDataConsumptionType = .consumed,
        sortOrder: Int
    ) {
        self.itemTypeID = itemTypeID
        self.typeIsResolved = typeIsResolved
        self.quantity = quantity
        self.consumptionType = consumptionType
        self.sortOrder = sortOrder
    }
}

public struct StaticBlueprintProductSnapshot: Equatable, Sendable {
    public let itemTypeID: Int64
    public let typeIsResolved: Bool
    public let quantity: Int64
    public let probability: Double?
    public let sortOrder: Int

    public init(
        itemTypeID: Int64,
        typeIsResolved: Bool = true,
        quantity: Int64,
        probability: Double?,
        sortOrder: Int
    ) {
        self.itemTypeID = itemTypeID
        self.typeIsResolved = typeIsResolved
        self.quantity = quantity
        self.probability = probability
        self.sortOrder = sortOrder
    }
}

public struct StaticBlueprintActivitySnapshot: Equatable, Sendable {
    public let activity: StaticIndustryActivity
    public let timeSeconds: Int64
    public let materials: [StaticBlueprintMaterialSnapshot]
    public let products: [StaticBlueprintProductSnapshot]

    public init(
        activity: StaticIndustryActivity,
        timeSeconds: Int64,
        materials: [StaticBlueprintMaterialSnapshot],
        products: [StaticBlueprintProductSnapshot]
    ) {
        self.activity = activity
        self.timeSeconds = timeSeconds
        self.materials = materials
        self.products = products
    }
}

public struct StaticBlueprintSnapshot: Equatable, Sendable {
    public let blueprintTypeID: Int64
    public let maxProductionLimit: Int64?
    public let activities: [StaticBlueprintActivitySnapshot]

    public init(
        blueprintTypeID: Int64,
        maxProductionLimit: Int64?,
        activities: [StaticBlueprintActivitySnapshot]
    ) {
        self.blueprintTypeID = blueprintTypeID
        self.maxProductionLimit = maxProductionLimit
        self.activities = activities
    }
}

public struct StaticDataCatalogCounts: Codable, Equatable, Sendable {
    public let categories: Int
    public let groups: Int
    public let itemTypes: Int
    public let blueprints: Int
    public let activities: Int
    public let materials: Int
    public let products: Int
    public let unresolvedTypeReferences: Int

    public init(
        categories: Int,
        groups: Int,
        itemTypes: Int,
        blueprints: Int,
        activities: Int,
        materials: Int,
        products: Int,
        unresolvedTypeReferences: Int = 0
    ) {
        self.categories = categories
        self.groups = groups
        self.itemTypes = itemTypes
        self.blueprints = blueprints
        self.activities = activities
        self.materials = materials
        self.products = products
        self.unresolvedTypeReferences = unresolvedTypeReferences
    }
}

public enum StaticDataCatalogValidationError: Error, Equatable, Sendable {
    case invalidBuildNumber
    case invalidContentHash
    case emptyDataset(SDEDatasetKind)
    case duplicateCategoryID(Int64)
    case duplicateGroupID(Int64)
    case duplicateItemTypeID(Int64)
    case duplicateBlueprintID(Int64)
    case missingCategory(groupID: Int64, categoryID: Int64)
    case missingGroup(typeID: Int64, groupID: Int64)
    case categoryMismatch(typeID: Int64)
    case missingBlueprintType(Int64)
    case duplicateActivity(blueprintID: Int64, activity: StaticIndustryActivity)
    case invalidActivityTime(blueprintID: Int64, activity: StaticIndustryActivity)
    case duplicateMaterial(
        blueprintID: Int64,
        activity: StaticIndustryActivity,
        typeID: Int64
    )
    case duplicateProduct(
        blueprintID: Int64,
        activity: StaticIndustryActivity,
        typeID: Int64
    )
    case referenceResolutionMismatch(Int64)
    case invalidQuantity(Int64)
    case invalidProbability(Double)
}

public enum StaticDataMappingError: Error, Equatable, Sendable {
    case packageMissing
    case unsafeSymbolicLink(SDEDatasetKind?)
    case manifestMissing
    case invalidManifest
    case unsupportedPackageFormat
    case missingDataset(SDEDatasetKind)
    case invalidLine(dataset: SDEDatasetKind, line: Int)
    case invalidField(
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    )
    case unsupportedActivity(line: Int, value: String)
    case datasetChanged(SDEDatasetKind)
    case snapshotChanged
    case fileOperationFailed
}

public struct StaticDataCatalogSnapshot: Equatable, Sendable {
    public let buildNumber: Int
    public let contentSHA256: String
    public let officialArchiveURL: String
    public let sourceFormat: SDEImportSourceFormat
    public let categories: [StaticItemCategorySnapshot]
    public let groups: [StaticItemGroupSnapshot]
    public let itemTypes: [StaticItemTypeSnapshot]
    public let blueprints: [StaticBlueprintSnapshot]
    public let reactionRuleProfile: ReactionRuleProfile?

    public init(
        buildNumber: Int,
        contentSHA256: String,
        officialArchiveURL: String,
        sourceFormat: SDEImportSourceFormat,
        categories: [StaticItemCategorySnapshot],
        groups: [StaticItemGroupSnapshot],
        itemTypes: [StaticItemTypeSnapshot],
        blueprints: [StaticBlueprintSnapshot],
        reactionRuleProfile: ReactionRuleProfile? = nil
    ) throws {
        self.buildNumber = buildNumber
        self.contentSHA256 = contentSHA256
        self.officialArchiveURL = officialArchiveURL
        self.sourceFormat = sourceFormat
        self.categories = categories
        self.groups = groups
        self.itemTypes = itemTypes
        self.blueprints = blueprints
        self.reactionRuleProfile = reactionRuleProfile
        try validate()
    }

    public var counts: StaticDataCatalogCounts {
        StaticDataCatalogCounts(
            categories: categories.count,
            groups: groups.count,
            itemTypes: itemTypes.count,
            blueprints: blueprints.count,
            activities: blueprints.reduce(0) { $0 + $1.activities.count },
            materials: blueprints.reduce(0) { partial, blueprint in
                partial + blueprint.activities.reduce(0) {
                    $0 + $1.materials.count
                }
            },
            products: blueprints.reduce(0) { partial, blueprint in
                partial + blueprint.activities.reduce(0) {
                    $0 + $1.products.count
                }
            },
            unresolvedTypeReferences: blueprints.reduce(0) {
                blueprintTotal,
                blueprint in
                blueprintTotal + blueprint.activities.reduce(0) {
                    activityTotal,
                    activity in
                    activityTotal
                        + activity.materials.filter {
                            !$0.typeIsResolved
                        }.count
                        + activity.products.filter {
                            !$0.typeIsResolved
                        }.count
                }
            }
        )
    }

    private func validate() throws {
        guard buildNumber > 0 else {
            throw StaticDataCatalogValidationError.invalidBuildNumber
        }
        guard contentSHA256.count == 64,
              contentSHA256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw StaticDataCatalogValidationError.invalidContentHash
        }
        guard !categories.isEmpty else {
            throw StaticDataCatalogValidationError.emptyDataset(.categories)
        }
        guard !groups.isEmpty else {
            throw StaticDataCatalogValidationError.emptyDataset(.groups)
        }
        guard !itemTypes.isEmpty else {
            throw StaticDataCatalogValidationError.emptyDataset(.types)
        }
        guard !blueprints.isEmpty else {
            throw StaticDataCatalogValidationError.emptyDataset(.blueprints)
        }

        var categoriesByID: [Int64: StaticItemCategorySnapshot] = [:]
        for category in categories {
            guard categoriesByID.updateValue(category, forKey: category.externalID) == nil else {
                throw StaticDataCatalogValidationError
                    .duplicateCategoryID(category.externalID)
            }
        }

        var groupsByID: [Int64: StaticItemGroupSnapshot] = [:]
        for group in groups {
            guard categoriesByID[group.categoryExternalID] != nil else {
                throw StaticDataCatalogValidationError.missingCategory(
                    groupID: group.externalID,
                    categoryID: group.categoryExternalID
                )
            }
            guard groupsByID.updateValue(group, forKey: group.externalID) == nil else {
                throw StaticDataCatalogValidationError
                    .duplicateGroupID(group.externalID)
            }
        }

        var typesByID: [Int64: StaticItemTypeSnapshot] = [:]
        for itemType in itemTypes {
            guard let group = groupsByID[itemType.groupExternalID] else {
                throw StaticDataCatalogValidationError.missingGroup(
                    typeID: itemType.externalID,
                    groupID: itemType.groupExternalID
                )
            }
            guard group.categoryExternalID == itemType.categoryExternalID else {
                throw StaticDataCatalogValidationError
                    .categoryMismatch(typeID: itemType.externalID)
            }
            guard typesByID.updateValue(itemType, forKey: itemType.externalID) == nil else {
                throw StaticDataCatalogValidationError
                    .duplicateItemTypeID(itemType.externalID)
            }
        }

        var blueprintIDs = Set<Int64>()
        for blueprint in blueprints {
            guard blueprintIDs.insert(blueprint.blueprintTypeID).inserted else {
                throw StaticDataCatalogValidationError
                    .duplicateBlueprintID(blueprint.blueprintTypeID)
            }
            guard typesByID[blueprint.blueprintTypeID] != nil else {
                throw StaticDataCatalogValidationError
                    .missingBlueprintType(blueprint.blueprintTypeID)
            }
            var activities = Set<StaticIndustryActivity>()
            for activity in blueprint.activities {
                guard activities.insert(activity.activity).inserted else {
                    throw StaticDataCatalogValidationError.duplicateActivity(
                        blueprintID: blueprint.blueprintTypeID,
                        activity: activity.activity
                    )
                }
                guard activity.timeSeconds >= 0 else {
                    throw StaticDataCatalogValidationError.invalidActivityTime(
                        blueprintID: blueprint.blueprintTypeID,
                        activity: activity.activity
                    )
                }
                var materialIDs = Set<Int64>()
                for material in activity.materials {
                    guard materialIDs.insert(material.itemTypeID).inserted else {
                        throw StaticDataCatalogValidationError.duplicateMaterial(
                            blueprintID: blueprint.blueprintTypeID,
                            activity: activity.activity,
                            typeID: material.itemTypeID
                        )
                    }
                    try validateReferencedType(
                        material.itemTypeID,
                        isResolved: material.typeIsResolved,
                        quantity: material.quantity,
                        knownTypes: typesByID
                    )
                }
                var productIDs = Set<Int64>()
                for product in activity.products {
                    guard productIDs.insert(product.itemTypeID).inserted else {
                        throw StaticDataCatalogValidationError.duplicateProduct(
                            blueprintID: blueprint.blueprintTypeID,
                            activity: activity.activity,
                            typeID: product.itemTypeID
                        )
                    }
                    try validateReferencedType(
                        product.itemTypeID,
                        isResolved: product.typeIsResolved,
                        quantity: product.quantity,
                        knownTypes: typesByID
                    )
                    if let probability = product.probability,
                       !(probability > 0 && probability <= 1) {
                        throw StaticDataCatalogValidationError
                            .invalidProbability(probability)
                    }
                }
            }
        }
    }

    private func validateReferencedType(
        _ typeID: Int64,
        isResolved: Bool,
        quantity: Int64,
        knownTypes: [Int64: StaticItemTypeSnapshot]
    ) throws {
        guard (knownTypes[typeID] != nil) == isResolved else {
            throw StaticDataCatalogValidationError
                .referenceResolutionMismatch(typeID)
        }
        guard quantity > 0 else {
            throw StaticDataCatalogValidationError.invalidQuantity(quantity)
        }
    }
}

public struct StaticDataActivationResult: Equatable, Sendable {
    public let buildNumber: Int
    public let contentSHA256: String
    public let counts: StaticDataCatalogCounts
    public let reusedExistingVersion: Bool

    public init(
        buildNumber: Int,
        contentSHA256: String,
        counts: StaticDataCatalogCounts,
        reusedExistingVersion: Bool
    ) {
        self.buildNumber = buildNumber
        self.contentSHA256 = contentSHA256
        self.counts = counts
        self.reusedExistingVersion = reusedExistingVersion
    }
}

public protocol StaticDataCatalogMapping: Sendable {
    func mapStagingPackage(at packageURL: URL) async throws
        -> StaticDataCatalogSnapshot
}

public struct StaticDataCatalogPackageMetadata: Equatable, Sendable {
    public let buildNumber: Int
    public let contentSHA256: String
    public let officialArchiveURL: String
    public let sourceFormat: SDEImportSourceFormat

    public init(
        buildNumber: Int,
        contentSHA256: String,
        officialArchiveURL: String,
        sourceFormat: SDEImportSourceFormat
    ) {
        self.buildNumber = buildNumber
        self.contentSHA256 = contentSHA256
        self.officialArchiveURL = officialArchiveURL
        self.sourceFormat = sourceFormat
    }
}

public enum StaticDataCatalogBatch: Equatable, Sendable {
    case categories([StaticItemCategorySnapshot])
    case groups([StaticItemGroupSnapshot])
    case itemTypes([StaticItemTypeSnapshot])
    case blueprints([StaticBlueprintSnapshot])
    case reactionRuleProfile(ReactionRuleProfile)

    public var recordCount: Int {
        switch self {
        case .categories(let records):
            records.count
        case .groups(let records):
            records.count
        case .itemTypes(let records):
            records.count
        case .blueprints(let records):
            records.count
        case .reactionRuleProfile:
            1
        }
    }
}

public struct StaticDataCatalogStreamResult: Equatable, Sendable {
    public let metadata: StaticDataCatalogPackageMetadata
    public let counts: StaticDataCatalogCounts

    public init(
        metadata: StaticDataCatalogPackageMetadata,
        counts: StaticDataCatalogCounts
    ) {
        self.metadata = metadata
        self.counts = counts
    }
}

public typealias StaticDataCatalogBatchConsumer =
    @Sendable (StaticDataCatalogBatch) async throws -> Void

public protocol StaticDataCatalogStreamingMapping: Sendable {
    func packageMetadata(at packageURL: URL) async throws
        -> StaticDataCatalogPackageMetadata

    func streamStagingPackage(
        at packageURL: URL,
        batchSize: Int,
        consume: @escaping StaticDataCatalogBatchConsumer
    ) async throws -> StaticDataCatalogStreamResult
}

public protocol StaticDataCatalogStoring: Sendable {
    func activate(_ snapshot: StaticDataCatalogSnapshot) async throws
        -> StaticDataActivationResult
}

public protocol StaticDataCatalogStreamingStoring: Sendable {
    func activateStreaming(
        packageURL: URL,
        mapper: any StaticDataCatalogStreamingMapping,
        batchSize: Int
    ) async throws -> StaticDataActivationResult

    func discardStreamingImport(contentSHA256: String) async throws
}

public struct ImportStaticDataUseCase: Sendable {
    private let mapper: any StaticDataCatalogMapping
    private let repository: any StaticDataCatalogStoring

    public init(
        mapper: any StaticDataCatalogMapping,
        repository: any StaticDataCatalogStoring
    ) {
        self.mapper = mapper
        self.repository = repository
    }

    public func callAsFunction(
        packageURL: URL
    ) async throws -> StaticDataActivationResult {
        let snapshot = try await mapper.mapStagingPackage(at: packageURL)
        return try await repository.activate(snapshot)
    }
}
