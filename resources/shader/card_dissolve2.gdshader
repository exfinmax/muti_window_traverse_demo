shader_type canvas_item;

uniform sampler2D pre_melting_gradient; // mixes with base color
uniform sampler2D falling_gradient;     // override base color

uniform float animation_progress : hint_range(0.0, 1.0); //[0..1] progress of animation
uniform float random_influence = 0.05;
uniform vec2 melting_point = vec2(0.5); // point where melting starts in uv coordinates
uniform vec2 atlas_size = vec2(1.);     // frames in spritesheet

uniform float melting_time = 0.1;
uniform float falling_time = 0.2;

uniform int fall_distance = 16;

float noise(vec3 vec){
    float random = dot(vec, vec3(12.9898, 78.233, 37.719));
    random = fract(random);
    return random;
}

float get_melting_progress(float _animation_progress){
	float sum = melting_time + 1. + falling_time;
	float a = melting_time/sum;
	float b = 1./sum;

	return (_animation_progress - a)/b;
}

float get_melting_progress_to_point(float _animation_progress, vec2 uv, vec2 texture_pixel_size){
	uv = floor(uv / texture_pixel_size) * texture_pixel_size;

	float distance_from_center = distance(uv, melting_point) / sqrt(2);
	float progress = get_melting_progress(_animation_progress) - distance_from_center;
	float rand = noise(vec3(uv, 0.)) * random_influence - random_influence * 0.5;

	return progress + rand;
}

float get_falling_progress(float _animation_progress, vec2 uv, vec2 texture_pixel_size){
	float progress = get_melting_progress_to_point(_animation_progress, uv, texture_pixel_size);

	progress /= falling_time;
	progress = min(max(progress, 0.), 1.);

	return progress;
}

void fragment() {
	// snapping uv to pixels
	vec2 uv_whole = floor(UV / TEXTURE_PIXEL_SIZE) * TEXTURE_PIXEL_SIZE;
	vec2 uv = fract(uv_whole * atlas_size);
	vec2 texel = TEXTURE_PIXEL_SIZE / atlas_size;

	float progress = get_melting_progress_to_point(animation_progress, uv, texel);

	// melting
	if (progress > 0.){
		COLOR.a = 0.;
	}else{
		float melting_progress = (progress + melting_time) / melting_time;
		melting_progress = min(max(melting_progress, 0), 1);

		if (melting_progress > 0.){
			vec4 melt_color = texture(pre_melting_gradient, vec2(melting_progress, 0.));
			melt_color.a *= COLOR.a;
			COLOR = mix(COLOR, melt_color, melt_color.a);
		}
	}

	// pixels falling from above
	vec4 falling_color = vec4(0.);
	for (float height = 0.; height < float(fall_distance); height += 0.33){
		vec2 fall_uv = uv_whole + vec2(0., -1. * height) * texel;
		vec2 fall_uv_fract = fract(fall_uv * atlas_size);

		float f_progress = get_falling_progress(animation_progress, fall_uv_fract, texel);
		float pixel_distance = (f_progress * f_progress * float(fall_distance)) - height;

		if (pixel_distance > 0. && abs(pixel_distance) < 0.5 && fall_uv_fract.y > 0.){
			vec4 particle_color = texture(falling_gradient, vec2(f_progress, 0.));
			particle_color.a *= texture(TEXTURE, fall_uv).a;
			falling_color = mix(falling_color, particle_color, particle_color.a);
		}
	}

	COLOR = mix(COLOR, falling_color, falling_color.a);
}
