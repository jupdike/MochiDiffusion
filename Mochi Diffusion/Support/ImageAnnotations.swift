//
//  ImageAnnotations.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 2/24/25.
//

import Vision

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
    let assets: [ProjectAsset]

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

    static func find(inImage cgImage: CGImage) -> ImageAnnotations {
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
        let smallDim = myBounds.avgDim
        let smallCenterX = (0.5 * center.x + 0.5 * myBounds.midX)
        let smallCenterY = (0.5 * center.y + 0.5 * myBounds.midY)
        let smallFaceRect = CGRect(
            x: smallCenterX - 0.5 * smallDim,
            y: smallCenterY - 0.5 * smallDim,
            width: smallDim,
            height: smallDim
        )
        let noseToChin = abs(myBounds.minY - center.y)
        let hRad = r + noseToChin
        var headRect = CGRect(
            x: cx2 - hRad,
            // don't let head rect stick out from face rect
            y: max(0, max(finalRect.maxY - hRad * 2, cy2 - hRad + dy - hRad * 0.4)),
            width: hRad * 2,
            height: hRad * 2
        )
        let baseRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
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
        bodyRectScaled = bodyRectScaled.horizKeepWithin(baseRect)
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

        let lrW = anotherRect.width * 0.6
        let lrH = anotherRect.height * 0.6
        let leftRect = CGRect(
            x: anotherRect.minX, y: anotherRect.midY - 0.5 * lrH,
            width: lrW, height: lrH
        )
        let rightRect = CGRect(
            x: anotherRect.maxX - 1 - lrW, y: anotherRect.midY - 0.5 * lrH,
            width: lrW, height: lrH
        )

        let comboMidX = 0.5 * headRect.midX + 0.5 * anotherRect.midX
        let comboHeight = anotherRect.maxY - headRect.minY
        var comboRect = CGRect(
            x: comboMidX - comboHeight * 0.5,
            y: headRect.minY,
            width: comboHeight,
            height: comboHeight
        )
        comboRect = comboRect.horizKeepWithin(baseRect)

        let comboArea = comboRect.width * comboRect.height
        let imageArea = imageSize.width * imageSize.height
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
        if bigEnough {
            print("comboRect: \(comboRect)")
            print("headRect before: \(headRect)")
            headRect = headRect.horizKeepWithin(comboRect)
            print("headRect after: \(headRect)")
        }
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
        var assets: [ProjectAsset] = []
        let baseAsset = ProjectAsset(image: cgImage)
        assets.append(baseAsset)
        var comboOrFull = baseAsset
        var belowOrFull = baseAsset
        if bigEnough {
            if bigOverlapRatio < 0.6 {
                fShapes.append(
                    MyShape(points: bigBelowRect.toPathPoints(), classification: .openPath)
                )
                assets.append(ProjectAsset(rectToBase: bigBelowRect, parent: baseAsset))
            }
            fShapes.append(MyShape(points: comboRect.toPathPoints(), classification: .openPath))
            comboOrFull = ProjectAsset(rectToBase: comboRect, parent: baseAsset)
            assets.append(comboOrFull)
            if extraOverlapRatio < 0.5 {
                fShapes.append(MyShape(points: extraRect.toPathPoints(), classification: .openPath))
                let bigBelow = ProjectAsset(rectToBase: extraRect, parent: baseAsset)
                assets.append(bigBelow)
                belowOrFull = bigBelow
            }
        }
        if bigEnough && overlapRatio < 0.7 {
            fShapes.append(MyShape(points: belowRect.toPathPoints(), classification: .openPath))
            assets.append(ProjectAsset(rectToBase: belowRect, parent: belowOrFull))
        }
        fShapes.append(MyShape(points: anotherRect.toPathPoints(), classification: .openPath))
        let another = ProjectAsset(rectToBase: anotherRect, parent: comboOrFull)
        assets.append(another)

        fShapes.append(MyShape(points: leftRect.toPathPoints(), classification: .openPath))
        assets.append(ProjectAsset(rectToBase: leftRect, parent: another))
        fShapes.append(MyShape(points: rightRect.toPathPoints(), classification: .openPath))
        assets.append(ProjectAsset(rectToBase: rightRect, parent: another))

        fShapes.append(MyShape(points: headRect.toPathPoints(), classification: .openPath))
        let head = ProjectAsset(rectToBase: headRect, parent: comboOrFull)
        assets.append(head)
        fShapes.append(MyShape(points: finalRect.toPathPoints(), classification: .openPath))
        let face = ProjectAsset(rectToBase: finalRect, parent: head)
        assets.append(face)
        fShapes.append(MyShape(points: smallFaceRect.toPathPoints(), classification: .openPath))
        assets.append(ProjectAsset(rectToBase: smallFaceRect, parent: face))

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
}
