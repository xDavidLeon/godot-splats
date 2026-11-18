// Shows the resolved splat picture, one art pixel to many screen pixels with no filtering. A pixel is
// drawn fully or not at all, so alpha stays 0 or 1. Ported from a Unity shader of the same design.
// (Unity's version also converts sRGB to linear, because that project renders in linear; Godot's 2D
// canvas takes the picture's sRGB values as they are.)
// Put it on a TextureRect or Sprite2D whose texture is the scene's picture and whose texture filter
// is Nearest.
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0);
}
