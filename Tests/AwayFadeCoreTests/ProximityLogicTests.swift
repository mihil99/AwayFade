import Testing
@testable import AwayFadeCore

struct ProximityLogicTests {
    private let bands = ProximityBand.defaults

    @Test func boundariesFallBetweenAnchors() {
        #expect(ProximityLogic.boundaries(for: bands) == [-49, -63, -77])
    }

    @Test func assignsAllFourBands() {
        #expect(ProximityLogic.idealBand(for: -40, bands: bands) == 0)
        #expect(ProximityLogic.idealBand(for: -55, bands: bands) == 1)
        #expect(ProximityLogic.idealBand(for: -70, bands: bands) == 2)
        #expect(ProximityLogic.idealBand(for: -90, bands: bands) == 3)
    }

    @Test func hysteresisKeepsCurrentBandNearBoundary() {
        #expect(ProximityLogic.hystereticBand(for: -50, currentBand: 0, bands: bands, margin: 2.5) == 0)
        #expect(ProximityLogic.hystereticBand(for: -53, currentBand: 0, bands: bands, margin: 2.5) == 1)
        #expect(ProximityLogic.hystereticBand(for: -48, currentBand: 1, bands: bands, margin: 2.5) == 1)
        #expect(ProximityLogic.hystereticBand(for: -46, currentBand: 1, bands: bands, margin: 2.5) == 0)
    }

    @Test func medianRejectsSingleOutlier() {
        #expect(ProximityLogic.median([-60, -61, -30, -62, -60]) == -60)
    }

    @Test func anchorValidationPreservesOrdering() {
        #expect(ProximityLogic.validAnchor(-60, at: 1, in: bands))
        #expect(!ProximityLogic.validAnchor(-40, at: 1, in: bands))
        #expect(!ProximityLogic.validAnchor(-69, at: 1, in: bands))
    }

    @Test func simulationSliderRunsFromNearToFar() {
        #expect(ProximityLogic.simulationSliderValue(forRSSI: -30) == 30)
        #expect(ProximityLogic.simulationSliderValue(forRSSI: -95) == 95)
        #expect(ProximityLogic.rssi(forSimulationSliderValue: 30) == -30)
        #expect(ProximityLogic.rssi(forSimulationSliderValue: 95) == -95)
    }

    @Test func volumeCurvePassesThroughControlPoints() {
        for band in bands {
            #expect(ProximityLogic.volumeMultiplier(for: band.anchorRSSI, bands: bands) == band.volumeMultiplier)
        }
    }

    @Test func volumeCurveSmoothlyInterpolatesAndClamps() {
        #expect(ProximityLogic.volumeMultiplier(for: -30, bands: bands) == 1)
        #expect(ProximityLogic.volumeMultiplier(for: -100, bands: bands) == 0.42)
        #expect(abs(ProximityLogic.volumeMultiplier(for: -49, bands: bands) - 0.91) < 0.0001)
        #expect(abs(ProximityLogic.volumeMultiplier(for: -63, bands: bands) - 0.72) < 0.0001)
    }

    @Test func twoPointCurveContinuesFlatAfterRightmostPoint() {
        let points = [bands[0], bands[3]]
        #expect(ProximityLogic.volumeMultiplier(for: -84, bands: points) == 0.42)
        #expect(ProximityLogic.volumeMultiplier(for: -95, bands: points) == 0.42)
        #expect(ProximityLogic.volumeMultiplier(for: -120, bands: points) == 0.42)
    }

    @Test func removingPointUsesStableIdentityAndStopsAtTwo() {
        let removedID = bands[1].id
        let three = ProximityLogic.removingPoint(id: removedID, from: bands)
        #expect(three?.count == 3)
        #expect(three?.contains(where: { $0.id == removedID }) == false)

        let two = ProximityLogic.removingPoint(id: bands[2].id, from: three ?? [])
        #expect(two?.count == 2)
        #expect(ProximityLogic.removingPoint(id: bands[0].id, from: two ?? []) == nil)
    }
}
