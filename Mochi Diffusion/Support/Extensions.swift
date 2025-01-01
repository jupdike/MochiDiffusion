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

extension String {
    // Truncates the string to the specified length number of characters
    // and appends an optional trailing string if longer.
    // - Parameter length: Desired maximum lengths of a string
    // - Parameter trailing: A 'String' that will be appended after the truncation.
    // - Returns: 'String' object.
    func trunc(length: Int, trailing: String = "…") -> String {
        return (self.count > length) ? self.prefix(length) + trailing : self
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
