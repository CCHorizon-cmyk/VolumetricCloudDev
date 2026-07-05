#ifndef CLOUD_CORE_INCLUDED
#define CLOUD_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

// ========== 变量声明（与 Properties 完全对应） ==========
float4 _CameraPos;

TEXTURE3D(_NoiseTex3D1); SAMPLER(sampler_NoiseTex3D1);
TEXTURE3D(_NoiseTex3D2); SAMPLER(sampler_NoiseTex3D2);
TEXTURE2D(_WeatherTex); SAMPLER(sampler_WeatherTex);
TEXTURE2D(_ProfileTex); SAMPLER(sampler_ProfileTex);
float _ProfileTexUV_V;
TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

float2 _JitterUV;

float _VolumeTexScaler1;
float _VolumeTexScaler2;
float _WeathereTexScaler;
float _WeatherTexIntensity;
float _FrequencyMix;
float _CloudType;
float _Coverage;
float3 _PlanetCenter;
float _CloudBottom, _CloudTop;
float _CloudRadius;
float _Density;
int _StepCount;
float _AdaptiveViewStepSize;
float _MaxStepSize;
int _LightStep;
int _SkyUpStep;
float _SkyUpStepSize;
float3 _SunDayColor;
float3 _SunHorizonColor;
float _SunHorizonHeight;
float _SunHorizonBlend;
float4 _IsotropySkyColor;
float _IsotropySkyLightFactor;
float _G;
float _LightAbsorption;
float _LightIntensity;

float _MaxAOIntensity;
float _AOIntensity;
float _DistanceFogColorFactor;
float3 _MainLightDirection;
float _FactorSwift;
float _DistanceFogDensity;
float _HeightFogDensity;
float _MultiScatteringStrength;
float _MsExtinctionFactor;
float _MsScatterFactor;
float _ShadowStrength;

float _IndirectLightMode; // 0=后处理单点, 1=循环内间隔采样×补偿
float _EnableAdaptiveStep;
float _EnableWispy;
float _WispyIntensity;
float _LightStepMultiplier;
float _UseSphericalShell;
float _DebugCheapSample;
float _EnablePowderEffect;
float3 _WindDirection;
float _WindSpeed;

// 多散射级别
#define kMsCount 2

float4 _LowResParams; // (lowW, lowH, 1/lowW, 1/lowH)

// 250米内使用的固定步长（硬编码）
#define NEAR_FIXED_STEP 4.0
#define NEAR_DISTANCE_THRESHOLD 40.0
// 透射率提前退出阈值（视线+光源统一）
#define TRANSMITTANCE_EXIT_THRESHOLD 0.01
// 间接光模式：0=循环外单点，1=循环内每4命中×4倍补偿
#define INDIRECT_STEP_INTERVAL 4
// ========== 这里粘贴你所有的辅助函数（GetJitter, remap, SampleDensity, CloudLayerIntersection3, 光照函数等） ==========
float GetJitter(float2 screenUV)
{
    float2 noiseUV = screenUV * _ScreenParams.xy / 128.0;
                // 128 = 噪声贴图尺寸（例如128x128）

    float noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;

    return noise;
}
            

float3 CloudLayerIntersection2(float3 camPos, float3 rayDir)
{
    float eps = 1e-5;
    float _MaxDistance = (_CloudTop - _CloudBottom) * 50;

                // ===== 高度交点（不变）=====
    float tMin, tMax;
    if (abs(rayDir.y) < eps)
    {
        if (camPos.y > _CloudBottom && camPos.y < _CloudTop)
        {
            tMin = 0.0;
            tMax = _MaxDistance;
        }
        else
            return float3(0, 0, 0);
    }
    else
    {
        float invY = 1.0 / rayDir.y;
        float t0 = (_CloudBottom - camPos.y) * invY;
        float t1 = (_CloudTop - camPos.y) * invY;
        tMin = max(min(t0, t1), 0.0);
        tMax = max(t0, t1);
        if (tMax <= tMin)
            return float3(0, 0, 0);
    }

                // ===== XZ 半径限制（修改此处）=====
    float cloudRadius = _CloudRadius;

                // ★ 将射线起点转换为相对于圆柱中心的坐标 ★
    float2 centerXZ = _CameraPos.xz; // 圆柱中心
    float2 ro = camPos.xz - centerXZ; // 相对位置
    float2 rd = rayDir.xz; // 方向不变

    float a = dot(rd, rd);
    float b = 2.0 * dot(ro, rd);
    float c = dot(ro, ro) - cloudRadius * cloudRadius;

    float disc = b * b - 4 * a * c;

    if (disc > 0.0)
    {
        float sqrtDisc = sqrt(disc);
        float t0 = (-b - sqrtDisc) / (2.0 * a);
        float t1 = (-b + sqrtDisc) / (2.0 * a);

        float tEnter = min(t0, t1);
        float tExit = max(t0, t1);

                    // 与高度区间求交
        tMin = max(tMin, tEnter);
        tMax = min(tMax, tExit);

        if (tMax <= tMin)
            return float3(0, 0, 0);
    }
    else
    {
        return float3(0, 0, 0);
    }

                // ===== 最终长度限制（不变）=====
    float maxRayLength = (_CloudTop - _CloudBottom) * 50;
    tMax = min(tMax, tMin + maxRayLength);

    float length = tMax - tMin;
    float stepSize = length / _StepCount;
    stepSize = clamp(stepSize, 0.5, max(_MaxStepSize, 20.0));

    return float3(tMin, tMax, stepSize);
}

float3 CloudLayerIntersection3(float3 camPos, float3 rayDir, out int actualStepCount)
{
    float eps = 1e-5;
    float _MaxDistance = (_CloudTop - _CloudBottom) * 50;



    // ===== 高度交点（不变）=====
    float tMin, tMax;
    if (abs(rayDir.y) < eps)
    {
        if (camPos.y > _CloudBottom && camPos.y < _CloudTop)
        {
            tMin = 0.0;
            tMax = _MaxDistance;
        }
        else
        {
            actualStepCount = 0;
            return float3(0, 0, 0);
        }
    }
    else
    {
        float invY = 1.0 / rayDir.y;
        float t0 = (_CloudBottom - camPos.y) * invY;
        float t1 = (_CloudTop - camPos.y) * invY;
        tMin = max(min(t0, t1), 0.0);
        tMax = max(t0, t1);
        if (tMax <= tMin)
        {
            actualStepCount = 0;
            return float3(0, 0, 0);
        }
    }

    // ===== XZ 半径限制 =====
    float cloudRadius = _CloudRadius;
    float2 centerXZ = camPos.xz;
    float2 ro = camPos.xz - centerXZ;
    float2 rd = rayDir.xz;

    float a = dot(rd, rd);
    float b = 2.0 * dot(ro, rd);
    float c = dot(ro, ro) - cloudRadius * cloudRadius;

    float disc = b * b - 4 * a * c;

    if (disc > 0.0)
    {
        float sqrtDisc = sqrt(disc);
        float t0 = (-b - sqrtDisc) / (2.0 * a);
        float t1 = (-b + sqrtDisc) / (2.0 * a);

        float tEnter = min(t0, t1);
        float tExit = max(t0, t1);

        tMin = max(tMin, tEnter);
        tMax = min(tMax, tExit);

        if (tMax <= tMin)
        {
            actualStepCount = 0;
            return float3(0, 0, 0);
        }
    }
    else
    {
        actualStepCount = 0;
        return float3(0, 0, 0);
    }

    // ===== 最终长度限制 =====
    float maxRayLength = (_CloudTop - _CloudBottom) * 50;
    tMax = min(tMax, tMin + maxRayLength);

    // 步数 = 基准192 × (_StepCount/192) × 视角系数
    // 天顶: _StepCount步, 地平线: _StepCount×2步
    // 250m内: 强制NEAR_FIXED_STEP小步长
    float length = tMax - tMin;
    float baseSteps = 192.0;
    float stepFactor = _StepCount / baseSteps;
    float verticalFactor = saturate(abs(rayDir.y));
    float angleScale = lerp(2.0, 1.0, verticalFactor);

    if (length <= NEAR_DISTANCE_THRESHOLD)
    {
        actualStepCount = max(32, (int)(baseSteps * stepFactor * angleScale));
        float stepSize = length / float(actualStepCount);
        stepSize = clamp(stepSize, 0.5, max(_MaxStepSize, 20.0));
        return float3(tMin, tMax, stepSize);
    }

    int nearSteps = (int)ceil(NEAR_DISTANCE_THRESHOLD / NEAR_FIXED_STEP);
    float remaining = length - NEAR_DISTANCE_THRESHOLD;
    int farSteps = max(32, (int)(baseSteps * stepFactor * angleScale));
    float farStepSize = remaining / float(farSteps);
    farStepSize = clamp(farStepSize, 0.5, max(_MaxStepSize, 20.0));
    actualStepCount = nearSteps + farSteps;

    return float3(tMin, tMax, farStepSize);
}

// ========== 球形壳层相交（HZD / Flower方案）==========
float raySphereIntersectNearest(float3 ro, float3 rd, float3 center, float radius)
{
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return -1.0;
    h = sqrt(h);
    float t0 = -b - h;
    float t1 = -b + h;
    if (t0 > 0.0) return t0;
    if (t1 > 0.0) return t1;
    return -1.0;
}

float raySphereIntersectInside(float3 ro, float3 rd, float3 center, float radius)
{
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return -1.0;
    return -b + sqrt(h);
}

bool raySphereIntersectOutSide(float3 ro, float3 rd, float3 center, float radius, inout float2 t0t1)
{
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return false;
    h = sqrt(h);
    t0t1 = float2(-b - h, -b + h);
    return true;
}

float3 CloudLayerIntersectionSpherical(float3 camPos, float3 rayDir, out int actualStepCount)
{
    const float planetRadius = 6370000.0;
    float3 sphereCenter = _PlanetCenter; // 固定在地心
    float radiusCloudInner = planetRadius + _CloudBottom;
    float radiusCloudOuter = planetRadius + _CloudTop;
    float viewHeight = length(camPos - sphereCenter);

    float tMin, tMax;

    if (viewHeight < radiusCloudInner)
    {
        // 摄像机在云层下方（靠近地面）
        float tEarth = raySphereIntersectNearest(camPos, rayDir, sphereCenter, planetRadius);
        if (tEarth > 0.0)
        {
            actualStepCount = 0;
            return float3(0, 0, 0);
        }
        tMin = raySphereIntersectInside(camPos, rayDir, sphereCenter, radiusCloudInner);
        tMax = raySphereIntersectInside(camPos, rayDir, sphereCenter, radiusCloudOuter);
    }
    else if (viewHeight > radiusCloudOuter)
    {
        // 摄像机在云层上方（太空）
        float2 tOuter;
        if (!raySphereIntersectOutSide(camPos, rayDir, sphereCenter, radiusCloudOuter, tOuter))
        {
            actualStepCount = 0;
            return float3(0, 0, 0);
        }
        float2 tInner;
        if (raySphereIntersectOutSide(camPos, rayDir, sphereCenter, radiusCloudInner, tInner))
        {
            tMin = tOuter.x;
            tMax = tInner.x;
        }
        else
        {
            tMin = tOuter.x;
            tMax = tOuter.y;
        }
    }
    else
    {
        // 摄像机在云层内部
        tMin = 0.0;
        float tStart = raySphereIntersectNearest(camPos, rayDir, sphereCenter, radiusCloudInner);
        if (tStart > 0.0)
            tMax = tStart;
        else
            tMax = raySphereIntersectInside(camPos, rayDir, sphereCenter, radiusCloudOuter);
    }

    tMin = max(tMin, 0.0);
    tMax = max(tMax, 0.0);

    if (tMax <= tMin)
    {
        actualStepCount = 0;
        return float3(0, 0, 0);
    }

    // XZ水平范围限幅（_CloudRadius），避免地平线处步进距离过大
    float rdXZlen = dot(rayDir.xz, rayDir.xz);
    if (rdXZlen > 0.0001)
    {
        float tCyl = _CloudRadius / sqrt(rdXZlen);
        tMax = min(tMax, tCyl);
    }

    // 最大射线长度限制
    float maxRayLength = (_CloudTop - _CloudBottom) * 100;
    tMax = min(tMax, tMin + maxRayLength);

    float length = tMax - tMin;
    float baseSteps = 192.0;
    float stepFactor = _StepCount / baseSteps;
    float verticalFactor = saturate(abs(rayDir.y));
    float angleScale = lerp(2.0, 1.0, verticalFactor);

    if (length <= NEAR_DISTANCE_THRESHOLD)
    {
        actualStepCount = max(32, (int)(baseSteps * stepFactor * angleScale));
        float stepSize = length / float(actualStepCount);
        stepSize = clamp(stepSize, 0.5, max(_MaxStepSize, 20.0));
        return float3(tMin, tMax, stepSize);
    }

    int nearSteps = (int)ceil(NEAR_DISTANCE_THRESHOLD / NEAR_FIXED_STEP);
    float remaining = length - NEAR_DISTANCE_THRESHOLD;
    int farSteps = max(32, (int)(baseSteps * stepFactor * angleScale));
    float farStepSize = remaining / float(farSteps);
    farStepSize = clamp(farStepSize, 0.5, max(_MaxStepSize, 20.0));
    actualStepCount = nearSteps + farSteps;

    return float3(tMin, tMax, farStepSize);
}

// 统一入口：根据 _UseSphericalShell 切换
float3 CloudLayerIntersectionDispatch(float3 camPos, float3 rayDir, out int actualStepCount)
{
    if (_UseSphericalShell > 0.5)
        return CloudLayerIntersectionSpherical(camPos, rayDir, actualStepCount);
    else
        return CloudLayerIntersection3(camPos, rayDir, actualStepCount);
}

// ========== 球形壳层相交结束 ==========


            //remap函数，采样函数要用

float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}


float SampleWeatherTex(float3 worldPos)
{
    float3 windOffset = _WindDirection * _Time.y * _WindSpeed;
    float2 weatherUV = (worldPos.xz + windOffset.xz) * _WeathereTexScaler * 0.001;
    float h = (worldPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);

    float4 weathertex = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, weatherUV);
    float weather = weathertex.r;

    weather = remap(weather, 1 - _Coverage, 1, 0, 1);
    weather *= _WeatherTexIntensity;
    float normalizedHeight = h;
    float2 profileUV = float2(weather, h);
    float profile = SAMPLE_TEXTURE2D(_ProfileTex, sampler_ProfileTex, profileUV).r;
    float3 profileTex = SAMPLE_TEXTURE2D(_ProfileTex, sampler_ProfileTex, profileUV);
    float profileR, profileG, profileB;
    profileR = max(0, 0.5 - _CloudType);
    profileG = -abs(0.5 - _CloudType) + 0.5;
    profileB = max(0, -0.5 + _CloudType);
    float Finalprofile = profileTex.r * profileR + profileTex.g * profileG + profileTex.b * profileB;
    return Finalprofile;

}

// ========== 密度采样（Flower cloudMap 1:1移植，统一风驱动）==========
float SampleDensity(float3 worldPos, inout float LFDensity)
{
    if (worldPos.y > _CloudTop || worldPos.y < _CloudBottom)
        return 0.0;

    float h = (worldPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
    float3 windOffset = _WindDirection * _Time.y * _WindSpeed;

    // ---- 天气图（双尺度：大尺度→profile, 细节→局部变化）----
    float2 weatherUV = (worldPos.xz + windOffset.xz) * _WeathereTexScaler * 0.001;
    float weatherCoarse = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, weatherUV).r;
    float weatherDetail = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, weatherUV * 3.7 + 0.5).r;
    float weather = saturate(weatherCoarse * _WeatherTexIntensity);
    float weatherFine = saturate(lerp(weatherCoarse, weatherDetail, 0.35) * _WeatherTexIntensity);

    // ---- 局部覆盖率（XZ大尺度低频采样，随风漂移）----
    float localCoverage = (SAMPLE_TEXTURE3D(_NoiseTex3D2, sampler_NoiseTex3D2,
        float3((worldPos.xz + windOffset.xz) * 0.000001 + 0.5, 0.3)).r - 0.5) * _FrequencyMix;
    float coverage = saturate(_Coverage * (localCoverage + weatherFine));

    // ---- 高度渐变（大尺度weather → Profile UV → 云型垂直分布）----
    float2 profileUV = float2(weather, h);
    float3 profileTex = SAMPLE_TEXTURE2D(_ProfileTex, sampler_ProfileTex, profileUV);
    float profileR = max(0.0, 0.5 - _CloudType);
    float profileG = -abs(0.5 - _CloudType) + 0.5;
    float profileB = max(0.0, _CloudType - 0.5);
    float profile = profileTex.r * profileR + profileTex.g * profileG + profileTex.b * profileB;

    float gradientShape = remap(h, 0.0, 0.1, 0.0, 1.0) * remap(h, 0.7, 1.0, 1.0, 0.0) * profile;

    // ---- 基础3D噪声（fBm合成）：顺风位移 ----
    float3 uvBasic = (worldPos + windOffset) * 0.05 * _VolumeTexScaler1;
    float4 LFnoiseTex = SAMPLE_TEXTURE3D(_NoiseTex3D1, sampler_NoiseTex3D1, uvBasic);
    float HFnoise = SAMPLE_TEXTURE3D(_NoiseTex3D2, sampler_NoiseTex3D2, uvBasic * _VolumeTexScaler2 / _VolumeTexScaler1).r;
    float low_freq_fBm = HFnoise * 0.625 + LFnoiseTex.b * 0.25 + LFnoiseTex.a * 0.125;
    float basicNoise = remap(LFnoiseTex.r, -(1.0 - low_freq_fBm), 1.0, 0.0, 1.0);

    // ---- 基础形状 = 梯度(含profile) × 噪声 ----
    float basicCloudNoise = gradientShape * basicNoise;

    // ---- 覆盖率驱动密度映射 ----
    float cloudWithCoverage = coverage * remap(basicCloudNoise, 1.0 - coverage, 1.0, 0.0, 1.0);

    // ---- 细节侵蚀（HF噪声，云顶反转）：逆风×0.15，模拟湍流混合 ----
    float3 uvDetail = (worldPos - windOffset * 0.15) * 0.05 * _VolumeTexScaler2;
    float detailNoise = SAMPLE_TEXTURE3D(_NoiseTex3D2, sampler_NoiseTex3D2, uvDetail).r;
    float erosionStrength = _EnableWispy > 0.5 ? _WispyIntensity : _FrequencyMix;
    float detailErosion = erosionStrength * lerp(detailNoise, 1.0 - detailNoise, saturate(h * 10.0));

    // ---- 云密度 ----
    float cloudDensity = remap(cloudWithCoverage, detailErosion, 1.0, 0.0, 1.0);

    // ---- 高度密度衰减 ----
    float densityShape = saturate(0.01 + h * 1.15) * _Density
        * remap(h, 0.0, 0.1, 0.0, 1.0)
        * remap(h, 0.8, 1.0, 1.0, 0.0);

    LFDensity = HFnoise;
    return saturate(cloudDensity) * densityShape;
}

// 粗密度：仅低频 + 覆盖率，用于 SkyupTransmittance 大尺度遮挡
float SampleCoarseDensity(float3 worldPos)
{
    if (worldPos.y > _CloudTop || worldPos.y < _CloudBottom)
        return 0.0;

    float h = (worldPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
    float3 windOffset = _WindDirection * _Time.y * _WindSpeed;

    float2 weatherUV = (worldPos.xz + windOffset.xz) * _WeathereTexScaler * 0.001;
    float weather = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, weatherUV).r;
    weather = saturate(weather * _WeatherTexIntensity);

    float3 uv = (worldPos + windOffset) * 0.05 * _VolumeTexScaler1;
    float LFnoise = SAMPLE_TEXTURE3D(_NoiseTex3D1, sampler_NoiseTex3D1, uv).r;

    float localCoverage = (LFnoise - 0.5) * _FrequencyMix;
    float coverage = saturate(_Coverage * (localCoverage + weather));

    float gradientShape = remap(h, 0.0, 0.1, 0.0, 1.0) * remap(h, 0.7, 1.0, 1.0, 0.0);

    float basicCloudNoise = gradientShape * LFnoise;
    float cloudWithCoverage = coverage * remap(basicCloudNoise, 1.0 - coverage, 1.0, 0.0, 1.0);

    float densityShape = saturate(0.01 + h * 1.15) * _Density
        * remap(h, 0.0, 0.1, 0.0, 1.0)
        * remap(h, 0.8, 1.0, 1.0, 0.0);

    return saturate(cloudWithCoverage) * densityShape;
}

// 廉价密度：仅天气图 + Profile + 高度，无3D噪声（用于调试对比）
float SampleCheapDensity(float3 worldPos)
{
    if (worldPos.y > _CloudTop || worldPos.y < _CloudBottom)
        return 0.0;

    float h = (worldPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
    float3 windOffset = _WindDirection * _Time.y * _WindSpeed;

    float2 weatherUV = (worldPos.xz + windOffset.xz) * _WeathereTexScaler * 0.001;
    float weather = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, weatherUV).r;
    weather = saturate(weather * _WeatherTexIntensity);

    float2 profileUV = float2(weather, h);
    float3 profileTex = SAMPLE_TEXTURE2D(_ProfileTex, sampler_ProfileTex, profileUV);
    float profileR = max(0.0, 0.5 - _CloudType);
    float profileG = -abs(0.5 - _CloudType) + 0.5;
    float profileB = max(0.0, _CloudType - 0.5);
    float profile = profileTex.r * profileR + profileTex.g * profileG + profileTex.b * profileB;

    float coverage = saturate(_Coverage * weather);
    float gradientShape = remap(h, 0.0, 0.1, 0.0, 1.0) * remap(h, 0.7, 1.0, 1.0, 0.0) * profile;
    float density = coverage * gradientShape;

    float densityShape = saturate(0.01 + h * 1.15) * _Density
        * remap(h, 0.0, 0.1, 0.0, 1.0)
        * remap(h, 0.8, 1.0, 1.0, 0.0);

    return saturate(density) * densityShape;
}

// ========== Frostbite 多散射（单次光照步进推导高阶）==========
float getUniformPhase()
{
    return 1.0 / (4.0 * 3.14159);
}

// 从单次光照步进结果推导多级散射透射率
// T_light0: 直接透射率, extinctionAcc0: 累积消光
// 高阶通过 MsExtinctionFactor 比例推导
void DeriveMultiScattering(float T_light0, float extinctionAcc0,
                           out float T_light[kMsCount], out float extinctionAcc[kMsCount])
{
    T_light[0] = T_light0;
    extinctionAcc[0] = extinctionAcc0;

    float msFactor = _MsExtinctionFactor;
    for (int ms = 1; ms < kMsCount; ms++)
    {
        extinctionAcc[ms] = extinctionAcc0 * msFactor;
        T_light[ms] = exp(-extinctionAcc[ms]);
        msFactor *= _MsExtinctionFactor;
    }
}

// 高阶散射相位（趋近各向同性）
float getMsPhase(float basePhase, int ms)
{
    float uniformPhase = getUniformPhase();
    float MsPhaseFactor = _MsScatterFactor;
    float phase = basePhase;
    for (int i = 1; i <= ms; i++)
    {
        phase = lerp(uniformPhase, phase, MsPhaseFactor);
        MsPhaseFactor *= MsPhaseFactor;
    }
    return phase;
}
            
float3 ComputeSunColor(float3 sunDirection)
{
    float sunHeight = sunDirection.y;
    float t = smoothstep(_SunHorizonHeight - _SunHorizonBlend,
                                     _SunHorizonHeight + _SunHorizonBlend,
                                     sunHeight);
    float3 color = lerp(_SunHorizonColor.rgb, _SunDayColor.rgb, t);
    float brightness = saturate(sunHeight * 5.0);
    color *= lerp(0.6, 1.0, brightness);
    return color;
}

            //各向同性天光1
float3 GetSkyLightColor(float3 lightDir)
{
                // lightDir: 主光源方向（指向光源，normalized）

    float h = saturate(-lightDir.y * 0.5 + 0.5);

                // 天顶蓝（高空）
    float3 skyZenith = float3(0.22, 0.45, 1.0);

                // 地平线颜色（偏白/暖）
    float3 skyHorizon = float3(0.75, 0.85, 1.0);

                // 日落暖色（低太阳）
    float3 sunset = float3(1.0, 0.5, 0.2);

                // 基础天空渐变
    float3 sky = lerp(skyHorizon, skyZenith, h);

                // 日落染色（只在低角度出现）
    float sunsetFactor = pow(1.0 - h, 3.0);
    sky = lerp(sky, sunset, sunsetFactor);

    return sky;
}
            //各向同性天光2
float3 GetSkyAmbientColor(float3 lightDir)
{
                // lightDir：指向太阳的方向（normalized）

                // =====  太阳高度（-1~1 → 0~1）=====
    float h = saturate(lightDir.y * 0.5 + 0.5);
    h = abs(lightDir.y);
                
                // =====  基础天空颜色 =====
    float3 skyZenith = float3(0.22, 0.45, 1.0); // 天顶蓝
    float3 skyHorizon = float3(0.75, 0.85, 1.0); // 地平线偏亮

    float3 sky = lerp(skyHorizon, skyZenith, h);

                // =====  日落暖色（低太阳才出现）=====
    float sunsetFactor = pow(1.0 - h, 3.0);
    float3 sunsetColor = float3(0.9, 0.25, 0);

    sky = lerp(sky, sunsetColor, sunsetFactor);

                // =====  轻微去饱和（避免过蓝）=====
    float luminance = dot(sky, float3(0.299, 0.587, 0.114));
    sky = lerp(float3(luminance, luminance, luminance), sky, 0.85);

    return sky;
}

float3 GetAmbientFromSunDir(float3 sunDir)
{
    float h = max(0, sunDir.y);
    float intensity = pow(h, 0.6) * 0.8 + 0.1; // 强度范围 0.1~0.9
    float3 colorLow = float3(1.0, 0.5, 0.25);
    float3 colorHigh = float3(0.4, 0.55, 0.9);
    return lerp(colorLow, colorHigh, h) * intensity;
}

float GetAOIntensity(float3 worldPos, int step)
{
    float ao = 0;
                //if (step % 2 == 0)
                {
        float h = (worldPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
        float ao = smoothstep(0.4, _MaxAOIntensity, h);
    }
    return ao;
}

// 根据太阳高度角 Y 分量计算距离雾颜色
// sunDirY : 世界空间光源方向的 Y 分量（归一化向量，范围 -1 ~ 1）
// 返回   : HDR 线性空间的雾颜色（浮点精度）
float3 ComputeFogColorFromSunDir(float sunDirY)
{
                // 将 sunDirY 映射到 0~1（夜间为 0，正午为 1）
    float t = saturate(sunDirY * 0.5 + 0.5);
    t = smoothstep(0.0, 0.2, t); // 压低极低角度时的突变

                // 昼间暖雾色（正午偏白，下午偏浅黄）
    float3 dayColor = lerp(float3(0.9, 0.85, 0.7), float3(1.0, 0.95, 0.9), t);
                // 夜间冷雾色（深蓝灰）
    float3 nightColor = float3(0.05, 0.08, 0.2);

                // 根据太阳高度混合昼/夜
    float dayFactor = saturate(sunDirY * 3.0); // 太阳低于地平线较多时迅速转为夜晚
    float3 baseFog = lerp(nightColor, dayColor, dayFactor);

                // 黄昏增强（太阳贴近地平线时叠加橙红）
    float horizonGlow = exp(-abs(sunDirY) * 8.0); // sunDirY 接近 0 时最高
    float3 sunsetColor = float3(1.0, 0.6, 0.3);
    baseFog += sunsetColor * horizonGlow * 0.5;

                // 强度缩放（HDR 下可调，默认 1）
    float fogIntensity = 1.0;
    return baseFog * fogIntensity;
}

            //距离雾2
float3 ApplyDistanceFog2(
                float3 sceneColor,
                float3 worldPos,
                float3 cameraPos,
                float3 fogColor,
                float fogdensity,
                float height
            )
{
                
    float d = distance(worldPos, cameraPos);
    
                //float density = 0.0002;
    float density = fogdensity * 0.001;

                // 延迟雾开始（更真实）
    float fogStart = 10.0;
    d = max(d - fogStart, 0.0);
    height = clamp(height, 0, 1);
    float T = exp(-d * density);
                //float3 finalFogColor = fogColor * luminance(fogColor);
    float3 finalcolor = lerp(fogColor, sceneColor, T);
    //finalcolor = lerp(sceneColor, finalcolor, max(0.25,max(0.25, 1 - height)));
    //finalcolor = height;
    return finalcolor;
}



float3 ApplyHeightDistanceFog(
                float3 sceneColor,
                float3 worldPos,
                float3 cameraPos,
                float3 fogColor,
                float density, // 例如 0.0025
                float heightFalloff, // 例如 0.0008 (高度衰减系数)
                float distanceExp // 新增：距离幂次，通常 1.5~2.5
            )
{
                // ===== 距离（可开平方增强远处效果） =====
    float d = distance(worldPos, cameraPos);
    float distFactor = pow(d / 1000.0, distanceExp); // 将距离映射到合理数值范围

                // ===== 高度影响（低处更浓） =====
    float heightFactor = exp(-worldPos.y * heightFalloff);
                // 可限制雾只在某个高度以下有效
                // heightFactor = saturate(1.0 - worldPos.y * heightFalloff * 0.01);

                // ===== 光学厚度 =====
    float opticalDepth = distFactor * density * heightFactor;

                // ===== 透射率（允许完全衰减） =====
    float T = exp(-opticalDepth);

                // ===== 混合 =====
    return lerp(fogColor, sceneColor, T);
}

float powderEffectNew(float depth, float height, float VoL)
{
    float r = VoL * 0.5 + 0.5;
    r = r * r;
    height = height * (1.0 - r) + r;
    return depth * height;
}
            //----高度雾---
float3 ApplyHeightFog(
                float3 sceneColor, // 原颜色
                float height, // 当前高度（世界空间 y）
                float density // 雾浓度
            )
{
                // ===== 高度雾因子（指数衰减）=====
    float fogFactor = exp(-height * density);

                // 限制范围（避免数值问题）
    fogFactor = saturate(fogFactor);

                // ===== 默认雾颜色（中性灰蓝，避免脏）=====
    float3 fogColor = float3(0.7, 0.8, 0.9);

                // ===== 混合 =====
    return lerp(fogColor, sceneColor, fogFactor);
}





            // =========================
            // HG 相位函数
            // =========================
float HG(float cosTheta, float g)
{
    float g2 = g * g;
    return (1 - g2) / (4 * 3.14159 * pow(1 + g2 - 2 * g * cosTheta, 1.5));
}

float HGPhase(float VOL, float g)
{
    float numer = 1 - g * g;
    float denom = 1 + g * g + 2 * g * VOL;
    return numer / (4 * 3.14159 * denom * sqrt(denom));
}

float DualHG_Soft(float cosTheta)
{
    float forward = HG(0.7, cosTheta);
    float backward = HG(-0.3, cosTheta);

    float phase = lerp(backward, forward, 0.8);

                // 关键：防止死黑
    phase = lerp(0.15, phase, 0.85);

    return phase;
}

float DualHGPhase(float g0, float g1, float w, float VOL)
{
    return lerp(HGPhase(g0, VOL), HGPhase(g1, VOL), w);
}



float3 SampleSkyAnalytic(float3 dir, float3 sunDir)
{
    float mu = dot(dir, sunDir);

    float rayleigh = 0.75 * (1 + mu * mu);

    float mie = HG(mu, 0.76);

    float3 rayleighColor = float3(0.5, 0.7, 1.0);
    float3 mieColor = float3(1.0, 0.9, 0.8);

    return rayleighColor * rayleigh + mieColor * mie;
}
            // =========================
// ========== 光照向太阳积分（每步完整密度采样）==========
float LightTransmittance(float3 pos, inout float LightDensity)
{
    float t = 0;
    float step = (_CloudTop - _CloudBottom) / _LightStep / 4;

    float trans = 1;
    float totaldensity = 0;

    [loop]
    for (int i = 0; i < _LightStep; i++)
    {
        float3 p = pos + _MainLightDirection * t;

        float LFDensity = 0;
        float d = SampleDensity(p, LFDensity);

        trans *= exp(-d * step * _LightAbsorption);
        totaldensity += d * step;
        if (trans < TRANSMITTANCE_EXIT_THRESHOLD)
            break;

        t += step;
        step *= _LightStepMultiplier;
    }

    LightDensity = totaldensity;
    return trans;
}
            // 光线向天顶方向积分
float SkyupTransmittance(float3 pos)
{
    float t = 0;
                //步长大小
    float step = (_CloudTop - _CloudBottom) / 2 / 4;
    step = step * _SkyUpStepSize;

    float trans = 1;
    float totaldensity = 0;
    float3 SkyupDir = float3(0, 1, 0);
                [loop]
    for (int i = 0; i < _LightStep; i++)
    {
        float3 p = pos + SkyupDir * t;
        float d = SampleCoarseDensity(p); // 粗密度过滤高频抖动

        trans *= exp(-d * step * _LightAbsorption);
        totaldensity += d * step;
        if (trans < TRANSMITTANCE_EXIT_THRESHOLD)
            break;

        t += step;
    }
                
    return trans;
}

            // 光线向地面方向积分
float GroundTransmittance(float3 pos)
{
    float t = 0;

    float step = (_CloudTop - _CloudBottom) / _LightStep / 4;
    step = step * _SkyUpStepSize;

    float trans = 1;
    float totaldensity = 0;
    float3 GroundDir = float3(0, -1, 0);
                [loop]
    for (int i = 0; i < _LightStep; i++)
    {
        float3 p = pos + GroundDir * t;
        float LFDensity = 0;
        float d = SampleDensity(p, LFDensity);

        trans *= exp(-d * step * _LightAbsorption);
        totaldensity += d / _LightStep;
        if (trans < TRANSMITTANCE_EXIT_THRESHOLD)
            break;

        t += step;
    }
                
    return trans;
}


// 内部散射增强因子
// worldPos:     云表面世界坐标（视线累计结束点）
// lightTransmittance: 该点到光源的透射率 (0~1)
// coneLength:   锥形采样长度（建议设为云层高度的一半）
// 返回: 额外内散射亮度，需加到最终散射项并乘以不透明度
float ComputeInternalInscattering(
    float3 worldPos,
    float lightTransmittance,
    float coneLength,
    float3 lightdir)
{
    // ----- 材质参数（建议暴露）-----
    int _InternalSteps = 4; // 采样步数 (4~8)
    float _InternalIntensity = 2; // 增强强度 (0~2)
    float _InternalThicknessScale = 4; // 光学厚度→亮度映射的缩放 (1~4)

    float stepSize = coneLength / max(_InternalSteps, 1);
    float3 sampleDir = -lightdir; // 光源反方向，即深入云体

    float opticalDepth = 0.0;
    float weightSum = 0.0;

    // 锥形权重：越深处贡献越小（模拟光衰减）
    for (int i = 0; i < _InternalSteps; i++)
    {
        float t = (i + 0.5) * stepSize; // 当前距离
        float3 samplePos = worldPos + sampleDir * t;
        float density = SampleDensity(samplePos, _Density);

        // 距离衰减权重（可调）
        float weight = saturate(t / coneLength); // 线性衰减，或用 exp(-t)
        opticalDepth += density * stepSize * weight;
        weightSum += weight;
    }

    // 归一化加权光学厚度
    float avgThickness = opticalDepth / max(weightSum, 0.001);

    // 将厚度映射为增强亮度（可改用 smoothstep 等）
    float enhancement = saturate(avgThickness * _InternalThicknessScale);

    // 该点接收的光照（含光源颜色和透射）
    float incidentLight = lightTransmittance;

    // 额外内散射亮度 = 光照 × 增强因子 × 相位函数（可加可不加，避免过亮）
    // 这里乘以一个平均相位（可定制）
   
    float extraLight = incidentLight * enhancement * _InternalIntensity;

    return extraLight;
}

            // >>> 粘贴结束 <<<

// ========== 顶点/片元 ==========
struct Attributes
{
    uint vertexID : SV_VertexID;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 screenUV : TEXCOORD0;
};

Varyings CloudVert(Attributes input)
{
    Varyings o;
    float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
    o.positionCS = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    if (_ProjectionParams.x < 0.0)
        o.positionCS.y = -o.positionCS.y;
    o.screenUV = uv;
    return o;
}

half4 CloudFrag(Varyings i) : SV_Target
{
    // ★ 应用 Jitter，每帧射线方向略有不同
    float2 screenUV = i.screenUV + _JitterUV * _LowResParams.zw;

    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV);
    float3 worldPos = ComputeWorldSpacePosition(screenUV, rawDepth, UNITY_MATRIX_I_VP);
    float3 campos = _WorldSpaceCameraPos;
    float3 raydir = normalize(worldPos - campos);
    float distToSurface = length(worldPos - campos);

    Light mainLight = GetMainLight();
    float3 lightDir = mainLight.direction;
    _MainLightDirection = lightDir;

    float abscloudlayer = _CloudTop - _CloudBottom;

    int actualStepCount;
    float3 CloudLayerPara = CloudLayerIntersectionDispatch(campos, raydir, actualStepCount);
    float tMin = CloudLayerPara.x;
    float tMax = CloudLayerPara.y;
    tMax = min(tMax, distToSurface);

    if (tMax <= tMin)
        return half4(0, 0, 0, 0);

    
    float stepsize = CloudLayerPara.z;
    stepsize = clamp(stepsize, 0.5, _MaxStepSize);

        // ★★★ 修改开始 ★★★
    float cloudLength = tMax - tMin; // 云层总长度
    bool isNearCloud = cloudLength <= NEAR_DISTANCE_THRESHOLD; // 是否在近距离阈值内

    float T_view = 1.0;
    float3 scatter = 0;

    float2 noiseUV = (screenUV + _Time.y * 60.0) / 512;
    // 近处使用固定起始偏移 0.5，远处使用时间变化的抖动
    float jitter = isNearCloud ? 0.0 : GetJitter(noiseUV);
    // ★★★ 修改结束 ★★★
    //jitter = 1;
    //jitter = lerp(0, 1, jitter);

    // ───────────────────────────────────────────────
    // 自适应步长（HZD方案：2D天气图廉价探测 + 步长渐变）
    // ───────────────────────────────────────────────
    float3 windOffset  = _WindDirection * _Time.y * _WindSpeed;
    float nearStep     = NEAR_FIXED_STEP;   // 250m内固定小步长
    float farStep      = stepsize;
    float maxStep      = farStep * max(8.0, _AdaptiveViewStepSize * 4.0);
    bool  adaptiveOn   = (_EnableAdaptiveStep > 0.5);

    float step = nearStep;
    float t = tMin + jitter * nearStep;

    float3 rayHitPos = campos;
    float3 firstHitPos = campos;
    float rayHitWeight = 0;
    bool rayHit = false;
    float totalLightDepth = 0;

    float VOL = dot(raydir, lightDir);
    float absVOL = saturate(dot(raydir, lightDir));

    float3 IsotropySkyLight = ComputeSunColor(lightDir);
    IsotropySkyLight *= max(0.2, lightDir.y);

    // ── 主循环 ──────────────────────────────────
    // 间接光模式切换
    bool usePerSampleAmbient = _IndirectLightMode > 0.5;
    int hitCount = 0;
    float3 cachedAmbient = float3(0, 0, 0);

    int iter = 0;
    float prevT = t;
    [loop]
    while (t < tMax && iter < actualStepCount)
    {
        iter++;
        float3 currentPos = campos + raydir * t;
        float  LFDensity = 0;

        // ── 2D天气图廉价探测（HZD：空区大步 → 命中回退 → 小步采样）──
        if (adaptiveOn)
        {
            float hQuick = (currentPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
            if (hQuick > 0.0 && hQuick < 1.0)
            {
                float heightFade = remap(hQuick, 0.0, 0.15, 0.0, 1.0) * remap(hQuick, 0.7, 1.0, 1.0, 0.0);
                float2 wUV = (currentPos.xz + windOffset.xz) * _WeathereTexScaler * 0.001;
                float weatherQuick = SAMPLE_TEXTURE2D(_WeatherTex, sampler_WeatherTex, wUV).r;

                if (weatherQuick * heightFade * _Coverage < 0.05)
                {
                    prevT = t;
                    step = maxStep;
                    t += step;
                    continue;
                }
            }
            // 命中潜在云区：回退到上一步，切小步长
            t = prevT;
            step = nearStep;
            currentPos = campos + raydir * t;
        }

        // 调试开关：对比廉价采样（天气+覆盖率+云型+profile）vs 完整3D噪声采样
        float density = (_DebugCheapSample > 0.5)
            ? SampleCheapDensity(currentPos)
            : SampleDensity(currentPos, LFDensity);

        if (density > 0.001)
        {
            if (!rayHit) { firstHitPos = currentPos; } // 记录首次命中
            rayHit = true;
            hitCount++;

            float h = (currentPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);

            float LightDensity = 0;
            float T_light0 = LightTransmittance(currentPos, LightDensity);
            float T_light2 = exp(-LightDensity * 0.25);

            float T_light[kMsCount];
            float extinctionAcc[kMsCount];
            DeriveMultiScattering(T_light0, LightDensity, T_light, extinctionAcc);

            totalLightDepth += LightDensity;

            float3 lightcolor = ComputeSunColor(lightDir);

            float phase1 = HG(absVOL, _G);
            float phase2 = DualHGPhase(0.5, -0.5, 0.2, -VOL);

            float isotropic = 1.0 / (4.0 * 3.14159);
            float phase = lerp(isotropic, phase1, 0.85);

            float s = _ShadowStrength;
            float shadowT = lerp(saturate(T_light0), saturate(T_light0) * saturate(T_light0), saturate(s - 1.0));
            float shadowT2 = lerp(saturate(T_light2), saturate(T_light2) * saturate(T_light2), saturate(s - 1.0));
            float DirectLight = max(shadowT, shadowT2 * 0.7) * _LightIntensity * (1.0 + phase2);

            float msPhase = getMsPhase(phase, 1);
            float MsEnhance = T_light[1] * _MultiScatteringStrength * (1.0 + msPhase) * (1.0 - T_light0);
            DirectLight += MsEnhance;

            // 循环内模式：每N次命中采样，×N补偿稀疏采样
            if (usePerSampleAmbient && (hitCount % INDIRECT_STEP_INTERVAL == 0))
            {
                float T_skyup_sample = SkyupTransmittance(currentPos);
                cachedAmbient = T_skyup_sample * _AOIntensity * IsotropySkyLight * INDIRECT_STEP_INTERVAL;
            }

            float3 TotalLight = DirectLight * lightcolor + cachedAmbient * (1.0 - saturate(DirectLight));

            float depth_probability = lerp(0.05 + pow(density, remap(h, 0.3, 0.85, 0.5, 2.0)), 1.0, saturate(T_light0 / step));
            float vertical_probability = pow(remap(h, 0.07, 0.22, 0.1, 1.0), 0.8);
            float in_scatter_probability = clamp(depth_probability * vertical_probability, 0, 0.9);
            in_scatter_probability = pow(in_scatter_probability, 4);
            in_scatter_probability = remap(in_scatter_probability, 0, 2, 1.5, 0);

            float3 contrib = T_view * density * TotalLight * in_scatter_probability;
            scatter += contrib * step;

            rayHitPos += (currentPos - campos) * T_view;
            rayHitWeight += T_view;

            T_view *= exp(-density * step);
        }

        if (T_view < TRANSMITTANCE_EXIT_THRESHOLD) break;

        // 越过近端阈值后切换为远距步长
        if (t >= NEAR_DISTANCE_THRESHOLD) step = farStep;

        t += step;
    }

    // ── 后处理 ──────────────────────────────────
    if (rayHitPos.y == 0)
        rayHitPos = campos;

    float rayHitHeight = (_CloudTop - rayHitPos.y) / (_CloudTop - _CloudBottom);
    float3 lightcolor = ComputeSunColor(lightDir);

    // 间接光：两点法，循环内模式已处理则跳过
    if (!usePerSampleAmbient)
    {
        float firstHitH = saturate((firstHitPos.y - _CloudBottom) / (_CloudTop - _CloudBottom));
        float rayHitH   = saturate((rayHitPos.y - _CloudBottom) / (_CloudTop - _CloudBottom));
        float T_skyup_entry = 1.0;
        float T_skyup_depth = 1.0;
        if (firstHitH > 0.01) T_skyup_entry = SkyupTransmittance(firstHitPos);
        if (rayHitH > 0.01)   T_skyup_depth = SkyupTransmittance(rayHitPos);
        float T_skyup_final = lerp(T_skyup_entry, T_skyup_depth, 1.0 - T_view);
        float T_light_rep = exp(-totalLightDepth * 0.5);
        scatter += T_skyup_final * _AOIntensity * IsotropySkyLight * (1.0 - T_view) * (1.0 - T_light_rep);
    }

    if (_EnablePowderEffect > 0.5)
    {
        float PowderEffectFactor1 = powderEffectNew(totalLightDepth, rayHitHeight, abs(VOL)) * (1 - T_view);
        float PowderEffectFactor2 = powderEffectNew(totalLightDepth, rayHitHeight, VOL);
        float PowderEffectFactor = (_FactorSwift * T_view) * pow(absVOL, 2) * 8 * (1 - T_view);

        scatter += PowderEffectFactor * lightcolor;
    }

    // 距离雾颜色：正午=指定色，夕阳=混合阳光色
    float fogT = 1.0 - saturate(lightDir.y * 3.0); // 太阳越低t越接近1
    float3 fogColor = lerp(_IsotropySkyColor.rgb, lightcolor, fogT * 0.5);

    float h = (rayHitPos.y - _CloudBottom) / (_CloudTop - _CloudBottom);
    scatter = ApplyDistanceFog2(scatter, rayHitPos, campos, fogColor, _DistanceFogDensity * 0.01, 1 - h);

    scatter = clamp(scatter, 0.1, 2.5);

    
    return half4(scatter, 1 - T_view);
}

// ========== GodRay 体积光（屏幕空间向太阳步进）==========
float3 ComputeGodRays(float3 startPos, float3 sunDir, int steps, float maxDist, float3 sunColor)
{
    float stepSize = maxDist / float(steps);
    float t = stepSize * 0.5;
    float T = 1.0;
    float3 scatter = float3(0, 0, 0);

    [loop]
    for (int i = 0; i < steps; i++)
    {
        float3 pos = startPos + sunDir * t;
        float LFDensity = 0;
        float density = SampleDensity(pos, LFDensity);

        if (density > 0.001)
        {
            float LightDensity = 0;
            float T_light = LightTransmittance(pos, LightDensity);

            float3 contrib = T * density * T_light * sunColor * stepSize;
            scatter += contrib;

            T *= exp(-density * stepSize);
        }

        t += stepSize;
        if (T < 0.01) break;
    }

    return scatter;
}

#endif // CLOUD_CORE_INCLUDED