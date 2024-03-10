/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal vertex and fragment shaders.
*/

#include <metal_stdlib>

using namespace metal;

#include "AAPLShaderTypes.h"

#pragma mark -

#pragma mark - Shaders for simple pipeline used to render triangle to renderable texture

// Vertex shader outputs and fragment shader inputs for simple pipeline
struct SimplePipelineRasterizerData
{
    float4 position [[position]];
    float4 color;
    float2 pos;
};

// Vertex shader which passes position and color through to rasterizer.
vertex SimplePipelineRasterizerData
simpleVertexShader(const uint vertexID [[ vertex_id ]],
                   const device AAPLSimpleVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]])
{
    SimplePipelineRasterizerData out;

    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = vertices[vertexID].position.xy;

    out.color = vertices[vertexID].color;
    out.pos = vertices[vertexID].position.xy;
    
    return out;
}

// Fragment shader that just outputs color passed from rasterizer.
fragment float4 simpleFragmentShader(SimplePipelineRasterizerData in [[stage_in]])
{
    return in.color;
}

fragment float4 negativeFragmentShader(SimplePipelineRasterizerData in [[stage_in]])
{
    return 1-in.color;
}

#pragma mark -

#pragma mark Shaders for pipeline used texture from renderable texture when rendering to the drawable.

// Vertex shader outputs and fragment shader inputs for texturing pipeline.
struct TexturePipelineRasterizerData
{
    float4 position [[position]];
    float2 texcoord;
};



// Vertex shader which adjusts positions by an aspect ratio and passes texture
// coordinates through to the rasterizer.
vertex TexturePipelineRasterizerData
textureVertexShader(const uint vertexID [[ vertex_id ]],
                    const device AAPLTextureVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]],
                    constant float &aspectRatio [[ buffer(AAPLVertexInputIndexAspectRatio) ]])
{
    TexturePipelineRasterizerData out;

    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);

    out.position.x = vertices[vertexID].position.x;// * aspectRatio;
    out.position.y = vertices[vertexID].position.y;

    out.texcoord = vertices[vertexID].texcoord;

    return out;
}

#pragma mark -
#pragma mark Gauss shaders

// Gauss blur shaders
//fragment float4 textureFirstGaussShader(TexturePipelineRasterizerData in      [[stage_in]],
//                                      texture2d<float>              texture [[texture(0)]])
//{
//    sampler simpleSampler(mip_filter::linear,
//                          mag_filter::linear,
//                          min_filter::linear,
//                          address::mirrored_repeat);
//
//    // Sample data from the texture.
//    float4 colorSample;
//
//    float4 color = float4(0.0);
//    float sigma = 10.0, radius = 3.0 * sigma, weightSum = 0.0, x = 0.0;
//    
//    for (int y = -radius; y <= radius; y++) {
//        float2 offset = float2(y, x) / float2(texture.get_height(), texture.get_width());
//        float weight = exp(-(y * y) / (2.0 * sigma * sigma));
//        color += texture.sample(simpleSampler, in.texcoord.xy + offset) * weight;
//        weightSum += weight;
//    }
//    
//    colorSample = color / weightSum;
//
//    return colorSample;
//}
//
//fragment float4 textureSecondGaussShader(TexturePipelineRasterizerData in      [[stage_in]],
//                                      texture2d<float>              texture [[texture(1)]])
//{
//    sampler simpleSampler(mip_filter::linear,
//                          mag_filter::linear,
//                          min_filter::linear,
//                          address::mirrored_repeat);
//    
//    // Sample data from the texture.
//    float4 colorSample;
//    
//    float4 color = float4(0.0);
//    float sigma = 10.0, radius = 3.0 * sigma, weightSum = 0.0, y = 0.0;
//    
//    for (int x = -radius; x <= radius; x++) {
//        float2 offset = float2(y, x) / float2(texture.get_height(), texture.get_width());
//        float weight = exp(-(x * x) / (2.0 * sigma * sigma));
//        color += texture.sample(simpleSampler, in.texcoord.xy + offset) * weight;
//        weightSum += weight;
//    }
//    
//    colorSample = color / weightSum;
//    
//    return colorSample;
//}

#pragma mark -
#pragma mark Kawase shaders

fragment float4 textureKawaseShader(TexturePipelineRasterizerData in [[stage_in]],
                                    texture2d<float> texture [[texture(1)]],
                                    constant float &kawaseIter [[buffer(kawaseIterator)]]) {
    
    sampler simpleSampler(mip_filter::linear,
                          mag_filter::linear,
                          min_filter::linear,
                          address::mirrored_repeat);
    
    float3 colorSample;
    float2 pixel = 1. / float2(texture.get_width(), texture.get_height());
    float3 col = float3(0.0);
        
    col += texture.sample(simpleSampler, in.texcoord.xy + (kawaseIter + 0.5) * float2(pixel.x, -pixel.y)).rgb;
    col += texture.sample(simpleSampler, in.texcoord.xy + (kawaseIter + 0.5) * float2(-pixel.x, pixel.y)).rgb;
    col += texture.sample(simpleSampler, in.texcoord.xy + (kawaseIter + 0.5) * float2(-pixel.x, -pixel.y)).rgb;
    col += texture.sample(simpleSampler, in.texcoord.xy + (kawaseIter + 0.5) * float2(pixel.x, pixel.y)).rgb;
        
    colorSample = col / 4.;
    
    return float4(colorSample, 1.0);
}

#pragma mark -
#pragma mark Render texture shader

fragment float4 textureRender(TexturePipelineRasterizerData in [[stage_in]],
                                    texture2d<float> texture [[texture(0)]]){
 
    sampler simpleSampler;
    
    float4 colorSample = texture.sample(simpleSampler, in.texcoord);
    return colorSample;
}
