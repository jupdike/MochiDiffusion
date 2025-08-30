//
//  ImageCommands.swift
//  Mochi Diffusion
//
//  Created by Joshua Park on 1/14/23.
//

import SwiftUI

struct ImageCommands: Commands {
    @ObservedObject var controller: ImageController
    @ObservedObject var galleryCoordinator: GalleryCoordinator
    var generator: ImageGenerator
    var store: ImageStore
    var focusController: FocusController

    var body: some Commands {
        CommandMenu("Image") {
            Section {
                Button {
                    Task { await ImageController.shared.generate() }
                } label: {
                    if case .ready = ImageGenerator.shared.state {
                        Text(
                            "Generate",
                            comment: "Button to generate image"
                        )
                    } else {
                        Text(
                            "Add to Queue",
                            comment: "Button to generate image"
                        )
                    }
                }
                .keyboardShortcut("G", modifiers: .command)
                .disabled(controller.modelName.isEmpty)
                Button {
                    if let selectedId = ImageStore.shared.selectedId {
                        galleryCoordinator.scrollTo(selectedId)
                    }
                } label: {
                    Text(
                        "Scroll to Selected",
                        comment: "Scroll up or down to selected image so it is visible in gallery"
                    )
                }
                .keyboardShortcut("L", modifiers: .command)
                Button {
                    Task {
                        await ImageController.shared.enqueueText()
                    }
                } label: {
                    Text(
                        "Enqueue Text File Prompts",
                        comment: "Button to enqueue text file as series of prompts"
                    )
                }
                .keyboardShortcut("T", modifiers: .command)
                .disabled(controller.modelName.isEmpty)
                Button {
                    Task {
                        await ImageController.shared.enqueueNested()
                    }
                } label: {
                    Text(
                        "Nested 2 Text File Prompts",
                        comment: "Button to enqueue outer product of two sets of prompt files"
                    )
                }
                .keyboardShortcut("N", modifiers: .command)
                .disabled(controller.modelName.isEmpty)
                Button {
                    Task {
                        //await ImageController.shared.generateSeeded()
                        await ImageController.shared.test2()
                    }
                } label: {
                    Text(
                        "Test Generate Seeded",
                        comment: "Button to generate the same img2img over and over"
                    )
                }
                .keyboardShortcut("R", modifiers: .command)
                .disabled(controller.modelName.isEmpty)
                Button {
                    Task {
                        await ImageStore.shared.autoEnqueueProjects()
                    }
                } label: {
                    Text(
                        "Auto-enqueue Projects",
                        comment: "Enqueue all visible images as projects"
                    )
                }
                .keyboardShortcut("U", modifiers: .command)
                .disabled(store.images.isEmpty)
            }
            Section {
                Button {
                    Task { await ImageController.shared.selectNext() }
                } label: {
                    Text(
                        "Select Next",
                        comment: "Select next image in Gallery"
                    )
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(
                    !store.showMain
                        || store.images.isEmpty
                        || focusController.isTextFieldFocused
                )

                Button {
                    Task { await ImageController.shared.selectPrevious() }
                } label: {
                    Text(
                        "Select Previous",
                        comment: "Select previous image in Gallery"
                    )
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(
                    !store.showMain
                        || store.images.isEmpty
                        || focusController.isTextFieldFocused
                )
            }
            Section {
                Button {
                    guard let sdi = store.selected() else { return }
                    guard let cgi = sdi.image else { return }
                    Task {
                        if store.projectController == nil {
                            store.projectController = MDProjectController(
                                path: sdi.path,
                                cgImage: cgi,
                                store: store,
                                controller: controller,
                                generator: generator,
                                options:
                                    AnnotationOptions(
                                        shouldUseSmallestFace: controller.shouldUseSmallestFace,
                                        footStr: controller.footStr,
                                        shouldMakePSD: controller.shouldMakePSD
                                    )
                            )
                        } else {
                            store.projectController = nil
                        }
                    }
                } label: {
                    Text(
                        store.projectController == nil ? "Enter Project" : "Close Projwct",
                        comment: store.projectController == nil
                            ? "Create or Edit Project using selected image as main image"
                            : "Close project if open"
                    )
                }
                .keyboardShortcut("P", modifiers: .command)
                .disabled(store.selected() == nil)
            }
            Section {
                Button {
                    ImageController.shared.copyToPrompt()
                } label: {
                    Text(
                        "Copy Options to Sidebar",
                        comment:
                            "Button to copy the currently selected image's generation options to the prompt input sidebar"
                    )
                }
                .keyboardShortcut("C", modifiers: [.command, .shift])
                .disabled(store.selected() == nil)
                Button {
                    guard let sdi = store.selected() else { return }
                    Task { await ImageController.shared.selectStartingImage(sdi: sdi) }
                } label: {
                    Text(
                        "Set as Starting Image",
                        comment: "Set the current image as the starting image for img2img"
                    )
                }
                .keyboardShortcut("E", modifiers: .command)
                .disabled(store.selected() == nil)

                Button {
                    Task { await ImageController.shared.upscaleCurrentImage() }
                } label: {
                    Text(
                        "Convert to High Resolution",
                        comment: "Convert the current image to high resolution"
                    )
                }
                .keyboardShortcut("R", modifiers: .command)
                .disabled(store.selected() == nil)

                Button {
                    Task { await ImageController.shared.quicklookCurrentImage() }
                } label: {
                    Text(
                        "Quick Look",
                        comment: "View current image using Quick Look"
                    )
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(store.selected() == nil)
            }
            Section {
                Button {
                    Task { await ImageController.shared.removeCurrentImage() }
                } label: {
                    Text(
                        "Remove",
                        comment: "Remove image from the gallery"
                    )
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selected() == nil || focusController.isTextFieldFocused)
            }
        }
    }
}
