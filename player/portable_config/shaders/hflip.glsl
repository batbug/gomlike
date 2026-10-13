// GomLike: отражение картинки по горизонтали (панель изображения, F7)
//!HOOK MAIN
//!BIND HOOKED
//!DESC GomLike hflip
vec4 hook() { return HOOKED_tex(vec2(1.0 - HOOKED_pos.x, HOOKED_pos.y)); }
