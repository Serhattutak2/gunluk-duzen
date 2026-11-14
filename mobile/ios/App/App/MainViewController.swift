import UIKit
import Capacitor

/// Uygulamanın kendi yerel eklentisini (Bahce) Capacitor'a tanıtır.
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(BahcePlugin())
    }
}
