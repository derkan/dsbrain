//
// SMC.swift
//
//

import Foundation
import IOKit

enum SMCDataType: String {
    case UI8 = "ui8 "
    case UI16 = "ui16"
    case UI32 = "ui32"
    case SP1E = "sp1e"
    case SP3C = "sp3c"
    case SP4B = "sp4b"
    case SP5A = "sp5a"
    case SPA5 = "spa5"
    case SP69 = "sp69"
    case SP78 = "sp78"
    case SP87 = "sp87"
    case SP96 = "sp96"
    case SPB4 = "spb4"
    case SPF0 = "spf0"
    case FLT = "flt "
    case FPE2 = "fpe2"
    case FP2E = "fp2e"
    case FDS = "{fds"
}

enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
    case readPLimit = 11
    case readVers = 12
}

public enum FanMode: Int, Codable {
    case automatic = 0
    case forced = 1
    case auto3 = 3

    public var isAutomatic: Bool {
        self == .automatic || self == .auto3
    }
}

struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)

    init(_ key: String) {
        self.key = key
    }
}

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { sum, character in
            sum << 8 | UInt32(character)
        }
    }

    func toString() -> String {
        String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
            String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
            String(describing: UnicodeScalar(self >> 8 & 0xff)!) +
            String(describing: UnicodeScalar(self & 0xff)!)
    }
}

extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

extension Int {
    init(fromFPE2 bytes: (UInt8, UInt8)) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
}

extension Float {
    init?(_ bytes: [UInt8]) {
        if bytes.count < 4 { return nil }
        self = bytes.withUnsafeBytes {
            $0.load(fromByteOffset: 0, as: Self.self)
        }
    }

    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }
}

public final class SMC {
    public static let shared = SMC()
    private var conn: io_connect_t = 0
    private var _fanModeKeyIsLower: Bool?

    public init() {
        var iterator: io_iterator_t = 0
        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)
        guard result == kIOReturnSuccess else { return }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }

        let openResult = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        if openResult != kIOReturnSuccess {
            conn = 0
        }
    }

    deinit {
        _ = close()
    }

    public func close() -> kern_return_t {
        if conn != 0 {
            let res = IOServiceClose(conn)
            conn = 0
            return res
        }
        return kIOReturnSuccess
    }

    public var isOpen: Bool { conn != 0 }

    public func getValue(_ key: String) -> Double? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess else { return nil }

        guard val.dataSize > 0 else { return nil }

        if val.bytes.first(where: { $0 != 0 }) == nil,
           val.key != "FS! ",
           !val.key.hasSuffix("Md"),
           !val.key.hasSuffix("md")
        {
            return nil
        }

        switch val.dataType {
        case SMCDataType.UI8.rawValue:
            return Double(val.bytes[0])
        case SMCDataType.UI16.rawValue:
            return Double(UInt16(bytes: (val.bytes[0], val.bytes[1])))
        case SMCDataType.UI32.rawValue:
            return Double(UInt32(bytes: (val.bytes[0], val.bytes[1], val.bytes[2], val.bytes[3])))
        case SMCDataType.SP1E.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 16384
        case SMCDataType.SP3C.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 4096
        case SMCDataType.SP4B.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 2048
        case SMCDataType.SP5A.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 1024
        case SMCDataType.SP69.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 512
        case SMCDataType.SP78.rawValue:
            let intValue = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
            return intValue / 256
        case SMCDataType.SP87.rawValue:
            let intValue = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
            return intValue / 128
        case SMCDataType.SP96.rawValue:
            let intValue = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
            return intValue / 64
        case SMCDataType.SPA5.rawValue:
            let result = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
            return result / 32
        case SMCDataType.SPB4.rawValue:
            let intValue = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
            return intValue / 16
        case SMCDataType.SPF0.rawValue:
            return Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
        case SMCDataType.FLT.rawValue:
            if let value = Float(val.bytes) {
                return Double(value)
            }
            return nil
        case SMCDataType.FPE2.rawValue:
            return Double(Int(fromFPE2: (val.bytes[0], val.bytes[1])))
        default:
            return nil
        }
    }

    public func getStringValue(_ key: String) -> String? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }
        guard val.bytes.first(where: { $0 != 0 }) != nil else { return nil }

        guard val.dataType == SMCDataType.FDS.rawValue else { return nil }

        let chars = (4...15).compactMap { idx -> String? in
            guard idx < val.bytes.count else { return nil }
            return String(UnicodeScalar(val.bytes[idx]))
        }
        return chars.joined().trimmingCharacters(in: .whitespaces)
    }

    public func fanModeKey(_ id: Int) -> String {
        #if arch(arm64)
        if _fanModeKeyIsLower == nil {
            var probe = SMCVal_t("F0md")
            _fanModeKeyIsLower = read(&probe) == kIOReturnSuccess && probe.dataSize > 0
        }
        return _fanModeKeyIsLower == true ? "F\(id)md" : "F\(id)Md"
        #else
        return "F\(id)Md"
        #endif
    }

    public func setFanMode(_ id: Int, mode: FanMode) -> Bool {
        #if arch(arm64)
        if mode == .forced {
            return unlockFanControl(fanId: id)
        }

        let modeKey = fanModeKey(id)
        let targetKey = "F\(id)Tg"

        if getValue(modeKey) != nil {
            var modeVal = SMCVal_t(modeKey)
            guard read(&modeVal) == kIOReturnSuccess else { return false }
            if modeVal.bytes[0] != 0 {
                modeVal.bytes[0] = 0
                if !writeWithRetry(modeVal) { return false }
            }
        }

        var targetValue = SMCVal_t(targetKey)
        guard read(&targetValue) == kIOReturnSuccess else { return false }
        let bytes = Float(0).bytes
        targetValue.bytes[0] = bytes[0]
        targetValue.bytes[1] = bytes[1]
        targetValue.bytes[2] = bytes[2]
        targetValue.bytes[3] = bytes[3]
        return writeWithRetry(targetValue)
        #else
        if getValue("F\(id)Md") != nil {
            var value = SMCVal_t("F\(id)Md")
            guard read(&value) == kIOReturnSuccess else { return false }
            value.bytes = Array(repeating: 0, count: 32)
            value.bytes[0] = UInt8(mode.rawValue)
            guard write(value) == kIOReturnSuccess else { return false }
        }

        let fansMode = Int(getValue("FS! ") ?? 0)
        var newMode: UInt8 = 0

        if fansMode == 0 && id == 0 && mode == .forced { newMode = 1 }
        else if fansMode == 0 && id == 1 && mode == .forced { newMode = 2 }
        else if fansMode == 1 && id == 0 && mode == .automatic { newMode = 0 }
        else if fansMode == 1 && id == 1 && mode == .forced { newMode = 3 }
        else if fansMode == 2 && id == 1 && mode == .automatic { newMode = 0 }
        else if fansMode == 2 && id == 0 && mode == .forced { newMode = 3 }
        else if fansMode == 3 && id == 0 && mode == .automatic { newMode = 2 }
        else if fansMode == 3 && id == 1 && mode == .automatic { newMode = 1 }

        if fansMode == Int(newMode) { return true }

        var value = SMCVal_t("FS! ")
        guard read(&value) == kIOReturnSuccess else { return false }
        value.bytes = Array(repeating: 0, count: 32)
        value.bytes[1] = newMode
        return write(value) == kIOReturnSuccess
        #endif
    }

    public func setFanSpeed(_ id: Int, speed: Int) -> Bool {
        guard let maxSpeed = getValue("F\(id)Mx") else { return false }
        let targetSpeed = min(speed, Int(maxSpeed))

        #if arch(arm64)
        var modeVal = SMCVal_t(fanModeKey(id))
        guard read(&modeVal) == kIOReturnSuccess else { return false }
        if modeVal.bytes[0] != 1 {
            if !unlockFanControl(fanId: id) { return false }
        }
        #endif

        var value = SMCVal_t("F\(id)Tg")
        guard read(&value) == kIOReturnSuccess else { return false }

        if value.dataType == "flt " {
            let bytes = Float(targetSpeed).bytes
            value.bytes[0] = bytes[0]
            value.bytes[1] = bytes[1]
            value.bytes[2] = bytes[2]
            value.bytes[3] = bytes[3]
        } else if value.dataType == "fpe2" {
            value.bytes[0] = UInt8(targetSpeed >> 6)
            value.bytes[1] = UInt8((targetSpeed << 2) ^ ((targetSpeed >> 6) << 8))
            value.bytes[2] = 0
            value.bytes[3] = 0
        }

        #if arch(arm64)
        return writeWithRetry(value)
        #else
        return write(value) == kIOReturnSuccess
        #endif
    }

    #if arch(arm64)
    private func smcError(_ operation: String, key: String, result: kern_return_t) -> String {
        let errorDesc = String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown error"
        return "[\(key)] \(operation) failed: \(errorDesc) (0x\(String(result, radix: 16)))"
    }

    private func writeWithRetry(_ value: SMCVal_t, maxAttempts: Int = 10, delayMicros: UInt32 = 50_000) -> Bool {
        var lastResult: kern_return_t = kIOReturnSuccess
        for _ in 0..<maxAttempts {
            lastResult = write(value)
            if lastResult == kIOReturnSuccess {
                return true
            }
            usleep(delayMicros)
        }
        print(smcError("write", key: value.key, result: lastResult))
        return false
    }

    private func unlockFanControl(fanId: Int) -> Bool {
        let modeKey = fanModeKey(fanId)
        var modeVal = SMCVal_t(modeKey)
        guard read(&modeVal) == kIOReturnSuccess else { return false }
        modeVal.bytes[0] = 1
        if write(modeVal) == kIOReturnSuccess {
            return true
        }

        var ftstVal = SMCVal_t("Ftst")
        guard read(&ftstVal) == kIOReturnSuccess, ftstVal.dataSize > 0 else {
            return false
        }

        if ftstVal.bytes[0] == 1 {
            return retryModeWrite(fanId: fanId, maxAttempts: 20)
        }

        ftstVal.bytes[0] = 1
        if !writeWithRetry(ftstVal, maxAttempts: 100) {
            return false
        }

        usleep(3_000_000)
        return retryModeWrite(fanId: fanId, maxAttempts: 300)
    }

    private func retryModeWrite(fanId: Int, maxAttempts: Int) -> Bool {
        let modeKey = fanModeKey(fanId)
        var modeVal = SMCVal_t(modeKey)
        guard read(&modeVal) == kIOReturnSuccess else { return false }
        modeVal.bytes[0] = 1
        return writeWithRetry(modeVal, maxAttempts: maxAttempts, delayMicros: 100_000)
    }
    #endif

    public func resetFanControl() -> Bool {
        var success = true
        var hasFtst = false
        var ftstVal = SMCVal_t("Ftst")

        #if arch(arm64)
        let ftstReadResult = read(&ftstVal)
        hasFtst = ftstReadResult == kIOReturnSuccess && ftstVal.dataSize > 0
        if hasFtst, ftstVal.bytes[0] != 1 {
            ftstVal.bytes[0] = 1
            if !writeWithRetry(ftstVal, maxAttempts: 100) {
                print("Failed to unlock Ftst for reset")
            } else {
                usleep(1_000_000)
            }
        }
        #endif

        guard let count = getValue("FNum") else { return false }
        for i in 0..<Int(count) {
            if !setFanMode(i, mode: .automatic) {
                success = false
            }
        }

        #if arch(arm64)
        if hasFtst {
            ftstVal.bytes[0] = 0
            if !writeWithRetry(ftstVal, maxAttempts: 100) {
                success = false
            }
        }
        #endif

        return success
    }

    private func read(_ value: UnsafeMutablePointer<SMCVal_t>) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        input.key = FourCharCode(fromString: value.pointee.key)
        input.data8 = SMCKeys.readKeyInfo.rawValue

        var result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        value.pointee.dataSize = UInt32(output.keyInfo.dataSize)
        value.pointee.dataType = output.keyInfo.dataType.toString()
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue

        result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        memcpy(&value.pointee.bytes, &output.bytes, Int(value.pointee.dataSize))
        return kIOReturnSuccess
    }

    private func write(_ value: SMCVal_t) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        input.key = FourCharCode(fromString: value.key)
        input.data8 = SMCKeys.writeBytes.rawValue
        input.keyInfo.dataSize = IOByteCount32(value.dataSize)
        input.bytes = (
            value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3], value.bytes[4], value.bytes[5],
            value.bytes[6], value.bytes[7], value.bytes[8], value.bytes[9], value.bytes[10], value.bytes[11],
            value.bytes[12], value.bytes[13], value.bytes[14], value.bytes[15], value.bytes[16], value.bytes[17],
            value.bytes[18], value.bytes[19], value.bytes[20], value.bytes[21], value.bytes[22], value.bytes[23],
            value.bytes[24], value.bytes[25], value.bytes[26], value.bytes[27], value.bytes[28], value.bytes[29],
            value.bytes[30], value.bytes[31]
        )

        let result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }
        return output.result == 0x00 ? kIOReturnSuccess : kIOReturnError
    }

    private func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        guard conn != 0 else { return kIOReturnNotOpen }
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }
}
