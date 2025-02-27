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
            //Spacer(minLength: 100)

            if case .running(_) = generator.state {
                Text("GENERATING")
            } else if case .loading = generator.state {
                Text("LOADING")
            } else {
                Text("READY")
            }

            if case .running(let progress) = generator.state, let progress = progress,
                progress.stepCount > 0
            {
                let step = progress.step + 1
                let stepValue = Double(step) / Double(progress.stepCount)

                Button {
                    //self.isStatusPopoverShown.toggle()
                } label: {
                    CircularProgressView(progress: stepValue)
                        .frame(width: 16, height: 16)
                }
            } else if case .loading = generator.state {
                Button {
                    //self.isStatusPopoverShown.toggle()
                } label: {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                }
            }

            Text(controller.projectStatusMessage)
                .frame(height: 120)

            Button {
                guard let sdi = store.selected() else { return }
                print("path to selected image: \(sdi.path)")
                if let project = store.projectController {
                    project.enqueueProjectTask(
                        shouldExportPSD: true,
                        strength: controller.strength,
                        prompt: controller.prompt,
                        negativePrompt: controller.negativePrompt
                    )
                } else {
                    print("store somehow does not have a projectController")
                }
            } label: {
                Text(
                    "Enqueue",
                    comment: "A Button for Testing MDProject functionality"
                )
            }
            .disabled(
                store.projectController == nil || store.projectController!.isExecuting
            )

            Text(
                store.projectController != nil
                    ? store.projectController!.currentScale
                    : "")

            Button {
                // TODO maybe write out project just in case?
                store.projectController = nil
            } label: {
                Text(
                    "X",
                    comment: "Close Project mode and return to Main view"
                )
            }
        }
    }
}
