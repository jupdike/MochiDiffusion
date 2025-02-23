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

struct Register: Identifiable, Equatable, Hashable {
    let scale: Double
    let offsetX: Int
    let offsetY: Int
    let nw: Int
    let nh: Int
    let id: UUID = UUID()
}

public struct SSAsset: Identifiable, Equatable, Hashable {
    var result: Register?
    // needs to be converted to result relative to parent, not relative to base
    var rectToBase: CGRect?
    var image: CGImage?
    public var id: UUID
    var parentId: UUID?

    var isBaseImage: Bool { parentId == nil }

    public let stage: AssetStage

    init(
        image: CGImage? = nil,
        result: Register? = nil,
        rectToBase: CGRect? = nil,
        parentId: UUID? = nil,
        stage: AssetStage? = nil,
        id: UUID? = nil
    ) {
        self.result = result
        self.rectToBase = rectToBase
        self.image = image
        self.id = id != nil ? id! : UUID()
        self.parentId = parentId
        if stage == nil {
            if parentId == nil {
                self.stage = .generatedNotUpscaled3
            } else {
                self.stage = .needsRectToParentResult0
            }
        } else {
            self.stage = stage!
        }
    }

    init(rectToBase: CGRect, parent: SSAsset) {
        self.init(image: nil, result: nil, rectToBase: rectToBase, parentId: parent.id)
    }

    static func getNodeById(assets: [SSAsset], id: UUID) -> SSAsset? {
        return assets.first { $0.id == id }
    }

    // in old baseImage coord space, not new scaled (maxScale) space
    func getOffsetRelativeToBase(assets: [SSAsset]) -> CGPoint {
        if self.isBaseImage {
            return CGPoint(x: 0, y: 0)
        }
        // else, have parent
        guard let register = self.result else {
            print("Expected to have a parent and a register with offset relative to parent")
            return CGPoint(x: -1337, y: -1337)
        }
        guard let pid = self.parentId else {
            print("Expected node parentId not to be nil, this should not happen")
            return CGPoint(x: -1337, y: -1337)
        }
        // makes multiple calls to this O(n^2) which is OK for low values of n
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Expected node to not be nil, this should not happen")
            return CGPoint(x: -1337, y: -1337)
        }
        let scaleParentToBase = parent.getScaleRelativeToBase(assets: assets)
        var ox = CGFloat(register.offsetX) * scaleParentToBase
        var oy = CGFloat(register.offsetY) * scaleParentToBase
        let po = parent.getOffsetRelativeToBase(assets: assets)
        ox += po.x
        oy += po.y
        let offset = CGPoint(x: ox, y: oy)
        return offset
    }

    // this is O(n) so the ForEach call is O(n^2) which should not be a problem for under a dozen images, or even higher
    // really, you shouldn't go for like hundreds of images, as this is untested :sucking air through teeth emoji:
    func getScaleRelativeToBase(assets: [SSAsset]) -> Double {
        var node = self
        var scale = 1.0
        while !node.isBaseImage {
            guard let register = node.result else {
                print("Expected to have a Register result if not a base image")
                break
            }
            scale *= register.scale
            if let pid = node.parentId,
                let parent = SSAsset.getNodeById(assets: assets, id: pid)
            {
                node = parent
            } else {
                print("Expected node to not be nil, this should not happen")
                break
            }
        }
        return scale
    }
}

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

struct ImageAnnotations: Hashable, Equatable, Identifiable {
    let id: UUID = UUID()
    let shapes: [MyShape]
    let faceRect: CGRect
    let centerShape: MyShape
    let center: CGPoint
    let bounds: CGRect
    let boundsShape: MyShape
    let finalRect: CGRect
    let finalShapes: [MyShape]
    let assets: [SSAsset]
}

public enum AssetStage {
    case needsRectToParentResult0
    case needsCrop1
    case cropScaled2
    case generatedNotUpscaled3
    case finalUpscaled4
}

class AssetCollection {
    public var baseImage: CGImage? { assets.count > 0 ? assets[0].image : nil }

    init(assets: [SSAsset]) {
        self.assets = assets
    }

    private func computeMaxScale() -> Double {
        var maxScale = 0.1
        for asset in assets {
            let scale = 1.0 / asset.getScaleRelativeToBase(assets: assets)
            maxScale = max(scale, maxScale)
        }
        return maxScale
    }

    public var assets: [SSAsset] = []
    var scaleCache: [Int: Double] = [:]

    // cache Max Scale for a given set of unique UUIDs
    public func getMaxScale() -> Double {
        let hash: Int = hashAllSets
        if let ret = scaleCache[hash] {
            return ret
        }
        let result = computeMaxScale()
        scaleCache[hash] = result
        return result
    }

    public func getTrueOffsetRelativeToParent(asset: SSAsset) -> CGPoint {
        if asset.isBaseImage {
            return CGPoint(x: 0, y: 0)
        }
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return CGPoint(x: -1337, y: -1337)
        }
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Assets besides baseImage should have a parent!")
            return CGPoint(x: -1337, y: -1337)
        }
        var pOrigin = CGPoint(x: 0, y: 0)
        if let parentRectToBase = parent.rectToBase {
            pOrigin = parentRectToBase.origin
        }
        guard let orig = asset.rectToBase?.origin else {
            print("Expected own rect to be non-null while converting rect to result")
            return CGPoint(x: -1337, y: -1337)
        }
        //let parentOffset = getTrueOffsetRelativeToParent(asset: parent)
        //let parentOriginToGrand = parentRectToBase.origin
        let scale = getScaleRelativeToParent(asset: asset)
        return CGPoint(
            x: (orig.x - pOrigin.x) / scale,
            y: (orig.y - pOrigin.y) / scale
        )
    }

    public func getScaleRelativeToParent(asset: SSAsset) -> CGFloat {
        if asset.isBaseImage {
            return 1.0
        }
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return -1337.0
        }
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Assets besides baseImage should have a parent!")
            return -1337.0
        }
        var w: CGFloat = CGFloat(baseImage!.width)
        if let pRect = parent.rectToBase {
            w = CGFloat(pRect.width)
        }
        guard let rect = asset.rectToBase else {
            print("Expected own rect to be non-null while converting rect to result")
            return -1337.0
        }
        let scale: Double = rect.width / w
        return scale
    }

    public func getTrueScale(asset: SSAsset) -> Double {
        let max = getMaxScale()
        let scale = asset.getScaleRelativeToBase(assets: assets)
        // returns 1.0 for smallest image, and maxScale for biggest (base) image
        return max * scale
    }

    public func getTrueSize(asset: SSAsset) -> CGSize {
        guard let image = asset.image else {
            print("getTrueSize expected asset.image != nil")
            return CGSize(width: -1, height: -1)
        }
        let trueScale = getTrueScale(asset: asset)
        let bigw = round(trueScale * CGFloat(image.width))
        let bigh = round(trueScale * CGFloat(image.height))
        return CGSize(width: bigw, height: bigh)
    }

    public var hashAllSets: Int {
        var hasher = Hasher()
        for asset in assets {
            asset.hash(into: &hasher)
        }
        return hasher.finalize()
    }

    func verifyParentage(_ asset: SSAsset) -> Bool {
        var node = asset
        if node.isBaseImage {
            //print("isBaseImage: \(node.id)")
        }
        while !node.isBaseImage {
            guard let pid = node.parentId else {
                print("Assets besides baseImage should have a parentId!")
                return false
            }
            guard let n = SSAsset.getNodeById(assets: assets, id: pid) else {
                return false
            }
            //print("\(node.id) -- parent is --> \(n.id)")
            node = n
        }
        return true
    }

    func rectToParentResult(asset: SSAsset) -> SSAsset {
        //getTrueScale(asset: asset) // TODO this is wrong because it needs to be relative to parent!
        let scale = getScaleRelativeToParent(asset: asset)
        let offset = getTrueOffsetRelativeToParent(asset: asset)
        // need correct scale to get correct nw, nh
        let nw = Int(scale * CGFloat(baseImage!.width))
        let nh = Int(scale * CGFloat(baseImage!.height))
        let reg = Register(
            scale: scale,
            offsetX: Int(offset.x),
            offsetY: Int(offset.y),
            nw: nw, nh: nh
        )
        print("offset: \(reg.offsetX), \(reg.offsetY) -- nw x nh: \(nw) x \(nh)")
        return SSAsset(
            image: nil,
            result: reg,
            parentId: asset.parentId,
            stage: .needsCrop1,
            id: asset.id
        )
    }

    func testWalk01() -> [SSAsset] {
        var newAssets: [SSAsset] = []
        for asset in assets {
            //print("----\nVerifying parentage")
            if !verifyParentage(asset) {
                print("PROBLEM with parentage of asset \(asset.id)")
            }
            if asset.stage != .needsRectToParentResult0 {
                newAssets.append(asset)  // base asset
            }
            if asset.stage == .needsRectToParentResult0 {
                let newAsset = rectToParentResult(asset: asset)
                newAssets.append(newAsset)
            }
        }
        return newAssets
    }
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

    func testWith3(cgImage: CGImage) {
        let _ = MDProjectController.findAnnotations(cgImage: cgImage)
    }

    static func tipOfNose(
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

    static func getBounds(
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

    static func findRadius(
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

    // maybe this is really just a torso finder?
    static func findBodyRects(cgImage: CGImage) -> CGRect? {
        let detectHumanRequest = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([detectHumanRequest])
        } catch {
            print("Error performing face request")
            print(error)
            return nil
        }
        guard let arr: [VNHumanObservation] = detectHumanRequest.results,
            arr.count > 0
        else {
            print("No human observed?")
            return nil
        }
        print("ARR -- human rectangles count = \(arr.count)")
        for vnho in arr {
            print("VNHO - upperOnly? \(vnho.upperBodyOnly) -- \(vnho.boundingBox)")
        }
        return arr[0].boundingBox
    }

    static func findAnnotations(cgImage: CGImage) -> ImageAnnotations {
        let emptyShapes: [MyShape] = []  // empty shape list for error situation
        let emptyAnn: ImageAnnotations = ImageAnnotations(
            shapes: emptyShapes,
            faceRect: CGRect(),
            centerShape: MyShape.emptyShape(),
            center: CGPoint(x: 20, y: 20),
            bounds: CGRect(),
            boundsShape: MyShape.emptyShape(),
            finalRect: CGRect(),
            finalShapes: [MyShape.emptyShape()],
            assets: []
        )
        print("Got an image of size \(cgImage.width) x \(cgImage.height).")
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let detectFacesRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([detectFacesRequest])
        } catch {
            print("Error performing face request")
            print(error)
            return emptyAnn
        }
        guard let arr: [VNFaceObservation] = detectFacesRequest.results else {
            print("Nil results for face request")
            return emptyAnn
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
            return emptyAnn
        }
        guard let quality = qualityRequest.results,
            let qScore = quality[0].faceCaptureQuality
        else {
            print("Nil quality")
            return emptyAnn
        }
        print("Quality score: \(qScore)")
        guard let landmarks = landmarksRequest.results,
            landmarks.count > 0
        else {
            print("Nil landmarks")
            return emptyAnn
        }
        let rect = landmarks[0].boundingBox
        print("Landmark bbox: \(rect.minX), \(rect.minY) to \(rect.maxX), \(rect.maxY)")
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
            size: imageSize
        )
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
        // uses brow to nose instead, but if the head is tilted down, this will help capture
        // more of top of head
        let noseToChin = abs(myBounds.minY - center.y)
        let hRad = r + noseToChin
        let headRect = CGRect(
            x: cx2 - hRad,
            // don't let head rect stick out from face rect
            y: max(0, max(finalRect.maxY - hRad * 2, cy2 - hRad + dy - hRad * 0.4)),
            width: hRad * 2,
            height: hRad * 2
        )
        var bodyRectScaled: CGRect = CGRect(
            x: headRect.minX,
            y: headRect.minY,
            width: headRect.width,
            height: headRect.height * 2.0
        )
        if let bodyRect: CGRect = findBodyRects(cgImage: cgImage) {
            let h = bodyRect.height * imageSize.height
            bodyRectScaled = CGRect(
                x: bodyRect.origin.x * imageSize.width,
                y: imageSize.height - 1 - bodyRect.origin.y * imageSize.height - h,
                width: bodyRect.width * imageSize.width,
                height: h
            )
        }
        let oneHeadA = 1.2 * (0.5 * headRect.height + 0.5 * faceRect.height)
        let oneHeadB = 1.2 * (bodyRectScaled.maxY - faceRect.maxY)
        let oneHeadC = 0.5 * oneHeadA + 0.5 * oneHeadB
        let oneHead = 1.1 * (0.5 * oneHeadC + 0.5 * max(oneHeadC, bodyRectScaled.width))
        let rBottom = myBounds.maxY + oneHead * 0.95
        let rCenter = bodyRectScaled.midX + 0.5
        let rTop = min(imageSize.height - 1 - oneHead, rBottom - oneHead)
        let anotherRect = CGRect(
            x: rCenter - oneHead * 0.5, y: rTop, width: oneHead, height: oneHead
        )
        let comboMidX = 0.5 * headRect.midX + 0.5 * anotherRect.midX
        let comboHeight = anotherRect.maxY - headRect.minY
        let comboRect = CGRect(
            x: comboMidX - comboHeight * 0.5,
            y: headRect.minY,
            width: comboHeight,
            height: comboHeight
        )
        let comboArea = comboRect.width * comboRect.height
        let imageArea = imageSize.width * imageSize.height
        //let belowRect
        let belowTop = 0.5 * anotherRect.midY + 0.5 * anotherRect.maxY
        let belowRect = CGRect(
            x: anotherRect.minX,
            y: min(imageSize.height - 1 - anotherRect.height, belowTop),
            width: anotherRect.width,
            height: anotherRect.height
        )
        let overlapRect = belowRect.intersection(anotherRect)
        let overlapRatio =
            overlapRect.width * overlapRect.height / (anotherRect.width * anotherRect.height)
        let bigBelowRect = CGRect(
            x: anotherRect.midX - 0.5 * comboRect.width,
            y: min(imageSize.height - 1 - comboRect.height, belowTop),
            width: comboRect.width,
            height: comboRect.height
        )
        let bigComboOverlap = bigBelowRect.intersection(comboRect)
        let bigOverlapRatio = bigComboOverlap.width * bigComboOverlap.height / comboArea
        let bigEnough = !(comboArea > 0.9 * imageArea)
        // if bigEnough, also add some rectangles below anotherRect
        let extraY = belowRect.maxY  // smallish rectangle
        let extraRect = CGRect(
            x: belowRect.minX,
            y: min(imageSize.height - 1 - belowRect.height, extraY),
            width: belowRect.width,
            height: belowRect.height
        )
        let extraOverlapRect = extraRect.intersection(belowRect)
        let extraOverlapRatio =
            extraOverlapRect.width * extraOverlapRect.height / (belowRect.width * belowRect.height)
        // now gather up relevant rectangles
        var fShapes: [MyShape] = []
        var assets: [SSAsset] = []
        let baseAsset = SSAsset(image: cgImage)
        assets.append(baseAsset)
        var comboOrFull = baseAsset
        var belowOrFull = baseAsset
        if bigEnough {
            if bigOverlapRatio < 0.4 {
                fShapes.append(
                    MyShape(points: bigBelowRect.toPathPoints(), classification: .openPath)
                )
                assets.append(SSAsset(rectToBase: bigBelowRect, parent: baseAsset))
            }
            fShapes.append(MyShape(points: comboRect.toPathPoints(), classification: .openPath))
            comboOrFull = SSAsset(rectToBase: comboRect, parent: baseAsset)
            assets.append(comboOrFull)
            if extraOverlapRatio < 0.5 {
                fShapes.append(MyShape(points: extraRect.toPathPoints(), classification: .openPath))
                let bigBelow = SSAsset(rectToBase: extraRect, parent: baseAsset)
                assets.append(bigBelow)
                belowOrFull = bigBelow
            }
        }
        if bigEnough && overlapRatio < 0.7 {
            fShapes.append(MyShape(points: belowRect.toPathPoints(), classification: .openPath))
            assets.append(SSAsset(rectToBase: belowRect, parent: belowOrFull))
        }
        fShapes.append(MyShape(points: anotherRect.toPathPoints(), classification: .openPath))
        assets.append(SSAsset(rectToBase: anotherRect, parent: comboOrFull))
        fShapes.append(MyShape(points: headRect.toPathPoints(), classification: .openPath))
        let head = SSAsset(rectToBase: headRect, parent: comboOrFull)
        assets.append(head)
        fShapes.append(MyShape(points: finalRect.toPathPoints(), classification: .openPath))
        assets.append(SSAsset(rectToBase: finalRect, parent: head))
        return ImageAnnotations(
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
            finalShapes: fShapes,
            assets: assets
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
        self.anns = MDProjectController.findAnnotations(cgImage: cgImage)
        self.assets = AssetCollection(assets: self.anns.assets)
        self.assets.assets = self.assets.testWalk01()
        store.projectController = self
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
