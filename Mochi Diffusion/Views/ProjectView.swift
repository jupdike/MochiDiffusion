//
//  ProjectView.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 12/4/24.
//

import SwiftUI

struct ProjectView: View {
    @Environment(ImageStore.self) private var store: ImageStore
    @EnvironmentObject private var controller: ImageController
    @Environment(ImageGenerator.self) private var generator: ImageGenerator

    var body: some View {
        VStack(spacing: 0) {
            if let sdi = store.selected(),
                let cgi = sdi.image
            {
                let project = MDProjectController(
                    path: sdi.path,
                    cgImage: cgi,
                    store: store,
                    controller: controller,
                    generator: generator
                )
                let path2 = "\(project.folderPath)/bg.png"
                let cgi2 = cgImage(fromPath: path2)!
                let path3 = "\(project.folderPath)/over1.png"
                let cgi3 = cgImage(fromPath: path3)!
                GeometryReader { geometry in
                    let maxDim = min(geometry.size.height, geometry.size.width) * 0.95
                    ZStack {
                        Image(cgi, scale: 1, label: Text("image label placeholder"))
                            .resizable()
                            //.aspectRatio(contentMode: .fit)
                            .frame(width: 512.0, height: 512.0, alignment: .topLeading)
                            .offset(x: 0, y: 0)
                            .padding(4)
                            .shadow(color: .black, radius: 8)
                            .padding()
                        Image(cgi3, scale: 0.5, label: Text("image label placeholder"))
                            .resizable()
                            .frame(width: 256.0, height: 256.0, alignment: .topLeading)
                            .offset(x: -0.0, y: -128.0)
                            .padding(4)
                    }
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
}
