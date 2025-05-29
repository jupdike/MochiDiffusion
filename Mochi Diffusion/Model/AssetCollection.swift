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

enum ModelSemantic {
    case wideAbstract
    case narrowLiteral
    case tightLiteral
}

public struct ProjectAsset: Identifiable, Equatable, Hashable {
    var result: Register?
    // needs to be converted to result relative to parent, not relative to base
    var rectToBase: CGRect?
    var image: CGImage?
    public var id: UUID
    var parentId: UUID?

    var isBaseImage: Bool { parentId == nil }
    var model: ModelSemantic = .wideAbstract
    var extraPrompt: String

    public let stage: AssetStage

    init(
        image: CGImage? = nil,
        result: Register? = nil,
        rectToBase: CGRect? = nil,
        parentId: UUID? = nil,
        stage: AssetStage? = nil,
        extra: String,
        model: ModelSemantic,
        id: UUID? = nil
    ) {
        self.result = result
        self.rectToBase = rectToBase
        self.image = image
        self.id = id != nil ? id! : UUID()
        self.parentId = parentId
        self.model = model
        self.extraPrompt = extra
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

    init(rectToBase: CGRect, parent: ProjectAsset, model: ModelSemantic, _ extraPrompt: String) {
        self.init(
            image: nil, result: nil, rectToBase: rectToBase,
            parentId: parent.id, extra: extraPrompt, model: model
        )
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

    let maxMaxScale: Double = 11.25

    public func computeMaxScale() -> Double {
        var maxScale = 0.1
        for asset in assets {
            let scale = 1.0 / asset.getScaleRelativeToBase(assets: assets)
            maxScale = max(scale, maxScale)
        }
        return min(maxMaxScale, maxScale)
    }

    public var assets: [ProjectAsset] = []
    var scaleCache: [Int: Double] = [:]

    public let folderPath: String
    public let store: ImageStore
    public var projectController: MDProjectController? { store.projectController }

    // cache Max Scale for a given set of unique UUIDs
    public func getMaxScale() -> Double {
        //let hash: Int = hashAllSets
        //if let ret = scaleCache[hash] {
        //    return ret
        //}
        let result = computeMaxScale()
        //scaleCache[hash] = result
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

    //    public var hashAllSets: Int {
    //        var hasher = Hasher()
    //        for asset in assets {
    //            asset.hash(into: &hasher)
    //        }
    //        return hasher.finalize()
    //    }

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
            extra: asset.extraPrompt,
            model: asset.model,
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

    func assetReplacing(_ id: UUID, _ newAsset: ProjectAsset) -> [ProjectAsset] {
        return assets.map {
            if $0.id == id {
                return newAsset
            } else {
                return $0
            }
        }
    }
}
