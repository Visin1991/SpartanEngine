/*
Copyright(c) 2016-2020 Panos Karabelas

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

//= INCLUDES ==================
#include "Common.hlsl"
#include "ParallaxMapping.hlsl"
//=============================

//= TEXTURES ===========================
Texture2D texAlbedo 	: register (t0);
Texture2D texRoughness 	: register (t1);
Texture2D texMetallic 	: register (t2);
Texture2D texNormal 	: register (t3);
Texture2D texHeight 	: register (t4);
Texture2D texOcclusion 	: register (t5);
Texture2D texEmission 	: register (t6);
Texture2D texMask 		: register (t7);
//======================================

struct PixelInputType
{
    float4 position 			: SV_POSITION;
    float2 uv 					: TEXCOORD;
    float3 normal 				: NORMAL;
    float3 tangent 				: TANGENT;
	float4 position_ss_current	: SCREEN_POS;
	float4 position_ss_previous : SCREEN_POS_PREVIOUS;
};

struct PixelOutputType
{
	float4 albedo	: SV_Target0;
	float4 normal	: SV_Target1;
	float4 material	: SV_Target2;
	float2 velocity	: SV_Target3;
};

PixelInputType mainVS(Vertex_PosUvNorTan input)
{
    PixelInputType output;
    
    input.position.w 			= 1.0f;		
	output.position_ss_previous = mul(input.position, g_object_wvp_previous);
    output.position 			= mul(input.position, g_object_transform);
    output.position   		    = mul(output.position, g_viewProjection);
    output.position_ss_current 	= output.position;
	output.normal 				= normalize(mul(input.normal, (float3x3)g_object_transform)).xyz;	
	output.tangent 				= normalize(mul(input.tangent, (float3x3)g_object_transform)).xyz;
    output.uv 					= input.uv;
	
	return output;
}

PixelOutputType mainPS(PixelInputType input)
{
	PixelOutputType g_buffer;

	float2 texCoords 		= float2(input.uv.x * materialTiling.x + materialOffset.x, input.uv.y * materialTiling.y + materialOffset.y);
	float4 albedo			= materialAlbedoColor;
	float roughness 		= materialRoughness;
	float metallic 			= materialMetallic;
	float3 normal			= input.normal.xyz;
	float normal_intensity	= clamp(materialNormalStrength, 0.012f, materialNormalStrength);
	float emission			= 0.0f;
	float occlusion			= 1.0f;	
	
	//= VELOCITY ================================================================================
	float2 position_current 	= (input.position_ss_current.xy / input.position_ss_current.w);
	float2 position_previous 	= (input.position_ss_previous.xy / input.position_ss_previous.w);
	float2 position_delta		= position_current - position_previous;
    float2 velocity 			= (position_delta - g_taa_jitter_offset) * float2(0.5f, -0.5f);
	//===========================================================================================

	// Make TBN
	float3x3 TBN = makeTBN(input.normal, input.tangent);

	#if HEIGHT_MAP
		// Parallax Mapping
		float height_scale 		= materialHeight * 0.04f;
		float3 camera_to_pixel 	= normalize(g_camera_position - input.position.xyz);
		texCoords 				= ParallaxMapping(texHeight, sampler_anisotropic_wrap, texCoords, camera_to_pixel, TBN, height_scale);
	#endif
	
	float mask_threshold = 0.6f;
	
	#if MASK_MAP
		float3 maskSample = texMask.Sample(sampler_anisotropic_wrap, texCoords).rgb;
		if (maskSample.r <= mask_threshold && maskSample.g <= mask_threshold && maskSample.b <= mask_threshold)
			discard;
	#endif

	#if ALBEDO_MAP
		float4 albedo_sample = texAlbedo.Sample(sampler_anisotropic_wrap, texCoords);	
		if (albedo_sample.a <= mask_threshold)
			discard;

        albedo_sample.rgb = degamma(albedo_sample.rgb);
		albedo *= albedo_sample;
	#endif
	
	#if ROUGHNESS_MAP
		roughness *= texRoughness.Sample(sampler_anisotropic_wrap, texCoords).r;
	#endif
	
	#if METALLIC_MAP
		metallic *= texMetallic.Sample(sampler_anisotropic_wrap, texCoords).r;
	#endif
	
	#if NORMAL_MAP
		// Get tangent space normal and apply intensity
		float3 tangent_normal 	= normalize(unpack(texNormal.Sample(sampler_anisotropic_wrap, texCoords).rgb));
		tangent_normal.xy 		*= saturate(normal_intensity);
		normal 					= normalize(mul(tangent_normal, TBN).xyz); // Transform to world space
	#endif

	#if OCCLUSION_MAP
		occlusion = texOcclusion.Sample(sampler_anisotropic_wrap, texCoords).r;
	#endif
	
	#if EMISSION_MAP
		emission = texEmission.Sample(sampler_anisotropic_wrap, texCoords).r;
	#endif

	// Write to G-Buffer
	g_buffer.albedo		= albedo;
	g_buffer.normal 	= float4(normal_encode(normal), occlusion);
	g_buffer.material	= float4(roughness, metallic, emission, 1.0f);
	g_buffer.velocity	= velocity;

    return g_buffer;
}
