//
//  ijksdl_gpu_opengl_renderer_macos.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/4/15.
//

#import "ijksdl_gpu_opengl_renderer_macos.h"
#import "ijksdl_gpu_opengl_compiler_macos.h"
#import "ijksdl_gpu_opengl_fbo_macos.h"
#import "ijksdl_gles2.h"
#import "ijksdl_vout_ios_gles2.h"
// Uniform index.
enum
{
    UNIFORM_S_AI,
    DIMENSION_S_AI,
    NUM_UNIFORMS_AI
};

// Attribute index.
enum
{
    ATTRIB_VERTEX_AI,
    ATTRIB_TEXCOORD_AI,
    NUM_ATTRIBUTES_AI
};

@interface IJKSDLOpenGLSubRenderer()
{
    GLint _uniforms[NUM_UNIFORMS_AI];
    GLint _attributers[NUM_ATTRIBUTES_AI];
    
    /// 顶点对象
    GLuint _vbo;
    GLuint _vao;
}

@property (nonatomic) IJKSDLOpenGLCompiler * openglCompiler;
@property (nonatomic) CGRect lastRect;

@end

@implementation IJKSDLOpenGLSubRenderer

- (void)dealloc
{
    glDeleteBuffers(1, &_vbo);
    glDeleteVertexArrays(1, &_vao);
}

#define SDL_STRINGIZE(x)   #x
#define SDL_STRINGIZE2(x)  SDL_STRINGIZE(x)
#define SDL_STRING(x)      @SDL_STRINGIZE2(x)

- (NSString *)commonVSH
{
    return @"#"SDL_STRING(
version 330\n

in vec2 texCoord;
in vec2 position;
out vec2 texCoordVarying;

void main()
{
    gl_Position = vec4(position, 0.0, 1.0);
    texCoordVarying = texCoord;
}
                      );
}

- (NSString *)fsh
{
    return @"#"SDL_STRING(
version 330\n

uniform sampler2DRect SamplerS;
uniform vec2 textureDimensionS;
in vec2 texCoordVarying;
out vec4 fragColor;

void main()
{
    vec2 texCoord = texCoordVarying * textureDimensionS;
    fragColor = texture(SamplerS, texCoord);
}

                      );
}

- (void)setupOpenGLProgramIfNeed
{
    if (!self.openglCompiler) {
        self.openglCompiler = [[IJKSDLOpenGLCompiler alloc] initWithvsh:[self commonVSH] fsh:[self fsh]];
        
        if ([self.openglCompiler compileIfNeed]) {
            // Get uniform locations.
            _uniforms[UNIFORM_S_AI]   = [self.openglCompiler getUniformLocation:"SamplerS"];
            _uniforms[DIMENSION_S_AI] = [self.openglCompiler getUniformLocation:"textureDimensionS"];
            
            _attributers[ATTRIB_VERTEX_AI]   = [self.openglCompiler getAttribLocation:"position"];
            _attributers[ATTRIB_TEXCOORD_AI] = [self.openglCompiler getAttribLocation:"texCoord"];
            
            glGenVertexArrays(1, &_vao);
            // 创建顶点缓存对象
            glGenBuffers(1, &_vbo);
        }
    }
    [self.openglCompiler active];
}

- (void)updateSubtitleVertexIfNeed:(CGRect)rect
{
    if (CGRectEqualToRect(self.lastRect, rect)) {
        return;
    }
    
    self.lastRect = rect;
    
    float x = rect.origin.x;
    float y = rect.origin.y;
    float w = rect.size.width;
    float h = rect.size.height;
    /*
     triangle strip
       ^+
     V3|V4
     --|--->+
     V1|V2
     -->V1V2V3
     -->V2V3V4
     */
    
    y *= -1;
    GLfloat quadData [] = {
        x,     y,
        x + w, y,
        x, y + h,
        x + w, y + h,
        //Texture Postition;这里纹理坐标和显示的时候不一样，保证画面方向是正常的，而不是倒立的
        0, 0,
        1, 0,
        0, 1,
        1, 1,
    };
    
    // 绑定顶点缓存对象到当前的顶点位置,之后对GL_ARRAY_BUFFER的操作即是对_VBO的操作
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    // 将CPU数据发送到GPU,数据类型GL_ARRAY_BUFFER
    // GL_STATIC_DRAW 表示数据不会被修改,将其放置在GPU显存的更合适的位置,增加其读取速度
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadData), quadData, GL_DYNAMIC_DRAW);
    
    // 更新顶点数据
    glBindVertexArray(_vao);
    glEnableVertexAttribArray(_attributers[ATTRIB_VERTEX_AI]);
    glEnableVertexAttribArray(_attributers[ATTRIB_TEXCOORD_AI]);
    
    // 指定顶点着色器位置为0的参数的数据读取方式与数据类型
    // 第一个参数: 参数位置
    // 第二个参数: 一次读取数据
    // 第三个参数: 数据类型
    // 第四个参数: 是否归一化数据
    // 第五个参数: 间隔多少个数据读取下一次数据
    // 第六个参数: 指定读取第一个数据在顶点数据中的偏移量
    glVertexAttribPointer(_attributers[ATTRIB_VERTEX_AI], 2, GL_FLOAT, GL_FALSE, 0, (void*)0);
    IJK_GLES2_checkError_TRACE("glVertexAttribPointer(av4_position)");
    // texture coord attribute
    glVertexAttribPointer(_attributers[ATTRIB_TEXCOORD_AI], 2, GL_FLOAT, GL_FALSE, 0, (void*)(8 * sizeof(float)));
    IJK_GLES2_checkError_TRACE("glVertexAttribPointer(av2_texcoord)");
}

- (BOOL)uploadSubtitleTexture:(id<IJKSDLSubtitleTextureWrapper>)subTexture
{
    //设置采样器位置，保证了每个uniform采样器对应着正确的纹理单元
    glUniform1i(_uniforms[UNIFORM_S_AI], 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_RECTANGLE, [subTexture texture]);
    glUniform2f(_uniforms[DIMENSION_S_AI], subTexture.w, subTexture.h);
    
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindVertexArray(_vao);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindTexture(GL_TEXTURE_RECTANGLE, 0);
    glBindVertexArray(0);
    
    IJK_GLES2_checkError("subtitle renderer draw");
    return YES;
}

- (void)clean
{
    glClearColor(0.0,0.0,0.0,0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_DEPTH_TEST);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
}

- (void)bindFBO:(IJKSDLOpenGLFBO *)fbo
{
    // Bind the FBO
    [fbo bind];
    CGSize viewport = [fbo size];
    glViewport(0, 0, viewport.width, viewport.height);
}

- (void)renderTexture:(id<IJKSDLSubtitleTextureWrapper>)subTexture
{
    IJK_GLES2_checkError("render subtitle texture");
    [self uploadSubtitleTexture:subTexture];
}

@end
