// Rune ring: glyph-like marks along an ellipse inscribed in the sprite.
// Uniforms: u_time (seconds, from SpriteKit), u_pulse (0...1 flare), u_rune_color (rgba).
// The sprite texture is a faint ring; its alpha gates where marks may show.

void main() {
  vec4 base = texture2D(u_texture, v_tex_coord);
  vec2 p = v_tex_coord * 2.0 - 1.0;
  float radius = length(p);
  float angle = atan(p.y, p.x) + 3.14159265;
  float segments = 36.0;
  float cell = angle / 6.2831853 * segments;
  float index = floor(cell);
  float local = fract(cell);

  // Each segment gets a mark whose shape depends on a cheap hash of its index.
  float h = fract(sin(index * 12.9898) * 43758.5453);
  float bar = step(0.42, local) * step(local, 0.58);
  float cross = step(0.25, local) * step(local, 0.75) * step(0.5, h);
  float tick = mix(bar, max(bar, cross * 0.8), step(0.33, h));
  float band = smoothstep(0.78, 0.84, radius) * (1.0 - smoothstep(0.90, 0.96, radius));
  float marks = tick * band;

  float glow = 0.55 + 0.25 * sin(u_time * 1.2 + index * 0.7);
  float flare = u_pulse * (0.6 + 0.4 * sin(u_time * 6.0 - radius * 8.0));
  float strength = marks * (glow + flare);
  float halo = base.a * (0.35 + 0.35 * u_pulse + 0.1 * sin(u_time * 0.8));

  float alpha = clamp(max(strength, halo * 0.6), 0.0, 1.0) * u_rune_color.a;
  gl_FragColor = vec4(u_rune_color.rgb * alpha, alpha);
}
