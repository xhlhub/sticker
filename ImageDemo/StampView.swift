//
//  StampView.swift
//  ImageDemo
//

import PhotosUI
import SwiftUI
import UIKit

struct StampView: View {
    @Binding var page: StudioPage
    @State private var stamp: UIImage?
    @State private var sourceData: Data?
    @State private var look: StampLook = .faded
    @State private var paper: StampPaper = .rice
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var savedHint: String?
    @State private var successCount = 0
    @State private var jobID = UUID()

    private let cardShape = RoundedRectangle(cornerRadius: 32, style: .continuous)
    private let ink = Color(hex: 0x6B3A2A)
    private let accent = Color(hex: 0xC4553A)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xF8F1E6), Color(hex: 0xF0E0CC)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudioPager(page: $page)
                    header
                    preview
                    lookPicker
                    paperPicker
                    actions
                    if stamp != nil {
                        saveButton
                    }
                    if let savedHint {
                        statusText(savedHint, color: Color(hex: 0x0F9F6E))
                    }
                    if let errorMessage {
                        statusText(errorMessage, color: Color(hex: 0xE11D48))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .tint(accent)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera) { data in
                Task { await process(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                await loadPhoto(item)
                photoItem = nil
            }
        }
        .sensoryFeedback(.success, trigger: successCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("复古邮票")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.86), in: Capsule())

            Text("印成邮票")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(ink)

            Text("四种旧片风格，白边齿孔，再盖一枚邮戳")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(hex: 0x8A6556))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        ZStack {
            StampPaperFill(kind: paper)

            if let stamp {
                Image(uiImage: stamp)
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .shadow(color: ink.opacity(0.22), radius: 14, y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if !isBusy {
                emptyHint
            }

            if isBusy {
                ZStack {
                    Color.white.opacity(0.62)
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在印成邮票…")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(ink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
        }
        .shadow(color: Color(hex: 0xC4A27A).opacity(0.45), radius: 24, y: 14)
        .animation(.spring(duration: 0.35), value: stamp != nil)
        .animation(.easeInOut(duration: 0.2), value: paper)
        .animation(.easeInOut(duration: 0.2), value: look)
    }

    private var lookPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("风格")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StampLook.allCases) { item in
                        Button {
                            look = item
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(swatch(for: item))
                                    .frame(width: 48, height: 48)
                                    .padding(2)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(look == item ? accent : Color.white.opacity(0.7))
                                    }
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(look == item ? accent : Color(hex: 0x8A6556))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(look == item ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }

            Text(sourceData == nil ? "拍一张或选一张，再换风格" : "换风格会按原图重做，不用重新选图")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(hex: 0xA07C6C))
        }
        .onChange(of: look) { _, _ in
            guard let sourceData else { return }
            Task { await process(sourceData, resetPreview: false) }
        }
    }

    private func swatch(for look: StampLook) -> LinearGradient {
        switch look {
        case .faded:
            LinearGradient(colors: [Color(hex: 0xF3E6D4), Color(hex: 0xC9C2B8)], startPoint: .top, endPoint: .bottom)
        case .silver:
            LinearGradient(colors: [Color(hex: 0xF5F5F5), Color(hex: 0x6E6E6E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warm:
            LinearGradient(colors: [Color(hex: 0xFFE0B5), Color(hex: 0xE8894A)], startPoint: .top, endPoint: .bottom)
        case .classic:
            LinearGradient(colors: [Color(hex: 0xE7C8A0), Color(hex: 0x8C5A3C)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.open")
                .font(.system(size: 28, weight: .semibold))
            Text("邮票会出现在这里")
                .font(.system(.headline, design: .serif))
            Text("整张照片会变成一张旧邮票")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color(hex: 0x8A6556))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var paperPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("纸张")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StampPaper.allCases) { item in
                        Button {
                            paper = item
                        } label: {
                            VStack(spacing: 6) {
                                StampPaperFill(kind: item)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .padding(2)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(paper == item ? accent : Color.white.opacity(0.7))
                                    }
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(paper == item ? accent : Color(hex: 0x8A6556))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(paper == item ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }

            Text(paper == .clear ? "透明底保存后能看见齿孔" : "换纸张不用重新做邮票")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(hex: 0xA07C6C))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: openCamera) {
                actionLabel(title: "拍照", system: "camera.fill", prominent: true)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            PhotosPicker(selection: $photoItem, matching: .images) {
                actionLabel(title: "上传照片", system: "photo.on.rectangle.angled", prominent: false)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .opacity(isBusy ? 0.55 : 1)
    }

    private var saveButton: some View {
        Button(action: save) {
            Label("保存到相册", systemImage: "square.and.arrow.down")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func actionLabel(title: String, system: String, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
            Text(title)
        }
        .font(.system(.body, design: .rounded, weight: .bold))
        .foregroundStyle(prominent ? Color.white : ink)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background {
            if prominent {
                LinearGradient(
                    colors: [Color(hex: 0xC4553A), Color(hex: 0xD4894A)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.white
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if !prominent {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ink.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(color: prominent ? accent.opacity(0.28) : Color.black.opacity(0.05), radius: prominent ? 12 : 8, y: 6)
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "当前设备没有相机，先用上传照片试试"
            return
        }
        errorMessage = nil
        showCamera = true
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: PhotoFile.self)?.data else {
                errorMessage = StampError.unreadable.localizedDescription
                return
            }
            await process(data)
        } catch {
            errorMessage = StampError.unreadable.localizedDescription
        }
    }

    private func process(_ data: Data, resetPreview: Bool = true) async {
        let token = UUID()
        let look = self.look
        jobID = token
        sourceData = data
        isBusy = true
        errorMessage = nil
        savedHint = nil
        if resetPreview {
            stamp = nil
        }

        do {
            let png = try await Task.detached(priority: .userInitiated) {
                try StampMaker.makePNG(from: data, look: look)
            }.value
            guard jobID == token else { return }
            guard let image = UIImage(data: png) else {
                throw StampError.renderFailed
            }
            withAnimation(.spring(duration: 0.35)) {
                stamp = image
            }
            if resetPreview {
                successCount += 1
            }
        } catch {
            guard jobID == token else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? StampError.renderFailed.localizedDescription
        }

        if jobID == token {
            isBusy = false
        }
    }

    private func save() {
        guard let stamp else { return }
        let paper = self.paper
        let payload: UIImage
        if paper == .clear {
            payload = stamp
        } else if let card = renderCard(stamp: stamp, paper: paper) {
            payload = card
        } else {
            errorMessage = StampError.renderFailed.localizedDescription
            return
        }

        Task {
            do {
                try await PhotoLibrary.save(payload)
                savedHint = "已保存到相册"
                errorMessage = nil
            } catch {
                savedHint = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? StampError.renderFailed.localizedDescription
            }
        }
    }

    @MainActor
    private func renderCard(stamp: UIImage, paper: StampPaper) -> UIImage? {
        let renderer = ImageRenderer(
            content: StampCard(stamp: stamp, paper: paper)
                .frame(width: 900, height: 1125)
        )
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

enum StampPaper: String, CaseIterable, Identifiable {
    case clear
    case rice
    case kraft
    case airmail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "透明"
        case .rice: "米纸"
        case .kraft: "牛皮"
        case .airmail: "航空"
        }
    }
}

struct StampCard: View {
    let stamp: UIImage
    let paper: StampPaper

    var body: some View {
        ZStack {
            StampPaperFill(kind: paper)
            Image(uiImage: stamp)
                .resizable()
                .scaledToFit()
                .padding(48)
                .shadow(color: Color(hex: 0x6B3A2A).opacity(0.22), radius: 18, y: 10)
        }
    }
}

struct StampPaperFill: View {
    let kind: StampPaper

    var body: some View {
        switch kind {
        case .clear:
            Checkerboard()
        case .rice:
            LinearGradient(
                colors: [Color(hex: 0xFBF6EE), Color(hex: 0xF0E4D0)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .kraft:
            LinearGradient(
                colors: [Color(hex: 0xE0BE86), Color(hex: 0xC49662)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .airmail:
            airmail
        }
    }

    private var airmail: some View {
        GeometryReader { geo in
            let stripe = max(8, geo.size.width * 0.035)
            ZStack {
                Color(hex: 0xF7F3EA)
                HStack(spacing: 0) {
                    stripeColumn(width: stripe, height: geo.size.height)
                    Spacer()
                    stripeColumn(width: stripe, height: geo.size.height)
                }
                VStack(spacing: 0) {
                    stripeRow(height: stripe, width: geo.size.width)
                    Spacer()
                    stripeRow(height: stripe, width: geo.size.width)
                }
            }
        }
    }

    private func stripeColumn(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            var y: CGFloat = 0
            var red = true
            let band = width * 1.15
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: band)
                context.fill(Path(rect), with: .color(red ? Color(hex: 0xD94B4B) : Color(hex: 0x3E6FBF)))
                y += band
                red.toggle()
            }
        }
        .frame(width: width, height: height)
    }

    private func stripeRow(height: CGFloat, width: CGFloat) -> some View {
        Canvas { context, size in
            var x: CGFloat = 0
            var red = true
            let band = height * 1.15
            while x < size.width {
                let rect = CGRect(x: x, y: 0, width: band, height: size.height)
                context.fill(Path(rect), with: .color(red ? Color(hex: 0xD94B4B) : Color(hex: 0x3E6FBF)))
                x += band
                red.toggle()
            }
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    StampView(page: .constant(.stamp))
}
