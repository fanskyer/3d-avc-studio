import AVFoundation
import CoreVideo
import Foundation
import VideoToolbox

private let exitSkippedNoMVC: Int32 = 20
private let exitUsage: Int32 = 64
private let exitUnavailable: Int32 = 78

struct ConvertOptions {
    var input: URL
    var output: URL
    var profile = "sony-3d-avc"
    var codec = "h265-vt"
    var deinterlace = "60"
    var bitrate = "12000k"
    var debugWorkDir: URL?
}

struct StackYUVOptions {
    var left: URL
    var right: URL
    var output: URL
    var width: Int
    var height: Int
    var frames: Int?
}

struct EncodeYUVOptions {
    var input: URL
    var output: URL
    var audioSource: URL?
    var width: Int
    var height: Int
    var fps = "30000/1001"
    var bitrate = "12000k"
    var frames: Int?
}

struct PIDProfile {
    let identifier: String
    let name: String
    let basePID: UInt16
    let dependentPID: UInt16

    static func sony3DAVC() -> PIDProfile {
        PIDProfile(
            identifier: "sony-3d-avc",
            name: "Sony 3D AVC / AVCHD 3D",
            basePID: 0x1011,
            dependentPID: 0x1012
        )
    }
}

struct PIDScanResult {
    var packetSize: Int
    var transportOffset: Int
    var basePackets: Int
    var dependentPackets: Int
    var totalPackets: Int
}

struct InterleaveResult {
    var baseAccessUnits: Int
    var dependentAccessUnits: Int
    var interleavedAccessUnits: Int
}

struct PipelinePaths {
    let baseH264: URL
    let dependentH264: URL
    let combinedMVC: URL
    let leftYUV: URL
    let rightYUV: URL
    let sbsYUV: URL
}

struct DecodeResult {
    let leftYUV: URL
    let rightYUV: URL
    let frames: Int?
}

struct H264Metadata {
    var width: Int
    var height: Int
    var fps: String?
    var profileIDC: Int
    var levelIDC: Int
}

struct NALUnit {
    let startCode: Data
    let payload: Data

    var complete: Data {
        var data = Data()
        data.append(startCode)
        data.append(payload)
        return data
    }
}

struct BitReader {
    let bytes: [UInt8]
    var bitOffset = 0

    var hasMoreBits: Bool {
        bitOffset < bytes.count * 8
    }

    mutating func readBit() throws -> Bool {
        try readBits(1) == 1
    }

    mutating func readBits(_ count: Int) throws -> UInt32 {
        guard count >= 0, count <= 32, bitOffset + count <= bytes.count * 8 else {
            throw EngineError.invalidH264("Unexpected end of bitstream.")
        }
        var value: UInt32 = 0
        for _ in 0..<count {
            let byteIndex = bitOffset / 8
            let bitIndex = 7 - (bitOffset % 8)
            value = (value << 1) | UInt32((bytes[byteIndex] >> bitIndex) & 1)
            bitOffset += 1
        }
        return value
    }

    mutating func readUE() throws -> UInt32 {
        var leadingZeroBits = 0
        while hasMoreBits {
            if try readBit() {
                break
            }
            leadingZeroBits += 1
            if leadingZeroBits > 31 {
                throw EngineError.invalidH264("Exp-Golomb value is too large.")
            }
        }
        if leadingZeroBits == 0 {
            return 0
        }
        let suffix = try readBits(leadingZeroBits)
        return (1 << UInt32(leadingZeroBits)) - 1 + suffix
    }

    mutating func readSE() throws -> Int {
        let codeNum = try Int(readUE())
        let value = (codeNum + 1) / 2
        return codeNum % 2 == 0 ? -value : value
    }
}

enum EngineError: Error, CustomStringConvertible {
    case usage(String)
    case unsupportedProfile(String)
    case invalidTransportStream
    case invalidH264(String)
    case missingSPS
    case decoderUnavailable(String)
    case noAccessUnits
    case io(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .unsupportedProfile(let profile): return "Unsupported camera profile: \(profile)"
        case .invalidTransportStream: return "Could not find MPEG-TS sync byte; expected .MTS/.M2TS transport stream."
        case .invalidH264(let message): return "Invalid H.264 stream: \(message)"
        case .missingSPS: return "Could not find an H.264 SPS NAL unit."
        case .decoderUnavailable(let message): return message
        case .noAccessUnits: return "No MVC access units found after transport stream demux."
        case .io(let message): return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage: return exitUsage
        case .unsupportedProfile: return exitUsage
        case .invalidTransportStream: return 1
        case .invalidH264: return 1
        case .missingSPS: return 1
        case .decoderUnavailable: return exitUnavailable
        case .noAccessUnits: return 1
        case .io: return 1
        }
    }
}

@main
struct Sony3DEngine {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                throw EngineError.usage(Self.usage)
            }

            switch command {
            case "convert":
                let options = try parseConvert(Array(arguments.dropFirst()))
                try convert(options)
            case "probe":
                let options = try parseProbe(Array(arguments.dropFirst()))
                try probe(options)
            case "stack-yuv":
                let options = try parseStackYUV(Array(arguments.dropFirst()))
                try stackYUV(options)
            case "encode-yuv":
                let options = try parseEncodeYUV(Array(arguments.dropFirst()))
                try encodeYUV(options)
            case "--capabilities", "capabilities":
                printCapabilities()
            case "--help", "-h", "help":
                print(Self.usage)
            default:
                throw EngineError.usage("Unknown command: \(command)\n\n\(Self.usage)")
            }
        } catch let error as EngineError {
            fputs("\(error.description)\n", stderr)
            exit(error.exitCode)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static var usage: String {
        """
        sony3dengine convert INPUT OUTPUT --profile sony-3d-avc --codec h265-vt --deinterlace 60 --bitrate 12000k [--debug-work-dir DIR]
        sony3dengine probe INPUT --profile sony-3d-avc
        sony3dengine stack-yuv LEFT.yuv RIGHT.yuv SBS.yuv --width W --height H [--frames N]
        sony3dengine encode-yuv SBS.yuv OUTPUT.mp4 --width W --height H [--fps 30000/1001] [--bitrate 12000k] [--frames N]
        sony3dengine capabilities
        """
    }

    private static func parseConvert(_ arguments: [String]) throws -> ConvertOptions {
        guard arguments.count >= 2 else {
            throw EngineError.usage(Self.usage)
        }

        var options = ConvertOptions(
            input: URL(fileURLWithPath: arguments[0]),
            output: URL(fileURLWithPath: arguments[1])
        )
        try parseFlags(Array(arguments.dropFirst(2))) { key, value in
            switch key {
            case "--profile": options.profile = value
            case "--codec": options.codec = value
            case "--deinterlace": options.deinterlace = value
            case "--bitrate": options.bitrate = value
            case "--debug-work-dir": options.debugWorkDir = URL(fileURLWithPath: value)
            default: throw EngineError.usage("Unknown option: \(key)")
            }
        }
        return options
    }

    private static func parseStackYUV(_ arguments: [String]) throws -> StackYUVOptions {
        guard arguments.count >= 3 else {
            throw EngineError.usage(Self.usage)
        }

        var width: Int?
        var height: Int?
        var frames: Int?
        try parseFlags(Array(arguments.dropFirst(3))) { key, value in
            switch key {
            case "--width": width = Int(value)
            case "--height": height = Int(value)
            case "--frames": frames = Int(value)
            default: throw EngineError.usage("Unknown option: \(key)")
            }
        }
        guard let width, let height, width > 0, height > 0, width % 2 == 0, height % 2 == 0 else {
            throw EngineError.usage("stack-yuv requires even positive --width and --height values.")
        }
        if let frames, frames <= 0 {
            throw EngineError.usage("--frames must be positive when provided.")
        }

        return StackYUVOptions(
            left: URL(fileURLWithPath: arguments[0]),
            right: URL(fileURLWithPath: arguments[1]),
            output: URL(fileURLWithPath: arguments[2]),
            width: width,
            height: height,
            frames: frames
        )
    }

    private static func parseEncodeYUV(_ arguments: [String]) throws -> EncodeYUVOptions {
        guard arguments.count >= 2 else {
            throw EngineError.usage(Self.usage)
        }

        var width: Int?
        var height: Int?
        var fps = "30000/1001"
        var bitrate = "12000k"
        var frames: Int?
        try parseFlags(Array(arguments.dropFirst(2))) { key, value in
            switch key {
            case "--width": width = Int(value)
            case "--height": height = Int(value)
            case "--fps": fps = value
            case "--bitrate": bitrate = value
            case "--frames": frames = Int(value)
            default: throw EngineError.usage("Unknown option: \(key)")
            }
        }
        guard let width, let height, width > 0, height > 0, width % 2 == 0, height % 2 == 0 else {
            throw EngineError.usage("encode-yuv requires even positive --width and --height values.")
        }
        if let frames, frames <= 0 {
            throw EngineError.usage("--frames must be positive when provided.")
        }

        return EncodeYUVOptions(
            input: URL(fileURLWithPath: arguments[0]),
            output: URL(fileURLWithPath: arguments[1]),
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            frames: frames
        )
    }

    private static func parseProbe(_ arguments: [String]) throws -> ConvertOptions {
        guard let input = arguments.first else {
            throw EngineError.usage(Self.usage)
        }

        var options = ConvertOptions(
            input: URL(fileURLWithPath: input),
            output: URL(fileURLWithPath: "/dev/null")
        )
        try parseFlags(Array(arguments.dropFirst())) { key, value in
            switch key {
            case "--profile": options.profile = value
            default: throw EngineError.usage("Unknown option: \(key)")
            }
        }
        return options
    }

    private static func parseFlags(_ flags: [String], apply: (String, String) throws -> Void) throws {
        var index = 0
        while index < flags.count {
            let key = flags[index]
            guard key.hasPrefix("--"), index + 1 < flags.count else {
                throw EngineError.usage("Missing value for option: \(key)")
            }
            try apply(key, flags[index + 1])
            index += 2
        }
    }

    private static func profile(for identifier: String) throws -> PIDProfile {
        switch identifier {
        case "sony-3d-avc", "sony-avchd-3d":
            return .sony3DAVC()
        default:
            throw EngineError.unsupportedProfile(identifier)
        }
    }

    private static func convert(_ options: ConvertOptions) throws {
        let profile = try profile(for: options.profile)
        print("Engine: native sony3dengine")
        print("Profile: \(profile.name)")
        print("Codec: \(options.codec), deinterlace: \(options.deinterlace), bitrate: \(options.bitrate)")

        let workDir = try makeWorkDirectory(options.debugWorkDir)
        let paths = pipelinePaths(in: workDir)
        defer { cleanupWorkDirectory(workDir, keep: options.debugWorkDir != nil) }

        print("Stage: extract transport streams")
        let result = try extractPIDStreams(
            input: options.input,
            baseOutput: paths.baseH264,
            dependentOutput: paths.dependentH264,
            basePID: profile.basePID,
            dependentPID: profile.dependentPID
        )
        printScan(result, profile: profile)

        guard result.basePackets > 0, result.dependentPackets > 0 else {
            print(
                "Skipped: no complete Sony 3D AVC MVC dependent view found. " +
                "PID counts: base 0x\(String(profile.basePID, radix: 16))=\(result.basePackets), " +
                "dependent 0x\(String(profile.dependentPID, radix: 16))=\(result.dependentPackets)."
            )
            cleanupWorkDirectory(workDir, keep: options.debugWorkDir != nil)
            exit(exitSkippedNoMVC)
        }

        print("Stage: parse H.264 metadata")
        let metadata = try parseH264Metadata(readFile(paths.baseH264))
        printMetadata(metadata)

        print("Stage: interleave MVC access units")
        let interleave = try interleaveMVC(
            baseInput: paths.baseH264,
            dependentInput: paths.dependentH264,
            combinedOutput: paths.combinedMVC
        )
        if interleave.baseAccessUnits != interleave.dependentAccessUnits {
            fputs(
                "Warning: base/dependent access unit count differs: \(interleave.baseAccessUnits) vs \(interleave.dependentAccessUnits)\n",
                stderr
            )
        }
        print("Interleaved \(interleave.interleavedAccessUnits) MVC access units.")
        if options.debugWorkDir != nil {
            print("Work directory: \(workDir.path)")
        }

        print("Stage: decode MVC views")
        let decoded = try decodeMVC(
            combinedInput: paths.combinedMVC,
            leftOutput: paths.leftYUV,
            rightOutput: paths.rightYUV,
            metadata: metadata
        )

        print("Stage: stack SBS YUV")
        try stackYUV(
            StackYUVOptions(
                left: decoded.leftYUV,
                right: decoded.rightYUV,
                output: paths.sbsYUV,
                width: metadata.width,
                height: metadata.height,
                frames: decoded.frames
            )
        )

        print("Stage: encode HEVC MP4")
        try encodeYUV(
            EncodeYUVOptions(
                input: paths.sbsYUV,
                output: options.output,
                audioSource: options.input,
                width: metadata.width * 2,
                height: metadata.height,
                fps: metadata.fps ?? "30000/1001",
                bitrate: options.bitrate,
                frames: decoded.frames
            )
        )
    }

    private static func probe(_ options: ConvertOptions) throws {
        let profile = try profile(for: options.profile)
        let workDir = try makeWorkDirectory(nil)
        defer { cleanupWorkDirectory(workDir, keep: false) }
        let baseH264 = workDir.appendingPathComponent("base.h264")
        let dependentH264 = workDir.appendingPathComponent("dependent.h264")
        let result = try extractPIDStreams(
            input: options.input,
            baseOutput: baseH264,
            dependentOutput: dependentH264,
            basePID: profile.basePID,
            dependentPID: profile.dependentPID
        )
        printScan(result, profile: profile)
        if result.basePackets > 0 {
            let metadata = try parseH264Metadata(readFile(baseH264))
            printMetadata(metadata)
        }
    }

    private static func printCapabilities() {
        let conversionComplete = decoderExecutable() != nil ? "true" : "false"
        print(
            """
            {
              "engine": "sony3dengine",
              "version": "0.2.1",
              "profiles": ["sony-3d-avc", "sony-avchd-3d"],
              "codecs": ["h265-vt"],
              "transportExtractionComplete": true,
              "h264MetadataComplete": true,
              "mvcInterleaveComplete": true,
              "sbsStackComplete": true,
              "hevcMuxComplete": true,
              "audioPassthroughMuxComplete": true,
              "pipelineOrchestrationComplete": true,
              "decoderBoundaryComplete": true,
              "externalDecoderContractComplete": true,
              "conversionComplete": \(conversionComplete)
            }
            """
        )
    }

    private static func printScan(_ result: PIDScanResult, profile: PIDProfile) {
        print("Transport packet size: \(result.packetSize), offset: \(result.transportOffset)")
        print("Scanned packets: \(result.totalPackets)")
        print("Base AVC PID 0x\(String(profile.basePID, radix: 16)): \(result.basePackets) packets")
        print("Dependent MVC PID 0x\(String(profile.dependentPID, radix: 16)): \(result.dependentPackets) packets")
    }

    private static func printMetadata(_ metadata: H264Metadata) {
        let fpsText = metadata.fps.map { ", fps: \($0)" } ?? ""
        print("Video: \(metadata.width)x\(metadata.height), profile_idc: \(metadata.profileIDC), level_idc: \(metadata.levelIDC)\(fpsText)")
    }

    private static func makeWorkDirectory(_ requested: URL?) throws -> URL {
        let directory: URL
        if let requested {
            directory = requested
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "sony3dengine-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw EngineError.io("Could not create work directory \(directory.path): \(error.localizedDescription)")
        }
        return directory
    }

    private static func cleanupWorkDirectory(_ directory: URL, keep: Bool) {
        guard !keep else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func pipelinePaths(in workDir: URL) -> PipelinePaths {
        PipelinePaths(
            baseH264: workDir.appendingPathComponent("base.h264"),
            dependentH264: workDir.appendingPathComponent("dependent.h264"),
            combinedMVC: workDir.appendingPathComponent("combined_mvc.h264"),
            leftYUV: workDir.appendingPathComponent("left.yuv"),
            rightYUV: workDir.appendingPathComponent("right.yuv"),
            sbsYUV: workDir.appendingPathComponent("sbs.yuv")
        )
    }

    private static func decodeMVC(
        combinedInput: URL,
        leftOutput: URL,
        rightOutput: URL,
        metadata: H264Metadata
    ) throws -> DecodeResult {
        guard let decoder = decoderExecutable() else {
            fflush(stdout)
            throw EngineError.decoderUnavailable(
                """
                Native pipeline is ready through MVC interleave, SBS stacking, and HEVC MP4 writing, but this open-source preview does not bundle an MVC decoder.
                Build locally with a legally usable decoder at Contents/Resources/Engine/mvcdecoder or pass --decoder-path during packaging.
                """
            )
        }

        try? FileManager.default.removeItem(at: leftOutput)
        try? FileManager.default.removeItem(at: rightOutput)
        let process = Process()
        process.executableURL = decoder
        process.arguments = [
            "decode",
            combinedInput.path,
            leftOutput.path,
            rightOutput.path,
            "--width",
            String(metadata.width),
            "--height",
            String(metadata.height)
        ]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EngineError.io("MVC decoder failed with exit code \(process.terminationStatus).")
        }

        let frameBytes = metadata.width * metadata.height * 3 / 2
        let leftBytes = fileSize(leftOutput)
        let rightBytes = fileSize(rightOutput)
        guard leftBytes >= frameBytes, rightBytes >= frameBytes else {
            throw EngineError.io("MVC decoder did not produce complete left/right YUV420p frames.")
        }
        guard leftBytes % frameBytes == 0, rightBytes % frameBytes == 0 else {
            throw EngineError.io("MVC decoder output size is not aligned to complete YUV420p frames.")
        }
        let frames = min(leftBytes / frameBytes, rightBytes / frameBytes)
        print("Decoded \(frames) MVC frame(s) to left/right YUV420p.")
        return DecodeResult(leftYUV: leftOutput, rightYUV: rightOutput, frames: frames)
    }

    private static func decoderExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let ignoreLocalDecoder = environment["SONY3D_DISABLE_LOCAL_DECODER"] == "1"
        if !ignoreLocalDecoder {
            if let override = environment["SONY3D_MVC_DECODER"], !override.isEmpty {
                let url = URL(fileURLWithPath: override)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }

            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appendingPathComponent("3D AVC Studio/mvcdecoder")
            if let applicationSupport,
               FileManager.default.fileExists(atPath: applicationSupport.path) {
                return applicationSupport
            }
        }

        let engineURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let bundled = engineURL.deletingLastPathComponent().appendingPathComponent("mvcdecoder")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private static func scanPIDs(input: URL, basePID: UInt16, dependentPID: UInt16) throws -> PIDScanResult {
        let nullURL = URL(fileURLWithPath: "/dev/null")
        return try extractPIDStreams(
            input: input,
            baseOutput: nullURL,
            dependentOutput: nullURL,
            basePID: basePID,
            dependentPID: dependentPID
        )
    }

    private static func extractPIDStreams(
        input: URL,
        baseOutput: URL,
        dependentOutput: URL,
        basePID: UInt16,
        dependentPID: UInt16
    ) throws -> PIDScanResult {
        guard let handle = try? FileHandle(forReadingFrom: input) else {
            throw EngineError.io("Could not open input: \(input.path)")
        }
        defer { try? handle.close() }

        guard let baseHandle = try? FileHandle(forWritingTo: preparedOutput(baseOutput)),
              let dependentHandle = try? FileHandle(forWritingTo: preparedOutput(dependentOutput)) else {
            throw EngineError.io("Could not open elementary stream outputs.")
        }
        defer {
            try? baseHandle.close()
            try? dependentHandle.close()
        }

        let first = handle.readData(ofLength: 192)
        let layout = try packetLayout(first)
        try handle.seek(toOffset: 0)

        var result = PIDScanResult(
            packetSize: layout.packetSize,
            transportOffset: layout.transportOffset,
            basePackets: 0,
            dependentPackets: 0,
            totalPackets: 0
        )

        while true {
            let chunk = handle.readData(ofLength: layout.packetSize)
            if chunk.count < layout.packetSize {
                break
            }
            result.totalPackets += 1
            let bytes = [UInt8](chunk)
            let offset = layout.transportOffset
            guard bytes.count >= offset + 188, bytes[offset] == 0x47 else {
                continue
            }
            let pid = UInt16(bytes[offset + 1] & 0x1f) << 8 | UInt16(bytes[offset + 2])
            guard pid == basePID || pid == dependentPID else {
                continue
            }
            let payloadUnitStart = (bytes[offset + 1] & 0x40) != 0
            let adaptation = (bytes[offset + 3] >> 4) & 0x03
            var position = offset + 4
            if adaptation == 2 || adaptation == 3 {
                guard position < offset + 188 else {
                    continue
                }
                position += 1 + Int(bytes[position])
            }
            guard (adaptation == 1 || adaptation == 3), position < offset + 188 else {
                continue
            }
            var payload = Data(bytes[position..<(offset + 188)])
            if payloadUnitStart {
                payload = stripPESHeader(payload)
            }
            guard !payload.isEmpty else {
                continue
            }
            if pid == basePID {
                result.basePackets += 1
                try baseHandle.write(contentsOf: payload)
            } else if pid == dependentPID {
                result.dependentPackets += 1
                try dependentHandle.write(contentsOf: payload)
            }
        }

        return result
    }

    private static func preparedOutput(_ url: URL) throws -> URL {
        if url.path != "/dev/null" {
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
    }

    private static func stripPESHeader(_ payload: Data) -> Data {
        let bytes = [UInt8](payload)
        guard bytes.count >= 9, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01 else {
            return payload
        }
        let streamID = bytes[3]
        let noOptionalHeader: Set<UInt8> = [0xbc, 0xbe, 0xbf, 0xf0, 0xf1, 0xff, 0xf2, 0xf8]
        guard !noOptionalHeader.contains(streamID) else {
            return payload
        }
        let start = 9 + Int(bytes[8])
        guard start < bytes.count else {
            return Data()
        }
        return payload.subdata(in: start..<bytes.count)
    }

    private static func interleaveMVC(
        baseInput: URL,
        dependentInput: URL,
        combinedOutput: URL
    ) throws -> InterleaveResult {
        let base = try groupBaseAccessUnits(readFile(baseInput))
        let dependent = try groupDependentAccessUnits(readFile(dependentInput))
        let count = min(base.count, dependent.count)
        guard count > 0 else {
            throw EngineError.noAccessUnits
        }

        try? FileManager.default.removeItem(at: combinedOutput)
        FileManager.default.createFile(atPath: combinedOutput.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: combinedOutput) else {
            throw EngineError.io("Could not open combined MVC output: \(combinedOutput.path)")
        }
        defer { try? handle.close() }

        for index in 0..<count {
            for nal in base[index] {
                try handle.write(contentsOf: nal)
            }
            for nal in dependent[index] {
                try handle.write(contentsOf: nal)
            }
        }

        return InterleaveResult(
            baseAccessUnits: base.count,
            dependentAccessUnits: dependent.count,
            interleavedAccessUnits: count
        )
    }

    private static func readFile(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw EngineError.io("Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    private static func stackYUV(_ options: StackYUVOptions) throws {
        let left = try readFile(options.left)
        let right = try readFile(options.right)
        let eyeFrameBytes = options.width * options.height * 3 / 2
        guard eyeFrameBytes > 0 else {
            throw EngineError.usage("Invalid frame size.")
        }
        let availableFrames = min(left.count / eyeFrameBytes, right.count / eyeFrameBytes)
        let frames = options.frames ?? availableFrames
        guard frames <= availableFrames else {
            throw EngineError.io(
                "Requested \(frames) frames, but only \(availableFrames) complete YUV420p frame(s) are available."
            )
        }

        try? FileManager.default.removeItem(at: options.output)
        FileManager.default.createFile(atPath: options.output.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: options.output) else {
            throw EngineError.io("Could not open SBS YUV output: \(options.output.path)")
        }
        defer { try? output.close() }

        for frame in 0..<frames {
            let start = frame * eyeFrameBytes
            let leftFrame = left.subdata(in: start..<(start + eyeFrameBytes))
            let rightFrame = right.subdata(in: start..<(start + eyeFrameBytes))
            try output.write(contentsOf: makeSBSFrame(left: leftFrame, right: rightFrame, width: options.width, height: options.height))
        }

        print("Stacked \(frames) YUV420p frame(s) into full side-by-side raw video.")
    }

    private static func makeSBSFrame(left: Data, right: Data, width: Int, height: Int) -> Data {
        let leftBytes = [UInt8](left)
        let rightBytes = [UInt8](right)
        var output = Data()
        output.reserveCapacity(width * height * 3)

        appendRows(
            output: &output,
            left: leftBytes,
            right: rightBytes,
            leftOffset: 0,
            rightOffset: 0,
            rows: height,
            rowBytes: width
        )

        let ySize = width * height
        let chromaRows = height / 2
        let chromaRowBytes = width / 2
        let uOffset = ySize
        appendRows(
            output: &output,
            left: leftBytes,
            right: rightBytes,
            leftOffset: uOffset,
            rightOffset: uOffset,
            rows: chromaRows,
            rowBytes: chromaRowBytes
        )

        let vOffset = ySize + (ySize / 4)
        appendRows(
            output: &output,
            left: leftBytes,
            right: rightBytes,
            leftOffset: vOffset,
            rightOffset: vOffset,
            rows: chromaRows,
            rowBytes: chromaRowBytes
        )

        return output
    }

    private static func appendRows(
        output: inout Data,
        left: [UInt8],
        right: [UInt8],
        leftOffset: Int,
        rightOffset: Int,
        rows: Int,
        rowBytes: Int
    ) {
        for row in 0..<rows {
            let leftStart = leftOffset + row * rowBytes
            let rightStart = rightOffset + row * rowBytes
            output.append(contentsOf: left[leftStart..<(leftStart + rowBytes)])
            output.append(contentsOf: right[rightStart..<(rightStart + rowBytes)])
        }
    }

    private static func parseH264Metadata(_ data: Data) throws -> H264Metadata {
        guard let sps = iterNALUnits(data).first(where: { nalType($0.payload) == 7 }) else {
            throw EngineError.missingSPS
        }
        guard sps.payload.count > 1 else {
            throw EngineError.invalidH264("SPS payload is empty.")
        }

        let rbsp = removeEmulationPreventionBytes(Array(sps.payload.dropFirst()))
        var reader = BitReader(bytes: rbsp)
        let profileIDC = try Int(reader.readBits(8))
        _ = try reader.readBits(8)
        let levelIDC = try Int(reader.readBits(8))
        _ = try reader.readUE()

        var chromaFormatIDC = 1
        var separateColourPlaneFlag = false
        let highProfiles = Set([100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135])
        if highProfiles.contains(profileIDC) {
            chromaFormatIDC = try Int(reader.readUE())
            if chromaFormatIDC == 3 {
                separateColourPlaneFlag = try reader.readBit()
            }
            _ = try reader.readUE()
            _ = try reader.readUE()
            _ = try reader.readBit()
            let scalingMatrixPresent = try reader.readBit()
            if scalingMatrixPresent {
                let count = chromaFormatIDC != 3 ? 8 : 12
                for index in 0..<count {
                    if try reader.readBit() {
                        try skipScalingList(&reader, size: index < 6 ? 16 : 64)
                    }
                }
            }
        }

        _ = try reader.readUE()
        let picOrderCntType = try reader.readUE()
        if picOrderCntType == 0 {
            _ = try reader.readUE()
        } else if picOrderCntType == 1 {
            _ = try reader.readBit()
            _ = try reader.readSE()
            _ = try reader.readSE()
            let cycleCount = try reader.readUE()
            for _ in 0..<cycleCount {
                _ = try reader.readSE()
            }
        }

        _ = try reader.readUE()
        _ = try reader.readBit()
        let picWidthInMbsMinus1 = try reader.readUE()
        let picHeightInMapUnitsMinus1 = try reader.readUE()
        let frameMbsOnlyFlag = try reader.readBit()
        if !frameMbsOnlyFlag {
            _ = try reader.readBit()
        }
        _ = try reader.readBit()

        var cropLeft = 0
        var cropRight = 0
        var cropTop = 0
        var cropBottom = 0
        if try reader.readBit() {
            cropLeft = try Int(reader.readUE())
            cropRight = try Int(reader.readUE())
            cropTop = try Int(reader.readUE())
            cropBottom = try Int(reader.readUE())
        }

        var fps: String?
        if reader.hasMoreBits, (try? reader.readBit()) == true {
            fps = try? parseVUITiming(&reader)
        }

        let frameMbsFactor = frameMbsOnlyFlag ? 1 : 2
        var width = Int(picWidthInMbsMinus1 + 1) * 16
        var height = Int(picHeightInMapUnitsMinus1 + 1) * 16 * frameMbsFactor
        let cropUnit = cropUnits(chromaFormatIDC: chromaFormatIDC, separateColourPlaneFlag: separateColourPlaneFlag, frameMbsOnlyFlag: frameMbsOnlyFlag)
        width -= (cropLeft + cropRight) * cropUnit.x
        height -= (cropTop + cropBottom) * cropUnit.y

        guard width > 0, height > 0 else {
            throw EngineError.invalidH264("SPS produced invalid dimensions \(width)x\(height).")
        }
        return H264Metadata(width: width, height: height, fps: fps, profileIDC: profileIDC, levelIDC: levelIDC)
    }

    private static func removeEmulationPreventionBytes(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var zeroCount = 0
        for byte in bytes {
            if zeroCount >= 2, byte == 0x03 {
                zeroCount = 0
                continue
            }
            output.append(byte)
            zeroCount = byte == 0 ? zeroCount + 1 : 0
        }
        return output
    }

    private static func skipScalingList(_ reader: inout BitReader, size: Int) throws {
        var lastScale = 8
        var nextScale = 8
        for _ in 0..<size {
            if nextScale != 0 {
                let deltaScale = try reader.readSE()
                nextScale = (lastScale + deltaScale + 256) % 256
            }
            lastScale = nextScale == 0 ? lastScale : nextScale
        }
    }

    private static func cropUnits(chromaFormatIDC: Int, separateColourPlaneFlag: Bool, frameMbsOnlyFlag: Bool) -> (x: Int, y: Int) {
        if chromaFormatIDC == 0 || separateColourPlaneFlag {
            return (1, frameMbsOnlyFlag ? 2 : 4)
        }
        if chromaFormatIDC == 1 {
            return (2, frameMbsOnlyFlag ? 2 : 4)
        }
        if chromaFormatIDC == 2 {
            return (2, frameMbsOnlyFlag ? 1 : 2)
        }
        return (1, frameMbsOnlyFlag ? 1 : 2)
    }

    private static func parseVUITiming(_ reader: inout BitReader) throws -> String? {
        let aspectRatioInfoPresent = try reader.readBit()
        if aspectRatioInfoPresent {
            let aspectRatioIDC = try reader.readBits(8)
            if aspectRatioIDC == 255 {
                _ = try reader.readBits(16)
                _ = try reader.readBits(16)
            }
        }

        if try reader.readBit() {
            _ = try reader.readBit()
        }

        if try reader.readBit() {
            _ = try reader.readBits(3)
            let colourDescriptionPresent = try reader.readBit()
            if colourDescriptionPresent {
                _ = try reader.readBits(8)
                _ = try reader.readBits(8)
                _ = try reader.readBits(8)
            }
        }

        if try reader.readBit() {
            _ = try reader.readUE()
            _ = try reader.readUE()
        }

        let timingInfoPresent = try reader.readBit()
        guard timingInfoPresent else {
            return nil
        }
        let numUnitsInTick = try reader.readBits(32)
        let timeScale = try reader.readBits(32)
        _ = try reader.readBit()
        guard numUnitsInTick > 0 else {
            return nil
        }
        var numerator = timeScale
        var denominator = numUnitsInTick * 2
        let divisor = gcd(numerator, denominator)
        numerator /= divisor
        denominator /= divisor
        return "\(numerator)/\(denominator)"
    }

    private static func gcd(_ a: UInt32, _ b: UInt32) -> UInt32 {
        var x = a
        var y = b
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return max(x, 1)
    }

    private static func encodeYUV(_ options: EncodeYUVOptions) throws {
        let raw = try readFile(options.input)
        let frameBytes = options.width * options.height * 3 / 2
        guard frameBytes > 0 else {
            throw EngineError.usage("Invalid raw YUV frame size.")
        }
        let availableFrames = raw.count / frameBytes
        let frames = options.frames ?? availableFrames
        guard frames > 0, frames <= availableFrames else {
            throw EngineError.io("Requested \(frames) frame(s), but only \(availableFrames) complete raw frame(s) are available.")
        }

        let outputDirectory = options.output.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: options.output)
        let videoOnlyOutput: URL
        if options.audioSource == nil {
            videoOnlyOutput = options.output
        } else {
            videoOnlyOutput = outputDirectory.appendingPathComponent(".3davc-video-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: videoOnlyOutput)
        }

        let writer = try AVAssetWriter(outputURL: videoOnlyOutput, fileType: .mp4)
        let bitrate = parseBitrate(options.bitrate)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: options.width,
            AVVideoHeightKey: options.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw EngineError.io("AVAssetWriter cannot add HEVC video input.")
        }
        writer.add(writerInput)

        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: options.width,
            kCVPixelBufferHeightKey as String: options.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelAttributes
        )

        guard writer.startWriting() else {
            throw EngineError.io("Could not start AVAssetWriter: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        writer.startSession(atSourceTime: .zero)

        let fps = try parseFPS(options.fps)
        let frameDuration = CMTime(value: CMTimeValue(fps.denominator), timescale: fps.numerator)
        let rawBytes = [UInt8](raw)

        for frameIndex in 0..<frames {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let buffer = makeNV12PixelBuffer(
                rawBytes: rawBytes,
                frameOffset: frameIndex * frameBytes,
                width: options.width,
                height: options.height,
                attributes: pixelAttributes
            ) else {
                throw EngineError.io("Could not create pixel buffer for frame \(frameIndex).")
            }
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            if !adaptor.append(buffer, withPresentationTime: presentationTime) {
                throw EngineError.io("Could not append frame \(frameIndex): \(writer.error?.localizedDescription ?? "unknown error")")
            }
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw EngineError.io("Could not finish MP4 writer: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        print("Encoded \(frames) YUV420p frame(s) to HEVC MP4.")

        if let audioSource = options.audioSource {
            try muxAudioIfPresent(videoOnly: videoOnlyOutput, audioSource: audioSource, output: options.output)
            try? FileManager.default.removeItem(at: videoOnlyOutput)
        }
    }

    private static func muxAudioIfPresent(videoOnly: URL, audioSource: URL, output: URL) throws {
        let videoAsset = AVURLAsset(url: videoOnly)
        let sourceAsset = AVURLAsset(url: audioSource)
        let audioTracks = try loadTracks(sourceAsset, mediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: videoOnly, to: output)
            print("No readable source audio track found; wrote video-only MP4.")
            return
        }

        let composition = AVMutableComposition()
        guard let sourceVideoTrack = try loadTracks(videoAsset, mediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                  withMediaType: .video,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw EngineError.io("Could not prepare video track for audio mux.")
        }

        let videoDuration = try loadDuration(videoAsset)
        let sourceDuration = try loadDuration(sourceAsset)
        let videoRange = CMTimeRange(start: .zero, duration: videoDuration)
        try compositionVideoTrack.insertTimeRange(videoRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try loadPreferredTransform(sourceVideoTrack)

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw EngineError.io("Could not prepare audio track for mux.")
        }
        let audioDuration = CMTimeMinimum(sourceDuration, videoDuration)
        let audioRange = CMTimeRange(start: .zero, duration: audioDuration)
        try compositionAudioTrack.insertTimeRange(audioRange, of: sourceAudioTrack, at: .zero)

        let muxedOutput = output.deletingLastPathComponent().appendingPathComponent(".3davc-muxed-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: muxedOutput)
        defer { try? FileManager.default.removeItem(at: muxedOutput) }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw EngineError.io("Could not create AVAssetExportSession for audio mux.")
        }
        exporter.outputURL = muxedOutput
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let semaphore = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        guard exporter.status == .completed else {
            throw EngineError.io("Could not mux source audio: \(exporter.error?.localizedDescription ?? "unknown error")")
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: muxedOutput, to: output)
        print("Muxed source audio into MP4.")
    }

    private static func loadTracks(_ asset: AVURLAsset, mediaType: AVMediaType) throws -> [AVAssetTrack] {
        var result: Result<[AVAssetTrack], Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = .success(try await asset.loadTracks(withMediaType: mediaType))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result?.get() ?? []
    }

    private static func loadDuration(_ asset: AVURLAsset) throws -> CMTime {
        var result: Result<CMTime, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = .success(try await asset.load(.duration))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result?.get() ?? .zero
    }

    private static func loadPreferredTransform(_ track: AVAssetTrack) throws -> CGAffineTransform {
        var result: Result<CGAffineTransform, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = .success(try await track.load(.preferredTransform))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result?.get() ?? .identity
    }

    private static func parseBitrate(_ value: String) -> Int {
        let lower = value.lowercased()
        if lower.hasSuffix("k"), let number = Int(lower.dropLast()) {
            return number * 1000
        }
        if lower.hasSuffix("m"), let number = Int(lower.dropLast()) {
            return number * 1_000_000
        }
        return Int(lower) ?? 12_000_000
    }

    private static func parseFPS(_ value: String) throws -> (numerator: Int32, denominator: Int32) {
        if value.contains("/") {
            let parts = value.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let numerator = Int32(parts[0]),
                  let denominator = Int32(parts[1]),
                  numerator > 0,
                  denominator > 0 else {
                throw EngineError.usage("Invalid --fps value: \(value)")
            }
            return (numerator, denominator)
        }
        guard let fps = Double(value), fps > 0 else {
            throw EngineError.usage("Invalid --fps value: \(value)")
        }
        let scale: Int32 = 1000
        return (Int32((fps * Double(scale)).rounded()), scale)
    }

    private static func makeNV12PixelBuffer(
        rawBytes: [UInt8],
        frameOffset: Int,
        width: Int,
        height: Int,
        attributes: [String: Any]
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return nil
        }

        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let ySize = width * height
        let uOffset = frameOffset + ySize
        let vOffset = uOffset + ySize / 4

        rawBytes.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else {
                return
            }

            let yDest = yBase.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                let sourceStart = frameOffset + row * width
                yDest.advanced(by: row * yStride).update(from: base.advanced(by: sourceStart), count: width)
            }

            let uvDest = uvBase.assumingMemoryBound(to: UInt8.self)
            for row in 0..<(height / 2) {
                for column in 0..<(width / 2) {
                    let uvIndex = row * uvStride + column * 2
                    uvDest[uvIndex] = rawBytes[uOffset + row * (width / 2) + column]
                    uvDest[uvIndex + 1] = rawBytes[vOffset + row * (width / 2) + column]
                }
            }
        }

        return pixelBuffer
    }

    private static func groupBaseAccessUnits(_ data: Data) throws -> [[Data]] {
        var groups: [[Data]] = []
        var current: [Data] = []
        for nal in iterNALUnits(data) {
            if nalType(nal.payload) == 9, !current.isEmpty {
                groups.append(current)
                current = []
            }
            current.append(nal.complete)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private static func groupDependentAccessUnits(_ data: Data) throws -> [[Data]] {
        var groups: [[Data]] = []
        var current: [Data] = []
        for nal in iterNALUnits(data) {
            if nalType(nal.payload) == 24 {
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
                continue
            }
            current.append(nal.complete)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private static func iterNALUnits(_ data: Data) -> [NALUnit] {
        let bytes = [UInt8](data)
        let starts = nalStartCodes(bytes)
        guard !starts.isEmpty else {
            return []
        }
        var units: [NALUnit] = []
        for index in starts.indices {
            let start = starts[index]
            let payloadStart = start.offset + start.size
            let end = index + 1 < starts.count ? starts[index + 1].offset : bytes.count
            guard payloadStart <= end else {
                continue
            }
            let startCode = Data(bytes[start.offset..<payloadStart])
            let payload = Data(bytes[payloadStart..<end])
            units.append(NALUnit(startCode: startCode, payload: payload))
        }
        return units
    }

    private static func nalStartCodes(_ bytes: [UInt8]) -> [(offset: Int, size: Int)] {
        var starts: [(offset: Int, size: Int)] = []
        var index = 0
        while index + 3 <= bytes.count {
            if index + 4 <= bytes.count,
               bytes[index] == 0,
               bytes[index + 1] == 0,
               bytes[index + 2] == 0,
               bytes[index + 3] == 1 {
                starts.append((index, 4))
                index += 4
            } else if bytes[index] == 0,
                      bytes[index + 1] == 0,
                      bytes[index + 2] == 1 {
                starts.append((index, 3))
                index += 3
            } else {
                index += 1
            }
        }
        return starts
    }

    private static func nalType(_ payload: Data) -> UInt8 {
        guard let first = payload.first else {
            return 0xff
        }
        return first & 0x1f
    }

    private static func packetLayout(_ first: Data) throws -> (packetSize: Int, transportOffset: Int) {
        let bytes = [UInt8](first)
        if bytes.count >= 192, bytes[4] == 0x47 {
            return (192, 4)
        }
        if bytes.count >= 188, bytes[0] == 0x47 {
            return (188, 0)
        }
        throw EngineError.invalidTransportStream
    }
}
