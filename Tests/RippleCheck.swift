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
let queue = device.makeCommandQueue()!
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
let restingScenarios = [0, 3, 11]
// Move the same text and taps into a wider window, centred or in the right-hand pane,
// without changing their size in points. Resizing must not change the wave crossing the letters.
func translated(left: Float) -> [[Float]] {
    narrowScenarios.map { record in
        var moved = record
        for index in [0, 4] {
            moved[index] = (record[index] * 160 + left) / 640
            moved[index + 1] = (record[index + 1] * 80 + 200) / 480
        }
        return moved
    }
}
let wideScenarios = translated(left: 240)
// Narrow, wide, wide and cropped, then the right-hand pane: one block of 12 each.
let scenarios = narrowScenarios + wideScenarios + wideScenarios + translated(left: 400)
let count = scenarios.count * 12800

// Each tap record gains an aspect field; 1 keeps the original circular wave.
func render(aspects: (Int) -> (Float, Float) = { _ in (1, 1) }) -> [SIMD4<Float>] {
    let records = scenarios.indices.flatMap { scenario in
        let (first, second) = aspects(scenario)
        return Array(scenarios[scenario][0..<4]) + [first] + Array(scenarios[scenario][4..<8]) + [second]
    }
    let input = records.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)! }
    let buffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride)!
    let command = queue.makeCommandBuffer()!
    let encoder = command.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    encoder.setBuffer(input, offset: 0, index: 1)
    encoder.setTexture(texture, index: 0)
    encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    precondition(command.status == .completed)
    return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count), count: count))
}

// Every output must be a valid premultiplied colour, and resting scenarios must equal the input.
func checkColours(_ output: [SIMD4<Float>]) {
    for (i, pixel) in output.enumerated() {
        precondition((0..<4).allSatisfy { pixel[$0].isFinite && (0...1).contains(pixel[$0]) }, "Invalid colour output")
        precondition((0..<3).allSatisfy { pixel[$0] <= pixel.w + 0.001 }, "Output must stay premultiplied")
        if restingScenarios.contains((i / 12800) % 12) {
            let original = pixels[(i % 12800) * 4..<(i % 12800) * 4 + 4].map { Float($0) / 255 }
            precondition((0..<4).allSatisfy { abs(pixel[$0] - original[$0]) < 0.001 }, "Resting pixels must be unchanged")
        }
    }
}

let output = render()
checkColours(output)
var changed = 0
var colourEdges = Array(repeating: [0, 0], count: scenarios.count)
for (i, pixel) in output.enumerated() where !restingScenarios.contains((i / 12800) % 12) {
    let x = i % 160
    let original = Float(pixels[(i % 12800) * 4]) / 255
    let originalAlpha = Float(pixels[(i % 12800) * 4 + 3]) / 255
    let background: Float = x < 80 ? 1 : 0
    let displayed = SIMD3(pixel.x, pixel.y, pixel.z) + background * (1 - pixel.w)
    if abs(displayed.y - (original + background * (1 - originalAlpha))) > 0.1 { changed += 1 }
    if ((24..<70).contains(x) || (90..<134).contains(x))
        && displayed.max() - displayed.min() > 0.02 {
        colourEdges[i / 12800][x < 80 ? 0 : 1] += 1
    }
}
precondition(changed > 100, "Wave must still bend the strokes")
precondition([1, 5, 6].allSatisfy { colourEdges[$0].allSatisfy { $0 > 20 } },
             "The moving wave must disperse light in both appearances")
print("PASS: wave bends \(changed) stroke samples, disperses light in both appearances, exact static endpoints")

func differences(_ first: Int, _ second: Int) -> Int {
    (0..<12800).filter { pixel in
        (0..<4).contains { abs(output[first * 12800 + pixel][$0] - output[second * 12800 + pixel][$0]) > 0.001 }
    }.count
}
precondition(differences(1, 4) > 100, "Moving the tap must move the ripple")
precondition(differences(1, 5) > 100 && differences(1, 6) > 100, "Size variation must change the wave")
precondition(differences(7, 1) > 100 && differences(7, 10) > 100, "Both overlapping ripples must contribute")
precondition(differences(8, 1) == 0, "A new tap must not cancel or change the earlier wave")
precondition(differences(9, 10) == 0, "An expired wave must not affect the remaining wave")
print("PASS: tap origins, size variation, overlapping waves and independent endpoints")

// Moving or cropping the layer may round a few channels by one 8-bit shade (1/255), never more.
func matchesNarrow(block: Int) -> Bool {
    narrowScenarios.indices.allSatisfy { scenario in
        var peak: Float = 0, total: Float = 0
        for pixel in 0..<12800 {
            for channel in 0..<4 {
                let error = abs(output[scenario * 12800 + pixel][channel]
                                - output[(scenario + block * 12) * 12800 + pixel][channel])
                peak = max(peak, error)
                total += error
            }
        }
        return peak <= 0.005 && total / 51200 < 0.00001
    }
}
precondition(matchesNarrow(block: 1), "A wider window must not change the refraction")
precondition(matchesNarrow(block: 2), "Cropping must preserve the refraction and tap coordinates")
precondition(matchesNarrow(block: 3), "The right-hand pane must preserve the refraction and tap coordinates")
print("PASS: wide, cropped and right-hand layouts match the narrow refraction")

let varied = render { $0.isMultiple(of: 2) ? (0.975, 1.025) : (1.025, 0.975) }
checkColours(varied)
let variedPixels = zip(output, varied).filter { a, b in (0..<4).contains { abs(a[$0] - b[$0]) > 0.001 } }.count
precondition(variedPixels > 100, "Small aspect variation must change the refraction footprint")
print("PASS: subtle aspect variation changes \(variedPixels) samples without altering resting pixels or colour validity")
