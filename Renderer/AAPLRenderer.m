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
    MTLRenderPassDescriptor* _renderToTextureRenderPassDescriptor_secondPass;
    
    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _renderToTextureShaderRenderPipeline;
    id<MTLRenderPipelineState> _renderToTextureRenderPipeline;

    // A pipeline object to render to the screen.
    id<MTLRenderPipelineState> _drawableRenderPipeline;

    // Ratio of width to height to scale positions in the vertex shader.
    float _aspectRatio;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;
    
    id<MTLTexture> _colorMap;
    
    float kawaseIter;
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
        

        _renderToTextureRenderPassDescriptor_FBO = [MTLRenderPassDescriptor new];
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].texture = _renderTargetTexture;
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        _renderToTextureRenderPassDescriptor_FBO.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        _renderToTextureRenderPassDescriptor_secondPass = [MTLRenderPassDescriptor new];
        _renderToTextureRenderPassDescriptor_secondPass.colorAttachments[0].texture = _renderTargetTexture;
        _renderToTextureRenderPassDescriptor_secondPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
        _renderToTextureRenderPassDescriptor_secondPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        

        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        
        pipelineStateDescriptor.label = @"Offscreen Render texture render pipeline";
        pipelineStateDescriptor.sampleCount = 1;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureRender"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture.pixelFormat;
        _renderToTextureRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_renderToTextureRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);
        
        
        pipelineStateDescriptor.label = @"Offscreen Render texture shader pipeline";
        pipelineStateDescriptor.sampleCount = 1;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureKawaseShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture.pixelFormat;
        _renderToTextureShaderRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_renderToTextureShaderRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);
        
        
        pipelineStateDescriptor.label = @"Drawable Render Pipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureKawaseShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;
        _drawableRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_drawableRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);
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

#pragma mark -
#pragma mark - Render to generate textures

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
    
    // Global coordinates for full screen render
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
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptor_FBO];
        renderEncoder.label = @"Load texture pass";
        [renderEncoder setRenderPipelineState:_renderToTextureRenderPipeline];
        [renderEncoder setFragmentTexture:_textureFromFile 
                                  atIndex:0];
        
        [renderEncoder setVertexBytes:&quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];
        
        [renderEncoder endEncoding];
    }
    
    for (float i = 0; i < 5; i++) {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptor_secondPass];
        renderEncoder.label = @"Offscreen render shader pass";
        [renderEncoder setRenderPipelineState:_renderToTextureShaderRenderPipeline];
        
        [renderEncoder setVertexBytes:&quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder setFragmentBytes:&i
                                 length:sizeof(i)
                                atIndex:kawaseIterator];
        
        [renderEncoder setFragmentTexture:_renderTargetTexture atIndex:1];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];
        
        [renderEncoder endEncoding];
        
        
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
            
            [renderEncoder setFragmentBytes:&i
                                     length:sizeof(i)
                                    atIndex:kawaseIterator];
            
            
            // Set the offscreen texture as the source texture.
            [renderEncoder setFragmentTexture:_renderTargetTexture atIndex:1];
            
            // Draw quad with rendered texture.
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                              vertexStart:0
                              vertexCount:6];
            
            [renderEncoder endEncoding];
            
            
        }
    }

    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

@end
