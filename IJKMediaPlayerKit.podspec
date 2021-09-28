#
# Be sure to run `pod lib lint MRVTPKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MRVTPKit'
  s.version          = '0.4.2'
  s.summary          = 'extract pictures from video.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/debugly/MRVideoToPicture'
  s.license          = { :type => 'MIT', :text => 'LICENSE' }
  s.author           = { 'MattReach' => 'qianlongxu@gmail.com' }
  s.source           = { :git => 'https://github.com/debugly/MRVideoToPicture.git', :tag => s.version.to_s }

  s.osx.deployment_target = '10.11'
  
  s.pod_target_xcconfig = {
    'ALWAYS_SEARCH_USER_PATHS' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '${PODS_TARGET_SRCROOT}/MRVTPKit/ffmpeg4.3.1/include']
    }

  s.subspec 'common' do |ss|
    ss.source_files = 'MRVTPKit/common/**/*.{h,m}'
    ss.public_header_files = 'MRVTPKit/common/headers/public/*.h','MRVTPKit/common/*.h'
    ss.private_header_files = 'MRVTPKit/common/headers/private/*.h'
  end

  s.subspec 'core' do |ss|
    ss.source_files = 'MRVTPKit/core/*.{h,m}'
  end

  s.subspec 'sample' do |ss|
    ss.source_files = 'MRVTPKit/sample/*.{h,m}'
  end
  
  s.vendored_libraries = 'MRVTPKit/ffmpeg4.3.1/lib/*.a'

  # s.subspec 'libavutil' do |ss|
  #   ss.vendored_libraries = 'MRVTPKit/ffmpeg4.3.1/lib/libavutil.a'
  #   ss.source_files = 'MRVTPKit/ffmpeg4.3.1/include/libavutil/*.h'
  #   ss.private_header_files = 'MRVTPKit/ffmpeg4.3.1/include/libavutil/*.h'
  #   ss.preserve_paths = 'MRVTPKit/ffmpeg4.3.1/include/libavutil'
  #   ss.header_mappings_dir = 'MRVTPKit/ffmpeg4.3.1/include/libavutil'
  # end

  # s.subspec 'libavformat' do |ss|
  #   ss.vendored_libraries = 'MRVTPKit/ffmpeg4.3.1/lib/libavformat.a'
  #   ss.source_files = 'MRVTPKit/ffmpeg4.3.1/include/libavformat/*.h'
  #   ss.private_header_files = 'MRVTPKit/ffmpeg4.3.1/include/libavformat/*.h'
  #   ss.preserve_paths = 'MRVTPKit/ffmpeg4.3.1/include/libavformat'
  #   ss.header_mappings_dir = 'MRVTPKit/ffmpeg4.3.1/include/libavformat'
  # end

  # s.subspec 'libavcodec' do |ss|
  #   ss.vendored_libraries = 'MRVTPKit/ffmpeg4.3.1/lib/libavcodec.a'
  #   ss.source_files = 'MRVTPKit/ffmpeg4.3.1/include/libavcodec/*.h'
  #   ss.private_header_files = 'MRVTPKit/ffmpeg4.3.1/include/libavcodec/*.h'
  #   ss.preserve_paths = 'MRVTPKit/ffmpeg4.3.1/include/libavcodec'
  #   ss.header_mappings_dir = 'MRVTPKit/ffmpeg4.3.1/include/libavcodec'
  # end

  # s.subspec 'libswscale' do |ss|
  #   ss.vendored_libraries = 'MRVTPKit/ffmpeg4.3.1/lib/libswscale.a'
  #   ss.source_files = 'MRVTPKit/ffmpeg4.3.1/include/libswscale/*.h'
  #   ss.private_header_files = 'MRVTPKit/ffmpeg4.3.1/include/libswscale/*.h'
  #   ss.preserve_paths = 'MRVTPKit/ffmpeg4.3.1/include/libswscale'
  #   ss.header_mappings_dir = 'MRVTPKit/ffmpeg4.3.1/include/libswscale'
  # end

  s.library = 'z', 'bz2', 'iconv', 'lzma'
  s.frameworks = 'CoreFoundation', 'CoreVideo', 'VideoToolbox', 'CoreMedia', 'AudioToolbox'#, 'Security'
end
