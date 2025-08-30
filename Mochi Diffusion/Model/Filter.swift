//
//  Filter.swift
//  Mochi Diffusion
//
//  Created by Hossein on 10/12/24.
//

import Foundation

struct Filter: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var tagColor: FilterColorNumber = .clear
    var element: FilterElement = .prompt
    var type: FilterType = .contains
    var condition: FilterCondition = .isEqual
    func invertedCondition() -> Filter {
        return Filter(
            text: self.text,
            tagColor: self.tagColor,
            element: self.element,
            type: self.type,
            condition: self.condition == .isEqual ? .isNotEqual : .isNotEqual
        )
    }
}

enum FilterElement: String, CaseIterable {
    case tagColor = "Tag"
    case prompt = "Prompt"
    case seed = "Seed"
    case negativePrompt = "Negative Prompt"
    case model = "Model"
    case steps = "Steps"
    case guidanceScale = "Guidance Scale"
}

enum FilterType: String, CaseIterable {
    case equals = "Equals"
    case contains = "Contains"
}

enum FilterCondition: String, CaseIterable {
    case isEqual = "= is"
    case isNotEqual = "≠ is not"
}

enum FilterColorNumber: String, CaseIterable {
    case clear = "Clear"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case gray = "Gray"
}

extension Filter {
    func validate(_ sdImage: SDImage) -> Bool {
        if self.element == .tagColor && self.condition == .isEqual {
            switch self.tagColor {
            case .clear:
                return sdImage.finderTagColorNumber == 0
            case .red:
                return sdImage.finderTagColorNumber == 6
            case .orange:
                return sdImage.finderTagColorNumber == 7
            case .yellow:
                return sdImage.finderTagColorNumber == 5
            case .green:
                return sdImage.finderTagColorNumber == 2
            case .blue:
                return sdImage.finderTagColorNumber == 4
            case .purple:
                return sdImage.finderTagColorNumber == 3
            case .gray:
                return sdImage.finderTagColorNumber == 1
            }
        } else if self.element == .tagColor && self.condition == .isNotEqual {
            switch self.tagColor {
            case .clear:
                return sdImage.finderTagColorNumber != 0
            case .red:
                return sdImage.finderTagColorNumber != 6
            case .orange:
                return sdImage.finderTagColorNumber != 7
            case .yellow:
                return sdImage.finderTagColorNumber != 5
            case .green:
                return sdImage.finderTagColorNumber != 2
            case .blue:
                return sdImage.finderTagColorNumber != 4
            case .purple:
                return sdImage.finderTagColorNumber != 3
            case .gray:
                return sdImage.finderTagColorNumber != 1
            }
        }

        let filterValue = element.getFilterValueFrom(sdImage)
        let isContainsType = type == .contains

        let result =
            isContainsType
            ? filterValue.range(
                of: text, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
                != nil
            : filterValue == text

        return condition == .isEqual ? result : !result
    }

    func humanReadable() -> String {
        return "\(element.rawValue)\(condition == .isEqual ? "" : " not ") \(type.rawValue) \(text)"
    }
}

extension Array where Element == Filter {
    func humanReadable() -> String {
        self.map({ $0.humanReadable() }).joined(separator: " and ")
    }
}

extension FilterElement {
    func getFilterValueFrom(_ sdImage: SDImage) -> String {
        switch self {
        // not applicable in validate() code, but make this switch exhaustive anyway
        case .tagColor: sdImage.finderTagColorNumber.description
        case .prompt: sdImage.prompt
        case .seed: String(sdImage.seed)
        case .negativePrompt: sdImage.negativePrompt
        case .model: sdImage.model
        case .steps: String(sdImage.steps)
        case .guidanceScale: String(sdImage.guidanceScale)
        }
    }
}
