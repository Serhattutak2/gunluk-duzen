// Web arayüzü ile iPhone özellikleri arasındaki köprü:
// widget verisi, kilit ekranı canlı sayacı (Live Activity) ve Apple Sağlık.
import Foundation
import Capacitor
import WidgetKit
import HealthKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@objc(BahcePlugin)
public class BahcePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "BahcePlugin"
    public let jsName = "Bahce"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "sync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pull", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startFocus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopFocus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "healthAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "healthAuth", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "healthAddWater", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "healthSteps", returnType: CAPPluginReturnPromise)
    ]

    private let health = HKHealthStore()

    // MARK: Widget

    @objc func sync(_ call: CAPPluginCall) {
        guard let json = call.getString("json"), let data = json.data(using: .utf8),
              let s = try? JSONDecoder().decode(BahceSnapshot.self, from: data) else {
            call.reject("Geçersiz veri")
            return
        }
        Bahce.saveSnapshot(s)
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    @objc func pull(_ call: CAPPluginCall) {
        let p = Bahce.pending()
        Bahce.clearPending()
        call.resolve(["water": p])
    }

    // MARK: Canlı odak sayacı

    @objc func startFocus(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let name = call.getString("name") ?? "Odak"
            let color = call.getString("color") ?? "#3F9A52"
            let target = call.getInt("target") ?? 0
            let level = call.getInt("level") ?? 1
            let start = Date(timeIntervalSince1970: (call.getDouble("start") ?? Date().timeIntervalSince1970 * 1000) / 1000)
            let end = Date(timeIntervalSince1970: (call.getDouble("end") ?? 0) / 1000)
            Task {
                for a in Activity<FocusAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                guard ActivityAuthorizationInfo().areActivitiesEnabled, end > Date() else {
                    call.resolve(["ok": false])
                    return
                }
                let attrs = FocusAttributes(name: name, color: color, targetMin: target, level: level)
                let state = FocusAttributes.ContentState(start: start, end: end)
                do {
                    _ = try Activity.request(attributes: attrs,
                                             content: ActivityContent(state: state, staleDate: end.addingTimeInterval(120)),
                                             pushType: nil)
                    call.resolve(["ok": true])
                } catch {
                    call.resolve(["ok": false, "error": error.localizedDescription])
                }
            }
            return
        }
        #endif
        call.resolve(["ok": false])
    }

    @objc func stopFocus(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                for a in Activity<FocusAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                call.resolve()
            }
            return
        }
        #endif
        call.resolve()
    }

    // MARK: Apple Sağlık

    @objc func healthAvailable(_ call: CAPPluginCall) {
        call.resolve(["ok": HKHealthStore.isHealthDataAvailable()])
    }

    @objc func healthAuth(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let water = HKObjectType.quantityType(forIdentifier: .dietaryWater),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            call.resolve(["ok": false])
            return
        }
        health.requestAuthorization(toShare: [water], read: [steps]) { ok, _ in
            call.resolve(["ok": ok])
        }
    }

    @objc func healthAddWater(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            call.resolve(["ok": false])
            return
        }
        let ml = call.getDouble("ml") ?? 250
        let now = Date()
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: now, end: now)
        health.save(sample) { ok, _ in call.resolve(["ok": ok]) }
    }

    @objc func healthSteps(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            call.resolve(["steps": 0])
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, result, _ in
            let n = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            call.resolve(["steps": Int(n)])
        }
        health.execute(q)
    }
}
