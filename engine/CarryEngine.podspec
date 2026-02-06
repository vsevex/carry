Pod::Spec.new do |s|
  s.name             = 'CarryEngine'
  s.version          = '0.1.0'
  s.summary          = 'Carry sync engine native library'
  s.description      = 'Native Rust library for the Carry local-first sync engine'
  s.homepage         = 'https://github.com/carry/carry'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Carry' => 'carry@example.com' }
  s.source           = { :path => '.' }
  
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  
  s.vendored_frameworks = 'target/ios/CarryEngine.xcframework'
  s.source_files = 'include/**/*.h'
  s.public_header_files = 'include/**/*.h'
  
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/CarryEngine/target/ios/CarryEngine.xcframework/ios-arm64/libcarry_engine.a',
  }
  
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC',
  }
end
