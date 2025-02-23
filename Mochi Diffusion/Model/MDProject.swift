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

struct MyShape: Hashable, Equatable, Identifiable {
    let points: [CGPoint]
    let pointsClassification: VNPointsClassification
    let id: UUID = UUID()
    init(region: VNFaceLandmarkRegion2D?, size: CGSize) {
        guard let region2 = region else {
            self.points = []
            self.pointsClassification = .openPath
            return
        }
        self.points = region2.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        self.pointsClassification = region2.pointsClassification
    }
    init(points: [CGPoint], classification: VNPointsClassification) {
        self.points = points
        self.pointsClassification = classification
    }
    static func emptyShape() -> MyShape {
        return MyShape(points: [], classification: .openPath)
    }
}

struct MyFace: Hashable, Equatable, Identifiable {
    let id: UUID = UUID()
    let shapes: [MyShape]
    let faceRect: CGRect
    let centerShape: MyShape
    let center: CGPoint
    let bounds: CGRect
    let boundsShape: MyShape
    let finalRect: CGRect
    let finalShapes: [MyShape]
}

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

    // attempt to deserialize and restore state from disk, if possible
    // if not, create a new MDProject model object and write that out too
    static func tryLoad(
        fromProjectPath path: String,
        withDefaultWidth w: Int,
        defaultHeight h: Int
    ) -> MDProject {
        let projectModel = MDProject.read(path)
        if let model = projectModel {
            print("successfully read project.json from disk: \(path)")
            return model
        }
        print("could not read project.json from disk @ '\(path)' so a new one was created")
        // TODO also write out PNG image of root original image first
        let asset = MDProjectAsset(
            id: UUID(),
            dx: 0,
            dy: 0,
            width: w,
            height: h,
            subImages: [])
        let ret = MDProject(
            baseWidth: w,
            baseHeight: h,
            rootImage: asset
        )
        ret.write(path)
        return ret
    }

    func testWith3(cgImage: CGImage) {
        let _ = detectOneFace(cgImage: cgImage)
    }

    func tipOfNose(
        noseCrest: VNFaceLandmarkRegion2D?,
        median: VNFaceLandmarkRegion2D?,
        size: CGSize
    ) -> CGPoint {
        let ret: CGPoint = CGPoint(x: size.width * 0.5, y: 0)
        guard let region2 = noseCrest else {
            print("Nil nose crest region")
            return ret
        }
        guard let regionMedian = median else {
            print("Nil nose crest region")
            return ret
        }
        let points = region2.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        let n = points.count
        guard n >= 2 else {
            print("Not enough points in node crest region to find tip of nose")
            return ret
        }
        let lastPt = points[n - 1]
        let lastPt2 = points[n - 2]
        let cy = lastPt.y * 0.5 + lastPt2.y * 0.5
        // find cx by approx. intersection of horizontal line @ cy with face median countour
        let medianPts = regionMedian.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        let m1 = medianPts.count - 1
        var cx = lastPt.x  // temporaty, likely off-center
        for i in 0..<m1 {
            let one = medianPts[i]
            let two = medianPts[i + 1]
            if (one.y < cy && cy < two.y) || (two.y < cy && cy < one.y) {
                // keep center x value of line segment
                cx = one.x * 0.5 + two.x * 0.5
            }
        }
        return CGPoint(x: cx, y: cy)
    }

    func getBounds(
        contour contourRegion: VNFaceLandmarkRegion2D?,
        brow1 brow1Region: VNFaceLandmarkRegion2D?,
        brow2 brow2Region: VNFaceLandmarkRegion2D?,
        size: CGSize
    )
        -> CGRect
    {
        let emptyRect = CGRect()
        guard let region1 = brow1Region else {
            print("Nil face contour region")
            return emptyRect
        }
        guard let region2 = brow2Region else {
            print("Nil face contour region")
            return emptyRect
        }
        guard let region3 = contourRegion else {
            print("Nil face contour region")
            return emptyRect
        }
        let points1 = region1.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        let points2 = region2.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        let points3 = region3.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        var points: [CGPoint] = []
        points.append(contentsOf: points1)
        points.append(contentsOf: points2)
        points.append(contentsOf: points3)
        var minX: CGFloat = size.width
        var minY: CGFloat = size.height
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for pt in points {
            minX = min(minX, pt.x)
            minY = min(minY, pt.y)
            maxX = max(maxX, pt.x)
            maxY = max(maxY, pt.y)
        }
        if minX >= maxX || minY >= maxY {
            print("Invalid face region to find boudning box")
            return emptyRect
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func findRadius(
        _ faceContourRegion: VNFaceLandmarkRegion2D?,
        size: CGSize,
        center: CGPoint
    ) -> CGFloat {
        var r2: CGFloat = 0
        guard let region2 = faceContourRegion else {
            print("Nil face contour region")
            return r2
        }
        let points = region2.pointsInImage(imageSize: size)
            .map({ CGPoint(x: $0.x, y: size.height - 1 - $0.y) })
        for pt in points {
            let dx = pt.x - center.x
            let dy = pt.y - center.y
            let ptR2 = dx * dx + dy * dy
            if ptR2 > r2 {
                r2 = ptR2
            }
        }
        return sqrt(r2)
    }

    func detectOneFace(cgImage: CGImage) -> MyFace {
        let emptyShapes: [MyShape] = []  // empty shape list for error situation
        let emptyFace: MyFace = MyFace(
            shapes: emptyShapes,
            faceRect: CGRect(),
            centerShape: MyShape.emptyShape(),
            center: CGPoint(x: 20, y: 20),
            bounds: CGRect(),
            boundsShape: MyShape.emptyShape(),
            finalRect: CGRect(),
            finalShapes: [MyShape.emptyShape()]
        )
        print("Got an image of size \(cgImage.width) x \(cgImage.height).")
        let detectFacesRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([detectFacesRequest])
        } catch {
            print("Error performing face request")
            print(error)
            return emptyFace
        }
        guard let arr: [VNFaceObservation] = detectFacesRequest.results else {
            print("Nil results for face request")
            return emptyFace
        }
        print("Got \(arr.count) face results.")
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = arr
        qualityRequest.inputFaceObservations = arr
        do {
            try handler.perform([landmarksRequest, qualityRequest])
        } catch {
            print("Error performing face pair of requests")
            print(error)
            return emptyFace
        }
        guard let quality = qualityRequest.results,
            let qScore = quality[0].faceCaptureQuality
        else {
            print("Nil quality")
            return emptyFace
        }
        print("Quality score: \(qScore)")
        guard let landmarks = landmarksRequest.results,
            landmarks.count > 0
        else {
            print("Nil landmarks")
            return emptyFace
        }
        let rect = landmarks[0].boundingBox
        print("Landmark bbox: \(rect.minX), \(rect.minY) to \(rect.maxX), \(rect.maxY)")
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let shapes = [
            MyShape(region: landmarks[0].landmarks?.faceContour, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.leftEye, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.rightEye, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.noseCrest, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.leftEyebrow, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.rightEyebrow, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.innerLips, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.outerLips, size: imageSize),
            MyShape(region: landmarks[0].landmarks?.medianLine, size: imageSize),
        ]

        let center: CGPoint = tipOfNose(
            noseCrest: landmarks[0].landmarks?.noseCrest,
            median: landmarks[0].landmarks?.medianLine,
            size: imageSize)
        let rectRad: CGFloat = findRadius(
            landmarks[0].landmarks?.faceContour,
            size: imageSize,
            center: center
        )
        let faceRect: CGRect = CGRect(
            x: center.x - rectRad,
            y: center.y - rectRad,
            width: rectRad * 2,
            height: rectRad * 2
        )
        let myBounds: CGRect = getBounds(
            contour: landmarks[0].landmarks?.faceContour,
            brow1: landmarks[0].landmarks?.leftEyebrow,
            brow2: landmarks[0].landmarks?.rightEyebrow,
            size: imageSize
        )
        let centerPts: [CGPoint] = [
            CGPoint(x: center.x, y: center.y),
            CGPoint(x: center.x - rectRad, y: center.y),
            CGPoint(x: center.x, y: center.y),
            CGPoint(x: center.x, y: center.y - rectRad),
            CGPoint(x: center.x, y: center.y),
            CGPoint(x: center.x + rectRad, y: center.y),
            CGPoint(x: center.x, y: center.y),
            CGPoint(x: center.x, y: center.y + rectRad),
            CGPoint(x: center.x, y: center.y),
        ]
        //  2 3
        //  1 4
        let uno = CGPoint(x: myBounds.minX, y: myBounds.maxY)
        let dos = CGPoint(x: myBounds.minX, y: myBounds.minY)
        let tre = CGPoint(x: myBounds.maxX, y: myBounds.minY)
        let qua = CGPoint(x: myBounds.maxX, y: myBounds.maxY)
        // square with an X across it
        let bpts: [CGPoint] = [uno, dos, tre, qua, dos, tre, uno, qua]
        // This is unintuitive but since faces are 3-D, move the center in opposite direction
        // to capture ear on the back side.
        // So first: get a vector from center of myBounds (chin and brows) to tip-of-nose (center)
        let dx = myBounds.midX - center.x
        let dy = myBounds.midY - center.y
        // then move in opposite direction to capture ear sticking out of opposite side,
        // instead of a bunch of negative space on the front side of the face, in the
        // direction the nose is pointing
        let cx2 = (0.45 * center.x + 0.55 * myBounds.midX) + dx
        let cy2 = (0.45 * center.y + 0.55 * myBounds.midY) + dy
        // favor the generally larger rectangle, if there is a size discrepancy
        let r = 0.7 * rectRad + 0.3 * myBounds.avgDim * 0.5
        let finalRect = CGRect(x: cx2 - r, y: cy2 - r, width: r * 2, height: r * 2)
        let fpts: [CGPoint] = [
            finalRect.topLeft,
            finalRect.topRight,
            finalRect.bottomRight,
            finalRect.bottomLeft,
            finalRect.topLeft,
        ]
        return MyFace(
            shapes: shapes,
            faceRect: faceRect,
            centerShape: MyShape(
                points: centerPts,
                classification: .openPath
            ),
            center: center,
            bounds: myBounds,
            boundsShape: MyShape(
                points: bpts,
                classification: .openPath
            ),
            finalRect: finalRect,
            finalShapes: [MyShape(points: fpts, classification: .openPath)]
        )
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
    var projectModel: MDProject

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
        let path = "\(self.folderPath)/project.json"
        self.projectModel = MDProjectController.tryLoad(
            fromProjectPath: path,
            withDefaultWidth: baseWidth,
            defaultHeight: baseHeight
        )
        print("\(projectModel)")
        store.projectController = self
    }

    func walkAssets() -> [MDProjectAsset]? {
        var ret: [MDProjectAsset] = []
        walkAssetsInner(self.projectModel.rootImage, &ret)
        return ret
    }

    private func walkAssetsInner(_ asset: MDProjectAsset, _ ret: inout [MDProjectAsset]) {
        ret.append(asset)
        for sub in asset.subImages {
            walkAssetsInner(sub, &ret)
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
