//
//  ContentView.swift
//  ImageDemo
//

import Photos
import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var sticker: UIImage?
    @State private var backdrop: StickerBackdrop = .peach
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var savedHint: String?
    @State private var successCount = 0
    @State private var jobID = UUID()

    private let cardShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFFF1F6), Color(hex: 0xF3EEFF)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    preview
                    backdropPicker
                    actions
                    if sticker != nil {
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
        .tint(Color(hex: 0xFF5C7A))
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
            Text("自动抠图")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0xFF4D73))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.86), in: Capsule())

            Text("一键贴纸")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x241226))

            Text("人物、宠物、物品，拍完就贴出来")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(hex: 0x6B5872))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        ZStack {
            BackdropFill(kind: backdrop)

            if let sticker {
                Image(uiImage: sticker)
                    .resizable()
                    .scaledToFit()
                    .padding(36)
                    .shadow(color: Color(hex: 0x3B2148).opacity(0.2), radius: 16, y: 10)
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
                        Text("正在抠出主体…")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x241226))
                    }
                }
            }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
        }
        .shadow(color: Color(hex: 0xC9A6D6).opacity(0.45), radius: 24, y: 14)
        .animation(.spring(duration: 0.35), value: sticker != nil)
        .animation(.easeInOut(duration: 0.2), value: backdrop)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28, weight: .semibold))
            Text("贴纸会出现在这里")
                .font(.system(.headline, design: .rounded))
            Text("自动抠出人物、宠物或物品")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color(hex: 0x6B5872))
        }
        .foregroundStyle(Color(hex: 0x241226))
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var backdropPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("背景")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color(hex: 0x241226))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StickerBackdrop.allCases) { item in
                        Button {
                            backdrop = item
                        } label: {
                            VStack(spacing: 6) {
                                BackdropFill(kind: item)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .padding(2)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(backdrop == item ? Color(hex: 0xFF4D73) : Color.white.opacity(0.7))
                                    }
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(backdrop == item ? Color(hex: 0xFF4D73) : Color(hex: 0x6B5872))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(backdrop == item ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }

            Text(backdrop == .clear ? "透明背景保存后没有底色" : "换背景不用重新抠图")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(hex: 0x8A7694))
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
                .foregroundStyle(Color(hex: 0xFF4D73))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(hex: 0xFF4D73).opacity(0.18), lineWidth: 1)
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
        .foregroundStyle(prominent ? Color.white : Color(hex: 0x241226))
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background {
            if prominent {
                LinearGradient(
                    colors: [Color(hex: 0xFF4D73), Color(hex: 0xFF8A4C)],
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
                    .strokeBorder(Color(hex: 0x241226).opacity(0.06), lineWidth: 1)
            }
        }
        .shadow(
            color: prominent ? Color(hex: 0xFF4D73).opacity(0.32) : Color.black.opacity(0.05),
            radius: prominent ? 12 : 8,
            y: 6
        )
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
                errorMessage = StickerError.unreadable.localizedDescription
                return
            }
            await process(data)
        } catch {
            errorMessage = StickerError.unreadable.localizedDescription
        }
    }

    private func process(_ data: Data) async {
        let token = UUID()
        jobID = token
        isBusy = true
        errorMessage = nil
        savedHint = nil
        sticker = nil

        do {
            let png = try await Task.detached(priority: .userInitiated) {
                try StickerMaker.makePNG(from: data)
            }.value
            guard jobID == token else { return }
            guard let image = UIImage(data: png) else {
                throw StickerError.renderFailed
            }
            withAnimation(.spring(duration: 0.35)) {
                sticker = image
            }
            successCount += 1
        } catch {
            guard jobID == token else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? StickerError.renderFailed.localizedDescription
        }

        if jobID == token {
            isBusy = false
        }
    }

    private func save() {
        guard let sticker else { return }
        let backdrop = self.backdrop
        let payload: UIImage
        if backdrop == .clear {
            payload = sticker
        } else if let card = renderCard(sticker: sticker, backdrop: backdrop) {
            payload = card
        } else {
            errorMessage = StickerError.renderFailed.localizedDescription
            return
        }

        Task {
            do {
                try await PhotoLibrary.save(payload)
                savedHint = "已保存到相册"
                errorMessage = nil
            } catch {
                savedHint = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? StickerError.renderFailed.localizedDescription
            }
        }
    }

    @MainActor
    private func renderCard(sticker: UIImage, backdrop: StickerBackdrop) -> UIImage? {
        let renderer = ImageRenderer(
            content: StickerCard(sticker: sticker, backdrop: backdrop)
                .frame(width: 900, height: 1125)
        )
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private struct PhotoFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PhotoFile(data: data)
        }
    }
}

private enum PhotoLibrary {
    static func save(_ image: UIImage) async throws {
        let status = await addAuthorization()
        guard status == .authorized || status == .limited else {
            throw StickerError.noPermission
        }
        guard let data = image.pngData() else {
            throw StickerError.renderFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? StickerError.renderFailed)
                }
            }
        }
    }

    private static func addAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

#Preview {
    ContentView()
}
