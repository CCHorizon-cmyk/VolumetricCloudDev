using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

public class LightDirPasseer : MonoBehaviour
{
    public Material _Material;
    public Vector4 _LightDirection;
    public string _LightDir;


    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        _Material.SetVector(_LightDir, _LightDirection);



    }
}
