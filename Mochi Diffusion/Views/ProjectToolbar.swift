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
        Button("Close", systemImage: "xmark.circle") {
            // TODO maybe write out project just in case?
            store.projectController = nil
        }

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

        Spacer(minLength: 10)

        Text(controller.projectStatusMessage)
            .frame(minWidth: 160)

        Spacer()

        TextField("foot", text: $controller.footStr)
            .frame(minWidth: 100)

        Toggle(isOn: $controller.shouldUseSmallestFace) {
            Text("Small Face")
        }
        .toggleStyle(CheckboxToggleStyle())
        .padding()

        Toggle(isOn: $controller.shouldMakePSD) {
            Text("Export PSD")
        }
        .toggleStyle(CheckboxToggleStyle())
        .padding()

        Button {
            guard let sdi = store.selected() else { return }
            print("path to selected image: \(sdi.path)")
            if let project = store.projectController {
                project.enqueueProjectTask(
                    shouldExportPSD: controller.shouldMakePSD,
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
                comment: "Enqueue Project"
            )
        }
        .disabled(
            store.projectController == nil || store.projectController!.isExecuting
        )
    }
}
