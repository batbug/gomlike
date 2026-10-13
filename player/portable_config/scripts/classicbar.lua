-- classicbar.lua — классическая панель управления под видео (тёмная, оранжевый акцент)
-- Настройки: portable_config/script-opts/classicbar.conf

local mp = require 'mp'
local options = require 'mp.options'

local o = {
    accent = 'EF9F27',        -- цвет акцента RRGGBB
    accent_dark = 'BA7517',
    panel = '232326',         -- фон панели
    height = 64,              -- высота панели в пикселях (при масштабе 100%)
    hide_timeout = 1.5,       -- через сколько секунд прятать панель в полноэкранном режиме
    remaining_time = false,   -- показывать оставшееся время вместо общего
    icon_font = 'MaterialIconsRound-Regular',
}
options.read_options(o, 'classicbar')

-- ---------- цвета ----------
local function bgr(hex) return hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2) end
local C = {
    accent = bgr(o.accent), accent_dark = bgr(o.accent_dark), panel = bgr(o.panel),
    track = bgr('3A3A3D'), buffered = bgr('4A4A4E'), hover = bgr('34343A'),
    icon = bgr('C8C8C8'), icon_hi = bgr('FFFFFF'), text = bgr('E8E8E8'), dim = bgr('8A8A8A'),
    dark = bgr('1C1C1E'), sep = bgr('3A3A3D'), tip = bgr('111113'),
}

-- ---------- состояние ----------
local st = {
    w = 0, h = 0, scale = 1, mx = -1, my = -1, inside = false,
    pos = nil, dur = nil, cache = nil, pause = false, vol = 100, mute = false, speed = 1,
    fs = false, idle = true, visible = true, dragging = nil, hovered = nil,
    remaining = o.remaining_time, margin = -1, bound = false,
}
local elements, panel_top, seek_area, vol_area = {}, 0, nil, nil
local ov = mp.create_osd_overlay('ass-events')
ov.z = -1
local dirty = true
local hide_timer

-- ---------- рисование ----------
local function f(n) return string.format('%.1f', n) end
local HEAD = '{\\an7\\pos(0,0)\\bord0\\shad0\\blur0\\1c&H%s&\\1a&H%s&\\p1}'

local function rect(a, x1, y1, x2, y2, col, alpha)
    a[#a + 1] = string.format(HEAD, col, alpha or '00') ..
        table.concat({'m', f(x1), f(y1), 'l', f(x2), f(y1), f(x2), f(y2), f(x1), f(y2)}, ' ') .. '{\\p0}'
end

local function rrect(a, x1, y1, x2, y2, r, col, alpha)
    r = math.min(r, (x2 - x1) / 2, (y2 - y1) / 2)
    local c = r * 0.5523
    local p = {
        'm', x1 + r, y1, 'l', x2 - r, y1,
        'b', x2 - r + c, y1, x2, y1 + r - c, x2, y1 + r,
        'l', x2, y2 - r,
        'b', x2, y2 - r + c, x2 - r + c, y2, x2 - r, y2,
        'l', x1 + r, y2,
        'b', x1 + r - c, y2, x1, y2 - r + c, x1, y2 - r,
        'l', x1, y1 + r,
        'b', x1, y1 + r - c, x1 + r - c, y1, x1 + r, y1,
    }
    for i, v in ipairs(p) do if type(v) == 'number' then p[i] = f(v) end end
    a[#a + 1] = string.format(HEAD, col, alpha or '00') .. table.concat(p, ' ') .. '{\\p0}'
end

local function circle(a, cx, cy, r, col, alpha)
    rrect(a, cx - r, cy - r, cx + r, cy + r, r, col, alpha)
end

local function text(a, x, y, s, size, col, align)
    a[#a + 1] = string.format('{\\an%d\\pos(%s,%s)\\bord0\\shad0\\blur0\\fs%s\\1c&H%s&}%s',
        align or 4, f(x), f(y), f(size), col, s)
end

local function icon(a, x, y, name, size, col)
    a[#a + 1] = string.format('{\\an5\\pos(%s,%s)\\bord0\\shad0\\blur0\\fn%s\\fs%s\\1c&H%s&}%s',
        f(x), f(y), o.icon_font, f(size), col, name)
end

local function fmt_time(t)
    if not t or t < 0 then t = 0 end
    t = math.floor(t)
    return string.format('%02d:%02d:%02d', math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
end

local function text_w(s, size)
    local n = 0
    for _ in s:gmatch('[^\128-\191]') do n = n + 1 end
    return n * size * 0.56
end

-- ---------- действия ----------
local function cmd(...) mp.commandv(...) end
local function uosc(name) return function() cmd('script-binding', 'uosc/' .. name) end end

-- ---------- окно выбора файла (обычное окно Windows) ----------
local is_windows = package.config:sub(1, 1) == '\\'
local dialog_busy = false

local EXTS = 'mkv;mp4;avi;mov;wmv;flv;webm;m4v;mpg;mpeg;ts;m2ts;mts;vob;3gp;ogv;divx;rm;rmvb;asf;f4v;' ..
    'mp3;flac;m4a;aac;ogg;opus;wav;wma;ape'

local function open_dialog()
    if not is_windows then cmd('script-binding', 'uosc/open-file'); return end
    if dialog_busy then return end
    dialog_busy = true
    local dir = ''
    local path = mp.get_property('path')
    if path and not path:find('://') then dir = path:match('^(.*)[\\/]') or '' end
    local pat = '*.' .. EXTS:gsub(';', ';*.')
    -- Окно открывает отдельный процесс PowerShell, а Windows не пускает фоновый процесс
    -- поверх активного окна. Поэтому скрытая форма-владелец диалога становится «дочерней»
    -- для окна плеера (диалог всегда над ним) и забирает фокус через AttachThreadInput.
    -- Код на C# компилируется один раз в %TEMP%. Двойных кавычек в -Command нет:
    -- Windows PowerShell их портит, QQ заменяется на кавычку уже внутри PowerShell.
    local hwnd = string.format('%d', mp.get_property_number('window-id', 0) or 0)
    local fg = table.concat({
        'using System; using System.Runtime.InteropServices;',
        'public static class GomLikeFg {',
        '[DllImport(QQuser32.dllQQ)] static extern IntPtr GetForegroundWindow();',
        '[DllImport(QQuser32.dllQQ)] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);',
        '[DllImport(QQkernel32.dllQQ)] static extern uint GetCurrentThreadId();',
        '[DllImport(QQuser32.dllQQ)] static extern bool AttachThreadInput(uint a, uint b, bool attach);',
        '[DllImport(QQuser32.dllQQ)] static extern bool SetForegroundWindow(IntPtr h);',
        '[DllImport(QQuser32.dllQQ)] static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);',
        'public static void Take(IntPtr mine, IntPtr owner) {',
        '  if (owner != IntPtr.Zero) SetWindowLongPtr(mine, -8, owner);',
        '  uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero), me = GetCurrentThreadId();',
        '  if (fg != me) AttachThreadInput(fg, me, true);',
        '  SetForegroundWindow(mine);',
        '  if (fg != me) AttachThreadInput(fg, me, false);',
        '} }',
    }, ' ')
    local ps = table.concat({
        "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
        "Add-Type -AssemblyName System.Windows.Forms",
        "$dll = Join-Path $env:TEMP 'gomlike-dialog-1.dll'",
        "if (-not (Test-Path $dll)) { Add-Type -OutputAssembly $dll -TypeDefinition ('" .. fg .. "' -replace 'QQ', [char]34) }",
        "Add-Type -Path $dll",
        "$o = New-Object System.Windows.Forms.Form",
        "$o.TopMost = $true; $o.ShowInTaskbar = $false; $o.StartPosition = 'Manual'",
        "$o.Location = New-Object System.Drawing.Point(-32000, -32000); $o.Size = New-Object System.Drawing.Size(1, 1)",
        "$o.Show(); [GomLikeFg]::Take($o.Handle, [IntPtr][int64]" .. hwnd .. "); $o.Activate()",
        "$d = New-Object System.Windows.Forms.OpenFileDialog",
        "$d.Multiselect = $true",
        "$d.Title = 'Открыть файл'",
        "$d.Filter = 'Видео и аудио|" .. pat .. "|Все файлы|*.*'",
        "$d.InitialDirectory = '" .. dir:gsub("'", "''") .. "'",
        "if ($d.ShowDialog($o) -eq [System.Windows.Forms.DialogResult]::OK) { $d.FileNames }",
        "$o.Close()",
    }, '\n')
    mp.command_native_async({
        name = 'subprocess', playback_only = false, capture_stdout = true,
        args = {'powershell', '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', ps},
    }, function(ok, res)
        dialog_busy = false
        if not ok or not res or not res.stdout then return end
        local first = true
        for line in res.stdout:gmatch('[^\r\n]+') do
            cmd('loadfile', line, first and 'replace' or 'append')
            first = false
        end
    end)
end

local actions = {
    play = function() cmd('cycle', 'pause') end,
    stop = function() mp.set_property_bool('pause', true); cmd('seek', '0', 'absolute') end,
    prev = uosc('prev'), next = uosc('next'), open = open_dialog,
    subs = uosc('subtitles'), audio = uosc('audio'),
    -- то же системное меню Windows, что и по правому клику (пункты в menu.conf)
    menu = function() cmd('script-binding', 'select/context-menu') end,
    mute = function() cmd('cycle', 'mute') end,
    fullscreen = function() cmd('cycle', 'fullscreen') end,
    time = function() st.remaining = not st.remaining; dirty = true end,
    speed = function() mp.set_property_number('speed', 1) end,
}

local tips = {
    play = 'Пауза / воспроизведение (Пробел)', stop = 'Стоп', prev = 'Предыдущий файл (PgUp)',
    next = 'Следующий файл (PgDn)', open = 'Открыть файл (Ctrl+O)', subs = 'Субтитры (Alt+S)',
    audio = 'Звуковая дорожка (Alt+A)', list = 'Плейлист (колесико мыши, F8)', menu = 'Меню',
    mute = 'Без звука (M)', fullscreen = 'Полный экран (Enter)', speed = 'Сбросить скорость (Z)',
    time = 'Показать оставшееся время', image = 'Настройки изображения (F7)',
    ['eqrot-l'] = 'Повернуть влево', ['eqrot-r'] = 'Повернуть вправо',
    ['eqflip-h'] = 'Отразить по горизонтали', ['eqflip-v'] = 'Отразить по вертикали',
}
local function tip_for(id)
    if id:find('^eqval:') then return 'Сбросить' end
    return tips[id]
end

-- ---------- изображение: цвет, поворот, отражение, масштаб ----------
local EQ = {
    {'brightness', 'Яркость'}, {'contrast', 'Контраст'}, {'saturation', 'Насыщенность'},
    {'gamma', 'Гамма'}, {'hue', 'Оттенок'},
}
local EQ_NAMES = {}
for _, e in ipairs(EQ) do EQ_NAMES[e[1]] = e[2] end
st.eq = {}

local function signed(v)
    v = math.floor(v + 0.5)
    return v > 0 and '+' .. v or tostring(v)
end
local function zoom_pct(z) return math.floor(2 ^ (z or st.zoom or 0) * 100 + 0.5) .. '%' end

local function view_reset()
    mp.set_property_number('video-zoom', 0)
    mp.set_property_number('video-pan-x', 0)
    mp.set_property_number('video-pan-y', 0)
end

-- отражение — шейдерами на видеокарте: фильтры vf hflip/vflip не работают с аппаратным декодированием
local FLIP = {h = '~~/shaders/hflip.glsl', v = '~~/shaders/vflip.glsl'}

local function image_reset()
    for _, e in ipairs(EQ) do mp.set_property_number(e[1], 0) end
    mp.set_property_number('video-rotate', 0)
    if st.hflip then cmd('change-list', 'glsl-shaders', 'remove', FLIP.h) end
    if st.vflip then cmd('change-list', 'glsl-shaders', 'remove', FLIP.v) end
    view_reset()
end

-- горячие клавиши из input.conf: script-message-to classicbar adjust|zoom|pan|view-reset
-- при зажатой клавише mpv повторяет её 40 раз в секунду, это слишком быстро:
-- пропускаем повторы чаще заданной частоты
local last_rep = {}
local function too_soon(kind, per_sec)
    local t = mp.get_time()
    if last_rep[kind] and t - last_rep[kind] < 1 / per_sec then return true end
    last_rep[kind] = t
    return false
end

mp.register_script_message('adjust', function(prop, d)
    if not EQ_NAMES[prop] or too_soon('adjust', 25) then return end
    cmd('no-osd', 'add', prop, d)
    mp.osd_message(EQ_NAMES[prop] .. ': ' .. signed(mp.get_property_number(prop, 0)))
end)
-- масштаб от 25% до 800%; при зажатой клавише — примерно вдвое за секунду
mp.register_script_message('zoom', function(d)
    if too_soon('zoom', 10) then return end
    local z = math.max(-2, math.min(mp.get_property_number('video-zoom', 0) + tonumber(d), 3))
    mp.set_property_number('video-zoom', z)
    mp.osd_message('Масштаб: ' .. zoom_pct(z))
end)
-- pan x|y <шаг> или pan xy <шаг по x> <шаг по y> (по диагонали)
mp.register_script_message('pan', function(axis, d, d2)
    if too_soon('pan', 20) then return end
    if axis == 'xy' then
        cmd('no-osd', 'add', 'video-pan-x', d)
        cmd('no-osd', 'add', 'video-pan-y', d2)
    else
        cmd('no-osd', 'add', 'video-pan-' .. axis, d)
    end
end)
-- перемотка стрелками: seek <секунды>, с надписью «Вперёд 5 сек · 00:01:23 / 00:20:00».
-- При зажатой стрелке mpv складывает быстрые перемотки, поэтому считаем от прошлой цели,
-- а не от time-pos, который ещё не успел обновиться
local seek_target, seek_time, seek_label
local function seek_osd(pos)
    local dur = mp.get_property_number('duration')
    mp.osd_message(seek_label .. ' · ' .. fmt_time(pos) .. (dur and ' / ' .. fmt_time(dur) or ''))
end
mp.register_script_message('seek', function(d)
    d = tonumber(d)
    if not d or st.idle or too_soon('seek', 10) then return end
    local dur = mp.get_property_number('duration')
    local base = seek_time and mp.get_time() - seek_time < 0.5 and seek_target or mp.get_property_number('time-pos', 0)
    seek_target = math.max(0, dur and math.min(base + d, dur) or base + d)
    seek_time = mp.get_time()
    cmd('no-osd', 'seek', tostring(d))
    local a = math.abs(d)
    seek_label = (d < 0 and 'Назад ' or 'Вперёд ') .. (a >= 60 and a % 60 == 0 and (a / 60) .. ' мин' or a .. ' сек')
    seek_osd(seek_target)
end)
-- mpv перематывает к ближайшему ключевому кадру: когда перемотка закончилась,
-- показываем время, где видео встало на самом деле
mp.register_event('playback-restart', function()
    if seek_time and mp.get_time() - seek_time < 1.5 then
        seek_osd(mp.get_property_number('time-pos', 0))
    end
end)

mp.register_script_message('view-reset', function()
    view_reset()
    mp.osd_message('Масштаб: 100%')
end)

actions['eqrot-l'] = function() mp.set_property_number('video-rotate', ((st.rotate or 0) + 270) % 360) end
actions['eqrot-r'] = function() mp.set_property_number('video-rotate', ((st.rotate or 0) + 90) % 360) end
actions['eqflip-h'] = function() cmd('change-list', 'glsl-shaders', 'toggle', FLIP.h) end
actions['eqflip-v'] = function() cmd('change-list', 'glsl-shaders', 'toggle', FLIP.v) end
actions.eqreset = image_reset

-- ---------- раскладка и отрисовка ----------
local function panel_shown() return not st.fs or st.visible end

local base_sub_margin = mp.get_property_number('sub-margin-y', 22)
local function update_margin()
    local m = 0
    if not st.fs and st.h > 0 then m = math.floor(o.height * st.scale + 0.5) / st.h end
    if math.abs(m - st.margin) > 1e-6 then
        st.margin = m
        mp.set_property_number('video-margin-ratio-bottom', m)
    end
    -- субтитры не должны прятаться под панелью: приподнимаем их, пока она видна
    local sm = base_sub_margin
    if (not st.fs or st.visible) and st.h > 0 then
        sm = base_sub_margin + math.floor(o.height * st.scale * 720 / st.h + 0.5)
    end
    if sm ~= st.sub_margin then
        st.sub_margin = sm
        mp.set_property_number('sub-margin-y', sm)
    end
end

-- ---------- плейлист ----------
local pl_box
local function basename(p) return p:gsub('[\\/]+$', ''):match('[^\\/]+$') or p end
local function strip_ext(n) return n:match('^(.+)%.[^.]+$') or n end
local function esc(str) return (str:gsub('\\', '\\\226\129\160'):gsub('{', '\\{'):gsub('[\r\n]', ' ')) end
local function fit(str, width, size)
    local maxc = math.max(4, math.floor(width / (size * 0.47)))
    local chars = {}
    for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = ch end
    if #chars <= maxc then return str end
    return table.concat(chars, '', 1, maxc - 1) .. '…'
end

local function draw_playlist(a)
    pl_box = nil
    if not st.pl_open then return end
    local w, h, s = st.w, st.h, st.scale
    local list = st.playlist or {}
    local n = #list
    local x2, y1 = w, 0
    local x1 = w - math.min(420 * s, w * 0.45)
    local y2 = panel_shown() and panel_top or h
    pl_box = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
    rect(a, x1, y1, x2, y2, C.panel, '10')
    rect(a, x1, y1, x1 + 1 * s, y2, C.sep)

    local hh = 38 * s
    text(a, x1 + 14 * s, y1 + hh / 2, 'Плейлист', 15 * s, C.text, 4)
    text(a, x1 + 14 * s + text_w('Плейлист', 15 * s) + 8 * s, y1 + hh / 2, tostring(n), 13 * s, C.dim, 4)
    local cx = x2 - 8 * s - 28 * s
    if st.hovered == 'plclose' then rrect(a, cx, y1 + 5 * s, cx + 28 * s, y1 + hh - 5 * s, 4 * s, C.hover) end
    icon(a, cx + 14 * s, y1 + hh / 2, 'close', 18 * s, st.hovered == 'plclose' and C.icon_hi or C.icon)
    elements[#elements + 1] = {id = 'plclose', x1 = cx, y1 = y1 + 5 * s, x2 = cx + 28 * s, y2 = y1 + hh - 5 * s}
    rect(a, x1, y1 + hh, x2, y1 + hh + 1 * s, C.sep)

    local rh = 28 * s
    local top = y1 + hh + 4 * s
    local rows = math.max(1, math.floor((y2 - top - 4 * s) / rh))
    st.pl_rows = rows
    local maxscroll = math.max(0, n - rows)
    st.pl_scroll = math.max(0, math.min(st.pl_scroll or 0, maxscroll))
    for i = st.pl_scroll + 1, math.min(n, st.pl_scroll + rows) do
        local e = list[i]
        local ry = top + (i - st.pl_scroll - 1) * rh
        local id = 'pl:' .. i
        local cur = e.current or e.playing
        if st.hovered == id then rect(a, x1 + 1 * s, ry, x2, ry + rh, C.hover) end
        text(a, x1 + 34 * s, ry + rh / 2, tostring(i), 12 * s, C.dim, 6)
        if cur then icon(a, x1 + 48 * s, ry + rh / 2, 'play_arrow', 16 * s, C.accent) end
        local nx = x1 + 60 * s
        local name = e.title or strip_ext(basename(e.filename or ''))
        text(a, nx, ry + rh / 2, esc(fit(name, x2 - nx - 14 * s, 13 * s)), 13 * s, cur and C.accent or C.text, 4)
        elements[#elements + 1] = {id = id, x1 = x1 + 1 * s, y1 = ry, x2 = x2, y2 = ry + rh}
    end
    if maxscroll > 0 then
        local th = math.max(20 * s, (y2 - top) * rows / n)
        local ty = top + (y2 - top - th) * st.pl_scroll / maxscroll
        rrect(a, x2 - 5 * s, ty, x2 - 2 * s, ty + th, 1.5 * s, C.buffered)
    end
end

-- ---------- панель изображения (F7) ----------
local eq_box, eq_tracks
local function draw_eq(a)
    eq_box, eq_tracks = nil, {}
    if not st.eq_open then return end
    -- невысокая широкая полоса над панелью управления, как в GOM:
    -- слева ползунки в две колонки, справа поворот, отражение и сброс
    local s = st.scale
    local hh, rh, bs = 28 * s, 26 * s, 28 * s
    -- если открыт плейлист, полоса помещается слева от него
    local room = st.pl_open and st.w - math.min(420 * s, st.w * 0.45) or st.w
    local bw = math.min(800 * s, room - 24 * s)
    local x1 = (room - bw) / 2
    local x2 = x1 + bw
    local rw = 4 * bs + 3 * 4 * s + 24 * s
    local rx1 = x2 - rw
    -- ползунки в две колонки, а в узком окне — в одну
    local cols = (rx1 - x1) / 2 - 154 * s >= 80 * s and 2 or 1
    local rows = math.ceil(#EQ / cols)
    local cw = (rx1 - x1) / cols
    local y2 = (panel_shown() and panel_top or st.h) - 8 * s
    local y1 = y2 - (hh + rows * rh + 12 * s)
    eq_box = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
    rrect(a, x1, y1, x2, y2, 6 * s, C.panel, '10')

    -- заголовок
    text(a, x1 + 12 * s, y1 + hh / 2, 'Изображение', 13 * s, C.text, 4)
    local cx = x2 - 6 * s - 24 * s
    if st.hovered == 'eqclose' then rrect(a, cx, y1 + 3 * s, cx + 24 * s, y1 + hh - 3 * s, 4 * s, C.hover) end
    icon(a, cx + 12 * s, y1 + hh / 2, 'close', 16 * s, st.hovered == 'eqclose' and C.icon_hi or C.icon)
    elements[#elements + 1] = {id = 'eqclose', x1 = cx, y1 = y1 + 3 * s, x2 = cx + 24 * s, y2 = y1 + hh - 3 * s}
    rect(a, x1, y1 + hh, x2, y1 + hh + 1 * s, C.sep)

    local top = y1 + hh + 6 * s
    rect(a, rx1, top, rx1 + 1 * s, y2 - 6 * s, C.sep)

    -- ползунки цвета: от -100 до 100, ноль посередине
    for i, e in ipairs(EQ) do
        local prop, label = e[1], e[2]
        local v = st.eq[prop] or 0
        local cx1 = x1 + math.floor((i - 1) / rows) * cw
        local ry = top + ((i - 1) % rows) * rh
        local cy = ry + rh / 2
        local tx1, tx2 = cx1 + 104 * s, cx1 + cw - 50 * s
        local mid = (tx1 + tx2) / 2
        local active = st.hovered == 'eq:' .. prop or st.dragging == 'eq:' .. prop
        text(a, cx1 + 12 * s, cy, label, 12 * s, C.text, 4)
        rrect(a, tx1, cy - 2 * s, tx2, cy + 2 * s, 2 * s, C.track)
        rect(a, mid - 0.5 * s, cy - 4 * s, mid + 0.5 * s, cy + 4 * s, C.dim)
        local px = tx1 + (tx2 - tx1) * (math.max(-100, math.min(v, 100)) + 100) / 200
        if math.abs(px - mid) > 1 then
            rrect(a, math.min(px, mid), cy - 2 * s, math.max(px, mid), cy + 2 * s, 2 * s, C.accent)
        end
        circle(a, px, cy, (active and 6.5 or 5.5) * s, C.icon_hi)
        elements[#elements + 1] = {id = 'eq:' .. prop, x1 = tx1 - 8 * s, y1 = ry, x2 = tx2 + 8 * s, y2 = ry + rh}
        eq_tracks[prop] = {x1 = tx1, x2 = tx2}
        local vid, vx2 = 'eqval:' .. prop, cx1 + cw - 8 * s
        if st.hovered == vid and math.abs(v) >= 0.5 then
            rrect(a, vx2 - 38 * s, cy - 10 * s, vx2, cy + 10 * s, 4 * s, C.hover)
        end
        text(a, vx2 - 6 * s, cy, signed(v), 12 * s, math.abs(v) >= 0.5 and C.accent or C.dim, 6)
        elements[#elements + 1] = {id = vid, x1 = vx2 - 38 * s, y1 = cy - 10 * s, x2 = vx2, y2 = cy + 10 * s}
    end

    -- справа: поворот и отражение, состояние, сброс
    local bx = rx1 + 12 * s
    local by = top + rh / 2
    local function ibtn(id, name, on)
        if st.hovered == id then rrect(a, bx, by - bs / 2, bx + bs, by + bs / 2, 4 * s, C.hover) end
        icon(a, bx + bs / 2, by, name, 20 * s, on and C.accent or (st.hovered == id and C.icon_hi or C.icon))
        elements[#elements + 1] = {id = id, x1 = bx, y1 = by - bs / 2, x2 = bx + bs, y2 = by + bs / 2}
        bx = bx + bs + 4 * s
    end
    ibtn('eqrot-l', 'rotate_left')
    ibtn('eqrot-r', 'rotate_right')
    ibtn('eqflip-h', 'swap_horiz', st.hflip)
    ibtn('eqflip-v', 'swap_vert', st.vflip)
    local state = {}
    if (st.rotate or 0) ~= 0 then state[#state + 1] = st.rotate .. '°' end
    if (st.zoom or 0) ~= 0 then state[#state + 1] = 'масштаб ' .. zoom_pct() end
    if #state > 0 then text(a, rx1 + 12 * s, top + rh * 1.5, table.concat(state, ', '), 12 * s, C.accent, 4) end

    local label = 'Сбросить всё'
    local lw = text_w(label, 12 * s) + 16 * s
    local lx, ly = rx1 + 8 * s, top + rh * 2.5
    if st.hovered == 'eqreset' then rrect(a, lx, ly - 11 * s, lx + lw, ly + 11 * s, 4 * s, C.hover) end
    text(a, lx + lw / 2, ly, label, 12 * s, st.hovered == 'eqreset' and C.icon_hi or C.text, 5)
    elements[#elements + 1] = {id = 'eqreset', x1 = lx, y1 = ly - 11 * s, x2 = lx + lw, y2 = ly + 11 * s}
end

-- ---------- верхняя полоса в полноэкранном режиме (как в GOM) ----------
-- появляется, когда мышь у верхнего края: название и кнопки окна
local function topbar_h() return 36 * st.scale end

actions['tb-fs'] = function() mp.set_property_bool('fullscreen', false) end
actions['tb-min'] = function() mp.set_property_bool('window-minimized', true) end
actions['tb-max'] = function()
    mp.set_property_bool('fullscreen', false)
    mp.set_property_bool('window-maximized', true)
end
actions['tb-close'] = function() cmd('quit') end
tips['tb-fs'] = 'Выйти из полноэкранного режима (Esc)'
tips['tb-min'] = 'Свернуть'
tips['tb-max'] = 'Развернуть в окно'
tips['tb-close'] = 'Закрыть'

local function draw_topbar(a)
    if not (st.fs and st.top) then return end
    local s, w = st.scale, st.w
    local th, bw = topbar_h(), 46 * s
    rect(a, 0, 0, w, th, C.panel)
    local bx = w - 4 * bw
    local function tbtn(id, name, size, hover_col)
        local hov = st.hovered == id
        if hov then rect(a, bx, 0, bx + bw, th, hover_col or C.hover) end
        icon(a, bx + bw / 2, th / 2, name, size * s, hov and C.icon_hi or C.icon)
        elements[#elements + 1] = {id = id, x1 = bx, y1 = 0, x2 = bx + bw, y2 = th}
        bx = bx + bw
    end
    tbtn('tb-fs', 'fullscreen_exit', 20)
    tbtn('tb-min', 'remove', 18)
    tbtn('tb-max', 'crop_square', 16)
    tbtn('tb-close', 'close', 20, bgr('E81123'))
    -- как в заголовке окна (title в mpv.conf): «Фильм.avi - GomLike»
    local title = (st.title and st.title ~= '' and st.title .. ' - ' or '') .. 'GomLike'
    text(a, 14 * s, th / 2, esc(fit(title, w - 4 * bw - 28 * s, 13 * s)), 13 * s, C.text, 4)
end

local function render()
    dirty = false
    local w, h, s = st.w, st.h, st.scale
    if w <= 0 or h <= 0 then return end
    update_margin()
    local a = {}
    elements, seek_area, vol_area = {}, nil, nil

    if st.idle then
        icon(a, w / 2, h / 2 - 40 * s, 'folder_open', 64 * s, C.accent)
        text(a, w / 2, h / 2 + 20 * s, 'Дважды щёлкни, чтобы открыть файл, или перетащи его сюда', 20 * s, C.dim, 5)
        elements[#elements + 1] = {id = 'open', x1 = w / 2 - 60 * s, y1 = h / 2 - 80 * s, x2 = w / 2 + 60 * s, y2 = h / 2}
    end

    if not panel_shown() then
        draw_topbar(a)
        draw_eq(a)
        draw_playlist(a)
        ov.res_x, ov.res_y, ov.data = w, h, table.concat(a, '\n')
        ov:update()
        return
    end

    local H = o.height * s
    local top = h - H
    panel_top = top
    rect(a, 0, top, w, h, C.panel)

    -- полоса перемотки
    local sx1, sx2, sy = 12 * s, w - 12 * s, top + 12 * s
    seek_area = {x1 = sx1 - 6 * s, x2 = sx2 + 6 * s, y1 = top, y2 = top + 22 * s, tx1 = sx1, tx2 = sx2}
    rrect(a, sx1, sy - 3 * s, sx2, sy + 3 * s, 3 * s, C.track)
    local dur = st.dur or 0
    if dur > 0 then
        if st.cache and st.cache > 0 then
            local b = math.min(st.cache / dur, 1)
            rrect(a, sx1, sy - 3 * s, sx1 + (sx2 - sx1) * b, sy + 3 * s, 3 * s, C.buffered)
        end
        local p = math.max(0, math.min((st.pos or 0) / dur, 1))
        local px = sx1 + (sx2 - sx1) * p
        if px > sx1 + 1 then rrect(a, sx1, sy - 3 * s, px, sy + 3 * s, 3 * s, C.accent) end
        local over_seek = st.hovered == 'seek' or st.dragging == 'seek'
        circle(a, px, sy, (over_seek and 7 or 5.5) * s, C.icon_hi)
    end

    -- ряд кнопок
    local cy = top + 41 * s
    local bs = 30 * s
    local function button(id, x, name, size, col)
        local x1, x2 = x, x + bs
        if st.hovered == id then rrect(a, x1, cy - bs / 2, x2, cy + bs / 2, 4 * s, C.hover) end
        icon(a, (x1 + x2) / 2, cy, name, (size or 22) * s,
            col or (st.hovered == id and C.icon_hi or C.icon))
        elements[#elements + 1] = {id = id, x1 = x1, y1 = cy - bs / 2, x2 = x2, y2 = cy + bs / 2}
        return x2
    end
    local function sep(x)
        rect(a, x, cy - 10 * s, x + 1 * s, cy + 10 * s, C.sep)
        return x + 1 * s
    end

    -- левая часть
    local x = 10 * s
    local r = 18 * s
    circle(a, x + r, cy, r, st.hovered == 'play' and C.accent_dark or C.accent)
    icon(a, x + r, cy, (st.pause or st.idle) and 'play_arrow' or 'pause', 26 * s, C.dark)
    elements[#elements + 1] = {id = 'play', x1 = x, y1 = cy - r, x2 = x + 2 * r, y2 = cy + r}
    x = x + 2 * r + 6 * s

    local time_str
    if st.remaining and dur > 0 then
        time_str = '-' .. fmt_time(dur - (st.pos or 0))
    else
        time_str = fmt_time(st.pos) .. ' / ' .. fmt_time(dur)
    end
    local ts = 14 * s
    local time_w = text_w(time_str, ts) + 20 * s
    local sp = math.abs(st.speed - 1) > 0.001 and string.format('%.2gx', st.speed)
    local spw = sp and text_w(sp, 14 * s) + 12 * s or 0

    -- что помещается: в узком окне по очереди прячем меню/плейлист/изображение (вместе
    -- с временем), ползунок громкости, субтитры и дорожку, потом стоп/назад/вперёд/открыть;
    -- пуск, звук и полный экран видны всегда
    local tiers = {
        {extra = true, vol = true, tracks = true, left = true},
        {vol = true, tracks = true, left = true},
        {tracks = true, left = true},
        {left = true},
        {},
    }
    local show
    for _, t in ipairs(tiers) do
        show = t
        local need = x + (t.left and 4 * bs or 0) -- левая часть
            + 10 * s + bs + (t.vol and 132 * s or 4 * s) + bs + 14 * s -- полный экран, громкость, звук
            + (t.tracks and 2 * bs or 0) + (t.extra and 3 * bs + time_w or 0) + spw + 8 * s
        if need <= w then break end
    end

    if show.left then
        x = button('stop', x, 'stop')
        x = button('prev', x, 'skip_previous')
        x = button('next', x, 'skip_next')
        x = button('open', x, 'folder_open', 20)
    end
    local left_end = x

    -- правая часть (справа налево)
    local rx = w - 10 * s
    rx = rx - bs; button('fullscreen', rx, st.fs and 'fullscreen_exit' or 'fullscreen', 24)
    if show.vol then
        rx = rx - 40 * s
        text(a, rx + 36 * s, cy, math.floor(st.vol + 0.5) .. '%', 13 * s, C.dim, 6)
        local vx2, vx1 = rx - 6 * s, rx - 86 * s
        rrect(a, vx1, cy - 2 * s, vx2, cy + 2 * s, 2 * s, C.track)
        local vfrac = st.mute and 0 or math.min(st.vol / 100, 1)
        if vfrac > 0 then rrect(a, vx1, cy - 2 * s, vx1 + (vx2 - vx1) * vfrac, cy + 2 * s, 2 * s, C.accent) end
        if st.hovered == 'vol' or st.dragging == 'vol' then circle(a, vx1 + (vx2 - vx1) * vfrac, cy, 6 * s, C.icon_hi) end
        vol_area = {x1 = vx1 - 6 * s, x2 = vx2 + 6 * s, y1 = cy - 12 * s, y2 = cy + 12 * s, tx1 = vx1, tx2 = vx2}
        rx = vx1 - 6 * s - bs
    else
        rx = rx - 4 * s - bs
    end
    local vicon = (st.mute or st.vol <= 0) and 'volume_off' or (st.vol < 50 and 'volume_down' or 'volume_up')
    button('mute', rx, vicon)
    rx = rx - 8 * s; sep(rx); rx = rx - 6 * s
    if show.extra then
        rx = rx - bs; button('menu', rx, 'tune')
        rx = rx - bs; button('list', rx, 'queue_music')
        rx = rx - bs; button('image', rx, 'brightness_6', 20, st.eq_open and C.accent or nil)
    end
    if show.tracks then
        rx = rx - bs; button('audio', rx, 'audiotrack', 20)
        rx = rx - bs; button('subs', rx, 'subtitles')
    end
    if sp then
        rx = rx - spw
        if st.hovered == 'speed' then rrect(a, rx, cy - bs / 2, rx + spw, cy + bs / 2, 4 * s, C.hover) end
        text(a, rx + spw / 2, cy, sp, 14 * s, C.accent, 5)
        elements[#elements + 1] = {id = 'speed', x1 = rx, y1 = cy - bs / 2, x2 = rx + spw, y2 = cy + bs / 2}
    end

    -- время
    if left_end + 10 * s + time_w < rx then
        x = sep(left_end + 8 * s) + 10 * s
        text(a, x, cy, time_str, ts, st.hovered == 'time' and C.icon_hi or C.text, 4)
        elements[#elements + 1] = {id = 'time', x1 = x, y1 = cy - bs / 2, x2 = x + time_w - 10 * s, y2 = cy + bs / 2}
    end

    draw_topbar(a)
    draw_eq(a)
    draw_playlist(a)

    -- подсказки: над панелью управления или над кнопкой панели изображения
    local tip, tx, ty2
    if (st.hovered == 'seek' or st.dragging == 'seek') and dur > 0 and seek_area then
        local fr = math.max(0, math.min((st.mx - sx1) / (sx2 - sx1), 1))
        tip, tx = fmt_time(fr * dur), st.mx
    elseif st.hovered and tip_for(st.hovered) and not st.dragging and not st.menu and not st.hovered:find('^pl') then
        tip = tip_for(st.hovered)
        if st.hovered == 'time' and st.remaining then tip = 'Показать общее время' end
        for _, e in ipairs(elements) do
            if e.id == st.hovered then
                tx = (e.x1 + e.x2) / 2
                if e.id:find('^eq') then ty2 = e.y1 - 4 * s end
                if e.id:find('^tb%-') then ty2 = e.y2 + 28 * s end
            end
        end
    end
    if tip and tx then
        local fs = 13 * s
        local tw = text_w(tip, fs) + 16 * s
        local tx1 = math.max(4 * s, math.min(tx - tw / 2, w - tw - 4 * s))
        ty2 = ty2 or top - 6 * s
        rrect(a, tx1, ty2 - 24 * s, tx1 + tw, ty2, 4 * s, C.tip, '30')
        text(a, tx1 + tw / 2, ty2 - 12 * s, tip, fs, C.text, 5)
    end

    ov.res_x, ov.res_y, ov.data = w, h, table.concat(a, '\n')
    ov:update()
end

-- ---------- мышь ----------
local function in_box(b, x, y) return b and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 end

local function hit(x, y)
    if in_box(seek_area, x, y) then return 'seek' end
    if in_box(vol_area, x, y) then return 'vol' end
    for _, e in ipairs(elements) do if in_box(e, x, y) then return e.id end end
    return nil
end

local function seek_to(x, exact)
    if not seek_area or not st.dur or st.dur <= 0 then return end
    local fr = math.max(0, math.min((x - seek_area.tx1) / (seek_area.tx2 - seek_area.tx1), 1))
    cmd('seek', tostring(fr * 100), exact and 'absolute-percent+exact' or 'absolute-percent+keyframes')
end

local function eq_to(id, x)
    local prop = id:sub(4)
    local tr = eq_tracks and eq_tracks[prop]
    if not tr then return end
    local fr = math.max(0, math.min((x - tr.x1) / (tr.x2 - tr.x1), 1))
    mp.set_property_number(prop, math.floor(fr * 200 - 100 + 0.5))
end

local function vol_to(x)
    local fr = math.max(0, math.min((x - vol_area.tx1) / (vol_area.tx2 - vol_area.tx1), 1))
    mp.set_property_number('volume', math.floor(fr * 100 + 0.5))
    if st.mute then mp.set_property_bool('mute', false) end
end

local function on_left(t)
    if t.event == 'down' then
        local id = hit(st.mx, st.my)
        if id == 'seek' then st.dragging = 'seek'; seek_to(st.mx, false)
        elseif id == 'vol' then st.dragging = 'vol'; vol_to(st.mx)
        elseif id and id:find('^eq:') then st.dragging = id; eq_to(id, st.mx)
        else st.pressed = id end
        dirty = true
    elseif t.event == 'up' then
        if st.dragging == 'seek' then seek_to(st.mx, true) end
        st.dragging = nil
        -- кнопки срабатывают на отпускание, чтобы открытые меню не закрывались тем же кликом
        local id = st.pressed
        st.pressed = nil
        if id and hit(st.mx, st.my) == id then
            if id:sub(1, 3) == 'pl:' then
                cmd('playlist-play-index', tostring(tonumber(id:sub(4)) - 1))
            elseif id:find('^eqval:') then
                mp.set_property_number(id:sub(7), 0)
            elseif actions[id] then
                actions[id]()
            end
        end
        dirty = true
    end
end

local function over_ui(x, y)
    if st.idle and hit(x, y) == 'open' then return true end
    if st.pl_open and in_box(pl_box, x, y) then return true end
    if st.eq_open and in_box(eq_box, x, y) then return true end
    if st.fs and st.top and y <= topbar_h() then return true end
    return panel_shown() and y >= panel_top - 2
end

-- колесо: над плейлистом прокручивает список, над ползунком изображения двигает его,
-- над панелью меняет громкость
local function wheel(dir)
    if st.eq_open and in_box(eq_box, st.mx, st.my) then
        local id = hit(st.mx, st.my)
        if id and id:find('^eq:') then cmd('add', id:sub(4), tostring(-dir * 2)) end
    elseif st.pl_open and in_box(pl_box, st.mx, st.my) then
        st.pl_scroll = (st.pl_scroll or 0) + dir * 3
        dirty = true
    else
        cmd('add', 'volume', tostring(-dir * 5))
    end
end

local function toggle_playlist()
    st.pl_open = not st.pl_open
    if st.pl_open then
        local cur = (mp.get_property_number('playlist-pos', 0) or 0) + 1
        st.pl_scroll = math.max(0, cur - math.floor((st.pl_rows or 12) / 2))
        mp.add_forced_key_binding('ESC', 'classicbar-plesc', toggle_playlist)
        if st.fs then st.visible = true end
    else
        mp.remove_key_binding('classicbar-plesc')
        st.hovered = nil
    end
    dirty = true
end
actions.list = toggle_playlist
actions.plclose = toggle_playlist
mp.add_key_binding(nil, 'playlist', toggle_playlist)

local function toggle_eq()
    st.eq_open = not st.eq_open
    if st.eq_open then
        mp.add_forced_key_binding('ESC', 'classicbar-eqesc', toggle_eq)
        if st.fs then st.visible = true end
    else
        mp.remove_key_binding('classicbar-eqesc')
        st.hovered = nil
    end
    dirty = true
end
actions.image = toggle_eq
actions.eqclose = toggle_eq
mp.add_key_binding(nil, 'image', toggle_eq)

-- над панелями окно нельзя таскать мышью: иначе mpv начинает перетаскивать окно,
-- Windows сразу присылает «кнопка отпущена», и ползунки не тянутся
local window_dragging = mp.get_property_bool('window-dragging', true)

local function set_bindings(on)
    if on == st.bound then return end
    st.bound = on
    mp.set_property_bool('window-dragging', window_dragging and not on)
    if on then
        mp.add_forced_key_binding('MBTN_LEFT', 'classicbar-left', on_left, {complex = true})
        mp.add_forced_key_binding('MBTN_LEFT_DBL', 'classicbar-dbl', function() end)
        mp.add_forced_key_binding('WHEEL_UP', 'classicbar-wup', function() wheel(-1) end)
        mp.add_forced_key_binding('WHEEL_DOWN', 'classicbar-wdown', function() wheel(1) end)
    else
        mp.remove_key_binding('classicbar-left')
        mp.remove_key_binding('classicbar-dbl')
        mp.remove_key_binding('classicbar-wup')
        mp.remove_key_binding('classicbar-wdown')
    end
end

local function show_panel()
    if not st.fs then return end
    if not st.visible then st.visible = true; dirty = true end
    hide_timer:kill()
    hide_timer:resume()
end

mp.observe_property('mouse-pos', 'native', function(_, m)
    if not m then return end
    local moved = m.x ~= st.mx or m.y ~= st.my
    st.mx, st.my, st.inside = m.x, m.y, m.hover
    local top = st.fs and m.hover and m.y <= topbar_h() or false
    if top ~= st.top then st.top = top; dirty = true end
    if moved then show_panel() end
    if st.dragging == 'seek' then seek_to(st.mx, false)
    elseif st.dragging == 'vol' then vol_to(st.mx)
    elseif st.dragging and st.dragging:find('^eq:') then eq_to(st.dragging, st.mx) end
    local id = m.hover and over_ui(m.x, m.y) and hit(m.x, m.y) or nil
    if id ~= st.hovered then st.hovered = id; dirty = true end
    set_bindings(st.dragging ~= nil or (m.hover and over_ui(m.x, m.y)))
end)

hide_timer = mp.add_timeout(o.hide_timeout, function()
    if st.fs and not st.dragging and not st.pl_open and not st.eq_open and not (st.inside and st.my >= panel_top) then
        st.visible = false
        -- мышь может стоять на верхней полосе: её кнопки должны и дальше нажиматься
        local over = st.inside and over_ui(st.mx, st.my)
        st.hovered = over and hit(st.mx, st.my) or nil
        set_bindings(over)
        dirty = true
    elseif st.fs then
        hide_timer:resume()
    end
end)
hide_timer:kill()

-- ---------- свойства ----------
local function watch(name, key, fn)
    mp.observe_property(name, 'native', function(_, v)
        if fn then fn(v) else st[key] = v end
        dirty = true
    end)
end
watch('time-pos', 'pos')
watch('duration', 'dur')
watch('demuxer-cache-time', 'cache')
watch('pause', 'pause')
watch('volume', 'vol', function(v) st.vol = v or 100 end)
watch('mute', 'mute')
watch('speed', 'speed', function(v) st.speed = v or 1 end)
watch('idle-active', 'idle', function(v) st.idle = v and true or false end)
watch('display-hidpi-scale', 'scale', function(v) st.scale = (v and v > 0) and v or 1 end)
watch('osd-dimensions', nil, function(v)
    if v then st.w, st.h = v.w, v.h end
end)
watch('user-data/uosc/menu/type', 'menu')
watch('media-title', 'title')
watch('playlist', 'playlist', function(v) st.playlist = v or {} end)
for _, e in ipairs(EQ) do
    watch(e[1], nil, function(v) st.eq[e[1]] = v or 0 end)
end
watch('video-rotate', 'rotate', function(v) st.rotate = tonumber(v) or 0 end)
watch('video-zoom', 'zoom')
watch('glsl-shaders', nil, function(v)
    st.hflip, st.vflip = false, false
    for _, p in ipairs(v or {}) do
        if p == FLIP.h then st.hflip = true elseif p == FLIP.v then st.vflip = true end
    end
end)
watch('fullscreen', 'fs', function(v)
    st.fs = v and true or false
    st.visible = true
    if st.fs then hide_timer:kill(); hide_timer:resume() else hide_timer:kill() end
end)

mp.add_key_binding(nil, 'open', open_dialog)
-- клик по видео — пауза (с маленькой задержкой, чтобы не мешать двойному клику),
-- двойной клик — полный экран, на пустом экране — открыть файл
local click_timer, last_dbl = nil, 0
local function dbl_time() return (mp.get_property_number('input-doubleclick-time', 300) + 50) / 1000 end

mp.add_key_binding(nil, 'click', function()
    if st.idle or mp.get_time() - last_dbl < dbl_time() then return end
    if click_timer then click_timer:kill() end
    click_timer = mp.add_timeout(dbl_time(), function()
        click_timer = nil
        cmd('cycle', 'pause')
    end)
end)

mp.add_key_binding(nil, 'dblclick', function()
    last_dbl = mp.get_time()
    if click_timer then click_timer:kill(); click_timer = nil end
    if st.idle then open_dialog() else cmd('cycle', 'fullscreen') end
end)

mp.add_periodic_timer(1 / 30, function() if dirty then render() end end)
