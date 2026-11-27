# Low-end / max-FPS profile for 6 GB cards (for example an RTX 3050 Laptop)
# and modest CPUs: lower internal resolution with upscaling, hard caps that
# keep the card's memory under about 5 GB, and the gameplay-critical accuracy
# fixes left on.
#
#   .\scripts\play-lowend.ps1 -Exe 'D:\Games\MyDump\game_scarlett_master.exe'
#   .\scripts\play-lowend.ps1 -Exe ... -Mode ultraperformance   # most FPS, softest
#   .\scripts\play-lowend.ps1 -Exe ... -Mode balanced           # sharper, a little slower
#   .\scripts\play-lowend.ps1 -Exe ... -Res 4k                  # stock output (no 1440p patch)
#   .\scripts\play-lowend.ps1 -Exe ... -SeriesS                 # 720p scene, the fastest and softest
#   .\scripts\play-lowend.ps1 -Exe ... -More @{VICTORY_ROOM='x'} # any extra switch (wins over the preset)
#
# Run Get-NVIDIA-DLSS.cmd ONCE before the first start (about 70 MB of NVIDIA's
# own files, fetched from NVIDIA). Without them the game runs with its own
# upscaling at the full 1440p scene, which is heavy; the log then says no
# Streamline files were found.
#
# WHAT THIS SETS, AND WHY (all values are STARTING POINTS, not measurements on
# your card; nothing here has been measured on an RTX 3050 Laptop):
#
#   -Mode               DLSS Super Resolution mode. The scene renders at this
#                       fraction of the output: performance = 0.5 (1280x720 on
#                       a 1440p output), ultraperformance = 1/3 (about 854x480),
#                       balanced = 0.58 (about 1485x835), quality = 2/3 (about
#                       1706x960). Lower render size = more FPS and a softer
#                       picture. DLSS needs an RTX card; every RTX 20/30/40/50
#                       card supports Super Resolution. Default: performance.
#   -Res                Output. 1440 (default): 2560x1440 output, the 1440p
#                       patch of the retail build. 1080to1440: scene at
#                       1920x1080 upscaled by the title. 4k: the stock
#                       3840x2160 output (no patch; use this on non-retail
#                       builds, where the 1440p patch refuses to apply).
#   -TextureBudgetMB    Hard cap, in MB, on the card copies made from host
#                       copies of textures the title fills (the ones shaders
#                       pick by index). Default 1536. When the cap is reached,
#                       no more of those copies are made. If scenes texture
#                       visibly late (pop-in), raise it; if the card still
#                       thrashs, lower it.
#   -RoomPercent        Share of the card's budget the texture queue may fill
#                       (50-97, launcher default 86-90). Default 70. This is
#                       the main "stay under ~5 GB" knob.
#   -MemoryCardMB       Most of the title's memory kept on the card (default
#                       upstream: 4096); beyond it the side shaders see is in
#                       the PC's memory. Default 2048: frees card memory at the
#                       cost of slower reads over PC memory when exceeded.
#   -TargetsRoomMB      Room kept free for render targets the host makes
#                       (upstream default 3072). Default 1536, so textures get
#                       room on a 6 GB card. Too low: target starvation
#                       (log lines about no room, or target stalls); raise it
#                       if you see those.
#
# ALWAYS ON / ALWAYS OFF HERE
#   - Frame generation is NOT made ready (-NoFrameGenReady): it needs an
#     RTX 40 or later (and, for more than 2x, an RTX 50), plus hardware-
#     accelerated GPU scheduling. An RTX 3050 cannot do it. If you run this on
#     a newer card, use scripts\play-foxhound.ps1 -FrameGen instead.
#   - Ray tracing (VICTORY_BVH_BUILDER) stays off: it is slow and produces a
#     broken picture on this base, on any card.
#   - The two passes the standard launcher leaves out stay left out:
#     the decal heap's defragmentation (about 5.6 ms of GPU time a frame) and
#     the heat-haze pass (blocks of smeared pixels). GTA VI 1.0.2.1 is the only
#     supported title; it runs the same here, with those passes absent.
#   - The light estimate (VICTORY_AMBIENT=0.8, VICTORY_AMBIENT_SPECULAR,
#     VICTORY_AMBIENT_AIR) stays ON: without it, interiors are black.
#   - The texture read-back to the title's memory (boats' physics samples;
#     without it the boat sinks) stays ON, as upstream.
#
# THE F1 MENU vs THIS SCRIPT
#   The five settings above are passed as the script's parameters and ALWAYS
#   win over the F1 menu's saved file (victory-settings.txt is applied by the
#   underlying launcher first, this script's values are applied after it).
#   The menu still controls the frame rate cap, the output, resolution and
#   what it saves; to change DLSS mode or the four memory knobs, use this
#   script's parameters. The other knobs the F1 menu exposes are untouched.
#
# WHAT TO WATCH
#   In the game: F3 shows the stats panel (frame rate, VRAM). The log
#   (%LOCALAPPDATA%\victory\logs) has periodic memory lines. If you see
#   "no room" constantly, or the card reported near 100% of budget, lower
#   -RoomPercent by 5-10 or lower -TextureBudgetMB. If textures pop in
#   constantly, raise them.
#
# This script contains no game data. It wraps scripts\play-foxhound.ps1.

param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('1440', '1080to1440', '4k')][string]$Res = '1440',
    [ValidateSet('ultraperformance', 'performance', 'balanced', 'quality')][string]$Mode = 'performance',
    [ValidateSet('release', 'diag')][string]$Build = 'release',
    # Series S profile: 1280x720 scene, the fastest and softest option.
    [switch]$SeriesS,
    [ValidateRange(256, 8192)][int]$TextureBudgetMB = 1536,
    [ValidateRange(50, 97)][int]$RoomPercent = 70,
    [ValidateRange(512, 8192)][int]$MemoryCardMB = 2048,
    [ValidateRange(256, 8192)][int]$TargetsRoomMB = 1536,
    [hashtable]$More = @{}
)

if (-not (Test-Path -LiteralPath $Exe)) {
    Write-Host "No such file: $Exe"
    Write-Host "Point -Exe at your own dump of the title's game_scarlett_master.exe."
    exit 1
}

# The preset. These are applied AFTER victory-settings.txt is merged by the
# underlying launcher, so they always win while this script is used.
$switches = @{
    VICTORY_DLSS_MODE = $Mode
    VICTORY_TEXTURE_ROOM_PERCENT = [string]$RoomPercent
    VICTORY_TEXTURE_BUDGET_MB = [string]$TextureBudgetMB
    VICTORY_MEMORY_CARD_MB = [string]$MemoryCardMB
    VICTORY_CARD_ROOM_FOR_TARGETS_MB = [string]$TargetsRoomMB
}
# The caller's -More wins over the preset.
foreach ($key in @($More.Keys)) { $switches[[string]$key] = [string]$More[$key] }

# The underlying launcher has no 'ultraperformance' in its -Dlss set; give it
# 'performance' (a valid member) and let VICTORY_DLSS_MODE above select the
# real mode. They are applied in the same launcher pass, ours last.
$dlss = if ($Mode -eq 'ultraperformance') { 'performance' } else { $Mode }

Write-Host 'Low-end / max-FPS profile'
Write-Host "  output          $Res$(if ($SeriesS) { ', Series S profile' })"
Write-Host "  DLSS mode       $Mode (scene renders at the mode's scale of the output)"
Write-Host "  card memory     room $RoomPercent%% of budget, texture copies capped at ${TextureBudgetMB} MB,"
Write-Host "                  title memory on card capped at ${MemoryCardMB} MB, render-target room ${TargetsRoomMB} MB"
Write-Host '  frame gen       not made ready (needs RTX 40 or later; your card cannot do it)'
Write-Host '  note            values are starting points, not measurements on this card'
Write-Host ''

$forward = @{
    Exe = $Exe
    Build = $Build
    Res = $Res
    Dlss = $dlss
    NoFrameGenReady = $true
    More = $switches
}
if ($SeriesS) { $forward.SeriesS = $true }

& (Join-Path $PSScriptRoot 'play-foxhound.ps1') @forward
