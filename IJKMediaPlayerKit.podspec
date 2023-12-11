#
# Be sure to run `pod lib lint IJKMediaPlayerKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'IJKMediaPlayerKit'
  s.version          = '0.10.4'
  s.summary          = 'IJKMediaPlayerKit for ios/macOS.'
  
# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/debugly/ijkplayer'
  s.license          = { :type => 'LGPLv2.1', :text => 'LICENSE' }
  s.author           = { 'MattReach' => 'qianlongxu@gmail.com' }
  s.source           = { :git => 'https://github.com/debugly/ijkplayer', :tag => s.version.to_s }

  #metal 2.0 required
  s.osx.deployment_target = '10.11'
  s.ios.deployment_target = '11.0'

  s.osx.pod_target_xcconfig = {
    'ALWAYS_SEARCH_USER_PATHS' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '${PODS_TARGET_SRCROOT}/shell/build/product/macos/universal/ffmpeg/include',
      '${PODS_TARGET_SRCROOT}/ijkmedia'
    ],
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) IJK_USE_METAL_2=1',
    'METAL_LIBRARY_OUTPUT_DIR' => '${CONFIGURATION_BUILD_DIR}/IJKMediaPlayerKit.framework/Resources',
    'MTL_LANGUAGE_REVISION' => 'Metal20'
  }

  s.ios.pod_target_xcconfig = {
    'ALWAYS_SEARCH_USER_PATHS' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '${PODS_TARGET_SRCROOT}/shell/build/product/ios/universal/ffmpeg/include',
      '${PODS_TARGET_SRCROOT}/ijkmedia'
    ],
    'EXCLUDED_ARCHS' => 'armv7',
    # fix apple m1 building iOS Simulator platform,linking xxx built
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) IJK_USE_METAL_2=1',
    'METAL_LIBRARY_OUTPUT_DIR' => '${CONFIGURATION_BUILD_DIR}/IJKMediaPlayerKit.framework',
    'MTL_LANGUAGE_REVISION' => 'Metal20'
  }

  # fix apple m1 building iOS Simulator platform,linking xxx built
  s.ios.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }

  s.script_phases = [
    { 
      :name => 'ijkversion.h',
      :shell_path => '/bin/sh',
      :script => 'sh "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer/version.sh" "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer" "ijkversion.h"',
      :execution_position => :before_compile
    }
  ]

  s.source_files = 
    'ijkmedia/ijkplayer/**/*.{h,c,m,cpp}',
    'ijkmedia/ijksdl/**/*.{h,c,m,cpp,metal}',
    'ijkmedia/wrapper/apple/*.{h,m}'
  # s.project_header_files = 'ijkmedia/**/*.{h}'
  s.public_header_files =
    'ijkmedia/wrapper/apple/IJKMediaPlayback.h',
    'ijkmedia/wrapper/apple/IJKFFOptions.h',
    'ijkmedia/wrapper/apple/IJKFFMonitor.h',
    'ijkmedia/wrapper/apple/IJKFFMoviePlayerController.h',
    'ijkmedia/wrapper/apple/IJKMediaModule.h',
    'ijkmedia/wrapper/apple/IJKMediaPlayer.h',
    'ijkmedia/wrapper/apple/IJKNotificationManager.h',
    'ijkmedia/wrapper/apple/IJKKVOController.h',
    'ijkmedia/wrapper/apple/IJKVideoRenderingProtocol.h',
    'ijkmedia/wrapper/apple/IJKMediaPlayerKit.h',
    'ijkmedia/wrapper/apple/IJKInternalRenderView.h'
  s.exclude_files = 
    'ijkmedia/ijksdl/ijksdl_extra_log.c',
    'ijkmedia/ijkplayer/ijkversion.h',
    'ijkmedia/ijkplayer/ijkavformat/ijkioandroidio.c',
    'ijkmedia/ijkplayer/android/**/*.*',
    'ijkmedia/ijksdl/android/**/*.*',
    'ijkmedia/ijksdl/ffmpeg/ijksdl_vout_overlay_ffmpeg.{h,c}'
  s.osx.exclude_files = 
    'ijkmedia/ijksdl/ijksdl_egl.*',
    'ijkmedia/ijksdl/ios/*.*',
    'ijkmedia/wrapper/apple/IJKAudioKit.*'
  s.ios.exclude_files = 'ijkmedia/ijksdl/mac/*.*'

  s.osx.vendored_libraries = 'shell/build/product/macos/universal/**/*.a'
  s.ios.vendored_libraries = 'shell/build/product/ios/universal/**/*.a'
  s.osx.frameworks = 'Cocoa', 'AudioUnit', 'OpenGL', 'GLKit', 'CoreImage'
  s.ios.frameworks = 'UIKit', 'OpenGLES'

  s.library = 'z', 'iconv', 'xml2', 'bz2', 'c++', 'lzma'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo', 'VideoToolbox', 'Metal'
  
end
