param([Parameter(Mandatory = $true)][string]$Dest, [string]$Icon)
# Downloads the latest mpv build for Windows and puts it into $Dest (used by GomLike-Setup.exe).
# mpv.exe / mpv.com become GomLike.exe / GomLike.com; with -Icon the exe gets that icon
# (mpv takes its window and taskbar icon from its own exe resources).
$ErrorActionPreference = 'Stop'

# Replaces the icon group of an exe with the images of an .ico file, keeping the group's
# name (mpv loads it as IDI_ICON1) and language
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

public static class ExeIcon {
    const uint RT_ICON = 3, RT_GROUP_ICON = 14;
    delegate bool EnumNameProc(IntPtr h, IntPtr type, IntPtr name, IntPtr p);
    delegate bool EnumLangProc(IntPtr h, IntPtr type, IntPtr name, ushort lang, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string file, IntPtr h, uint flags);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumResourceNames(IntPtr h, IntPtr type, EnumNameProc cb, IntPtr p);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumResourceLanguages(IntPtr h, IntPtr type, IntPtr name, EnumLangProc cb, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResource(string file, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool UpdateResource(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool EndUpdateResource(IntPtr h, bool discard);

    class Res { public object Name; public ushort Lang; }

    static List<Res> List(IntPtr module, uint type) {
        var names = new List<object>();
        EnumResourceNames(module, (IntPtr)type, (h, t, n, p) => {
            names.Add(((long)n >> 16) == 0 ? (object)(int)(long)n : Marshal.PtrToStringUni(n));
            return true;
        }, IntPtr.Zero);
        var all = new List<Res>();
        foreach (var name in names) {
            IntPtr np = Ptr(name);
            EnumResourceLanguages(module, (IntPtr)type, np, (h, t, n, l, p) => {
                all.Add(new Res { Name = name, Lang = l });
                return true;
            }, IntPtr.Zero);
            Free(name, np);
        }
        return all;
    }

    static IntPtr Ptr(object name) { return name is int ? (IntPtr)(int)name : Marshal.StringToHGlobalUni((string)name); }
    static void Free(object name, IntPtr p) { if (!(name is int)) Marshal.FreeHGlobal(p); }

    static void Update(IntPtr h, uint type, object name, ushort lang, byte[] data) {
        IntPtr np = Ptr(name);
        try {
            if (!UpdateResource(h, (IntPtr)type, np, lang, data, data == null ? 0 : (uint)data.Length))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        } finally { Free(name, np); }
    }

    public static void Set(string exe, string ico) {
        byte[] ic = File.ReadAllBytes(ico);
        int count = BitConverter.ToUInt16(ic, 4);

        IntPtr module = LoadLibraryEx(exe, IntPtr.Zero, 0x22); // as datafile + image resource
        if (module == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        List<Res> icons, groups;
        try { icons = List(module, RT_ICON); groups = List(module, RT_GROUP_ICON); }
        finally { FreeLibrary(module); }
        object groupName = groups.Count > 0 ? groups[0].Name : "IDI_ICON1";
        ushort lang = groups.Count > 0 ? groups[0].Lang : (ushort)1033;

        IntPtr h = BeginUpdateResource(exe, false);
        if (h == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        bool ok = false;
        try {
            foreach (var r in groups) Update(h, RT_GROUP_ICON, r.Name, r.Lang, null);
            foreach (var r in icons) Update(h, RT_ICON, r.Name, r.Lang, null);
            var group = new MemoryStream();
            group.Write(ic, 0, 6); // reserved, type 1, count
            for (int i = 0; i < count; i++) {
                int e = 6 + 16 * i;
                int size = BitConverter.ToInt32(ic, e + 8), offset = BitConverter.ToInt32(ic, e + 12);
                byte[] img = new byte[size];
                Array.Copy(ic, offset, img, 0, size);
                Update(h, RT_ICON, i + 1, lang, img);
                group.Write(ic, e, 12); // width, height, colors, reserved, planes, bit count, size
                group.Write(BitConverter.GetBytes((ushort)(i + 1)), 0, 2);
            }
            Update(h, RT_GROUP_ICON, groupName, lang, group.ToArray());
            ok = true;
        } finally {
            if (!EndUpdateResource(h, !ok) && ok) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tmp = Join-Path $env:TEMP ("gomlike_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Output "Looking up latest mpv build..."
    $rel = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest' -Headers @{ 'User-Agent' = 'GomLike-Setup' }
    $asset = $rel.assets | Where-Object { $_.name -match '^mpv-x86_64-\d{8}-git-[0-9a-f]+\.7z$' } | Select-Object -First 1
    if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match '^mpv-x86_64-.*\.7z$' -and $_.name -notmatch 'v3' } | Select-Object -First 1 }
    if (-not $asset) { throw "mpv archive not found in release $($rel.tag_name)" }

    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'GomLike-Setup')
    Write-Output ("Downloading {0} ({1} MB)..." -f $asset.name, [math]::Round($asset.size / 1MB))
    $archive = Join-Path $tmp $asset.name
    $wc.DownloadFile($asset.browser_download_url, $archive)

    Write-Output "Downloading 7zr.exe from 7-zip.org..."
    $sevenZip = Join-Path $tmp '7zr.exe'
    $wc.DownloadFile('https://www.7-zip.org/a/7zr.exe', $sevenZip)

    Write-Output "Extracting..."
    $out = Join-Path $tmp 'mpv'
    & $sevenZip x $archive "-o$out" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "extraction failed" }
    $exe = Get-ChildItem $out -Recurse -Filter 'mpv.exe' | Select-Object -First 1
    if (-not $exe) { throw "mpv.exe not found in archive" }

    # The player is GomLike.exe with our icon; mpv.com is renamed too, it starts the exe with its own name
    $dir = $exe.DirectoryName
    Rename-Item (Join-Path $dir 'mpv.exe') 'GomLike.exe'
    if (Test-Path (Join-Path $dir 'mpv.com')) { Rename-Item (Join-Path $dir 'mpv.com') 'GomLike.com' }
    if ($Icon) {
        Write-Output "Setting GomLike icon..."
        [ExeIcon]::Set((Join-Path $dir 'GomLike.exe'), (Resolve-Path $Icon).Path)
    }
    $exe = Get-Item (Join-Path $dir 'GomLike.exe')

    # Only the player itself: no updater, no stock installer or file association scripts
    $skip = @('portable_config', 'installer', 'updater.bat', 'updater.ps1', 'mpv-register.bat', 'mpv-unregister.bat')
    $items = Get-ChildItem $exe.DirectoryName | Where-Object { $skip -notcontains $_.Name }
    foreach ($i in $items) { Copy-Item $i.FullName -Destination $Dest -Recurse -Force }
    $items | ForEach-Object { $_.Name } | Set-Content -Path (Join-Path $Dest 'gomlike-files.txt') -Encoding ASCII

    # Where this exact mpv build comes from (mpv is GPLv2+, see licenses\mpv)
    $src = @(
        "mpv build: $($asset.name)",
        "Build release: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/$($rel.tag_name)",
        "Build scripts: https://github.com/shinchiro/mpv-winbuild-cmake"
    )
    if ($asset.name -match '-git-([0-9a-f]+)\.7z$') { $src += "mpv source: https://github.com/mpv-player/mpv/tree/$($Matches[1])" }
    $src | Set-Content -Path (Join-Path $Dest 'mpv-source.txt') -Encoding ASCII
    if (-not (Test-Path (Join-Path $Dest 'GomLike.exe'))) { throw "GomLike.exe was not copied" }
    Write-Output "mpv installed."
    exit 0
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    exit 1
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
