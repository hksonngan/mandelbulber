formulaOut Fractal(__constant sClInConstants *consts, float3 point, sClCalcParams *calcParam)
{	
	float dist = 0.0f;
	int N = calcParam->N;
	float3 z = point;
	float3 c = consts->fractal.julia;
	int i;
	formulaOut out;
	float r = 0.0f;
	float colourMin = 1e8f;
	
	
