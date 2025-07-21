Pod::Spec.new do |spec|
  spec.name         = "FacialAuthFramework"
  spec.version      = "1.0.0"
  spec.summary      = "Advanced facial authentication framework for iOS"
  spec.description  = <<-DESC
    FacialAuth Framework provides advanced facial authentication for iOS apps
    using TrueDepth Camera, Core ML, and Vision Framework. Features include
    AES-256 encryption, local processing, and multi-user support.
  DESC
  
  spec.homepage     = "https://github.com/fernandopr11/FacialAuthFramework"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Fernando Paucar" => "fernandopaucar149@gmail.com" }
  
  spec.platform     = :ios, "15.0"
  spec.swift_version = "5.9"
  
  spec.source       = {
    :git => "https://github.com/fernandopr11/FacialAuthFramework.git",
    :tag => "#{spec.version}"
  }
  
  spec.source_files = "Sources/FacialAuthFramework/**/*.{swift,h,m}"
  
  spec.frameworks   = "UIKit", "AVFoundation", "Vision", "CoreML", "CryptoKit"
  
  spec.requires_arc = true
end
