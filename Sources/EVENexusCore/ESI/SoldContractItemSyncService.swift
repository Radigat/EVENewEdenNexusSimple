import Foundation

/// Item lines of own contracts a character was paid for.
public struct SoldContractItemsResult: Sendable {
  /// Contracts whose item lines ESI delivered, in request order.
  public let loaded: [(contractID: Int64, items: [ESIPrivateContractItemDTO])]
  /// Requested contracts without a usable answer (error, no lines, limit).
  public let unavailableContractIDs: [Int64]

  public init(
    loaded: [(contractID: Int64, items: [ESIPrivateContractItemDTO])],
    unavailableContractIDs: [Int64]
  ) {
    self.loaded = loaded
    self.unavailableContractIDs = unavailableContractIDs
  }
}

/// Loads the item lines of accepted contracts by ID so a `contract_price`
/// income can be matched with the sold item. The item endpoint answers for
/// every contract the character is a party of, also finished ones, as long
/// as ESI still knows the contract.
public struct SoldContractItemSyncService: Sendable {
  public static let requiredScope = PrivateContractSyncService.requiredScope
  /// Upper bound of item requests per character and synchronization.
  public static let maximumContracts = 50

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func load(
    characterID: Int64,
    contractIDs: [Int64],
    lease: AccessTokenLease
  ) async -> SoldContractItemsResult {
    guard lease.characterID == characterID,
      lease.scopes.contains(Self.requiredScope)
    else {
      return SoldContractItemsResult(
        loaded: [], unavailableContractIDs: contractIDs)
    }
    let requested = Array(contractIDs.prefix(Self.maximumContracts))
    var loaded: [(contractID: Int64, items: [ESIPrivateContractItemDTO])] = []
    var unavailable = Array(contractIDs.dropFirst(Self.maximumContracts))
    let client = esi
    do {
      try await ESIOrderedLoader.load(
        count: requested.count,
        load: { index -> [ESIPrivateContractItemDTO]? in
          let contractID = requested[index]
          do {
            return try await client.get(
              [ESIPrivateContractItemDTO].self,
              endpoint: ESIEndpoint(
                path:
                  "/characters/\(characterID)/contracts/\(contractID)/items/",
                requiresAuthorization: true,
                requiredScope: Self.requiredScope
              ),
              lease: lease
            ).value
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            // One contract ESI no longer knows must not end the others.
            return nil
          }
        },
        deliver: { index, items in
          if let items, !items.isEmpty {
            loaded.append((requested[index], items))
          } else {
            unavailable.append(requested[index])
          }
        }
      )
    } catch {
      // Cancelled: what was delivered so far stays usable.
      let delivered = Set(loaded.map(\.contractID)).union(unavailable)
      unavailable.append(contentsOf: requested.filter { !delivered.contains($0) })
    }
    return SoldContractItemsResult(
      loaded: loaded, unavailableContractIDs: unavailable)
  }
}
