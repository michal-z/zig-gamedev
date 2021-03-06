#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX)"

struct DrawConst {
    float4x4 object_to_clip;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);

[RootSignature(ROOT_SIGNATURE)]
void vsMain(
    float3 position : POSITION,
    float3 normal : _Normal,
    out float4 out_position_sv : SV_Position,
    out float3 out_normal : _Normal
) {
    out_position_sv = mul(float4(position, 1.0), cbv_draw_const.object_to_clip);
    out_normal = normal; // object-space normal
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(
    float4 position_window : SV_Position,
    float3 normal : _Normal,
    out float4 out_color : SV_Target0
) {
    out_color = float4(abs(normal), 1.0);
}
