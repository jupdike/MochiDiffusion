//
//  AppView.swift
//  Mochi Diffusion
//
//  Created by Joshua Park on 12/17/22.
//

import SwiftUI

struct AppView: View {
    @Environment(ImageStore.self) var store: ImageStore
    @State private var isShowingInspector = true

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 450)
        } detail: {
            if store.showMain {
                GalleryView()
                    .inspector(isPresented: $isShowingInspector) {
                        InspectorView()
                            .inspectorColumnWidth(min: 300, ideal: 300, max: 500)
                    }
            } else {
                ProjectView()
            }
        }
        .toolbar {
            if store.showMain {
                GalleryToolbarView(isShowingInspector: $isShowingInspector)
            } else {
                ProjectToolbar()
            }
        }
    }
}

#Preview {
    AppView()
        .environment(ImageStore.shared)
}
