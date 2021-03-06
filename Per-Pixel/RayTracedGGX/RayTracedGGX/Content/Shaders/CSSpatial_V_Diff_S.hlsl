//--------------------------------------------------------------------------------------
// Copyright (c) XU, Tianchen. All rights reserved.
//--------------------------------------------------------------------------------------

#include "SpatialFilter.hlsli"

//--------------------------------------------------------------------------------------
// Textures
//--------------------------------------------------------------------------------------
RWTexture2D<float4>	g_renderTarget;
Texture2D<float3>	g_txAverage		: register (t1);
Texture2D			g_txDest		: register (t2);
Texture2D			g_txNormal		: register (t3);
Texture2D<float2>	g_txRoughMetal	: register (t4);
//Texture2D<float>	g_txDepth		: register (t5);

groupshared uint4 g_avgMtlNrms[SHARED_MEM_SIZE];
//groupshared float g_depths[SHARED_MEM_SIZE];

void loadSamples(uint2 dTid, uint gTid, uint radius)
{
	const uint offset = radius * 2;
	dTid.y -= radius;

	[unroll]
	for (uint i = 0; i < 2; ++i, dTid.y += offset, gTid += offset)
	{
		const float3 avg = g_txAverage[dTid];
		float4 norm = g_txNormal[dTid];
		const float mtl = g_txRoughMetal[dTid].y;
		//const float depth = g_txDepth[dTid];

		norm.xyz = norm.xyz * 2.0 - 1.0;
		g_avgMtlNrms[gTid] = uint4(pack(float4(avg, mtl)), pack(norm));
		//g_depths[gTid] = depth;
	}

	GroupMemoryBarrierWithGroupSync();
}

[numthreads(1, THREADS_PER_WAVE, 1)]
void main(uint2 DTid : SV_DispatchThreadID, uint2 GTid : SV_GroupThreadID)
{
	const float4 dest = g_txDest[DTid];
	float4 normC = g_txNormal[DTid];
	const bool vis = normC.w > 0.0 && g_txRoughMetal[DTid].y < 1.0;
	if (WaveActiveAllTrue(!vis))
	{
		g_renderTarget[DTid] = dest;
		return;
	}
	const uint radius = RADIUS;
	loadSamples(DTid, GTid.y, radius);
	if (!vis)
	{
		g_renderTarget[DTid] = dest;
		return;
	}

	const float3 src = g_txSource[DTid];
	//const float depthC = g_depths[GTid.y + radius];
	const uint sampleCount = radius * 2 + 1;
	normC.xyz = normC.xyz * 2.0 - 1.0;

	float3 mu = 0.0, m2 = 0.0;
	float wsum = 0.0;

	[unroll]
	for (uint i = 0; i < sampleCount; ++i)
	{
		const uint j = GTid.y + i;
		const float4 avgMtl = unpack(g_avgMtlNrms[j].xy);
		const float4 norm = unpack(g_avgMtlNrms[j].zw);

		const float w = (norm.w > 0.0 && avgMtl.w < 1.0 ? 1.0 : 0.0)
			* NormalWeight(normC.xyz, norm.xyz, SIGMA_N);
			//* Gaussian(depthC, g_depths[j], SIGMA_Z);
		mu += avgMtl.xyz * w;
		wsum += w;
	}

	mu /= wsum;
	const float3 result = mu;
	//const float3 result = Denoise(src, mu, 1.0);

	g_renderTarget[DTid] = float4(dest.xyz + ITM(result), dest.w);
}
