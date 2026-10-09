Pod::Spec.new do |s|
  s.name             = 'LetsBotChat'
  s.version          = '0.2.0'
  s.summary          = 'LetsBot In-App Chat for iOS: support chat answered by your LetsBot AI assistant and team.'
  s.description      = <<-DESC
    Add a support chat to your iOS app. Conversations are answered by the same LetsBot AI assistant and human team
    that already answer the business on WhatsApp and on its website, and land in the LetsBot inbox. Includes verified
    identity, push notifications (APNs or FCM), unread badge, context and a ready-made chat screen for UIKit and SwiftUI.
  DESC
  s.homepage         = 'https://letsbot.net/developers/in-app-chat'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'LetsBot' => 'support@letsbot.net' }
  s.source           = { :git => 'https://github.com/Lets-Bot/letsbot-chat-ios.git', :tag => s.version.to_s }
  s.documentation_url = 'https://letsbot.net/developers/in-app-chat'

  s.ios.deployment_target = '13.0'
  s.swift_versions   = ['5.9', '5.10', '6.0']

  s.source_files     = 'Sources/LetsBotChat/**/*.swift'
  s.resource_bundles = { 'LetsBotChat_Privacy' => ['Sources/LetsBotChat/Resources/PrivacyInfo.xcprivacy'] }
  s.frameworks       = 'UIKit', 'WebKit', 'Security', 'CryptoKit', 'Combine'
  s.weak_frameworks  = 'SwiftUI'
end
