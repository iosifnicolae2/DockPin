/// A monitor as the graphics hardware (IOKit) reports it. Virtual displays, which apps make
/// (screen recorders, test displays), have none behind them.
public struct HardwareScreen: Equatable {
    public var vendor: UInt32
    public var serial: UInt32?

    public init(vendor: UInt32, serial: UInt32?) {
        self.vendor = vendor
        self.serial = serial
    }

    /// A display is real when it's built in or the hardware lists its vendor (and its serial, when it reports one).
    /// No hardware listed at all means it couldn't be read: then every display counts as real.
    public static func isReal(builtIn: Bool, vendor: UInt32, serial: UInt32, among screens: [HardwareScreen]) -> Bool {
        builtIn || screens.isEmpty || screens.contains { $0.vendor == vendor && ($0.serial == nil || $0.serial == serial) }
    }
}
