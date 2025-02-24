//
//  Autosave.swift
//  Ainter
//
//  Created by Jared Updike on 2/11/25.
//

import Photos

extension String {
    func lastFileComponentWithoutExt() -> String {
        // this isn't super safe and can crash and should be rewritten to be more robust
        return self.components(separatedBy: "/").last!.components(separatedBy: ".").first!
    }
}

class Autosave {
    static let shared = Autosave()

    var plistDict: [String: String]

    let plistBaseFilename = "autosave"

    init() {
        self.plistDict = plistBaseFilename.readDictFromPlist()
    }

    let countKey = "nextImageFileCount"
    func getNextImageFileCount() -> Int {
        if let rhs = self.plistDict[countKey],
            let i = Int(rhs)
        {
            var iPlus = i + 1
            if iPlus > 9999 {
                iPlus = 0
            }
            self.plistDict[countKey] = "\(iPlus)"
            plistBaseFilename.writeDictAsPlist(dict: self.plistDict)
            return i
        }
        self.plistDict[countKey] = "1"
        plistBaseFilename.writeDictAsPlist(dict: self.plistDict)
        return 0
    }

    static func getFileNameWithoutExt(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let fname = url.lastPathComponent.lastFileComponentWithoutExt()
        return fname
    }

    func copyFileToDownloadsWithUniqueName(url: URL) -> String? {
        let manager = FileManager.default
        let downloadsDirectory = "/Users/\(NSUserName())/Downloads"
        let ext = url.pathExtension
        let fname = url.lastPathComponent.lastFileComponentWithoutExt()
        var counter = Autosave.shared.getNextImageFileCount()  // will increment itself
        var newPath = ""
        while true {
            newPath = "\(downloadsDirectory)/\(fname)_\(String(format: "%0.4d", counter)).\(ext)"
            if !manager.fileExists(atPath: newPath) {
                break
            }
            counter = Autosave.shared.getNextImageFileCount()
        }
        do {
            try manager.copyItem(at: url, to: URL(fileURLWithPath: newPath))
        } catch {
            print("Failed to copy file to \(newPath). Erro: \(error)")
            return nil
        }
        return newPath
    }

    // https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library
    static func copyImageUrlToCameraRoll(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        } completionHandler: { success, error in
            if !success, let error = error {
                print("Error creating PHPhotoLibrary asset: \(error)\nURL: \(url)")
            }
        }
    }
}

extension String {
    func getPlistUrl() -> URL {
        let baseFileName: String = self
        let docsBaseURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let customPlistURL: URL = docsBaseURL.appendingPathComponent(baseFileName + ".plist")
        return customPlistURL
    }

    func writeDictAsPlist(dict: [String: String]) {
        let baseFileName: String = self
        let customPlistURL = baseFileName.getPlistUrl()
        //print(customPlistURL.absoluteString)
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: PropertyListSerialization.PropertyListFormat.binary,
                options: 0
            )
            do {
                try data.write(to: customPlistURL, options: .atomic)
                print("Successfully wrote to \(baseFileName).plist")
            } catch (let err) {
                print(err.localizedDescription)
            }
        } catch (let err) {
            print(err.localizedDescription)
        }
    }

    func readDictFromPlist() -> [String: String] {
        let baseFileName: String = self
        let customPlistURL = baseFileName.getPlistUrl()
        //print(customPlistURL.absoluteString)
        if let dict = NSMutableDictionary(contentsOf: customPlistURL) {
            let ret = dict as! [String: String]
            return ret
        }
        return [:]
    }
}
