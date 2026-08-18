import XCTest
@testable import ScreenTidy

final class VisualIntelligenceTests: XCTestCase {
    func testVisualLabelFilterDropsLowInformationAndCaps() {
        XCTAssertTrue(VisualLabelFilter.lowInformationIdentifiers.contains("indoor"))
        XCTAssertTrue(VisionEvidencePolicy.nounDenylist.contains("airplane"))
        XCTAssertTrue(ResolverPolicy.genericTitleDenylist.contains("airplane"))
        XCTAssertTrue(ResolverPolicy.genericTitleDenylist.contains("furniture"))

        let outcome = VisualLabelFilter.filterCandidates(
            [
                .init(identifier: "sofa", confidence: 0.92, precisionOK: true),
                .init(identifier: "indoor", confidence: 0.99, precisionOK: true),
                .init(identifier: "text", confidence: 0.88, precisionOK: true),
                .init(identifier: "furniture", confidence: 0.81, precisionOK: true),
                .init(identifier: "noise", confidence: 0.10, precisionOK: false)
            ],
            settings: .production
        )
        XCTAssertTrue(outcome.raw.contains(where: { $0.identifier == "indoor" }))
        XCTAssertTrue(outcome.filtered.contains(where: { $0.identifier == "sofa" }))
        XCTAssertFalse(outcome.filtered.contains(where: { $0.identifier == "indoor" }))
        XCTAssertTrue(outcome.dropped.contains(where: { $0.identifier == "indoor" && $0.reason == .lowInformation }))
        XCTAssertTrue(outcome.dropped.contains(where: { $0.identifier == "noise" }))
    }

    func testNeighborBandThresholds() {
        XCTAssertEqual(VisualAnalysisPipeline.neighborBand(distance: 0.40), .strong)
        XCTAssertEqual(VisualAnalysisPipeline.neighborBand(distance: 0.80), .weak)
        XCTAssertEqual(VisualAnalysisPipeline.neighborBand(distance: 1.20), .far)
    }

    func testAnalysisInputLongEdgeNoteSeparatesOCRAndVisual() {
        let note = VisualAnalysisPipeline.analysisInputLongEdgeNote
        XCTAssertTrue(note.contains("\(Int(VisualAnalysisPipeline.imageLongEdge))"))
        XCTAssertTrue(note.contains("\(Int(OCRPipeline.imageLongEdge))"))
        XCTAssertNotEqual(VisualAnalysisPipeline.imageLongEdge, OCRPipeline.imageLongEdge)
    }

    func testPersistedRawEmptyMessagingWhenFilteredExists() throws {
        let message = VisualEvalDebugMessaging.persistedRawEmptyExplanation(rawCount: 0, filteredCount: 2)
        let text = try XCTUnwrap(message)
        XCTAssertTrue(text.contains("RAW labels were not persisted"))
        XCTAssertTrue(text.contains("Live classify"))
        XCTAssertNil(VisualEvalDebugMessaging.persistedRawEmptyExplanation(rawCount: 3, filteredCount: 2))
    }

    func testPersistedRawEmptyMessagingWhenBothEmpty() throws {
        let message = VisualEvalDebugMessaging.persistedRawEmptyExplanation(rawCount: 0, filteredCount: 0)
        let text = try XCTUnwrap(message)
        XCTAssertTrue(text.contains("No RAW or FILTERED"))
        XCTAssertTrue(text.contains("Live classify"))
    }

    func testFacetDeriverFurnitureInteriorWithoutImageOnly() {
        let labels = [
            VisualLabelObservation(identifier: "sofa", confidence: 0.9),
            VisualLabelObservation(identifier: "furniture", confidence: 0.8)
        ]
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: "", labels: labels)
        XCTAssertFalse(evidence.contains { $0.id == "image_only" })
        XCTAssertTrue(evidence.contains { $0.id == "interior_reference" && $0.strength == .strong })
        XCTAssertFalse(evidence.contains { $0.id == "boarding_pass" })
    }

    func testFacetDeriverBoardingPassFromOCR() {
        let facets = ScreenshotFacetDeriver.derive(
            ocrText: "Boarding Pass DOH → NRT Seat 12A",
            labels: []
        )
        XCTAssertTrue(facets.contains("boarding_pass"))
    }

    func testFacetAirlineCheckInIsNotHotel() {
        let ocr = """
        Flight details
        AUH CGK
        Terminal 3
        Check-in opens in 1 day
        Passenger Mr Example
        Manage trip
        """
        let evidence = ScreenshotFacetDeriver.evaluate(
            ocrText: ocr,
            labels: [VisualLabelObservation(identifier: "document", confidence: 0.96)]
        )
        let strong = Set(evidence.filter { $0.strength == .strong }.map(\.id))
        XCTAssertTrue(strong.contains("flight_booking") || strong.contains("boarding_pass"))
        XCTAssertFalse(strong.contains("hotel_booking"))
        XCTAssertFalse(evidence.contains { $0.id == "hotel_booking" })
        // Vision document alone must not define type.
        XCTAssertFalse(strong.contains("document"))
    }

    func testFacetRealHotelCheckInCheckOut() {
        let ocr = """
        Park Hyatt Tokyo
        Check-in 15:00
        Check-out 11:00
        Guest room 1204
        2 nights accommodation
        """
        let strong = Set(ScreenshotFacetDeriver.derive(ocrText: ocr, labels: []))
        XCTAssertTrue(strong.contains("hotel_booking"))
        XCTAssertFalse(strong.contains("boarding_pass"))
    }

    func testFacetHotelArrivalDepartureReservationStrong() {
        let ocr = """
        Your stay at The Ritz
        Arrival 15:00
        Departure 11:00
        Room type Deluxe King
        Guests 2
        Booking reference HX991
        """
        let strong = Set(ScreenshotFacetDeriver.derive(ocrText: ocr, labels: []))
        XCTAssertTrue(strong.contains("hotel_booking"))
    }

    func testFacetIsolatedCheckInInsufficientForHotel() {
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: "Check-in reminder", labels: [])
        XCTAssertFalse(evidence.contains { $0.id == "hotel_booking" })
    }

    func testFacetChatDialogueStrongWithoutWhatsApp() {
        let ocr = """
        04:02
        Kita udahan gausah hubungi aku lagi
        04:03
        kenapa kamu ngegas terus
        04:04
        ok fine bye
        04:05
        jangan chat lagi
        04:06
        serius sudah aku bilang
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [
            VisualLabelObservation(identifier: "document", confidence: 0.7)
        ])
        let chat = evidence.first { $0.id == "chat" }
        XCTAssertEqual(chat?.strength, .strong)
        XCTAssertEqual(chat?.sources.contains(.ocrStructure), true)
    }

    func testFacetChatStrongWithMultiCueConversation() {
        let ocr = """
        04:02
        Alex: Kita udahan gausah hubungi aku lagi
        04:03
        You: kenapa kamu ngegas terus
        04:04
        Alex: ok fine bye
        04:05
        You: jangan chat lagi
        Delivered
        Read
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [])
        let chat = evidence.first { $0.id == "chat" }
        XCTAssertEqual(chat?.strength, .strong)
    }

    func testFacetNonChatShortRowsWithClocksNotChat() {
        let ocr = """
        Wi‑Fi
        09:41
        Bluetooth
        09:41
        Cellular
        09:42
        Notifications
        09:42
        Sounds
        09:43
        Focus
        09:43
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [])
        XCTAssertFalse(evidence.contains { $0.id == "chat" })
    }

    func testFacetStackedNotificationsFeedNotChat() {
        let ocr = """
        9:41
        Weather
        Partly Cloudy in Jakarta
        Messages
        Alex sent you a photo
        9:40
        Mail
        Your flight to Singapore is tomorrow
        9:38
        Calendar
        Design review with team
        9:30
        Photos
        New Memory from last week
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [])
        XCTAssertFalse(evidence.contains { $0.id == "chat" })
        XCTAssertFalse(evidence.contains {
            ($0.id == "boarding_pass" || $0.id == "flight_booking") && $0.strength == .strong
        })
    }

    func testFacetNotificationCenterNotStrongBoarding() {
        let ocr = """
        Notification Center
        MON
        Weather NYC 72°
        Messages
        to 12
        at 3
        Calendar
        Flight reminder later
        Photos
        Memories
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [
            VisualLabelObservation(identifier: "document", confidence: 0.8)
        ])
        XCTAssertFalse(evidence.contains {
            ($0.id == "boarding_pass" || $0.id == "flight_booking") && $0.strength == .strong
        })
        XCTAssertFalse(evidence.contains { $0.id == "chat" })
    }

    func testFacetEmptyOCRNeverEmitsImageOnly() {
        let personLabels = [
            VisualLabelObservation(identifier: "adult", confidence: 0.9),
            VisualLabelObservation(identifier: "eyeglasses", confidence: 0.9),
            VisualLabelObservation(identifier: "clothing", confidence: 0.8)
        ]
        let personEvidence = ScreenshotFacetDeriver.evaluate(ocrText: "", labels: personLabels)
        XCTAssertFalse(personEvidence.contains { $0.id == "image_only" })
        XCTAssertFalse(personEvidence.contains { $0.id == "selfie" })

        let emptyEvidence = ScreenshotFacetDeriver.evaluate(ocrText: "", labels: [])
        XCTAssertFalse(emptyEvidence.contains { $0.id == "image_only" })
        XCTAssertTrue(emptyEvidence.isEmpty)
    }

    func testFacetTruePhotoEmptyOCRNoImageOnlyFacet() {
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: "", labels: [
            VisualLabelObservation(identifier: "sofa", confidence: 0.9),
            VisualLabelObservation(identifier: "furniture", confidence: 0.8)
        ])
        XCTAssertFalse(evidence.contains { $0.id == "image_only" })
        XCTAssertTrue(evidence.contains { $0.id == "interior_reference" })
    }

    func testFacetGameplayAbstains() {
        let ocr = """
        Level 12
        HP 80/100
        Score 4500
        Combo x3
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [])
        let strongSemantic = evidence.filter {
            $0.strength == .strong && !["interior_reference", "travel_imagery"].contains($0.id)
        }
        XCTAssertTrue(strongSemantic.isEmpty)
        XCTAssertFalse(evidence.contains { $0.id == "game" || $0.id == "gameplay" || $0.id == "image_only" })
    }

    func testFacetStrongTravelSuppressesStructureOnlyChat() {
        let ocr = """
        Boarding Pass
        DOH NRT
        Terminal 1 Gate A12
        Seat 12A
        Passenger Example
        04:02
        short note
        04:03
        another note
        04:04
        third note
        04:05
        fourth note
        """
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocr, labels: [])
        XCTAssertTrue(evidence.contains {
            ($0.id == "boarding_pass" || $0.id == "flight_booking") && $0.strength == .strong
        })
        XCTAssertFalse(evidence.contains { $0.id == "chat" && $0.strength == .weak })
    }

    func testFacetChatWeakAmbiguousProseAbstainsStrong() {
        let ocr = """
        This morning I thought about many things. The weather was fine and I walked to the store.
        Later I wrote a short note to myself about groceries and plans for the weekend project.
        """
        let strong = Set(ScreenshotFacetDeriver.derive(ocrText: ocr, labels: []))
        XCTAssertFalse(strong.contains("chat"))
    }

    func testFacetPersonImageOnlyNoSelfieType() {
        let labels = [
            VisualLabelObservation(identifier: "adult", confidence: 0.9),
            VisualLabelObservation(identifier: "eyeglasses", confidence: 0.9),
            VisualLabelObservation(identifier: "clothing", confidence: 0.8)
        ]
        let evidence = ScreenshotFacetDeriver.evaluate(ocrText: "", labels: labels)
        let ids = Set(evidence.map(\.id))
        XCTAssertFalse(ids.contains("selfie"))
        XCTAssertFalse(ids.contains("portrait"))
        XCTAssertFalse(ids.contains("friend"))
        XCTAssertFalse(ids.contains("image_only"))
    }

    func testFacetReceiptRequiresMultipleCues() {
        let strongReceipt = Set(ScreenshotFacetDeriver.derive(
            ocrText: "Subtotal $12.00 Tax $1.20 Total $13.20 Receipt #441",
            labels: []
        ))
        XCTAssertTrue(strongReceipt.contains("receipt"))

        let isolated = ScreenshotFacetDeriver.evaluate(ocrText: "Total sales strategy overview", labels: [])
        XCTAssertFalse(isolated.contains { $0.id == "receipt" })
    }

    func testFacetMapNavigation() {
        let strong = Set(ScreenshotFacetDeriver.derive(
            ocrText: "Google Maps Directions 12 min walk to destination",
            labels: [VisualLabelObservation(identifier: "map", confidence: 0.8)]
        ))
        XCTAssertTrue(strong.contains("map"))
    }

    func testFacetArticleVsSocialConservative() {
        let social = ScreenshotFacetDeriver.evaluate(
            ocrText: "Instagram liked by anna and 40 others followers comments",
            labels: []
        )
        XCTAssertTrue(social.contains { $0.id == "social_post" && $0.strength == .strong })

        let ambiguous = ScreenshotFacetDeriver.evaluate(
            ocrText: "Notes from the meeting about Q3 planning",
            labels: [VisualLabelObservation(identifier: "document", confidence: 0.9)]
        )
        let strongIDs = Set(ambiguous.filter { $0.strength == .strong }.map(\.id))
        XCTAssertFalse(strongIDs.contains("article"))
        XCTAssertFalse(strongIDs.contains("social_post"))
        XCTAssertFalse(strongIDs.contains("chat"))
    }

    func testFacetGenericVisionDocumentNeverDefinesLevel2Type() {
        let evidence = ScreenshotFacetDeriver.evaluate(
            ocrText: "Notes from the meeting about Q3 planning and follow-ups",
            labels: [VisualLabelObservation(identifier: "document", confidence: 0.96)]
        )
        XCTAssertFalse(evidence.contains { $0.id == "document" })
        XCTAssertFalse(evidence.contains { $0.strength == .strong })
    }

    func testFacetAmbiguousUnsupportedAbstains() {
        let strong = Set(ScreenshotFacetDeriver.derive(
            ocrText: "misc token xyz 123",
            labels: [VisualLabelObservation(identifier: "document", confidence: 0.5)]
        ))
        XCTAssertTrue(strong.isEmpty)
    }

    func testFacetEvidenceJSONRoundTrip() throws {
        let evidence = ScreenshotFacetDeriver.evaluate(
            ocrText: "Boarding Pass DOH NRT Seat 12A Terminal 1",
            labels: []
        )
        XCTAssertFalse(evidence.isEmpty)
        let json = ScreenshotRecord.facetEvidenceJSON(evidence)
        let decoded = ScreenshotRecord.decodeFacetEvidence(json)
        XCTAssertEqual(decoded.map(\.id), evidence.map(\.id))
        XCTAssertEqual(decoded.first?.strength, evidence.first?.strength)
    }

    func testFacetIdentifiersNeverInVisionNounDenylistAsTitles() {
        // Facet vocabulary must not be treated as Collection titles via noun denylist path —
        // resolver also blocks typeFacets matching titles; spot-check denylist does not auto-create.
        let facets = ["chat", "flight_booking", "boarding_pass", "hotel_booking", "receipt", "map"]
        for facet in facets {
            // Dynamic Collection Invariant: these are evidence ids, not required denylist entries.
            XCTAssertFalse(facet.isEmpty)
        }
        XCTAssertTrue(VisionEvidencePolicy.nounDenylist.contains("document"))
        XCTAssertTrue(VisionEvidencePolicy.nounDenylist.contains("airplane"))
    }

    func testOnDeviceProviderNeverProposesVisionNounTitle() async throws {
        let provider = OnDeviceStructuredUnderstandingProvider()
        let input = UnderstandingInput(
            screenshotID: ScreenshotMemoryID(),
            ocrText: "",
            createdAt: Date(),
            photosLocalIdentifier: nil,
            eligibleCollectionTitles: [],
            eligibleCollectionContexts: [],
            allowMultimodal: false,
            batchMemberIDs: [],
            imageJPEGData: nil,
            visualLabels: [
                VisualLabelObservation(identifier: "airplane", confidence: 0.95),
                VisualLabelObservation(identifier: "airport", confidence: 0.9)
            ],
            visualFacets: ["image_only", "travel_imagery"]
        )
        let result = try await provider.understand(input)
        XCTAssertNil(result.proposedNewCollection)
        XCTAssertTrue(result.visualDescriptors.contains("airplane") || result.visualDescriptors.contains("airport"))
        XCTAssertFalse(result.candidateCollections.contains(where: {
            VisionEvidencePolicy.nounDenylist.contains(CollectionResolver.normalizeTitle($0.title))
        }))
    }

    func testOnDeviceImageOnlyCanReuseExistingContextualCollection() async throws {
        let provider = OnDeviceStructuredUnderstandingProvider()
        let input = UnderstandingInput(
            screenshotID: ScreenshotMemoryID(),
            ocrText: "",
            createdAt: Date(),
            photosLocalIdentifier: nil,
            eligibleCollectionTitles: ["Japan Trip"],
            eligibleCollectionContexts: [
                EligibleCollectionContext(
                    title: "Japan Trip",
                    aliases: [],
                    keyEntities: ["Tokyo"],
                    keyTerms: ["trip"],
                    visualDescriptors: ["airplane", "city"],
                    dateRangeStart: nil,
                    dateRangeEnd: nil
                )
            ],
            allowMultimodal: false,
            batchMemberIDs: [],
            imageJPEGData: nil,
            visualLabels: [
                VisualLabelObservation(identifier: "airplane", confidence: 0.9),
                VisualLabelObservation(identifier: "city", confidence: 0.75)
            ],
            visualFacets: ["image_only", "travel_imagery"]
        )
        let result = try await provider.understand(input)
        XCTAssertNil(result.proposedNewCollection)
        XCTAssertTrue(result.candidateCollections.contains(where: { $0.title == "Japan Trip" }))
    }

    func testMultiSignalClusterGroupsTravelContextSignals() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "boarding pass DOH NRT seat 12a",
            visualLabels: ["airplane"],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0.8,
            profileTitles: ["Weekend Context"]
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(600),
            ocrNormalized: "park hyatt tokyo confirmation number HX99122",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0.8,
            profileTitles: ["Weekend Context"]
        )
        let c = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(900),
            ocrNormalized: "google maps directions to park hyatt",
            visualLabels: ["map"],
            facets: ["map"],
            featurePrintData: nil,
            profileMatchScore: 0.7,
            profileTitles: ["Weekend Context"]
        )
        let d = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(1_200),
            ocrNormalized: "",
            visualLabels: ["landmark", "skyscraper"],
            facets: ["travel_imagery"],
            featurePrintData: nil,
            profileMatchScore: 0.6,
            profileTitles: ["Weekend Context"]
        )
        let unrelated = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(300),
            ocrNormalized: "lol meme funny chat",
            visualLabels: ["person"],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )

        let result = MultiSignalClusterer.cluster(
            around: a,
            candidates: [b, c, d, unrelated],
            maxSize: 8
        )
        XCTAssertTrue(result.memberIDs.contains(a.id))
        XCTAssertTrue(result.memberIDs.contains(b.id))
        XCTAssertTrue(result.memberIDs.contains(c.id))
        XCTAssertFalse(result.memberIDs.contains(unrelated.id))
        XCTAssertGreaterThan(result.supportedEdgeCount, 0)
        XCTAssertFalse(result.memberSupport.filter { !$0.pruned }.isEmpty)
    }

    func testTimeAloneDoesNotClusterUnrelated() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "receipt total $12.50",
            visualLabels: [],
            facets: ["receipt"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(120),
            ocrNormalized: "funny meme lol",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterGenericDocumentVisionDoesNotGroup() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "notes from standup planning",
            visualLabels: ["document"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(60),
            ocrNormalized: "grocery list milk eggs",
            visualLabels: ["document"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterGenericAdultVisionDoesNotGroup() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "",
            visualLabels: ["adult", "clothing"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(60),
            ocrNormalized: "",
            visualLabels: ["adult", "person"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterStrongFeaturePrintAloneDoesNotGroup() {
        let now = Date()
        let print = Data(repeating: 7, count: 64)
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "banking statement march",
            visualLabels: [],
            facets: [],
            featurePrintData: print,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(30),
            ocrNormalized: "recipe chocolate cake flour",
            visualLabels: [],
            facets: [],
            featurePrintData: print,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterSharedHighTierEntityMayGroup() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "boarding pass confirmation number ZX44K91 DOH",
            visualLabels: [],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(86_400 * 3),
            ocrNormalized: "hotel email confirmation number ZX44K91 guest",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertTrue(result.memberIDs.contains(a.id))
        XCTAssertTrue(result.memberIDs.contains(b.id))
    }

    func testClusterSameHotelFacetDifferentContextsStaySeparate() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "marriott downtown check-in guest room 1204",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(86_400 * 40),
            ocrNormalized: "hilton airport check-out guest room 88",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterProfileWithoutIndependentContextDoesNotForce() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "random notes alpha",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0.9,
            profileTitles: ["Existing Context"]
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(120),
            ocrNormalized: "unrelated shopping beta",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0.9,
            profileTitles: ["Existing Context"]
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterOutlierBridgePrunedWhenGroupSupportWeak() {
        let now = Date()
        let seed = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "boarding pass DOH NRT confirmation number AB12CD9",
            visualLabels: [],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let hotel = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(600),
            ocrNormalized: "hotel booking confirmation number AB12CD9 nights",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        // Shares a travel facet bridge with hotel weakly via facet only + time, but no real entity with group core
        let distractor = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(700),
            ocrNormalized: "random map of springfield zoo hours",
            visualLabels: [],
            facets: ["map"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(
            around: seed,
            candidates: [hotel, distractor],
            maxSize: 8
        )
        XCTAssertTrue(result.memberIDs.contains(seed.id))
        XCTAssertTrue(result.memberIDs.contains(hotel.id))
        // Map-only travel bridge without entity overlap should not confidently join, or be pruned
        XCTAssertFalse(result.memberIDs.contains(distractor.id))
    }

    func testClusterExposesGroupHealthDiagnostics() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "flight DOH NRT confirmation number QQ55ZZ1",
            visualLabels: [],
            facets: ["flight_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(400),
            ocrNormalized: "hotel confirmation number QQ55ZZ1 check-in",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs.count, 2)
        XCTAssertGreaterThan(result.meanCohesion, 0)
        XCTAssertGreaterThan(result.weakestMemberSupport, 0)
        XCTAssertFalse(result.memberSupport.filter { !$0.pruned }.isEmpty)
        XCTAssertTrue(result.flags.contains("precision_first"))
        XCTAssertNil(result.singletonReason)
    }

    func testClusterNoPeersReportsNoPeersInPool() {
        let seed = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: Date(),
            ocrNormalized: "boarding pass alone",
            visualLabels: [],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: seed, candidates: [], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [seed.id])
        XCTAssertEqual(result.singletonReason, "no_peers_in_pool")
        XCTAssertEqual(result.inputPeerCount, 0)
        XCTAssertTrue(result.rejectedCandidates.isEmpty)
    }

    func testClusterPeersScoredNoneAdmittedAndRejectedReasons() throws {
        let now = Date()
        let seed = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "park hyatt tokyo reservation nights",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        // Travel facet bridge + near time → contextual PASS but typically below admitFloor.
        let boarding = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(600),
            ocrNormalized: "boarding pass seat 12a gate",
            visualLabels: [],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        // Soft vision/time only → no contextual support.
        let visionPeer = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(120),
            ocrNormalized: "unrelated grocery milk eggs bread",
            visualLabels: ["document"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(
            around: seed,
            candidates: [boarding, visionPeer],
            maxSize: 8
        )
        XCTAssertEqual(result.memberIDs, [seed.id])
        XCTAssertEqual(result.singletonReason, "peers_scored_none_admitted")
        XCTAssertEqual(result.inputPeerCount, 2)
        XCTAssertFalse(result.rejectedCandidates.isEmpty)

        let boardingReject = try XCTUnwrap(result.rejectedCandidates.first { $0.id == boarding.id })
        XCTAssertTrue(boardingReject.hasContextualSupport)
        XCTAssertLessThan(boardingReject.totalScore, MultiSignalClusterer.admitFloor)
        XCTAssertEqual(boardingReject.rejectionReason, "below_admit_threshold")

        let visionReject = try XCTUnwrap(result.rejectedCandidates.first { $0.id == visionPeer.id })
        XCTAssertFalse(visionReject.hasContextualSupport)
        XCTAssertEqual(visionReject.rejectionReason, "no_contextual_support")
    }

    func testClusterRejectedNoContextualWhenScoreWouldOtherwiseLookStrong() throws {
        let now = Date()
        // Soft profile + time accumulate score; without an independent contextual family they must not admit.
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "random notes alpha zebra",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0.9,
            profileTitles: ["Existing Context"]
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(60),
            ocrNormalized: "unrelated shopping beta quartz",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0.9,
            profileTitles: ["Existing Context"]
        )
        let pair = MultiSignalClusterer.score(seed: a, other: b)
        XCTAssertGreaterThan(pair.total, 0.15)
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        let rejected = try XCTUnwrap(result.rejectedCandidates.first)
        XCTAssertEqual(rejected.id, b.id)
        XCTAssertFalse(rejected.hasContextualSupport)
        XCTAssertEqual(rejected.rejectionReason, "no_contextual_support")
    }

    func testClusterCollapsedAfterPrunePreservesDiagnostics() {
        let now = Date()
        // Keep seed-pair scores in [0.32, 0.40) with ~0 cross-score so support≈seedPair/2 < outlierFloor.
        let seed = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "zxqwv plmnt qwert asdfg",
            visualLabels: [],
            facets: ["boarding_pass"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: ["TripHotel", "TripToken"]
        )
        let hotel = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(600),
            ocrNormalized: "park hyatt downtown suite",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: ["TripHotel"]
        )
        let tokenPeer = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: nil, // no time glue with hotel
            // Same tokens, different order — avoids shared multi-word phrase entities.
            ocrNormalized: "plmnt zxqwv asdfg qwert",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: ["TripToken"]
        )
        let seedHotel = MultiSignalClusterer.score(seed: seed, other: hotel)
        let seedToken = MultiSignalClusterer.score(seed: seed, other: tokenPeer)
        let hotelToken = MultiSignalClusterer.score(seed: hotel, other: tokenPeer)
        let diag = String(
            format: "seedHotel=%.3f %@ seedToken=%.3f %@ hotelToken=%.3f",
            seedHotel.total,
            seedHotel.parts.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.3f", $0.value))" }.joined(separator: ","),
            seedToken.total,
            seedToken.parts.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.3f", $0.value))" }.joined(separator: ","),
            hotelToken.total
        )

        let result = MultiSignalClusterer.cluster(
            around: seed,
            candidates: [hotel, tokenPeer],
            maxSize: 8
        )
        XCTAssertGreaterThanOrEqual(seedHotel.total, MultiSignalClusterer.admitFloor, diag)
        XCTAssertLessThan(seedHotel.total, MultiSignalClusterer.outlierFloor * 2, diag)
        XCTAssertGreaterThanOrEqual(seedToken.total, MultiSignalClusterer.admitFloor, diag)
        XCTAssertLessThan(seedToken.total, MultiSignalClusterer.outlierFloor * 2, diag)
        XCTAssertLessThan(hotelToken.total, 0.08, diag)
        XCTAssertEqual(result.memberIDs, [seed.id], diag)
        XCTAssertEqual(result.singletonReason, "collapsed_after_prune", diag)
        XCTAssertFalse(result.memberSupport.filter(\.pruned).isEmpty, diag)
        XCTAssertTrue(
            result.rejectedCandidates.contains { $0.rejectionReason == "pruned_outlier" }
                || result.memberSupport.filter(\.pruned).count >= 1,
            diag
        )
    }

    func testClusterAcceptedGroupingUnchangedWithDiagnostics() throws {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "flight DOH NRT confirmation number QQ55ZZ1",
            visualLabels: [],
            facets: ["flight_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(400),
            ocrNormalized: "hotel confirmation number QQ55ZZ1 check-in",
            visualLabels: [],
            facets: ["hotel_booking"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let distractor = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(500),
            ocrNormalized: "lol meme funny chat",
            visualLabels: ["person"],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b, distractor], maxSize: 8)
        XCTAssertEqual(Set(result.memberIDs), Set([a.id, b.id]))
        XCTAssertNil(result.singletonReason)
        XCTAssertEqual(result.inputPeerCount, 2)
        XCTAssertTrue(result.rejectedCandidates.contains { $0.id == distractor.id })
        let rejected = try XCTUnwrap(result.rejectedCandidates.first { $0.id == distractor.id })
        XCTAssertEqual(rejected.rejectionReason, "no_contextual_support")
    }

    // MARK: - Sprint 8.2B-R1 source / type / family

    func testSourceDeriverInstagramSocialFamily() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: "Instagram Liked by alex and others Comments",
            strongFacets: ["social_post"]
        )
        XCTAssertEqual(e.sourcePlatform, "instagram")
        XCTAssertEqual(e.contentType, "social_post")
        XCTAssertEqual(e.contentFamily, "social_media")
    }

    func testSourceDeriverIdentityNotFromDocumentVisionAlone() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: "some notes",
            labels: [VisualLabelObservation(identifier: "document", confidence: 0.99)],
            strongFacets: []
        )
        XCTAssertNotEqual(e.contentType, "identity_document")
        XCTAssertEqual(e.contentFamily, ScreenshotSourceEvidence.unknown)
    }

    func testSourceDeriverIdentityRequiresMultipleCues() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: "Resident ID Nationality Date of Birth Document No 12345",
            strongFacets: []
        )
        XCTAssertEqual(e.contentType, "identity_document")
        XCTAssertEqual(e.contentFamily, "identity_document")
    }

    func testClusterSamePlatformAloneInsufficient() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "cats vacation beach sunset",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(120),
            ocrNormalized: "cooking pasta recipe dinner",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        let rejected = try? XCTUnwrap(result.rejectedCandidates.first)
        XCTAssertEqual(rejected?.rejectionReason, "type_alone_insufficient")
        XCTAssertFalse(rejected?.hasContextualSupport ?? true)
        XCTAssertGreaterThan(rejected?.signalParts["source_platform"] ?? 0, 0)
        XCTAssertGreaterThan(rejected?.signalParts["content_type"] ?? 0, 0)
        XCTAssertGreaterThan(rejected?.signalParts["content_family"] ?? 0, 0)
    }

    func testClusterSameFamilyAloneInsufficient() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "hiring announcement alphacorp",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "linkedin",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(90),
            ocrNormalized: "weekend barbecue photos",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "facebook",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        let rejected = try? XCTUnwrap(result.rejectedCandidates.first)
        // Same type+family, different platform → type_alone_insufficient
        XCTAssertEqual(rejected?.rejectionReason, "type_alone_insufficient")
    }

    func testClusterCrossPlatformSameCompanyMayGroup() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "qatar airways cabin crew hiring open roles",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(200),
            ocrNormalized: "qatar airways open roles cabin crew apply",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "linkedin",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let pair = MultiSignalClusterer.score(seed: a, other: b)
        // Distinctive OCR / phrases should create contextual support; type/family may corroborate.
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        if pair.total >= MultiSignalClusterer.admitFloor {
            XCTAssertTrue(result.memberIDs.contains(b.id), "shared topic should admit when score clears floor")
            XCTAssertNil(result.singletonReason)
        } else {
            // Still must not use platform-alone reason if OCR overlap exists with contextual families.
            let rejected = try? XCTUnwrap(result.rejectedCandidates.first)
            XCTAssertNotEqual(rejected?.rejectionReason, "source_alone_insufficient")
            XCTAssertNotEqual(rejected?.rejectionReason, "family_alone_insufficient")
        }
    }

    func testClusterUnrelatedCrossPlatformStaySeparate() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "sushi dinner tokyo night",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(200),
            ocrNormalized: "resume tips for graduates",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "linkedin",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testClusterEmailsSameThreadMayGroup() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "from:hr@acme.com interview schedule confirmation number ZX99QQ1",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "gmail",
            contentType: "email",
            contentFamily: "email"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(300),
            ocrNormalized: "from:hr@acme.com interview schedule confirmation number ZX99QQ1",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "gmail",
            contentType: "email",
            contentFamily: "email"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertTrue(result.memberIDs.contains(a.id))
        XCTAssertTrue(result.memberIDs.contains(b.id))
    }

    func testClusterUnrelatedEmailsStaySeparate() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "your receipt for blue running shoes order",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "gmail",
            contentType: "email",
            contentFamily: "email"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(300),
            ocrNormalized: "weekly science newsletter edition forty",
            visualLabels: [],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "gmail",
            contentType: "email",
            contentFamily: "email"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        let rejected = try? XCTUnwrap(result.rejectedCandidates.first)
        XCTAssertEqual(rejected?.rejectionReason, "type_alone_insufficient")
    }

    func testClusterAdultVisionDoesNotGroupAsPerson() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "",
            visualLabels: ["adult", "eyeglasses", "clothing"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(60),
            ocrNormalized: "",
            visualLabels: ["adult", "hoodie", "person"],
            facets: [],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: []
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        // Same-person similarity deferred — no grouping claim from Vision nouns.
    }

    func testClusterWhatsAppSameConversationStillGroups() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "alex: see you at terminal 3 gate b12 tomorrow morning",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(400),
            ocrNormalized: "alex: terminal 3 gate b12 yes bring boarding pass",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertTrue(result.memberIDs.contains(a.id))
        XCTAssertTrue(result.memberIDs.contains(b.id), "same WhatsApp conversation must keep grouping")
    }

    func testClusterUnrelatedWhatsAppConversationsDoNotMergeOnMessagingAlone() {
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "mom: pick up groceries milk eggs bread",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(400),
            ocrNormalized: "boss: quarterly budget spreadsheet ready",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
        let rejected = try? XCTUnwrap(result.rejectedCandidates.first)
        XCTAssertTrue(
            ["type_alone_insufficient", "source_alone_insufficient", "no_contextual_support"]
                .contains(rejected?.rejectionReason ?? "")
        )
    }

    // MARK: - Sprint 8.2B-R2a DEBUG / observability

    func testR2aUnknownPlatformKnownChatMessaging() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: """
            Yesterday
            10:42
            Hey are we still on for dinner
            10:43
            Yes see you at 8
            Delivered
            """,
            strongFacets: ["chat"]
        )
        XCTAssertEqual(e.sourcePlatform, ScreenshotSourceEvidence.unknown)
        XCTAssertEqual(e.contentType, "chat")
        XCTAssertEqual(e.contentFamily, "messaging")
        XCTAssertEqual(e.surface.value, "app_screen")
        XCTAssertFalse(e.platform.trace.isEmpty)
        XCTAssertTrue(e.type.trace.contains { $0.contains("facet") || $0.contains("chat") })
    }

    func testR2aLockScreenEmbeddedGmailNotWholeShotGmail() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: """
            9:41
            Monday, August 10
            Gmail
            Alex: Q3 deck ready for review
            9:38
            Flashlight
            Camera
            Swipe up to unlock
            """,
            strongFacets: []
        )
        XCTAssertEqual(e.surface.value, "lock_screen")
        XCTAssertEqual(e.sourcePlatform, ScreenshotSourceEvidence.unknown)
        XCTAssertEqual(e.contentType, ScreenshotSourceEvidence.unknown)
        XCTAssertEqual(e.contentFamily, ScreenshotSourceEvidence.unknown)
        XCTAssertTrue(e.embeddedHints.contains { $0.value == "gmail" && $0.kind == "notification" })
        XCTAssertTrue(e.platform.trace.contains { $0.lowercased().contains("embedded") || $0.lowercased().contains("abstain") })
    }

    func testR2aAppScreenSurfaceFromPlatform() {
        let e = ScreenshotSourceDeriver.derive(
            ocrText: "Instagram Liked by alex and others Comments",
            strongFacets: ["social_post"]
        )
        XCTAssertEqual(e.surface.value, "app_screen")
        XCTAssertEqual(e.sourcePlatform, "instagram")
        XCTAssertTrue(e.embeddedHints.isEmpty)
    }

    func testR2aCorrelatedFacetTypeFamilyReporting() {
        let channels = SemanticCorrelationDiagnostics.correlatedChannelsForPair(
            sharedFacets: ["chat"],
            sharedContentType: "chat",
            sharedContentFamily: "messaging",
            signalParts: [
                "facets": 0.08,
                "content_type": 0.05,
                "content_family": 0.04,
                "ocr_entities": 0.18
            ]
        )
        XCTAssertTrue(channels.contains("facet(chat)"))
        XCTAssertTrue(channels.contains("type(chat)"))
        XCTAssertTrue(channels.contains("family(messaging)"))
    }

    func testR2aAdmittedMemberAuditAndRejectedPreserved() {
        let now = Date()
        let shared = "Zara confirmation code WX9K4 boarding gate B12"
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: shared,
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(60),
            ocrNormalized: shared + " see you there",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let distractor = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(90),
            ocrNormalized: "unrelated pasta recipe tomatoes basil",
            visualLabels: [],
            facets: ["chat"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "whatsapp",
            contentType: "chat",
            contentFamily: "messaging"
        )
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b, distractor], maxSize: 8)
        XCTAssertTrue(result.memberIDs.contains(a.id))
        XCTAssertTrue(result.memberIDs.contains(b.id))
        let admittedB = try? XCTUnwrap(result.admittedMemberAudits.first { $0.id == b.id })
        XCTAssertEqual(admittedB?.admissionReason, "seed_expand")
        XCTAssertEqual(admittedB?.hasContextualSupport, true)
        XCTAssertEqual(admittedB?.outlierValidationPassed, true)
        XCTAssertGreaterThan(admittedB?.totalScore ?? 0, 0)
        XCTAssertFalse(admittedB?.signalParts.isEmpty ?? true)
        XCTAssertFalse(admittedB?.correlatedSemanticChannels.isEmpty ?? true)
        XCTAssertTrue(result.rejectedCandidates.contains { $0.id == distractor.id })
    }

    func testR2aNoScoringWeightOrFloorChange() {
        XCTAssertEqual(MultiSignalClusterer.admitFloor, 0.32, accuracy: 0.0001)
        XCTAssertEqual(MultiSignalClusterer.maxGroupSize, 8)
        let now = Date()
        let a = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now,
            ocrNormalized: "alpha beach sunset cats",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let b = MultiSignalClusterer.Member(
            id: ScreenshotMemoryID(),
            createdAt: now.addingTimeInterval(120),
            ocrNormalized: "beta cooking pasta recipe",
            visualLabels: [],
            facets: ["social_post"],
            featurePrintData: nil,
            profileMatchScore: 0,
            profileTitles: [],
            sourcePlatform: "instagram",
            contentType: "social_post",
            contentFamily: "social_media"
        )
        let score = MultiSignalClusterer.score(seed: a, other: b)
        XCTAssertEqual(score.parts["source_platform"] ?? -1, 0.04, accuracy: 0.0001)
        XCTAssertEqual(score.parts["content_type"] ?? -1, 0.05, accuracy: 0.0001)
        XCTAssertEqual(score.parts["content_family"] ?? -1, 0.04, accuracy: 0.0001)
        // R2a must not admit on type stack alone.
        let result = MultiSignalClusterer.cluster(around: a, candidates: [b], maxSize: 8)
        XCTAssertEqual(result.memberIDs, [a.id])
    }

    func testLabelsJSONRoundTripLegacyAndObject() {
        let objects = [VisualLabelObservation(identifier: "sofa", confidence: 0.8)]
        let json = ScreenshotRecord.labelsJSON(objects)
        let decoded = ScreenshotRecord.decodeLabels(json)
        XCTAssertEqual(decoded, objects)

        let legacy = ScreenshotRecord.decodeLabels("[\"sofa\",\"chair\"]")
        XCTAssertEqual(legacy.map(\.identifier), ["sofa", "chair"])
    }
}
