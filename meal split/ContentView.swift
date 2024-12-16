//
//  ContentView.swift
//  meal split
//
//  Created by Katherine on 11/22/24.
//

import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var scannedText = "No data scanned yet."

    var body: some View {
        VStack(spacing: 20) {
            Button("Scan Receipt (Camera)") {
                isCameraPresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding()

            Button("Upload Receipt (Photo Library)") {
                isPhotoPickerPresented = true
            }
            .buttonStyle(.bordered)
            .padding()

            Text(scannedText)
                .padding()
                .multilineTextAlignment(.center)
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraView { result in
                handleResult(result)
                isCameraPresented = false
            }
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoPickerView { result in
                handleResult(result)
                isPhotoPickerPresented = false
            }
        }
    }

    private func handleResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let text):
            scannedText = text
        case .failure(let error):
            scannedText = "Error: \(error.localizedDescription)"
        }
    }
}

func extractNumbersOrPrices(from text: String) -> [String] {
    // Define a regex pattern for numbers, including decimals
    let numberPattern = "[0-9]+(\\.[0-9]{1,2})?" // Matches integers and decimal numbers like 123 or 123.45
    let regex = try? NSRegularExpression(pattern: numberPattern)

    // Find matches in the input text
    let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []

    // Convert matches into strings
    return matches.compactMap {
        if let range = Range($0.range, in: text) {
            return String(text[range])
        }
        return nil
    }
}


// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController
    var onCapture: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (Result<String, Error>) -> Void

        init(onCapture: @escaping (Result<String, Error>) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                onCapture(.failure(NSError(domain: "CameraView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to capture image."])))
                picker.dismiss(animated: true)
                return
            }

            // Perform OCR on the image
            recognizeText(from: image) { result in
                DispatchQueue.main.async {
                    self.onCapture(result)
                }
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(.failure(NSError(domain: "CameraView", code: 2, userInfo: [NSLocalizedDescriptionKey: "User canceled."])))
            picker.dismiss(animated: true)
        }

        // MARK: - OCR Functionality
        private func recognizeText(from image: UIImage, completion: @escaping (Result<[String], Error>) -> Void) {
            guard let cgImage = image.cgImage else {
                completion(.failure(NSError(domain: "CameraView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid image."])))
                return
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Extract recognized text
                let recognizedText = request.results?
                    .compactMap { $0 as? VNRecognizedTextObservation }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                
                // Extract numbers or prices from the recognized text
                let extractedNumbers = extractNumbersOrPrices(from: recognizedText)
                
                completion(.success(extractedNumbers))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            if let image = UIImage(named: "receipt") {
                recognizeText(from: image) { result in
                    switch result {
                    case .success(let numbers):
                        print("Extracted numbers or prices: \(numbers)")
                        // You can display these in the UI or process them further
                    case .failure(let error):
                        print("Failed to recognize text: \(error)")
                    }
                }
            }

            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try requestHandler.perform([request])
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}



// MARK: - Photo Picker View
struct PhotoPickerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController
    var onPick: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onPick: (Result<String, Error>) -> Void

        init(onPick: @escaping (Result<String, Error>) -> Void) {
            self.onPick = onPick
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                onPick(.failure(NSError(domain: "PhotoPickerView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image."])))
                picker.dismiss(animated: true)
                return
            }

            // Perform OCR on the image
            recognizeText(from: image) { result in
                self.onPick(result)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(.failure(NSError(domain: "PhotoPickerView", code: 2, userInfo: [NSLocalizedDescriptionKey: "User canceled."])))
            picker.dismiss(animated: true)
        }

        // MARK: - OCR Functionality
        private func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
            guard let cgImage = image.cgImage else {
                completion(.failure(NSError(domain: "PhotoPickerView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid image."])))
                return
            }

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let recognizedText = request.results?
                    .compactMap { $0 as? VNRecognizedTextObservation }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? "No text found"

                completion(.success(recognizedText))
            }

            do {
                try requestHandler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}


#Preview {
    ContentView()
}

