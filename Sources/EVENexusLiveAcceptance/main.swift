import Darwin
import EVENexusCore
import Foundation

@main
enum EVENexusLiveAcceptance {
  static func main() async {
    do {
      guard let command = CommandLine.arguments.dropFirst().first else {
        throw LiveAcceptanceError.usage
      }
      if command == "facility-reference" {
        try await verifyFacilityReference()
        return
      }
      if command == "system-security" {
        guard CommandLine.arguments.count >= 3 else {
          throw LiveAcceptanceError.usage
        }
        try await verifySystemSecurity(
          query: CommandLine.arguments.dropFirst(2).joined(separator: " ")
        )
        return
      }
      guard command == "sde" else { throw LiveAcceptanceError.usage }
      guard
        let contact = ProcessInfo.processInfo.environment[
          "EVE_SDE_OWNER_CONTACT"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !contact.isEmpty
      else {
        throw LiveAcceptanceError.missingOwnerContact
      }
      let applicationSupport = applicationSupportRoot()
      let root =
        applicationSupport
        .appendingPathComponent(
          "com.local.EVENexusSimple",
          isDirectory: true
        )
        .appendingPathComponent("sde", isDirectory: true)
      let lifecycle = try SDELifecycleService(
        rootURL: root,
        ownerContact: contact
      )
      let recovered = try await lifecycle.recoverInterruptedInstallations()
      print("recovered_operations=\(recovered)")
      let preview = try await lifecycle.check()
      print("official_build=\(preview.officialBuild)")
      print("active_build_before=\(preview.activeBuild.map(String.init) ?? "none")")
      print("schema_entries=\(preview.schemaEntryCount)")
      if !preview.requiresUpdate,
        let active = try await lifecycle.activeVersion()
      {
        print("result=already-current")
        print("active_build=\(active.0)")
        return
      }
      let result = try await lifecycle.installConfirmed(
        preview: preview,
        schemaReviewConfirmed: true
      ) { phase in
        print("phase=\(phase.rawValue)")
      }
      print("result=activated")
      print("active_build=\(result.buildNumber)")
      print("content_sha256=\(result.contentSHA256)")
      print("backup_created=\(result.backupCreated)")
      print("categories=\(result.counts.categories)")
      print("groups=\(result.counts.groups)")
      print("types=\(result.counts.itemTypes)")
      print("blueprints=\(result.counts.blueprints)")
      print("activities=\(result.counts.activities)")
      print("materials=\(result.counts.materials)")
      print("products=\(result.counts.products)")
      print(
        "unresolved_type_references=\(result.counts.unresolvedTypeReferences)"
      )
    } catch let error as LiveAcceptanceError {
      FileHandle.standardError.write(
        Data("live_acceptance_error=\(error.rawValue)\n".utf8)
      )
      exit(EXIT_FAILURE)
    } catch {
      FileHandle.standardError.write(
        Data("live_acceptance_error=\(safeCode(for: error))\n".utf8)
      )
      exit(EXIT_FAILURE)
    }
  }

  private static func verifyFacilityReference() async throws {
    let applicationSupport = applicationSupportRoot()
    let root =
      applicationSupport
      .appendingPathComponent(
        "com.local.EVENexusSimple",
        isDirectory: true
      )
      .appendingPathComponent("sde", isDirectory: true)
    let catalog = SQLiteStaticCatalog(
      rootURL: root.appendingPathComponent(
        "catalog-store",
        isDirectory: true
      )
    )
    let reference = try await catalog.industryFacilityReferences()
    print("result=facility-reference-readable")
    print("sde_build=\(reference.source.version)")
    if let arkTypeID = try await catalog.typeID(named: "Ark"),
      let arkVolume = try await catalog.packagedVolume(typeID: arkTypeID)
    {
      print("ark_packaged_volume=\(arkVolume)")
    }
    print("structure_definitions=\(reference.structures.count)")
    print("service_modules=\(reference.serviceModules.count)")
    print("compatible_rigs=\(reference.rigs.count)")
    if let researchLab = reference.serviceModules.first(where: {
      $0.typeID == 35_891
    }) {
      print(
        "research_lab_activities="
          + researchLab.activities.map(\.rawValue).joined(separator: ",")
      )
    }
    if let reprocessingFacility = reference.serviceModules.first(where: {
      $0.typeID == 35_899
    }) {
      print(
        "reprocessing_ore_yield="
          + String(reprocessingFacility.normalOreYieldMultiplier ?? 0)
      )
      print(
        "reprocessing_gas_yield="
          + String(reprocessingFacility.gasYieldMultiplier ?? 0)
      )
    }
    if let raitaru = reference.structures.first(where: {
      $0.typeID == 35_825
    }) {
      print("raitaru_rig_size=\(raitaru.size.displayName)")
      print(
        "raitaru_me=\(raitaru.manufacturingMaterialBonusPercent)"
      )
      print("raitaru_te=\(raitaru.manufacturingTimeBonusPercent)")
    }
  }

  private static func verifySystemSecurity(query: String) async throws {
    let service = SolarSystemSearchService(esi: ESIClient())
    let matches = try await service.search(query: query)
    guard
      let system = matches.first(where: {
        $0.name.caseInsensitiveCompare(query) == .orderedSame
      }) ?? matches.first
    else {
      throw LiveAcceptanceError.systemNotFound
    }
    let details = try await service.details(systemID: system.id)
    let band = SecurityBand.resolved(
      solarSystemID: details.id,
      securityStatus: details.securityStatus,
      regionID: details.regionID
    )
    print("result=system-security-resolved")
    print("system_name=\(details.name)")
    print("system_id=\(details.id)")
    print("region_name=\(details.regionName)")
    print("region_id=\(details.regionID)")
    print("security_status=\(details.securityStatus)")
    print("security_band=\(band.rawValue)")
  }

  private static func safeCode(for error: Error) -> String {
    if let error = error as? StaticCatalogError {
      return "static-catalog-\(String(describing: error))"
    }
    return String(reflecting: type(of: error))
  }

  private static func applicationSupportRoot() -> URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support",
        isDirectory: true
      )
  }
}

private enum LiveAcceptanceError: String, Error {
  case usage =
    "usage: EVENexusLiveAcceptance sde|facility-reference|system-security <name>"
  case missingOwnerContact = "owner-contact-missing"
  case systemNotFound = "system-not-found"
}
