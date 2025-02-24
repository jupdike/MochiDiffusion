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

    var anns: ImageAnnotations
    let assets: AssetCollection

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
        self.anns = ImageAnnotations.find(inImage: cgImage)
        self.assets = AssetCollection(
            assets: self.anns.assets,
            folderPath: folderPath,
            store: store
        )
        self.assets.assets = self.assets.stage0to1()
        store.projectController = self
    }

    func actuallyExecutePlan() {
        Task {
            await self.assets.stage1to2()
        }
    }

}
