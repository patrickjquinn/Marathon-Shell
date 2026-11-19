#version 440
// The globe: a sphere of dots on an equal-area lattice (each row has as
// many dots as its circumference holds), land from an equirectangular mask,
// the places with stations from a second one, lit and shaded on a dark
// field. Every pixel is ray-cast; nothing is meshed.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // the item, px
    float radius;       // the globe's radius, px
    float lon0;         // the longitude facing the viewer, radians
    float lat0;         // the latitude facing the viewer, radians
    float dotStep;      // lattice spacing, radians
    vec4 landColor;
    vec4 seaColor;
    vec4 bodyColor;
    vec4 stationColor;
    vec4 rimColor;
};

layout(binding = 1) uniform sampler2D land;
layout(binding = 2) uniform sampler2D places;

const float PI = 3.14159265;
const float TAU = 6.28318531;

void main()
{
    vec2 p = (qt_TexCoord0 - 0.5) * size / radius;
    float r = length(p);
    float px = 1.0 / radius;
    if (r > 1.0) {
        // A thin halo, gone within a tenth of the radius.
        float halo = exp(-(r - 1.0) * 28.0) * 0.55;
        fragColor = rimColor * halo * qt_Opacity;
        return;
    }
    float z = sqrt(1.0 - r * r);
    vec3 v = vec3(p.x, -p.y, z);
    // From view to world: tilt back by the latitude, then turn by the longitude.
    float cl = cos(lat0), sl = sin(lat0);
    vec3 a = vec3(v.x, v.y * cl + v.z * sl, -v.y * sl + v.z * cl);
    float co = cos(lon0), so = sin(lon0);
    vec3 w = vec3(a.x * co + a.z * so, a.y, -a.x * so + a.z * co);
    float lat = asin(clamp(w.y, -1.0, 1.0));
    float lon = atan(w.x, w.z);

    // The nearest lattice dot.
    float latc = floor(lat / dotStep + 0.5) * dotStep;
    float n = max(1.0, floor(TAU * cos(latc) / dotStep + 0.5));
    float lonStep = TAU / n;
    float lonc = floor(lon / lonStep + 0.5) * lonStep;
    float dlon = mod(lon - lonc + PI, TAU) - PI;
    float dist = length(vec2(lat - latc, dlon * cos(lat)));

    vec2 uv = vec2(lonc / TAU + 0.5, 0.5 - latc / PI);
    float isLand = smoothstep(0.35, 0.65, texture(land, uv).r);
    float station = texture(places, uv).r;

    // Dots shrink towards the rim with the surface; a pixel of softening.
    float soft = px / max(z, 0.2);
    float rdot = dotStep * mix(0.26, 0.38, station);
    float dotMask = 1.0 - smoothstep(rdot - soft, rdot + soft, dist);

    // Places glow by how much radio they have: a lone station dimly, a
    // city of them at full strength.
    vec4 dotColor = mix(seaColor, landColor, isLand);
    float glow = smoothstep(0.5, 1.0, station);
    vec4 lit = stationColor * (0.55 + 0.45 * glow);
    dotColor = mix(dotColor, lit, step(0.25, station));
    float light = 0.30 + 0.70 * z;
    vec4 col = bodyColor * (0.55 + 0.45 * z);
    col = mix(col, dotColor * light, dotMask);
    // A rim of light where the sphere turns away.
    col += rimColor * pow(1.0 - z, 3.0) * 0.45;
    // Antialiased edge of the disc.
    col *= 1.0 - smoothstep(1.0 - 1.5 * px, 1.0, r);
    fragColor = col * qt_Opacity;
}
