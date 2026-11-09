import Foundation
import Metal

// Run from the repository root on macOS: swift Tests/RippleCheck.swift
// Sample the real shader using transparent black/white strokes in both appearances.
let device = MTLCreateSystemDefaultDevice()!
let source = try String(contentsOfFile: "LimaApp/Ripple.metal", encoding: .utf8)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
try (source + """

kernel void probe(device float4 *output [[buffer(0)]], device const float *records [[buffer(1)]],
                  texture2d<half> input [[texture(0)]],
                  uint i [[thread_position_in_grid]]) {
    uint scenario = i / 12800;
    float2 size = scenario < 12 ? float2(160, 80) : float2(640, 480);
    float2 translation = (size - float2(160, 80)) * 0.5;
    if (scenario >= 36) translation.x += 160;
    bool cropped = scenario >= 24;
    SwiftUI::Layer layer;
    layer.tex = input;
    layer.info[0] = float2(1.0 / 160, 0);
    layer.info[1] = float2(0, 1.0 / 80);
    layer.info[2] = cropped ? float2(0) : -translation / float2(160, 80);
    layer.info[3] = float2(0.5 / 160, 0.5 / 80);
    layer.info[4] = float2(159.5 / 160, 79.5 / 80);
    float2 position = float2(i % 160, (i / 160) % 80) + 0.5;
    half4 background = position.x < 80 ? half4(1) : half4(0, 0, 0, 1);
    output[i] = float4(limaRipple(position + (cropped ? float2(0) : translation), layer, size,
                                 cropped ? translation : float2(0), 11.2, records + scenario * 10,
                                 scenario % 12 == 11 ? 0 : 10, background));
}
""").write(to: temporary.appendingPathComponent("probe.metal"), atomically: true, encoding: .utf8)
for arguments in [
    ["--sdk", "macosx", "metal", "-c", "probe.metal", "-o", "probe.air"],
    ["--sdk", "macosx", "metallib", "probe.air", "-o", "probe.metallib"]
] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.currentDirectoryURL = temporary
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "Shader compilation failed")
}
let library = try device.makeLibrary(URL: temporary.appendingPathComponent("probe.metallib"))
let descriptor = MTLComputePipelineDescriptor()
descriptor.computeFunction = library.makeFunction(name: "probe")!
let linked = MTLLinkedFunctions()
linked.functions = [library.makeFunction(name: "limaRipple")!]
descriptor.linkedFunctions = linked
let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
let texture = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 160, height: 80, mipmapped: false))!
var pixels = [UInt8]()
for y in 0..<80 {
    for x in 0..<160 {
        let stroke = (18..<62).contains(y) && [(30..<38), (54..<62), (96..<104), (120..<128)].contains { $0.contains(x) }
        let value: UInt8 = stroke && x >= 80 ? 255 : 0
        pixels += [value, value, value, stroke ? 255 : 0]
    }
}
pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, 160, 80), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 160 * 4) }
// x/y, progress, scale for two independent taps. Zero progress means not started.
let narrowScenarios: [[Float]] = [
    [0.55, 0.5, 0, 1.45,    0, 0, 0, 1],
    [0.55, 0.5, 0.25, 1.45, 0, 0, 0, 1],
    [0.55, 0.5, 0.45, 1.45, 0, 0, 0, 1],
    [0.55, 0.5, 1, 1.45,    0, 0, 0, 1],
    [0.2, 0.5, 0.25, 1.45,  0, 0, 0, 1],
    [0.55, 0.5, 0.25, 1.35, 0, 0, 0, 1],
    [0.55, 0.5, 0.25, 1.55, 0, 0, 0, 1],
    [0.55, 0.5, 0.25, 1.45, 0.8, 0.5, 0.2, 1.45],
    [0.55, 0.5, 0.25, 1.45, 0.8, 0.5, 0, 1.45],
    [0.55, 0.5, 1, 1.45,    0.8, 0.5, 0.2, 1.45],
    [0.8, 0.5, 0.2, 1.45,   0, 0, 0, 1],
    [0, 0, 0, 1,          0, 0, 0, 1]
]
// Move the same text and taps into the centre of a wider window without changing
// their size in points. Resizing must not change the wave crossing the letters.
let wideScenarios = narrowScenarios.map { record in
    var translated = record
    for index in [0, 4] {
        translated[index] = (record[index] * 160 + 240) / 640
        translated[index + 1] = (record[index + 1] * 80 + 200) / 480
    }
    return translated
}
let rightScenarios = narrowScenarios.map { record in
    var translated = record
    for index in [0, 4] {
        translated[index] = (record[index] * 160 + 400) / 640
        translated[index + 1] = (record[index + 1] * 80 + 200) / 480
    }
    return translated
}
let scenarios = narrowScenarios + wideScenarios + wideScenarios + rightScenarios
// Keep the original circular cases, adding the new aspect field to each tap record.
let records: [Float] = scenarios.flatMap { scenario in
    [0, 4].flatMap { Array(scenario[$0..<($0 + 4)]) + [1] }
}
let recordBuffer = records.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)! }
let count = scenarios.count * 160 * 80
let buffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride)!
let command = device.makeCommandQueue()!.makeCommandBuffer()!
let encoder = command.makeComputeCommandEncoder()!
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(buffer, offset: 0, index: 0)
encoder.setBuffer(recordBuffer, offset: 0, index: 1)
encoder.setTexture(texture, index: 0)
encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
precondition(command.status == .completed)
let output = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
var changed = 0
var colourEdges = Array(repeating: [0, 0], count: scenarios.count)
for i in 0..<count {
    let pixel = output[i]
    let original = Float(pixels[(i % 12800) * 4]) / 255
    let originalAlpha = Float(pixels[(i % 12800) * 4 + 3]) / 255
    let x = i % 160
    let background: Float = x < 80 ? 1 : 0
    let displayed = SIMD3(pixel.x, pixel.y, pixel.z) + background * (1 - pixel.w)
    for channel in 0..<4 {
        precondition(pixel[channel].isFinite && (0...1).contains(pixel[channel]), "Invalid colour output")
    }
    for channel in 0..<3 {
        precondition(pixel[channel] <= pixel.w + 0.001, "Output must stay premultiplied")
    }
    if [0, 3, 11].contains((i / 12800) % 12) {
        precondition(abs(pixel.x - original) < 0.001 && abs(pixel.y - original) < 0.001 && abs(pixel.z - original) < 0.001 && abs(pixel.w - originalAlpha) < 0.001, "Resting pixels must be unchanged")
    } else {
        if abs(displayed.y - (original + background * (1 - originalAlpha))) > 0.1 { changed += 1 }
        if (24..<70).contains(x) || (90..<134).contains(x) {
            if max(displayed.x, displayed.y, displayed.z) - min(displayed.x, displayed.y, displayed.z) > 0.02 {
                colourEdges[i / 12800][x < 80 ? 0 : 1] += 1
            }
        }
    }
}
precondition(changed > 100, "Wave must still bend the strokes")
print("Changed stroke samples: \(changed); coloured edges in light/dark (default size): \(colourEdges[1])")
guard [1, 5, 6].allSatisfy({ colourEdges[$0].allSatisfy { $0 > 20 } }) else {
    print("FAIL: the moving wave must disperse light in both appearances")
    exit(1)
}
print("PASS: temporary dispersion in both appearances; exact static endpoints")

func differences(_ first: Int, _ second: Int) -> Int {
    (0..<12800).filter { pixel in
        let a = output[first * 12800 + pixel]
        let b = output[second * 12800 + pixel]
        return (0..<4).contains { abs(a[$0] - b[$0]) > 0.001 }
    }.count
}
precondition(differences(1, 4) > 100, "Moving the tap must move the ripple")
precondition(differences(1, 5) > 100 && differences(1, 6) > 100, "Size variation must change the wave")
precondition(differences(7, 1) > 100 && differences(7, 10) > 100, "Both overlapping ripples must contribute")
precondition(differences(8, 1) == 0, "A new tap must not cancel or change the earlier wave")
precondition(differences(9, 10) == 0, "An expired wave must not affect the remaining wave")
print("PASS: tap origins, size variation, overlapping waves and independent endpoints")
var largestLayoutDifference: Float = 0
for scenario in narrowScenarios.indices {
    var peak: Float = 0
    var total: Float = 0
    for pixel in 0..<12800 {
        let narrow = output[scenario * 12800 + pixel]
        let wide = output[(scenario + narrowScenarios.count) * 12800 + pixel]
        for channel in 0..<4 {
            let error = abs(narrow[channel] - wide[channel])
            peak = max(peak, error)
            total += error
        }
    }
    let mean = total / (12800 * 4)
    // Translating the texture can round a few channels by one 8-bit shade.
    guard peak <= 0.005, mean < 0.00001 else {
        print("FAIL: layout changed refraction in scenario \(scenario); peak error \(peak), mean error \(mean)")
        exit(1)
    }
    largestLayoutDifference = max(largestLayoutDifference, peak)
}
print("PASS: matching refraction across narrow and wide layouts; peak channel rounding \(largestLayoutDifference)")
for scenario in narrowScenarios.indices {
    precondition(differences(scenario, scenario + 2 * narrowScenarios.count) == 0,
                 "Cropping must preserve the original refraction and tap coordinates")
}
print("PASS: cropped rendering preserves all sampled pixels, including overlapping waves")
for scenario in narrowScenarios.indices {
    var peak: Float = 0, total: Float = 0
    for pixel in 0..<12800 {
        let expected = output[scenario * 12800 + pixel]
        let right = output[(scenario + 3 * narrowScenarios.count) * 12800 + pixel]
        for channel in 0..<4 {
            let error = abs(expected[channel] - right[channel])
            peak = max(peak, error)
            total += error
        }
    }
    precondition(peak <= 0.005 && total / 51200 < 0.00001,
                 "Moving content to the right-hand pane must preserve refraction and tap mapping")
}
print("PASS: right-hand pane refraction and tap coordinates match the centred layout")

var variedRecords = records
for scenario in scenarios.indices {
    variedRecords[scenario * 10 + 4] = scenario.isMultiple(of: 2) ? 0.975 : 1.025
    variedRecords[scenario * 10 + 9] = scenario.isMultiple(of: 2) ? 1.025 : 0.975
}
let variedInput = variedRecords.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)! }
let variedBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride)!
let variedCommand = device.makeCommandQueue()!.makeCommandBuffer()!
let variedEncoder = variedCommand.makeComputeCommandEncoder()!
variedEncoder.setComputePipelineState(pipeline)
variedEncoder.setBuffer(variedBuffer, offset: 0, index: 0)
variedEncoder.setBuffer(variedInput, offset: 0, index: 1)
variedEncoder.setTexture(texture, index: 0)
variedEncoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
variedEncoder.endEncoding()
variedCommand.commit()
variedCommand.waitUntilCompleted()
precondition(variedCommand.status == .completed)
let variedOutput = variedBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
var variedPixels = 0
for i in 0..<count {
    let pixel = variedOutput[i]
    precondition((0..<4).allSatisfy { pixel[$0].isFinite && (0...1).contains(pixel[$0]) })
    precondition((0..<3).allSatisfy { pixel[$0] <= pixel.w + 0.001 })
    let changed = (0..<4).contains { abs(pixel[$0] - output[i][$0]) > 0.001 }
    if [0, 3, 11].contains((i / 12800) % 12) {
        precondition(!changed, "Aspect variation must preserve exact static endpoints")
    } else if changed { variedPixels += 1 }
}
precondition(variedPixels > 100, "Small aspect variation must change the refraction footprint")
print("PASS: subtle aspect variation changes \(variedPixels) samples without altering resting pixels or colour validity")
