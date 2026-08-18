import Testing
@testable import FourStream

struct ElapsedTimeTests {
    @Test
    func formatsBelowOneHourAsMinutesAndSeconds() {
        let start = ContinuousClock().now
        #expect(ElapsedTime.formatted(from: start, to: start) == "00:00")
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(5))) == "00:05")
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(90))) == "01:30")
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(3599))) == "59:59")
        #expect(ElapsedTime.formatted(duration: .seconds(0)) == "00:00")
        #expect(ElapsedTime.formatted(duration: .seconds(59)) == "00:59")
    }

    @Test
    func formatsOneHourAndAboveWithHours() {
        let start = ContinuousClock().now
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(3600))) == "01:00:00")
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(3661))) == "01:01:01")
        #expect(ElapsedTime.formatted(duration: .seconds(3600)) == "01:00:00")
        #expect(ElapsedTime.formatted(duration: .seconds(12_345)) == "03:25:45")
    }

    @Test
    func formatsDurationsBeyondTwentyFourHours() {
        let start = ContinuousClock().now
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(86_400))) == "24:00:00")
        #expect(ElapsedTime.formatted(from: start, to: start.advanced(by: .seconds(90_000))) == "25:00:00")
        #expect(ElapsedTime.formatted(duration: .seconds(86_400)) == "24:00:00")
        #expect(ElapsedTime.formatted(duration: .seconds(100_000)) == "27:46:40")
    }

    @Test
    func durationIsTakenFromMonotonicInstantsNotTheWallClock() {
        let start = ContinuousClock().now
        let end = start.advanced(by: .seconds(90))
        #expect(end - start == Duration.seconds(90))
        #expect(ElapsedTime.formatted(from: start, to: end) == "01:30")
        #expect(ElapsedTime.formatted(duration: end - start) == "01:30")
    }
}
