import Combine
import EVENexusCore
import SwiftData
import SwiftUI

enum NavigationSection: String, CaseIterable, Identifiable {
  case planner
  case assets
  case blueprints
  case productionBook
  case profiles
  case characters
  case wallet
  case data

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .planner: "Planner"
    case .assets: "Assets & Warehouse"
    case .blueprints: "Blueprints"
    case .productionBook: "Production Overview"
    case .profiles: "Profile"
    case .characters: "Characters"
    case .wallet: "Wallet"
    case .data: "Data & Settings"
    }
  }

  var icon: String {
    switch self {
    case .planner: "hammer.fill"
    case .assets: "shippingbox.fill"
    case .blueprints: "doc.on.doc.fill"
    case .productionBook: "books.vertical.fill"
    case .profiles: "slider.horizontal.3"
    case .characters: "person.2.fill"
    case .wallet: "creditcard.fill"
    case .data: "externaldrive.fill"
    }
  }
}

struct ContentView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @AppStorage(AppLanguage.storageKey)
  private var storedLanguage = AppLanguage.defaultLanguage.rawValue
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @State private var selection: NavigationSection? = .planner
  @State private var didPreparePlannerConfiguration = false
  @StateObject private var profileNavigationGuard =
    ProfileNavigationGuard()

  var body: some View {
    NavigationSplitView {
      List(NavigationSection.allCases, selection: guardedSelection) { item in
        Label(item.title, systemImage: item.icon)
          .tag(item)
          .accessibilityIdentifier("navigation.\(item.rawValue)")
      }
      .navigationSplitViewColumnWidth(
        min: DesignTokens.sidebarMinimum,
        ideal: DesignTokens.sidebarIdeal
      )
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text("EVE NEXUS SIMPLE")
            .font(.caption.bold())
          Text("Local • Jita • \(EVEConstants.esiCompatibilityDate)")
            .font(.caption2.monospaced())
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.spacingMD)
      }
    } detail: {
      VStack(spacing: 0) {
        EVEOnlineServiceBanner()
        Group {
          switch selection ?? .planner {
          case .planner:
            PlannerView()
          case .assets:
            AssetsWarehouseView()
          case .blueprints:
            BlueprintsView()
          case .productionBook:
            ProductionBookView()
          case .profiles:
            ProfilesView()
          case .characters:
            CharactersView()
          case .wallet:
            WalletView()
          case .data:
            DataSettingsView()
          }
        }
        .background(DesignTokens.canvas)
        .tint(DesignTokens.accent)
      }
      .id(storedLanguage)
    }
    .environmentObject(profileNavigationGuard)
    .task {
      guard !didPreparePlannerConfiguration else { return }
      didPreparePlannerConfiguration = true
      await runtime.preparePlannerConfiguration(
        encodedBasis: storedBases.first?.encodedBasis
      )
    }
    .task {
      while !Task.isCancelled {
        await runtime.refreshEVEOnlineServiceStatus()
        do {
          try await Task.sleep(for: .seconds(300))
        } catch {
          break
        }
      }
    }
    .confirmationDialog(
      "Unsaved profile changes",
      isPresented: $profileNavigationGuard.isPresentingWarning,
      titleVisibility: .visible
    ) {
      Button("Save and Continue") {
        profileNavigationGuard.requestSaveAndContinue()
      }
      Button("Discard Changes", role: .destructive) {
        profileNavigationGuard.requestDiscardAndContinue()
      }
      Button("Cancel", role: .cancel) {
        profileNavigationGuard.cancelNavigation()
      }
    } message: {
      Text(
        "Your Profile changes have not been saved. Save them before leaving this page so your configuration is not lost."
      )
    }
  }

  private var guardedSelection: Binding<NavigationSection?> {
    Binding(
      get: { selection },
      set: { destination in
        guard let destination else { return }
        guard selection != destination else { return }
        if selection == .profiles {
          profileNavigationGuard.attemptNavigation {
            selection = destination
          }
        } else {
          selection = destination
        }
      }
    )
  }
}

private struct EVEOnlineServiceBanner: View {
  @EnvironmentObject private var runtime: RuntimeState

  private struct Notice {
    let title: String
    let message: String
    let systemImage: String
    let color: Color
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      if let notice = notice(at: context.date) {
        HStack(alignment: .top, spacing: DesignTokens.spacingSM) {
          Image(systemName: notice.systemImage)
            .foregroundStyle(notice.color)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(AppLocalization.text(notice.title))
              .font(.subheadline.bold())
            Text(AppLocalization.text(notice.message))
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer(minLength: DesignTokens.spacingSM)
          Link(
            AppLocalization.text("Open CCP status"),
            destination: URL(string: "https://status.eveonline.com/")!
          )
          .font(.caption)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.color.opacity(0.12))
        .overlay(alignment: .bottom) {
          Divider()
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func notice(at date: Date) -> Notice? {
    let status = recentStatus(at: date)
    if status?.hasLoginIssue == true && status?.hasESIIssue == true {
      return Notice(
        title: "EVE services affected",
        message:
          "CCP currently reports problems with both EVE Login (SSO) and ESI. Authorization and data synchronization can fail; locally stored data remains available.",
        systemImage: "network.slash",
        color: DesignTokens.negative
      )
    }
    if status?.hasLoginIssue == true {
      return Notice(
        title: "EVE SSO affected",
        message:
          "CCP currently reports a problem with EVE Login (SSO). New authorization or token renewal can fail; this is separate from an ESI data error.",
        systemImage: "person.crop.circle.badge.exclamationmark",
        color: DesignTokens.negative
      )
    }
    if status?.hasESIIssue == true {
      return Notice(
        title: "EVE ESI affected",
        message:
          "CCP currently reports a problem with ESI. SSO can still work while character, asset, blueprint, market or wallet data cannot be refreshed.",
        systemImage: "arrow.triangle.2.circlepath.circle.fill",
        color: DesignTokens.negative
      )
    }
    if status?.isGameServerUnderMaintenance == true {
      let confirmsLoginAndESI =
        status?.login == .operational && status?.esi == .operational
      return Notice(
        title: "EVE downtime",
        message:
          confirmsLoginAndESI
          ? "Tranquility is in maintenance. CCP currently reports Login (SSO) and ESI as operational, but data synchronization can still be slow or incomplete. Wait a few minutes and try again."
          : "Tranquility is in maintenance. Authorization and data synchronization may be temporarily delayed. Wait a few minutes and try again.",
        systemImage: "wrench.and.screwdriver.fill",
        color: DesignTokens.caution
      )
    }
    if EVEOnlineDailyDowntime.isExpected(at: date) {
      return Notice(
        title: "Expected EVE downtime",
        message:
          "The daily Tranquility restart begins at 11:00 UTC and usually lasts only a few minutes. SSO and ESI are separate services, but synchronization can still be temporarily slow or incomplete.",
        systemImage: "clock.badge.exclamationmark.fill",
        color: DesignTokens.caution
      )
    }
    if status?.hasGameServerIssue == true {
      return Notice(
        title: "EVE game server affected",
        message:
          "CCP currently reports a Tranquility problem. Login and ESI have separate status, so the app keeps their errors distinct.",
        systemImage: "exclamationmark.triangle.fill",
        color: DesignTokens.caution
      )
    }
    return nil
  }

  private func recentStatus(
    at date: Date
  ) -> EVEOnlineServiceStatusSnapshot? {
    guard let status = runtime.eveOnlineServiceStatus,
      abs(date.timeIntervalSince(status.fetchedAt)) < 15 * 60
    else {
      return nil
    }
    return status
  }
}

@MainActor
final class ProfileNavigationGuard: ObservableObject {
  @Published var hasUnsavedChanges = false
  @Published var isPresentingWarning = false
  @Published private(set) var saveRequestID = 0
  @Published private(set) var discardRequestID = 0

  private var pendingNavigation: (@MainActor () -> Void)?

  func attemptNavigation(
    _ navigation: @escaping @MainActor () -> Void
  ) {
    guard hasUnsavedChanges else {
      navigation()
      return
    }
    pendingNavigation = navigation
    isPresentingWarning = true
  }

  func updateDirtyState(_ isDirty: Bool) {
    hasUnsavedChanges = isDirty
  }

  func requestSaveAndContinue() {
    isPresentingWarning = false
    saveRequestID += 1
  }

  func requestDiscardAndContinue() {
    isPresentingWarning = false
    discardRequestID += 1
  }

  func completeSave(success: Bool) {
    guard success else {
      pendingNavigation = nil
      return
    }
    completePendingNavigation()
  }

  func completeDiscard() {
    completePendingNavigation()
  }

  func cancelNavigation() {
    isPresentingWarning = false
    pendingNavigation = nil
  }

  private func completePendingNavigation() {
    hasUnsavedChanges = false
    let navigation = pendingNavigation
    pendingNavigation = nil
    navigation?()
  }
}

enum DesignTokens {
  static let canvas = Color(red: 11 / 255, green: 15 / 255, blue: 26 / 255)
  static let panel = Color(red: 19 / 255, green: 26 / 255, blue: 42 / 255)
  static let elevated = Color(red: 27 / 255, green: 36 / 255, blue: 56 / 255)
  static let border = Color(red: 38 / 255, green: 49 / 255, blue: 73 / 255)
  static let textPrimary = Color(
    red: 230 / 255, green: 236 / 255, blue: 245 / 255
  )
  static let textSecondary = Color(
    red: 139 / 255, green: 150 / 255, blue: 171 / 255
  )
  static let textDisabled = Color(
    red: 85 / 255, green: 96 / 255, blue: 122 / 255
  )
  static let accent = Color(red: 53 / 255, green: 199 / 255, blue: 232 / 255)
  static let accentSoft = accent.opacity(0.2)
  static let highlight = Color(
    red: 245 / 255, green: 185 / 255, blue: 66 / 255
  )
  static let positive = Color(
    red: 61 / 255, green: 220 / 255, blue: 151 / 255
  )
  static let caution = Color(
    red: 245 / 255, green: 166 / 255, blue: 35 / 255
  )
  static let negative = Color(
    red: 240 / 255, green: 84 / 255, blue: 79 / 255
  )
  static let information = Color(
    red: 122 / 255, green: 140 / 255, blue: 255 / 255
  )

  static let spacingXS: CGFloat = 4
  static let spacingSM: CGFloat = 8
  static let spacingMD: CGFloat = 16
  static let spacingLG: CGFloat = 24
  static let cardRadius: CGFloat = 10
  static let badgeRadius: CGFloat = 6
  static let sidebarMinimum: CGFloat = 220
  static let sidebarIdeal: CGFloat = 240
  static let plannerInputMinimumHeight: CGFloat = 152
  static let stockInputMinimumHeight: CGFloat = 72
  static let profileColumnMinimum: CGFloat = 340
  static let systemNameMinimum: CGFloat = 150
  static let systemIDWidth: CGFloat = 132
  static let compactNumberWidth: CGFloat = 92
  static let structureEditorMinimum: CGFloat = 440
  static let efficiencyLabelMinimum: CGFloat = 148
}

struct Panel<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      Text(title)
        .textCase(.uppercase)
        .font(.caption.weight(.semibold))
        .tracking(1.1)
        .foregroundStyle(DesignTokens.textSecondary)
      content
    }
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }
}
