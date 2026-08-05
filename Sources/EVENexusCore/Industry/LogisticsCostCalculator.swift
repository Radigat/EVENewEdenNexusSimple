import Foundation

public struct LogisticsCargoItem: Sendable {
  public let typeID: Int64
  public let quantity: Int64
  public let collateral: Double?
  public let packagedVolumePerUnit: Double?

  public init(
    typeID: Int64,
    quantity: Int64,
    collateral: Double?,
    packagedVolumePerUnit: Double?
  ) {
    self.typeID = typeID
    self.quantity = quantity
    self.collateral = collateral
    self.packagedVolumePerUnit = packagedVolumePerUnit
  }
}

public enum LogisticsCostCalculator {
  public static func calculateLegs(
    kind: LogisticsLegKind,
    origin: String,
    destination: String,
    cargo: [LogisticsCargoItem],
    iskPerCubicMeter: Double,
    maximumContractVolumeM3: Double
  ) -> (legs: [LogisticsCostLeg], warnings: [DomainWarning]) {
    guard !cargo.isEmpty else { return ([], []) }
    guard iskPerCubicMeter.isFinite, iskPerCubicMeter > 0 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.missing-volume-rate",
            message:
              "Logistics is enabled, but the ISK per m³ rate is missing or invalid.",
            severity: .blocking
          )
        ]
      )
    }
    guard maximumContractVolumeM3.isFinite, maximumContractVolumeM3 > 0 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.invalid-volume-limit",
            message:
              "Logistics is enabled, but the contract volume limit is invalid.",
            severity: .blocking
          )
        ]
      )
    }

    struct AcceptedCargoItem {
      let typeID: Int64
      let quantity: Int64
      let unitVolume: Double
      let unitCollateral: Double
    }
    struct ContractDraft {
      var volume: Double
      var collateral: Double
    }

    var acceptedCargo: [AcceptedCargoItem] = []
    var totalVolume = 0.0
    var warnings: [DomainWarning] = []
    for item in cargo {
      guard item.quantity > 0,
        let unitVolume = item.packagedVolumePerUnit,
        unitVolume.isFinite,
        unitVolume >= 0
      else {
        warnings.append(
          DomainWarning(
            code: "logistics.missing-packaged-volume",
            message:
              "A packaged SDE volume required for \(kind.displayName.lowercased()) is unavailable.",
            severity: .blocking
          )
        )
        continue
      }
      let itemVolume = unitVolume * Double(item.quantity)
      guard itemVolume.isFinite, itemVolume >= 0 else {
        warnings.append(
          DomainWarning(
            code: "logistics.invalid-volume",
            message: "A logistics cargo volume exceeded safe numeric limits.",
            severity: .blocking
          )
        )
        continue
      }
      totalVolume += itemVolume
      guard let itemCollateral = item.collateral,
        itemCollateral.isFinite,
        itemCollateral >= 0
      else {
        warnings.append(
          DomainWarning(
            code: "logistics.missing-collateral",
            message:
              "Accurate market collateral for \(kind.displayName.lowercased()) is unavailable.",
            severity: .blocking
          )
        )
        continue
      }
      guard unitVolume <= maximumContractVolumeM3 else {
        warnings.append(
          DomainWarning(
            code: "logistics.single-item-volume-exceeded",
            message:
              "Type \(item.typeID) has a packaged volume of \(unitVolume.formatted()) m³ and cannot fit into the configured \(maximumContractVolumeM3.formatted()) m³ contract limit.",
            severity: .blocking
          )
        )
        continue
      }
      acceptedCargo.append(
        AcceptedCargoItem(
          typeID: item.typeID,
          quantity: item.quantity,
          unitVolume: unitVolume,
          unitCollateral: itemCollateral / Double(item.quantity)
        )
      )
    }
    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return ([], warnings)
    }
    guard totalVolume.isFinite, totalVolume >= 0 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.invalid-volume",
            message: "A logistics cargo volume exceeded safe numeric limits.",
            severity: .blocking
          )
        ]
      )
    }
    let minimumContractCount = ceil(
      totalVolume / maximumContractVolumeM3
    )
    guard minimumContractCount <= 100_000 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.contract-count-limit",
            message:
              "\(kind.displayName) would require more than 100,000 contracts and exceeds the planning safety limit.",
            severity: .blocking
          )
        ]
      )
    }

    acceptedCargo.sort {
      if $0.unitVolume != $1.unitVolume {
        return $0.unitVolume > $1.unitVolume
      }
      return $0.typeID < $1.typeID
    }
    var contracts: [ContractDraft] = []
    let tolerance = max(1, maximumContractVolumeM3) * 1e-12
    for item in acceptedCargo {
      var remaining = item.quantity
      if item.unitVolume == 0 {
        if contracts.isEmpty {
          contracts.append(ContractDraft(volume: 0, collateral: 0))
        }
        contracts[0].collateral += item.unitCollateral * Double(remaining)
        continue
      }
      while remaining > 0 {
        var selectedIndex: Int?
        var acceptedQuantity: Int64 = 0
        for index in contracts.indices {
          let available = maximumContractVolumeM3 - contracts[index].volume
          let capacity = Int64(
            min(
              Double(remaining),
              floor(max(0, available + tolerance) / item.unitVolume)
            )
          )
          if capacity > 0 {
            selectedIndex = index
            acceptedQuantity = min(remaining, capacity)
            break
          }
        }
        if selectedIndex == nil {
          guard contracts.count < 100_000 else {
            return (
              [],
              warnings + [
                DomainWarning(
                  code: "logistics.contract-count-limit",
                  message:
                    "\(kind.displayName) requires more than 100,000 contracts and exceeds the planning safety limit.",
                  severity: .blocking
                )
              ]
            )
          }
          contracts.append(ContractDraft(volume: 0, collateral: 0))
          selectedIndex = contracts.index(before: contracts.endIndex)
          acceptedQuantity = min(
            remaining,
            max(
              1,
              Int64(
                min(
                  Double(remaining),
                  floor(
                    (maximumContractVolumeM3 + tolerance) / item.unitVolume
                  )
                )
              )
            )
          )
        }
        guard let selectedIndex else { continue }
        contracts[selectedIndex].volume +=
          item.unitVolume * Double(acceptedQuantity)
        contracts[selectedIndex].collateral +=
          item.unitCollateral * Double(acceptedQuantity)
        remaining -= acceptedQuantity
      }
    }

    let contractCount = contracts.count
    if contractCount > 1 {
      warnings.append(
        DomainWarning(
          code: "logistics.contracts-split",
          message:
            "\(kind.displayName) is automatically split into \(contractCount) contracts to stay within \(maximumContractVolumeM3.formatted()) m³ per contract.",
          severity: .information
        )
      )
    }
    var legs: [LogisticsCostLeg] = []
    for (offset, contract) in contracts.enumerated() {
      let volumeCharge = contract.volume * iskPerCubicMeter
      let collateralCharge =
        contract.collateral * LogisticsConfiguration.collateralRate
      let chargedBy: LogisticsChargeBasis =
        volumeCharge >= collateralCharge ? .volume : .collateral
      let unroundedCharge = max(volumeCharge, collateralCharge)
      let roundedCharge =
        ceil(unroundedCharge / LogisticsConfiguration.roundingIncrement)
        * LogisticsConfiguration.roundingIncrement
      guard volumeCharge.isFinite, collateralCharge.isFinite,
        roundedCharge.isFinite, roundedCharge >= 0
      else {
        return (
          [],
          warnings + [
            DomainWarning(
              code: "logistics.invalid-charge",
              message: "A logistics charge exceeded safe numeric limits.",
              severity: .blocking
            )
          ]
        )
      }
      legs.append(
        LogisticsCostLeg(
          kind: kind,
          origin: origin,
          destination: destination,
          contractNumber: offset + 1,
          contractCount: contractCount,
          cargoVolumeM3: contract.volume,
          collateral: contract.collateral,
          volumeCharge: volumeCharge,
          collateralCharge: collateralCharge,
          chargedBy: chargedBy,
          unroundedCharge: unroundedCharge,
          roundedCharge: roundedCharge
        )
      )
    }
    return (legs, warnings)
  }
}
