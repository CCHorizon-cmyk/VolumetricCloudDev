using UnityEngine;

public class CloudCenterSetter : MonoBehaviour
{
    [Header("云层中心跟随")]
    [Tooltip("云层圆柱中心跟随的目标（如主摄像机）")]
    public Transform target;

    public Material cloudMaterial;

    [Header("面片跟随")]
    [Tooltip("需要时刻面向摄像机的面片（如全屏 Quad）")]
    public Transform quadTransform;

    [Tooltip("面片与摄像机的恒定距离")]
    public float constantDistance = 10f;

    private void Update()
    {
        // 1. 更新云层中心
        if (target != null)
        {
            Vector3 pos = target.position;
            //Shader.SetGlobalVector("_CameraPos", new Vector4(pos.x, pos.y, pos.z, 0));
            cloudMaterial.SetVector("_CameraPos", Camera.main.transform.position);
        }

        // 2. 更新面片：位于摄像机前方恒定距离，且旋转与摄像机一致
        if (quadTransform != null)
        {
            // 获取主摄像机（如果 target 是摄像机就用它，否则用 Camera.main）
            Camera cam = target != null ? target.GetComponent<Camera>() : Camera.main;
            if (cam == null)
            {
                cam = Camera.main;
            }

            if (cam != null)
            {
                // 面片位置：摄像机前方 constantDistance 处
                quadTransform.position = cam.transform.position + cam.transform.forward * constantDistance;
                // 面片旋转：与摄像机旋转一致（使面片平面垂直于摄像机视线）
                quadTransform.rotation = cam.transform.rotation;
            }
        }
    }
}