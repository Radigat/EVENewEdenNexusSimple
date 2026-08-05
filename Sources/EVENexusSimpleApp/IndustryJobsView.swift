import EVENexusCore
import Foundation
import SwiftData
import SwiftUI

private struct OwnedIndustryJob: Identifiable {
  let characterID: Int64
  let characterName: String
  let job: ESIIndustryJobDTO

  var id: String { "\(characterID):\(job.jobID)" }
}

private struct IndustryJobTableRow: Identifiable {
  let owned: OwnedIndustryJob
  let primaryItemName: String
  let blueprintName: String
  let facilityName: String
  let activityName: String
  let statusName: String
  let statusRank: Int
  let remainingText: String
  let remainingSortDate: Date

  var id: String { owned.id }
  var characterName: String { owned.characterName }
  var runs: Int { owned.job.runs }
}

private enum IndustryJobStatusFilter: String, CaseIterable, Identifiable {
  case all
  case active
  case ready
  case delivered
  case cancelled

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .all: "All"
    case .active: "Active"
    case .ready: "Ready"
    case .delivered: "Delivered"
    case .cancelled: "Cancelled"
    }
  }
}

private enum IndustryJobActivityFilter: String, CaseIterable, Identifiable {
  case all
  case manufacturing
  case reaction
  case copying
  case invention
  case materialResearch
  case timeResearch

  var id: Self { self }

  var activity: DashboardIndustryActivity? {
    switch self {
    case .all: nil
    case .manufacturing: .manufacturing
    case .reaction: .reaction
    case .copying: .copying
    case .invention: .invention
    case .materialResearch: .materialResearch
    case .timeResearch: .timeResearch
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .all: "All activities"
    case .manufacturing: "Manufacturing"
    case .reaction: "Reaction"
    case .copying: "Copying"
    case .invention: "Invention"
    case .materialResearch: "ME Research"
    case .timeResearch: "TE Research"
    }
  }
}

struct IndustryJobsView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \AppSetting.key)
  private var settings: [AppSetting]

  let onOpenSynchronization: () -> Void

  @State private var statusFilter: IndustryJobStatusFilter = .all
  @State private var activityFilter: IndustryJobActivityFilter = .all
  @State private var showDelivered = false
  @State private var typeNames: [Int64: String] = [:]
  @State private var facilityNames: [Int64: String] = [:]
  @State private var facilityNameState: DataFreshness?
  @State private var sortOrder = [
    KeyPathComparator(\IndustryJobTableRow.remainingSortDate, order: .forward)
  ]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        filters
        sourceNotice
        jobsTable(now: context.date)
      }
      .padding(DesignTokens.spacingLG)
    }
    .background(DesignTokens.canvas)
    .navigationTitle(AppLocalization.text("Industry Jobs"))
    .task(id: typeIdentity) {
      typeNames = await runtime.resolveAssetTypeNames(typeIDs)
    }
    .task(id: facilityIdentity) {
      await resolveFacilityNames()
    }
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
        heading
        Spacer()
        syncButton
      }
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        heading
        syncButton
      }
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Label("Industry Jobs", systemImage: "hammer.fill")
        .font(.largeTitle.bold())
        .foregroundStyle(DesignTokens.highlight)
      Text(
        AppLocalization.format(
          "%lld jobs across %lld characters",
          Int64(jobs.count),
          Int64(jobSnapshots.count)
        )
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var syncButton: some View {
    Button(action: onOpenSynchronization) {
      Label("Synchronize jobs", systemImage: "arrow.triangle.2.circlepath")
    }
    .buttonStyle(.borderedProminent)
    .help("Open character synchronization")
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(alignment: .center, spacing: DesignTokens.spacingMD) {
        Picker("Status", selection: $statusFilter) {
          ForEach(IndustryJobStatusFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 560)

        Toggle("Show delivered", isOn: $showDelivered)
          .disabled(statusFilter == .delivered)
      }

      Picker("Activity", selection: $activityFilter) {
        ForEach(IndustryJobActivityFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 900)
    }
  }

  @ViewBuilder
  private var sourceNotice: some View {
    let incomplete =
      jobSnapshots.filter { $0.1.state != .fresh }.count
      + max(0, characters.count - jobSnapshots.count)
    if characters.isEmpty {
      Label(
        "Connect a character under Data & Settings to load industry jobs.",
        systemImage: "person.crop.circle.badge.plus"
      )
      .foregroundStyle(DesignTokens.textSecondary)
    } else if incomplete > 0 {
      Label(
        "Some job sources are missing, stale, partial or forbidden. Last known jobs remain visible.",
        systemImage: "exclamationmark.triangle"
      )
      .foregroundStyle(DesignTokens.caution)
    } else if facilityNameState == .partial {
      Label(
        "Some station or structure names could not be resolved; their jobs remain visible.",
        systemImage: "mappin.slash"
      )
      .foregroundStyle(DesignTokens.caution)
    }
  }

  private func jobsTable(now: Date) -> some View {
    let rows = sortedTableRows(now: now)
    return Group {
      if rows.isEmpty {
        ContentUnavailableView(
          "No matching industry jobs",
          systemImage: "hammer",
          description: Text(emptyDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(rows, sortOrder: $sortOrder) {
          TableColumn("Character", value: \.characterName) { row in
            EVEEntityText(value: row.characterName, lineLimit: 1)
          }
          .width(min: 120, ideal: 150)

          TableColumn("Blueprint / product", value: \.primaryItemName) { row in
            VStack(alignment: .leading, spacing: 2) {
              EVEEntityText(value: row.primaryItemName, lineLimit: 1)
              if let productTypeID = row.owned.job.productTypeID,
                productTypeID != row.owned.job.blueprintTypeID
              {
                EVEEntityText(
                  value: row.blueprintName,
                  font: .caption,
                  lineLimit: 1
                )
              }
            }
          }
          .width(min: 190, ideal: 280)

          TableColumn("Station / structure", value: \.facilityName) { row in
            EVEEntityText(
              value: row.facilityName,
              lineLimit: 2
            )
          }
          .width(min: 180, ideal: 280)

          TableColumn("Activity", value: \.activityName) { row in
            Label(
              row.activityName,
              systemImage: activityIcon(row.owned.job.dashboardActivity)
            )
            .lineLimit(1)
          }
          .width(min: 120, ideal: 150)

          TableColumn("Runs", value: \.runs) { row in
            Text(row.runs.formatted())
              .monospacedDigit()
          }
          .width(min: 55, ideal: 70)

          TableColumn("Status", value: \.statusRank) { row in
            Text(row.statusName)
              .font(.caption.weight(.semibold))
              .foregroundStyle(statusColor(row.owned.job, now: now))
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(statusColor(row.owned.job, now: now).opacity(0.14))
              .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
          }
          .width(min: 80, ideal: 95)

          TableColumn("Remaining", value: \.remainingSortDate) { row in
            Text(row.remainingText)
              .monospacedDigit()
              .foregroundStyle(DesignTokens.textSecondary)
          }
          .width(min: 100, ideal: 140)
        }
        .alternatingRowBackgrounds(.enabled)
      }
    }
  }

  private var emptyDescription: String {
    if jobSnapshots.isEmpty {
      return AppLocalization.text("Synchronize characters to load industry jobs.")
    }
    return AppLocalization.text("Change the status or activity filters to show other jobs.")
  }

  private func filteredJobs(now: Date) -> [OwnedIndustryJob] {
    jobs.filter { owned in
      let job = owned.job
      let matchesActivity =
        activityFilter.activity == nil
        || job.dashboardActivity == activityFilter.activity
      let matchesStatus: Bool
      switch statusFilter {
      case .all:
        matchesStatus = showDelivered || !job.isDelivered
      case .active:
        matchesStatus = job.isRunning(at: now)
      case .ready:
        matchesStatus = job.isReadyForDelivery(at: now)
      case .delivered:
        matchesStatus = job.isDelivered
      case .cancelled:
        matchesStatus = job.isCancelledOrReverted
      }
      return matchesActivity && matchesStatus
    }
  }

  private func sortedTableRows(now: Date) -> [IndustryJobTableRow] {
    let rows = filteredJobs(now: now).map { owned in
      IndustryJobTableRow(
        owned: owned,
        primaryItemName: primaryItemName(owned.job),
        blueprintName: blueprintName(owned.job),
        facilityName: facilityName(owned.job),
        activityName: activityTitle(owned.job.dashboardActivity),
        statusName: statusTitle(owned.job, now: now),
        statusRank: statusRank(owned.job, now: now),
        remainingText: timeText(owned.job, now: now),
        remainingSortDate: owned.job.completedDate ?? owned.job.endDate
      )
    }
    let activeSortOrder = sortOrder.isEmpty
      ? [KeyPathComparator(\IndustryJobTableRow.remainingSortDate, order: .forward)]
      : sortOrder
    return rows.sorted(
      using: activeSortOrder
        + [KeyPathComparator(\IndustryJobTableRow.id, order: .forward)]
    )
  }

  private var jobSnapshots: [(StoredCharacter, Sourced<[ESIIndustryJobDTO]>)] {
    let values = Dictionary(uniqueKeysWithValues: settings.map { ($0.key, $0.value) })
    return characters.compactMap { character in
      guard
        let encoded = values[AppSettingKey.industryJobs(characterID: character.characterID)],
        let data = Data(base64Encoded: encoded),
        let snapshot = try? JSONDecoder().decode(
          Sourced<[ESIIndustryJobDTO]>.self,
          from: data
        )
      else { return nil }
      return (character, snapshot)
    }
  }

  private var jobs: [OwnedIndustryJob] {
    jobSnapshots.flatMap { character, snapshot in
      (snapshot.value ?? []).map {
        OwnedIndustryJob(
          characterID: character.characterID,
          characterName: character.characterName,
          job: $0
        )
      }
    }
  }

  private var typeIDs: Set<Int64> {
    Set(jobs.flatMap { [$0.job.blueprintTypeID, $0.job.productTypeID].compactMap { $0 } })
  }

  private var typeIdentity: String {
    typeIDs.sorted().map(String.init).joined(separator: ",")
  }

  private var facilityIDs: Set<Int64> {
    Set(
      jobs.flatMap {
        [Optional($0.job.facilityID), $0.job.stationID]
          .compactMap { id in id.flatMap { $0 > 0 ? $0 : nil } }
      }
    )
  }

  private var facilityIdentity: String {
    facilityIDs.sorted().map(String.init).joined(separator: ",")
  }

  private func resolveFacilityNames() async {
    var names = storedFacilityNames
    let resolved = await runtime.resolveAssetLocationNames(facilityIDs)
    for (id, name) in resolved.value ?? [:] where names[id] == nil {
      names[id] = name
    }
    facilityNames = names
    facilityNameState = names.count == facilityIDs.count ? .fresh : .partial
  }

  private var storedFacilityNames: [Int64: String] {
    var names: [Int64: String] = [:]
    for structure in runtime.productionBasis.structures {
      if let id = structure.structureID {
        names[id] = structure.eveStructureName ?? structure.name
      }
    }
    for character in characters {
      for data in [character.assetSnapshot, character.corporationAssetSnapshot].compactMap({ $0 }) {
        guard
          let snapshot = try? JSONDecoder().decode(
            Sourced<AssetSnapshot>.self,
            from: data
          )
        else { continue }
        for (id, name) in snapshot.value?.resolvedLocationNames ?? [:] {
          names[id] = name
        }
      }
    }
    return names
  }

  private func primaryItemName(_ job: ESIIndustryJobDTO) -> String {
    if let productTypeID = job.productTypeID,
      let name = typeNames[productTypeID]
    {
      return name
    }
    return blueprintName(job)
  }

  private func blueprintName(_ job: ESIIndustryJobDTO) -> String {
    typeNames[job.blueprintTypeID]
      ?? AppLocalization.format("Blueprint #%lld", job.blueprintTypeID)
  }

  private func facilityName(_ job: ESIIndustryJobDTO) -> String {
    if let name = job.facilityName { return name }
    if let name = facilityNames[job.facilityID] { return name }
    if let stationID = job.stationID, let name = facilityNames[stationID] {
      return name
    }
    return AppLocalization.text("Unresolved station or structure")
  }

  private func activityTitle(_ activity: DashboardIndustryActivity?) -> String {
    switch activity {
    case .manufacturing: AppLocalization.text("Manufacturing")
    case .reaction: AppLocalization.text("Reaction")
    case .copying: AppLocalization.text("Copying")
    case .invention: AppLocalization.text("Invention")
    case .materialResearch: AppLocalization.text("ME Research")
    case .timeResearch: AppLocalization.text("TE Research")
    case nil: AppLocalization.text("Unknown activity")
    }
  }

  private func activityIcon(_ activity: DashboardIndustryActivity?) -> String {
    switch activity {
    case .manufacturing: "hammer.fill"
    case .reaction: "atom"
    case .copying: "doc.on.doc"
    case .invention: "lightbulb.fill"
    case .materialResearch: "percent"
    case .timeResearch: "clock.arrow.circlepath"
    case nil: "questionmark.circle"
    }
  }

  private func statusTitle(_ job: ESIIndustryJobDTO, now: Date) -> String {
    if job.isReadyForDelivery(at: now) { return AppLocalization.text("Ready") }
    if job.isRunning(at: now) {
      return job.status.caseInsensitiveCompare("paused") == .orderedSame
        ? AppLocalization.text("Paused") : AppLocalization.text("Active")
    }
    if job.isDelivered { return AppLocalization.text("Delivered") }
    if job.isCancelledOrReverted { return AppLocalization.text("Cancelled") }
    return job.status.capitalized
  }

  private func statusColor(_ job: ESIIndustryJobDTO, now: Date) -> Color {
    if job.isReadyForDelivery(at: now) { return DesignTokens.highlight }
    if job.isRunning(at: now) { return DesignTokens.positive }
    if job.isDelivered { return DesignTokens.textSecondary }
    if job.isCancelledOrReverted { return DesignTokens.negative }
    return DesignTokens.caution
  }

  private func statusRank(_ job: ESIIndustryJobDTO, now: Date) -> Int {
    if job.isRunning(at: now) {
      return job.status.caseInsensitiveCompare("paused") == .orderedSame ? 1 : 0
    }
    if job.isReadyForDelivery(at: now) { return 2 }
    if job.isDelivered { return 3 }
    if job.isCancelledOrReverted { return 4 }
    return 5
  }

  private func timeText(_ job: ESIIndustryJobDTO, now: Date) -> String {
    if job.isRunning(at: now) {
      return job.endDate.formatted(.relative(presentation: .named))
    }
    if job.isReadyForDelivery(at: now) { return AppLocalization.text("Ready") }
    if let completedDate = job.completedDate {
      return completedDate.formatted(date: .abbreviated, time: .shortened)
    }
    return job.endDate.formatted(date: .abbreviated, time: .shortened)
  }
}
