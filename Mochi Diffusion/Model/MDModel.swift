//
//  MDModel.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 12/22/24.
//

import SwiftUI

// A Mochi Diffusion Project allows a workflow to include:
// + cropping without using an external image editor;
// + setting a cropped image as starting image for img2img;
// + Mochi Diffusion img2img generate / prompt editing on that starting image;
// + automatic upscaling to keep growing the image canvas as new "zoomed-in" assets are created (eliminating any bicubic upscaling artifacts)
// + some sort of progress or even just message updates when tasks start and finish (Upscaling... Upscaled. Generating... Generated. ...)
// The project
// - tracks all the offsets and width/height of all the user's crops, relative to the original image;
// - persists (JSON to disk) all the x,y,w,h,z-order for each cropped/scaled/generated image;
// 1 allows a one-click PDF export using PSDWriter, using all that bookeeping information.
//
// The UI
// - makes interactive cropping easy
// - makes seeing the aligned, crop, upscaled, generated pieces/layers easy
//
// The user can then import this entire PSD file stack of ordered and aligned layers, in one step,
// into Serif Affinity Photo or Adobe Photoshop on iPad, and quickly manually mask/inpaint the layers
// together to create one detailed, high-resolution image with hand-picked details.
class MDProject {
    let folderPath: String
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

    func testWith(cgImage: CGImage) {
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
                await ImageController.shared.setStartingImage(image: cgi2)
                await logMessage("Upscaling an image...")
                await testUpscale(cgImage: cgImage)
                await logMessage("Enqueue an image to generate...")
                await ImageController.shared.generate(folderPath, "test-output-stem")
                // TODO some async method in ImageController to wait until queue is empty again
                await logMessage("Done.")
            }
        }
    }

    func testUpscale(cgImage: CGImage) async {
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
        }
    }

    func logMessage(_ message: String) async {
        await self.controller.setProjectStatusMessage(message)
    }

    init(
        path: String,
        cgImage: CGImage,
        controller: ImageController,
        generator: ImageGenerator
    ) {
        self.controller = controller
        self.generator = generator
        let folderPath = MDProject.imagePathToProjectFolder(path)
        self.folderPath = folderPath
        testWith(cgImage: cgImage)
    }

}
