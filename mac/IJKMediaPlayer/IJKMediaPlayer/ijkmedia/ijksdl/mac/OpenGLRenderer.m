/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The OpenGLRenderer class creates and draws objects.
  Most of the code is OS independent.
 */

#import "OpenGLRenderer.h"
#include "glUtil.h"
#import "ProgramTools.h"

#define RC_GLES_STRINGIZE(x) #x
/*
 GLSL(OpenGL Shader Language): 一种类似于C语言的专门为GPU设计的语言，它可以放在GPU里面被并行运行。
 OpenGL的着色器有.fsh和.vsh两个文件。这两个文件在被编译和链接后就可以产生可执行程序与GPU交互。.vsh 是Vertex Shader（顶点着色器），用于顶点计算，可以理解控制顶点的位置，在这个文件中我们通常会传入当前顶点的位置，和纹理的坐标。.fsh 是Fragment Shader（片元着色器），在这里面我可以对于每一个像素点进行重新计算。
 
 变量类型：
 
 attribute：外部传入vsh文件的变量，每一个顶点都会有这两个属性。变化率高，用于定义每个点。
 varying：用于 vsh和fsh之间相互传递的参数。
 uniform：外部传入vsh文件的变量。变化率较低，对于可能在整个渲染过程没有改变，只是个常量。
 上文代码中使用了以下数据类型：
 vec2：包含了2个浮点数的向量
 vec3：包含了3个浮点数的向量
 vec4：包含了4个浮点数的向量
 sampler1D：1D纹理着色器
 sampler2D：2D纹理着色器
 sampler3D：3D纹理着色器
 mat2：2*2维矩阵
 mat3：3*3维矩阵
 mat4：4*4维矩阵
 
 ---------------------
 作者：雷霄骅
 来源：CSDN
 原文：https://blog.csdn.net/leixiaohua1020/article/details/40379845
 版权声明：本文为博主原创文章，转载请附上博文链接！
 */


//标准顶点坐标
static const char FLAT_VSH_STR[] = RC_GLES_STRINGIZE(
            attribute vec4 a_Position;
            attribute vec2 a_TexCoordinate;
            varying vec2 v_TexCoordinate;
            void main()
            {
                v_TexCoordinate = a_TexCoordinate;
                gl_Position = a_Position;
            }
                                                    );


static const char FLAT_FSH_YUV420P_STR[] = RC_GLES_STRINGIZE(
                                                             uniform sampler2D sample0;
                                                             uniform sampler2D sample1;
                                                             uniform sampler2D sample2;
                                                             varying vec2 v_TexCoordinate;
                                                             void main() {
                                                                 vec3 yuv;
                                                                 vec3 rgb;
                                                                 yuv.x = texture2D(sample0, v_TexCoordinate).r;
                                                                 yuv.y = texture2D(sample1, v_TexCoordinate).r - 0.5;
                                                                 yuv.z = texture2D(sample2, v_TexCoordinate).r - 0.5;
                                                                 rgb = mat3( 1,       1,         1,
                                                                            0,       -0.39465,  2.03211,
                                                                            1.13983, -0.58060,  0) * yuv;
                                                                 gl_FragColor = vec4(rgb, 1);
                                                             }
                                                             );

//static const char FLAT_FSH_YUV420P_STR[] = RC_GLES_STRINGIZE(
//                                                             uniform sampler2D sample0;
//                                                             uniform sampler2D sample1;
//                                                             uniform sampler2D sample2;
//                                                             const vec3 offset = vec3(-0.0627451017, -0.501960814, -0.501960814);
//                                                             const vec3 Rcoeff = vec3(1.164,  0.000,  1.596);
//                                                             const vec3 Gcoeff = vec3(1.164, -0.391, -0.813);
//                                                             const vec3 Bcoeff = vec3(1.164,  2.018,  0.000);
//                                                             varying vec2 v_TexCoordinate;
//                                                             void main() {
//                                                                 vec3 yuv;
//                                                                 vec3 rgb;
//                                                                 yuv.x = texture2D(sample0, v_TexCoordinate).r;
//                                                                 yuv.y = texture2D(sample1, v_TexCoordinate).g;
//                                                                 yuv.z = texture2D(sample2, v_TexCoordinate).b;
//                                                                 yuv += offset;
//                                                                 rgb.r = dot(yuv, Rcoeff);
//                                                                 rgb.g = dot(yuv, Gcoeff);
//                                                                 rgb.b = dot(yuv, Bcoeff);
//                                                                 gl_FragColor = vec4(rgb, 1.0);
//                                                             }
//                                                             );

static const char FLAT_FSH_NV12_STR[] = RC_GLES_STRINGIZE(
                                                          uniform sampler2D sample0;
                                                          uniform sampler2D sample1;
                                                          const vec3 offset = vec3(-0.0627451017, -0.501960814, -0.501960814);
                                                          const vec3 Rcoeff = vec3(1.164,  0.000,  1.596);
                                                          const vec3 Gcoeff = vec3(1.164, -0.391, -0.813);
                                                          const vec3 Bcoeff = vec3(1.164,  2.018,  0.000);
                                                          varying vec2 v_TexCoordinate;
                                                          void main() {
                                                              vec3 yuv;
                                                              vec3 rgb;
                                                              yuv.x = texture2D(sample0, v_TexCoordinate).r;
                                                              yuv.yz = texture2D(sample1, v_TexCoordinate).ra;
                                                              yuv += offset;
                                                              rgb.r = dot(yuv, Rcoeff);
                                                              rgb.g = dot(yuv, Gcoeff);
                                                              rgb.b = dot(yuv, Bcoeff);
                                                              gl_FragColor = vec4(rgb, 1.0);
                                                          }
                                                          );

@interface OpenGLRenderer ()
{
    GLuint _viewWidth;
    GLuint _viewHeight;
    GLuint textures[3];
    GLuint uniformSamplers[3];
    GLuint aPostionLocation;
    GLuint aTextureCoordLocation;
    GLuint mMVPMatrixHandle;
    GLuint program;
    RcFrame* overLay;
    int index;
    NSLock* renderLock;
}
@end

@implementation OpenGLRenderer


- (void) resizeWithWidth:(GLuint)width AndHeight:(GLuint)height
{
    if(renderLock == nil) {
        renderLock = [[NSLock alloc]init];
    }
	glViewport(0, 0, width, height);

	_viewWidth = width;
	_viewHeight = height;
}

- (void)checkGLError {
    
    GLenum error = glGetError();
    
    switch (error) {
        case GL_INVALID_ENUM:
            NSLog(@"GL Error: Enum argument is out of range \r\n");
            break;
        case GL_INVALID_VALUE:
            NSLog(@"GL Error: Numeric value is out of range \r\n");
            break;
        case GL_INVALID_OPERATION:
            NSLog(@"GL Error: Operation illegal in current state \r\n");
            break;
        case GL_OUT_OF_MEMORY:
            NSLog(@"GL Error: Not enough memory to execute command \r\n");
            break;
        case GL_INVALID_FRAMEBUFFER_OPERATION:
            NSLog(@"GL Error:GL_INVALID_FRAMEBUFFER_OPERATION \r\n");
            break;
        case GL_NO_ERROR:
            break;
        default:
            NSLog(@"Unknown GL Error %d \r\n",error);
            break;
    }
}


- (void) render
{
    glClearColor(0.f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    if(overLay == NULL) {
        return;
    }
    
    if(program == 0) {
        if ([self initShader:overLay->format]) {
            [self initTextures];
            [self checkGLError];
        }
    }
    if(/* DISABLES CODE */ (0)) {
        int ySize = overLay->width * overLay->height;
        static FILE* file = NULL;
        if (!file) {
           file = fopen("/Users/qianlongxu/Desktop/ijk.yuv", "wb+");
        }
        
        fwrite(overLay->data[0], 1, ySize, file);
        fwrite(overLay->data[1], 1, ySize / 4, file);
        fwrite(overLay->data[2], 1, ySize / 4, file);
        fflush(file);
        //fclose(file);
    }
    
    glUseProgram(program);
    
    [renderLock lock];
    const int planes = overLay->planes;
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    int widths[3] = {0};
    int heights[3] = {0};
    int formats[3] = {0};
    switch (overLay->format) {
        case FMT_YUV420P:
//            widths[0] = overLay->linesize[0];
//            widths[1] = widths[2] = (overLay->linesize[0] >> 1);
//            heights[0] = overLay->height;
//            heights[1] = heights[2] = (heights[0] >> 1);
//            formats[0] = formats[1] = formats[2] = GL_LUMINANCE;
            widths[0] = overLay->linesize[0];
            widths[1] = overLay->linesize[1];
            widths[2] = overLay->linesize[2];
            
            heights[0] = overLay->height;
            heights[1] = heights[2] = (heights[0] >> 1);
            formats[0] = formats[1] = formats[2] = GL_LUMINANCE;
            break;
        case FMT_NV12:
            widths[0] = overLay->linesize[0];
            widths[1] = overLay->linesize[0] / 2;
            heights[0] = overLay->height;
            heights[1] = overLay->height / 2;
            formats[0] = GL_LUMINANCE;
            formats[1] = GL_LUMINANCE_ALPHA;
            break;
        default:
            break;
    }
    for (int i = 0; i < planes; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, textures[i]);
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     formats[i],
                     (int) widths[i],
                     (int) heights[i],
                     0,
                     formats[i],
                     GL_UNSIGNED_BYTE,
                     overLay->data[i]);
        glUniform1i(uniformSamplers[i], i);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    [renderLock unlock];
    
    static const GLfloat squareVertices[] = {
        -1.0f,  1.0f,
        -1.0f, -1.0f,
        1.0f,  1.0f,
        1.0f, -1.0f,
    };
    
    static const GLfloat textureCoordinates[] = {
        0.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
    };
    
    glEnableVertexAttribArray(aPostionLocation);
    glVertexAttribPointer(aPostionLocation, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(aTextureCoordLocation);
    glVertexAttribPointer(aTextureCoordLocation, 2, GL_FLOAT, 0, 0, textureCoordinates);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

- (void)initTextures{
    glGenTextures(3, textures);
    for (int i = 0; i < 3; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, textures[i]);
    }
}

- (BOOL)initShader:(RcColorFormat) format{
    ProgramTools* programTools = [[ProgramTools alloc]init];
    program = [programTools compileProgram:FLAT_VSH_STR frag:(format == FMT_YUV420P ? FLAT_FSH_YUV420P_STR : FLAT_FSH_NV12_STR)];
    if (program > 0) {
        glUseProgram(program);
        aPostionLocation = glGetAttribLocation(program, "a_Position");
        aTextureCoordLocation = glGetAttribLocation(program, "a_TexCoordinate");
        uniformSamplers[0] = glGetUniformLocation(program, "sample0");
        uniformSamplers[1] = glGetUniformLocation(program, "sample1");
        uniformSamplers[2] = glGetUniformLocation(program, "sample2");
        mMVPMatrixHandle = glGetUniformLocation(program, "u_MVPMatrix");
        return YES;
    } else {
        //compile shader failed.
        return NO;
    }
}

- (void)setImage:(RcFrame*)cacheOverlay {
    [renderLock lock];
    overLay = cacheOverlay;
    [renderLock unlock];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSLog(@"%s %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    }
    return self;
}

- (void) dealloc
{
	
}

@end
