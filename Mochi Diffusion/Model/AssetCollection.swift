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

public struct ProjectAsset: Identifiable, Equatable, Hashable {
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

    init(rectToBase: CGRect, parent: ProjectAsset) {
        self.init(image: nil, result: nil, rectToBase: rectToBase, parentId: parent.id)
    }

    static func getNodeById(assets: [ProjectAsset], id: UUID) -> ProjectAsset? {
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
    func getOffsetRelativeToBase(assets: [ProjectAsset]) -> CGPoint {
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
        guard let parent = ProjectAsset.getNodeById(assets: assets, id: pid) else {
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
    func getScaleRelativeToBase(assets: [ProjectAsset]) -> Double {
        var node = self
        var scale = 1.0
        while !node.isBaseImage {
            guard let register = node.result else {
                print("Expected to have a Register result if not a base image")
                break
            }
            scale *= register.scale
            if let pid = node.parentId,
                let parent = ProjectAsset.getNodeById(assets: assets, id: pid)
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

    init(assets: [ProjectAsset], folderPath: String, store: ImageStore) {
        self.assets = assets
        self.folderPath = folderPath
        // keep a reference to store which can have a nullable
        // reference to projectController, which is what we
        // really care about
        self.store = store
    }

    public func computeMaxScale() -> Double {
        var maxScale = 0.1
        for asset in assets {
            let scale = 1.0 / asset.getScaleRelativeToBase(assets: assets)
            maxScale = max(scale, maxScale)
        }
        return maxScale
    }

    public var assets: [ProjectAsset] = []
    var scaleCache: [Int: Double] = [:]

    public let folderPath: String
    public let store: ImageStore
    public var projectController: MDProjectController? { store.projectController }

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

    public func getOffsetRelativeToParent(asset: ProjectAsset) -> CGPoint {
        if asset.isBaseImage {
            return CGPoint(x: 0, y: 0)
        }
        guard let base = baseImage else {
            print("Cannot do anything with a base image")
            return CGPoint(x: -1337, y: -1337)
        }
        let ww: CGFloat = CGFloat(base.width)
        let hh: CGFloat = CGFloat(base.height)
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return CGPoint(x: -1337, y: -1337)
        }
        guard let parent = ProjectAsset.getNodeById(assets: assets, id: pid) else {
            print("Assets besides baseImage should have a parent!")
            return CGPoint(x: -1337, y: -1337)
        }
        var pRect = CGRect(x: 0, y: 0, width: ww, height: hh)
        if let parentRectToBase = parent.rectToBase {
            pRect = parentRectToBase
        }
        guard let r = asset.rectToBase else {
            print("Expected own rect to be non-null while converting rect to result")
            return CGPoint(x: -1337, y: -1337)
        }
        let orig = r.origin
        return CGPoint(
            x: ww * (orig.x - pRect.minX) / pRect.width,
            y: hh * (orig.y - pRect.minY) / pRect.height
        )
    }

    public func getScaleRelativeToParent(asset: ProjectAsset) -> CGFloat {
        if asset.isBaseImage {
            return 1.0
        }
        guard let pid = asset.parentId else {
            print("Assets besides baseImage should have a parentId!")
            return -1337.0
        }
        guard let parent = ProjectAsset.getNodeById(assets: assets, id: pid) else {
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

    public func getTrueScale(asset: ProjectAsset) -> Double {
        let max = getMaxScale()
        let scale = asset.getScaleRelativeToBase(assets: assets)
        // returns 1.0 for smallest image, and maxScale for biggest (base) image
        return max * scale
    }

    public func getTrueSize(asset: ProjectAsset) -> CGSize {
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

    func verifyParentage(_ asset: ProjectAsset) -> Bool {
        var node = asset
        if node.isBaseImage {
            //print("isBaseImage: \(node.id)")
        }
        while !node.isBaseImage {
            guard let pid = node.parentId else {
                print("Assets besides baseImage should have a parentId!")
                return false
            }
            guard let n = ProjectAsset.getNodeById(assets: assets, id: pid) else {
                return false
            }
            //print("\(node.id) -- parent is --> \(n.id)")
            node = n
        }
        return true
    }

    func rectToParentResult(asset: ProjectAsset) -> ProjectAsset {
        if let r = asset.rectToBase {
            let x0 = Int(r.minX)
            let y0 = Int(r.minY)
            let x1 = Int(r.maxX)
            let y1 = Int(r.maxY)
            print("asset.rectToBase: \(x0), \(y0) -> \(x1), \(y1)")
        }
        // TODO  What parts are wrong? It almost works!
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
        return ProjectAsset(
            image: nil,
            result: reg,
            parentId: asset.parentId,
            stage: .needsCrop1,
            id: asset.id
        )
    }

    func stage0to1() -> [ProjectAsset] {
        var newAssets: [ProjectAsset] = []
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
            id: asset.id
        )
    }

    func logMessage(_ message: String) async {
        guard let controller = self.projectController else { return }
        await controller.logMessage(message)
    }

    func doGenerate(image: CGImage) async -> CGImage? {
        let controller = await ImageController.shared
        await controller.setStartingImage(image: image)
        await logMessage("(\(i)/\(n)) Img2img")
        let uuid = UUID()
        await controller.generate1(folderPath, "\(uuid)")
        // load the image and return it so it can possibly be used as input
        let ret = "\(folderPath)/\(uuid).png".loadPngImage()
        return ret
    }

    func generateFromAssetItself(_ asset: ProjectAsset) async -> ProjectAsset {
        guard let image = asset.image else {
            print("Cannot generate with nil image")
            return asset  // eek, nothing to do? could cause an infinite loop
        }
        let maybeCgi = await doGenerate(image: image)
        return ProjectAsset(
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
    func processOne() async -> ProjectAsset? {
        guard let input = assets.filter({ $0.stage == .needsCrop1 }).first else {
            return nil
        }
        var newAsset = await cropScaleParent(input)
        if newAsset.image != nil {
            newAsset = await generateFromAssetItself(newAsset)
        }
        return newAsset
    }

    func assetReplacing(_ id: UUID, _ newAsset: ProjectAsset) -> [ProjectAsset] {
        return assets.map {
            if $0.id == id {
                return newAsset
            } else {
                return $0
            }
        }
    }

    var n = 1
    var i = 1
    func stage1to2() async {
        n = assets.count
        // baseImage is already ... based!
        i = 2
        while true {
            if let oneChanged = await processOne() {
                // replace in-place over and over, to make sure we can use previous images
                assets = assetReplacing(oneChanged.id, oneChanged)
                await logMessage("(\(i)/\(n)) Done")
                i += 1
            } else {
                break
            }
        }
    }
}
