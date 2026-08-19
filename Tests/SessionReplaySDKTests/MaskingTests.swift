//
//  MaskingTests.swift
//  SessionReplaySDKTests
//
//  Masking is the SDK's privacy boundary: anything these tests let through is
//  pixel data shipped off-device. Treat a failure here as a data-leak bug, not
//  a cosmetic one.
//

#if canImport(UIKit)
import XCTest
import UIKit
@testable import SessionReplaySDK

final class MaskingTests: XCTestCase {

    private var manager: SessionReplayManager { .shared }

    /// Root view large enough to hold the fixtures below.
    private func makeRoot() -> UIView {
        UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    }

    private func configure(
        autoMaskTextFields: Bool = true,
        autoMaskSecureTextFields: Bool = true,
        autoMaskViewClasses: [String] = []
    ) {
        var config = SessionReplayConfig()
        config.storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReplayTests", isDirectory: true)
        config.autoStartOnLaunch = false
        config.enableVideoRecording = false
        config.autoMaskTextFields = autoMaskTextFields
        config.autoMaskSecureTextFields = autoMaskSecureTextFields
        config.autoMaskViewClasses = autoMaskViewClasses
        manager.configure(config)
    }

    override func setUp() {
        super.setUp()
        configure()
    }

    // MARK: - Auto-masking basics

    func testPlainTextFieldIsAutoMasked() {
        let root = makeRoot()
        let field = UITextField(frame: CGRect(x: 10, y: 20, width: 200, height: 40))
        root.addSubview(field)

        let frames = manager.collectSensitiveViewFrames(in: root)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first, CGRect(x: 10, y: 20, width: 200, height: 40))
    }

    func testTextViewIsAutoMasked() {
        let root = makeRoot()
        root.addSubview(UITextView(frame: CGRect(x: 0, y: 0, width: 100, height: 100)))

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1)
    }

    func testNothingIsMaskedWhenAutoMaskingIsOffAndNothingIsMarked() {
        configure(autoMaskTextFields: false, autoMaskSecureTextFields: false)
        let root = makeRoot()
        root.addSubview(UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40)))
        root.addSubview(UILabel(frame: CGRect(x: 0, y: 50, width: 100, height: 40)))

        XCTAssertTrue(manager.collectSensitiveViewFrames(in: root).isEmpty)
    }

    func testCustomViewClassIsAutoMaskedByName() {
        configure(autoMaskTextFields: false,
                  autoMaskSecureTextFields: false,
                  autoMaskViewClasses: ["UILabel"])
        let root = makeRoot()
        root.addSubview(UILabel(frame: CGRect(x: 5, y: 5, width: 60, height: 20)))

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1)
    }

    // MARK: - Secure fields: must never be exposed by an opt-out

    func testSecureFieldIsMaskedEvenWhenPlainTextFieldMaskingIsOff() {
        configure(autoMaskTextFields: false, autoMaskSecureTextFields: true)
        let root = makeRoot()

        let plain = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let secure = UITextField(frame: CGRect(x: 0, y: 50, width: 100, height: 40))
        secure.isSecureTextEntry = true
        root.addSubview(plain)
        root.addSubview(secure)

        let frames = manager.collectSensitiveViewFrames(in: root)

        XCTAssertEqual(frames, [CGRect(x: 0, y: 50, width: 100, height: 40)],
                       "Only the secure field should be masked")
    }

    func testSecureFieldStaysMaskedWhenExplicitlyMarkedUnmasked() {
        let root = makeRoot()
        let secure = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        secure.isSecureTextEntry = true
        secure.markAsUnmasked()
        root.addSubview(secure)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1,
                       "markAsUnmasked() must never expose a password field")
    }

    func testSecureFieldStaysMaskedInsideAnUnmaskedContainer() {
        let root = makeRoot()

        // A whole section opted out of masking — e.g. .unmaskedContent() on a Form section.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        container.markAsUnmasked()

        let url = UITextField(frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        let password = UITextField(frame: CGRect(x: 10, y: 60, width: 200, height: 40))
        password.isSecureTextEntry = true
        container.addSubview(url)
        container.addSubview(password)
        root.addSubview(container)

        let frames = manager.collectSensitiveViewFrames(in: root)

        XCTAssertEqual(frames, [CGRect(x: 10, y: 60, width: 200, height: 40)],
                       "The plain field is exposed by the opt-out; the password field is not")
    }

    // MARK: - Opt-out and precedence

    func testUnmaskedOptOutExposesAPlainTextField() {
        let root = makeRoot()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        field.markAsUnmasked()
        root.addSubview(field)

        XCTAssertTrue(manager.collectSensitiveViewFrames(in: root).isEmpty)
    }

    func testExplicitlySensitiveWinsOverUnmasked() {
        let root = makeRoot()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        field.markAsUnmasked()
        field.markAsSensitive()
        root.addSubview(field)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1,
                       "markAsSensitive() must win over markAsUnmasked()")
    }

    func testMaskedViewIsAlwaysMaskedRegardlessOfAutoMaskSettings() {
        configure(autoMaskTextFields: false, autoMaskSecureTextFields: false)
        let root = makeRoot()
        root.addSubview(MaskedView(frame: CGRect(x: 1, y: 2, width: 30, height: 40)))

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root),
                       [CGRect(x: 1, y: 2, width: 30, height: 40)])
    }

    func testUnmaskedDoesNotExposeAnExplicitlySensitiveSubview() {
        let root = makeRoot()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        container.markAsUnmasked()

        let secret = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        secret.markAsSensitive()
        container.addSubview(secret)
        root.addSubview(container)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root),
                       [CGRect(x: 10, y: 10, width: 50, height: 50)])
    }

    // MARK: - Geometry

    func testFramesAreReportedInRootCoordinates() {
        let root = makeRoot()
        let middle = UIView(frame: CGRect(x: 100, y: 200, width: 200, height: 200))
        let field = UITextField(frame: CGRect(x: 10, y: 20, width: 50, height: 30))
        middle.addSubview(field)
        root.addSubview(middle)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root),
                       [CGRect(x: 110, y: 220, width: 50, height: 30)],
                       "Frame must be converted into the captured root's coordinate space")
    }

    func testChildrenOfAMaskedViewAreNotCollectedSeparately() {
        let root = makeRoot()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        container.markAsSensitive()
        container.addSubview(UITextField(frame: CGRect(x: 5, y: 5, width: 100, height: 40)))
        container.addSubview(UITextField(frame: CGRect(x: 5, y: 50, width: 100, height: 40)))
        root.addSubview(container)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1,
                       "A masked container should produce one frame, not one per descendant")
    }

    func testPartiallyOverlappingUnmaskedRegionDoesNotExposeAField() {
        let root = makeRoot()

        // Opt-out marker that only covers the left half of the field.
        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 40))
        marker.markAsUnmasked()
        root.addSubview(marker)

        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        root.addSubview(field)

        XCTAssertEqual(manager.collectSensitiveViewFrames(in: root).count, 1,
                       "50% coverage is below the threshold, so the field stays masked")
    }

    func testIsCoveredThreshold() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(manager.isCovered(frame, by: [frame]))
        XCTAssertTrue(manager.isCovered(frame, by: [CGRect(x: -10, y: -10, width: 200, height: 200)]))
        XCTAssertFalse(manager.isCovered(frame, by: []))
        XCTAssertFalse(manager.isCovered(frame, by: [CGRect(x: 200, y: 200, width: 10, height: 10)]),
                       "Disjoint region must not count as coverage")
        XCTAssertFalse(manager.isCovered(frame, by: [CGRect(x: 0, y: 0, width: 50, height: 100)]),
                       "50% coverage is below the 90% threshold")
        XCTAssertFalse(manager.isCovered(.zero, by: [frame]),
                       "A zero-area frame must not be treated as covered")
    }

    // MARK: - Markers

    func testMarkersAppendToAnExistingAccessibilityIdentifier() {
        let view = UIView()
        view.accessibilityIdentifier = "checkout-button"
        view.markAsSensitive()

        XCTAssertTrue(view.isSensitive)
        XCTAssertTrue(view.accessibilityIdentifier!.contains("checkout-button"),
                      "Marking must not destroy an identifier the app relies on")
    }

    func testMarkersAreIdempotent() {
        let view = UIView()
        view.markAsSensitive()
        view.markAsSensitive()
        view.markAsUnmasked()
        view.markAsUnmasked()

        XCTAssertEqual(view.accessibilityIdentifier?.components(separatedBy: "sr-no-capture").count, 2)
        XCTAssertEqual(view.accessibilityIdentifier?.components(separatedBy: "sr-unmasked").count, 2)
    }

    func testSensitiveAndUnmaskedMarkersDoNotCollide() {
        let sensitive = UIView()
        sensitive.markAsSensitive()
        XCTAssertTrue(sensitive.isSensitive)
        XCTAssertFalse(sensitive.isUnmasked)

        let unmasked = UIView()
        unmasked.markAsUnmasked()
        XCTAssertTrue(unmasked.isUnmasked)
        XCTAssertFalse(unmasked.isSensitive)
    }
}
#endif
