//
//  InspectorView.swift
//  Mochi Diffusion
//
//  Created by Joshua Park on 12/19/22.
//

import CoreML
import StableDiffusion
import SwiftUI

struct InfoGridRow: View {
    var type: LocalizedStringKey
    var text: String?
    var image: CGImage?
    var showCopyToPromptOption: Bool
    var callback: (@MainActor () -> Void)?

    var body: some View {
        GridRow {
            Text("")
            Text(type)
                .helpTextFormat()
        }
        GridRow {
            if showCopyToPromptOption {
                Button {
                    guard let callbackFn = callback else { return }
                    callbackFn()
                } label: {
                    Image(systemName: "arrow.left.circle.fill")
                        .foregroundColor(Color.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy Option to Sidebar")
            } else {
                Text("")
            }

            if let image = image {
                Image(image, scale: 4, label: Text(type))
                    .resizable()
                    .aspectRatio(
                        CGSize(width: image.width, height: image.height), contentMode: .fit
                    )
                    .frame(
                        height: image.height >= image.width
                            ? 90 : 90 * Double(image.height) / Double(image.width))
            } else if let text = text {
                Text(text)
                    .selectableTextFormat()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Spacer().frame(height: 12)
    }
}

func getCompositeReticleView(scale: CGFloat, offset: CGSize) -> some View {
    return GeometryReader { geometry in
        FaceReticle()
            .scale(scale * 6.0 / 5.0)  // reticle square is inset
            .offset(x: geometry.size.width * offset.width, y: geometry.size.height * offset.height)
    }
}

// had to split this up to get compiler to stop whining about unsound type system
func tapToPlaceReticle(
    store: ImageStore, sdi: SDImage,
    img: CGImage, location: CGPoint, frame geom: CGRect
) {
    let ratX: CGFloat = (location.x - geom.minX) / CGFloat((geom.maxX - geom.minX)) - 0.5
    let ratY: CGFloat = (location.y - geom.minY) / CGFloat((geom.maxY - geom.minY)) - 0.5
    store.updateMetadata(
        sdi, reticleScale: sdi.reticleScale,
        reticleOffset: CGSize(width: ratX, height: ratY)
    )
}

struct MyGuy {
    let sdi: SDImage
    let store: ImageStore
    init(store: ImageStore, sdi: SDImage) {
        self.store = store
        self.sdi = sdi
    }
}

//@Observable
//class Obool {
//    var myBool: Bool = false
//    init(_ bool: Bool) {
//        self.myBool = bool
//    }
//}

struct InspectorView: View {
    @Environment(ImageStore.self) private var store: ImageStore

    @State var lastScaleValue: CGFloat = 1.0
    @State private var isChecked = false
    //@Bindable var checked: Obool = Obool(false)

    var body: some View {
        return GeometryReader { proxy in
            //print("\(geometry.size)")
            VStack(spacing: 0) {
                if let sdi = store.selected(), let img = sdi.image {
                    ZStack {
                        Image(img, scale: 1, label: Text(verbatim: String(sdi.prompt)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                            .shadow(color: sdi.image?.averageColor ?? .black, radius: 16)
                            .padding(4)
                        if sdi.showReticle {
                            getCompositeReticleView(
                                scale: sdi.reticleScale,
                                offset: sdi.reticleOffset
                            )
                            .foregroundColor(.white)
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                            .shadow(color: .black, radius: 1)
                            .shadow(color: .black, radius: 1)
                            .shadow(color: .black, radius: 1)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    // ^^^ Not a bug, yes set the height to the width
                    // vvv Also two widths -- not a bug, this is deliberate
                    // because the geometry read gets the
                    // full height and we want the aspect height
                    // TODO deal with non-square images
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        if !sdi.showReticle {
                            return
                        }
                        let frame = proxy.frame(in: .local)
                        tapToPlaceReticle(
                            store: store, sdi: sdi, img: img, location: location,
                            frame: CGRect(
                                origin: CGPoint(x: 8, y: 8),
                                size: CGSize(width: frame.width - 16, height: frame.width - 16)
                            )
                        )
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                if !sdi.showReticle {
                                    return
                                }
                                let delta = val / self.lastScaleValue
                                self.lastScaleValue = val
                                let newScale = max(sdi.reticleScale * delta, 0.05)
                                store.updateMetadata(
                                    sdi, reticleScale: newScale, reticleOffset: sdi.reticleOffset
                                )
                            }
                            .onEnded { val in
                                self.lastScaleValue = 1.0
                            }
                    )
                    ScrollView(.vertical) {
                        Grid(alignment: .leading, horizontalSpacing: 4) {
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.date.rawValue),
                                text: sdi.generatedDate.formatted(date: .long, time: .standard),
                                showCopyToPromptOption: false
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.model.rawValue),
                                text: sdi.model,
                                showCopyToPromptOption: false
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.size.rawValue),
                                text:
                                    "\(sdi.width) x \(sdi.height)\(!sdi.upscaler.isEmpty ? " (Upscaled using \(sdi.upscaler))" : "")",
                                showCopyToPromptOption: false
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.includeInImage.rawValue),
                                text: sdi.prompt,
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copyPromptToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.excludeFromImage.rawValue),
                                text: sdi.negativePrompt,
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copyNegativePromptToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.seed.rawValue),
                                text: String(sdi.seed),
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copySeedToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.steps.rawValue),
                                text: String(sdi.steps),
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copyStepsToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.guidanceScale.rawValue),
                                text: String(sdi.guidanceScale),
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copyGuidanceScaleToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.scheduler.rawValue),
                                text: sdi.scheduler.rawValue,
                                showCopyToPromptOption: true,
                                callback: ImageController.shared.copySchedulerToPrompt
                            )
                            InfoGridRow(
                                type: LocalizedStringKey(Metadata.mlComputeUnit.rawValue),
                                text: MLComputeUnits.toString(sdi.mlComputeUnit),
                                showCopyToPromptOption: false
                            )
                        }
                    }
                    .padding([.horizontal])

                    Divider()

                    VStack {
                        if let sdi = store.selected() {
                            let longSymbolName = "arrow.up.left.and.arrow.down.right.square"
                            Button {
                                store.updateMetadata(sdi, showReticle: !sdi.showReticle)
                            } label: {
                                HStack {
                                    let symbolName =
                                        sdi.showReticle ? "\(longSymbolName).fill" : longSymbolName
                                    Image.init(systemName: symbolName)
                                    Text("Reticle")
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(EdgeInsets(top: 4, leading: 2, bottom: 0, trailing: 2))
                        }
                        HStack {
                            Button {
                                ImageController.shared.copyToPrompt()
                            } label: {
                                Text(
                                    "Copy Options to Sidebar",
                                    comment:
                                        "Button to copy the currently selected image's generation options to the prompt input sidebar"
                                )
                            }
                            Button {
                                let info = sdi.getHumanReadableInfo()
                                let pasteboard = NSPasteboard.general
                                pasteboard.declareTypes([.string], owner: nil)
                                pasteboard.setString(info, forType: .string)
                            } label: {
                                Text(
                                    "Copy Info",
                                    comment:
                                        "Button to copy the currently selected image's generation options to the clipboard"
                                )
                            }
                        }
                        .padding(EdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2))
                    }
                } else {
                    Text(
                        "No Info",
                        comment: "Placeholder text for image inspector"
                    )
                    .font(.title2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

extension CGImage {
    var averageColor: Color? {
        /// First, resize the image. We do this for two reasons,
        /// 1) less pixels to deal with means faster calculation and a resized image still has the "gist" of the colors
        /// 2) the image we're dealing with may come in any of a variety of color formats (CMYK, ARGB, RGBA, etc.) which complicates things, and redrawing it normalizes that into a base color format we can deal with
        /// 40x40 is a good size to resize to still preserve quite a bit of detail but not have too many pixels to deal with. Aspect ratio is irrelevant for just finding average color.
        let size = CGSize(width: 40, height: 40)
        let width = Int(size.width)
        let height = Int(size.height)
        let totalPixels = width * height

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        /// ARGB format
        let bitmapInfo: UInt32 =
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        /// 8 bits for each color channel, we're doing ARGB so 32 bits (4 bytes) total, and thus if the image is n pixels wide, and has 4 bytes per pixel, the total bytes per row is 4n.
        /// That gives us 2^8 = 256 color variations for each RGB channel or 256 * 256 * 256 = ~16.7M color options in total.
        /// That seems like a lot, but lots of HDR movies are in 10 bit, which is (2^10)^3 = 1 billion color options!
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else { return nil }

        /// Draw our resized image
        context.draw(self, in: CGRect(origin: .zero, size: size))

        guard let pixelBuffer = context.data else { return nil }

        /// Bind the pixel buffer's memory location to a pointer we can use/access
        let pointer = pixelBuffer.bindMemory(to: UInt32.self, capacity: width * height)

        /// Keep track of total colors (note: we don't care about alpha and will always assume alpha of 1, AKA opaque)
        var totalRed = 0
        var totalBlue = 0
        var totalGreen = 0

        /// Column of pixels in image
        for x in 0..<width {
            /// Row of pixels in image
            for y in 0..<height {
                /// To get the pixel location just think of the image as a grid of pixels,
                /// but stored as one long row rather than columns and rows,
                /// so for instance to map the pixel from the grid in the 15th row and 3 columns in to our "long row",
                /// we'd offset ourselves 15 times the width in pixels of the image, and then offset by the amount of columns
                let pixel = pointer[(y * width) + x]

                let r = red(for: pixel)
                let g = green(for: pixel)
                let b = blue(for: pixel)

                totalRed += Int(r)
                totalBlue += Int(b)
                totalGreen += Int(g)
            }
        }

        let averageRed = CGFloat(totalRed) / CGFloat(totalPixels)
        let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels)
        let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels)

        /// Convert from [0 ... 255] format to Color format [0 ... 1.0]
        return Color(
            red: averageRed / 255.0,
            green: averageGreen / 255.0,
            blue: averageBlue / 255.0,
            opacity: 1.0
        )
    }

    private func red(for pixelData: UInt32) -> UInt8 {
        UInt8((pixelData >> 16) & 255)
    }

    private func green(for pixelData: UInt32) -> UInt8 {
        UInt8((pixelData >> 8) & 255)
    }

    private func blue(for pixelData: UInt32) -> UInt8 {
        UInt8((pixelData >> 0) & 255)
    }
}

#Preview {
    InspectorView()
        .environment(ImageStore.shared)
}
