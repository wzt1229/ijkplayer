## ass 字幕渲染

以下是解决 ass字幕渲染时颜色存在偏差问题的备忘。

### 颜色混合原理

将要画上去的颜色称为“源颜色”，把原来的颜色称为“目标颜色”；
视频画面就是目标颜色，字幕就是源颜色。

定义如下：

```
源颜色   (Rs,Gs,Bs,As)，源因子  (Sr,Sg,Sb,Sa)
目标颜色 (Rd,Gd,Bd,Ad)，目标因子 (Dr,Dg,Db,Da)
颜色混合基础公式：
(Rs*Sr+Rd*Dr, Gs*Sg+Gd*Dg, Bs*Sb+Bd*Db, As*Sa+Ad*Da)
```

令：

```
Sr=Sg=Sb=Sa
Dr=Dg=Db=Da
```

则源公式简化为：

```
(Rs*Sa+Rd*Da, Gs*Sa+Gd*Da, Bs*Sa+Bd*Da, As*Sa+Ad*Da)
```

再令 `Da = 1-Sa` 可推导出：

`(Rs*Sa+Rd*(1-Sa), Gs*Sa+Gd**(1-Sa), Bs*Sa+Bd**(1-Sa), As*Sa+Ad**(1-Sa))`

可根据这个公式编写 ass layer 合成的逻辑:

```
static void draw_ass_rgba(unsigned char *src, int src_w, int src_h,
                          int src_stride, unsigned char *dst, size_t dst_stride,
                          int dst_x, int dst_y, uint32_t color)
{
    const unsigned int sr = (color >> 24) & 0xff;
    const unsigned int sg = (color >> 16) & 0xff;
    const unsigned int sb = (color >>  8) & 0xff;
    const unsigned int _sa = 0xff - (color & 0xff);

    #define COLOR_BLEND(_sa,_sc,_dc) ((_sc * _sa + _dc * (65025 - _sa)) >> 16 & 0xFF)
    
    for (int y = 0; y < src_h; y++) {
        uint32_t *dstrow = (uint32_t *) dst;
        for (int x = 0; x < src_w; x++) {
            const uint32_t sa = _sa * src[x];
            
            uint32_t dstpix = dstrow[x];
            uint32_t dstr =  dstpix        & 0xFF;
            uint32_t dstg = (dstpix >>  8) & 0xFF;
            uint32_t dstb = (dstpix >> 16) & 0xFF;
            uint32_t dsta = (dstpix >> 24) & 0xFF;
            
            dstr = COLOR_BLEND(sa, sr, dstr);
            dstg = COLOR_BLEND(sa, sg, dstg);
            dstb = COLOR_BLEND(sa, sb, dstb);
            dsta = COLOR_BLEND(sa, 255, dsta);
            
            dstrow[x] = dstr | (dstg << 8) | (dstb << 16) | (dsta << 24);
        }
        dst += dst_stride;
        src += src_stride;
    }
    #undef COLOR_BLEND
}

static void blend_single(FFSubtitleBuffer * frame, ASS_Image *img, int layer)
{
    if (img->w == 0 || img->h == 0)
        return;
    //printf("blend %d rect:{%d,%d}{%d,%d}\n", layer, img->dst_x, img->dst_y, img->w, img->h);
    unsigned char *dst = frame->data;
    dst += img->dst_y * frame->stride + img->dst_x * 4;
    draw_ass_rgba(img->bitmap, img->w, img->h, img->stride, dst, frame->stride, img->dst_x, img->dst_y, img->color);
}

static void blend(FFSubtitleBuffer * frame, ASS_Image *img)
{
    int cnt = 0;
    while (img) {
        ++cnt;
        blend_single(frame, img, cnt);
        img = img->next;
    }
}
```

以上是 ass image 混合到一张大的 rgba bitmap 的过程。

### 渲染 rgba bitmap

字幕的渲染和视频是分开的，分别有一套纹理上传和渲染的过程，然后做混合。这是由于在集成 libass 之前字幕功能就已经实现了，通过 Core Graphic API 将 文本转成一张刚好装下内容的图片，而 ass 的渲染逻辑则是将多层透明通道的图层混合到一张和视频大小一样的大图上。

此处省去纹理上传的相关逻辑。接入 ass 后渲染总是不对，于是将渲染前的 rgba 保存成本地图片查看颜色是正常的，最终定位到是 OpenGl blend 方式的问题！



老版本的 OpenGL 不支持对每个颜色分量单独设置混合因子，而是所有分量统一使用一个因子，实际上使用的就是上面简化后的公式，
glBlendFunc 方法的第一个参数是上面公式的 Sa 参数，第二个参数是上面公式的 Da 参数。

OpenGL 里可用的常量：

```
GL_ZERO： 表示使用0.0作为因子，实际上相当于不使用这种颜色参与混合运算。
GL_ONE： 表示使用1.0作为因子，实际上相当于完全的使用了这种颜色参与混合运算。
GL_SRC_ALPHA：表示使用源颜色的alpha值来作为因子。
GL_DST_ALPHA：表示使用目标颜色的alpha值来作为因子。
GL_ONE_MINUS_SRC_ALPHA：表示用1.0减去源颜色的alpha值来作为因子。
GL_ONE_MINUS_DST_ALPHA：表示用1.0减去目标颜色的alpha值来作为因子。
```

解决 ass 字幕渲染问题，需要设置正确的混合模式：

glEnable(GL_BLEND);
//之前使用的是 GL_SRC_ALPHA，而不是 GL_ONE
glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

改成 GL_ONE 之后，原本的 Core Graphic API 生成的图片仍旧正常显示。

## end

到此问题解决，你能想明白为什么 ass 字幕的图片需要使用 GL_ONE 这个源因子吗？
