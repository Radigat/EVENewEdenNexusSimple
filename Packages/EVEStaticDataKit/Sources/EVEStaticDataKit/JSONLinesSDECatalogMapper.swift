import CoreFoundation
import CryptoKit
import Foundation

public actor JSONLinesSDECatalogMapper:
    StaticDataCatalogMapping,
    StaticDataCatalogStreamingMapping {
    private static let reactionFacilityTypeIDs: Set<Int64> = [
        35_835, 35_836
    ]
    private static let reactionReactorTypeIDs: Set<Int64> = [
        45_537, 45_538, 45_539
    ]
    private static let reactionRigTypeIDs =
        Set(Int64(46_484)...Int64(46_497))
    private static let reactionsSkillTypeID: Int64 = 45_746
    private static let reactionRelevantTypeIDs =
        reactionFacilityTypeIDs
            .union(reactionReactorTypeIDs)
            .union(reactionRigTypeIDs)
            .union([reactionsSkillTypeID])
    private static let reactionRelevantAttributeIDs: Set<Int64> = [
        2_356, 2_357, 2_660, 2_713, 2_714, 2_721
    ]
    private static let reactionRelevantEffectIDs: Set<Int64> = [
        6_892, 6_969, 6_970, 6_971, 6_973, 6_974, 6_975, 6_976
    ]
    private let fileManager: FileManager
    private let readChunkSize: Int
    private let maximumLineBytes: Int

    public init(
        fileManager: FileManager = .default,
        readChunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.readChunkSize = max(1_024, readChunkSize)
        self.maximumLineBytes = max(1_024, maximumLineBytes)
    }

    public func mapStagingPackage(
        at packageURL: URL
    ) async throws -> StaticDataCatalogSnapshot {
        let collector = StaticDataCatalogSnapshotCollector()
        let result = try await streamStagingPackage(
            at: packageURL,
            batchSize: 500
        ) { batch in
            await collector.append(batch)
        }
        let values = await collector.values()
        return try StaticDataCatalogSnapshot(
            buildNumber: result.metadata.buildNumber,
            contentSHA256: result.metadata.contentSHA256,
            officialArchiveURL: result.metadata.officialArchiveURL,
            sourceFormat: result.metadata.sourceFormat,
            categories: values.categories,
            groups: values.groups,
            itemTypes: values.itemTypes,
            blueprints: values.blueprints,
            reactionRuleProfile: values.reactionRuleProfile
        )
    }

    public func packageMetadata(
        at packageURL: URL
    ) async throws -> StaticDataCatalogPackageMetadata {
        try Task.checkCancellation()
        try validateDirectory(packageURL)
        let manifest = try readManifest(at: packageURL)
        return try metadata(from: manifest)
    }

    public func streamStagingPackage(
        at packageURL: URL,
        batchSize: Int,
        consume: @escaping StaticDataCatalogBatchConsumer
    ) async throws -> StaticDataCatalogStreamResult {
        try Task.checkCancellation()
        try validateDirectory(packageURL)
        let manifest = try readManifest(at: packageURL)
        let metadata = try metadata(from: manifest)
        let expectedDescriptors = try descriptorMap(
            manifest.snapshot.datasets
        )
        let batchLimit = max(1, batchSize)

        var categoryIDs = Set<Int64>()
        var categoryBatch: [StaticItemCategorySnapshot] = []
        let categoryDescriptor = try await readDataset(
            .categories,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            let category = try self.mapCategory(object, line: line)
            categoryIDs.insert(category.externalID)
            categoryBatch.append(category)
            if categoryBatch.count >= batchLimit {
                let batch = categoryBatch
                categoryBatch.removeAll(keepingCapacity: true)
                return .categories(batch)
            }
            return nil
        }
        if !categoryBatch.isEmpty {
            try await consume(.categories(categoryBatch))
        }
        try compare(
            categoryDescriptor,
            with: expectedDescriptors[.categories],
            kind: .categories
        )

        var groupsByID: [Int64: StaticItemGroupSnapshot] = [:]
        var groupBatch: [StaticItemGroupSnapshot] = []
        let groupDescriptor = try await readDataset(
            .groups,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            let group = try self.mapGroup(object, line: line)
            guard categoryIDs.contains(group.categoryExternalID) else {
                throw StaticDataCatalogValidationError.missingCategory(
                    groupID: group.externalID,
                    categoryID: group.categoryExternalID
                )
            }
            groupsByID[group.externalID] = group
            groupBatch.append(group)
            if groupBatch.count >= batchLimit {
                let batch = groupBatch
                groupBatch.removeAll(keepingCapacity: true)
                return .groups(batch)
            }
            return nil
        }
        if !groupBatch.isEmpty {
            try await consume(.groups(groupBatch))
        }
        try compare(
            groupDescriptor,
            with: expectedDescriptors[.groups],
            kind: .groups
        )

        var knownTypeIDs = Set<Int64>()
        var reactionTypeGroupIDs: [Int64: Int64] = [:]
        var itemTypeBatch: [StaticItemTypeSnapshot] = []
        let typeDescriptor = try await readDataset(
            .types,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            let itemType = try self.mapItemType(
                object,
                line: line,
                groupsByID: groupsByID
            )
            knownTypeIDs.insert(itemType.externalID)
            if Self.reactionRelevantTypeIDs.contains(
                itemType.externalID
            ) {
                reactionTypeGroupIDs[itemType.externalID] =
                    itemType.groupExternalID
            }
            itemTypeBatch.append(itemType)
            if itemTypeBatch.count >= batchLimit {
                let batch = itemTypeBatch
                itemTypeBatch.removeAll(keepingCapacity: true)
                return .itemTypes(batch)
            }
            return nil
        }
        if !itemTypeBatch.isEmpty {
            try await consume(.itemTypes(itemTypeBatch))
        }
        try compare(
            typeDescriptor,
            with: expectedDescriptors[.types],
            kind: .types
        )

        var blueprintBatch: [StaticBlueprintSnapshot] = []
        var activityCount = 0
        var materialCount = 0
        var productCount = 0
        var unresolvedTypeReferenceCount = 0
        let blueprintDescriptor = try await readDataset(
            .blueprints,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            let blueprint = try self.mapBlueprint(
                object,
                line: line,
                knownTypeIDs: knownTypeIDs
            )
            try self.validateBlueprint(
                blueprint,
                knownTypeIDs: knownTypeIDs
            )
            activityCount += blueprint.activities.count
            for activity in blueprint.activities {
                materialCount += activity.materials.count
                productCount += activity.products.count
                unresolvedTypeReferenceCount +=
                    activity.materials.filter {
                        !$0.typeIsResolved
                    }.count
                unresolvedTypeReferenceCount +=
                    activity.products.filter {
                        !$0.typeIsResolved
                    }.count
            }
            blueprintBatch.append(blueprint)
            if blueprintBatch.count >= batchLimit {
                let batch = blueprintBatch
                blueprintBatch.removeAll(keepingCapacity: true)
                return .blueprints(batch)
            }
            return nil
        }
        if !blueprintBatch.isEmpty {
            try await consume(.blueprints(blueprintBatch))
        }
        try compare(
            blueprintDescriptor,
            with: expectedDescriptors[.blueprints],
            kind: .blueprints
        )

        var typeDogmaValues: [Int64: [Int64: Double]] = [:]
        var typeDogmaEffects: [Int64: Set<Int64>] = [:]
        let typeDogmaDescriptor = try await readDataset(
            .typeDogma,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            guard let typeID = try self.optionalRelevantKey(
                object,
                dataset: .typeDogma,
                line: line,
                relevant: Self.reactionRelevantTypeIDs
            ) else {
                return nil
            }
            typeDogmaValues[typeID] = try self.mapDogmaAttributeValues(
                object["dogmaAttributes"],
                dataset: .typeDogma,
                line: line
            )
            typeDogmaEffects[typeID] = try self.mapDogmaEffectIDs(
                object["dogmaEffects"],
                dataset: .typeDogma,
                line: line
            )
            return nil
        }
        try compare(
            typeDogmaDescriptor,
            with: expectedDescriptors[.typeDogma],
            kind: .typeDogma
        )

        var dogmaAttributeNames: [Int64: String] = [:]
        let dogmaAttributeDescriptor = try await readDataset(
            .dogmaAttributes,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            guard let attributeID = try self.optionalRelevantKey(
                object,
                dataset: .dogmaAttributes,
                line: line,
                relevant: Self.reactionRelevantAttributeIDs
            ) else {
                return nil
            }
            dogmaAttributeNames[attributeID] =
                try self.requiredString(
                    object["name"],
                    dataset: .dogmaAttributes,
                    line: line,
                    field: "name"
                )
            return nil
        }
        try compare(
            dogmaAttributeDescriptor,
            with: expectedDescriptors[.dogmaAttributes],
            kind: .dogmaAttributes
        )

        var dogmaEffectNames: [Int64: String] = [:]
        let dogmaEffectDescriptor = try await readDataset(
            .dogmaEffects,
            packageURL: packageURL,
            consume: consume
        ) { object, line in
            guard let effectID = try self.optionalRelevantKey(
                object,
                dataset: .dogmaEffects,
                line: line,
                relevant: Self.reactionRelevantEffectIDs
            ) else {
                return nil
            }
            dogmaEffectNames[effectID] = try self.requiredString(
                object["name"],
                dataset: .dogmaEffects,
                line: line,
                field: "name"
            )
            return nil
        }
        try compare(
            dogmaEffectDescriptor,
            with: expectedDescriptors[.dogmaEffects],
            kind: .dogmaEffects
        )

        let reactionProfile = try makeReactionRuleProfile(
            metadata: metadata,
            groupsByID: groupsByID,
            typeGroupIDs: reactionTypeGroupIDs,
            typeDogmaValues: typeDogmaValues,
            typeDogmaEffects: typeDogmaEffects,
            dogmaAttributeNames: dogmaAttributeNames,
            dogmaEffectNames: dogmaEffectNames
        )
        try await consume(.reactionRuleProfile(reactionProfile))

        let actualDescriptors = [
            categoryDescriptor,
            groupDescriptor,
            typeDescriptor,
            blueprintDescriptor,
            typeDogmaDescriptor,
            dogmaAttributeDescriptor,
            dogmaEffectDescriptor
        ]
        let actualContentHash = SDEContentHash.make(
            buildNumber: metadata.buildNumber,
            descriptors: actualDescriptors
        )
        guard actualContentHash == metadata.contentSHA256 else {
            throw StaticDataMappingError.snapshotChanged
        }

        return StaticDataCatalogStreamResult(
            metadata: metadata,
            counts: StaticDataCatalogCounts(
                categories: categoryDescriptor.recordCount,
                groups: groupDescriptor.recordCount,
                itemTypes: typeDescriptor.recordCount,
                blueprints: blueprintDescriptor.recordCount,
                activities: activityCount,
                materials: materialCount,
                products: productCount,
                unresolvedTypeReferences:
                    unresolvedTypeReferenceCount
            )
        )
    }

    private func metadata(
        from manifest: SDEStagingManifest
    ) throws -> StaticDataCatalogPackageMetadata {
        let snapshot = manifest.snapshot
        guard snapshot.buildNumber > 0,
              snapshot.contentSHA256.count == 64,
              snapshot.contentSHA256.allSatisfy({
                  $0.isHexDigit && !$0.isUppercase
              }),
              !snapshot.officialArchiveURL.isEmpty else {
            throw StaticDataMappingError.invalidManifest
        }
        return StaticDataCatalogPackageMetadata(
            buildNumber: snapshot.buildNumber,
            contentSHA256: snapshot.contentSHA256,
            officialArchiveURL: snapshot.officialArchiveURL,
            sourceFormat: snapshot.sourceFormat
        )
    }

    private func validateBlueprint(
        _ blueprint: StaticBlueprintSnapshot,
        knownTypeIDs: Set<Int64>
    ) throws {
        guard knownTypeIDs.contains(blueprint.blueprintTypeID) else {
            throw StaticDataCatalogValidationError.missingBlueprintType(
                blueprint.blueprintTypeID
            )
        }
        var activities = Set<StaticIndustryActivity>()
        for activity in blueprint.activities {
            guard activities.insert(activity.activity).inserted else {
                throw StaticDataCatalogValidationError.duplicateActivity(
                    blueprintID: blueprint.blueprintTypeID,
                    activity: activity.activity
                )
            }
            var materials = Set<Int64>()
            for material in activity.materials {
                guard materials.insert(material.itemTypeID).inserted else {
                    throw StaticDataCatalogValidationError.duplicateMaterial(
                        blueprintID: blueprint.blueprintTypeID,
                        activity: activity.activity,
                        typeID: material.itemTypeID
                    )
                }
            }
            var products = Set<Int64>()
            for product in activity.products {
                guard products.insert(product.itemTypeID).inserted else {
                    throw StaticDataCatalogValidationError.duplicateProduct(
                        blueprintID: blueprint.blueprintTypeID,
                        activity: activity.activity,
                        typeID: product.itemTypeID
                    )
                }
            }
        }
    }

    private func mapCategory(
        _ object: [String: Any],
        line: Int
    ) throws -> StaticItemCategorySnapshot {
        StaticItemCategorySnapshot(
            externalID: try requiredNonnegativeInteger(
                object["_key"],
                dataset: .categories,
                line: line,
                field: "_key"
            ),
            name: try requiredEnglishText(
                object["name"],
                dataset: .categories,
                line: line,
                field: "name.en"
            ),
            published: try requiredBoolean(
                object["published"],
                dataset: .categories,
                line: line,
                field: "published"
            )
        )
    }

    private func mapGroup(
        _ object: [String: Any],
        line: Int
    ) throws -> StaticItemGroupSnapshot {
        StaticItemGroupSnapshot(
            externalID: try requiredNonnegativeInteger(
                object["_key"],
                dataset: .groups,
                line: line,
                field: "_key"
            ),
            categoryExternalID: try requiredNonnegativeInteger(
                object["categoryID"],
                dataset: .groups,
                line: line,
                field: "categoryID"
            ),
            name: try requiredEnglishText(
                object["name"],
                dataset: .groups,
                line: line,
                field: "name.en"
            ),
            published: try requiredBoolean(
                object["published"],
                dataset: .groups,
                line: line,
                field: "published"
            )
        )
    }

    private func mapItemType(
        _ object: [String: Any],
        line: Int,
        groupsByID: [Int64: StaticItemGroupSnapshot]
    ) throws -> StaticItemTypeSnapshot {
        let typeID = try requiredNonnegativeInteger(
            object["_key"],
            dataset: .types,
            line: line,
            field: "_key"
        )
        let groupID = try requiredNonnegativeInteger(
            object["groupID"],
            dataset: .types,
            line: line,
            field: "groupID"
        )
        guard let group = groupsByID[groupID] else {
            throw StaticDataCatalogValidationError.missingGroup(
                typeID: typeID,
                groupID: groupID
            )
        }
        return StaticItemTypeSnapshot(
            externalID: typeID,
            groupExternalID: groupID,
            categoryExternalID: group.categoryExternalID,
            marketGroupExternalID: try optionalNonnegativeInteger(
                object["marketGroupID"],
                dataset: .types,
                line: line,
                field: "marketGroupID"
            ),
            name: try requiredEnglishText(
                object["name"],
                dataset: .types,
                line: line,
                field: "name.en"
            ),
            description: try optionalEnglishText(
                object["description"],
                dataset: .types,
                line: line,
                field: "description.en"
            ),
            volume: try optionalNonnegativeDouble(
                object["volume"],
                dataset: .types,
                line: line,
                field: "volume"
            ),
            packagedVolume: try optionalNonnegativeDouble(
                object["packagedVolume"],
                dataset: .types,
                line: line,
                field: "packagedVolume"
            ),
            basePrice: try optionalNonnegativeDouble(
                object["basePrice"],
                dataset: .types,
                line: line,
                field: "basePrice"
            ),
            portionSize: try requiredPositiveInteger(
                object["portionSize"],
                dataset: .types,
                line: line,
                field: "portionSize"
            ),
            published: try requiredBoolean(
                object["published"],
                dataset: .types,
                line: line,
                field: "published"
            ),
            iconExternalID: try optionalNonnegativeInteger(
                object["iconID"],
                dataset: .types,
                line: line,
                field: "iconID"
            )
        )
    }

    private func mapBlueprint(
        _ object: [String: Any],
        line: Int,
        knownTypeIDs: Set<Int64>
    ) throws -> StaticBlueprintSnapshot {
        let recordID = try requiredNonnegativeInteger(
            object["_key"],
            dataset: .blueprints,
            line: line,
            field: "_key"
        )
        let blueprintTypeID = try requiredNonnegativeInteger(
            object["blueprintTypeID"],
            dataset: .blueprints,
            line: line,
            field: "blueprintTypeID"
        )
        guard recordID == blueprintTypeID else {
            throw StaticDataMappingError.invalidField(
                dataset: .blueprints,
                line: line,
                field: "blueprintTypeID"
            )
        }
        guard let rawActivities = object["activities"] as? [String: Any],
              !rawActivities.isEmpty else {
            throw StaticDataMappingError.invalidField(
                dataset: .blueprints,
                line: line,
                field: "activities"
            )
        }

        var activities: [StaticBlueprintActivitySnapshot] = []
        for key in rawActivities.keys.sorted() {
            guard let activity = StaticIndustryActivity(rawValue: key) else {
                throw StaticDataMappingError.unsupportedActivity(
                    line: line,
                    value: key
                )
            }
            guard let rawActivity = rawActivities[key] as? [String: Any] else {
                throw StaticDataMappingError.invalidField(
                    dataset: .blueprints,
                    line: line,
                    field: "activities.\(key)"
                )
            }
            let materials = try mapMaterials(
                rawActivity["materials"],
                line: line,
                activity: activity,
                knownTypeIDs: knownTypeIDs
            )
            let products = try mapProducts(
                rawActivity["products"],
                line: line,
                activity: activity,
                knownTypeIDs: knownTypeIDs
            )
            activities.append(
                StaticBlueprintActivitySnapshot(
                    activity: activity,
                    timeSeconds: try requiredNonnegativeInteger(
                        rawActivity["time"],
                        dataset: .blueprints,
                        line: line,
                        field: "activities.\(key).time"
                    ),
                    materials: materials,
                    products: products
                )
            )
        }

        return StaticBlueprintSnapshot(
            blueprintTypeID: blueprintTypeID,
            maxProductionLimit: try optionalPositiveInteger(
                object["maxProductionLimit"],
                dataset: .blueprints,
                line: line,
                field: "maxProductionLimit"
            ),
            activities: activities
        )
    }

    private func mapMaterials(
        _ value: Any?,
        line: Int,
        activity: StaticIndustryActivity,
        knownTypeIDs: Set<Int64>
    ) throws -> [StaticBlueprintMaterialSnapshot] {
        guard let value else {
            return []
        }
        guard let array = value as? [Any] else {
            throw StaticDataMappingError.invalidField(
                dataset: .blueprints,
                line: line,
                field: "activities.\(activity.rawValue).materials"
            )
        }
        return try array.enumerated().map { index, rawMaterial in
            guard let material = rawMaterial as? [String: Any] else {
                throw StaticDataMappingError.invalidField(
                    dataset: .blueprints,
                    line: line,
                    field: "activities.\(activity.rawValue).materials"
                )
            }
            let typeID = try requiredNonnegativeInteger(
                    material["typeID"],
                    dataset: .blueprints,
                    line: line,
                    field: "materials.typeID"
                )
            return StaticBlueprintMaterialSnapshot(
                itemTypeID: typeID,
                typeIsResolved: knownTypeIDs.contains(typeID),
                quantity: try requiredPositiveInteger(
                    material["quantity"],
                    dataset: .blueprints,
                    line: line,
                    field: "materials.quantity"
                ),
                sortOrder: index
            )
        }
    }

    private func mapProducts(
        _ value: Any?,
        line: Int,
        activity: StaticIndustryActivity,
        knownTypeIDs: Set<Int64>
    ) throws -> [StaticBlueprintProductSnapshot] {
        guard let value else {
            return []
        }
        guard let array = value as? [Any] else {
            throw StaticDataMappingError.invalidField(
                dataset: .blueprints,
                line: line,
                field: "activities.\(activity.rawValue).products"
            )
        }
        return try array.enumerated().map { index, rawProduct in
            guard let product = rawProduct as? [String: Any] else {
                throw StaticDataMappingError.invalidField(
                    dataset: .blueprints,
                    line: line,
                    field: "activities.\(activity.rawValue).products"
                )
            }
            let typeID = try requiredNonnegativeInteger(
                    product["typeID"],
                    dataset: .blueprints,
                    line: line,
                    field: "products.typeID"
                )
            return StaticBlueprintProductSnapshot(
                itemTypeID: typeID,
                typeIsResolved: knownTypeIDs.contains(typeID),
                quantity: try requiredPositiveInteger(
                    product["quantity"],
                    dataset: .blueprints,
                    line: line,
                    field: "products.quantity"
                ),
                probability: try optionalProbability(
                    product["probability"],
                    line: line
                ),
                sortOrder: index
            )
        }
    }

    private func readDataset(
        _ kind: SDEDatasetKind,
        packageURL: URL,
        consume: @escaping StaticDataCatalogBatchConsumer,
        record: ([String: Any], Int) throws -> StaticDataCatalogBatch?
    ) async throws -> SDEDatasetDescriptor {
        let url = packageURL.appendingPathComponent(kind.fileName)
        try validateDatasetFile(url, kind: kind)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw StaticDataMappingError.fileOperationFailed
        }

        var result: Result<SDEDatasetDescriptor, any Error>
        do {
            var hasher = SHA256()
            var byteCount: Int64 = 0
            var recordCount = 0
            var lineNumber = 0
            var buffer = Data()
            var keys = Set<Int64>()

            while let chunk = try handle.read(upToCount: readChunkSize),
                  !chunk.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: chunk)
                byteCount += Int64(chunk.count)
                buffer.append(chunk)
                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let lineData = Data(buffer[..<newlineIndex])
                    buffer.removeSubrange(...newlineIndex)
                    lineNumber += 1
                    let object = try decodeObject(
                        lineData,
                        dataset: kind,
                        line: lineNumber
                    )
                    let key = try requiredNonnegativeInteger(
                        object["_key"],
                        dataset: kind,
                        line: lineNumber,
                        field: "_key"
                    )
                    guard keys.insert(key).inserted else {
                        throw StaticDataMappingError.invalidField(
                            dataset: kind,
                            line: lineNumber,
                            field: "_key"
                        )
                    }
                    if let batch = try record(object, lineNumber) {
                        try await consume(batch)
                    }
                    recordCount += 1
                }
                guard buffer.count <= maximumLineBytes else {
                    throw StaticDataMappingError.invalidLine(
                        dataset: kind,
                        line: lineNumber + 1
                    )
                }
            }
            if !buffer.isEmpty {
                lineNumber += 1
                let object = try decodeObject(
                    buffer,
                    dataset: kind,
                    line: lineNumber
                )
                let key = try requiredNonnegativeInteger(
                    object["_key"],
                    dataset: kind,
                    line: lineNumber,
                    field: "_key"
                )
                guard keys.insert(key).inserted else {
                    throw StaticDataMappingError.invalidField(
                        dataset: kind,
                        line: lineNumber,
                        field: "_key"
                    )
                }
                if let batch = try record(object, lineNumber) {
                    try await consume(batch)
                }
                recordCount += 1
            }
            guard recordCount > 0 else {
                throw StaticDataMappingError.invalidLine(
                    dataset: kind,
                    line: 1
                )
            }
            result = .success(
                SDEDatasetDescriptor(
                    kind: kind,
                    fileName: kind.fileName,
                    recordCount: recordCount,
                    byteCount: byteCount,
                    sha256: hasher.finalize().hexString
                )
            )
        } catch {
            result = .failure(error)
        }
        do {
            try handle.close()
        } catch {
            throw StaticDataMappingError.fileOperationFailed
        }
        return try result.get()
    }

    private func decodeObject(
        _ rawLine: Data,
        dataset: SDEDatasetKind,
        line: Int
    ) throws -> [String: Any] {
        var lineData = rawLine
        if lineData.last == 0x0D {
            lineData.removeLast()
        }
        guard !lineData.isEmpty,
              lineData.count <= maximumLineBytes,
              String(data: lineData, encoding: .utf8) != nil else {
            throw StaticDataMappingError.invalidLine(
                dataset: dataset,
                line: line
            )
        }
        do {
            guard let object = try JSONSerialization.jsonObject(
                with: lineData
            ) as? [String: Any] else {
                throw StaticDataMappingError.invalidLine(
                    dataset: dataset,
                    line: line
                )
            }
            return object
        } catch let error as StaticDataMappingError {
            throw error
        } catch {
            throw StaticDataMappingError.invalidLine(
                dataset: dataset,
                line: line
            )
        }
    }

    private func readManifest(at packageURL: URL) throws -> SDEStagingManifest {
        let url = packageURL.appendingPathComponent(
            JSONLinesSDEImportService.manifestFileName
        )
        guard fileManager.fileExists(atPath: url.path) else {
            throw StaticDataMappingError.manifestMissing
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw StaticDataMappingError.unsafeSymbolicLink(nil)
            }
            guard values.isRegularFile == true else {
                throw StaticDataMappingError.manifestMissing
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(
                SDEStagingManifest.self,
                from: Data(contentsOf: url)
            )
            guard manifest.formatIdentifier
                    == JSONLinesSDEImportService.formatIdentifier,
                  manifest.formatVersion
                    == JSONLinesSDEImportService.formatVersion,
                  manifest.snapshot.sourceFormat == .jsonLines else {
                throw StaticDataMappingError.unsupportedPackageFormat
            }
            return manifest
        } catch let error as StaticDataMappingError {
            throw error
        } catch {
            throw StaticDataMappingError.invalidManifest
        }
    }

    private func descriptorMap(
        _ descriptors: [SDEDatasetDescriptor]
    ) throws -> [SDEDatasetKind: SDEDatasetDescriptor] {
        guard descriptors.count == SDEDatasetKind.allCases.count else {
            throw StaticDataMappingError.invalidManifest
        }
        var result: [SDEDatasetKind: SDEDatasetDescriptor] = [:]
        for descriptor in descriptors {
            guard descriptor.fileName == descriptor.kind.fileName,
                  result.updateValue(
                    descriptor,
                    forKey: descriptor.kind
                  ) == nil else {
                throw StaticDataMappingError.invalidManifest
            }
        }
        guard result.count == SDEDatasetKind.allCases.count else {
            throw StaticDataMappingError.invalidManifest
        }
        return result
    }

    private func compare(
        _ actual: SDEDatasetDescriptor,
        with expected: SDEDatasetDescriptor?,
        kind: SDEDatasetKind
    ) throws {
        guard actual == expected else {
            throw StaticDataMappingError.datasetChanged(kind)
        }
    }

    private func validateDirectory(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StaticDataMappingError.packageMissing
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw StaticDataMappingError.unsafeSymbolicLink(nil)
            }
            guard values.isDirectory == true else {
                throw StaticDataMappingError.packageMissing
            }
        } catch let error as StaticDataMappingError {
            throw error
        } catch {
            throw StaticDataMappingError.fileOperationFailed
        }
    }

    private func validateDatasetFile(
        _ url: URL,
        kind: SDEDatasetKind
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StaticDataMappingError.missingDataset(kind)
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw StaticDataMappingError.unsafeSymbolicLink(kind)
            }
            guard values.isRegularFile == true else {
                throw StaticDataMappingError.missingDataset(kind)
            }
        } catch let error as StaticDataMappingError {
            throw error
        } catch {
            throw StaticDataMappingError.fileOperationFailed
        }
    }

    private func requiredEnglishText(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> String {
        guard let text = try optionalEnglishText(
            value,
            dataset: dataset,
            line: line,
            field: field
        ), !text.isEmpty else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return text
    }

    private func optionalEnglishText(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> String? {
        guard let value else {
            return nil
        }
        guard let localized = value as? [String: Any],
              let text = localized["en"] as? String else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return text.isEmpty ? nil : text
    }

    private func requiredBoolean(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return number.boolValue
    }

    private func requiredNonnegativeInteger(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Int64 {
        guard let result = exactInteger(value), result >= 0 else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return result
    }

    private func requiredPositiveInteger(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Int64 {
        guard let result = exactInteger(value), result > 0 else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return result
    }

    private func optionalNonnegativeInteger(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Int64? {
        guard let value else {
            return nil
        }
        return try requiredNonnegativeInteger(
            value,
            dataset: dataset,
            line: line,
            field: field
        )
    }

    private func optionalPositiveInteger(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Int64? {
        guard let value else {
            return nil
        }
        return try requiredPositiveInteger(
            value,
            dataset: dataset,
            line: line,
            field: field
        )
    }

    private func exactInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              Decimal(number.int64Value) == number.decimalValue else {
            return nil
        }
        return number.int64Value
    }

    private func requiredString(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> String {
        guard let value = value as? String, !value.isEmpty else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return value
    }

    private func optionalRelevantKey(
        _ object: [String: Any],
        dataset: SDEDatasetKind,
        line: Int,
        relevant: Set<Int64>
    ) throws -> Int64? {
        let key = try requiredNonnegativeInteger(
            object["_key"],
            dataset: dataset,
            line: line,
            field: "_key"
        )
        return relevant.contains(key) ? key : nil
    }

    private func mapDogmaAttributeValues(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int
    ) throws -> [Int64: Double] {
        guard let rows = value as? [[String: Any]] else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: "dogmaAttributes"
            )
        }
        var result: [Int64: Double] = [:]
        for row in rows {
            let attributeID = try requiredNonnegativeInteger(
                row["attributeID"],
                dataset: dataset,
                line: line,
                field: "dogmaAttributes.attributeID"
            )
            guard let number = row["value"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  result.updateValue(
                    number.doubleValue,
                    forKey: attributeID
                  ) == nil else {
                throw StaticDataMappingError.invalidField(
                    dataset: dataset,
                    line: line,
                    field: "dogmaAttributes.value"
                )
            }
        }
        return result
    }

    private func mapDogmaEffectIDs(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int
    ) throws -> Set<Int64> {
        guard let rows = value as? [[String: Any]] else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: "dogmaEffects"
            )
        }
        var result = Set<Int64>()
        for row in rows {
            let effectID = try requiredNonnegativeInteger(
                row["effectID"],
                dataset: dataset,
                line: line,
                field: "dogmaEffects.effectID"
            )
            guard result.insert(effectID).inserted else {
                throw StaticDataMappingError.invalidField(
                    dataset: dataset,
                    line: line,
                    field: "dogmaEffects.effectID"
                )
            }
        }
        return result
    }

    private func makeReactionRuleProfile(
        metadata: StaticDataCatalogPackageMetadata,
        groupsByID: [Int64: StaticItemGroupSnapshot],
        typeGroupIDs: [Int64: Int64],
        typeDogmaValues: [Int64: [Int64: Double]],
        typeDogmaEffects: [Int64: Set<Int64>],
        dogmaAttributeNames: [Int64: String],
        dogmaEffectNames: [Int64: String]
    ) throws -> ReactionRuleProfile {
        let expectedGroups: [Int64: String] = [
            1_888: "Composite Reaction Formulas",
            1_889: "Polymer Reaction Formulas",
            1_890: "Biochemical Reaction Formulas",
            4_097: "Molecular-Forged Reaction Formulas"
        ]
        guard expectedGroups.allSatisfy({
            groupsByID[$0.key]?.name == $0.value
        }),
        Self.reactionRelevantTypeIDs.allSatisfy({
            typeGroupIDs[$0] != nil && typeDogmaValues[$0] != nil
        }),
        dogmaAttributeNames[2_356] == "lowSecModifier",
        dogmaAttributeNames[2_357] == "nullSecModifier",
        dogmaAttributeNames[2_660] == "reactionTimeBonus",
        dogmaAttributeNames[2_713] == "RefRigTimeBonus",
        dogmaAttributeNames[2_714] == "RefRigMatBonus",
        dogmaAttributeNames[2_721] == "strReactionTimeMultiplier",
        dogmaEffectNames[6_892]
            == "reactionSkillBoostManufacturingTimeBonus",
        dogmaEffectNames[6_976]
            == "structureReactionRigSecurityModification" else {
            throw StaticDataMappingError.invalidField(
                dataset: .typeDogma,
                line: 0,
                field: "reactionRuleProfile"
            )
        }

        let facilityRules = try [
            ReactionFacilityRule(
                typeID: 35_835,
                timeMultiplierBasisPoints: basisPoints(
                    typeDogmaValues[35_835]?[2_721] ?? 1
                )
            ),
            ReactionFacilityRule(
                typeID: 35_836,
                timeMultiplierBasisPoints: basisPoints(
                    try requiredDogmaValue(
                        typeID: 35_836,
                        attributeID: 2_721,
                        values: typeDogmaValues
                    )
                )
            )
        ]
        let reactorRules = [
            ReactionReactorRule(typeID: 45_537, kind: .composite),
            ReactionReactorRule(typeID: 45_538, kind: .hybrid),
            ReactionReactorRule(typeID: 45_539, kind: .biochemical)
        ]
        var rigRules: [ReactionRigRule] = []
        for typeID in Self.reactionRigTypeIDs.sorted() {
            let kind: [ReactionKind]
            switch typeID {
            case 46_484...46_487:
                kind = [.composite]
            case 46_488...46_491:
                kind = [.hybrid]
            case 46_492...46_495:
                kind = [.biochemical]
            case 46_496...46_497:
                kind = ReactionKind.allCases
            default:
                throw StaticDataMappingError.invalidField(
                    dataset: .typeDogma,
                    line: 0,
                    field: "rigTypeID"
                )
            }
            let values = typeDogmaValues[typeID] ?? [:]
            let effects = typeDogmaEffects[typeID] ?? []
            guard effects.contains(6_976) else {
                throw StaticDataMappingError.invalidField(
                    dataset: .typeDogma,
                    line: 0,
                    field: "rigSecurityEffect"
                )
            }
            rigRules.append(
                ReactionRigRule(
                    typeID: typeID,
                    supportedKinds: kind,
                    timeBonusBasisPoints:
                        try percentageBasisPoints(values[2_713] ?? 0),
                    materialBonusBasisPoints:
                        try percentageBasisPoints(values[2_714] ?? 0),
                    lowSecurityBonusMultiplierPermille:
                        try permille(
                            try requiredDogmaValue(
                                typeID: typeID,
                                attributeID: 2_356,
                                values: typeDogmaValues
                            )
                        ),
                    nullSecurityBonusMultiplierPermille:
                        try permille(
                            try requiredDogmaValue(
                                typeID: typeID,
                                attributeID: 2_357,
                                values: typeDogmaValues
                            )
                        )
                )
            )
        }
        guard typeDogmaEffects[Self.reactionsSkillTypeID]?
            .contains(6_892) == true else {
            throw StaticDataMappingError.invalidField(
                dataset: .typeDogma,
                line: 0,
                field: "reactionSkillEffect"
            )
        }
        let skillBonus = try percentageBasisPoints(
            try requiredDogmaValue(
                typeID: Self.reactionsSkillTypeID,
                attributeID: 2_660,
                values: typeDogmaValues
            )
        )
        return ReactionRuleProfile(
            catalogBuildNumber: metadata.buildNumber,
            catalogContentSHA256: metadata.contentSHA256,
            verificationStatus: .verified,
            verifiedAt: Date(timeIntervalSince1970: 1_784_870_400),
            sourceURLs: [
                metadata.officialArchiveURL,
                "https://developers.eveonline.com/docs/services/static-data/",
                "https://support.eveonline.com/hc/en-us/articles/115005405785-Reactions"
            ],
            formulaGroupKinds: [
                1_888: .composite,
                1_889: .hybrid,
                1_890: .biochemical,
                4_097: .biochemical
            ],
            facilities: facilityRules,
            reactors: reactorRules,
            rigs: rigRules,
            reactionsSkillTypeID: Self.reactionsSkillTypeID,
            skillTimeBonusBasisPointsPerLevel: skillBonus
        )
    }

    private func requiredDogmaValue(
        typeID: Int64,
        attributeID: Int64,
        values: [Int64: [Int64: Double]]
    ) throws -> Double {
        guard let value = values[typeID]?[attributeID],
              value.isFinite else {
            throw StaticDataMappingError.invalidField(
                dataset: .typeDogma,
                line: 0,
                field: "\(typeID).\(attributeID)"
            )
        }
        return value
    }

    private func basisPoints(_ value: Double) throws -> Int64 {
        try exactScaled(value, scale: 10_000)
    }

    private func percentageBasisPoints(_ value: Double) throws -> Int64 {
        try exactScaled(value, scale: 100)
    }

    private func permille(_ value: Double) throws -> Int64 {
        try exactScaled(value, scale: 1_000)
    }

    private func exactScaled(
        _ value: Double,
        scale: Double
    ) throws -> Int64 {
        let scaled = value * scale
        let rounded = scaled.rounded()
        guard scaled.isFinite,
              rounded >= Double(Int64.min),
              rounded <= Double(Int64.max),
              abs(scaled - rounded) < 0.000_001 else {
            throw StaticDataMappingError.invalidField(
                dataset: .typeDogma,
                line: 0,
                field: "scaledDogmaValue"
            )
        }
        return Int64(rounded)
    }

    private func optionalNonnegativeDouble(
        _ value: Any?,
        dataset: SDEDatasetKind,
        line: Int,
        field: String
    ) throws -> Double? {
        guard let value else {
            return nil
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue >= 0 else {
            throw StaticDataMappingError.invalidField(
                dataset: dataset,
                line: line,
                field: field
            )
        }
        return number.doubleValue
    }

    private func optionalProbability(
        _ value: Any?,
        line: Int
    ) throws -> Double? {
        guard let value else {
            return nil
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue > 0,
              number.doubleValue <= 1 else {
            throw StaticDataMappingError.invalidField(
                dataset: .blueprints,
                line: line,
                field: "products.probability"
            )
        }
        return number.doubleValue
    }
}

private actor StaticDataCatalogSnapshotCollector {
    private var categories: [StaticItemCategorySnapshot] = []
    private var groups: [StaticItemGroupSnapshot] = []
    private var itemTypes: [StaticItemTypeSnapshot] = []
    private var blueprints: [StaticBlueprintSnapshot] = []
    private var reactionRuleProfile: ReactionRuleProfile?

    func append(_ batch: StaticDataCatalogBatch) {
        switch batch {
        case .categories(let records):
            categories.append(contentsOf: records)
        case .groups(let records):
            groups.append(contentsOf: records)
        case .itemTypes(let records):
            itemTypes.append(contentsOf: records)
        case .blueprints(let records):
            blueprints.append(contentsOf: records)
        case .reactionRuleProfile(let profile):
            reactionRuleProfile = profile
        }
    }

    func values() -> (
        categories: [StaticItemCategorySnapshot],
        groups: [StaticItemGroupSnapshot],
        itemTypes: [StaticItemTypeSnapshot],
        blueprints: [StaticBlueprintSnapshot],
        reactionRuleProfile: ReactionRuleProfile?
    ) {
        (
            categories,
            groups,
            itemTypes,
            blueprints,
            reactionRuleProfile
        )
    }
}
