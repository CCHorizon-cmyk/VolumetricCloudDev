using UnityEngine;

public class SimpleFlyCamera : MonoBehaviour
{
    [Header("目标对象")]
    public Transform targetTransform;   // 指定要控制的对象

    [Header("移动")]
    public float maxSpeed = 10f;
    public float acceleration = 20f;

    [Header("视角")]
    public bool enableMouseLook = true;
    public float mouseSensitivity = 2f;
    public bool invertY = false;

    private Vector3 currentVelocity;
    private float rotationX;
    private float rotationY;

    private void Start()
    {
        // 如果没有指定目标，则控制自身
        if (targetTransform == null)
            targetTransform = transform;

        Vector3 euler = targetTransform.eulerAngles;
        rotationX = euler.y;
        rotationY = euler.x;
        LockCursor();
    }

    private void Update()
    {
        // Debug.Log("FlyCamera Update"); // 可按需开启
        // 保持光标锁定
        if (enableMouseLook && Cursor.lockState != CursorLockMode.Locked)
            LockCursor();

        HandleMouseLook();
        HandleMovement();
    }

    void LockCursor()
    {
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    void HandleMouseLook()
    {
        if (!enableMouseLook) return;

        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity * (invertY ? 1f : -1f);

        rotationX += mouseX;
        rotationY += mouseY;
        rotationY = Mathf.Clamp(rotationY, -90f, 90f);

        targetTransform.rotation = Quaternion.Euler(rotationY, rotationX, 0f);
    }

    void HandleMovement()
    {
        float h = Input.GetAxis("Horizontal");
        float v = Input.GetAxis("Vertical");

        Vector3 moveDir = (targetTransform.forward * v + targetTransform.right * h).normalized;

        if (moveDir.sqrMagnitude > 0.01f)
            currentVelocity = Vector3.MoveTowards(currentVelocity, moveDir * maxSpeed, acceleration * Time.deltaTime);
        else
            currentVelocity = Vector3.MoveTowards(currentVelocity, Vector3.zero, acceleration * Time.deltaTime);

        targetTransform.position += currentVelocity * Time.deltaTime;
    }
}