@testable import MeetingTranscriber
import XCTest

final class MeetingLibraryTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeetingLibraryTests_\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    private func write(_ name: String, _ text: String = "x") throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - Basename parsing

    func testParseStripsStampAndShortID() throws {
        let parsed = try XCTUnwrap(MeetingRecord.parse(basename: "20261001_0949_microphone_recording_92dfa501"))
        XCTAssertEqual(parsed.slug, "microphone_recording")
        XCTAssertEqual(parsed.date, localDate(2026, 10, 1, 9, 49))
    }

    func testParseWithoutShortIDKeepsTheWholeSlug() throws {
        let parsed = try XCTUnwrap(MeetingRecord.parse(basename: "20260929_1500_devsync"))
        XCTAssertEqual(parsed.slug, "devsync")
        XCTAssertEqual(parsed.date, localDate(2026, 9, 29, 15, 0))
    }

    func testParseKeepsNonLatinSlugs() throws {
        let parsed = try XCTUnwrap(MeetingRecord.parse(basename: "20260930_1100_евгений_елена_0a1b2c3d"))
        XCTAssertEqual(parsed.slug, "евгений_елена")
    }

    func testParseOfAStemWithOnlyAShortIDLeavesAnEmptySlug() throws {
        let parsed = try XCTUnwrap(MeetingRecord.parse(basename: "20261001_0949_92dfa501"))
        XCTAssertEqual(parsed.slug, "")
        XCTAssertEqual(MeetingRecord.humanize(slug: parsed.slug), "Meeting")
    }

    func testParseRejectsAStemWithoutStamp() {
        XCTAssertNil(MeetingRecord.parse(basename: "notes from monday"))
        XCTAssertNil(MeetingRecord.parse(basename: "2026_0949_short"))
    }

    func testHumanizeRestoresSpacesAndCapitalisesTheFirstLetter() {
        XCTAssertEqual(MeetingRecord.humanize(slug: "microphone_recording"), "Microphone recording")
        XCTAssertEqual(MeetingRecord.humanize(slug: "qa_monthly_talks"), "Qa monthly talks")
        XCTAssertEqual(MeetingRecord.humanize(slug: "евгений_елена"), "Евгений елена")
    }

    // MARK: - Scanning

    func testScanPairsTranscriptAndProtocolByStem() throws {
        try write("20261001_1115_grooming_aaaaaaaa.txt")
        try write("20261001_1115_grooming_aaaaaaaa.md")
        try write("20260930_1300_qa_talks_bbbbbbbb.txt")

        let records = MeetingLibrary.scan(protocolsDir: dir)

        XCTAssertEqual(records.map(\.basename), [
            "20261001_1115_grooming_aaaaaaaa",
            "20260930_1300_qa_talks_bbbbbbbb",
        ], "newest meeting first")
        XCTAssertNotNil(records[0].transcriptURL)
        XCTAssertNotNil(records[0].protocolURL)
        XCTAssertNotNil(records[1].transcriptURL)
        XCTAssertNil(records[1].protocolURL)
        XCTAssertEqual(records[0].title, "Grooming")
    }

    func testScanIgnoresOtherFilesAndHiddenOnes() throws {
        try write("20261001_1115_grooming_aaaaaaaa.txt")
        try write("20261001_1115_grooming_aaaaaaaa_16k.wav")
        try write("20261001_1115_grooming_aaaaaaaa_meta.json")
        try write(".DS_Store")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("folder.md"), withIntermediateDirectories: true,
        )

        let records = MeetingLibrary.scan(protocolsDir: dir)

        XCTAssertEqual(records.map(\.basename), ["20261001_1115_grooming_aaaaaaaa"])
    }

    func testScanPrefersAStoredTitleOverTheSlug() throws {
        try write("20261001_1130_crm_daily_cccccccc.txt")

        let records = MeetingLibrary.scan(
            protocolsDir: dir, knownTitles: ["20261001_1130_crm_daily_cccccccc": "CRM daily (Q4)"],
        )

        XCTAssertEqual(records.first?.title, "CRM daily (Q4)")
    }

    func testScanFallsBackToTheModificationDateForAnUnstampedFile() throws {
        try write("hand renamed.txt")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: modified], ofItemAtPath: dir.appendingPathComponent("hand renamed.txt").path,
        )

        let record = try XCTUnwrap(MeetingLibrary.scan(protocolsDir: dir).first)

        XCTAssertEqual(record.title, "hand renamed")
        XCTAssertEqual(record.date.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1)
    }

    func testScanOfAMissingFolderIsEmpty() {
        XCTAssertEqual(MeetingLibrary.scan(protocolsDir: dir.appendingPathComponent("nope")), [])
    }

    // MARK: - Stored titles

    func testKnownTitlesKeysBothFilesByStem() {
        let record = JobStatusDTO(
            jobID: UUID().uuidString, state: .done, meetingTitle: "Wallet Team Stand UP",
            transcriptPath: "/old/place/protocols/20261001_1200_wallet_team_stand_up_dddddddd.txt",
            protocolPath: "/old/place/protocols/20261001_1200_wallet_team_stand_up_dddddddd.md",
            error: nil, warnings: [],
        )

        let titles = MeetingLibrary.knownTitles(from: [record])

        XCTAssertEqual(titles, ["20261001_1200_wallet_team_stand_up_dddddddd": "Wallet Team Stand UP"])
    }

    // MARK: - Grouping

    func testGroupedByDayOrdersDaysNewestFirstAndKeepsOrderWithinADay() throws {
        let calendar = Calendar(identifier: .gregorian)
        func record(_ name: String, _ date: Date?) throws -> MeetingRecord {
            let date = try XCTUnwrap(date)
            return MeetingRecord(
                basename: name, title: name, date: date,
                transcriptURL: nil, protocolURL: nil, modifiedAt: date,
            )
        }
        let records = try [
            record("late", localDate(2026, 10, 1, 17, 0)),
            record("early", localDate(2026, 10, 1, 9, 0)),
            record("yesterday", localDate(2026, 9, 30, 14, 0)),
        ]

        let groups = MeetingLibrary.groupedByDay(records, calendar: calendar)

        XCTAssertEqual(groups.map { $0.records.map(\.basename) }, [["late", "early"], ["yesterday"]])
        XCTAssertEqual(groups.first?.day, calendar.startOfDay(for: records[0].date))
    }
}
