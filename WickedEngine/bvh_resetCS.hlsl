#include "globals.hlsli"
#include "ShaderInterop_BVH.h"

// This shader resets the BVH structure

RWSTRUCTUREDBUFFER(bvhNodeBuffer, BVHNode, 0);
RWSTRUCTUREDBUFFER(bvhAABBBuffer, BVHAABB, 1);

[numthreads(1, 1, 1)]
void main( uint3 DTid : SV_DispatchThreadID )
{
	// Initialize root as leaf node (safety):
	bvhNodeBuffer[0].ParentIndex = 0;
	bvhNodeBuffer[0].LeftChildIndex = 0;
	bvhNodeBuffer[0].RightChildIndex = 0;

	// Write root level AABB:
	bvhAABBBuffer[0].min = g_xFrame_WorldBoundsMin;
	bvhAABBBuffer[0].max = g_xFrame_WorldBoundsMax;
}
