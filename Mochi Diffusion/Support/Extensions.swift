//
//  Extensions.swift
//  Mochi Diffusion
//
//  Created by Joshua Park on 12/17/2022.
//

import CompactSlider
import CoreML
import StableDiffusion
import SwiftUI
import UniformTypeIdentifiers

struct MochiCompactSliderStyle: CompactSliderStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color(nsColor: .textColor))
            .background(Color(NSColor.labelColor).opacity(0.075))
            .accentColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

extension NSApplication {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }
}

extension View {
    func syncFocus<T: Equatable>(_ binding: Binding<T>, with focusState: FocusState<T>) -> some View
    {
        self
            .onChange(of: binding.wrappedValue) {
                focusState.wrappedValue = binding.wrappedValue
            }
            .onChange(of: focusState.wrappedValue) {
                binding.wrappedValue = focusState.wrappedValue
            }
    }
}

extension String {
    func loadJpegOrPngImage() -> CGImage? {
        let lower = self.lowercased()
        if lower.hasSuffix(".png") {
            return self.loadPngImage()
        } else if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") {
            return self.loadJpegImage()
        }
        return nil
    }

    func loadJpegImage() -> CGImage? {
        let url = URL(filePath: self)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            print("Failed to create data provider.")
            return nil
        }
        guard
            let cgImage =
                CGImage(
                    jpegDataProviderSource: dataProvider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                )
        else {
            print("Failed to create CGImage.")
            return nil
        }
        return cgImage
    }

    func loadPngImage() -> CGImage? {
        let url = URL(filePath: self)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            print("Failed to create data provider.")
            return nil
        }
        guard
            let cgImage =
                CGImage(
                    pngDataProviderSource: dataProvider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                )
        else {
            print("Failed to create CGImage.")
            return nil
        }
        return cgImage
    }

    // filters lines starting withp # and empty lines
    func contensOfFileAsLines() -> [String] {
        var all = ""
        do {
            all = try String(contentsOfFile: self, encoding: .utf8)
        } catch {
            print("Error loading contents of madlib.txt")
        }
        guard all != "" else { return [] }
        let lines = all.components(separatedBy: "\n").filter {
            s in s != "" && !(s.starts(with: "#"))
        }
        return lines
    }
}

extension NSImage {
    func getImageHash() -> Int {
        self.tiffRepresentation!.hashValue
    }

    func toPngData() -> Data {
        let imageRepresentation = NSBitmapImageRep(data: self.tiffRepresentation!)
        return (imageRepresentation?.representation(using: .png, properties: [:])!)!
    }
}

extension CGImage {
    func scaledAndCroppedTo(size: CGSize) -> CGImage? {
        let sizeRatio = size.width / size.height
        let imageSizeRatio = Double(self.width) / Double(self.height)
        let scaleFactor =
            sizeRatio > imageSizeRatio
            ? size.width / Double(self.width) : size.height / Double(self.height)
        let scaledWidth = CGFloat(self.width) * scaleFactor
        let scaledHeight = CGFloat(self.height) * scaleFactor

        // Calculate the origin point of the crop
        let cropX = (scaledWidth - size.width) / 2.0
        let cropY = (scaledHeight - size.height) / 2.0

        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: self.bitsPerComponent,
                bytesPerRow: 0,
                space: self.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        // Adjust the context to handle the scaled image
        context.translateBy(x: -cropX, y: -cropY)
        context.scaleBy(x: scaleFactor, y: scaleFactor)

        // Draw the image into the context
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Extract the cropped and resized image from the context
        let scaledCroppedImage = context.makeImage()

        return scaledCroppedImage
    }

    func playWithAlphaChannel() -> CGImage? {
        // Basic validation
        guard self.bitsPerComponent == 8,
            self.bitsPerPixel == 24 || self.bitsPerPixel == 32,
            self.colorSpace?.model == .rgb
        else {
            print("Error: Image must be RGB with 8 bits per component")
            return nil
        }
        let width = self.width
        let height = self.height
        // Get input buffer
        guard let inputDataProvider = self.dataProvider,
            let inputData = inputDataProvider.data,
            let inputBuffer = CFDataGetBytePtr(inputData)
        else {
            print("Error: Could not access input image data")
            return nil
        }
        // Calculate bytes per row for input (handle both RGB and RGBA)
        let inputBytesPerPixel = self.bitsPerPixel / 8
        let inputBytesPerRow = self.bytesPerRow
        // Create output buffer (always RGBA)
        let outputBytesPerPixel = 4
        let outputBytesPerRow = width * outputBytesPerPixel
        let outputBufferSize = height * outputBytesPerRow
        var outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
        // Process pixels
        for y in 0..<height {
            for x in 0..<width {
                // Calculate input pixel offset
                let inputPixelOffset = y * inputBytesPerRow + x * inputBytesPerPixel
                // Get R G B from input image, ignore alpha (assume it is 255)
                let r = inputBuffer[inputPixelOffset]
                let g = inputBuffer[inputPixelOffset + 1]
                let b = inputBuffer[inputPixelOffset + 2]
                //
                let newAlpha: UInt8 = 255  // this works and is a no-op / identifty function
                // this works and proves that our PSD write code can write out PSD files with varying alpha
                // let newAlpha: UInt8 = UInt8((x * y) % 255)  // TODOx I will write a better version of this
                //
                // Calculate output pixel offset
                let outputPixelOffset = y * outputBytesPerRow + x * outputBytesPerPixel
                // r g b and newAlpha get put back into a buffer here
                outputBuffer[outputPixelOffset] = r
                outputBuffer[outputPixelOffset + 1] = g
                outputBuffer[outputPixelOffset + 2] = b
                outputBuffer[outputPixelOffset + 3] = newAlpha
            }
        }
        // Turn buffer back into CGImage
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let dataProvider = CGDataProvider(data: Data(outputBuffer) as CFData)
        else {
            print("Error: Could not create color space or data provider")
            return nil
        }
        let newImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: outputBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        guard let finalImage = newImage else {
            print("Error: Could not create output CGImage")
            return nil
        }
        return finalImage
    }
}

public struct TransferableImage {
    public let image: NSImage
}

extension TransferableImage: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation<TransferableImage, URL> { transferableImage in
            try transferableImage.image.temporaryFileURL()
        }
    }
}

extension NSImage {
    private static var urlCache = [Int: URL]()

    public static func cleanupTempFiles() {
        for url in self.urlCache {
            try? FileManager.default.removeItem(at: url.value)
        }
    }

    func temporaryFileURL() throws -> URL {
        let imageHash = self.getImageHash()
        if let cachedURL = Self.urlCache[imageHash],
            FileManager.default.fileExists(atPath: cachedURL.path(percentEncoded: false))
        {
            return cachedURL
        }
        let name = String(imageHash)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            name, conformingTo: .png)
        let fileWrapper = FileWrapper(regularFileWithContents: self.toPngData())
        try fileWrapper.write(to: url, originalContentsURL: nil)
        Self.urlCache[imageHash] = url
        return url
    }

    var png: Data? { tiffRepresentation?.bitmap?.png }
    func trySaveTo(_ imageURL: URL) -> Bool {
        if let png = self.png {
            do {
                try png.write(to: imageURL)
                print("PNG image saved")
                return true
            } catch {
                print(error)
                return false
            }
        }
        print("failed to get PNG from NSImage")
        return false
    }
}
extension CGImage {
    func trySaveTo(_ imageURL: URL) -> Bool {
        let ns = NSImage(
            cgImage: self,
            size: NSSize(width: self.width, height: self.height)
        )
        if ns.trySaveTo(imageURL) {
            return true
        }
        return false
    }
}

// https://stackoverflow.com/questions/29262624/nsimage-to-nsdata-as-png-swift
// https://stackoverflow.com/questions/46432709/saving-nsimage-in-different-formats-locally/46481947#46481947
extension NSBitmapImageRep {
    var png: Data? { representation(using: .png, properties: [:]) }
}

extension Data {
    var bitmap: NSBitmapImageRep? { NSBitmapImageRep(data: self) }
}

extension NSImage {
    func cgImage() -> CGImage? {
        guard let tiffData = self.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.cgImage
    }
}

extension CGImage {
    func trySaveToPng(_ imageURL: URL) -> Bool {
        let ns = NSImage(
            cgImage: self,
            size: NSSize(width: self.width, height: self.height)
        )
        if ns.trySaveTo(imageURL) {
            return true
        }
        return false
    }
}

extension CGPoint {
    var toRect: CGRect { CGRect(x: self.x, y: self.y, width: 0, height: 0) }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: self.midX, y: self.midY) }
    var topLeft: CGPoint { self.origin }
    var topRight: CGPoint { CGPoint(x: self.maxX, y: self.minY) }
    var topCenter: CGPoint { CGPoint(x: self.midX, y: self.minY) }
    var bottomLeft: CGPoint { CGPoint(x: self.minX, y: self.maxY) }
    var bottomRight: CGPoint { CGPoint(x: self.maxX, y: self.maxY) }
    var bottomCenter: CGPoint { CGPoint(x: self.midX, y: self.maxY) }

    var maxDim: CGFloat { max(self.width, self.height) }
    var minDim: CGFloat { min(self.width, self.height) }
    var avgDim: CGFloat { 0.5 * self.width + 0.5 * self.height }
    var geomMeanDim: CGFloat { sqrt(self.width * self.height) }

    func toPathPoints() -> [CGPoint] {
        [
            self.topLeft,
            self.topRight,
            self.bottomRight,
            self.bottomLeft,
            self.topLeft,
        ]
    }

    var description: String {
        "TL -- \(self.minX),\(self.minY) -- BR -- \(self.maxX),\(self.maxY)"
    }

    func horizKeepWithin(_ other: CGRect) -> CGRect {
        var ret = self
        // push rectangle in from either side, but keep width
        ret = CGRect(
            x: max(other.minX, ret.minX),
            y: ret.minY,
            width: ret.width,
            height: ret.height
        )
        ret = CGRect(
            x: min(other.maxX - ret.width, ret.minX),
            y: ret.minY,
            width: ret.width,
            height: ret.height
        )
        return ret
    }

    func vertKeepWithin(_ other: CGRect) -> CGRect {
        var ret = self
        // push rectangle in from either side, but keep width
        ret = CGRect(
            x: ret.minX,
            y: max(other.minY, ret.minY),
            width: ret.width,
            height: ret.height
        )
        ret = CGRect(
            x: ret.minX,
            y: min(other.maxY - ret.width, ret.minY),
            width: ret.width,
            height: ret.height
        )
        return ret
    }

    func keepWithin(_ other: CGRect) -> CGRect {
        self.horizKeepWithin(other).vertKeepWithin(other)
    }

    func interpolatePyramidWithSmallRect(_ other: CGRect, n: Int) -> [CGRect] {
        // TODO BUG: assumes baseRect has top-left at 0,0
        let baseRect = self
        let targetRect = other
        let maxScale: CGFloat = baseRect.height / targetRect.height
        let neighborRatio: CGFloat = CGFloat(pow(maxScale, 1.0 / CGFloat(n)))
        //print("***> MAXSCALE: \(maxScale), neighborRatio: \(neighborRatio)")
        var ret: [CGRect] = []
        var curRatio: CGFloat = maxScale
        var w = baseRect.width
        var h = baseRect.height
        for _ in 0...n {
            let k: CGFloat = (maxScale - curRatio) / (maxScale - 1.0)
            let ptX = targetRect.minX * k
            let ptY = targetRect.minY * k
            let wrecked = CGRect(
                x: ptX, y: ptY,
                width: w, height: h
            )
            ret.append(wrecked)
            curRatio /= neighborRatio
            w /= neighborRatio
            h /= neighborRatio
        }
        return ret
    }

}

extension Text {
    struct SidebarLabelFormat: ViewModifier {
        func body(content: Content) -> some View {
            content
                .textCase(.uppercase)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }

    func sidebarLabelFormat() -> some View {
        modifier(SidebarLabelFormat())
    }

    struct HelpTextFormat: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    func helpTextFormat() -> some View {
        modifier(HelpTextFormat())
    }

    struct SelectableTextFormat: ViewModifier {
        func body(content: Content) -> some View {
            content
                .textSelection(.enabled)
                .foregroundColor(Color(nsColor: .textColor))
            /// Fixes dark text in dark mode SwiftUI bug
        }
    }

    func selectableTextFormat() -> some View {
        modifier(SelectableTextFormat())
    }
}

extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                handler(newValue)
            }
        )
    }
}

extension CompactSliderStyle where Self == MochiCompactSliderStyle {
    static var `mochi`: MochiCompactSliderStyle { MochiCompactSliderStyle() }
}

extension UTType {
    static func fromString(_ fileExtension: String) -> UTType {
        switch fileExtension {
        case UTType.jpeg.preferredFilenameExtension!:
            return UTType.jpeg
        case UTType.heic.preferredFilenameExtension!:
            return UTType.heic
        default:
            return UTType.png
        }
    }
}

extension MLComputeUnits {
    static func toString(_ computeUnit: MLComputeUnits?) -> String {
        guard let computeUnit = computeUnit else {
            return ""
        }
        switch computeUnit {
        case .cpuOnly:
            return "CPU Only"
        case .cpuAndGPU:
            return "CPU & GPU"
        case .all:
            return "All"
        case .cpuAndNeuralEngine:
            return "CPU & Neural Engine"
        default:
            return ""
        }
    }

    static func fromString(_ value: String) -> MLComputeUnits {
        switch value {
        case "CPU Only":
            return .cpuOnly
        case "CPU & GPU":
            return .cpuAndGPU
        case "All":
            return .all
        case "CPU & Neural Engine":
            return .cpuAndNeuralEngine
        default:
            return .all
        }
    }
}

func cgImage(fromPath fullPath: String) -> CGImage? {
    let nsMaybe: NSImage? = NSImage(contentsOfFile: fullPath)
    guard let ns = nsMaybe else {
        print("error loading image: \(fullPath)")
        return nil
    }
    let cgImageUnman: Unmanaged<CGImage> = newCGImageForNSImage(ns)
    let cgImage = cgImageUnman.takeRetainedValue() as CGImage?
    return cgImage
}

extension String {
    // Truncates the string to the specified length number of characters
    // and appends an optional trailing string if longer.
    // - Parameter length: Desired maximum lengths of a string
    // - Parameter trailing: A 'String' that will be appended after the truncation.
    // - Returns: 'String' object.
    func trunc(length: Int, trailing: String = "…") -> String {
        return (self.count > length) ? self.prefix(length) + trailing : self
    }
    func getFileName() -> String {
        let split = self.split(by: "/")
        return split.last ?? ""
    }
}

// from https://dev.to/arnavmotwani/handling-persistent-data-in-swiftui-2-0-with-json-1h7
// https://developer.apple.com/documentation/foundation/archives_and_serialization/encoding_and_decoding_custom_types
// https://developer.apple.com/documentation/foundation/archives_and_serialization/using_json_with_custom_types
// https://developer.apple.com/documentation/foundation/jsonencoder
// https://developer.apple.com/documentation/foundation/jsondecoder
extension Bundle {
    static func load<T: Decodable>(_ filename: String) -> T {

        // Example json file in our bundle
        let readURL = Bundle.main.url(forResource: filename, withExtension: "json")!
        // Initializing the url for the location where we store our data in filemanager
        let documentDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        // appending the file name to the url
        let jsonURL =
            documentDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("json")

        // The following condition copies the example file in our bundle to the correct location if it isnt present
        if !FileManager.default.fileExists(atPath: jsonURL.path) {
            try? FileManager.default.copyItem(at: readURL, to: jsonURL)
        }

        // returning the parsed data
        return try! JSONDecoder().decode(T.self, from: Data(contentsOf: jsonURL))
    }
}
