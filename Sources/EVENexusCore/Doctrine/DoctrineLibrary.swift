import Foundation

// Doctrine stock (DOKTRIN_BEDARF_PLAN.md): the imported doctrine library and
// how it is built from parsed wiki pages.

/// Where the doctrines live in the alliance wiki.
public struct DoctrineWikiConfiguration: Equatable, Sendable {
  public let baseURL: URL
  /// Namespace of the doctrine pages; its `start` page is the overview.
  public let doctrineNamespace: String
  /// Namespace of the ship pages that hold the fits.
  public let shipNamespace: String

  public init(baseURL: URL, doctrineNamespace: String, shipNamespace: String) {
    self.baseURL = baseURL
    self.doctrineNamespace = doctrineNamespace
    self.shipNamespace = shipNamespace
  }

  /// Brave Collective's member wiki (owner decision 25.11.2026).
  public static let braveCollective = DoctrineWikiConfiguration(
    baseURL: URL(string: "https://wiki.bravecollective.com")!,
    doctrineNamespace: "member:alliance:military:doctrines",
    shipNamespace: "member:alliance:military:doctrines:ships"
  )

  public var host: String { baseURL.host ?? "" }

  /// Login page of the wiki.
  public var loginURL: URL {
    baseURL.appendingPathComponent("start").appending(queryItems: [
      URLQueryItem(name: "do", value: "login")
    ])
  }

  /// Index page listing the pages of `namespace`.
  public func indexURL(namespace: String) -> URL {
    baseURL.appendingPathComponent("").appending(queryItems: [
      URLQueryItem(name: "idx", value: namespace)
    ])
  }

  /// Raw DokuWiki markup of `pageID`.
  public func rawURL(pageID: String) -> URL {
    var url = baseURL
    for part in pageID.split(separator: ":") {
      url.appendPathComponent(String(part))
    }
    return url.appending(queryItems: [URLQueryItem(name: "do", value: "export_raw")])
  }

  /// Rendered page, optionally at a section anchor.
  public func pageURL(pageID: String, anchor: String? = nil) -> URL {
    var url = baseURL
    for part in pageID.split(separator: ":") {
      url.appendPathComponent(String(part))
    }
    guard let anchor, var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.fragment = anchor
    return components.url ?? url
  }
}

/// One item of a fit with its SDE type, when the name resolved.
public struct DoctrineFitItem: Codable, Equatable, Sendable {
  public let name: String
  /// `nil` when the name is unknown or ambiguous in the SDE.
  public let typeID: Int64?
  public let quantity: Int64

  public init(name: String, typeID: Int64?, quantity: Int64) {
    self.name = name
    self.typeID = typeID
    self.quantity = quantity
  }
}

/// One EFT fit of the wiki.
public struct DoctrineFitRecord: Codable, Equatable, Sendable, Identifiable {
  /// `<pageID>#<n>`, n counting the fits of the page from 1.
  public let id: String
  public let pageID: String
  /// Anchors of the sections enclosing the fit, outermost first.
  public let sectionAnchors: [String]
  public let hull: DoctrineFitItem
  public let fitName: String
  /// Modules, charges, drones and cargo, without the hull.
  public let items: [DoctrineFitItem]

  public init(
    id: String,
    pageID: String,
    sectionAnchors: [String],
    hull: DoctrineFitItem,
    fitName: String,
    items: [DoctrineFitItem]
  ) {
    self.id = id
    self.pageID = pageID
    self.sectionAnchors = sectionAnchors
    self.hull = hull
    self.fitName = fitName
    self.items = items
  }
}

/// A doctrine page and the fits it uses.
public struct DoctrineRecord: Codable, Equatable, Sendable, Identifiable {
  /// Page ID of the doctrine page.
  public let id: String
  public let title: String
  public let fitIDs: [String]

  public init(id: String, title: String, fitIDs: [String]) {
    self.id = id
    self.title = title
    self.fitIDs = fitIDs
  }
}

public enum DoctrineImportIssueKind: String, Codable, Sendable {
  /// A doctrine links a ship page that does not exist.
  case linkedPageMissing
  /// A doctrine links a section that the ship page no longer has; the
  /// doctrine gets every fit of the page (owner decision 25.11.2026).
  case linkedSectionMissing
  /// A doctrine page yields no fit at all.
  case doctrineWithoutFits
  /// An item or hull name is not in the SDE.
  case unknownItemName
  /// An item or hull name matches several SDE types.
  case ambiguousItemName
  /// A page could not be read; it is missing from the library.
  case pageUnreadable
}

public struct DoctrineImportIssue: Codable, Equatable, Hashable, Sendable {
  public let kind: DoctrineImportIssueKind
  public let pageID: String
  /// Link target, item name or reason, depending on `kind`.
  public let detail: String

  public init(kind: DoctrineImportIssueKind, pageID: String, detail: String) {
    self.kind = kind
    self.pageID = pageID
    self.detail = detail
  }
}

/// The imported doctrines with every fit of the wiki.
public struct DoctrineLibrary: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let importedAt: Date
  /// Base URL of the wiki the library was read from.
  public let source: String
  public let doctrines: [DoctrineRecord]
  /// Every fit of the ship pages and doctrine pages, also those no doctrine
  /// links; they count for “Fits” but never for the required quantity.
  public let fits: [DoctrineFitRecord]
  public let issues: [DoctrineImportIssue]

  public init(
    importedAt: Date,
    source: String,
    doctrines: [DoctrineRecord],
    fits: [DoctrineFitRecord],
    issues: [DoctrineImportIssue]
  ) {
    self.formatVersion = Self.currentFormatVersion
    self.importedAt = importedAt
    self.source = source
    self.doctrines = doctrines
    self.fits = fits
    self.issues = issues
  }

  public static func encode(_ library: DoctrineLibrary) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(library)
  }

  public static func decode(_ data: Data) throws -> DoctrineLibrary {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let library = try decoder.decode(DoctrineLibrary.self, from: data)
    guard library.formatVersion == currentFormatVersion else {
      throw DoctrineLibraryError.unsupportedFormat(library.formatVersion)
    }
    return library
  }
}

public enum DoctrineLibraryError: Error, Equatable, Sendable {
  case unsupportedFormat(Int)
}

/// The owner's required number of fits per doctrine (doctrine page ID →
/// count). Every fit of a doctrine needs that many (owner decision
/// 25.11.2026); a missing doctrine means 0.
public enum DoctrineTargets {
  public static let maximumTarget = 10_000

  public static func clamped(_ value: Int) -> Int {
    min(maximumTarget, max(0, value))
  }

  public static func encode(_ targets: [String: Int]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(targets.filter { $0.value > 0 })
  }

  public static func decode(_ data: Data) throws -> [String: Int] {
    try JSONDecoder().decode([String: Int].self, from: data)
      .mapValues(clamped)
      .filter { $0.value > 0 }
  }
}

// MARK: Building

public enum DoctrineLibraryBuilder {
  /// A fit as found on a page, before name resolution.
  public struct PageFit: Equatable, Sendable {
    public let id: String
    public let pageID: String
    public let sectionAnchors: [String]
    public let fit: EFTFit
  }

  /// Every EFT block of `page`, numbered from 1 in page order.
  public static func fits(in page: DokuWikiPage) -> [PageFit] {
    var result: [PageFit] = []
    for block in page.codeBlocks {
      guard let fit = EFTFitParser.parse(block.text) else { continue }
      result.append(
        PageFit(
          id: "\(page.pageID)#\(result.count + 1)",
          pageID: page.pageID,
          sectionAnchors: block.sectionAnchors,
          fit: fit
        )
      )
    }
    return result
  }

  /// Every hull and item name of the pages, for the SDE lookup.
  public static func itemNames(in pages: [DokuWikiPage]) -> Set<String> {
    var names: Set<String> = []
    for page in pages {
      for pageFit in fits(in: page) {
        names.insert(pageFit.fit.hullName)
        names.formUnion(pageFit.fit.items.map(\.name))
      }
    }
    return names
  }

  /// Builds the library.
  /// - Doctrines are the pages of the doctrine namespace except its `start`
  ///   overview; a doctrine uses its own fits and those of every ship page
  ///   it links, including optional ships (owner decision 25.11.2026).
  /// - A link with a section anchor uses the fits of that section; the
  ///   anchor also matches with or without a trailing `s`. A section that
  ///   no longer exists yields every fit of the page plus an issue.
  /// - Fits keep the order of first use; a fit linked twice counts once.
  public static func build(
    configuration: DoctrineWikiConfiguration,
    doctrinePages: [DokuWikiPage],
    shipPages: [DokuWikiPage],
    resolutions: [String: ItemTypeNameResolution],
    unreadablePageIDs: [String] = [],
    importedAt: Date
  ) -> DoctrineLibrary {
    var issues: [DoctrineImportIssue] = unreadablePageIDs.map {
      DoctrineImportIssue(kind: .pageUnreadable, pageID: $0, detail: "")
    }
    var unresolvedNames: Set<String> = []
    func item(_ name: String, quantity: Int64, pageID: String) -> DoctrineFitItem {
      switch resolutions[name] {
      case .resolved(let typeID, _, _)?:
        return DoctrineFitItem(name: name, typeID: typeID, quantity: quantity)
      case .ambiguous?:
        if unresolvedNames.insert(name).inserted {
          issues.append(DoctrineImportIssue(kind: .ambiguousItemName, pageID: pageID, detail: name))
        }
      case .unknown?, .localizedNamesUnavailable?, nil:
        if unresolvedNames.insert(name).inserted {
          issues.append(DoctrineImportIssue(kind: .unknownItemName, pageID: pageID, detail: name))
        }
      }
      return DoctrineFitItem(name: name, typeID: nil, quantity: quantity)
    }
    func record(_ pageFit: PageFit) -> DoctrineFitRecord {
      DoctrineFitRecord(
        id: pageFit.id,
        pageID: pageFit.pageID,
        sectionAnchors: pageFit.sectionAnchors,
        hull: item(pageFit.fit.hullName, quantity: 1, pageID: pageFit.pageID),
        fitName: pageFit.fit.fitName,
        items: pageFit.fit.items.map { item($0.name, quantity: $0.quantity, pageID: pageFit.pageID) }
      )
    }

    let shipPagesByID = Dictionary(
      shipPages.map { ($0.pageID, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var fitsByPage: [String: [PageFit]] = [:]
    var allFits: [DoctrineFitRecord] = []
    for page in shipPages.sorted(by: { $0.pageID < $1.pageID }) {
      let pageFits = fits(in: page)
      fitsByPage[page.pageID] = pageFits
      allFits += pageFits.map(record)
    }

    let overviewID = configuration.doctrineNamespace + ":start"
    var doctrines: [DoctrineRecord] = []
    for page in doctrinePages.sorted(by: { $0.pageID < $1.pageID })
    where page.pageID != overviewID {
      var fitIDs: [String] = []
      var used: Set<String> = []
      func use(_ ids: [String]) {
        for id in ids where used.insert(id).inserted { fitIDs.append(id) }
      }
      let ownFits = fits(in: page)
      allFits += ownFits.map(record)
      use(ownFits.map(\.id))
      for link in page.links
      where DokuWikiRawParser.namespace(of: link.pageID) == configuration.shipNamespace {
        guard let target = shipPagesByID[link.pageID] else {
          issues.append(
            DoctrineImportIssue(kind: .linkedPageMissing, pageID: page.pageID, detail: link.pageID)
          )
          continue
        }
        let pageFits = fitsByPage[target.pageID] ?? []
        guard let anchor = link.anchor else {
          use(pageFits.map(\.id))
          continue
        }
        let anchors = Set(target.headings.map(\.anchor))
        let alternative = anchor.hasSuffix("s") ? String(anchor.dropLast()) : anchor + "s"
        if let matched = [anchor, alternative].first(where: anchors.contains) {
          use(pageFits.filter { $0.sectionAnchors.contains(matched) }.map(\.id))
        } else {
          issues.append(
            DoctrineImportIssue(
              kind: .linkedSectionMissing,
              pageID: page.pageID,
              detail: "\(link.pageID)#\(anchor)"
            )
          )
          use(pageFits.map(\.id))
        }
      }
      if fitIDs.isEmpty {
        issues.append(DoctrineImportIssue(kind: .doctrineWithoutFits, pageID: page.pageID, detail: ""))
      }
      let fallbackTitle = page.pageID.split(separator: ":").last.map(String.init) ?? page.pageID
      doctrines.append(
        DoctrineRecord(
          id: page.pageID,
          title: page.title ?? fallbackTitle,
          fitIDs: fitIDs
        )
      )
    }

    var seenIssues: Set<DoctrineImportIssue> = []
    return DoctrineLibrary(
      importedAt: importedAt,
      source: configuration.baseURL.absoluteString,
      doctrines: doctrines,
      fits: allFits,
      issues: issues.filter { seenIssues.insert($0).inserted }
    )
  }
}
