import Foundation
import Testing
@testable import WizKit

@Suite struct BrightnessTests {
    @Test func dimmerLeavesAnOffBulbOff() {
        #expect(Brightness.relative(isOn: false, current: 60, delta: -10) == nil)
    }

    @Test func brighterTurnsAnOffBulbOnAtTheStep() {
        #expect(Brightness.relative(isOn: false, current: 80, delta: 20) == 20)
    }

    @Test func dimmingStopsAtTheBulbFloor() {
        #expect(Brightness.relative(isOn: true, current: 15, delta: -20) == 10)
        #expect(Brightness.relative(isOn: true, current: 95, delta: 20) == 100)
    }
}

@Suite struct PilotChangeTests {
    @Test func offWinsOverEarlierChanges() {
        var change = PilotChange(on: true, brightness: 40, mode: .white(kelvin: 3000))
        change.merge(.off)
        #expect(change.params as NSDictionary == ["state": false])
    }

    @Test func changeAfterOffTurnsBackOn() {
        var change = PilotChange.off
        change.merge(PilotChange(on: true, brightness: 5))
        #expect(change.params as NSDictionary == ["state": true, "dimming": 10])
    }

    @Test func newModeReplacesOldModeAndDropsSceneSpeed() {
        var change = PilotChange(on: true, mode: .scene(id: 5), speed: 150)
        change.merge(PilotChange(on: true, mode: .color(RGB(255, 0, 0))))
        #expect(change.params as NSDictionary == ["state": true, "r": 255, "g": 0, "b": 0])
    }

    @Test func outOfRangeValuesAreClamped() {
        let change = PilotChange(on: true, brightness: 150, mode: .white(kelvin: 9000), speed: 999)
        #expect(change.params as NSDictionary == ["state": true, "dimming": 100, "temp": 6500, "speed": 200])
    }
}

@Suite struct PilotParsingTests {
    @Test func sceneWinsOverLeftoverTemperature() {
        let state = BulbState(pilot: ["state": true, "dimming": 50, "sceneId": 5, "temp": 2700, "speed": 120])
        #expect(state?.mode == .scene(id: 5))
        #expect(state?.speed == 120)
    }

    @Test func colorModeWhenNoSceneOrTemperature() {
        let state = BulbState(pilot: ["state": true, "dimming": 75, "sceneId": 0, "r": 255, "g": 127, "b": 80, "c": 0, "w": 0])
        #expect(state?.mode == .color(RGB(255, 127, 80)))
        #expect(Catalog.describe(state?.mode) == "Coral")
    }

    @Test func whiteMode() {
        let state = BulbState(pilot: ["state": false, "dimming": 75, "sceneId": 0, "temp": 3000])
        #expect(state?.isOn == false)
        #expect(state?.mode == .white(kelvin: 3000))
        #expect(Catalog.describe(state?.mode) == "Soft white")
    }

    @Test func missingStateIsRejected() {
        #expect(BulbState(pilot: ["dimming": 50]) == nil)
    }
}

@Suite struct ReplyParsingTests {
    /// Real getPilot reply shape from firmware 1.35: `src` holds raw bytes.
    private func reply(src: [UInt8]) -> Data {
        Data(#"{"method":"getPilot","env":"pro","result":{"mac":"d8a0118e5ea9","rssi":-68,"src":""#.utf8)
            + Data(src)
            + Data(#"","state":true,"sceneId":0,"temp":3000,"dimming":56}}"#.utf8)
    }

    @Test(arguments: [
        [0x38, 0xC3, 0x28, 0x3F],   // invalid UTF-8
        [0x01, 0x22, 0x5C, 0x3F],   // control byte, quote, backslash
        [0x50, 0x41, 0x42, 0x3F],   // clean
    ])
    func garbageInSrcStillParses(src: [UInt8]) throws {
        let parsed = try #require(WizClient.parseReply(reply(src: src)))
        let result = try #require(parsed["result"] as? [String: Any])
        let state = try #require(BulbState(pilot: result))
        #expect(state.mode == .white(kelvin: 3000))
        #expect(state.brightness == 56)
    }
}
