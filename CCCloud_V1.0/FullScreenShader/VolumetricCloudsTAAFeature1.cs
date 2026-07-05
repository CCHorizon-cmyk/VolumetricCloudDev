using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricCloudsTAAFeature : ScriptableRendererFeature
{
    [System.Serializable]


    public class Settings
    {
        public Material cloudMaterial;       // 使用包含多个 Pass 的云材质
        //public Material blitMaterial;
        [Range(0.1f, 1f)] public float resolutionScale = 0.5f;
        public float cloudDistance = 5000f;   // 云层参考距离（世界单位）

        public bool enableTAA = true;

        public bool enableBlur = true;
        [Range(0, 5)] public float blurRadius = 1.0f; // 新增
    }

    public Settings settings = new Settings();
    private VolumetricCloudsTAAPass pass;
    protected override void Dispose(bool disposing)
    {
        pass?.ReleaseHistory();
    }

    public override void Create()
    {
        pass = new VolumetricCloudsTAAPass(settings);
        pass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.cloudMaterial == null) return;
        renderer.EnqueuePass(pass);
    }

    private class VolumetricCloudsTAAPass : ScriptableRenderPass
    {
        private Settings settings;
        private RenderTexture highResHistoryRT;      // 累积后的较高分辨率历史
        private Matrix4x4 prevViewProj;
        private Matrix4x4 prevInvProj;
        private bool historyReady;
        private int taaBlendFactorID;
        private int taaMotionScaleID;
        private int jitterID;
        public float cloudDistance = 5000f;   // 云层参考距离（世界单位）
        private int highResParamsID;
        private int frameIndex;                     // 用于 Halton 序列


        public VolumetricCloudsTAAPass(Settings settings)
        {
            this.settings = settings;
            taaBlendFactorID = Shader.PropertyToID("_TaaBlendFactor");
            taaMotionScaleID = Shader.PropertyToID("_TaaMotionScale");
            jitterID = Shader.PropertyToID("_JitterUV");

            highResParamsID = Shader.PropertyToID("_HighResParams");
            frameIndex = 0;
        }

        // Halton 序列生成 0..1 均匀分布
        private float Halton(int index, int baseVal)
        {
            float result = 0f;
            float f = 1f / baseVal;
            int i = index;
            while (i > 0)
            {
                result += f * (i % baseVal);
                i /= baseVal;
                f /= baseVal;
            }
            return result;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (settings.cloudMaterial == null) return;
            CommandBuffer cmd = CommandBufferPool.Get("Volumetric Clouds TAAU");
            RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            var cam = renderingData.cameraData.camera;
            int fullW = cam.pixelWidth;
            int fullH = cam.pixelHeight;
            // 低分辨率：使用 settings.resolutionScale 直接控制（建议 0.5~0.75）
            int lowW = Mathf.Max(1, (int)(fullW * settings.resolutionScale));
            int lowH = Mathf.Max(1, (int)(fullH * settings.resolutionScale));

            // 高分辨率（累积目标）：刚好是低分辨率的 2 倍，当 lowW = 0.5*fullW 时 highW = fullW
            int highW = lowW * 2;
            int highH = lowH * 2;

            // ---- Jitter ----
            int sampleCount = 8;
            float jitterX = Halton(frameIndex % sampleCount, 2) - 0.5f;
            float jitterY = Halton(frameIndex % sampleCount, 3) - 0.5f;
            Vector2 jitter = new Vector2(jitterX, jitterY);
            //jitter *= 10;
            frameIndex++;

            // ---- 1. 低分辨率云 ----
            RenderTextureDescriptor lowDesc = renderingData.cameraData.cameraTargetDescriptor;
            lowDesc.width = lowW;
            lowDesc.height = lowH;
            lowDesc.depthBufferBits = 0;
            lowDesc.colorFormat = RenderTextureFormat.ARGBHalf;
            int lowResRT = Shader.PropertyToID("_LowResCloud");
            cmd.GetTemporaryRT(lowResRT, lowDesc, FilterMode.Point);
            cmd.SetRenderTarget(lowResRT);
            cmd.ClearRenderTarget(false, true, Color.clear);
            cmd.SetGlobalVector(jitterID, jitter);
            Shader.SetGlobalInt("_FrameCount", Time.frameCount);
            cmd.DrawProcedural(Matrix4x4.identity, settings.cloudMaterial, 1, MeshTopology.Triangles, 3, 1);

            // ---- 2. 历史纹理管理 ----
            RenderTextureDescriptor highDesc = new RenderTextureDescriptor(highW, highH, RenderTextureFormat.ARGBHalf, 0);
            highDesc.depthBufferBits = 0;
            highDesc.msaaSamples = 1;
            if (!settings.enableTAA && highResHistoryRT != null)
            {
                highResHistoryRT.Release();
                highResHistoryRT = null;
                historyReady = false;
            }
            if (settings.enableTAA)
            {
                if (highResHistoryRT == null || highResHistoryRT.width != highW || highResHistoryRT.height != highH)
                {
                    if (highResHistoryRT != null) highResHistoryRT.Release();
                    highResHistoryRT = new RenderTexture(highDesc);
                    highResHistoryRT.filterMode = FilterMode.Bilinear;
                    highResHistoryRT.Create();
                    RenderTexture.active = highResHistoryRT;
                    GL.Clear(true, true, Color.clear);
                    historyReady = false;
                }
            }

            Matrix4x4 curViewProj = cam.projectionMatrix * cam.worldToCameraMatrix;
            Matrix4x4 curInvProj = cam.cameraToWorldMatrix * cam.projectionMatrix.inverse;

            if (settings.enableTAA)
            {
                // ---- TAAU 路径 ----
                if (!historyReady)
                {
                    prevViewProj = curViewProj;
                    prevInvProj = curInvProj;
                    cmd.SetRenderTarget(highResHistoryRT);
                    cmd.ClearRenderTarget(false, true, Color.clear);
                    cmd.Blit(lowResRT, highResHistoryRT);
                    historyReady = true;
                }

                cmd.SetGlobalMatrix("_PrevViewProj", prevViewProj);
                cmd.SetGlobalMatrix("_CurInvProj", curInvProj);
                // 运动自适应混合因子：基础值 0.1，但在 TAAU Shader 中会根据运动检测动态调整
                cmd.SetGlobalFloat(taaBlendFactorID, 0.25f);
                cmd.SetGlobalVector(highResParamsID, new Vector4(highW, highH, 1.0f / highW, 1.0f / highH));
                cmd.SetGlobalVector(jitterID, jitter);

                int highResTaaRT = Shader.PropertyToID("_HighResTaaCloud");
                cmd.GetTemporaryRT(highResTaaRT, highDesc, FilterMode.Bilinear);
                cmd.SetGlobalTexture("_CurrentCloud", lowResRT);
                cmd.SetGlobalTexture("_CloudHistory", highResHistoryRT);
                cmd.SetRenderTarget(highResTaaRT);
                cmd.ClearRenderTarget(false, true, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, settings.cloudMaterial, 4, MeshTopology.Triangles, 3, 1);

                cmd.CopyTexture(highResTaaRT, highResHistoryRT);
                prevViewProj = curViewProj;
                prevInvProj = curInvProj;

                // ---- 决定最终纹理（是否模糊） ----
                RenderTextureDescriptor fullDesc = renderingData.cameraData.cameraTargetDescriptor;
                fullDesc.msaaSamples = 1;
                fullDesc.depthBufferBits = 0;
                fullDesc.colorFormat = RenderTextureFormat.ARGBHalf;
                int finalCloudRT = highResTaaRT;
                int blurredCloudRT = Shader.PropertyToID("_BlurredCloud");
                if (settings.enableBlur && settings.blurRadius > 0f)
                {

                    
                    cmd.GetTemporaryRT(blurredCloudRT, fullDesc, FilterMode.Bilinear);
                    cmd.SetRenderTarget(blurredCloudRT);
                    cmd.ClearRenderTarget(false, true, Color.clear);
                    cmd.SetGlobalTexture("_MainTex", highResTaaRT);
                    cmd.SetGlobalFloat("_BlurRadius", settings.blurRadius); // 传递模糊半径
                    cmd.DrawProcedural(Matrix4x4.identity, settings.cloudMaterial, 2, MeshTopology.Triangles, 3, 1);
                    finalCloudRT = blurredCloudRT;
                }

                // ---- 混合到屏幕 ----
                int sceneCopyRT = Shader.PropertyToID("_SceneColorCopy");
                cmd.GetTemporaryRT(sceneCopyRT, fullDesc, FilterMode.Point);
                cmd.CopyTexture(cameraColorTarget, sceneCopyRT);
                cmd.SetRenderTarget(cameraColorTarget);
                cmd.SetGlobalTexture("_CloudTex", finalCloudRT);
                cmd.SetGlobalTexture("_SceneColorCopy", sceneCopyRT);
                cmd.SetGlobalFloat("_BlurRadius", settings.blurRadius);
                cmd.DrawProcedural(Matrix4x4.identity, settings.cloudMaterial, 3, MeshTopology.Triangles, 3, 1);

                cmd.ReleaseTemporaryRT(highResTaaRT);
                if (settings.enableBlur && settings.blurRadius > 0f) cmd.ReleaseTemporaryRT(blurredCloudRT);
                cmd.ReleaseTemporaryRT(sceneCopyRT);
            }
            else
            {
                // ---- 非 TAA 路径 ----
                cmd.SetRenderTarget(cameraColorTarget);
                cmd.SetGlobalTexture("_MainTex", lowResRT);
                cmd.DrawProcedural(Matrix4x4.identity, settings.cloudMaterial, 2, MeshTopology.Triangles, 3, 1);
            }

            cmd.ReleaseTemporaryRT(lowResRT);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void ReleaseHistory()
        {
            if (highResHistoryRT != null)
            {
                highResHistoryRT.Release();
                highResHistoryRT = null;
                historyReady = false;
            }
        }
    }

}