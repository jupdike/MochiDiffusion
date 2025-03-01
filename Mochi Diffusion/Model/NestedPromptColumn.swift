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
    var negativePrompt: String = ""
    var imageFiles: [String] = []

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
                column.imageFiles = ps.map { "\(columnsFolderPath)\($0)" }
                for fname in column.imageFiles {
                    if !FileManager.default.fileExists(atPath: fname) {
                        print("Could not find file: \(fname)")
                        return []
                    }
                }
                isFirst = false
            } else if line.starts(with: "+") {
                column.prompt =
                    line.trimmingPrefix("+").trimmingCharacters(in: CharacterSet.whitespaces)
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
