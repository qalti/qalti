import Foundation
import AWSS3
import AWSSDKIdentity

// MARK: - S3 presigned URL container
struct S3URLPair {
    let uploadURL: URL
    let downloadURL: URL
    let filePath: String
}

// MARK: - Screenshot uploader for S3 integration
final class ScreenshotUploader {
    
    // MARK: - Properties
    private let session: URLSession
    private let credentialsService: CredentialsService
    private let errorCapturer: ErrorCapturing

    // MARK: - Initialization
    init(credentialsService: CredentialsService, errorCapturer: ErrorCapturing) {
        self.credentialsService = credentialsService
        self.errorCapturer = errorCapturer

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Uploads screenshot to S3 and returns the download URL for use in chat history
    /// - Parameters:
    ///   - image: The screenshot image to upload
    ///   - filename: Optional filename (defaults to screenshot-{timestamp}.jpg)
    ///   - completion: Callback with download URL or error
    func uploadScreenshot(
        image: PlatformImage,
        filename: String? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Generate filename with timestamp if not provided
        let finalFilename = filename ?? "screenshot-\(Int(Date().timeIntervalSince1970)).jpg"

        // Convert image to JPEG data
        guard let imageData = image.jpegData() else {
            completion(.failure(UIElementLocator.Error.screenshotConversionFailed))
            return
        }

        // If S3 is not configured, fall back to a base64 data URL for the LLM.
        if credentialsService.s3Settings == nil {
            let dataURLString = imageData.toBase64JpegURLString()
            guard let dataURL = URL(string: dataURLString) else {
                completion(.failure(UIElementLocator.Error.invalidResponseFormat))
                return
            }
            completion(.success(dataURL))
            return
        }
        
        // Step 1: Generate presigned URLs locally
        generatePresignedURLs(filename: finalFilename, contentType: "image/jpeg") { result in
            switch result {
            case .success(let urlPair):
                // Step 2: Upload to S3 using presigned URL
                self.uploadToS3(imageData: imageData, uploadURL: urlPair.uploadURL, contentType: "image/jpeg") { uploadResult in
                    switch uploadResult {
                    case .success:
                        // Step 3: Return download URL
                        completion(.success(urlPair.downloadURL))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate presigned URLs locally using AWS SDK for Swift
    private func generatePresignedURLs(
        filename: String,
        contentType: String,
        completion: @escaping (Result<S3URLPair, Error>) -> Void
    ) {
        guard let settings = credentialsService.s3Settings else {
            completion(.failure(UIElementLocator.Error.s3ConfigurationMissing))
            return
        }

        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFilename = trimmedFilename.isEmpty
            ? "screenshot-\(Int(Date().timeIntervalSince1970)).jpg"
            : trimmedFilename
        let objectKey = "uploads/\(UUID().uuidString)-\(safeFilename)"
        let expiration = TimeInterval(settings.effectivePresignTTLSeconds)

        Task {
            do {
                let credentials = AWSCredentialIdentity(
                    accessKey: settings.accessKeyId,
                    secret: settings.secretAccessKey,
                    sessionToken: nil
                )
                let identityResolver = try StaticAWSCredentialIdentityResolver(credentials)
                let config = try await S3Client.S3ClientConfiguration(
                    awsCredentialIdentityResolver: identityResolver,
                    region: settings.region
                )

                let putInput = PutObjectInput(
                    bucket: settings.bucket,
                    contentType: contentType,
                    key: objectKey
                )
                guard let uploadURL = try await putInput.presignURL(
                    config: config,
                    expiration: expiration
                ) else {
                    completion(.failure(UIElementLocator.Error.invalidResponseFormat))
                    return
                }

                let getInput = GetObjectInput(
                    bucket: settings.bucket,
                    key: objectKey
                )
                guard let downloadURL = try await getInput.presignURL(
                    config: config,
                    expiration: expiration
                ) else {
                    completion(.failure(UIElementLocator.Error.invalidResponseFormat))
                    return
                }

                completion(.success(S3URLPair(
                    uploadURL: uploadURL,
                    downloadURL: downloadURL,
                    filePath: objectKey
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Upload image data to S3 using presigned URL
    private func uploadToS3(
        imageData: Data,
        uploadURL: URL,
        contentType: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(UIElementLocator.Error.connectionError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(UIElementLocator.Error.connectionError(URLError(.cannotWriteToFile))))
                return
            }
            
            completion(.success(()))
        }.resume()
    }
}
