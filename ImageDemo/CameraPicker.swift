//
//  CameraPicker.swift
//  ImageDemo
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onCapture: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onCapture = onCapture
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var isPresented: Bool
        var onCapture: (Data) -> Void

        init(isPresented: Binding<Bool>, onCapture: @escaping (Data) -> Void) {
            _isPresented = isPresented
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92)
            isPresented = false
            if let data {
                onCapture(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented = false
        }
    }
}
