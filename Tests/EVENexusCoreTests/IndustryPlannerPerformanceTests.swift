import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry planner query efficiency")
struct IndustryPlannerPerformanceTests {
  @Test
  func marketDiscoveryVisitsSharedProductionBranchesOnce() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let definitions: [Int64: BlueprintDefinition] = [
      1: Self.definition(
        blueprintID: 101,
        productID: 1,
        materials: [2, 3],
        source: source
      ),
      2: Self.definition(
        blueprintID: 102,
        productID: 2,
        materials: [4],
        source: source
      ),
      3: Self.definition(
        blueprintID: 103,
        productID: 3,
        materials: [4],
        source: source
      ),
    ]
    let catalog = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      definitions: definitions
    )

    let result = try await IndustryPlanner().requiredMarketTypeIDs(
      input: "Product 1 10 20",
      catalog: catalog
    )

    #expect(result == [1, 2, 3, 4])
    #expect(await catalog.definitionCallCounts() == [1: 1, 2: 1, 3: 1, 4: 1])
  }

  @Test
  func memoizedCatalogCachesPresentAndMissingResults() async throws {
    let base = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      typeNames: [1: "Product"]
    )
    let catalog = MemoizedIndustryCatalog(base: base)

    #expect(try await catalog.typeID(named: "Product") == 1)
    #expect(try await catalog.typeID(named: "Product") == 1)
    #expect(try await catalog.typeName(id: 1) == "Product")
    #expect(try await catalog.typeName(id: 1) == "Product")
    #expect(try await catalog.productionDefinition(productTypeID: 999) == nil)
    #expect(try await catalog.productionDefinition(productTypeID: 999) == nil)

    #expect(await base.typeIDCallCount(named: "Product") == 1)
    #expect(await base.typeNameCallCount(id: 1) == 1)
    #expect(await base.definitionCallCount(id: 999) == 1)
  }

  private static func definition(
    blueprintID: Int64,
    productID: Int64,
    materials: [Int64],
    source: SourceIdentity
  ) -> BlueprintDefinition {
    BlueprintDefinition(
      blueprintTypeID: blueprintID,
      productTypeID: productID,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: materials.map {
          BlueprintMaterial(typeID: $0, quantity: 1)
        },
        products: [
          BlueprintProduct(
            typeID: productID,
            quantity: 1,
            probability: nil
          )
        ]
      ),
      source: source
    )
  }
}

private actor CountingIndustryCatalog: IndustryCatalogQuerying {
  private let typeIDs: [String: Int64]
  private let typeNames: [Int64: String]
  private let definitions: [Int64: BlueprintDefinition]
  private var typeIDCalls: [String: Int] = [:]
  private var typeNameCalls: [Int64: Int] = [:]
  private var definitionCalls: [Int64: Int] = [:]

  init(
    typeIDs: [String: Int64] = [:],
    typeNames: [Int64: String] = [:],
    definitions: [Int64: BlueprintDefinition] = [:]
  ) {
    self.typeIDs = typeIDs
    self.typeNames = typeNames
    self.definitions = definitions
  }

  func typeID(named name: String) async throws -> Int64? {
    typeIDCalls[name, default: 0] += 1
    return typeIDs[name]
  }

  func typeName(id: Int64) async throws -> String? {
    typeNameCalls[id, default: 0] += 1
    return typeNames[id]
  }

  func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    definitionCalls[productTypeID, default: 0] += 1
    return definitions[productTypeID]
  }

  func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    nil
  }

  func packagedVolume(typeID: Int64) async throws -> Double? {
    nil
  }

  func definitionCallCounts() -> [Int64: Int] {
    definitionCalls
  }

  func definitionCallCount(id: Int64) -> Int {
    definitionCalls[id, default: 0]
  }

  func typeIDCallCount(named name: String) -> Int {
    typeIDCalls[name, default: 0]
  }

  func typeNameCallCount(id: Int64) -> Int {
    typeNameCalls[id, default: 0]
  }
}
