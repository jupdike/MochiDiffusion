//
//  ProjectView.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 12/4/24.
//

import SwiftUI

struct ProjectToolbar: View {
    @Environment(ImageStore.self) private var store: ImageStore
    @EnvironmentObject private var controller: ImageController
    @Environment(ImageGenerator.self) private var generator: ImageGenerator

    var body: some View {
        HStack {

            if case .running(_) = generator.state {
                Text("GENERATING")
            } else if case .loading = generator.state {
                Text("LOADING")
            } else {
                Text("READY")
            }

            Text(controller.projectStatusMessage)
                .frame(height: 120)

            Button {
                print("pressed Button")
                guard let sdi = store.selected() else { return }
                guard let cgi = sdi.image else { return }
                print("path to selected image: \(sdi.path)")
                let _ = MDProject(
                    path: sdi.path,
                    cgImage: cgi,
                    controller: controller,
                    generator: generator
                )
            } label: {
                Text(
                    "Test",
                    comment: "A Button for Testing MDProject functionality"
                )
            }

            Button {
                store.showMain = true
            } label: {
                Text(
                    "X",
                    comment: "Close Project mode and return to Main view"
                )
            }
        }
    }
}
