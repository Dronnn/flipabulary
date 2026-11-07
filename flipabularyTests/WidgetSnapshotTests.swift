import XCTest
import SwiftUI
import WidgetKit
@testable import flipabulary

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private let sizes: [(WidgetFamily, WidgetSizeClass, CGSize)] = [
        (.systemSmall, .small, CGSize(width: 170, height: 170)),
        (.systemMedium, .medium, CGSize(width: 364, height: 170)),
        (.systemLarge, .large, CGSize(width: 364, height: 382)),
        (.systemExtraLarge, .extraLarge, CGSize(width: 768, height: 382))
    ]

    func testAllWidgetKindSizeAppearanceVariantsRender() throws {
        let snapshot = WidgetSnapshot.galleryPlaceholder
        let entry = WidgetData.makeEntry(
            date: testDate("2026-11-07T10:00:00Z"),
            snapshot: snapshot,
            sortOverride: .dueFirst,
            translationsOverride: true,
            isPlaceholder: true
        )

        for (family, sizeClass, size) in sizes {
            for scheme in [ColorScheme.light, .dark] {
                let summary = ZStack {
                    AppColor.page
                    SummaryWidgetView(entry: entry, familyOverride: family)
                }
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)

                let list = ZStack {
                    AppColor.page
                    ListWidgetView(entry: entry, familyOverride: family)
                }
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)

                for (name, view) in [("summary", AnyView(summary)), ("list", AnyView(list))] {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    renderer.proposedSize = ProposedViewSize(size)
                    let image = try XCTUnwrap(renderer.uiImage, "\(name) \(sizeClass.rawValue) \(scheme)")
                    XCTAssertEqual(image.size.width, size.width, accuracy: 1)
                    XCTAssertEqual(image.size.height, size.height, accuracy: 1)
                    let data = try XCTUnwrap(image.pngData())
                    XCTAssertGreaterThan(data.count, 1_000)
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                    attachment.name = "\(name)-\(sizeClass.rawValue)-\(scheme == .dark ? "dark" : "light")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testListWidgetTranslationVisibilityChangesRenderedWidthUsage() throws {
        let snapshot = WidgetSnapshot.galleryPlaceholder
        let entry = WidgetData.makeEntry(
            date: testDate("2026-11-07T10:00:00Z"),
            snapshot: snapshot,
            sortOverride: .dueFirst,
            translationsOverride: true,
            isPlaceholder: true
        )
        let showing = ListWidgetView(entry: entry, familyOverride: .systemMedium)
            .frame(width: 364, height: 170)
        let hiding = ListWidgetView(
            entry: FlipWidgetEntry(
                date: entry.date,
                snapshot: entry.snapshot,
                stackID: entry.stackID,
                wordSetID: nil,
                sort: entry.sort,
                showTranslations: false,
                missingConfiguredStack: false,
                missingConfiguredWordSet: false,
                isPlaceholder: true
            ),
            familyOverride: .systemMedium
        )
        .frame(width: 364, height: 170)

        let rendererShowing = ImageRenderer(content: showing)
        rendererShowing.scale = 1
        let rendererHiding = ImageRenderer(content: hiding)
        rendererHiding.scale = 1
        XCTAssertNotNil(rendererShowing.uiImage)
        XCTAssertNotNil(rendererHiding.uiImage)
        XCTAssertNotEqual(rendererShowing.uiImage?.pngData(), rendererHiding.uiImage?.pngData())
    }
}
