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
                let project = MDProject(
                    path: sdi.path,
                    cgImage: cgi,
                    controller: controller,
                    generator: generator
                )
                let path = "\(project.folderPath)/bg.png"
                let cgi2 = cgImage(fromPath: path)
                Image(cgi, scale: 1, label: Text("image label placeholder"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
                    .shadow(color: .black, radius: 8)
                    .padding()
            } else {
                Text("Failed to load image")
            }
        }
    }
}
