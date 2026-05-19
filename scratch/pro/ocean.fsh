#version 150

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:fog.glsl>
#moj_import <physicsmod:ocean_vanilla.glsl>

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec4 vertexColor;
in vec3 lightColor;
in vec2 texCoord0;

in vec3 physics_localPosition;
in float physics_localWaviness;

out vec4 fragColor;

void main() {
    WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime);

	// VANILLA STYLE
	vec4 oceanColor = vec4(mix(wave.normal.x * 0.5 + 0.5, 0.0, pow(wave.normal.y, 4.0)));
    vec4 color = texture(Sampler0, texCoord0) * ColorModulator * vertexColor;
    color = clamp(color + (wave.foam + oceanColor * 0.3) * vec4(lightColor, 1.0), vec4(0.0), vec4(1.0));
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
