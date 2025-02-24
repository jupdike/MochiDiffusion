//
//  AssetCollection.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 2/24/25.
//

struct Register: Identifiable, Equatable, Hashable {
    let scale: Double
    let offsetX: Int
    let offsetY: Int
    let nw: Int
    let nh: Int
    let id: UUID = UUID()
}

public struct SSAsset: Identifiable, Equatable, Hashable {
    var result: Register?
    // needs to be converted to result relative to parent, not relative to base
    var rectToBase: CGRect?
    var image: CGImage?
    public var id: UUID
    var parentId: UUID?

    var isBaseImage: Bool { parentId == nil }

    public let stage: AssetStage

    init(
        image: CGImage? = nil,
        result: Register? = nil,
        rectToBase: CGRect? = nil,
        parentId: UUID? = nil,
        stage: AssetStage? = nil,
        id: UUID? = nil
    ) {
        self.result = result
        self.rectToBase = rectToBase
        self.image = image
        self.id = id != nil ? id! : UUID()
        self.parentId = parentId
        if stage == nil {
            if parentId == nil {
                self.stage = .generatedNotUpscaled3
            } else {
                self.stage = .needsRectToParentResult0
            }
        } else {
            self.stage = stage!
        }
    }

    init(rectToBase: CGRect, parent: SSAsset) {
        self.init(image: nil, result: nil, rectToBase: rectToBase, parentId: parent.id)
    }

    static func getNodeById(assets: [SSAsset], id: UUID) -> SSAsset? {
        return assets.first { $0.id == id }
    }

    func getCropRect() -> CGRect {
        guard let reg = result else {
            print("Expected result to not be null")
            return CGRect(x: 0, y: 0, width: -1337, height: -1337)
        }
        return CGRect(
            x: reg.offsetX,
            y: reg.offsetY,
            width: reg.nw,
            height: reg.nh
        )
    }

    // in old baseImage coord space, not new scaled (maxScale) space
    func getOffsetRelativeToBase(assets: [SSAsset]) -> CGPoint {
        if self.isBaseImage {
            return CGPoint(x: 0, y: 0)
        }
        // else, have parent
        guard let register = self.result else {
            print("Expected to have a parent and a register with offset relative to parent")
            return CGPoint(x: -1337, y: -1337)
        }
        guard let pid = self.parentId else {
            print("Expected node parentId not to be nil, this should not happen")
            return CGPoint(x: -1337, y: -1337)
        }
        // makes multiple calls to this O(n^2) which is OK for low values of n
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Expected node to not be nil, this should not happen")
            return CGPoint(x: -1337, y: -1337)
        }
        let scaleParentToBase = parent.getScaleRelativeToBase(assets: assets)
        var ox = CGFloat(register.offsetX) * scaleParentToBase
        var oy = CGFloat(register.offsetY) * scaleParentToBase
        let po = parent.getOffsetRelativeToBase(assets: assets)
        ox += po.x
        oy += po.y
        let offset = CGPoint(x: ox, y: oy)
        return offset
    }

    // this is O(n) so the ForEach call is O(n^2) which should not be a problem for under a dozen images, or even higher
    // really, you shouldn't go for like hundreds of images, as this is untested :sucking air through teeth emoji:
    func getScaleRelativeToBase(assets: [SSAsset]) -> Double {
        var node = self
        var scale = 1.0
        while !node.isBaseImage {
            guard let register = node.result else {
                print("Expected to have a Register result if not a base image")
                break
            }
            scale *= register.scale
            if let pid = node.parentId,
                let parent = SSAsset.getNodeById(assets: assets, id: pid)
            {
                node = parent
            } else {
                print("Expected node to not be nil, this should not happen")
                break
            }
        }
        return scale
    }
}

public enum AssetStage {
    case needsRectToParentResult0
    case needsCrop1
    case cropScaled2
    case generatedNotUpscaled3
    case finalUpscaled4
}

class AssetCollection {
    public var baseImage: CGImage? { assets.count > 0 ? assets[0].image : nil }

    init(assets: [SSAsset], folderPath: String) {
        self.assets = assets
        self.folderPath = folderPath
    }

    private func computeMaxScale() -> Double {
        var maxScale = 0.1
        for asset in assets {
            let scale = 1.0 / asset.getScaleRelativeToBase(assets: assets)
            maxScale = max(scale, maxScale)
        }
        return maxScale
    }

    public var assets: [SSAsset] = []
    var scaleCache: [Int: Double] = [:]

    public var folderPath: String

    // cache Max Scale for a given set of unique UUIDs
    public func getMaxScale() -> Double {
        let hash: Int = hashAllSets
        if let ret = scaleCache[hash] {
            return ret
        }
        let result = computeMaxScale()
        scaleCache[hash] = result
        return result
    }

    public func getOffsetRelativeToParent(asset: SSAsset) -> CGPoint {
        if asset.isBaseImage {
            return CGPoint(x: 0, y: 0)
        }
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return CGPoint(x: -1337, y: -1337)
        }
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Assets besides baseImage should have a parent!")
            return CGPoint(x: -1337, y: -1337)
        }
        var pOrigin = CGPoint(x: 0, y: 0)
        var pScale: CGFloat = 1.0
        if let parentRectToBase = parent.rectToBase {
            pOrigin = parentRectToBase.origin
            pScale = getScaleRelativeToParent(asset: parent)
        }
        guard let orig = asset.rectToBase?.origin else {
            print("Expected own rect to be non-null while converting rect to result")
            return CGPoint(x: -1337, y: -1337)
        }
        //let scale = getScaleRelativeToParent(asset: asset)
        return CGPoint(
            x: (orig.x - pOrigin.x) / pScale,
            y: (orig.y - pOrigin.y) / pScale
        )
    }

    public func getScaleRelativeToParent(asset: SSAsset) -> CGFloat {
        if asset.isBaseImage {
            return 1.0
        }
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return -1337.0
        }
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
            print("Assets besides baseImage should have a parent!")
            return -1337.0
        }
        var w: CGFloat = CGFloat(baseImage!.width)
        if let pRect = parent.rectToBase {
            w = CGFloat(pRect.width)
        }
        guard let rect = asset.rectToBase else {
            print("Expected own rect to be non-null while converting rect to result")
            return -1337.0
        }
        let scale: Double = rect.width / w
        return scale
    }

    public func getTrueScale(asset: SSAsset) -> Double {
        let max = getMaxScale()
        let scale = asset.getScaleRelativeToBase(assets: assets)
        // returns 1.0 for smallest image, and maxScale for biggest (base) image
        return max * scale
    }

    public func getTrueSize(asset: SSAsset) -> CGSize {
        guard let image = asset.image else {
            print("getTrueSize expected asset.image != nil")
            return CGSize(width: -1, height: -1)
        }
        let trueScale = getTrueScale(asset: asset)
        let bigw = round(trueScale * CGFloat(image.width))
        let bigh = round(trueScale * CGFloat(image.height))
        return CGSize(width: bigw, height: bigh)
    }

    public var hashAllSets: Int {
        var hasher = Hasher()
        for asset in assets {
            asset.hash(into: &hasher)
        }
        return hasher.finalize()
    }

    func verifyParentage(_ asset: SSAsset) -> Bool {
        var node = asset
        if node.isBaseImage {
            //print("isBaseImage: \(node.id)")
        }
        while !node.isBaseImage {
            guard let pid = node.parentId else {
                print("Assets besides baseImage should have a parentId!")
                return false
            }
            guard let n = SSAsset.getNodeById(assets: assets, id: pid) else {
                return false
            }
            //print("\(node.id) -- parent is --> \(n.id)")
            node = n
        }
        return true
    }

    func rectToParentResult(asset: SSAsset) -> SSAsset {
        //getTrueScale(asset: asset) // TODO this is wrong because it needs to be relative to parent!
        let scale = getScaleRelativeToParent(asset: asset)
        let offset = getOffsetRelativeToParent(asset: asset)
        // need correct scale to get correct nw, nh
        let nw = Int(scale * CGFloat(baseImage!.width))
        let nh = Int(scale * CGFloat(baseImage!.height))
        let reg = Register(
            scale: scale,
            offsetX: Int(offset.x),
            offsetY: Int(offset.y),
            nw: nw, nh: nh
        )
        print("\(asset.id) -- offset: \(reg.offsetX), \(reg.offsetY) -- nw x nh: \(nw) x \(nh)")
        return SSAsset(
            image: nil,
            result: reg,
            parentId: asset.parentId,
            stage: .needsCrop1,
            id: asset.id
        )
    }

    func stage0to1() -> [SSAsset] {
        var newAssets: [SSAsset] = []
        for asset in assets {
            //print("----\nVerifying parentage")
            if !verifyParentage(asset) {
                print("PROBLEM with parentage of asset \(asset.id)")
            }
            if asset.stage != .needsRectToParentResult0 {
                newAssets.append(asset)  // base asset
            }
            if asset.stage == .needsRectToParentResult0 {
                let newAsset = rectToParentResult(asset: asset)
                newAssets.append(newAsset)
            }
        }
        return newAssets
    }

    var currentMessage: String = ""

    private func doCropScaleExport(asset: SSAsset) async -> CGImage? {
        guard let pid = asset.parentId else {
            print("Should not happen: parentId")
            return nil
        }
        guard let parent = SSAsset.getNodeById(assets: assets, id: pid) else {
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
        currentMessage = "new size of image = \(cropImg.width) by \(cropImg.height)"
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
        currentMessage = "Upscaling (\(String(format: "%1.2f", s))x)..."
        let upped = await Upscaler.shared.upscale(
            cgImage: cropImg,
            upscaledWidth: w,
            upscaledHeight: h
        )
        guard let cgiUpscaled = upped else {
            print("Failed to upscale cropped image")
            return nil
        }
        currentMessage = "Upscaled"
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

    func cropScaleParent(_ asset: SSAsset) async -> SSAsset {
        let maybeCgi = await doCropScaleExport(asset: asset)
        return SSAsset(
            image: maybeCgi,
            result: asset.result,
            rectToBase: nil,
            parentId: asset.parentId,
            stage: .cropScaled2,
            id: asset.id
        )
    }

    func doGenerate(image: CGImage) async -> CGImage? {
        let controller = await ImageController.shared
        //await logMessage("Setting Starting Image...")
        await controller.setStartingImage(image: image)
        //await logMessage("Generating an image...")
        let uuid = UUID()
        await controller.generate1(folderPath, "\(uuid)")
        // await logMessage("Done.")
        // load the image and return it so it can possibly be used as input
        let ret = "\(folderPath)/\(uuid).png".loadPngImage()
        return ret
    }

    func generateFromAssetItself(_ asset: SSAsset) async -> SSAsset {
        guard let image = asset.image else {
            print("Cannot generate with nil image")
            return asset  // eek, nothing to do? could cause an infinite loop
        }
        let maybeCgi = await doGenerate(image: image)
        return SSAsset(
            image: maybeCgi,
            result: asset.result,
            rectToBase: nil,
            parentId: asset.parentId,
            stage: .generatedNotUpscaled3,
            id: asset.id
        )
    }

    // now time to get cropScaled
    // (one at a time because other ones depend on a parent being generated first)
    func processOne() async -> SSAsset? {
        guard let input = assets.filter({ $0.stage == .needsCrop1 }).first else {
            return nil
        }
        var newAsset = await cropScaleParent(input)
        if let image = newAsset.image {
            newAsset = await generateFromAssetItself(newAsset)
        }
        return newAsset
    }

    func assetReplacing(_ id: UUID, _ newAsset: SSAsset) -> [SSAsset] {
        return assets.map {
            if $0.id == id {
                return newAsset
            } else {
                return $0
            }
        }
    }

    func stage1to2() async {
        while true {
            if let oneChanged = await processOne() {
                // replace in-place over and over, to make sure we can use previous images
                assets = assetReplacing(oneChanged.id, oneChanged)
            } else {
                break
            }
        }
    }
}
