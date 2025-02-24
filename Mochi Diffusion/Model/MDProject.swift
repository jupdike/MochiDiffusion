//
//  MDProject.swift
//  Mochi Diffusion Project Model / Controller
//
//  Created by Jared Updike on 12/22/24.
//

import SwiftUI
import Vision

// Task {
//let _ = await controller.$generationQueue.sink {
//    // NB changes to 0 when dequeued, but not done until that generation finishes...
//    print("Generation Queue count changing to: \($0.count)")
//}
//let _ = await controller.$currentGeneration.sink {
//    print("Generation config is \($0 == nil ? "nil" : "non-nil")")
//}
//let _ = await generator.$state.sink {
//    print("State is now \($0)")
//}
// }

// A Mochi Diffusion Project allows a workflow to include:
// + cropping without using an external image editor;
// + setting a cropped image as starting image for img2img;
// + Mochi Diffusion img2img generate / prompt editing on that starting image;
// + automatic upscaling to keep growing the image canvas as new "zoomed-in" assets are created (eliminating any bicubic upscaling artifacts)
// + some sort of progress or even just message updates when tasks start and finish (Upscaling... Upscaled. Generating... Generated. ...)
//
// The project
// - tracks all the offsets and width/height of all the user's crops, relative to the original image;
// + persists (JSON to disk) all the x,y,w,h,z-order for each cropped/scaled/generated image;
// + allows a one-click PSD export using PSDWriter
// - using all that bookeeping information.
//
// The UI
// - makes interactive cropping easy
// - makes seeing the aligned, crop, upscaled, generated pieces/layers easy
//
// The user can then import this entire PSD file stack of ordered and aligned layers, in one step,
// into Serif Affinity Photo or Adobe Photoshop on iPad, and quickly manually mask/inpaint the layers
// together to create one detailed, high-resolution image with hand-picked details.
public class MDProjectController {
    let folderPath: String
    let store: ImageStore
    let controller: ImageController  // used to log progress status messages to UI
    let generator: ImageGenerator  // ... ? do we need this?

    static func imagePathToProjectFolder(_ path: String) -> String {
        let p2 = path.replacingOccurrences(
            of: "/images/",
            with: "/projects/"
        ).replacingOccurrences(of: ".png", with: "")
        do {
            try FileManager.default.createDirectory(
                atPath: p2,
                withIntermediateDirectories: true)
        } catch {
            print(error.localizedDescription)
        }
        return p2
    }

    func testWith3(cgImage: CGImage) {
        let _ = ImageAnnotations.find(inImage: cgImage)
    }

    func testWith2(cgImage: CGImage) {
        if let cgi2 = cgImage.cropping(to: CGRect(x: 128, y: 0, width: 256, height: 256)) {
            print("new size of image = \(cgi2.width) by \(cgi2.height)")
            let out = "\(self.folderPath)/test.png"
            let imageURL = URL(fileURLWithPath: out)
            print(imageURL)
            if cgi2.trySaveTo(imageURL) {
                print("PNG successfully written")
            }
            Task {
                await logMessage("Setting Starting Image...")
                await controller.setStartingImage(image: cgi2)
                await logMessage("Upscaling an image...")
                let cgi3Maybe = await testUpscale(cgImage: cgImage)
                guard let cgi3 = cgi3Maybe else {
                    await logMessage("Error upscaling image.")
                    return
                }
                await logMessage("Generating an image...")
                await controller.generate1(folderPath, "test-output-gen")
                await logMessage("Writing out a PSD file...")
                await testWrite(
                    cgi3: cgi3,
                    onTop: "test-output-gen.png"
                )
                await logMessage("Done.")
            }
        }
    }

    func testWrite(cgi3: CGImage, onTop: String) async {
        let size = CGSize(width: 1024, height: 1024)
        let writer = PSDWriter(documentSize: size)
        guard let w = writer else {
            return
        }
        // add background
        w.addLayer(
            with: cgi3,
            andName: "test",
            andOpacity: 1.0,
            andOffset: CGPoint(x: 0, y: 0)
        )
        // add small generated image!
        let fullPath = "\(self.folderPath)/\(onTop)"
        let cgImage = cgImage(fromPath: fullPath)
        guard let cgi = cgImage else {
            print("error getting CGImage for image: \(fullPath)")
            return
        }
        w.addLayer(
            with: cgi,
            andName: "test-on-top",
            andOpacity: 1.0,
            andOffset: CGPoint(x: 256, y: 0)
        )
        let out = "\(self.folderPath)/two-layer-test.psd"
        let outputUrl = URL(fileURLWithPath: out)
        let psd: Data = w.createPSDData()
        do {
            try psd.write(to: outputUrl)
        } catch {
            print("Failed to write PSD to \(outputUrl.absoluteString)")
        }
    }

    func testUpscale(cgImage: CGImage) async -> CGImage? {
        if let cgi3 = await Upscaler.shared.upscale(
            cgImage: cgImage,
            upscaledWidth: cgImage.width * 2,
            upscaledHeight: cgImage.height * 2
        ) {
            let out2 = "\(self.folderPath)/test2.png"
            let imageURL2 = URL(fileURLWithPath: out2)
            print(imageURL2)
            if cgi3.trySaveTo(imageURL2) {
                print("PNG test2.png successfully written")
            }
            return cgi3
        }
        return nil
    }

    func logMessage(_ message: String) async {
        await self.controller.setProjectStatusMessage(message)
    }

    let baseWidth: Int
    let baseHeight: Int
    //var projectModel: MDProject
    var anns: ImageAnnotations
    let assets: AssetCollection

    init(
        path: String,
        cgImage: CGImage,
        store: ImageStore,
        controller: ImageController,
        generator: ImageGenerator
    ) {
        baseWidth = cgImage.width
        baseHeight = cgImage.height
        self.store = store
        self.controller = controller
        self.generator = generator
        let folderPath = MDProjectController.imagePathToProjectFolder(path)
        self.folderPath = folderPath
        //let path = "\(self.folderPath)/project.json"
        self.anns = ImageAnnotations.find(inImage: cgImage)
        self.assets = AssetCollection(assets: self.anns.assets, folderPath: folderPath)
        self.assets.assets = self.assets.stage0to1()
        store.projectController = self
    }

    func actuallyExecutePlan() {
        Task {
            await self.assets.stage1to2()
        }
    }

}

struct MDProject: Hashable, Codable, CustomStringConvertible {
    public var description: String {
        let data = try? JSONEncoder().encode(self)
        if let dat = data {
            let str = String(decoding: dat, as: UTF8.self)
            return "MDProject \(str)"
        }
        return "MDProject @ \(baseWidth) x \(baseHeight)"
    }

    var baseWidth: Int
    var baseHeight: Int
    var rootImage: MDProjectAsset

    func write(_ filePath: String) {
        try? JSONEncoder()
            .encode(self)
            .write(
                to: URL(fileURLWithPath: filePath),
                options: .atomic
            )
    }

    static func read(_ filePath: String) -> MDProject? {
        let asset: MDProject? = try? JSONDecoder()
            .decode(
                MDProject.self,
                from: Data(contentsOf: URL(fileURLWithPath: filePath))
            )
        return asset
    }
}

struct MDProjectAsset: Hashable, Codable, Identifiable {
    var id: UUID
    var dx: Int
    var dy: Int
    var width: Int
    var height: Int
    var subImages: [MDProjectAsset]
}
