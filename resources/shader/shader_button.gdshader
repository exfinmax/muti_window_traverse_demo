shader_type canvas_item;

uniform vec2 size = vec2(0.);
uniform vec2 center1 = vec2(0.);
uniform vec2 center2 = vec2(0.);
uniform float time1 : hint_range(0., 1.) = 0.;
uniform float time2 : hint_range(0., 1.) = 0.;
uniform float width1 : hint_range(0., 0.5) = 0.05;
uniform float width2 : hint_range(0., 0.5) = 0.1;
uniform float corner_radius : hint_range(0., 1.) = 0.0; // 圆角参数，0-1范围
uniform float glow : hint_range(0., 10.) = 0.;
uniform vec4 color : source_color = vec4(1.);

// 圆角矩形距离场函数
float rounded_box(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

// 胶囊形状距离场函数
float capsule(vec2 p, float r, float length) {
    p.x = abs(p.x) - length/2.0;
    p.x = max(p.x, 0.0);
    return length(p) - r;
}

void fragment() {
	float aspect_ratio = size.x / size.y;
	vec2 uv = UV - vec2(0.5);
	uv.x *= aspect_ratio;

	// 根据圆角参数平滑过渡
	float capsule_distance;

	if (corner_radius == 0.0) {
		// 完全矩形
		vec2 rect_size = vec2(aspect_ratio * 0.5, 0.5);
		capsule_distance = rounded_box(uv, rect_size, 0.0);
	} else if (corner_radius == 1.0) {
		// 完全胶囊形状
		float capsule_radius = 0.5;
		float capsule_length = aspect_ratio - 1.0;
		capsule_distance = capsule(uv, capsule_radius, capsule_length);
	} else {
		// 平滑过渡：使用圆角矩形，圆角半径从0到0.5线性变化
		float radius_factor = corner_radius;
		float actual_radius = 0.5 * radius_factor; // 最大圆角半径为0.5（胶囊形状）

		vec2 rect_size = vec2(aspect_ratio * 0.5, 0.5);
		capsule_distance = rounded_box(uv, rect_size, actual_radius);
	}

	bool in_capsule = capsule_distance <= 0.0;

	// 计算辉光效果 - 使用主颜色作为辉光颜色
	float glow_alpha = 0.0;
	if (glow > 0.0) {
		// 辉光从胶囊边缘向外扩散
		float glow_distance = -capsule_distance;
		float glow_falloff = smoothstep(0.0, width2, glow_distance);
		glow_alpha = (1.0 - glow_falloff) * color.a * glow;

		// 限制辉光只在胶囊外部显示
		glow_alpha *= step(0.0, glow_distance);
	}

	// 计算涟漪和高光效果
	vec2 center1_uv = (UV - center1);
	center1_uv.x *= aspect_ratio;
	float center1_d = length(center1_uv);

	vec2 center2_uv = (UV - center2);
	center2_uv.x *= aspect_ratio;
	float center2_d = length(center2_uv);

	float max_center1_radius = max(aspect_ratio, 1.0) * 0.8;

	// 修改涟漪效果为模糊圆环
	float outer_radius = 0.1 + (max_center1_radius - 0.1) * time1;

	// 修改：内圆半径随时间从0.1倍到1.2倍逐渐缩小
	float inner_radius_factor = mix(0.1, 1.2, time1);
	float inner_radius = outer_radius * inner_radius_factor;

	// 使用模糊边缘创建圆环效果
	float ring = smoothstep(inner_radius - 0.20, inner_radius + 0.20, center1_d) -
				 smoothstep(outer_radius - 0.20, outer_radius + 0.20, center1_d);

	// 高光效果保持不变
	float circle2_blur = smoothstep(center2_d - 0.2, center2_d + 0.2, 0.1 + (max_center1_radius - 0.1) * time2 - 0.2);

	// 边缘区域检测
	bool in_edge_area = abs(capsule_distance) <= width1 && in_capsule;

	if (in_capsule) {
		float circle1_alpha = max(ring - max(time1, 0.1), 0.0);
		float circle2_alpha = in_edge_area ? circle2_blur : circle2_blur * 0.05;  // 内圆透明度

		vec3 final_color = color.rgb;
		float final_alpha = max(circle1_alpha, circle2_alpha);

		// 混合辉光效果 - 使用相同的颜色
		vec4 base_color = vec4(final_color, final_alpha);
		vec4 glow_layer = vec4(color.rgb, glow_alpha);

		COLOR = base_color + glow_layer;
	} else {
		// 只在胶囊外部显示辉光 - 使用相同的颜色
		COLOR = vec4(color.rgb, glow_alpha);
	}
}