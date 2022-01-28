#
# Be sure to run `pod lib lint IJKMediaPlayerKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'IJKMediaPlayeriOSKit'
  s.version          = '0.9.0.4'
  s.summary          = 'IJKMediaPlayeriOSKit for iOS.'
  
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

  s.ios.deployment_target = '9.0'

  s.ios.user_target_xcconfig = {
    'SUPPORTS_MACCATALYST' => 'NO'
  }

  s.ios.pod_target_xcconfig = {
    'SUPPORTS_MACCATALYST' => 'NO',
    'ALWAYS_SEARCH_USER_PATHS' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '${PODS_TARGET_SRCROOT}/shell/build/product/ios/universal/ffmpeg/include',
      '${PODS_TARGET_SRCROOT}/shell/build/product/ios/universal/libyuv/include',
      '${PODS_TARGET_SRCROOT}/ijkmedia'
    ]
  }

  s.script_phases = [
    { 
      :name => 'ijkversion.h',
      :shell_path => '/bin/sh',
      :script => 'sh "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer/version.sh" "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer" "ijkversion.h"',
      :execution_position => :before_compile
    }
  ]

  s.subspec 'IJKMediaPlayerKit' do |ss|
    ss.source_files = 'IJKMediaPlayerKit/*.{h,m}'
    ss.public_header_files = 
      'IJKMediaPlayerKit/IJKMediaPlayback.h',
      'IJKMediaPlayerKit/IJKFFOptions.h',
      'IJKMediaPlayerKit/IJKFFMonitor.h',
      'IJKMediaPlayerKit/IJKFFMoviePlayerController.h',
      'IJKMediaPlayerKit/IJKMediaModule.h',
      'IJKMediaPlayerKit/IJKMediaPlayer.h',
      'IJKMediaPlayerKit/IJKNotificationManager.h',
      'IJKMediaPlayerKit/IJKKVOController.h',
      'IJKMediaPlayerKit/IJKSDLGLViewProtocol.h'
    ss.ios.public_header_files = 'IJKMediaPlayerKit/IJKMediaPlayeriOSKit.h'
    ss.ios.exclude_files = 'IJKMediaPlayerKit/IJKMediaPlayerKit.h'
  end

  s.subspec 'ijkmedia' do |ss|
    ss.source_files = 
      'ijkmedia/ijkplayer/**/*.{h,c,m,cpp}',
      'ijkmedia/ijksdl/**/*.{h,c,m,cpp}'
    ss.project_header_files = 'ijkmedia/**/*.{h}'

    ss.exclude_files = 
      'ijkmedia/ijksdl/ijksdl_extra_log.c',
      'ijkmedia/ijkplayer/ijkversion.h',
      'ijkmedia/ijkplayer/ijkavformat/ijkioandroidio.c',
      'ijkmedia/ijkplayer/android/**/*.*',
      'ijkmedia/ijksdl/android/**/*.*',
      'ijkmedia/ijksdl/ffmpeg/ijksdl_vout_overlay_ffmpeg.{h,c}',

      # -w
      'ijkmedia/ijkplayer/ijkavutil/ijkdict.*',
      'ijkmedia/ijkplayer/ijkavutil/ijkfifo.*',
      'ijkmedia/ijkplayer/ijkavutil/ijkstl.*',
      # -fno-objc-arc
      'ijkmedia/ijksdl/apple/ijksdl_aout_ios_audiounit.*',
      'ijkmedia/ijksdl/apple/ijksdl_vout_ios_gles2.*',

    ss.ios.exclude_files = 
      'ijkmedia/ijksdl/mac/*.*',
      'ijkmedia/ijksdl/gles2/fsh/mac/*.*',
      'ijkmedia/ijksdl/gles2/vsh/mac/*.*'

  end

  s.subspec 'no-arc' do |ss|
    ss.source_files = 
      'ijkmedia/ijksdl/apple/ijksdl_aout_ios_audiounit.*',
      'ijkmedia/ijksdl/apple/ijksdl_vout_ios_gles2.*'
    ss.project_header_files = 'ijkmedia/ijksdl/apple/*.{h}'
    ss.compiler_flags = '-fno-objc-arc'
  end

  s.subspec 'w' do |ss|
    ss.source_files = 'ijkmedia/ijkplayer/ijkavutil/ijkdict.*',
      'ijkmedia/ijkplayer/ijkavutil/ijkfifo.*',
      'ijkmedia/ijkplayer/ijkavutil/ijkstl.*'
    ss.project_header_files = 'ijkmedia/ijkplayer/ijkavutil/*.{h}'
    ss.compiler_flags = '-w'
  end
  
  s.library = 'z', 'iconv', 'xml2', 'bz2', 'c++'
  s.ios.vendored_libraries = 'shell/build/product/ios/universal/**/*.a'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo', 'VideoToolbox', 'AudioUnit'
  
end
