import Foundation
import Testing

@testable import EVENexusSimpleApp

struct MarketStockAxisFormatTests {
  private let german = Locale(identifier: "de_DE")

  @Test
  func scalesToReadableUnitsWithoutScientificNotation() {
    #expect(MarketStockAxisFormat.label(0, locale: german) == "0")
    #expect(MarketStockAxisFormat.label(3.5, locale: german) == "3,5")
    #expect(MarketStockAxisFormat.label(20_000, locale: german) == "20 \("Tsd.".localizedUI)")
    #expect(MarketStockAxisFormat.label(500_000_000, locale: german) == "500 \("Mio.".localizedUI)")
    #expect(MarketStockAxisFormat.label(1_000_000_000, locale: german) == "1 B")
    #expect(MarketStockAxisFormat.label(2_500_000_000, locale: german) == "2,5 B")
    #expect(MarketStockAxisFormat.label(4_000_000_000_000, locale: german) == "4 T")
  }

  @Test
  func valueRoundingUpToAThousandMovesToTheNextUnit() {
    #expect(MarketStockAxisFormat.label(999_999_999, locale: german) == "1 B")
    #expect(MarketStockAxisFormat.label(999.999, locale: german) == "1 \("Tsd.".localizedUI)")
  }

  @Test
  func negativeValuesKeepTheirSignAndUnit() {
    #expect(MarketStockAxisFormat.label(-2_000_000_000, locale: german) == "-2 B")
  }
}
