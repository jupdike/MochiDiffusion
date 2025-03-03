//
//  ProjectTask.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 2/26/25.
//

class ProjectTask {
    let assetCollection: AssetCollection
    var assets: [ProjectAsset] { assetCollection.assets }
    let store: ImageStore
    let anns: ImageAnnotations
    let folderPath: String
    var strength: Double = 0.5
    var prompt = ""
    var negativePrompt = ""
    var shouldExportPSD = true

    init(
        path: String,
        cgImage: CGImage,
        store: ImageStore,
        shouldUseSmallestFace: Bool
    ) {
        self.store = store
        self.anns = ImageAnnotations.find(
            inImage: cgImage,
            shouldUseSmallestFace: shouldUseSmallestFace
        )
        self.folderPath = MDProjectController.imagePathToProjectFolder(path)
        self.assetCollection = AssetCollection(
            assets: self.anns.assets,
            folderPath: folderPath,
            store: store
        )
        self.assetCollection.assets = self.assetCollection.stage0to1()
    }

    private func writeOneAssetTo(psdWriter w: PSDWriter, asset: ProjectAsset) async {
        let maxScale = assetCollection.getMaxScale()
        if assets.count < 2 {
            print("SnapScale export requires at least two images")
            return
        }
        let baseAsset = assets[0]
        guard let img = asset.image else {
            print("")
            return
        }
        let trueScale = assetCollection.getTrueScale(asset: asset)
        print("trueScale: \(trueScale)")
        let trueSize = assetCollection.getTrueSize(asset: asset)
        let nw = Int(trueSize.width)
        let nh = Int(trueSize.height)
        let nameStr =
            "\(asset == baseAsset ? "BG" : "FG") \(Int(trueSize.width)) x \(Int(trueSize.height))"
        print("Layer named: \(nameStr)")
        let trueOffset = asset.getOffsetRelativeToBase(assets: assets)
        print("Offset relative to base: \(trueOffset.x), \(trueOffset.y)")
        print("Inverting scales results in img upscaled to \(trueSize.width) x \(trueSize.height)")
        var outImg = img
        // keep unscaled 1.0 image as is, otherwise upscale
        // scale of 0.9999999 needs to work as well
        let shouldKeepImage = trueScale == 1.0 || (nw == img.width && nh == img.height)
        if !shouldKeepImage {
            print("Starting upscale ...")
            guard
                let cgiUpscaled =
                    await Upscaler.shared.upscale(
                        cgImage: img,
                        upscaledWidth: Int(trueSize.width),
                        upscaledHeight: Int(trueSize.height)
                    )
            else {
                print("Failed to upscale img")
                return
            }
            print("Finished upscale")
            outImg = cgiUpscaled
        }
        // OK, write out a layer to PSD file
        print("Verifying new size of \(outImg.width), \(outImg.height)")
        // everything in the new space, not the old baseImage coord space
        let dx: Double = Double(trueOffset.x) * maxScale
        let dy: Double = Double(trueOffset.y) * maxScale
        w.addLayer(
            with: outImg,
            andName: nameStr,
            andOpacity: 1.0,
            andOffset: CGPoint(
                x: baseAsset == asset ? 0 : dx,
                y: baseAsset == asset ? 0 : dy
            )
        )
    }

    private func writeToUrl(psdWriter w: PSDWriter, toUrl outputUrl: URL) async {
        let psd: Data = w.createPSDData()
        do {
            try psd.write(to: outputUrl)
            print("Wrote out \(outputUrl.absoluteString)")
            // on Mac get permission to write to Downloads folder
            // then copy file there under new, unique filename IMG_xyzw.psd
            let _ = Autosave.shared.copyFileToDownloadsWithUniqueName(url: outputUrl)
        } catch {
            print("Failed to write PSD to \(outputUrl.absoluteString)")
        }
    }

    func logMessage(_ message: String) async {
        guard let controller = store.projectController else {
            print("No store.projectController to log a message: \(message)")
            return
        }
        await controller.logMessage(message)
    }

    func doExport() async {
        let tmpFolder = NSTemporaryDirectory()

        if assets.count < 2 {
            print("SnapScale export requires at least two images")
            return
        }
        let baseAsset = assets[0]
        let bigSize = assetCollection.getTrueSize(asset: baseAsset)

        // OK, write out a PSD file
        print("Verifying new size of \(bigSize.width), \(bigSize.height)")
        guard let w = PSDWriter(documentSize: bigSize) else {
            print("Failed to create PDSWriter of size \(bigSize)")
            return
        }

        var count = 1
        let total = assets.count
        for asset in assets {
            let trueScale = assetCollection.getTrueScale(asset: asset)
            let tsStr = String(format: "%1.2f", trueScale)
            await logMessage("(\(count)/\(total)) Upscaling \(tsStr)x...")
            await writeOneAssetTo(psdWriter: w, asset: asset)
            count += 1
        }
        await logMessage("Exporting...")
        let out = "\(tmpFolder)IMG.psd"
        let outputUrl = URL(fileURLWithPath: out)
        await writeToUrl(psdWriter: w, toUrl: outputUrl)
        await logMessage("Exported")
    }

    var n = 1
    var i = 1
    func stage1to2() async {
        n = assets.count
        // baseImage is already ... based! but write it out to project folder to see all assets together
        let firstBaseAsset = assets[0]
        let bimg = firstBaseAsset.image!
        let uuid = UUID()
        // load the image and return it so it can possibly be used as input
        if bimg.trySaveToPng(URL(fileURLWithPath: "\(folderPath)/\(uuid).png")) {
            print("wrote out one PNG")
        }
        i = 2
        while true {
            if let oneChanged = await processOne(task: self) {
                // replace in-place over and over, to make sure we can use previous images
                assetCollection.assets = assetCollection.assetReplacing(oneChanged.id, oneChanged)
                await logMessage("(\(i)/\(n)) Done")
                i += 1
            } else {
                break
            }
        }
    }

    private func doCropScaleExport(asset: ProjectAsset) async -> CGImage? {
        guard let pid = asset.parentId else {
            print("Should not happen: parentId")
            return nil
        }
        guard let parent = ProjectAsset.getNodeById(assets: assets, id: pid) else {
            print("Should not happen: parent is nil")
            return nil
        }
        guard let image = parent.image else {
            print("Should not happen: image is nil")
            return nil
        }
        let rect = asset.getCropRect()
        guard let cropImg = image.cropping(to: rect) else {
            print("Failed to get non-nil crop of input image")
            return nil
        }
        let cgi = await cropScaleExportPhase2(
            cropImg,
            origWidth: image.width,
            origHeight: image.height
        )
        return cgi
    }

    private func cropScaleExportPhase2(
        _ cropImg: CGImage,
        origWidth w: Int,
        origHeight h: Int
    ) async -> CGImage? {
        print("Phase 2: image = \(cropImg.width) by \(cropImg.height)")
        print("Upscale me to \(w) x \(h)")
        print("Starting upscale ...")
        let s = CGFloat(w) / CGFloat(cropImg.width)
        await logMessage("(\(i)/\(n)) Upscaling (\(String(format: "%1.2f", s))x)")
        let upped = await Upscaler.shared.upscale(
            cgImage: cropImg,
            upscaledWidth: w,
            upscaledHeight: h
        )
        guard let cgiUpscaled = upped else {
            print("Failed to upscale cropped image")
            return nil
        }
        //currentMessage = "Upscaled"
        //let tmpFolder = NSTemporaryDirectory()
        //let out = "\(tmpFolder)IMG.png"
        //let outputUrl = URL(fileURLWithPath: out)
        //let _ = await AssetCollection.writeToUrl(img: cgiUpscaled, toUrl: outputUrl)
        //currentMessage = "Exported"
        return upped
    }

    // also moves to camera roll (iPad), or Downloads (Mac)
    public static func writeToUrl(img: CGImage, toUrl outputUrl: URL) async -> String? {
        if img.trySaveToPng(outputUrl) {
            print("Wrote out \(outputUrl.absoluteString)")
            // on Mac get permission to write to Downloads folder
            // then copy file there under new, unique filename IMG_xyzw.psd
            return Autosave.shared.copyFileToDownloadsWithUniqueName(url: outputUrl)
        } else {
            print("Failed to write PSD to \(outputUrl.absoluteString)")
        }
        return nil
    }

    func cropScaleParent(_ asset: ProjectAsset) async -> ProjectAsset {
        let maybeCgi = await doCropScaleExport(asset: asset)
        return ProjectAsset(
            image: maybeCgi,
            result: asset.result,
            rectToBase: nil,
            parentId: asset.parentId,
            stage: .cropScaled2,
            model: asset.model,
            id: asset.id
        )
    }

    func doGenerate(image: CGImage) async -> CGImage? {
        let controller = await ImageController.shared
        await controller.setStartingImage(image: image)
        await logMessage("(\(i)/\(n)) Img2img")
        let uuid = UUID()
        await controller.generate1(
            folderPath, "\(uuid)",
            overrideStrength: strength,
            overridePrompt: prompt,
            overrideNegativePrompt: negativePrompt
        )
        // load the image and return it so it can possibly be used as input
        let ret = "\(folderPath)/\(uuid).png".loadPngImage()
        return ret
    }

    func generateFromAssetItself(
        _ asset: ProjectAsset,
        task: ProjectTask
    ) async -> ProjectAsset {
        guard let image = asset.image else {
            print("Cannot generate with nil image")
            return asset  // eek, nothing to do? could cause an infinite loop
        }
        await ImageController.shared.setModel(asset.model)
        let maybeCgi = await doGenerate(image: image)
        return ProjectAsset(
            image: maybeCgi,
            result: asset.result,
            rectToBase: nil,
            parentId: asset.parentId,
            stage: .generatedNotUpscaled3,
            model: asset.model,
            id: asset.id
        )
    }

    // now time to get cropScaled
    // (one at a time because other ones depend on a parent being generated first)
    func processOne(task: ProjectTask) async -> ProjectAsset? {
        guard let input = assets.filter({ $0.stage == .needsCrop1 }).first else {
            return nil
        }
        var newAsset = await cropScaleParent(input)
        if newAsset.image != nil {
            newAsset = await generateFromAssetItself(newAsset, task: task)
        }
        return newAsset
    }
}
