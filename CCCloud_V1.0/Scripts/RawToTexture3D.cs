using UnityEngine;
using System.IO;

#if UNITY_EDITOR
using UnityEditor;

public class RawToTexture3D : MonoBehaviour
{
    [Header("设置参数 (必须与 Blender 导出一致)")]
    public int resolution = 256;
    public int depth = 128;

    [Header("选中的文件路径")]
    [ReadOnly] public string selectedPath;

    public void SelectAndConvert()
    {
        // 1. 弹出系统文件选择窗口
        string path = EditorUtility.OpenFilePanel("选择导出的 RAW 文件", Application.dataPath, "raw");

        if (string.IsNullOrEmpty(path)) return;

        selectedPath = path;

        // 2. 读取数据
        byte[] data = File.ReadAllBytes(path);

        // 验证数据大小是否匹配 (RGBA32 = 4 bytes per pixel)
        long expectedSize = (long)resolution * resolution * depth * 4;
        if (data.Length != expectedSize)
        {
            Debug.LogError($"数据大小不匹配！预期: {expectedSize} bytes, 实际: {data.Length} bytes。请检查分辨率和层数设置。");
            return;
        }

        // 3. 创建 Texture3D
        Texture3D tex = new Texture3D(resolution, resolution, depth, TextureFormat.RGBA32, false);
        tex.filterMode = FilterMode.Bilinear;
        tex.wrapMode = TextureWrapMode.Clamp;

        Color32[] colors = new Color32[resolution * resolution * depth];
        for (int i = 0; i < colors.Length; i++)
        {
            int b = i * 4;
            colors[i] = new Color32(data[b], data[b + 1], data[b + 2], data[b + 3]);
        }

        tex.SetPixels32(colors);
        tex.Apply(updateMipmaps: false);

        // 4. 保存为 Asset
        string fileName = Path.GetFileNameWithoutExtension(path);
        string savePath = $"Assets/{fileName}_3D.asset";

        AssetDatabase.CreateAsset(tex, savePath);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        Debug.Log($"<color=green>转换成功！</color> 资源已保存在: {savePath}");
    }
}

// --- 以下是自定义编辑器代码，用于在 Inspector 显示按钮 ---
[CustomEditor(typeof(RawToTexture3D))]
public class RawToTexture3DEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector(); // 显示默认变量面板

        RawToTexture3D script = (RawToTexture3D)target;

        GUILayout.Space(10);
        GUI.backgroundColor = Color.cyan;

        if (GUILayout.Button("选择 RAW 文件并转换", GUILayout.Height(40)))
        {
            script.SelectAndConvert();
        }
    }
}

// 一个简单的只读特性装饰器
public class ReadOnlyAttribute : PropertyAttribute { }
[CustomPropertyDrawer(typeof(ReadOnlyAttribute))]
public class ReadOnlyDrawer : PropertyDrawer
{
    public override void OnGUI(Rect position, SerializedProperty property, GUIContent label)
    {
        GUI.enabled = false;
        EditorGUI.PropertyField(position, property, label);
        GUI.enabled = true;
    }
}
#endif
