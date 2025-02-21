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
                let cgi = sdi.image,
                let projectController = store.projectController
            {
                GeometryReader { geometry in
                    let maxDim = min(geometry.size.height, geometry.size.width) * 0.95
                    getZStack()
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

    func getZStack() -> some View {
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
