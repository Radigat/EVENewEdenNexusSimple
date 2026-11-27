import Foundation

// Doctrine stock (DOKTRIN_BEDARF_PLAN.md, section G): the doctrine market
// targets of Brave's supply officer from Allumis (“Brave Doctrine Market
// Management”), matched to the wiki fits. Allumis knows fits, not
// doctrines; its target is a number of complete fits per fit.

/// Where Allumis serves the doctrine table.
public struct AllumisConfiguration: Equatable, Sendable {
  public let baseURL: URL
  /// Market of the table: Allumis offers `staging`, `secondary` and
  /// `deployment`; the staging market is the owner's Home Hub (checked
  /// 26.11.2026).
  public let location: String

  public init(baseURL: URL, location: String) {
    self.baseURL = baseURL
    self.location = location
  }

  public static let braveDoctrineMarket = AllumisConfiguration(
    baseURL: URL(string: "https://api.allumis.co.uk")!,
    location: "staging"
  )

  public var host: String { baseURL.host ?? "" }

  /// Starts the EVE SSO login of Allumis. Allumis redirects a path without
  /// trailing slash to plain `http://` (checked 26.11.2026), which never
  /// loads in the app's web view, so the path ends with one.
  public var loginURL: URL { URL(string: baseURL.absoluteString + "/login/")! }

  /// Hosts of Allumis: the API host and the start page without `api.`.
  public var webHosts: Set<String> {
    let apiHost = host.lowercased()
    return apiHost.hasPrefix("api.") ? [apiHost, String(apiHost.dropFirst(4))] : [apiHost]
  }

  /// The `https` form of a plain-`http` Allumis address, so a redirect to
  /// `http://` (paths without trailing slash) still loads; nil for every
  /// other address.
  public func secureReplacement(for url: URL?) -> URL? {
    guard let url, url.scheme?.lowercased() == "http",
      let urlHost = url.host?.lowercased(), webHosts.contains(urlHost),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    components.scheme = "https"
    if components.port == 80 { components.port = nil }
    return components.url
  }

  /// Fit list of Allumis, for links.
  public var fitListURL: URL {
    URL(string: baseURL.absoluteString + "/user/doctrines/list/")!
  }

  /// JSON of the “Full information table”: one row per fit with its items.
  public var detailedTableURL: URL {
    URL(string: baseURL.absoluteString + "/api/?path=/doctrine/ships/detailedtable/&loc=" + location)!
  }

  /// Pages of a signed-in member live under `/user`; without a session
  /// Allumis redirects to its start page on another host.
  public func isSignedInPage(_ url: URL?) -> Bool {
    guard let url, url.host?.lowercased() == host.lowercased() else { return false }
    return url.path == "/user" || url.path.hasPrefix("/user/")
  }
}

/// One fit of Allumis with the supply officer's target.
public struct AllumisFitRecord: Codable, Equatable, Sendable, Identifiable {
  /// Fitting ID of Allumis (`node_index` of the fit row).
  public let id: Int64
  public let fitName: String
  public let hull: DoctrineFitItem
  /// Number of complete fits the staging market should hold.
  public let target: Int
  /// Fit items without the hull.
  public let items: [DoctrineFitItem]
  /// Alternative modules of the fit; like refit blocks of the wiki they
  /// neither count for the target nor for the fit content.
  public let refitItems: [DoctrineFitItem]

  public init(
    id: Int64,
    fitName: String,
    hull: DoctrineFitItem,
    target: Int,
    items: [DoctrineFitItem],
    refitItems: [DoctrineFitItem]
  ) {
    self.id = id
    self.fitName = fitName
    self.hull = hull
    self.target = target
    self.items = items
    self.refitItems = refitItems
  }
}

/// Market and loss figures Allumis shows per item; the same in every fit.
public struct AllumisItemStatistic: Codable, Equatable, Sendable {
  public let name: String
  public let typeID: Int64?
  /// Ø units sold per day over 7 days at the staging market.
  public let averageDailyVolume7Days: Double?
  /// Units dropped and destroyed in the last 10 days (killmails).
  public let dropped: Int64?
  public let destroyed: Int64?

  public init(
    name: String,
    typeID: Int64?,
    averageDailyVolume7Days: Double?,
    dropped: Int64?,
    destroyed: Int64?
  ) {
    self.name = name
    self.typeID = typeID
    self.averageDailyVolume7Days = averageDailyVolume7Days
    self.dropped = dropped
    self.destroyed = destroyed
  }

  /// Dropped plus destroyed, like the column “Items lost last 10 days”;
  /// unknown when one of them is.
  public var lostLast10Days: Int64? {
    guard let dropped, let destroyed else { return nil }
    let (sum, overflow) = dropped.addingReportingOverflow(destroyed)
    return overflow ? Int64.max : sum
  }
}

public enum AllumisImportIssueKind: String, Codable, Sendable {
  case unknownItemName
  case ambiguousItemName
  /// A row without fitting ID, hull or a valid quantity; it is left out.
  case invalidEntry
}

public struct AllumisImportIssue: Codable, Equatable, Hashable, Sendable {
  public let kind: AllumisImportIssueKind
  public let fitName: String
  /// Item name or the invalid field, depending on `kind`.
  public let detail: String

  public init(kind: AllumisImportIssueKind, fitName: String, detail: String) {
    self.kind = kind
    self.fitName = fitName
    self.detail = detail
  }
}

/// The fits, targets and item figures of one Allumis import.
public struct AllumisDoctrineSnapshot: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let importedAt: Date
  public let source: String
  public let location: String
  /// Ascending fitting ID.
  public let fits: [AllumisFitRecord]
  /// Sorted by name.
  public let itemStatistics: [AllumisItemStatistic]
  public let issues: [AllumisImportIssue]

  public init(
    importedAt: Date,
    source: String,
    location: String,
    fits: [AllumisFitRecord],
    itemStatistics: [AllumisItemStatistic],
    issues: [AllumisImportIssue]
  ) {
    self.formatVersion = Self.currentFormatVersion
    self.importedAt = importedAt
    self.source = source
    self.location = location
    self.fits = fits
    self.itemStatistics = itemStatistics
    self.issues = issues
  }

  public static func encode(_ snapshot: AllumisDoctrineSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshot)
  }

  public static func decode(_ data: Data) throws -> AllumisDoctrineSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(AllumisDoctrineSnapshot.self, from: data)
    guard snapshot.formatVersion == currentFormatVersion else {
      throw DoctrineLibraryError.unsupportedFormat(snapshot.formatVersion)
    }
    return snapshot
  }
}

// MARK: Parsing

/// The detailed table before name resolution.
public struct AllumisParsedTable: Equatable, Sendable {
  public struct Item: Equatable, Sendable {
    public let name: String
    public let quantity: Int64
  }

  public struct Fit: Equatable, Sendable {
    public let id: Int64
    public let fitName: String
    public let hullName: String
    public let target: Int
    public let items: [Item]
    public let refitItems: [Item]
  }

  public struct Statistic: Equatable, Sendable {
    public let name: String
    public let averageDailyVolume7Days: Double?
    public let dropped: Int64?
    public let destroyed: Int64?
  }

  public let fits: [Fit]
  public let statistics: [Statistic]
  public let invalidEntries: [AllumisImportIssue]

  /// Every hull and item name, for the SDE lookup.
  public var itemNames: Set<String> {
    var names: Set<String> = []
    for fit in fits {
      names.insert(fit.hullName)
      names.formUnion(fit.items.map(\.name))
      names.formUnion(fit.refitItems.map(\.name))
    }
    return names
  }
}

public enum AllumisDetailedTableParser {
  /// Parses the JSON of `detailedTableURL`. Allumis sends numbers mostly
  /// as strings; both forms are accepted. Rules:
  /// - a row is a fit: `node_index` is the fitting ID, `itemName` the hull,
  ///   `fittingName` the fit name and `minStock` the target in fits;
  /// - children with `fittingName` “Fit Item” are the fit content, every
  ///   other child (“Refit Item”) is a refit; equal names add up;
  /// - `avg7dVol`, `dropped` and `destroyed` are per item and equal in every
  ///   fit; if they ever differ the larger value counts;
  /// - rows without fitting ID or hull, and items without a whole quantity
  ///   of at least 1, are left out and reported; a repeated fitting ID
  ///   keeps its first row.
  /// Throws when the data is not a JSON array of rows.
  public static func parse(_ data: Data) throws -> AllumisParsedTable {
    let rows = try JSONDecoder().decode([Row].self, from: data)
    var fits: [AllumisParsedTable.Fit] = []
    var seenIDs: Set<Int64> = []
    var invalid: [AllumisImportIssue] = []
    var statistics: [String: AllumisParsedTable.Statistic] = [:]

    func observe(_ row: Row, name: String) {
      let observed = AllumisParsedTable.Statistic(
        name: name,
        averageDailyVolume7Days: row.avg7dVol?.nonnegative,
        dropped: row.dropped?.wholeNonnegative,
        destroyed: row.destroyed?.wholeNonnegative
      )
      guard let known = statistics[name] else {
        statistics[name] = observed
        return
      }
      statistics[name] = AllumisParsedTable.Statistic(
        name: name,
        averageDailyVolume7Days: larger(known.averageDailyVolume7Days, observed.averageDailyVolume7Days),
        dropped: larger(known.dropped, observed.dropped),
        destroyed: larger(known.destroyed, observed.destroyed)
      )
    }

    for row in rows {
      let fitName = row.fittingName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let id = row.nodeIndex?.wholeNonnegative else {
        invalid.append(AllumisImportIssue(kind: .invalidEntry, fitName: fitName, detail: "node_index"))
        continue
      }
      guard let hullName = row.itemName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !hullName.isEmpty
      else {
        invalid.append(AllumisImportIssue(kind: .invalidEntry, fitName: fitName, detail: "itemName"))
        continue
      }
      guard seenIDs.insert(id).inserted else { continue }
      observe(row, name: hullName)

      var itemOrder: [String] = []
      var itemQuantities: [String: Int64] = [:]
      var refitOrder: [String] = []
      var refitQuantities: [String: Int64] = [:]
      for child in row.children ?? [] {
        guard let name = child.itemName?.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.isEmpty
        else {
          invalid.append(AllumisImportIssue(kind: .invalidEntry, fitName: fitName, detail: "itemName"))
          continue
        }
        guard let quantity = child.quantity?.wholeNonnegative, quantity >= 1 else {
          invalid.append(AllumisImportIssue(kind: .invalidEntry, fitName: fitName, detail: name))
          continue
        }
        observe(child, name: name)
        let isFitItem =
          child.fittingName?.trimmingCharacters(in: .whitespaces).lowercased() == "fit item"
        if isFitItem {
          if itemQuantities[name] == nil { itemOrder.append(name) }
          itemQuantities[name] = add(itemQuantities[name] ?? 0, quantity)
        } else {
          if refitQuantities[name] == nil { refitOrder.append(name) }
          refitQuantities[name] = add(refitQuantities[name] ?? 0, quantity)
        }
      }
      let target = row.minStock?.wholeNonnegative.map {
        Int(min($0, Int64(DoctrineTargets.maximumTarget)))
      }
      fits.append(
        AllumisParsedTable.Fit(
          id: id,
          fitName: fitName.isEmpty ? hullName : fitName,
          hullName: hullName,
          target: target ?? 0,
          items: itemOrder.map { .init(name: $0, quantity: itemQuantities[$0] ?? 0) },
          refitItems: refitOrder.map { .init(name: $0, quantity: refitQuantities[$0] ?? 0) }
        )
      )
    }
    return AllumisParsedTable(
      fits: fits.sorted { $0.id < $1.id },
      statistics: statistics.values.sorted { $0.name < $1.name },
      invalidEntries: invalid
    )
  }

  private static func add(_ left: Int64, _ right: Int64) -> Int64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    return overflow ? EFTFitParser.maximumQuantity : min(EFTFitParser.maximumQuantity, sum)
  }

  private static func larger<T: Comparable>(_ left: T?, _ right: T?) -> T? {
    switch (left, right) {
    case (let left?, let right?): max(left, right)
    case (let left?, nil): left
    case (nil, let right?): right
    case (nil, nil): nil
    }
  }

  private struct Row: Decodable {
    let itemName: String?
    let fittingName: String?
    let quantity: FlexibleNumber?
    let minStock: FlexibleNumber?
    let avg7dVol: FlexibleNumber?
    let dropped: FlexibleNumber?
    let destroyed: FlexibleNumber?
    let nodeIndex: FlexibleNumber?
    let children: [Row]?

    enum CodingKeys: String, CodingKey {
      case itemName
      case fittingName
      case quantity
      case minStock
      case avg7dVol
      case dropped
      case destroyed
      case nodeIndex = "node_index"
      case children = "_children"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      itemName = try? container.decodeIfPresent(String.self, forKey: .itemName)
      fittingName = try? container.decodeIfPresent(String.self, forKey: .fittingName)
      quantity = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .quantity)
      minStock = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .minStock)
      avg7dVol = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .avg7dVol)
      dropped = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .dropped)
      destroyed = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .destroyed)
      nodeIndex = try? container.decodeIfPresent(FlexibleNumber.self, forKey: .nodeIndex)
      children = try container.decodeIfPresent([Row].self, forKey: .children)
    }
  }

  /// A number sent as JSON number or numeric string.
  private struct FlexibleNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        value = nil
      } else if let number = try? container.decode(Double.self) {
        value = number
      } else if let text = try? container.decode(String.self) {
        value = Double(text.trimmingCharacters(in: .whitespaces))
      } else {
        value = nil
      }
    }

    var nonnegative: Double? {
      guard let value, value.isFinite, value >= 0 else { return nil }
      return value
    }

    var wholeNonnegative: Int64? {
      guard let value = nonnegative, value.rounded() == value, value < 9e15 else { return nil }
      return Int64(value)
    }
  }
}

public enum AllumisSnapshotBuilder {
  /// Resolves the names of `table` and builds the snapshot. Names that are
  /// unknown or ambiguous keep no type ID and are reported once.
  public static func build(
    table: AllumisParsedTable,
    resolutions: [String: ItemTypeNameResolution],
    configuration: AllumisConfiguration,
    importedAt: Date
  ) -> AllumisDoctrineSnapshot {
    var issues = table.invalidEntries
    var reported: Set<String> = []
    func typeID(_ name: String, fitName: String) -> Int64? {
      switch resolutions[name] {
      case .resolved(let typeID, _, _)?:
        return typeID
      case .ambiguous?:
        if reported.insert(name).inserted {
          issues.append(AllumisImportIssue(kind: .ambiguousItemName, fitName: fitName, detail: name))
        }
      case .unknown?, .localizedNamesUnavailable?, nil:
        if reported.insert(name).inserted {
          issues.append(AllumisImportIssue(kind: .unknownItemName, fitName: fitName, detail: name))
        }
      }
      return nil
    }
    let fits = table.fits.map { fit in
      AllumisFitRecord(
        id: fit.id,
        fitName: fit.fitName,
        hull: DoctrineFitItem(
          name: fit.hullName,
          typeID: typeID(fit.hullName, fitName: fit.fitName),
          quantity: 1
        ),
        target: fit.target,
        items: fit.items.map {
          DoctrineFitItem(name: $0.name, typeID: typeID($0.name, fitName: fit.fitName), quantity: $0.quantity)
        },
        refitItems: fit.refitItems.map {
          DoctrineFitItem(name: $0.name, typeID: typeID($0.name, fitName: fit.fitName), quantity: $0.quantity)
        }
      )
    }
    let statistics = table.statistics.map { statistic in
      AllumisItemStatistic(
        name: statistic.name,
        typeID: resolutions[statistic.name].flatMap {
          if case .resolved(let typeID, _, _) = $0 { return typeID }
          return nil
        },
        averageDailyVolume7Days: statistic.averageDailyVolume7Days,
        dropped: statistic.dropped,
        destroyed: statistic.destroyed
      )
    }
    var seen: Set<AllumisImportIssue> = []
    return AllumisDoctrineSnapshot(
      importedAt: importedAt,
      source: configuration.baseURL.absoluteString,
      location: configuration.location,
      fits: fits,
      itemStatistics: statistics,
      issues: issues.filter { seen.insert($0).inserted }
    )
  }
}

// MARK: Import

public enum AllumisImportError: Error, Equatable, Sendable {
  /// Allumis answered with a redirect, 401/403 or a page instead of JSON:
  /// the session is missing or expired.
  case notSignedIn
  case httpStatus(Int)
  /// The answer is JSON but not the expected table.
  case unreadableResponse
  /// The table holds no fit.
  case noFits
}

public struct AllumisImporter: Sendable {
  public typealias Fetch = @Sendable (URL) async throws -> (Data, URLResponse)
  public typealias Resolve =
    @Sendable ([String]) async throws -> [String: ItemTypeNameResolution]

  public let configuration: AllumisConfiguration
  private let fetch: Fetch
  private let resolve: Resolve

  public init(
    configuration: AllumisConfiguration = .braveDoctrineMarket,
    fetch: @escaping Fetch,
    resolve: @escaping Resolve
  ) {
    self.configuration = configuration
    self.fetch = fetch
    self.resolve = resolve
  }

  /// Reads the detailed table once, resolves its names and builds the
  /// snapshot.
  public func run(now: @Sendable () -> Date = Date.init) async throws -> AllumisDoctrineSnapshot {
    let (data, response) = try await fetch(configuration.detailedTableURL)
    if let http = response as? HTTPURLResponse {
      switch http.statusCode {
      case 200: break
      case 300...399, 401, 403: throw AllumisImportError.notSignedIn
      default: throw AllumisImportError.httpStatus(http.statusCode)
      }
    }
    guard response.mimeType?.lowercased() == "application/json" else {
      throw AllumisImportError.notSignedIn
    }
    let table: AllumisParsedTable
    do {
      table = try AllumisDetailedTableParser.parse(data)
    } catch {
      throw AllumisImportError.unreadableResponse
    }
    guard !table.fits.isEmpty else { throw AllumisImportError.noFits }
    try Task.checkCancellation()
    let resolutions = try await resolve(table.itemNames.sorted())
    return AllumisSnapshotBuilder.build(
      table: table,
      resolutions: resolutions,
      configuration: configuration,
      importedAt: now()
    )
  }
}

// MARK: Matching and merging

/// The wiki library joined with Allumis: the doctrines of the wiki plus the
/// group “Only at Allumis” for every Allumis fit without a wiki counterpart.
public struct DoctrineAllumisMerge: Equatable, Sendable {
  /// Doctrine ID of the group of Allumis fits without a wiki counterpart.
  public static let onlyAtAllumisDoctrineID = "allumis:only"

  /// Fit ID of an Allumis fit inside the merged library.
  public static func fitID(allumisFitID: Int64) -> String { "allumis:\(allumisFitID)" }

  public let library: DoctrineLibrary
  /// Whether an Allumis import exists. Without one there is no target at
  /// all, which is not the same as a target of 0.
  public let hasAllumisImport: Bool
  /// The Allumis fit behind each fit ID of `library`: the paired one of a
  /// wiki fit and the fit itself in the group “Only at Allumis”. Every
  /// Allumis fit appears exactly once.
  public let allumisFitByFitID: [String: AllumisFitRecord]
  /// Allumis target per fit ID of `library`.
  public let allumisTargetByFitID: [String: Int]
  /// Wiki fits paired by hull and name although their content differs.
  public let contentDiffersFitIDs: Set<String>
  /// Wiki fits paired with an Allumis fit.
  public let matchedWikiFitCount: Int
  /// Allumis fits in the group “Only at Allumis”.
  public let onlyAtAllumisFitCount: Int

  /// Resolved types of every fit, from the wiki content and from the
  /// content of the paired Allumis fit (refits not counted).
  public var allTypeIDs: Set<Int64> {
    var typeIDs: Set<Int64> = []
    func insert(_ hull: DoctrineFitItem, _ items: [DoctrineFitItem]) {
      if let typeID = hull.typeID { typeIDs.insert(typeID) }
      for item in items {
        if let typeID = item.typeID { typeIDs.insert(typeID) }
      }
    }
    for fit in library.fits { insert(fit.hull, fit.items) }
    for fit in allumisFitByFitID.values { insert(fit.hull, fit.items) }
    return typeIDs
  }

  /// Allumis targets of the fits of `doctrine`.
  public func allumisTargets(for doctrine: DoctrineRecord) -> DoctrineAllumisTargets {
    var counts: [Int: Int] = [:]
    var matched = 0
    var differing = 0
    for fitID in doctrine.fitIDs {
      guard let target = allumisTargetByFitID[fitID] else { continue }
      matched += 1
      counts[target, default: 0] += 1
      if contentDiffersFitIDs.contains(fitID) { differing += 1 }
    }
    return DoctrineAllumisTargets(
      fitCount: doctrine.fitIDs.count,
      matchedFitCount: matched,
      contentDiffersFitCount: differing,
      targetCounts: counts.map { DoctrineAllumisTargets.TargetCount(target: $0.key, fitCount: $0.value) }
        .sorted { lhs, rhs in
          lhs.fitCount != rhs.fitCount ? lhs.fitCount > rhs.fitCount : lhs.target > rhs.target
        }
    )
  }
}

/// What Allumis wants for the fits of one doctrine.
public struct DoctrineAllumisTargets: Equatable, Sendable {
  public struct TargetCount: Equatable, Sendable {
    public let target: Int
    public let fitCount: Int
  }

  public let fitCount: Int
  public let matchedFitCount: Int
  public let contentDiffersFitCount: Int
  /// Most frequent target first; equal frequency puts the larger target
  /// first.
  public let targetCounts: [TargetCount]

  /// The most frequent Allumis target of the doctrine's fits, the larger
  /// one on a tie; nil when no fit of the doctrine is at Allumis. Sorts the
  /// doctrine list.
  public var mostFrequentTarget: Int? { targetCounts.first?.target }
}

public enum DoctrineAllumisMerger {
  /// Pairs every Allumis fit with at most one wiki fit and back:
  /// 1. same content and same hull and name,
  /// 2. same content (hull and items with quantities, refits ignored),
  /// 3. same hull and name, then marked as differing content.
  /// Names compare without leading tags such as `[DOC]`, case and extra
  /// spaces. Within a pass Allumis fits go by ascending fitting ID and take
  /// the first free wiki fit in library order. Unpaired Allumis fits form
  /// the group “Only at Allumis”, whose title the page localizes.
  public static func merge(
    library: DoctrineLibrary?,
    snapshot: AllumisDoctrineSnapshot?
  ) -> DoctrineAllumisMerge? {
    guard library != nil || snapshot != nil else { return nil }
    let wiki =
      library
      ?? DoctrineLibrary(
        importedAt: snapshot?.importedAt ?? Date(timeIntervalSince1970: 0),
        source: "",
        doctrines: [],
        fits: [],
        issues: []
      )
    guard let snapshot else {
      return DoctrineAllumisMerge(
        library: wiki,
        hasAllumisImport: false,
        allumisFitByFitID: [:],
        allumisTargetByFitID: [:],
        contentDiffersFitIDs: [],
        matchedWikiFitCount: 0,
        onlyAtAllumisFitCount: 0
      )
    }

    struct Key {
      let content: String
      let name: String
    }
    let wikiKeys = wiki.fits.map {
      Key(content: contentSignature(hull: $0.hull, items: $0.items), name: nameKey(hull: $0.hull, fitName: $0.fitName))
    }
    let allumisFits = snapshot.fits.sorted { $0.id < $1.id }
    let allumisKeys = allumisFits.map {
      Key(content: contentSignature(hull: $0.hull, items: $0.items), name: nameKey(hull: $0.hull, fitName: $0.fitName))
    }
    var freeWiki = Array(repeating: true, count: wiki.fits.count)
    var pairedWikiIndex: [Int?] = Array(repeating: nil, count: allumisFits.count)
    var differs: Set<String> = []

    func pass(_ matches: (Key, Key) -> Bool, markDiffering: Bool) {
      for allumisIndex in allumisFits.indices where pairedWikiIndex[allumisIndex] == nil {
        guard
          let wikiIndex = wiki.fits.indices.first(where: {
            freeWiki[$0] && matches(allumisKeys[allumisIndex], wikiKeys[$0])
          })
        else { continue }
        freeWiki[wikiIndex] = false
        pairedWikiIndex[allumisIndex] = wikiIndex
        if markDiffering { differs.insert(wiki.fits[wikiIndex].id) }
      }
    }
    pass({ $0.content == $1.content && $0.name == $1.name }, markDiffering: false)
    pass({ $0.content == $1.content }, markDiffering: false)
    pass({ $0.name == $1.name }, markDiffering: true)

    var targets: [String: Int] = [:]
    var fitsByFitID: [String: AllumisFitRecord] = [:]
    var onlyAtAllumis: [DoctrineFitRecord] = []
    for (allumisIndex, fit) in allumisFits.enumerated() {
      if let wikiIndex = pairedWikiIndex[allumisIndex] {
        targets[wiki.fits[wikiIndex].id] = fit.target
        fitsByFitID[wiki.fits[wikiIndex].id] = fit
      } else {
        let fitID = DoctrineAllumisMerge.fitID(allumisFitID: fit.id)
        targets[fitID] = fit.target
        fitsByFitID[fitID] = fit
        onlyAtAllumis.append(
          DoctrineFitRecord(
            id: fitID,
            pageID: DoctrineAllumisMerge.onlyAtAllumisDoctrineID,
            sectionAnchors: [],
            hull: fit.hull,
            fitName: fit.fitName,
            items: fit.items
          )
        )
      }
    }
    var doctrines = wiki.doctrines
    if !onlyAtAllumis.isEmpty {
      doctrines.append(
        DoctrineRecord(
          id: DoctrineAllumisMerge.onlyAtAllumisDoctrineID,
          title: "Only at Allumis",
          fitIDs: onlyAtAllumis.map(\.id)
        )
      )
    }
    return DoctrineAllumisMerge(
      library: DoctrineLibrary(
        importedAt: wiki.importedAt,
        source: wiki.source,
        doctrines: doctrines,
        fits: wiki.fits + onlyAtAllumis,
        issues: wiki.issues
      ),
      hasAllumisImport: true,
      allumisFitByFitID: fitsByFitID,
      allumisTargetByFitID: targets,
      contentDiffersFitIDs: differs,
      matchedWikiFitCount: pairedWikiIndex.compactMap { $0 }.count,
      onlyAtAllumisFitCount: onlyAtAllumis.count
    )
  }

  /// Hull and items with their summed quantities, by type ID where known
  /// and by name otherwise, independent of order.
  static func contentSignature(hull: DoctrineFitItem, items: [DoctrineFitItem]) -> String {
    var quantities: [String: Int64] = [:]
    for item in items {
      let key = itemKey(item)
      let (sum, overflow) = (quantities[key] ?? 0).addingReportingOverflow(item.quantity)
      quantities[key] = overflow ? Int64.max : sum
    }
    let body = quantities.keys.sorted().map { "\($0)*\(quantities[$0] ?? 0)" }.joined(separator: ";")
    return itemKey(hull) + "|" + body
  }

  static func nameKey(hull: DoctrineFitItem, fitName: String) -> String {
    itemKey(hull) + "|" + normalizedFitName(fitName)
  }

  /// Fit name without leading tags (`[DOC] `, `[WORKSHOP] `), in lower case
  /// with single spaces.
  static func normalizedFitName(_ name: String) -> String {
    var rest = Substring(name.trimmingCharacters(in: .whitespacesAndNewlines))
    while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
      rest = rest[rest.index(after: close)...].drop(while: \.isWhitespace)
    }
    return rest.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }

  private static func itemKey(_ item: DoctrineFitItem) -> String {
    item.typeID.map { "t\($0)" } ?? "n" + item.name.lowercased()
  }
}

/// Allumis market and loss figures per item for the doctrine table. The
/// target of the item is `DoctrineItemDemand.requiredQuantity`.
public struct DoctrineAllumisItemFigures: Equatable, Sendable {
  public let averageDailyVolume7Days: Double?
  public let dropped: Int64?
  public let destroyed: Int64?

  public init(
    averageDailyVolume7Days: Double?,
    dropped: Int64?,
    destroyed: Int64?
  ) {
    self.averageDailyVolume7Days = averageDailyVolume7Days
    self.dropped = dropped
    self.destroyed = destroyed
  }

  /// A type Allumis does not list: statistics unknown.
  public static let notListed = DoctrineAllumisItemFigures(
    averageDailyVolume7Days: nil,
    dropped: nil,
    destroyed: nil
  )

  public var lostLast10Days: Int64? {
    guard let dropped, let destroyed else { return nil }
    let (sum, overflow) = dropped.addingReportingOverflow(destroyed)
    return overflow ? Int64.max : sum
  }
}

public enum DoctrineAllumisItemAggregator {
  /// Figures per resolved type that Allumis lists; the first statistic of a
  /// type counts.
  public static func figures(
    snapshot: AllumisDoctrineSnapshot
  ) -> [Int64: DoctrineAllumisItemFigures] {
    var result: [Int64: DoctrineAllumisItemFigures] = [:]
    for statistic in snapshot.itemStatistics {
      guard let typeID = statistic.typeID, result[typeID] == nil else { continue }
      result[typeID] = DoctrineAllumisItemFigures(
        averageDailyVolume7Days: statistic.averageDailyVolume7Days,
        dropped: statistic.dropped,
        destroyed: statistic.destroyed
      )
    }
    return result
  }
}
