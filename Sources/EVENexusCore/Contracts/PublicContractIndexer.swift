import Foundation

public protocol PublicContractRemoteFetching: Sendable {
  func regionIDs() async throws -> ESIResponse<[Int64]>
  func regionNames(ids: Set<Int64>) async -> Sourced<[Int64: String]>
  func locationNames(ids: Set<Int64>) async -> Sourced<[Int64: String]>
  func contracts(
    regionID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractDTO]>
  func items(
    contractID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractItemDTO]>
  func releaseCachedItemResponses(contractID: Int64?) async
}

extension PublicContractRemoteFetching {
  public func releaseCachedItemResponses(contractID: Int64?) async {}
}

public protocol PublicContractTypeMetadataQuerying: Sendable {
  func publicContractItemMetadata(
    typeIDs: Set<Int64>
  ) async throws -> [Int64: PublicContractItemTypeMetadata]
}

extension SQLiteStaticCatalog: PublicContractTypeMetadataQuerying {}

public struct ESIPublicContractRemote: PublicContractRemoteFetching, Sendable {
  private let esi: ESIClient
  private let universeNames: UniverseNameService

  public init(
    esi: ESIClient,
    universeNames: UniverseNameService? = nil
  ) {
    self.esi = esi
    self.universeNames = universeNames ?? UniverseNameService(esi: esi)
  }

  public func regionIDs() async throws -> ESIResponse<[Int64]> {
    try await esi.get(
      [Int64].self,
      endpoint: ESIEndpoint(path: "/universe/regions/")
    )
  }

  public func regionNames(ids: Set<Int64>) async -> Sourced<[Int64: String]> {
    await universeNames.names(for: ids)
  }

  public func locationNames(ids: Set<Int64>) async -> Sourced<[Int64: String]> {
    await universeNames.names(for: ids)
  }

  public func contracts(
    regionID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractDTO]> {
    try await esi.get(
      [ESIPublicContractDTO].self,
      endpoint: ESIEndpoint(
        path: "/contracts/public/\(regionID)/",
        query: [URLQueryItem(name: "page", value: String(page))]
      )
    )
  }

  public func items(
    contractID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractItemDTO]> {
    try await esi.get(
      [ESIPublicContractItemDTO].self,
      endpoint: ESIEndpoint(
        path: "/contracts/public/items/\(contractID)/",
        query: [URLQueryItem(name: "page", value: String(page))]
      )
    )
  }

  public func releaseCachedItemResponses(contractID: Int64?) async {
    let pathPrefix =
      contractID.map {
        "/contracts/public/items/\($0)/"
      } ?? "/contracts/public/items/"
    await esi.removeCachedPublicResponses(
      pathPrefix: pathPrefix
    )
  }
}

public actor PublicContractIndexer {
  public typealias ProgressHandler =
    @MainActor @Sendable (
      PublicContractSyncProgress
    ) -> Void

  private let remote: any PublicContractRemoteFetching
  private let catalog: any PublicContractTypeMetadataQuerying
  private let store: PublicContractStore
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private let regionRequestSpacing: TimeInterval
  private let itemRequestSpacing: TimeInterval
  private let itemRequestConcurrency: Int
  private let itemBatchSize: Int
  private let errorBudgetFloor: Int
  private let schemaFailureLimit: Int
  private var nextItemRequestStart: Date?

  public init(
    remote: any PublicContractRemoteFetching,
    catalog: any PublicContractTypeMetadataQuerying,
    store: PublicContractStore,
    regionRequestSpacing: TimeInterval = 0.25,
    itemRequestSpacing: TimeInterval = 0.5,
    itemRequestConcurrency: Int = 2,
    itemBatchSize: Int = 100,
    errorBudgetFloor: Int = 20,
    schemaFailureLimit: Int = 3,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.remote = remote
    self.catalog = catalog
    self.store = store
    self.regionRequestSpacing = max(0.1, regionRequestSpacing)
    self.itemRequestSpacing = max(0.25, itemRequestSpacing)
    self.itemRequestConcurrency = min(2, max(1, itemRequestConcurrency))
    self.itemBatchSize = min(250, max(1, itemBatchSize))
    self.errorBudgetFloor = min(50, max(5, errorBudgetFloor))
    self.schemaFailureLimit = min(10, max(1, schemaFailureLimit))
    self.now = now
    self.sleep = sleep
  }

  public func localProgress() async throws -> PublicContractSyncProgress {
    try await store.progress()
  }

  public func setAutomaticUpdatesEnabled(_ isEnabled: Bool) async throws {
    try await store.setAutomaticUpdatesEnabled(isEnabled)
  }

  public func setAutomaticSafetyNotBefore(_ date: Date?) async throws {
    try await store.setAutomaticSafetyNotBefore(date)
  }

  public func automationState(
    regularRefreshInterval: TimeInterval = 6 * 60 * 60
  ) async throws -> PublicContractAutomationState {
    try await store.automationState(
      now: now(),
      regularRefreshInterval: regularRefreshInterval
    )
  }

  public func search(
    _ filter: PublicContractSearchFilter
  ) async throws -> [PublicContractSearchResult] {
    let results = try await store.search(filter, now: now())
    try Task.checkCancellation()
    return results
  }

  public func includedOfferSnapshot(
    typeIDs: Set<Int64>,
    limitPerType: Int = 100
  ) async throws -> (
    offers: [Int64: [PublicContractSearchResult]],
    progress: PublicContractSyncProgress
  ) {
    let snapshot = try await store.includedOfferSnapshot(
      typeIDs: typeIDs,
      now: now(),
      limitPerType: limitPerType
    )
    try Task.checkCancellation()
    return snapshot
  }

  public func facets() async throws -> (
    categories: [PublicContractFacet], groups: [PublicContractFacet]
  ) {
    try await store.facets()
  }

  public func synchronizeAll(
    progress: @escaping ProgressHandler
  ) async throws -> PublicContractSyncProgress {
    do {
      await progress(
        try await store.progress(
          phase: .loadingRegions,
          message: "esi.public-contracts.loading-regions"
        )
      )
      let regionResponse = try await remote.regionIDs()
      try await respectBudget(regionResponse)
      let validRegionIDs = Set(regionResponse.value.filter { $0 > 0 })
      guard !validRegionIDs.isEmpty else {
        throw PublicContractIndexError.noRegions
      }
      let names = await remote.regionNames(ids: validRegionIDs)
      let regions = validRegionIDs.map { id in
        (id: id, name: names.value?[id] ?? "Region \(id)")
      }
      try await store.upsertRegions(regions)

      let scheduledRegions = try await store.regionSchedule(now: now())
      var schemaFailures = 0
      for region in scheduledRegions {
        try Task.checkCancellation()
        await progress(
          try await store.progress(
            phase: .loadingContracts,
            activeRegionName: region.name,
            message: "esi.public-contracts.loading-region"
          )
        )
        do {
          let batch = try await regionContracts(regionID: region.id)
          let fetchedAt = now()
          try await store.recordRegionSuccess(
            regionID: region.id,
            contracts: batch.contracts,
            fetchedAt: fetchedAt,
            nextAllowedAt: max(
              batch.expiresAt ?? fetchedAt.addingTimeInterval(30 * 60),
              fetchedAt.addingTimeInterval(60)
            )
          )
        } catch is CancellationError {
          throw CancellationError()
        } catch ESIError.cancelled {
          throw CancellationError()
        } catch let error as ESIError {
          let retryAt = now().addingTimeInterval(Self.regionRetryDelay(error))
          try await store.recordRegionFailure(
            regionID: region.id,
            attemptedAt: now(),
            retryAt: retryAt,
            diagnostic: Self.diagnostic(error)
          )
          if case .decoding = error {
            schemaFailures += 1
            if schemaFailures >= schemaFailureLimit {
              let state = try await store.progress(
                phase: .partial,
                activeRegionName: region.name,
                message: "esi.public-contracts.schema-mismatch",
                nextRequestAt: retryAt
              )
              await progress(state)
              return state
            }
          }
          if case .rateLimited = error {
            let state = try await store.progress(
              phase: .throttled,
              activeRegionName: region.name,
              message: "esi.public-contracts.rate-limited",
              nextRequestAt: retryAt
            )
            await progress(state)
            return state
          }
        } catch {
          try await store.recordRegionFailure(
            regionID: region.id,
            attemptedAt: now(),
            retryAt: now().addingTimeInterval(30 * 60),
            diagnostic: "esi.public-contracts.region-unavailable"
          )
        }
        try await sleep(regionRequestSpacing)
      }

      try await resolvePendingLocationNames()

      let detailResult = try await indexPendingItems(progress: progress)
      if detailResult.phase == .throttled || detailResult.phase == .partial {
        await progress(detailResult)
        return detailResult
      }
      let finalPhase: PublicContractSyncPhase =
        detailResult.failedRegions > 0 || detailResult.failedItemContracts > 0
        ? .partial : .completed
      let final = try await store.progress(
        phase: finalPhase,
        message:
          finalPhase == .completed
          ? "esi.public-contracts.completed" : "esi.public-contracts.partial"
      )
      await progress(final)
      return final
    } catch is CancellationError {
      let cancelled = try await store.progress(
        phase: .cancelled,
        message: "esi.public-contracts.cancelled"
      )
      await progress(cancelled)
      return cancelled
    } catch ESIError.cancelled {
      let cancelled = try await store.progress(
        phase: .cancelled,
        message: "esi.public-contracts.cancelled"
      )
      await progress(cancelled)
      return cancelled
    } catch {
      let failed = try await store.progress(
        phase: .failed,
        message: Self.diagnostic(error)
      )
      await progress(failed)
      throw error
    }
  }

  private func resolvePendingLocationNames() async throws {
    while true {
      try Task.checkCancellation()
      let locationIDs = try await store.locationIDsNeedingResolution(
        now: now(),
        limit: 1_000
      )
      guard !locationIDs.isEmpty else { return }
      let attemptedAt = now()
      let names = await remote.locationNames(ids: locationIDs)
      try await store.recordLocationResolution(
        attemptedIDs: locationIDs,
        names: names.value ?? [:],
        attemptedAt: attemptedAt,
        retryAt: attemptedAt.addingTimeInterval(6 * 60 * 60)
      )
      try await sleep(regionRequestSpacing)
    }
  }

  private func regionContracts(regionID: Int64) async throws -> (
    contracts: [ESIPublicContractDTO], expiresAt: Date?
  ) {
    var first = try await remote.contracts(regionID: regionID, page: 1)
    try await respectBudget(first)
    var pageCount = max(1, first.pages ?? 1)
    let requiredWindow = Double(pageCount) * regionRequestSpacing + 5
    if let expiresAt = first.expiresAt,
      expiresAt.timeIntervalSince(now()) < requiredWindow
    {
      try await sleep(max(1, expiresAt.timeIntervalSince(now()) + 1))
      first = try await remote.contracts(regionID: regionID, page: 1)
      try await respectBudget(first)
      pageCount = max(1, first.pages ?? 1)
    }
    guard pageCount <= 1_000 else { throw ESIError.invalidPagination }
    var contracts = first.value
    if pageCount > 1 {
      for page in 2...pageCount {
        try Task.checkCancellation()
        try await sleep(regionRequestSpacing)
        let response = try await remote.contracts(
          regionID: regionID,
          page: page
        )
        try await respectBudget(response)
        guard response.pages == nil || response.pages == pageCount,
          response.lastModified == nil || first.lastModified == nil
            || response.lastModified == first.lastModified
        else { throw ESIError.invalidPagination }
        contracts.append(contentsOf: response.value)
      }
    }
    guard Set(contracts.map(\.contractID)).count == contracts.count else {
      throw ESIError.invalidPagination
    }
    return (contracts, first.expiresAt)
  }

  private func indexPendingItems(
    progress: @escaping ProgressHandler
  ) async throws -> PublicContractSyncProgress {
    while true {
      try Task.checkCancellation()
      let contractIDs = try await store.pendingContractIDs(
        now: now(),
        limit: itemBatchSize
      )
      guard !contractIDs.isEmpty else {
        return try await store.progress(phase: .loadingItems)
      }
      do {
        let interrupted = try await indexItemBatch(
          contractIDs,
          progress: progress
        )
        await remote.releaseCachedItemResponses(contractID: nil)
        if let interrupted {
          return interrupted
        }
      } catch {
        await remote.releaseCachedItemResponses(contractID: nil)
        throw error
      }
    }
  }

  private func indexItemBatch(
    _ contractIDs: [Int64],
    progress: @escaping ProgressHandler
  ) async throws -> PublicContractSyncProgress? {
    try await withThrowingTaskGroup(of: ItemFetchOutcome.self) { group in
      var nextIndex = 0
      var completedSinceProgress = 0

      func submitNext() {
        guard nextIndex < contractIDs.count else { return }
        let contractID = contractIDs[nextIndex]
        nextIndex += 1
        group.addTask { [self] in
          await fetchItemOutcome(contractID: contractID)
        }
      }

      for _ in 0..<min(itemRequestConcurrency, contractIDs.count) {
        submitNext()
      }

      while let outcome = try await group.next() {
        do {
          let contractID = outcome.contractID
          switch outcome {
          case .success(_, let items):
            let metadata = try await catalog.publicContractItemMetadata(
              typeIDs: Set(items.map(\.typeID))
            )
            try await store.storeItems(
              contractID: contractID,
              items: items,
              metadata: metadata,
              fetchedAt: now()
            )
            await remote.releaseCachedItemResponses(contractID: contractID)
          case .esiFailure(_, let error):
            let terminal: Bool
            switch error {
            case .forbidden, .notFound, .decoding:
              terminal = true
            default:
              terminal = false
            }
            try await store.recordItemFailure(
              contractID: contractID,
              diagnostic: Self.diagnostic(error),
              terminal: terminal
            )
            await remote.releaseCachedItemResponses(contractID: contractID)
            if !terminal {
              group.cancelAll()
              return try await store.progress(
                phase: error.isRateLimited ? .throttled : .partial,
                activeContractID: contractID,
                message: Self.diagnostic(error),
                nextRequestAt:
                  error.isRateLimited
                  ? now().addingTimeInterval(Self.regionRetryDelay(error)) : nil
              )
            }
          case .otherFailure:
            try await store.recordItemFailure(
              contractID: contractID,
              diagnostic: "esi.public-contracts.item-unavailable",
              terminal: false
            )
            await remote.releaseCachedItemResponses(contractID: contractID)
            group.cancelAll()
            return try await store.progress(
              phase: .partial,
              activeContractID: contractID,
              message: "esi.public-contracts.item-unavailable"
            )
          case .cancelled:
            await remote.releaseCachedItemResponses(contractID: contractID)
            group.cancelAll()
            throw CancellationError()
          }
          completedSinceProgress += 1
          if completedSinceProgress >= 25 {
            completedSinceProgress = 0
            await progress(
              try await store.progress(
                phase: .loadingItems,
                activeContractID: contractID,
                message: "esi.public-contracts.loading-items"
              )
            )
          }
          submitNext()
        } catch {
          group.cancelAll()
          throw error
        }
      }
      await progress(
        try await store.progress(
          phase: .loadingItems,
          activeContractID: contractIDs.last,
          message: "esi.public-contracts.loading-items"
        )
      )
      return nil
    }
  }

  private func fetchItemOutcome(contractID: Int64) async -> ItemFetchOutcome {
    do {
      return .success(
        contractID,
        try await contractItems(contractID: contractID)
      )
    } catch is CancellationError {
      return .cancelled(contractID)
    } catch ESIError.cancelled {
      return .cancelled(contractID)
    } catch let error as ESIError {
      return .esiFailure(contractID, error)
    } catch {
      return .otherFailure(contractID)
    }
  }

  private func contractItems(
    contractID: Int64
  ) async throws -> [ESIPublicContractItemDTO] {
    try await waitForItemRequestSlot()
    var first = try await remote.items(contractID: contractID, page: 1)
    try await respectBudget(first)
    var pageCount = max(1, first.pages ?? 1)
    let requiredWindow = Double(pageCount) * itemRequestSpacing + 5
    if let expiresAt = first.expiresAt,
      expiresAt.timeIntervalSince(now()) < requiredWindow
    {
      try await sleep(max(1, expiresAt.timeIntervalSince(now()) + 1))
      try await waitForItemRequestSlot()
      first = try await remote.items(contractID: contractID, page: 1)
      try await respectBudget(first)
      pageCount = max(1, first.pages ?? 1)
    }
    guard pageCount <= 1_000 else { throw ESIError.invalidPagination }
    var items = first.value
    if pageCount > 1 {
      for page in 2...pageCount {
        try Task.checkCancellation()
        try await waitForItemRequestSlot()
        let response = try await remote.items(
          contractID: contractID,
          page: page
        )
        try await respectBudget(response)
        guard response.pages == nil || response.pages == pageCount,
          response.lastModified == nil || first.lastModified == nil
            || response.lastModified == first.lastModified
        else { throw ESIError.invalidPagination }
        items.append(contentsOf: response.value)
      }
    }
    guard Set(items.map(\.recordID)).count == items.count else {
      throw ESIError.invalidPagination
    }
    return items
  }

  private func waitForItemRequestSlot() async throws {
    try Task.checkCancellation()
    let current = now()
    let reservedStart = max(nextItemRequestStart ?? current, current)
    nextItemRequestStart = reservedStart.addingTimeInterval(itemRequestSpacing)
    let delay = reservedStart.timeIntervalSince(current)
    if delay > 0 {
      try await sleep(delay)
    }
    try Task.checkCancellation()
  }

  private func respectBudget<Value>(_ response: ESIResponse<Value>) async throws {
    if let remain = response.errorLimitRemain,
      remain <= errorBudgetFloor
    {
      try await sleep(Double(max(response.errorLimitReset ?? 60, 1) + 1))
    }
    if let remaining = response.rateLimitRemaining,
      remaining <= errorBudgetFloor
    {
      try await sleep(5)
    }
  }

  private static func regionRetryDelay(_ error: ESIError) -> TimeInterval {
    switch error {
    case .rateLimited(let retryAfter):
      Double(max(retryAfter ?? 15 * 60, 60))
    case .forbidden, .notFound:
      24 * 60 * 60
    case .server:
      30 * 60
    default:
      60 * 60
    }
  }

  private static func diagnostic(_ error: Error) -> String {
    guard let error = error as? ESIError else {
      if error is StaticCatalogError {
        return "esi.public-contracts.sde-unavailable"
      }
      return "esi.public-contracts.unavailable"
    }
    switch error {
    case .rateLimited:
      return "esi.public-contracts.rate-limited"
    case .forbidden:
      return "esi.public-contracts.forbidden"
    case .notFound:
      return "esi.public-contracts.not-found"
    case .invalidPagination:
      return "esi.public-contracts.inconsistent-pages"
    case .decoding:
      return "esi.public-contracts.schema-mismatch"
    case .responseTooLarge:
      return "esi.public-contracts.response-too-large"
    case .server:
      return "esi.public-contracts.server-unavailable"
    case .cancelled:
      return "esi.public-contracts.cancelled"
    default:
      return "esi.public-contracts.unavailable"
    }
  }
}

private enum ItemFetchOutcome: Sendable {
  case success(Int64, [ESIPublicContractItemDTO])
  case esiFailure(Int64, ESIError)
  case otherFailure(Int64)
  case cancelled(Int64)

  var contractID: Int64 {
    switch self {
    case .success(let contractID, _), .esiFailure(let contractID, _),
      .otherFailure(let contractID), .cancelled(let contractID):
      contractID
    }
  }
}

public enum PublicContractIndexError: Error, Equatable, Sendable {
  case noRegions
}

extension ESIError {
  fileprivate var isRateLimited: Bool {
    if case .rateLimited = self { return true }
    return false
  }
}
