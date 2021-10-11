#
# Be sure to run `pod lib lint IJKMediaPlayerKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'IJKMediaPlayerKit'
  s.version          = '0.8.8'
  s.summary          = 'IJKMediaPlayerKit for macOS.'

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

  s.osx.deployment_target = '10.11'
  
  s.pod_target_xcconfig = {
    'ALWAYS_SEARCH_USER_PATHS' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '${PODS_TARGET_SRCROOT}/mac/build/universal/include',
      '${PODS_TARGET_SRCROOT}/ijkmedia',
      # '${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer',
      # '${PODS_TARGET_SRCROOT}/ijkmedia/ijksdl',
    ],
    # 'LIBRARY_SEARCH_PATHS' => [
    #   '$(inherited)',
    #   '${PODS_TARGET_SRCROOT}/mac/build/universal/lib'
    # ],
  }

  s.script_phases = [
    { 
      :name => 'ijkversion.h',
      :shell_path => '/bin/sh',
      :script => 'sh "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer/version.sh" "${PODS_TARGET_SRCROOT}/ijkmedia/ijkplayer" "ijkversion.h"',
      :execution_position => :before_compile
    }
  ]

  s.subspec 'mac' do |ss|
    ss.source_files = 'IJKMediaPlayerKit/*.{h,m}'
    ss.public_header_files = 'IJKMediaPlayerKit/IJKMediaPlayerKit.h',
      'IJKMediaPlayerKit/IJKMediaPlayback.h',
      'IJKMediaPlayerKit/IJKFFOptions.h',
      'IJKMediaPlayerKit/IJKFFMonitor.h',
      'IJKMediaPlayerKit/IJKFFMoviePlayerController.h',
      'IJKMediaPlayerKit/IJKMediaModule.h',
      'IJKMediaPlayerKit/IJKMediaPlayer.h',
      'IJKMediaPlayerKit/IJKNotificationManager.h',
      'IJKMediaPlayerKit/IJKKVOController.h',
      'IJKMediaPlayerKit/IJKSDLGLViewProtocol.h'
  end

  s.subspec 'ijkmedia' do |ss|
    ss.source_files = 
     'ijkmedia/ijkplayer/**/*.{h,c,m,cpp}',
     'ijkmedia/ijksdl/**/*.{h,c,m,cpp}'
    ss.project_header_files = 'ijkmedia/**/*.{h}'
    ss.exclude_files = 'ijkmedia/ijkplayer/android/**/*.*',
      'ijkmedia/ijksdl/ios/**/*.*',
      'ijkmedia/ijksdl/android/**/*.*',
      'ijkmedia/ijksdl/gles2/renderer_yuv444p10le.c',
      'ijkmedia/ijksdl/gles2/fsh/yuv444p10le.fsh.c',
      'ijkmedia/ijksdl/ijksdl_extra_log.c',
      'ijkmedia/ijksdl/gles2/fsh/yuv420p.fsh.c',
      'ijkmedia/ijksdl/gles2/vsh/mvp.vsh.c',
      'ijkmedia/ijkplayer/ijkversion.h',
      'ijkmedia/ijkplayer/ijkavformat/ijkioandroidio.c',
      'ijkmedia/ijkplayer/ijkavutil/ijkdict.c',
      'ijkmedia/ijkplayer/ijkavutil/ijkfifo.c',
      'ijkmedia/ijkplayer/ijkavutil/ijkstl.cpp'
  end

  s.subspec 'no-arc' do |ss|
    ss.source_files = 'ijkmedia/ijksdl/apple/ijksdl_aout_ios_audiounit.m',
      'ijkmedia/ijksdl/apple/ijksdl_vout_ios_gles2.m'
    ss.compiler_flags = '-fno-objc-arc'
  end

  s.subspec 'w' do |ss|
    ss.source_files = 'ijkmedia/ijkplayer/ijkavutil/ijkdict.c',
      'ijkmedia/ijkplayer/ijkavutil/ijkfifo.c',
      'ijkmedia/ijkplayer/ijkavutil/ijkstl.cpp'
    ss.compiler_flags = '-w'
  end
  
  s.vendored_libraries = 'mac/build/universal/lib/*.a'
  s.library = 'z', 'iconv', 'xml2', 'bz2', 'c++'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'AudioUnit', 'Cocoa', 'OpenGL', 'CoreMedia', 'CoreVideo', 'VideoToolbox', 'GLKit'
end
