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
    var strength: Double = 0.5
    var prompt = ""
    var negativePrompt = ""
    var shouldExportPSD = true

    init(
        path: String,
        cgImage: CGImage,
        store: ImageStore
    ) {
        self.store = store
        self.anns = ImageAnnotations.find(inImage: cgImage)
        let folderPath = MDProjectController.imagePathToProjectFolder(path)
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
}
