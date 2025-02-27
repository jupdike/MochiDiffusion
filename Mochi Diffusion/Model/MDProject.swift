//
//  MDProject.swift
//  Mochi Diffusion Project Model / Controller
//
//  Created by Jared Updike on 12/22/24.
//

import SwiftUI
import Vision

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

    func logMessage(_ message: String) async {
        await self.controller.setProjectStatusMessage(message)
    }

    var currentScale = ""
    func setMaxScale() {
        let scale = self.projectTask.assetCollection.computeMaxScale()
        currentScale = "\(String(format: "%1.2f", scale))x"
    }

    var isExecuting = false
    var readyToEnqueue: Bool {
        store.projectTaskQueue.count > 0 && !isExecuting
    }

    func executeOneTaskProject(_ task: ProjectTask) async {
        await task.assetCollection.stage1to2()
        if task.shouldExportPSD {
            await task.doExport()
        }
    }

    func executeProjectQueue() async {
        print("execute \(store.projectTaskQueue.count) queued projects in store.projectTaskQueue")
        isExecuting = true
        for task in store.projectTaskQueue {
            await executeOneTaskProject(task)
        }
        store.projectTaskQueue = []
        isExecuting = false
    }

    var projectTask: ProjectTask

    init(
        path: String,
        cgImage: CGImage,
        store: ImageStore,
        controller: ImageController,
        generator: ImageGenerator
    ) {
        self.store = store
        self.controller = controller
        self.generator = generator
        let folderPath = MDProjectController.imagePathToProjectFolder(path)
        self.folderPath = folderPath
        //let path = "\(self.folderPath)/project.json"
        self.projectTask = ProjectTask(
            path: path,
            cgImage: cgImage,
            store: store
        )
        store.projectController = self
        self.setMaxScale()
    }

    func enqueueProjectTask(
        shouldExportPSD: Bool,
        strength: Double,
        prompt: String,
        negativePrompt: String
    ) {
        // TODO allow user to opt-out in UI
        self.projectTask.shouldExportPSD = shouldExportPSD
        self.projectTask.strength = strength
        self.projectTask.prompt = prompt
        self.projectTask.negativePrompt = negativePrompt
        store.projectTaskQueue.append(self.projectTask)
    }

}
