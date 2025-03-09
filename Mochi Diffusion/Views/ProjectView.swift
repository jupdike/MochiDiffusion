//
//  ProjectView.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 12/4/24.
//

import SwiftUI
import Vision

struct AnnotationShape: Shape {
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
            if let projectController = store.projectController,
                let anns: ImageAnnotations = Optional.some(
                    projectController.projectTask.anns
                )
            {
                GeometryReader { geometry in
                    let maxDim = min(geometry.size.height, geometry.size.width) * 0.95
                    getZStack(anns)
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
        .navigationSubtitle(
            store.projectController != nil
                ? store.projectController!.currentScale
                : ""
        )
    }

    func getZStack(_ anns: ImageAnnotations) -> some View {
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
                    ForEach(anns.shapes) { shape in
                        AnnotationShape(myShape: shape)
                            .stroke(.orange, lineWidth: lineWidth)
                            .frame(
                                width: CGFloat(cgi.width),
                                height: CGFloat(cgi.height),
                                alignment: .topLeading
                            )
                    }
                    AnnotationShape(myShape: anns.boundsShape)
                        .stroke(.red, lineWidth: lineWidth)
                        .frame(
                            width: CGFloat(cgi.width),
                            height: CGFloat(cgi.height),
                            alignment: .topLeading
                        )
                    AnnotationShape(myShape: anns.centerShape)
                        .stroke(.yellow, lineWidth: lineWidth)
                        .frame(
                            width: CGFloat(cgi.width),
                            height: CGFloat(cgi.height),
                            alignment: .topLeading
                        )
                    ForEach(anns.limbs) { shape in
                        AnnotationShape(myShape: shape)
                            .stroke(.green, lineWidth: lineWidth)
                            .frame(
                                width: CGFloat(cgi.width),
                                height: CGFloat(cgi.height),
                                alignment: .topLeading
                            )
                    }
                    ForEach(anns.finalShapes) { shape in
                        AnnotationShape(myShape: shape)
                            .stroke(.cyan, lineWidth: lineWidth * 2)
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
}
