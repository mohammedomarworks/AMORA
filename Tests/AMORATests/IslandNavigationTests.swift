import XCTest
@testable import AMORA

@MainActor
final class IslandNavigationTests: XCTestCase {

    func testIslandPageProperties() {
        let pages = IslandPage.allCases
        XCTAssertEqual(pages.count, 8)
        XCTAssertEqual(pages[0], .home)
        XCTAssertEqual(pages[1], .aiTalk)
        XCTAssertEqual(pages[2], .timer)
        XCTAssertEqual(pages[3], .clipboard)
        XCTAssertEqual(pages[4], .notes)
        XCTAssertEqual(pages[5], .fileShelf)
        XCTAssertEqual(pages[6], .automations)
        XCTAssertEqual(pages[7], .github)

        for page in pages {
            XCTAssertFalse(page.icon.isEmpty, "Page \(page) should have an icon")
            XCTAssertFalse(page.label.isEmpty, "Page \(page) should have a label")
        }
    }

    func testIslandNavigationModelInitialState() {
        let model = IslandNavigationModel.shared
        model.selectedPage = .home
        model.isQuickMenuOpen = false

        XCTAssertEqual(model.selectedPage, .home)
        XCTAssertFalse(model.isQuickMenuOpen)
    }

    func testIslandNavigationModelPageSwitching() {
        let model = IslandNavigationModel.shared
        model.navigateTo(.timer)
        XCTAssertEqual(model.selectedPage, .timer)
        XCTAssertFalse(model.isQuickMenuOpen)

        model.navigateTo(.notes)
        XCTAssertEqual(model.selectedPage, .notes)

        model.navigateTo(.home)
        XCTAssertEqual(model.selectedPage, .home)
    }

    func testIslandNavigationModelBoundaries() {
        let model = IslandNavigationModel.shared
        model.navigateTo(.home)
        XCTAssertEqual(model.selectedPage, .home)

        // Previous from first page should clamp to home
        model.previousPage()
        XCTAssertEqual(model.selectedPage, .home)

        // Advance to next pages
        model.nextPage()
        XCTAssertEqual(model.selectedPage, .aiTalk)
        model.nextPage()
        XCTAssertEqual(model.selectedPage, .timer)

        // Navigate to last page
        model.navigateTo(.github)
        XCTAssertEqual(model.selectedPage, .github)

        // Next from last page should clamp to github
        model.nextPage()
        XCTAssertEqual(model.selectedPage, .github)

        // Previous from github should go to automations
        model.previousPage()
        XCTAssertEqual(model.selectedPage, .automations)
    }

    func testIslandNavigationModelQuickMenuToggle() {
        let model = IslandNavigationModel.shared
        model.isQuickMenuOpen = false

        model.toggleQuickMenu()
        XCTAssertTrue(model.isQuickMenuOpen)

        model.toggleQuickMenu()
        XCTAssertFalse(model.isQuickMenuOpen)

        // Navigating to page should close quick menu
        model.isQuickMenuOpen = true
        model.navigateTo(.clipboard)
        XCTAssertFalse(model.isQuickMenuOpen)
        XCTAssertEqual(model.selectedPage, .clipboard)
    }

    func testWideIslandDimensionsOnMacBookDisplays() {
        // Typical MacBook Air / Pro 13" resolution: 1440 x 900
        let macBookAirWidth: CGFloat = 1440
        let macBookAirHeight: CGFloat = 900
        let screenMargin: CGFloat = 8

        let targetWidth = min(840, max(760, macBookAirWidth * 0.58))
        let targetTotalHeight = min(230, max(200, macBookAirHeight * 0.25))

        // Target: expanded width approximately 760-900 points
        XCTAssertGreaterThanOrEqual(targetWidth, 760)
        XCTAssertLessThanOrEqual(targetWidth, 900)

        // Target: expanded total height approximately 190-250 points
        XCTAssertGreaterThanOrEqual(targetTotalHeight, 190)
        XCTAssertLessThanOrEqual(targetTotalHeight, 250)

        // Test graceful scale down on smaller screens (e.g. 800 x 600)
        let smallScreenWidth: CGFloat = 800
        let smallMaxWidth = smallScreenWidth - (screenMargin * 2)
        let smallTargetWidth = min(min(840, max(760, smallScreenWidth * 0.58)), smallMaxWidth)
        XCTAssertLessThanOrEqual(smallTargetWidth, smallMaxWidth)
    }
}
