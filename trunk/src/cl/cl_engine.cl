#pragma OPENCL EXTENSION cl_khr_byte_addressable_store : enable

typedef float3 cl_float3;
typedef float cl_float;
typedef int cl_int;
typedef unsigned int cl_uint;
typedef unsigned short cl_ushort;

#include "mandelbulber_cl_data.h"

#define MAX_RAYMARCHING 500

typedef struct
{
	float3 z;
	float iters;
	float distance;
	float colourIndex;
} formulaOut;

static formulaOut Fractal(__constant sClInConstants *consts, float3 point, sClCalcParams *calcParam);
static formulaOut CalculateDistance(__constant sClInConstants *consts, float3 point, sClCalcParams *calcParam);

inline float3 Matrix33MulFloat3(matrix33 matrix, float3 vect)
{
	float3 out;
	out.x = dot(vect, matrix.m1);
	out.y = dot(vect, matrix.m2);
	out.z = dot(vect, matrix.m3);
	return out;
}

matrix33 Matrix33MulMatrix33(matrix33 m1, matrix33 m2)
{
	matrix33 out;
	out.m1.x = m1.m1.x * m2.m1.x + m1.m1.y * m2.m2.x + m1.m1.z * m2.m3.x;
	out.m1.y = m1.m1.x * m2.m1.y + m1.m1.y * m2.m2.y + m1.m1.z * m2.m3.y;
	out.m1.z = m1.m1.x * m2.m1.z + m1.m1.y * m2.m2.z + m1.m1.z * m2.m3.z;
	out.m2.x = m1.m2.x * m2.m1.x + m1.m2.y * m2.m2.x + m1.m2.z * m2.m3.x;
	out.m2.y = m1.m2.x * m2.m1.y + m1.m2.y * m2.m2.y + m1.m2.z * m2.m3.y;
	out.m2.z = m1.m2.x * m2.m1.z + m1.m2.y * m2.m2.z + m1.m2.z * m2.m3.z;
	out.m3.x = m1.m3.x * m2.m1.x + m1.m3.y * m2.m2.x + m1.m3.z * m2.m3.x;
	out.m3.y = m1.m3.x * m2.m1.y + m1.m3.y * m2.m2.y + m1.m3.z * m2.m3.y;
	out.m3.z = m1.m3.x * m2.m1.z + m1.m3.y * m2.m2.z + m1.m3.z * m2.m3.z;
	return out;
}

matrix33 RotateX(matrix33 m, float angle)
{
		matrix33 out, rot;
		float s = sin(angle);
		float c = cos(angle);		
		rot.m1 = (float3) {1.0f, 0.0f, 0.0f};
		rot.m2 = (float3) {0.0f, c   , -s  };
		rot.m3 = (float3) {0.0f, s   ,  c  };
		out = Matrix33MulMatrix33(m, rot);
		return out;
}

matrix33 RotateY(matrix33 m, float angle)
{
		matrix33 out, rot;
		float s = sin(angle);
		float c = cos(angle);		
		rot.m1 = (float3) {c   , 0.0f, s   };
		rot.m2 = (float3) {0.0f, 1.0f, 0.0f};
		rot.m3 = (float3) {-s  , 0.0f, c   };
		out = Matrix33MulMatrix33(m, rot);
		return out;
}

matrix33 RotateZ(matrix33 m, float angle)
{
		matrix33 out, rot;
		float s = sin(angle);
		float c = cos(angle);		
		rot.m1 = (float3) { c  , -s  , 0.0f};
		rot.m2 = (float3) { s  ,  c  , 0.0f};
		rot.m3 = (float3) {0.0f, 0.0f, 1.0f};
		out = Matrix33MulMatrix33(m, rot);
		return out;
}

float4 quaternionMul(float4 q1, float4 q2)
{
//source: http://www.cs.columbia.edu/~keenan/Projects/QuaternionJulia/QJuliaFragment.html
	float4 result;
	result.x = q1.x * q2.x - dot(q1.yzw, q2.yzw);
	result.yzw = q1.x * q2.yzw + q2.x * q1.yzw + cross(q1.yzw, q2.yzw);
	return result;
}

float4 quaternionSqr(float4 q)
{
	//source: http://www.cs.columbia.edu/~keenan/Projects/QuaternionJulia/QJuliaFragment.html
	float4 result;
	result.x = q.x * q.x - dot(q.yzw, q.yzw);
	result.yzw = 2.0f * q.x * q.yzw;
	return result;
}

/*
float PrimitivePlane(float4 point, float4 centre, float4 normal)
{
	float4 plane = normal;
	plane = plane * (1.0/ fast_length(plane));
	float planeDistance = dot(plane, point - centre);
	return planeDistance;
}

float PrimitiveBox(float4 point, float4 center, float4 size)
{
	float distance, planeDistance;
	float4 corner1 = (float4){center.x - 0.5f*size.x, center.y - 0.5f*size.y, center.z - 0.5f*size.z, 0.0f};
	float4 corner2 = (float4){center.x + 0.5f*size.x, center.y + 0.5f*size.y, center.z + 0.5f*size.z, 0.0f};

	planeDistance = PrimitivePlane(point, corner1, (float4){-1,0,0,0});
	distance = planeDistance;
	planeDistance = PrimitivePlane(point, corner2, (float4){1,0,0,0});
	distance = (planeDistance > distance) ? planeDistance : distance;

	planeDistance = PrimitivePlane(point, corner1, (float4){0,-1,0,0});
	distance = (planeDistance > distance) ? planeDistance : distance;
	planeDistance = PrimitivePlane(point, corner2, (float4){0,1,0,0});
	distance = (planeDistance > distance) ? planeDistance : distance;

	planeDistance = PrimitivePlane(point, corner1, (float4){0,0,-1,0});
	distance = (planeDistance > distance) ? planeDistance : distance;
	planeDistance = PrimitivePlane(point, corner2, (float4){0,0,1,0});
	distance = (planeDistance > distance) ? planeDistance : distance;

	return distance;
}
*/


float3 NormalVector(__constant sClInConstants *consts, float3 point, float mainDistance, float distThresh, sClCalcParams *calcParam)
{
	float delta = distThresh;
	float s1 = CalculateDistance(consts, point + (float3){delta,0.0f,0.0f}, calcParam).distance;
	float s2 = CalculateDistance(consts, point + (float3){0.0f,delta,0.0f}, calcParam).distance;
	float s3 = CalculateDistance(consts, point + (float3){0.0f,0.0f,delta}, calcParam).distance;
	float3 normal = (float3) {s1 - mainDistance, s2 - mainDistance, s3 - mainDistance};
	normal = normalize(normal);
	return normal;
}


float Shadow(__constant sClInConstants *consts, float3 point, float3 lightVector, float distThresh, sClCalcParams *calcParam)
{
	float scan = distThresh * 2.0f;
	float shadow = 0.0f;
	float factor = distThresh * 1000.0f;
	for(int count = 0; (count < 100); count++)
	{
		float3 pointTemp = point + lightVector*scan;
		float distance = CalculateDistance(consts, pointTemp, calcParam).distance;
		scan += distance * 2.0f;
		
		if(scan > factor)
		{
			shadow = 1.0f;
			break;
		}
		
		if(distance < distThresh)
		{
			shadow = scan / factor;
			break;
		}
	}
	return shadow;
}


float FastAmbientOcclusion(__constant sClInConstants *consts, float3 point, float3 normal, float dist_thresh, float tune, int quality, sClCalcParams *calcParam)
{
	//reference: http://www.iquilezles.org/www/material/nvscene2008/rwwtt.pdf (Iñigo Quilez – iq/rgba)

	float delta = dist_thresh;
	float aoTemp = 0.0f;
	for(int i=1; i<quality*quality; i++)
	{
		float scan = i * i * delta;
		float3 pointTemp = point + normal * scan;
		float dist = CalculateDistance(consts, pointTemp, calcParam).distance;
		aoTemp += 1.0f/(native_powr(2.0f,(float)i)) * (scan - tune*dist)/dist_thresh;
	}
	float ao = 1.0f - 0.2f * aoTemp;
	if(ao < 0.0f) ao = 0.0f;
	return ao;
}

float3 IndexToColour(int index, global float3 *palette)
{
	float3 colOut, col1, col2, colDiff;

	if (index < 0)
	{
		colOut = palette[255];
	}
	else
	{
		int index2 = index % 65280;
		int no = index2 / 256;
		col1 = palette[no];
		col2 = palette[no+1];
		colDiff = col2 - col1;
		float delta = (index2 % 256)/256.0;
		colOut = col1 + colDiff * delta;
	}
	return colOut;
}

float3 Background(float3 viewVector, __constant sClParams *params)
{
	float3 vector = {0.0f, 0.0f, -1.0f};
	vector = fast_normalize(vector);
	float grad = dot(viewVector, vector) + 1.0f;
	float3 colour;
	if(grad < 1.0f)
	{
		float ngrad = 1.0f - grad;
		colour = params->backgroundColour3 * ngrad + params->backgroundColour2 * grad;
	}
	else
	{
		grad = grad - 1.0f;
		float ngrad = 1.0f - grad;
		colour = params->backgroundColour2 * ngrad + params->backgroundColour1 * grad;
	}
	return colour;
}

//------------------ MAIN RENDER FUNCTION --------------------
kernel void fractal3D(__global sClPixel *out, __global sClInBuff *inBuff, __constant sClInConstants *consts, __global sClReflect *reflectBuff, int Gcl_offset)
{
	int cl_offset = Gcl_offset;
	
	const unsigned int i = get_global_id(0) + cl_offset;
	const unsigned int imageX = i % consts->params.width;
	const unsigned int imageY = i / consts->params.width;
	const unsigned int buffIndex = (i - cl_offset);
	
	if(imageY < consts->params.height)
	{
		float2 screenPoint = (float2) {convert_float(imageX), convert_float(imageY)};
		float width = convert_float(consts->params.width);
		float height = convert_float(consts->params.height);
		float resolution = 1.0f/width;
		
		const float3 one = (float3) {1.0f, 0.0f, 0.0f};
		const float3 ones = 1.0f;
		
		matrix33 rot;
		rot.m1 = (float3){1.0f, 0.0f, 0.0f};
		rot.m2 = (float3){0.0f, 1.0f, 0.0f};
		rot.m3 = (float3){0.0f, 0.0f, 1.0f};
		rot = RotateZ(rot, consts->params.alpha);
		rot = RotateX(rot, consts->params.beta);
		rot = RotateY(rot, consts->params.gamma);
		
		float3 back = (float3) {0.0f, 1.0f, 0.0f} / consts->params.persp * consts->params.zoom;
		float3 start = consts->params.vp - Matrix33MulFloat3(rot, back);
		
		float aspectRatio = width / height;
		float x2,z2;
		x2 = (screenPoint.x / width - 0.5f) * aspectRatio;
		z2 = (screenPoint.y / height - 0.5f);
		float3 viewVector = (float3) {x2 * consts->params.persp, 1.0f, z2 * consts->params.persp}; 
		viewVector = Matrix33MulFloat3(rot, viewVector);
		
		bool found = false;
		int count;
		
		float3 point;
		float scan, distThresh, distance;
		
		scan = 1e-10f;
		
		sClCalcParams calcParam;
		calcParam.N = consts->fractal.N;
		
		formulaOut outF;
		//ray-marching
		for(count = 0; count < MAX_RAYMARCHING; count++)
		{
			point = start + viewVector * scan;
			outF = CalculateDistance(consts, point, &calcParam);
			distance = outF.distance;
			distThresh = scan * resolution * consts->params.persp;
			
			if(distance < distThresh)
			{
				found = true;
				break;
			}
					
			float step = (distance  - 0.5f*distThresh) * consts->params.DEfactor;			
			scan += step;
			
			if(scan > 50.0f) break;
		}
		
		
		//binary searching
		float step = distThresh;
		for(int i=0; i<10; i++)
		{
			if(distance < distThresh && distance > distThresh * 0.95f)
			{
				break;
			}
			else
			{
				if(distance > distThresh)
				{
					point += viewVector * step;
				}
				else if(distance < distThresh * 0.95f)
				{
					point -= viewVector * step;
				}
			}
			outF = CalculateDistance(consts, point, &calcParam);
			distance = outF.distance;
			step *= 0.5f;
		}
		
		float zBuff = scan;
		
		float3 colour = 0.0f;
		if(found)
		{
			float3 normal = NormalVector(consts, point, distance, distThresh, &calcParam);
			
			float3 lightVector = (float3) {
				cos(consts->params.mainLightAlfa - 0.5f * M_PI) * cos(-consts->params.mainLightBeta), 
				sin(consts->params.mainLightAlfa - 0.5f * M_PI) * cos(-consts->params.mainLightBeta), 
				sin(-consts->params.mainLightBeta)};
			lightVector = Matrix33MulFloat3(rot, lightVector);
			float shade = dot(lightVector, normal);
			if(shade<0.0f) shade = 0.0f;
			
			float shadow = Shadow(consts, point, lightVector, distThresh, &calcParam);
			//float shadow = 1.0f;
			//shadow = 0.0;
			
			float3 half = lightVector - viewVector;
			half = fast_normalize(half);
			float specular = dot(normal, half);
			if (specular < 0.0f) specular = 0.0f;
			specular = pown(specular, 30.0f);
			if (specular > 15.0f) specular = 15.0f;
			
			float ao = FastAmbientOcclusion(consts, point, normal, distThresh, 1.0f, 3, &calcParam);
			
			int colourNumber = outF.colourIndex * consts->params.colouringSpeed + 256.0f * consts->params.colouringOffset;
			float3 surfaceColour = 1.0;
			if (consts->params.colouringEnabled) surfaceColour = IndexToColour(colourNumber, inBuff->palette);
			
			colour = (shade * surfaceColour + specular * consts->params.specularIntensity) * shadow * consts->params.mainLightIntensity + ao * surfaceColour * consts->params.ambientOcclusionIntensity;
		}
		else
		{
			colour = Background(viewVector, &consts->params);
		}
		
		float glow = count / 2560.0f;
		float glowN = 1.0f - glow;
		if(glowN < 0.0f) glowN = 0.0f;
		float3 glowColor;
		glowColor.x = 1.0f * glowN + 1.0f * glow;
		glowColor.y = 0.0f * glowN + 1.0f * glow;
		glowColor.z = 0.0f * glowN + 0.0f * glow;
		colour += glowColor * glow;
		
		
		ushort R = convert_ushort_sat(colour.x * 65536.0f);
		ushort G = convert_ushort_sat(colour.y * 65536.0f);
		ushort B = convert_ushort_sat(colour.z * 65536.0f);
		
		out[buffIndex].R = R;
		out[buffIndex].G = G;
		out[buffIndex].B = B;
		out[buffIndex].zBuffer = zBuff;
	}
}

