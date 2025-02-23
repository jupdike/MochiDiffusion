//
//  ProjectView.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 12/4/24.
//

import SwiftUI
import Vision

struct FaceLandmark: Shape {
    let myShape: MyShape
    func path(in rect: CGRect) -> Path {
        let path = CGMutablePath()
        path.move(to: myShape.points[0])
        for index in 1..<myShape.points.count {
            path.addLine(to: myShape.points[index])
        }
        if myShape.pointsClassification == .closedPath {
            path.closeSubpath()
        }
        return Path(path)
    }
}

struct ProjectView: View {
    @Environment(ImageStore.self) private var store: ImageStore
    @EnvironmentObject private var controller: ImageController
    @Environment(ImageGenerator.self) private var generator: ImageGenerator

    var body: some View {
        VStack(spacing: 0) {
            if let sdi = store.selected(),
                let cgi = sdi.image,
                let projectController = store.projectController,
                let myFace: MyFace = Optional.some(
                    projectController.detectOneFace(cgImage: cgi)
                )
            {
                GeometryReader { geometry in
                    let maxDim = min(geometry.size.height, geometry.size.width) * 0.95
                    getZStack(myFace)
                        .frame(
                            width: geometry.frame(in: .global).width,
                            height: geometry.frame(in: .global).height
                        )
                        .scaleEffect(maxDim / 512.0, anchor: .center)
                }
            } else {
                Text("Failed to load image")
            }
        }
    }

    func getZStack(_ face: MyFace) -> some View {
        if let sdi = store.selected(),
            let cgi = sdi.image,
            let lineWidth = Optional.some(
                ceil(Double(max(cgi.width, cgi.height)) * 0.001)
            )
        {
            AnyView(
                ZStack {
                    Image(cgi, scale: 1.0, label: Text("an image the user selected"))
                        .resizable()
                        .frame(
                            width: CGFloat(cgi.width),
                            height: CGFloat(cgi.height),
                            alignment: .topLeading
                        )
                    ForEach(face.shapes) { shape in
                        FaceLandmark(myShape: shape)
                            .stroke(.orange, lineWidth: lineWidth)
                            .frame(
                                width: CGFloat(cgi.width),
                                height: CGFloat(cgi.height),
                                alignment: .topLeading
                            )
                    }
                    FaceLandmark(myShape: face.boundsShape)
                        .stroke(.red, lineWidth: lineWidth)
                        .frame(
                            width: CGFloat(cgi.width),
                            height: CGFloat(cgi.height),
                            alignment: .topLeading
                        )
                    FaceLandmark(myShape: face.centerShape)
                        .stroke(.yellow, lineWidth: lineWidth)
                        .frame(
                            width: CGFloat(cgi.width),
                            height: CGFloat(cgi.height),
                            alignment: .topLeading
                        )
                    ForEach(face.finalShapes) { shape in
                        FaceLandmark(myShape: shape)
                            .stroke(.white, lineWidth: lineWidth * 2)
                            .frame(
                                width: CGFloat(cgi.width),
                                height: CGFloat(cgi.height),
                                alignment: .topLeading
                            )
                    }
                }
            )
        } else {
            AnyView(Text("Failed to load image"))
        }
    }

    func getZStackOld() -> some View {
        if let sdi = store.selected(),
            let cgi = sdi.image,
            let projectController = store.projectController,
            let assets = projectController.walkAssets(),
            assets.count > 0
        {
            let path2 = "\(projectController.folderPath)/bg.png"
            let cgi2 = cgImage(fromPath: path2)!
            let path3 = "\(projectController.folderPath)/over1.png"
            let cgi3 = cgImage(fromPath: path3)!
            return AnyView(
                ZStack {
                    ForEach(assets) { (asset: MDProjectAsset) in
                        Image(
                            cgi,
                            scale: CGFloat(asset.width / projectController.projectModel.baseWidth),
                            label: Text("\(asset.id)")
                        )
                        .resizable()
                        .frame(
                            width: CGFloat(asset.width),
                            height: CGFloat(asset.height),
                            alignment: .topLeading
                        )
                        .offset(x: 0, y: 0)  // TODO use correct numbers
                    }
                }
            )
        } else {
            return AnyView(Text("Failed to load image"))
        }
    }
}
