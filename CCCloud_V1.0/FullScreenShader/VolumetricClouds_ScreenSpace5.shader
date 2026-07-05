Shader "Hidden/VolumetricClouds_ScreenSpace5"
{
    Properties
    {
// ========== 你的所有属性，一字不改 ==========
        [Header(Camera Follow)]
        _CameraPos("Cloud Center", Vector) = (0,0,0,0)
        
        [Header(Cloud Geometry)]
        _NoiseTex3D1("Noise 3D A", 3D) = "" {}
        _NoiseTex3D2("Noise 3D B", 3D) = "" {}
        _WeatherTex("Weather Map", 2D) = "white" {}
        _WeatherTexIntensity("WeatherTexIntensity", Range(0, 10)) = 2
        _ProfileTex("Profile Tex", 2D) = "white" {}
        _ProfileTexUV_V("ProfileTexUV_V", Range(0,1)) = 0.3
        _NoiseTex("NoiseTex", 2D) = "white" {}
        [Space(10)]
        [Header(TexShaping)]
        _VolumeTexScaler1 ("3DVolumeTex Scaler", Range(0.001, 1)) = 0.2
        _VolumeTexScaler2 ("3DVolumeTex Scaler2", Range(0.001, 1)) = 0.2
        _WeathereTexScaler ("WeatherTex Scaler", Range(0.001, 1)) = 0.2
        _FrequencyMix ("FrequencyMix", Range(0.001, 1)) = 0.2
        _CloudType("_CloudType", Range(0,1)) = 0.5
        _Coverage ("Coverage", Range(0.1, 1)) = 0.3
        _PlanetCenter("PlanetCenter", Vector) = (0,-6371,0,0)
        _CloudBottom("Cloud Bottom", Float) = 0
        _CloudTop("Cloud Top", Float) = 1000
        _CloudRadius("_CloudRadius", Range(1,20000)) = 1000
        [Space(10)]
        [Header(Lighting)]
        _LightStep("Light Steps", Range(2,24)) = 6
        _SkyUpStep("SkyUpStep", Range(2,12)) = 4
        _SkyUpStepSize("SkyUpStepSize", Range(0.01,12)) = 4
        _SunDayColor ("Sun Day Color", Color) = (1.0, 0.95, 0.85, 1.0)
        _SunHorizonColor ("Sun Horizon Color", Color) = (1.0, 0.3, 0.05, 1.0)
        _SunHorizonHeight ("Sun Horizon Height", Range(0, 0.5)) = 0.1
        _SunHorizonBlend ("Sun Horizon Blend", Range(0.01, 0.3)) = 0.1
        _IsotropySkyLightFactor("IsotropySkyLightFactor", Range(0, 1)) = 0.5
        _IsotropySkyColor ("IsotropySkyColor", Color) = (0.691, 0.769, 0.863, 1.0)
        _MaxAOIntensity("MaxAOIntensity", Range(0,1)) = 0.3
        _AOIntensity("AOIntensity", Range(0,10)) = 4
        _G("HG g", Range(0,0.95)) = 0.8
        _LightAbsorption("Light Absorption", Float) = 1.0

        _LightIntensity("LightIntensity", Range(0,4)) = 1.5
        [Space(10)]
        [Header(Raymarching)]
        _DebugCheapSample("Debug Cheap Sample", Range(0,1)) = 0
        _Density("Density", Range(0,10)) = 1
        _StepCount("StepCount", Range(32,512)) = 24
        _AdaptiveViewStepSize("AdaptiveViewStepSize", Range(0.1,10)) = 2
        _MaxStepSize("MaxStepSize", Range(1,200)) = 100
        _DistanceFogColorFactor("DistanceFogColorFactor", Range(0,1)) = 0.3
        _DistanceFogDensity("DistanceFogDensity", Range(0,10)) = 0.02
        _HeightFogDensity("HeightFogDensity",Range(0,1)) = 0.02
        _FactorSwift("FactorSwift", Range(0,1)) = 0
        [Header(Wispy Detail)]
        _EnableWispy("Enable Wispy Edge", Range(0,1)) = 1
        _WispyIntensity("Wispy Intensity", Range(0, 1)) = 0.2

        [Header(Multiple Scattering Frostbite)]
        _MultiScatteringStrength("Multi-Scattering Strength", Range(0, 2)) = 0.5
        _MsExtinctionFactor("MS Extinction Factor", Range(0.1, 1)) = 0.5
        _MsScatterFactor("MS Scatter Factor", Range(0.1, 1)) = 0.5

        [Header(Adaptive Light Step)]
        _LightStepMultiplier("Light Step Multiplier", Range(1.0, 3.0)) = 1.2

        [Header(Spherical Shell)]
        _UseSphericalShell("Use Spherical Shell", Range(0,1)) = 0

        _EnableAdaptiveStep ("Enable Adaptive Step", Range(0,1)) = 1
        _BlurRadius ("Blur Radius", Range(0, 3)) = 1.0

        _ShadowStrength("Shadow Strength", Range(0.5, 4.0)) = 1.0
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        // ================================================================
        // Pass 0：全分辨率备用（混合到屏幕）
        // ================================================================
        Pass
        {
            Name "FullRes"
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex CloudVert
            #pragma fragment CloudFrag
            #define PASS_CLOUD 1
            #include "CloudCore.hlsl"   // 见下文说明：你可以把核心函数放在外部文件，或直接内联
            ENDHLSL
        }

        // ================================================================
        // Pass 1：低分辨率绘制（无混合）
        Pass
        {
            Name "Downscale"
            Blend Off
            ZWrite Off ZTest Always Cull Off

            HLSLPROGRAM
            #pragma vertex CloudVert
            #pragma fragment CloudFrag
            #define PASS_CLOUD 1
            #include "CloudCore.hlsl"
            ENDHLSL
        }

        //PASS 2 //模糊混合
        Pass
{
    Name "CloudBlur"
    Blend Off
    ZWrite Off ZTest Always Cull Off

    HLSLPROGRAM
    #pragma vertex BlitVert
    #pragma fragment BlitFrag
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    struct BlitAttributes { uint vertexID : SV_VertexID; };
    struct BlitVaryings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

    TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
    float4 _MainTex_TexelSize;
    float _BlurRadius;

    BlitVaryings BlitVert(BlitAttributes input)
    {
        BlitVaryings o;
        float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
        o.positionCS = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        if (_ProjectionParams.x < 0.0) o.positionCS.y = -o.positionCS.y;
        o.uv = uv;
        return o;
    }

    half4 BlitFrag(BlitVaryings i) : SV_Target
    {
        int radius = (int)(_BlurRadius * 2.0);
        half4 col = 0;
        int samples = 0;
        for (int x = -radius; x <= radius; x++)
            for (int y = -radius; y <= radius; y++)
            {
                float2 offset = float2(x, y) * _MainTex_TexelSize.xy;
                col += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset);
                samples++;
            }
        return col / samples;
    }
    ENDHLSL
}


Pass
{
    Name "BlitAlpha"
    Blend SrcAlpha OneMinusSrcAlpha
    ZWrite Off ZTest Always Cull Off

    HLSLPROGRAM
    #pragma vertex BlitVert
    #pragma fragment CompositeFrag
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    struct BlitAttributes { uint vertexID : SV_VertexID; };
    struct BlitVaryings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

    TEXTURE2D(_CloudTex);
    SAMPLER(sampler_LinearClamp);
    float4 _CloudTex_TexelSize;
    float _BlurRadius;

    BlitVaryings BlitVert(BlitAttributes input)
    {
        BlitVaryings o;
        float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
        o.positionCS = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        if (_ProjectionParams.x < 0.0) o.positionCS.y = -o.positionCS.y;
        o.uv = uv;
        return o;
    }

    float4 CompositeFrag(BlitVaryings i) : SV_Target
    {
        // 当模糊半径 <= 0 时直接采样，避免性能开销
        if (_BlurRadius <= 0.0)
        {
            return SAMPLE_TEXTURE2D(_CloudTex, sampler_LinearClamp, i.uv);
        }

        // 均值模糊
        int radius = (int)_BlurRadius;
        half4 col = 0;
        int samples = 0;
        for (int x = -radius; x <= radius; x++)
        {
            for (int y = -radius; y <= radius; y++)
            {
                float2 offset = float2(x, y) * _CloudTex_TexelSize.xy;
                col += SAMPLE_TEXTURE2D(_CloudTex, sampler_LinearClamp, i.uv + offset);
                samples++;
            }
        }
        return col / samples;
    }
    ENDHLSL
}
        
        // Pass 4：
Pass
{
    Name "TAAU"
    Blend Off
    ZWrite Off ZTest Always Cull Off

    HLSLPROGRAM
    #pragma vertex BlitVert
    #pragma fragment TAAUFrag
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    struct BlitAttributes { uint vertexID : SV_VertexID; };
    struct BlitVaryings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

    TEXTURE2D(_CurrentCloud);   // 低分辨率当前帧
    TEXTURE2D(_CloudHistory);   // 高分辨率历史
    SAMPLER(sampler_LinearClamp);
    SAMPLER(sampler_PointClamp);

    float _TaaBlendFactor;
    float4x4 _CurInvProj;       // 当前帧 ViewInv * ProjInv
    float4x4 _PrevViewProj;     // 前一帧 Proj * View
    float2 _JitterUV;           // 低分辨率像素单位 Jitter [-0.5, 0.5]
    float4 _LowResParams;       // (lowW, lowH, 1/lowW, 1/lowH)

    // 云层高度范围（需在云材质中声明，TAAU 材质可直接访问）
    float _CloudBottom;         // 云底高度（世界 Y 坐标）
    float _CloudTop;            // 云顶高度（世界 Y 坐标）

    // Jitter 轴符号控制（根据实际翻转调整，通常 Y 轴为 -1）
    static const float _JitterSignX = 1.0;
    static const float _JitterSignY = -1.0;

    BlitVaryings BlitVert(BlitAttributes input)
    {
        BlitVaryings o;
        float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
        o.positionCS = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        if (_ProjectionParams.x < 0.0) o.positionCS.y = -o.positionCS.y;
        o.uv = uv;
        return o;
    }

    float4 TAAUFrag(BlitVaryings i) : SV_Target
{
    float2 uv = i.uv;

    // 1. 当前帧（低分辨率，双线性采样，包含 Jitter 信息）
    float4 curr = SAMPLE_TEXTURE2D(_CurrentCloud, sampler_LinearClamp, uv);
    float3 currColor = curr.rgb;

    // 2. 去 Jitter，得到理想像素 UV
    float2 jitterUV = _JitterUV * _LowResParams.zw;
    jitterUV.x *= _JitterSignX;
    jitterUV.y *= _JitterSignY;
    float2 unjitteredUV = uv - jitterUV;

    // 3. 重建世界坐标（用云中心高度）
    float2 ndc = unjitteredUV * 2.0 - 1.0;
    float4 farClip = float4(ndc, 1.0, 1.0);
    float4 farWorld = mul(_CurInvProj, farClip);
    farWorld /= farWorld.w;
    float3 viewDir = normalize(farWorld.xyz - _WorldSpaceCameraPos.xyz);
    float cloudCenter = (_CloudBottom + _CloudTop) * 0.5;
    float t = (cloudCenter - _WorldSpaceCameraPos.y) / max(viewDir.y, 0.0001);
    float3 worldPos = _WorldSpaceCameraPos.xyz + viewDir * t;

    // 4. 重投影到上一帧
    float4 prevClip = mul(_PrevViewProj, float4(worldPos, 1.0));
    prevClip /= prevClip.w;
    float2 prevUV = prevClip.xy * 0.5 + 0.5;
    prevUV = clamp(prevUV, 0.0, 1.0);

    // 5. 采样历史（注意：历史纹理是高分辨率，采样器用双线性）
    float4 hist = SAMPLE_TEXTURE2D(_CloudHistory, sampler_LinearClamp, prevUV);
    float3 histColor = hist.rgb;

    // 6. 邻域钳位（防止历史错误颜色污染）
    float2 texelSize = _LowResParams.zw;
    float3 cMin = currColor, cMax = currColor;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            float2 sampleUV = uv + float2(x, y) * texelSize;
            float3 col = SAMPLE_TEXTURE2D(_CurrentCloud, sampler_PointClamp, sampleUV).rgb;
            cMin = min(cMin, col);
            cMax = max(cMax, col);
        }
    }
    cMin -= 0.05;
    cMax += 0.05;
    histColor = clamp(histColor, cMin, cMax);

    // 7. 运动检测：计算重投影 UV 与当前 UV 的距离
    float motion = length(prevUV - uv);
    // 运动越大，当前帧占比越大（避免拖影）
    float blend = lerp(_TaaBlendFactor, 0.9, saturate(motion * 5));

    // 8. 混合
    float3 finalColor = lerp(histColor, currColor, blend);
    return float4(finalColor, curr.a);
}
    ENDHLSL
}

    }


}