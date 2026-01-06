shader_type canvas_item;

uniform vec2 center = vec2(0.5);
uniform int stripes = 24;
uniform float speed : hint_range(0.0, 5.0, 0.001) = 0.2;
uniform int direction : hint_range(-1, 1, 2) = 1;
uniform vec4 stripe_colors[8];
uniform int color_count : hint_range(1, 8) = 2;

void fragment() {
    vec2 uv_deriv = fwidthFine(UV);
    float aspect_ratio = uv_deriv.y / uv_deriv.x;
    vec2 corrected_uv = UV * vec2(aspect_ratio, 1.0);
    vec2 corrected_center = center * vec2(aspect_ratio, 1.0);

    vec2 dir = corrected_center - corrected_uv;
    float angle = atan(dir.y, dir.x) - (TIME * speed * float(direction));

    int stripe_index = int(floor(angle / (TAU / float(stripes)))) % stripes;
    int color_index = stripe_index % color_count;
    color_index = clamp(color_index, 0, color_count - 1);

    // Apply the color
    COLOR.rgb = stripe_colors[color_index].rgb;
}
