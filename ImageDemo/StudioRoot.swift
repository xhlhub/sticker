//
//  StudioRoot.swift
//  ImageDemo
//

import SwiftUI

enum StudioPage: String, CaseIterable, Identifiable {
    case sticker
    case stamp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sticker: "贴纸"
        case .stamp: "邮票"
        }
    }
}

struct StudioRoot: View {
    @State private var page: StudioPage = .sticker

    var body: some View {
        ZStack {
            ContentView(page: $page)
                .opacity(page == .sticker ? 1 : 0)
                .allowsHitTesting(page == .sticker)
                .accessibilityHidden(page != .sticker)
            StampView(page: $page)
                .opacity(page == .stamp ? 1 : 0)
                .allowsHitTesting(page == .stamp)
                .accessibilityHidden(page != .stamp)
        }
    }
}

struct StudioPager: View {
    @Binding var page: StudioPage

    var body: some View {
        Picker("页面", selection: $page) {
            ForEach(StudioPage.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }
}
