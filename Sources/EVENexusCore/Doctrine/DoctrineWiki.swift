import Foundation

// Doctrine stock (DOKTRIN_BEDARF_PLAN.md): parsing of the alliance wiki's
// DokuWiki raw pages and of the EFT fits embedded in them. Everything here
// is pure and deterministic; fetching and name resolution live elsewhere.

// MARK: EFT

/// One item line of an EFT fit, merged by name in order of first appearance.
public struct EFTFitItemLine: Codable, Equatable, Sendable {
  public let name: String
  public let quantity: Int64

  public init(name: String, quantity: Int64) {
    self.name = name
    self.quantity = quantity
  }
}

/// A fit in the EFT text format: `[Hull, Fit name]`, then modules, drones,
/// charges and cargo. The hull itself is not part of `items`.
public struct EFTFit: Equatable, Sendable {
  public let hullName: String
  public let fitName: String
  public let items: [EFTFitItemLine]

  public init(hullName: String, fitName: String, items: [EFTFitItemLine]) {
    self.hullName = hullName
    self.fitName = fitName
    self.items = items
  }
}

public enum EFTFitParser {
  public static let maximumQuantity: Int64 = 1_000_000_000

  /// Whether `text` starts with an EFT header line `[Hull, Fit name]`.
  public static func looksLikeFit(_ text: String) -> Bool {
    guard let first = firstNonEmptyLine(text) else { return false }
    return header(first) != nil
  }

  /// Parses one EFT block. Rules:
  /// - the first non-empty line is `[Hull, Fit name]`; the hull ends at the
  ///   first comma, so fit names may contain brackets (`[DOC] Ferox`);
  /// - `[Empty … slot]` lines are skipped;
  /// - a trailing `/offline` is ignored;
  /// - `Name xN` carries a quantity, every other line counts once;
  /// - `Module, Charge` is a module with its loaded charge; EFT does not
  ///   state the loaded amount, so the charge counts once per module line.
  /// Returns nil without a valid header.
  public static func parse(_ text: String) -> EFTFit? {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard let headerIndex = lines.firstIndex(where: { !$0.isEmpty }),
      let (hull, fitName) = header(lines[headerIndex])
    else { return nil }
    var order: [String] = []
    var quantities: [String: Int64] = [:]
    func add(_ name: String, _ quantity: Int64) {
      let accepted = name.trimmingCharacters(in: .whitespaces)
      guard !accepted.isEmpty, quantity > 0 else { return }
      if quantities[accepted] == nil { order.append(accepted) }
      quantities[accepted] = min(maximumQuantity, (quantities[accepted] ?? 0) + quantity)
    }
    for raw in lines[(headerIndex + 1)...] {
      var line = raw
      guard !line.isEmpty else { continue }
      if line.hasPrefix("["), line.hasSuffix("]") { continue }
      line = strippingOfflineSuffix(line)
      if let (name, quantity) = quantityLine(line) {
        add(name, quantity)
      } else if let comma = line.range(of: ",") {
        add(String(line[..<comma.lowerBound]), 1)
        add(String(line[comma.upperBound...]), 1)
      } else {
        add(line, 1)
      }
    }
    return EFTFit(
      hullName: hull,
      fitName: fitName,
      items: order.map { EFTFitItemLine(name: $0, quantity: quantities[$0] ?? 0) }
    )
  }

  static func header(_ line: String) -> (String, String)? {
    guard line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 else { return nil }
    let inner = line.dropFirst().dropLast()
    guard let comma = inner.firstIndex(of: ",") else { return nil }
    let hull = inner[..<comma].trimmingCharacters(in: .whitespaces)
    let name = inner[inner.index(after: comma)...].trimmingCharacters(in: .whitespaces)
    guard !hull.isEmpty, !hull.contains("["), !hull.contains("]") else { return nil }
    return (hull, name)
  }

  private static func firstNonEmptyLine(_ text: String) -> String? {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty }
  }

  private static func strippingOfflineSuffix(_ line: String) -> String {
    guard let range = line.range(of: "/offline", options: [.caseInsensitive, .backwards]),
      range.upperBound == line.endIndex
    else { return line }
    return line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
  }

  /// `Name xN` with N ≥ 1; nil for other lines.
  private static func quantityLine(_ line: String) -> (String, Int64)? {
    guard let space = line.lastIndex(of: " ") else { return nil }
    let token = line[line.index(after: space)...]
    guard token.count >= 2, token.first == "x" || token.first == "X" else { return nil }
    let digits = token.dropFirst()
    guard digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
      let quantity = Int64(digits), quantity > 0
    else { return nil }
    let name = line[..<space].trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }
    return (name, min(quantity, maximumQuantity))
  }
}

// MARK: DokuWiki

/// A section heading of a DokuWiki page with the anchor DokuWiki renders.
public struct DokuWikiHeading: Equatable, Sendable {
  /// 1 for `======`, 5 for `==`.
  public let level: Int
  public let title: String
  public let anchor: String
}

/// A `<code>` block with the anchors of the sections that enclose it, from
/// the outermost to the innermost heading.
public struct DokuWikiCodeBlock: Equatable, Sendable {
  public let text: String
  public let sectionAnchors: [String]
}

/// An internal link `[[target#anchor|text]]`, resolved to a page ID.
public struct DokuWikiLink: Equatable, Sendable {
  public let pageID: String
  public let anchor: String?
  /// Titles of the enclosing sections, outermost first.
  public let sectionTitles: [String]
}

public struct DokuWikiPage: Equatable, Sendable {
  public let pageID: String
  /// The first level-1 heading.
  public let title: String?
  public let headings: [DokuWikiHeading]
  public let codeBlocks: [DokuWikiCodeBlock]
  public let links: [DokuWikiLink]
}

/// Parser for DokuWiki raw markup (`?do=export_raw`). It knows headings,
/// `<code>`/`<file>` blocks and internal links, which is all the doctrine
/// import needs.
public enum DokuWikiRawParser {
  public static func parse(_ raw: String, pageID: String) -> DokuWikiPage {
    let namespace = namespace(of: pageID)
    var headings: [DokuWikiHeading] = []
    var usedAnchors: [String] = []
    var anchorPath: [String?] = []
    var titlePath: [String?] = []
    var codeBlocks: [DokuWikiCodeBlock] = []
    var links: [DokuWikiLink] = []
    var codeLines: [String]?
    var codeEndTag = ""

    let source = strippingComments(raw)
    for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      var line = String(rawLine)
      if codeLines != nil {
        if let end = line.range(of: codeEndTag) {
          codeLines?.append(String(line[..<end.lowerBound]))
          codeBlocks.append(
            DokuWikiCodeBlock(
              text: (codeLines ?? []).joined(separator: "\n"),
              sectionAnchors: anchorPath.compactMap { $0 }
            )
          )
          codeLines = nil
          line = String(line[end.upperBound...])
        } else {
          codeLines?.append(line)
          continue
        }
      }
      if let heading = heading(line) {
        let anchor = sectionID(heading.title, existing: &usedAnchors)
        headings.append(DokuWikiHeading(level: heading.level, title: heading.title, anchor: anchor))
        anchorPath = Array(anchorPath.prefix(heading.level - 1))
        titlePath = Array(titlePath.prefix(heading.level - 1))
        while anchorPath.count < heading.level - 1 {
          anchorPath.append(nil)
          titlePath.append(nil)
        }
        anchorPath.append(anchor)
        titlePath.append(heading.title)
        continue
      }
      // Links before an opening code tag on the same line.
      var linkText = line
      if let open = openingCodeTag(in: line) {
        linkText = String(line[..<open.range.lowerBound])
        let rest = String(line[open.range.upperBound...])
        if let end = rest.range(of: open.endTag) {
          codeBlocks.append(
            DokuWikiCodeBlock(
              text: String(rest[..<end.lowerBound]),
              sectionAnchors: anchorPath.compactMap { $0 }
            )
          )
          linkText += " " + rest[end.upperBound...]
        } else {
          codeLines = [rest]
          codeEndTag = open.endTag
        }
      }
      for link in internalLinks(in: linkText, namespace: namespace) {
        links.append(
          DokuWikiLink(
            pageID: link.pageID,
            anchor: link.anchor,
            sectionTitles: titlePath.compactMap { $0 }
          )
        )
      }
    }
    return DokuWikiPage(
      pageID: pageID,
      title: headings.first { $0.level == 1 }?.title,
      headings: headings,
      codeBlocks: codeBlocks,
      links: links
    )
  }

  /// DokuWiki's `cleanID` with the wiki's settings (`sepchar` `_`,
  /// `useslash` and `deaccent` on): lower case, accents removed, `/` and
  /// `;` separate namespaces like `:`, every other character except
  /// letters, digits, `.` and `-` becomes `_`, repeated `_` collapse,
  /// `:._-` are trimmed at both ends and next to every `:`. Checked against
  /// the rendered heading IDs of the wiki on 25.11.2026.
  public static func cleanID(_ raw: String) -> String {
    let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "/", with: ":")
      .replacingOccurrences(of: ";", with: ":")
    var result = ""
    var lastWasSeparator = false
    for scalar in folded.unicodeScalars {
      let keep =
        CharacterSet.alphanumerics.contains(scalar)
        || scalar == "." || scalar == "-" || scalar == ":"
      if keep {
        result.unicodeScalars.append(scalar)
        lastWasSeparator = false
      } else if !lastWasSeparator {
        result.append("_")
        lastWasSeparator = true
      }
    }
    while result.contains("::") {
      result = result.replacingOccurrences(of: "::", with: ":")
    }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: ":._-"))
    result = result.replacingOccurrences(
      of: #":[:._\-]+"#, with: ":", options: .regularExpression)
    return result.replacingOccurrences(
      of: #"[:._\-]+:"#, with: ":", options: .regularExpression)
  }

  /// DokuWiki's `sectionID`: `cleanID` without `:` and `.`, leading digits,
  /// `_` and `-` removed (`section` plus the digits when nothing is left),
  /// and a numeric suffix for a repeated anchor on the same page.
  public static func sectionID(_ title: String, existing: inout [String]) -> String {
    let base = sectionID(title)
    var candidate = base
    var suffix = 0
    while existing.contains(candidate) {
      suffix += 1
      candidate = base + String(suffix)
    }
    existing.append(candidate)
    return candidate
  }

  /// `sectionID` without the duplicate check, as DokuWiki applies it to the
  /// anchor of a link.
  public static func sectionID(_ title: String) -> String {
    let cleaned = cleanID(title).replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: ".", with: "")
    let trimmed = cleaned.drop { "0123456789_-".contains($0) }
    if trimmed.isEmpty {
      return "section" + cleaned.filter(\.isNumber)
    }
    return String(trimmed)
  }

  /// Resolves a link target the way DokuWiki does with `useslash` on: `/`
  /// separates namespaces, a leading `:` or `/` is absolute, a target with
  /// a namespace separator is absolute, a plain name and `.`/`..` prefixes
  /// are relative to `namespace`.
  public static func resolvePageID(_ target: String, namespace: String) -> String? {
    let trimmed = target.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.lowercased().hasPrefix("mailto:"),
      !trimmed.hasPrefix("\\\\")
    else { return nil }
    var value = trimmed.replacingOccurrences(of: "/", with: ":")
    var base = namespace.split(separator: ":").map(String.init)
    if value.hasPrefix(":") {
      base = []
      value = String(value.drop { $0 == ":" })
    } else if value.hasPrefix(".") {
      while value.hasPrefix("..:") || value.hasPrefix(".:") {
        if value.hasPrefix("..:") {
          if !base.isEmpty { base.removeLast() }
          value.removeFirst(3)
        } else {
          value.removeFirst(2)
        }
      }
    } else if value.contains(":") {
      base = []
    }
    let parts = (base + value.split(separator: ":").map(String.init))
      .map(cleanID)
      .filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: ":")
  }

  /// Removes `/* … */` comments (the wiki's comment plugin), which the wiki
  /// does not render: their headings get no anchor and their code blocks
  /// are no fits. Code and file blocks keep their content unchanged; an
  /// unclosed comment runs to the end of the page.
  static func strippingComments(_ raw: String) -> String {
    guard raw.contains("/*") else { return raw }
    var result = ""
    var index = raw.startIndex
    while index < raw.endIndex {
      let comment = raw.range(of: "/*", range: index..<raw.endIndex)
      let code = openingCodeTag(in: raw, range: index..<raw.endIndex)
      if let code, comment.map({ code.range.lowerBound < $0.lowerBound }) ?? true {
        // Copy the code block verbatim up to and including its end tag.
        let end =
          raw.range(of: code.endTag, range: code.range.upperBound..<raw.endIndex)?.upperBound
          ?? raw.endIndex
        result += raw[index..<end]
        index = end
      } else if let comment {
        result += raw[index..<comment.lowerBound]
        guard let close = raw.range(of: "*/", range: comment.upperBound..<raw.endIndex) else {
          break
        }
        index = close.upperBound
      } else {
        result += raw[index...]
        break
      }
    }
    return result
  }

  static func namespace(of pageID: String) -> String {
    guard let colon = pageID.lastIndex(of: ":") else { return "" }
    return String(pageID[..<colon])
  }

  private static func heading(_ line: String) -> (level: Int, title: String)? {
    let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard trimmed.hasPrefix("=="), trimmed.hasSuffix("==") else { return nil }
    let opening = trimmed.prefix { $0 == "=" }.count
    let closing = trimmed.reversed().prefix { $0 == "=" }.count
    guard opening + closing < trimmed.count else { return nil }
    let title = trimmed.dropFirst(opening).dropLast(closing)
      .trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return nil }
    return (7 - min(6, opening), title)
  }

  private static func openingCodeTag(in line: String) -> (range: Range<String.Index>, endTag: String)? {
    openingCodeTag(in: line, range: line.startIndex..<line.endIndex)
  }

  /// First `<code>`/`<file>` opening tag (also with attributes) in `range`.
  private static func openingCodeTag(
    in line: String,
    range: Range<String.Index>
  ) -> (range: Range<String.Index>, endTag: String)? {
    var best: (range: Range<String.Index>, endTag: String)?
    for tag in ["code", "file"] {
      var searchStart = range.lowerBound
      while let start = line.range(of: "<\(tag)", range: searchStart..<range.upperBound) {
        let afterName = start.upperBound
        guard afterName < range.upperBound,
          line[afterName] == ">" || line[afterName] == " "
        else {
          searchStart = afterName
          continue
        }
        guard let close = line[afterName..<range.upperBound].firstIndex(of: ">") else { break }
        let range = start.lowerBound..<line.index(after: close)
        if best == nil || range.lowerBound < best!.range.lowerBound {
          best = (range, "</\(tag)>")
        }
        break
      }
    }
    return best
  }

  private static func internalLinks(
    in line: String,
    namespace: String
  ) -> [(pageID: String, anchor: String?)] {
    var result: [(String, String?)] = []
    var searchStart = line.startIndex
    while let open = line.range(of: "[[", range: searchStart..<line.endIndex),
      let close = line.range(of: "]]", range: open.upperBound..<line.endIndex)
    {
      searchStart = close.upperBound
      var target = String(line[open.upperBound..<close.lowerBound])
      if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
      var anchor: String?
      if let hash = target.firstIndex(of: "#") {
        let rawAnchor = target[target.index(after: hash)...].trimmingCharacters(in: .whitespaces)
        anchor = rawAnchor.isEmpty ? nil : sectionID(rawAnchor)
        target = String(target[..<hash])
      }
      guard let pageID = resolvePageID(target, namespace: namespace) else { continue }
      result.append((pageID, anchor))
    }
    return result
  }
}

/// Page IDs of one namespace from a DokuWiki index page (`?idx=<ns>`): the
/// `title` attributes of its links to existing pages (`class="wikilink1"`);
/// namespace entries (`idx_dir`) and deeper pages do not count.
public enum DokuWikiIndexParser {
  public static func pageIDs(inNamespace namespace: String, html: String) -> [String] {
    let prefix = namespace + ":"
    var result: [String] = []
    var seen: Set<String> = []
    var searchStart = html.startIndex
    while let open = html.range(of: "<a ", range: searchStart..<html.endIndex),
      let close = html[open.upperBound...].firstIndex(of: ">")
    {
      searchStart = close
      let tag = html[open.upperBound..<close]
      guard tag.contains("wikilink1"),
        let attribute = tag.range(of: "title=\""),
        let end = tag[attribute.upperBound...].firstIndex(of: "\"")
      else { continue }
      let value = String(tag[attribute.upperBound..<end])
      guard value.hasPrefix(prefix) else { continue }
      let name = value.dropFirst(prefix.count)
      guard !name.isEmpty, !name.contains(":"), value == DokuWikiRawParser.cleanID(value)
      else { continue }
      if seen.insert(value).inserted { result.append(value) }
    }
    return result
  }
}
