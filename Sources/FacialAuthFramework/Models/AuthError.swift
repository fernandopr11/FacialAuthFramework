import Foundation

public enum AuthError: Error {
    // Errores de configuración
    case modelNotFound
    case modelLoadingFailed
    
    // Errores de permisos
    case cameraPermissionDenied
    
    // Errores de autenticación
    case userNotRegistered
    case faceNotDetected
    case multipleFacesDetected
    case similarityThresholdNotMet
    case maxAttemptsExceeded
    
    // Errores de registro
    case registrationFailed
    case profileAlreadyExists
    
    // Errores de sistema
    case cameraUnavailable
    case processingFailed
    case unknownError
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Modelo de reconocimiento facial no encontrado"
        case .modelLoadingFailed:
            return "Error al cargar el modelo de IA"
        case .cameraPermissionDenied:
            return "Permiso de cámara denegado"
        case .userNotRegistered:
            return "Usuario no registrado en el sistema"
        case .faceNotDetected:
            return "No se detectó un rostro en la imagen"
        case .multipleFacesDetected:
            return "Múltiples rostros detectados"
        case .similarityThresholdNotMet:
            return "Rostro no coincide con el perfil registrado"
        case .maxAttemptsExceeded:
            return "Máximo número de intentos excedido"
        case .registrationFailed:
            return "Error en el registro del usuario"
        case .profileAlreadyExists:
            return "El perfil de usuario ya existe"
        case .cameraUnavailable:
            return "Cámara no disponible"
        case .processingFailed:
            return "Error procesando la imagen"
        case .unknownError:
            return "Error desconocido"
        }
    }
}
