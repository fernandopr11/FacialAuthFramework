import Foundation
import AVFoundation
import UIKit

@MainActor
internal class TrueDepthCameraManager: NSObject {
    
    // MARK: - Properties
    private var captureSession: AVCaptureSession?
    private var frontCamera: AVCaptureDevice?
    private var frontCameraInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    private let debugMode: Bool
    private var isSessionRunning = false
    
    // Delegate para callbacks
    internal weak var delegate: CameraManagerDelegate?
    
    // ✅ AGREGAR: Queue para video processing
    private let videoQueue = DispatchQueue(label: "com.facialauth.video", qos: .userInitiated)
    
    // Estado de captura
    private var isCapturing = false
    private var capturedPhotos: [UIImage] = []
    
    // MARK: - Initialization
    internal init(debugMode: Bool = false) {
        self.debugMode = debugMode
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Configurar la sesión de cámara
    internal func setupCamera() async throws {
        if debugMode {
            print("📹 TrueDepthCamera: Configurando cámara...")
        }
        
        // Verificar permisos
        guard await checkCameraPermission() else {
            throw CameraError.permissionDenied
        }
        
        // ✅ MOVER A BACKGROUND THREAD
        let session = AVCaptureSession()
        
        // Configurar calidad
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        
        // Configurar cámara frontal
        try configureFrontCamera(session: session)
        
        // Configurar outputs
        try configurePhotoOutput(session: session)
        try configureVideoOutput(session: session) // ✅ AGREGAR VIDEO OUTPUT
        try configureDepthOutput(session: session)
        
        self.captureSession = session
        
        if debugMode {
            print("✅ TrueDepthCamera: Cámara configurada exitosamente")
        }
        
        delegate?.cameraDidSetup()
    }
    
    /// Iniciar preview de cámara
    internal func startSession() {
        guard let session = captureSession else {
            delegate?.cameraDidFail(error: .sessionNotConfigured)
            return
        }
        
        if !isSessionRunning {
            // ✅ MOVER A BACKGROUND THREAD
            Task.detached { [weak self] in
                session.startRunning()
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isSessionRunning = true
                    
                    if self.debugMode {
                        print("▶️ TrueDepthCamera: Sesión iniciada")
                    }
                    
                    self.delegate?.cameraDidStart()
                }
            }
        }
    }
    
    /// Detener preview de cámara
    internal func stopSession() {
        guard let session = captureSession else { return }
        
        if isSessionRunning {
            // ✅ MOVER A BACKGROUND THREAD
            Task.detached { [weak self] in
                session.stopRunning()
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isSessionRunning = false
                    
                    if self.debugMode {
                        print("⏹️ TrueDepthCamera: Sesión detenida")
                    }
                    
                    self.delegate?.cameraDidStop()
                }
            }
        }
    }
    
    /// ✅ NUEVO: Configurar delegate para video frames
    internal func setVideoDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        videoOutput?.setSampleBufferDelegate(delegate, queue: videoQueue)
        
        if debugMode {
            print("📹 TrueDepthCamera: Video delegate configurado")
        }
    }
    
    /// Capturar foto
    internal func capturePhoto() {
        guard let photoOutput = photoOutput else {
            delegate?.cameraDidFail(error: .captureOutputNotConfigured)
            return
        }
        
        guard !isCapturing else {
            if debugMode {
                print("⚠️ TrueDepthCamera: Ya hay una captura en progreso")
            }
            return
        }
        
        isCapturing = true
        // Configurar formato de foto
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        
        // Habilitar depth data si está disponible
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = true
        }
        
        // Configurar calidad
        settings.photoQualityPrioritization = .quality
        
        if debugMode {
            print("📸 TrueDepthCamera: Capturando foto...")
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    /// Obtener preview layer para mostrar en UI
    internal func getPreviewLayer() -> CALayer? {
        guard let session = captureSession else { return nil }
        
        if videoPreviewLayer == nil {
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
            videoPreviewLayer?.videoGravity = .resizeAspectFill
            
            if debugMode {
                print("📺 TrueDepthCamera: Preview layer creado")
            }
        }
        
        return videoPreviewLayer
    }
    
    /// Verificar si TrueDepth está disponible
    internal var isTrueDepthAvailable: Bool {
        guard let frontCamera = frontCamera else { return false }
        return frontCamera.activeDepthDataFormat != nil
    }
    
    /// Limpiar recursos
    internal func cleanup() {
        stopSession()
        captureSession = nil
        frontCamera = nil
        frontCameraInput = nil
        photoOutput = nil
        videoOutput = nil // ✅ AGREGAR
        depthDataOutput = nil
        videoPreviewLayer = nil
        
        if debugMode {
            print("🧹 TrueDepthCamera: Recursos limpiados")
        }
    }
}

// MARK: - Private Methods
private extension TrueDepthCameraManager {
    
    func checkCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    func configureFrontCamera(session: AVCaptureSession) throws {
        // Buscar cámara frontal con TrueDepth
        guard let camera = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) ??
                            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.frontCameraNotAvailable
        }
        
        // Crear input
        let input = try AVCaptureDeviceInput(device: camera)
        
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        
        session.addInput(input)
        
        self.frontCamera = camera
        self.frontCameraInput = input
        
        // Configurar formatos con depth si está disponible
        if camera.activeFormat.supportedDepthDataFormats.count > 0 {
            try configureCameraForDepth(camera: camera)
        }
        
        if debugMode {
            let depthAvailable = camera.activeDepthDataFormat != nil
            print("📹 TrueDepthCamera: Cámara frontal configurada")
            print("   - Dispositivo: \(camera.localizedName)")
            print("   - TrueDepth: \(depthAvailable ? "SÍ" : "NO")")
        }
    }
    
    func configureCameraForDepth(camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        
        // Buscar formato compatible con depth
        let depthFormats = camera.activeFormat.supportedDepthDataFormats
        if let depthFormat = depthFormats.first {
            camera.activeDepthDataFormat = depthFormat
            
            if debugMode {
                print("✅ TrueDepthCamera: Formato depth configurado")
            }
        }
        
        camera.unlockForConfiguration()
    }
    
    func configurePhotoOutput(session: AVCaptureSession) throws {
        let output = AVCapturePhotoOutput()
        
        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        
        session.addOutput(output)
        
        // Configurar depth data si está disponible
        if output.isDepthDataDeliverySupported {
            output.isDepthDataDeliveryEnabled = true
        }
        
        self.photoOutput = output
        
        if debugMode {
            print("📷 TrueDepthCamera: Photo output configurado")
            print("   - Depth data: \(output.isDepthDataDeliverySupported ? "SÍ" : "NO")")
        }
    }
    
    // ✅ NUEVO: Configurar video output para frames en tiempo real
    func configureVideoOutput(session: AVCaptureSession) throws {
        let output = AVCaptureVideoDataOutput()
        
        // Configurar formato de pixel
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Descartar frames si el processing está ocupado
        output.alwaysDiscardsLateVideoFrames = true
        
        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }
        
        session.addOutput(output)
        self.videoOutput = output
        
        if debugMode {
            print("📹 TrueDepthCamera: Video output configurado")
        }
    }
    
    func configureDepthOutput(session: AVCaptureSession) throws {
        let output = AVCaptureDepthDataOutput()
        
        guard session.canAddOutput(output) else {
            if debugMode {
                print("⚠️ TrueDepthCamera: No se puede agregar depth output")
            }
            return // No es crítico
        }
        
        session.addOutput(output)
        
        // Configurar conexión
        if let connection = output.connection(with: .depthData) {
            connection.isEnabled = true
        }
        
        self.depthDataOutput = output
        
        if debugMode {
            print("🎯 TrueDepthCamera: Depth output configurado")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension TrueDepthCameraManager: AVCapturePhotoCaptureDelegate {

    nonisolated internal func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        // Captura segura de los datos binarios de la imagen
        guard let imageData = photo.fileDataRepresentation() else {
            Task { @MainActor in
                isCapturing = false
                if debugMode {
                    print("❌ TrueDepthCamera: No se pudo obtener datos de imagen")
                }
                delegate?.cameraDidFail(error: .imageProcessingError)
            }
            return
        }

        // Serializar depthData de forma segura sin riesgo de data race
        var depthDataSerialized: Data? = nil
        if let originalDepthData = photo.depthData {
            depthDataSerialized = try? NSKeyedArchiver.archivedData(withRootObject: originalDepthData, requiringSecureCoding: false)
        }

        Task { @MainActor in
            isCapturing = false

            guard let image = UIImage(data: imageData) else {
                if debugMode {
                    print("❌ TrueDepthCamera: No se pudo procesar imagen")
                }
                delegate?.cameraDidFail(error: .imageProcessingError)
                return
            }

            // Deserializar depthData desde el MainActor (seguro)
            var depthData: AVDepthData? = nil
            if let serialized = depthDataSerialized {
                depthData = NSKeyedUnarchiver.unarchiveObject(with: serialized) as? AVDepthData
            }

            if debugMode {
                print("✅ TrueDepthCamera: Foto capturada exitosamente")
                print("   - Resolución: \(image.size)")
                print("   - Depth data: \(depthData != nil ? "SÍ" : "NO")")
            }

            delegate?.cameraDidCapturePhoto(image: image, depthData: depthData)
        }
    }
}

// MARK: - Camera Manager Delegate
internal protocol CameraManagerDelegate: AnyObject {
    func cameraDidSetup()
    func cameraDidStart()
    func cameraDidStop()
    func cameraDidCapturePhoto(image: UIImage, depthData: AVDepthData?)
    func cameraDidFail(error: CameraError)
}

// Extensión para hacer métodos opcionales
internal extension CameraManagerDelegate {
    func cameraDidSetup() {}
    func cameraDidStart() {}
    func cameraDidStop() {}
}

// MARK: - Camera Errors
internal enum CameraError: Error {
    case permissionDenied
    case frontCameraNotAvailable
    case sessionNotConfigured
    case cannotAddInput
    case cannotAddOutput
    case captureOutputNotConfigured
    case captureError
    case imageProcessingError
}

extension CameraError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permiso de cámara denegado"
        case .frontCameraNotAvailable:
            return "Cámara frontal no disponible"
        case .sessionNotConfigured:
            return "Sesión de cámara no configurada"
        case .cannotAddInput:
            return "No se puede agregar input de cámara"
        case .cannotAddOutput:
            return "No se puede agregar output de cámara"
        case .captureOutputNotConfigured:
            return "Output de captura no configurado"
        case .captureError:
            return "Error durante la captura"
        case .imageProcessingError:
            return "Error procesando la imagen"
        }
    }
}
