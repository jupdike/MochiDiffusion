//
//  NestedPromptColumn.swift
//  Mochi Diffusion
//
//  Created by Jared Updike on 2/28/25.
//

class NestedPromptColumn {
    var strengthMin: Double = 0.0
    var strengthMax: Double = 0.0
    var prompt: String = ""
    var origPrompt: String = ""
    var negativePrompt: String = ""
    var imageFiles: [String] = []

    // take an outputted prompt and try to put curly braces back in for Project use
    func tryModify(prompt: String) -> String {
        if prompt.contains(where: { c in c == "{" || c == "}" }) {
            // already done, some other column already modified this prompt to be viable
            return prompt
        }
        let str =
            self.prompt
            .replacingOccurrences(of: "$", with: "(.+)")
        if let regex: Regex = try? Regex(str) {
            //print("got a regex to test with")
            if let match = try? regex.wholeMatch(in: prompt) {
                let entireMatch = String(match.0)  // entire match
                let firstCapture = match.output[1]
                if let sub = firstCapture.substring {
                    let captureMatch = String(sub)
                    //print("*** Got a match, esp. capture: \(captureMatch)")
                    let reverseEngineered = prompt.replacingOccurrences(of: captureMatch, with: "$")
                    if reverseEngineered == self.prompt {
                        let modifiedPrompt = self.origPrompt.replacingOccurrences(
                            of: "$", with: captureMatch
                        )
                        print("*** Successfully reverse engineered! \(modifiedPrompt)")
                        return modifiedPrompt
                    }
                }
            }
        }
        return prompt
    }

    static func fromLines(
        _ columnsFolderPath: String
    )
        -> [NestedPromptColumn]
    {
        let colFile = "\(columnsFolderPath)index.txt"
        let lines = colFile.contensOfFileAsLines()
        //
        var column = NestedPromptColumn()
        var ret: [NestedPromptColumn] = []
        var isFirst = true
        for l in lines {
            let line = l.trimmingCharacters(in: CharacterSet.whitespaces)
            if line.starts(with: "*") {
                if !isFirst {
                    ret.append(column)
                }
                column = NestedPromptColumn()
                let stripped =
                    line.trimmingPrefix("*").trimmingCharacters(in: CharacterSet.whitespaces)
                let ps = stripped.split(by: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                // check that each file exists so we don't crash on a missing image, but after the fact!
                if stripped.hasSuffix("*") && ps.count == 1 {
                    // filename globbing
                    let filePrefix = stripped.replacingOccurrences(of: "*", with: "")
                    if let files: [String] =
                        try? FileManager.default.contentsOfDirectory(atPath: columnsFolderPath)
                    {
                        column.imageFiles = files.filter { $0.getFileName().hasPrefix(filePrefix) }
                            .map { "\(columnsFolderPath)/\($0)" }
                        print("Found \(column.imageFiles.count) image files")
                    } else {
                        print("Problem interpreting filename glob for \(stripped)")
                    }
                } else {
                    // normal files
                    column.imageFiles = ps.map { "\(columnsFolderPath)\($0)" }
                }
                for fname in column.imageFiles {
                    if !FileManager.default.fileExists(atPath: fname) {
                        print("Could not find file: \(fname)")
                        return []
                    }
                }
                isFirst = false
            } else if line.starts(with: "+") {
                column.origPrompt = line.trimmingPrefix("+")
                    .trimmingCharacters(in: CharacterSet.whitespaces)
                column.prompt =
                    line.trimmingPrefix("+")
                    .trimmingCharacters(in: CharacterSet.whitespaces)
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                if !column.prompt.contains("$") {
                    print("Expected all prompts in columns/index.txt to have ")
                    return []
                }
            } else if line.starts(with: "-") {
                column.negativePrompt =
                    line.trimmingPrefix("-").trimmingCharacters(in: CharacterSet.whitespaces)
            } else {
                let ps: [String] = line.split(by: "-")
                if ps.count >= 2 {
                    if let d0 = Double(ps[0]),
                        let d1 = Double(ps[1])
                    {
                        column.strengthMin = d0
                        column.strengthMax = d1
                    }
                } else {
                    if column.strengthMax == 0.0 && column.strengthMin == 0.0 {
                        print("Problem parsing a Column, got bogus strength range: \(line)")
                    }
                }
            }
        }
        // append the last one
        ret.append(column)
        return ret
    }
}
