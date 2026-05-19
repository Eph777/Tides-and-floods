#version 150

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:light.glsl>
#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:sample_lightmap.glsl>
#moj_import <physicsmod:ocean_vanilla.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;

uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;
out vec3 lightColor;
out vec2 texCoord0;

out vec3 physics_localPosition;
out float physics_localWaviness;

void main() {
	physics_localWaviness = physics_waviness;
	vec3 finalPosition = vec3(Position.x, Position.y + physics_waveHeight(Position.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), Position.z);
    physics_localPosition = finalPosition;
    
	vec4 cameraSpacePos = ModelViewMat * vec4(Position, 1.0);
    gl_Position = ProjMat * ModelViewMat * vec4(finalPosition, 1.0);

    sphericalVertexDistance = fog_spherical_distance(cameraSpacePos.xyz);
    // this is used for render distance stuff however we are in cameraSpace so no cylindrical calculation will work
    // just ignore it for now and hope minecraft someday implements proper model matrix uploads
    cylindricalVertexDistance = fog_cylindrical_distance(cameraSpacePos.xyz);
    vec4 tmpColor = sample_lightmap(Sampler2, UV2);
    vertexColor = tmpColor * Color;
    lightColor = tmpColor.rgb;
    
    texCoord0 = (TextureMat * vec4(UV0, 0.0, 1.0)).xy;
}
