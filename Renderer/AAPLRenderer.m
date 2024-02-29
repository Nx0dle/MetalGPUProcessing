/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation for a renderer class that performs Metal setup and
 per-frame rendering.
*/

@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLShaderTypes.h"

// The main class performing the rendering.
@implementation AAPLRenderer
{
    // Texture to render to and then sample from.
    id<MTLTexture> _renderTargetTexture;
    id<MTLTexture> _renderTargetTexture2;
    id<MTLTexture> _textureFromFile;

    // Render pass descriptor to draw to the texture
    MTLRenderPassDescriptor* _renderToTextureRenderPassDescriptor_FBO;
    MTLRenderPassDescriptor* _renderToTextureRenderPassDescriptorFirstPass;
    MTLRenderPassDescriptor* _renderToTextureRenderPassDescriptorSecondPass;
    
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _renderToTextureRenderPipeline;
    id<MTLRenderPipelineState> _renderToTextureShaderRenderPipeline;

    // A pipeline object to render to the screen.
    id<MTLRenderPipelineState> _drawableRenderPipeline;
    

    // Ratio of width to height to scale positions in the vertex shader.
    float _aspectRatio;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;
    
    id<MTLTexture> _colorMap;
}

#pragma mark -
#pragma mark Settings and pipeline

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        mtkView.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);

        _commandQueue = [_device newCommandQueue];

        // Set up a texture for rendering to and sampling from
        MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
        texDescriptor.textureType = MTLTextureType2D;
        texDescriptor.width = 512;
        texDescriptor.height = 512;
        texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
        texDescriptor.usage = MTLTextureUsageRenderTarget |
                              MTLTextureUsageShaderRead |
                              MTLTextureUsageShaderWrite;

        _renderTargetTexture = [_device newTextureWithDescriptor:texDescriptor];
        _renderTargetTexture2 = [_device newTextureWithDescriptor:texDescriptor];

        // Set up a render pass descriptor for the render pass to render into
        // _renderTargetTexture.

        _renderToTextureRenderPassDescriptor_FBO = [MTLRenderPassDescriptor new];
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].texture = _renderTargetTexture;
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        
        _renderToTextureRenderPassDescriptorFirstPass = [MTLRenderPassDescriptor new];
        _renderToTextureRenderPassDescriptorFirstPass.colorAttachments[0].texture = _renderTargetTexture;
        _renderToTextureRenderPassDescriptorFirstPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _renderToTextureRenderPassDescriptorFirstPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        _renderToTextureRenderPassDescriptorSecondPass = [MTLRenderPassDescriptor new];
        _renderToTextureRenderPassDescriptorSecondPass.colorAttachments[0].texture = _renderTargetTexture2;
        _renderToTextureRenderPassDescriptorSecondPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _renderToTextureRenderPassDescriptorSecondPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        

        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Drawable Render Pipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureSecondGaussShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;
        _drawableRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_drawableRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);

        
        pipelineStateDescriptor.label = @"Offscreen Render texture gen pipeline";
        pipelineStateDescriptor.sampleCount = 1;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"simpleVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"negativeFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture.pixelFormat;
        _renderToTextureRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_renderToTextureRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);
        
        
        pipelineStateDescriptor.label = @"Offscreen Render texture shader pipeline";
        pipelineStateDescriptor.sampleCount = 1;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureFirstGaussShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture2.pixelFormat;
        _renderToTextureShaderRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_renderToTextureShaderRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);
        
        
//        pipelineStateDescriptor.label = @"Offscreen Render Pipeline";
//        pipelineStateDescriptor.sampleCount = 1;
//        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"simpleVertexShader"];
//        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"simpleFragmentShader"];
//        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture.pixelFormat;
//        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
//        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
//        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
//        
//        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
//        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
//        
//        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceColor;
//        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceColor;
//        _renderToTextureRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
//        NSAssert(_renderToTextureRenderPipeline, @"Failed to create pipeline state to render to texture: %@", error);
    }
    
    {
            NSURL *url = [NSURL fileURLWithPath:@"/Users/motionvfx/Documents/chessboard.jpeg"];
            MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:_device];
            
            NSDictionary *options =
            @{
                MTKTextureLoaderOptionSRGB:                 @(false),
                MTKTextureLoaderOptionGenerateMipmaps:      @(false),
                MTKTextureLoaderOptionTextureUsage:         @(MTLTextureUsageShaderRead),
                MTKTextureLoaderOptionTextureStorageMode:   @(MTLStorageModePrivate)
            };
            
            _textureFromFile = [loader newTextureWithContentsOfURL:url options:options error:nil];
            if(!_textureFromFile)
            {
                NSLog(@"Failed to create the texture from %@", url.absoluteString);
                return nil;
            }
        }
        
    
    return self;
}

#pragma mark - Render sth to gen texture

// Handles view orientation and size changes.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    _aspectRatio =  (float)size.height / (float)size.width;
}

// Handles view rendering for a new frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Command Buffer";
    
    {
        static const AAPLSimpleVertex triVertices[] =
        {
            // Positions     ,  Colors
            { {  1.0,   1.0 },  { 1.0, 0.0, 0.0, 1.0 } },
            { {  1.0,  -1.0 },  { 1.0, 1.0, 1.0, 1.0 } },
            { { -1.0,  -1.0 },  { 0.0, 0.0, 1.0, 1.0 } },
            { { -1.0,  -1.0 },  { 1.0, 0.0, 0.0, 1.0 } },
            { { -1.0,   1.0 },  { 1.0, 1.0, 1.0, 1.0 } },
            { {  1.0,   1.0 },  { 0.0, 0.0, 1.0, 1.0 } },
            
        };
        
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptor_FBO];
        renderEncoder.label = @"Offscreen Render Pass";
        [renderEncoder setRenderPipelineState:_renderToTextureRenderPipeline];
        
        [renderEncoder setVertexBytes:&triVertices
                               length:sizeof(triVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];
        
        // End encoding commands for this render pass.
        [renderEncoder endEncoding];
    }
    
    {
        static const AAPLSimpleVertex triVertices[] =
        {
            // Positions     ,  Colors
            { {  0.4,   0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            { {  0.4,  -0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            { { -0.4,  -0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            { { -0.4,  -0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            { { -0.4,   0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            { {  0.4,   0.4 },  { 1.0, 1.0, 1.0, 1.0 } },
            
        };
        
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptorFirstPass];
        renderEncoder.label = @"Offscreen Render Pass2";
        [renderEncoder setRenderPipelineState:_renderToTextureRenderPipeline];
        
        [renderEncoder setVertexBytes:&triVertices
                               length:sizeof(triVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];
        
        // End encoding commands for this render pass.
        [renderEncoder endEncoding];
        
    }
    
    static const AAPLTextureVertex quadVertices[] =
    {
        // Positions     , Texture coordinates
        { {  1.0,  -1.0 },  { 1.0, 1.0 } },
        { { -1.0,  -1.0 },  { 0.0, 1.0 } },
        { { -1.0,   1.0 },  { 0.0, 0.0 } },

        { {  1.0,  -1.0 },  { 1.0, 1.0 } },
        { { -1.0,   1.0 },  { 0.0, 0.0 } },
        { {  1.0,   1.0 },  { 1.0, 0.0 } },
    };
    
    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptorSecondPass];
        renderEncoder.label = @"Offscreen render shader pass";
        [renderEncoder setRenderPipelineState:_renderToTextureShaderRenderPipeline];
        [renderEncoder setFragmentTexture:_renderTargetTexture atIndex:0];
        
        [renderEncoder setVertexBytes:&quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];

        [renderEncoder endEncoding];
    }

#pragma mark -
#pragma mark Draw texture to view
    
    MTLRenderPassDescriptor *drawableRenderPassDescriptor = view.currentRenderPassDescriptor;
    if(drawableRenderPassDescriptor != nil)
    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:drawableRenderPassDescriptor];
        renderEncoder.label = @"Drawable Render Pass shader final";

        [renderEncoder setRenderPipelineState:_drawableRenderPipeline];

        [renderEncoder setVertexBytes:&quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];

        [renderEncoder setVertexBytes:&_aspectRatio
                               length:sizeof(_aspectRatio)
                              atIndex:AAPLVertexInputIndexAspectRatio];

        
        // Set the offscreen texture as the source texture.
        [renderEncoder setFragmentTexture:_renderTargetTexture2 atIndex:1];

        // Draw quad with rendered texture.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

@end
