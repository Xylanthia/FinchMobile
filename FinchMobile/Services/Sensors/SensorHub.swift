import Foundation
import Observation

/// Sensor hub for non-BLE modalities. On stock iPhone, SDR/acoustic/optical run in Research Mode as synthetic streams.
@Observable
final class SensorHub {
    var sdrEnabled: Bool = false
    var acousticEnabled: Bool = false
    var opticalEnabled: Bool = false
    var uwbEnabled: Bool = false
    var lastClassification: String = "Sensors idle"
    var researchMode: Bool = false

    private weak var fusion: TrackFusionEngine?
    private weak var forensic: ForensicLogger?
    private var timer: Timer?

    func bind(fusion: TrackFusionEngine, forensic: ForensicLogger) {
        self.fusion = fusion
        self.forensic = forensic
    }

    func applyResearchMode(_ on: Bool) {
        researchMode = on
        forensic?.researchMode = on
        forensic?.record(category: "sensor", summary: on ? "Research Mode ON" : "Research Mode OFF")
        if on {
            startSyntheticPulse()
        } else {
            timer?.invalidate()
            timer = nil
            sdrEnabled = false
            acousticEnabled = false
            opticalEnabled = false
        }
    }

    func toggleSDR(_ on: Bool) {
        sdrEnabled = on
        lastClassification = on
            ? (researchMode ? "SDR: research PSD stream (simulated)" : "SDR: connect HackRF/RTLSDR over Lightning — not paired")
            : "SDR off"
        forensic?.record(category: "sensor", summary: lastClassification)
    }

    func toggleAcoustic(_ on: Bool) {
        acousticEnabled = on
        lastClassification = on
            ? (researchMode ? "Acoustic: motor/ringtone classifier (simulated)" : "Acoustic: enable mic permission + Research Mode for lab injects")
            : "Acoustic off"
        forensic?.record(category: "sensor", summary: lastClassification)
    }

    func toggleOptical(_ on: Bool) {
        opticalEnabled = on
        lastClassification = on
            ? (researchMode ? "Optical: YOLO-class object hints (simulated)" : "Optical: use AR tab camera overlay for bearings")
            : "Optical off"
        forensic?.record(category: "sensor", summary: lastClassification)
    }

    private func startSyntheticPulse() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self, self.researchMode else { return }
            let classes: [RFDeviceClass] = [.drone, .flipper, .airtag, .hackrf]
            let pick = classes.randomElement() ?? .unknown
            _ = self.fusion?.injectSynthetic(
                name: "SYN-\(pick.rawValue.uppercased())",
                deviceClass: pick,
                threatBoost: 1
            )
            self.lastClassification = "Research pulse: \(pick.rawValue)"
        }
    }
}
