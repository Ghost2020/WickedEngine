#ifndef _RAY_SCENE_INTERSECT_HF_
#define _RAY_SCENE_INTERSECT_HF_
#include "globals.hlsli"
#include "tracedRenderingHF.hlsli"

#ifndef RAYTRACE_STACKSIZE
#define RAYTRACE_STACKSIZE 32
#endif // RAYTRACE_STACKSIZE

STRUCTUREDBUFFER(materialBuffer, TracedRenderingMaterial, TEXSLOT_ONDEMAND0);
TEXTURE2D(materialTextureAtlas, float4, TEXSLOT_ONDEMAND1);
STRUCTUREDBUFFER(primitiveBuffer, BVHPrimitive, TEXSLOT_ONDEMAND2);
RAWBUFFER(primitiveCounterBuffer, TEXSLOT_ONDEMAND3);
STRUCTUREDBUFFER(primitiveIDBuffer, uint, TEXSLOT_ONDEMAND4);
STRUCTUREDBUFFER(bvhNodeBuffer, BVHNode, TEXSLOT_ONDEMAND5);
STRUCTUREDBUFFER(bvhAABBBuffer, BVHAABB, TEXSLOT_ONDEMAND6);


inline RayHit TraceScene(Ray ray)
{
	RayHit bestHit = CreateRayHit();

	// Using BVH acceleration structure:

	// Emulated stack for tree traversal:
	uint stack[RAYTRACE_STACKSIZE];
	uint stackpos = 0;

	const uint primitiveCount = primitiveCounterBuffer.Load(0);
	const uint leafNodeOffset = primitiveCount - 1;

	// push root node
	stack[stackpos] = 0;
	stackpos++;

	uint exit_condition = 0;
	do {
#ifdef RAYTRACE_EXIT
		if (exit_condition > RAYTRACE_EXIT)
			break;
		exit_condition++;
#endif // RAYTRACE_EXIT

		// pop untraversed node
		stackpos--;
		const uint nodeIndex = stack[stackpos];

		BVHNode node = bvhNodeBuffer[nodeIndex];
		BVHAABB box = bvhAABBBuffer[nodeIndex];

		if (IntersectBox(ray, box))
		{
			//if (node.LeftChildIndex == 0 && node.RightChildIndex == 0)
			if (nodeIndex >= primitiveCount - 1)
			{
				// Leaf node
				const uint nodeToPrimitiveID = nodeIndex - leafNodeOffset;
				const uint primitiveID = primitiveIDBuffer[nodeToPrimitiveID];
				IntersectTriangle(ray, bestHit, primitiveBuffer[primitiveID], primitiveID);
			}
			else
			{
				// Internal node
				if (stackpos < RAYTRACE_STACKSIZE - 1)
				{
					// push left child
					stack[stackpos] = node.LeftChildIndex;
					stackpos++;
					// push right child
					stack[stackpos] = node.RightChildIndex;
					stackpos++;
				}
				else
				{
					// stack overflow, terminate
					break;
				}
			}

		}

	} while (stackpos > 0);


	return bestHit;
}

inline bool TraceSceneANY(Ray ray, float maxDistance)
{
	bool shadow = false;

	// Using BVH acceleration structure:

	// Emulated stack for tree traversal:
	uint stack[RAYTRACE_STACKSIZE];
	uint stackpos = 0;

	const uint primitiveCount = primitiveCounterBuffer.Load(0);
	const uint leafNodeOffset = primitiveCount - 1;

	// push root node
	stack[stackpos] = 0;
	stackpos++;

	uint exit_condition = 0;
	do {
#ifdef RAYTRACE_EXIT
		if (exit_condition > RAYTRACE_EXIT)
			break;
		exit_condition++;
#endif // RAYTRACE_EXIT

		// pop untraversed node
		stackpos--;
		const uint nodeIndex = stack[stackpos];

		BVHNode node = bvhNodeBuffer[nodeIndex];
		BVHAABB box = bvhAABBBuffer[nodeIndex];

		if (IntersectBox(ray, box))
		{
			//if (node.LeftChildIndex == 0 && node.RightChildIndex == 0)
			if (nodeIndex >= primitiveCount - 1)
			{
				// Leaf node
				const uint nodeToPrimitiveID = nodeIndex - leafNodeOffset;
				const uint primitiveID = primitiveIDBuffer[nodeToPrimitiveID];
				
				if (IntersectTriangleANY(ray, maxDistance, primitiveBuffer[primitiveID]))
				{
					shadow = true;
					break;
				}
			}
			else
			{
				// Internal node
				if (stackpos < RAYTRACE_STACKSIZE - 1)
				{
					// push left child
					stack[stackpos] = node.LeftChildIndex;
					stackpos++;
					// push right child
					stack[stackpos] = node.RightChildIndex;
					stackpos++;
				}
				else
				{
					// stack overflow, terminate
					break;
				}
			}

		}

	} while (!shadow && stackpos > 0);

	return shadow;
}

// Returns number of BVH nodes that were hit:
//	returns 0xFFFFFFFF when there was a stack overflow
//	returns (0xFFFFFFFF - 1) when the exit condition was reached
inline uint TraceBVH(Ray ray)
{
	uint hit_counter = 0;

	// Emulated stack for tree traversal:
	uint stack[RAYTRACE_STACKSIZE];
	uint stackpos = 0;

	const uint primitiveCount = primitiveCounterBuffer.Load(0);
	const uint leafNodeOffset = primitiveCount - 1;

	// push root node
	stack[stackpos] = 0;
	stackpos++;

	uint exit_condition = 0;
	do {
#ifdef RAYTRACE_EXIT
		if (exit_condition > RAYTRACE_EXIT)
			return (0xFFFFFFFF - 1);
		exit_condition++;
#endif // RAYTRACE_EXIT

		// pop untraversed node
		stackpos--;
		const uint nodeIndex = stack[stackpos];

		BVHNode node = bvhNodeBuffer[nodeIndex];
		BVHAABB box = bvhAABBBuffer[nodeIndex];

		if (IntersectBox(ray, box))
		{
			hit_counter++;

			if (nodeIndex >= primitiveCount - 1)
			{
				// Leaf node
			}
			else
			{
				// Internal node
				if (stackpos < RAYTRACE_STACKSIZE - 1)
				{
					// push left child
					stack[stackpos] = node.LeftChildIndex;
					stackpos++;
					// push right child
					stack[stackpos] = node.RightChildIndex;
					stackpos++;
				}
				else
				{
					// stack overflow, terminate
					return 0xFFFFFFFF;
				}
			}

		}

	} while (stackpos > 0);


	return hit_counter;
}

// This will modify ray to continue the trace
//	Also fill the final params of rayHit, such as normal, uv, materialIndex
//	seed should be > 0
//	pixel should be normalized uv coordinates of the ray start position (used to randomize)
inline float3 Shade(inout Ray ray, inout RayHit hit, inout float seed, in float2 pixel)
{
	if (hit.distance < INFINITE_RAYHIT)
	{
		Primitive_Triangle tri = Primitive_UnpackTriangle(primitiveBuffer[hit.primitiveID]);

		float u = hit.bary.x;
		float v = hit.bary.y;
		float w = 1 - u - v;

		hit.N = normalize(tri.n0 * w + tri.n1 * u + tri.n2 * v);
		hit.uvsets = tri.u0 * w + tri.u1 * u + tri.u2 * v;
		hit.color = tri.c0 * w + tri.c1 * u + tri.c2 * v;
		hit.materialIndex = tri.materialIndex;

		TracedRenderingMaterial material = materialBuffer[hit.materialIndex];

		hit.uvsets = frac(hit.uvsets); // emulate wrap

		float4 baseColor;
		[branch]
		if (material.uvset_baseColorMap >= 0)
		{
			const float2 UV_baseColorMap = material.uvset_baseColorMap == 0 ? hit.uvsets.xy : hit.uvsets.zw;
			baseColor = materialTextureAtlas.SampleLevel(sampler_linear_clamp, UV_baseColorMap * material.baseColorAtlasMulAdd.xy + material.baseColorAtlasMulAdd.zw, 0);
			baseColor.rgb = DEGAMMA(baseColor.rgb);
		}
		else
		{
			baseColor = 1;
		}
		baseColor *= hit.color;

		float4 surface_occlusion_roughness_metallic_reflectance;
		[branch]
		if (material.uvset_surfaceMap >= 0)
		{
			const float2 UV_surfaceMap = material.uvset_surfaceMap == 0 ? hit.uvsets.xy : hit.uvsets.zw;
			surface_occlusion_roughness_metallic_reflectance = materialTextureAtlas.SampleLevel(sampler_linear_clamp, UV_surfaceMap * material.surfaceMapAtlasMulAdd.xy + material.surfaceMapAtlasMulAdd.zw, 0);
			if (material.specularGlossinessWorkflow)
			{
				ConvertToSpecularGlossiness(surface_occlusion_roughness_metallic_reflectance);
			}
		}
		else
		{
			surface_occlusion_roughness_metallic_reflectance = 1;
		}

		float roughness = material.roughness * surface_occlusion_roughness_metallic_reflectance.g;
		float metalness = material.metalness * surface_occlusion_roughness_metallic_reflectance.b;
		float reflectance = material.reflectance * surface_occlusion_roughness_metallic_reflectance.a;
		roughness = sqr(roughness); // convert linear roughness to cone aperture
		float4 emissiveColor = material.emissiveColor;
		[branch]
		if (material.emissiveColor.a > 0 && material.uvset_emissiveMap >= 0)
		{
			const float2 UV_emissiveMap = material.uvset_emissiveMap == 0 ? hit.uvsets.xy : hit.uvsets.zw;
			float4 emissiveMap = materialTextureAtlas.SampleLevel(sampler_linear_clamp, UV_emissiveMap * material.emissiveMapAtlasMulAdd.xy + material.emissiveMapAtlasMulAdd.zw, 0);
			emissiveMap.rgb = DEGAMMA(emissiveMap.rgb);
			emissiveColor *= emissiveMap;
		}

		[branch]
		if (material.uvset_normalMap >= 0)
		{
			const float2 UV_normalMap = material.uvset_normalMap == 0 ? hit.uvsets.xy : hit.uvsets.zw;
			float3 normalMap = materialTextureAtlas.SampleLevel(sampler_linear_clamp, UV_normalMap * material.normalMapAtlasMulAdd.xy + material.normalMapAtlasMulAdd.zw, 0).rgb;
			normalMap = normalMap.rgb * 2 - 1;
			normalMap.g *= material.normalMapFlip;
			const float3 N = hit.N;
			const float3x3 TBN = float3x3(tri.tangent, tri.binormal, N);
			hit.N = normalize(lerp(N, mul(normalMap, TBN), material.normalMapStrength));
		}



		// Calculate chances of reflection types:
		float refractChance = 1 - baseColor.a;

		// Roulette-select the ray's path
		float roulette = rand(seed, pixel);
		if (roulette < refractChance)
		{
			// Refraction
			float3 R = refract(ray.direction, hit.N, 1 - material.refractionIndex);
			ray.direction = lerp(R, SampleHemisphere(R, seed, pixel), roughness);
			ray.energy *= lerp(baseColor.rgb, 1, refractChance);

			// The ray penetrates the surface, so push DOWN along normal to avoid self-intersection:
			ray.origin = trace_bias_position(hit.position, -hit.N);
		}
		else
		{
			// Calculate chances of reflection types:
			float3 albedo = ComputeAlbedo(baseColor, reflectance, metalness);
			float3 f0 = ComputeF0(baseColor, reflectance, metalness);
			float3 F = F_Fresnel(f0, saturate(dot(-ray.direction, hit.N)));
			float specChance = dot(F, 0.33);
			float diffChance = dot(albedo, 0.33);
			float inv = rcp(specChance + diffChance);
			specChance *= inv;
			diffChance *= inv;

			roulette = rand(seed, pixel);
			if (roulette < specChance)
			{
				// Specular reflection
				float3 R = reflect(ray.direction, hit.N);
				ray.direction = lerp(R, SampleHemisphere(R, seed, pixel), roughness);
				ray.energy *= F / specChance;
			}
			else
			{
				// Diffuse reflection
				ray.direction = SampleHemisphere(hit.N, seed, pixel);
				ray.energy *= albedo / diffChance;
			}

			// Ray reflects from surface, so push UP along normal to avoid self-intersection:
			ray.origin = trace_bias_position(hit.position, hit.N);
		}

		ray.primitiveID = hit.primitiveID;
		ray.bary = hit.bary;
		ray.Update();

		return emissiveColor.rgb * emissiveColor.a;
	}
	else
	{
		// Erase the ray's energy - the sky doesn't reflect anything
		ray.energy = 0.0f;

		float3 envColor;
		[branch]
		if (IsStaticSky())
		{
			// We have envmap information in a texture:
			envColor = DEGAMMA_SKY(texture_globalenvmap.SampleLevel(sampler_linear_clamp, ray.direction, 0).rgb);
		}
		else
		{
			envColor = GetDynamicSkyColor(ray.direction);
		}
		return envColor;
	}
}

#endif // _RAY_SCENE_INTERSECT_HF_
