# ============================================================================
#  DEMENTE - v1.0.0.1
#  "Ayudarnos es la unica opcion"
#
#  FUSION COMPLETA:
#   - GUI XAML/WPF moderna
#   - Motor BlackEdition (diagnostico, optimizaciones, limpieza)
#   - Lazarus (optimizaciones de kernel + limpieza registro)
#   - Nitidus (transparencia de artefactos del sistema: Amcache, ShellBags,
#     USBSTOR, redes Wi-Fi guardadas -- SOLO LECTURA, no elimina evidencia
#     de uso; ver seccion "Transparencia" del panel de Seguridad)
#   - Mundus (75+ sectores de limpieza)
#   - Registro inteligente (auditoria verificable + limpieza segura con backup)
#   - YARA (deteccion de malware)
#
#  FILOSOFIA: Mostrar valor DEFAULT de Windows siempre
#             ACTUAL | DEFAULT WINDOWS | PROPUESTA DEMENTE
#
#  v1.0.0:
#   - Una sola Get-DiagnosticoCompleto (multi-area, sin puntaje falso)
#   - Previsualizacion antes de ejecutar
#   - Dashboard con ESTADO REAL legible
#   - Perfiles ESENCIAL / COMPLETO / DEFAULT WINDOWS por seccion
#   - Reversion segura al valor de fabrica de Windows
#
#  v1.0.0 (base):
#   - Una sola Get-DiagnosticoCompleto, preview, perfiles, reversion
#
#  v1.0.0.2:
#   - Transparencia Amcache/USBSTOR/ShellBags/Wi-Fi (solo lectura)
#   - Write-Host shim a streams estandar
#
#  v1.0.0.1 (release):
#   - Salud: bloque "Inicio y estabilidad" (antes "Configuracion") alineado
#     con categorias reales (Limpieza / Rendimiento / Reparacion). Sin
#     seccion fantasma en el menu.
#   - Limpieza profunda integrada (sin ventana externa de cleanmgr)
#   - DISM/SFC/Defender/YARA con latido visible (no parecen colgados)
#   - Parse fix: cancelar tarea (BtnConCancel) y taskkill silencioso
#   - Confianza: repair-network seguro (solo DNS); hard aislado Danger
#   - Perfiles ESENCIAL / COMPLETO / DEFAULT WINDOWS; SelfTest
#   - Dialogos modales oscuros; progreso quiet; planes automaticos del panel
#
#  Historial intermedio (absorbido en 1.0.0.1):
#   - v1.0.0.11-.14: papelera MB, shutdown args, instancia unica, P0 alcance
# ============================================================================

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$NoElevate,
    [string[]]$RunTool,
    [switch]$ListTools,
    [switch]$NoGUI,
    [switch]$WhatIf,   # Reservado: no implementado (no simula cambios)
    # -Undo eliminado en v1.0.0.12: no habia implementacion real
    [string]$LogPath = ""
)

# -- ELEVACION ------------------------------------------------------------------
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

# -- COMPATIBILIDAD: Write-Host -> streams estandar --------------------------
# DeMente corre tanto en modo consola (-ListTools/-RunTool) como detras de la
# GUI. El codigo historico llama a Write-Host en ~150 puntos distintos para
# reportar avance con color. En vez de editar cada call site a ciegas (alto
# riesgo de romper algo en un archivo de 7000+ lineas sin poder ejecutarlo en
# un entorno Windows real), se define esta funcion con el mismo nombre: al
# estar definida como funcion de script, PowerShell la resuelve ANTES que el
# cmdlet integrado, por lo que ningun call site necesita cambiar. La salida
# deja de perderse si el script se invoca redirigido (por ejemplo desde CI o
# desde otra herramienta) y queda disponible en el stream Information/Verbose.
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()][AllowEmptyString()]
        [object]$Object = '',

        [switch]$NoNewline,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [object]$Separator = ' '
    )
    process {
        $text = if ($null -eq $Object) { '' }
                elseif ($Object -is [array]) { ($Object -join [string]$Separator) }
                else { [string]$Object }

        # Capturable/redirigible: no depende de que haya una consola interactiva.
        try { Write-Verbose -Message $text } catch { }

        # Salida visible real en modo consola (-ListTools/-RunTool/-SelfTest).
        # Esto NO es el cmdlet Write-Host: es escritura directa a [Console],
        # que es lo que Write-Host termina haciendo igual puertas adentro,
        # pero pasando primero por un stream capturable de PowerShell.
        if (-not [Console]::IsOutputRedirected) {
            $prevFg = [Console]::ForegroundColor
            $prevBg = [Console]::BackgroundColor
            try {
                if ($PSBoundParameters.ContainsKey('ForegroundColor')) { [Console]::ForegroundColor = $ForegroundColor }
                if ($PSBoundParameters.ContainsKey('BackgroundColor')) { [Console]::BackgroundColor = $BackgroundColor }
                if ($NoNewline) { [Console]::Out.Write($text) } else { [Console]::Out.WriteLine($text) }
            }
            finally {
                [Console]::ForegroundColor = $prevFg
                [Console]::BackgroundColor = $prevBg
            }
        }
    }
}

$Global:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# -- INSTANCIA UNICA (mitiga Parameter count mismatch en ShowDialog) ----------
# Si ya hay otro powershell.exe ejecutando este mismo script, avisar y salir.
# Evita dos Owner/STA compitiendo por el mismo XAML y el crash post-limpieza.
if (-not $SelfTest -and -not $ListTools -and -not $NoGUI -and $PSCommandPath) {
    try {
        $me = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        $otros = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -EA SilentlyContinue |
            Where-Object {
                $_.ProcessId -ne $PID -and
                $_.CommandLine -and
                ($_.CommandLine -like "*$me*" -or $_.CommandLine -like '*DeMente*') -and
                $_.CommandLine -like '*-File*'
            })
        if ($otros.Count -gt 0) {
            $pids = ($otros | ForEach-Object { $_.ProcessId }) -join ', '
            Write-Host "DeMente ya esta abierto (PID: $pids). Cerra esa ventana y volve a ejecutar." -ForegroundColor Yellow
            try {
                Add-Type -AssemblyName System.Windows.Forms -EA 0
                [System.Windows.Forms.MessageBox]::Show(
                    "DeMente ya esta en ejecucion (PID: $pids).`n`nCerrola completamente y volve a abrir. Si ves 'Parameter count mismatch', es por una instancia residual.",
                    "DeMente - instancia en uso", 'OK', 'Warning'
                ) | Out-Null
            } catch { }
            exit 0
        }
    } catch { }
}

if (-not $Global:IsAdmin -and -not $SelfTest -and -not $ListTools -and -not $NoElevate) {
    Write-Host "DeMente necesita permisos de Administrador. Relanzando..." -ForegroundColor Yellow
    if (-not $PSCommandPath) {
        Write-Error "El script debe guardarse en un archivo para poder relanzarse como administrador."
        return
    }
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argsList = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    if ($WhatIf)  { $argsList += " -WhatIf" }
    if ($NoGUI)   { $argsList += " -NoGUI" }
    if ($LogPath) { $argsList += " -LogPath `"$LogPath`"" }
    try {
        Start-Process $exe -Verb RunAs -ArgumentList $argsList
        exit 0
    } catch {
        Add-Type -AssemblyName System.Windows.Forms -EA 0
        [System.Windows.Forms.MessageBox]::Show(
            "DeMente necesita permisos de Administrador.`n`nEjecuta como Administrador.",
            "Permisos necesarios", 'OK', 'Warning'
        ) | Out-Null
        exit 0
    }
}

# -- STA FORZADO --------------------------------------------------------------
if (-not $SelfTest -and -not $NoGUI -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    if ($PSCommandPath) {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        exit 0
    }
    Write-Error "DeMente necesita ejecutarse en modo STA."
    exit 1
}

# -- ENSAMBLADOS --------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic -EA 0

# -- RUTAS DE TRABAJO ----------------------------------------------------------
$Global:WDMHome = Join-Path $env:USERPROFILE 'Documents\DeMente'
$Global:WDMLogs = Join-Path $Global:WDMHome 'registros'
$Global:WDMRep  = Join-Path $Global:WDMHome 'reportes'
$Global:WDMBak  = Join-Path $Global:WDMHome 'backups'
$Global:WDMProf = Join-Path $Global:WDMHome 'perfiles'
$Global:WDMTmp  = Join-Path $env:TEMP 'DeMente'
$Global:WDMYaraHome = Join-Path $Global:WDMHome 'security\yara'
$Global:WDMYaraBin  = Join-Path $Global:WDMYaraHome 'bin'
$Global:WDMYaraRules= Join-Path $Global:WDMYaraHome 'rules'
$Global:WDMYaraQuar = Join-Path $Global:WDMYaraHome 'quarantine'
$Global:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

foreach ($d in @($Global:WDMHome, $Global:WDMLogs, $Global:WDMRep, $Global:WDMBak, $Global:WDMProf, $Global:WDMTmp, $Global:WDMYaraHome, $Global:WDMYaraBin, $Global:WDMYaraRules, $Global:WDMYaraQuar)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# -- DETECTAR HARDWARE PARA EL PRELUDIO --------------------------------------
try {
    $cpu = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
    $ram = Get-CimInstance Win32_PhysicalMemory -EA 0
    $disks = Get-CimInstance Win32_DiskDrive -EA 0
    $bat = Get-CimInstance Win32_Battery -EA 0
    
    $script:CPUCores = if ($cpu) { [int]$cpu.NumberOfCores } else { 4 }
    $script:RAMTotalGB = if ($ram) { [math]::Round(($ram|Measure-Object Capacity -Sum).Sum/1GB,1) } else { 8 }
    $script:TieneSSD = if ($disks) { (@($disks)|Where-Object{$_.Model -match "SSD|NVMe|M\.2|Solid"}).Count -gt 0 } else { $false }
    $script:EsLaptop = if ($bat) { $true } else { $false }
} catch {
    $script:CPUCores = 4
    $script:RAMTotalGB = 8
    $script:TieneSSD = $false
    $script:EsLaptop = $false
}

# -- PRELUDIO COMPLETO (CORREGIDO) --------------------------------------------
$Global:Prelude = @'
$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# -- HARDWARE LOCAL DE LA TAREA -----------------------------------------------
# Cada herramienta corre en un proceso PowerShell independiente. No asumimos
# que las variables $script:* del proceso principal existan aqui.
try {
    $cpuLocal = Get-CimInstance Win32_Processor -EA Stop | Select-Object -First 1
    $ramLocal = @(Get-CimInstance Win32_PhysicalMemory -EA Stop)
    $disksLocal = @(Get-CimInstance Win32_DiskDrive -EA Stop)
    $script:CPUCores = if ($cpuLocal) { [int]$cpuLocal.NumberOfCores } else { 4 }
    $script:RAMTotalGB = if ($ramLocal.Count -gt 0) { [math]::Round(($ramLocal | Measure-Object Capacity -Sum).Sum / 1GB, 1) } else { 8 }
    $script:TieneSSD = if ($disksLocal.Count -gt 0) {
        @($disksLocal | Where-Object { $_.MediaType -match 'SSD' -or $_.Model -match 'SSD|NVMe|M\.2|Solid State' }).Count -gt 0
    } else { $false }
} catch {
    $script:CPUCores = 4
    $script:RAMTotalGB = 8
    $script:TieneSSD = $false
}


function Step  ($m) { Write-Host ""; Write-Host ">> $m" }
function OK    ($m) { Write-Host "[OK] $m" }
function INFO  ($m) { Write-Host "[i] $m" }
function WARN  ($m) { Write-Host "[!] $m" }
function ERR   ($m) { Write-Host "[X] $m" }
function ROW   ($k, $v) { Write-Host ("    {0,-32} {1}" -f $k, $v) }
function HR    ($t) { Write-Host ""; Write-Host ("=== " + $t + " " + ("=" * [Math]::Max(4, 62 - $t.Length))) }

function Show-Optimization {
    param([string]$Nombre,[string]$DefaultValue,[string]$OptimalValue,[string]$Path)
    Write-Host ""; ROW "Parametro" $Nombre
    ROW "  Default Windows" $DefaultValue
    ROW "  Valor a aplicar" $OptimalValue
    ROW "  Ruta" $Path
}

<#
.SYNOPSIS
    Convierte un tamaño en bytes a una cadena legible (KB/MB/GB).
.PARAMETER b
    Tamaño en bytes. Acepta 0 o negativos sin lanzar error.
.OUTPUTS
    System.String
#>
function Human ([double]$b) {
    if ($b -lt 1KB) { return "$([math]::Round($b,0)) B" }
    elseif ($b -lt 1MB) { return "{0:N1} KB" -f ($b / 1KB) }
    elseif ($b -lt 1GB) { return "{0:N1} MB" -f ($b / 1MB) }
    elseif ($b -lt 1TB) { return "{0:N2} GB" -f ($b / 1GB) }
    else { return "{0:N2} TB" -f ($b / 1TB) }
}

<#
.SYNOPSIS
    Devuelve una marca de tiempo formateada para nombres de archivo (yyyyMMdd_HHmmss).
#>
function Stamp { return (Get-Date -Format "yyyyMMdd_HHmmss") }

function Get-WDMSessionUptime {
    # "Hace cuanto prendiste la PC de verdad"
    # - Evento Kernel 12 = arranque del sistema (mejor contra Inicio rapido)
    # - TickCount64 = ms de esta sesion
    # - WMI LastBootUpTime suele mentir con Inicio rapido (dias de mas) -> ultimo recurso
    $candidates = @()
    try {
        $ev = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-General'
            Id = 12
        } -MaxEvents 1 -ErrorAction Stop
        if ($ev -and $ev.TimeCreated) {
            $candidates += ((Get-Date) - $ev.TimeCreated)
        }
    } catch {
        try {
            $ev2 = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 12 } -MaxEvents 1 -ErrorAction Stop
            if ($ev2 -and $ev2.TimeCreated) { $candidates += ((Get-Date) - $ev2.TimeCreated) }
        } catch { }
    }
    try {
        $ms = [Environment]::TickCount64
        if ($ms -is [int] -and $ms -lt 0) { $ms = [double]([uint32]$ms) } else { $ms = [double]$ms }
        if ($ms -gt 1000) { $candidates += [TimeSpan]::FromMilliseconds($ms) }
    } catch { }
    try {
        $sec = (Get-CimInstance Win32_PerfFormattedData_PerfOS_System -EA Stop).SystemUpTime
        if ($null -ne $sec -and [double]$sec -gt 1) {
            $candidates += [TimeSpan]::FromSeconds([double]$sec)
        }
    } catch { }
    # WMI solo si no hay nada mas
    if ($candidates.Count -eq 0) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -EA Stop
            if ($os -and $os.LastBootUpTime) { $candidates += ((Get-Date) - $os.LastBootUpTime) }
        } catch { }
    }
    if ($candidates.Count -eq 0) { return [TimeSpan]::FromSeconds(0) }
    $best = $candidates | Where-Object { $_.TotalSeconds -gt 0 } | Sort-Object TotalSeconds | Select-Object -First 1
    if ($best) { return $best }
    return $candidates[0]
}

function Format-WDMUptime([TimeSpan]$ts) {
    if ($ts.TotalMinutes -lt 1) { return ("{0} s de sesion" -f [int]$ts.TotalSeconds) }
    if ($ts.TotalHours -lt 1) { return ("{0} min de sesion" -f [int]$ts.TotalMinutes) }
    if ($ts.TotalHours -lt 48) { return ("{0:N1} h de sesion" -f $ts.TotalHours) }
    return ("{0:N1} dias de sesion" -f $ts.TotalDays)
}

<#
.SYNOPSIS
    Devuelve (creando si hace falta) una subcarpeta bajo Documents\DeMente.
.PARAMETER sub
    Ruta relativa, p. ej. "\backups" o "\registros". Debe empezar con "\".
#>
function WDM-Dir ($sub) {
    if ([string]::IsNullOrWhiteSpace($sub)) {
        throw "WDM-Dir: el parametro 'sub' no puede estar vacio."
    }
    $p = Join-Path $env:USERPROFILE "Documents\DeMente$sub"
    try {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -Path $p -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        ERR "No se pudo crear la carpeta '$p': $($_.Exception.Message)"
        throw
    }
    return $p
}

<#
.SYNOPSIS
    Exporta una clave de registro a .reg antes de modificarla (backup best-effort).
.PARAMETER HivePath
    Ruta de PowerShell del hive, p. ej. 'HKLM:\SYSTEM\CurrentControlSet\Control'.
.PARAMETER Tag
    Etiqueta corta para nombrar el archivo de backup.
.OUTPUTS
    System.String -- ruta del .reg generado. Puede no existir si el export falla;
    siempre revisa con Test-Path antes de asumir que el backup se creo.
#>
function Backup-Reg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^(HKLM|HKCU|HKCR):\\')][string]$HivePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Tag
    )
    $f = Join-Path (WDM-Dir "\backups") ("{0}_{1}.reg" -f $Tag, (Stamp))
    $rp = $HivePath -replace "^HKLM:\\?", "HKEY_LOCAL_MACHINE\" -replace "^HKCU:\\?", "HKEY_CURRENT_USER\" -replace "^HKCR:\\?", "HKEY_CLASSES_ROOT\"
    try {
        $null = & reg.exe export "$rp" "$f" /y 2>$null
        if (Test-Path -LiteralPath $f) { OK "Respaldo del registro: $f" } else { INFO "Sin respaldo: $rp" }
    }
    catch {
        WARN "No se pudo respaldar '$rp': $($_.Exception.Message)"
    }
    return $f
}


# =============================================================================
# REGISTRO INTELIGENTE (no es un limpiador de miedo tipo 2005)
# - Solo hallazgos verificables (ruta inexistente, desinstalador huerfano)
# - Backup .reg antes de borrar
# - Nunca toca Services criticos, SAM, ni Classes del sistema a ciegas
# =============================================================================

function Get-WDMRegBackupDir {
    return (WDM-Dir '\backups\registry')
}

<#
.SYNOPSIS
    Heuristica: ¿la ruta de ejecutable que aparece en 'cmd' existe en disco?
.DESCRIPTION
    Usado por la auditoria de registro para distinguir entradas de inicio
    huerfanas (apuntan a un .exe que ya no existe) de las validas. Si la
    cadena no se puede interpretar como ruta, devuelve $true para NO generar
    falsos positivos.
#>
function Test-WDMExePath([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
    $pathGuess = $null
    if ($cmd -match '^"([^"]+)"') { $pathGuess = $Matches[1] }
    elseif ($cmd -match '^(.*?\.exe)') { $pathGuess = $Matches[1].Trim().Trim('"') }
    elseif ($cmd -match '^[A-Za-z]:\\') {
        $pathGuess = ($cmd -split '\s+')[0].Trim('"')
    }
    if (-not $pathGuess) { return $true } # no se pudo parsear: no marcar como roto
    try {
        if ($pathGuess.StartsWith('%')) {
            $pathGuess = [Environment]::ExpandEnvironmentVariables($pathGuess)
        }
    } catch { }
    return (Test-Path -LiteralPath $pathGuess -EA SilentlyContinue)
}

function Get-WDMRegAudit {
    $findings = [System.Collections.Generic.List[object]]::new()

    function Add-Finding($Area, $Risk, $Key, $Name, $Detail, $Action) {
        $findings.Add([pscustomobject]@{
            Area = $Area; Risk = $Risk; Key = $Key; Name = $Name
            Detail = $Detail; Action = $Action
        }) | Out-Null
    }

    # 1) Run / RunOnce rotos
    $runPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($rp in $runPaths) {
        if (-not (Test-Path $rp)) { continue }
        $props = Get-ItemProperty $rp -EA SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Value } | ForEach-Object {
            $val = [string]$_.Value
            if (-not (Test-WDMExePath $val)) {
                Add-Finding 'Inicio (Run)' 'bajo' $rp $_.Name "Apunta a archivo inexistente: $val" 'remove-value'
            }
        }
    }

    # 2) App Paths huerfanos
    $appPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
    )
    foreach ($ap in $appPaths) {
        if (-not (Test-Path $ap)) { continue }
        Get-ChildItem $ap -EA SilentlyContinue | ForEach-Object {
            try {
                $def = (Get-ItemProperty $_.PSPath -EA Stop).'(default)'
                if ($def -and -not (Test-WDMExePath ([string]$def))) {
                    Add-Finding 'App Paths' 'bajo' $_.PSPath $_.PSChildName "Default apunta a inexistente: $def" 'remove-key'
                }
            } catch { }
        }
    }

    # 3) Desinstaladores huerfanos (Uninstall)
    $unins = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($up in $unins) {
        if (-not (Test-Path $up)) { continue }
        Get-ChildItem $up -EA SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty $_.PSPath -EA Stop
                $name = $p.DisplayName
                if (-not $name) { return }
                # Saltar actualizaciones de Windows / KB
                if ($name -match '^KB\d+|Update for|Security Update|Microsoft Visual C\+\+') { return }
                $loc = $p.InstallLocation
                $ico = $p.DisplayIcon
                $unin = $p.UninstallString
                $broken = $false
                $why = @()
                if ($loc -and ($loc.Trim().Length -gt 3) -and -not (Test-Path -LiteralPath $loc -EA SilentlyContinue)) {
                    $broken = $true; $why += "InstallLocation no existe ($loc)"
                }
                if ($unin -and -not (Test-WDMExePath $unin)) {
                    # muchos uninstall son msiexec - no marcar msiexec como roto
                    if ($unin -notmatch 'msiexec') {
                        $broken = $true; $why += "UninstallString roto"
                    }
                }
                if ($ico) {
                    $icoPath = ($ico -split ',')[0].Trim('"')
                    if ($icoPath -match '\.exe|\.dll' -and -not (Test-Path -LiteralPath $icoPath -EA SilentlyContinue)) {
                        if ($broken) { $why += "icono ausente" }
                    }
                }
                # Solo reportar si InstallLocation muerto O uninstall muerto (senal fuerte)
                if ($broken -and ($why -match 'InstallLocation|UninstallString')) {
                    Add-Finding 'Desinstaladores' 'medio' $_.PSPath $name ($why -join '; ') 'remove-key'
                }
            } catch { }
        }
    }

    # 4) SharedDLLs con contador >0 pero archivo muerto (solo reportar, riesgo medio-alto para limpiar)
    try {
        $sd = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs'
        if (Test-Path $sd) {
            $props = Get-ItemProperty $sd -EA SilentlyContinue
            if ($props) {
                $n = 0
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match '^[A-Za-z]:\\' } | ForEach-Object {
                    if ($n -ge 30) { return }
                    if (-not (Test-Path -LiteralPath $_.Name -EA SilentlyContinue)) {
                        $n++
                        Add-Finding 'SharedDLLs' 'medio' $sd $_.Name "DLL registrada pero archivo ausente (ref=$($_.Value))" 'remove-value'
                    }
                }
            }
        }
    } catch { }

    # 5) Leftovers: MUI Cache / UserAssist no se tocan (privacidad forense).
    #    Si: StartupApproved huérfano, Explorer\FileExts rotas leves, TypeLib no.
    # 5a) Run keys en StartupApproved sin valor correspondiente en Run
    foreach ($sa in @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
    )) {
        if (-not (Test-Path $sa)) { continue }
        $runMirror = $sa -replace '\\Explorer\\StartupApproved\\Run32$', '\Run' -replace '\\Explorer\\StartupApproved\\Run$', '\Run'
        $runMirror = $runMirror -replace 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $runMirror = $runMirror -replace 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run32', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        $runMirror = $runMirror -replace 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $props = Get-ItemProperty $sa -EA SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $nm = $_.Name
            $existsInRun = $false
            try {
                if (Test-Path $runMirror) {
                    $rv = Get-ItemProperty $runMirror -Name $nm -EA SilentlyContinue
                    if ($null -ne $rv) { $existsInRun = $true }
                }
            } catch { }
            if (-not $existsInRun) {
                Add-Finding 'StartupApproved' 'bajo' $sa $nm 'Marca de inicio sin entrada Run correspondiente' 'remove-value'
            }
        }
    }

    # 5b) OpenWithList / UserChoice no se tocan (rompe asociaciones).
    # 5c) Installer\Products residuales con LocalPackage ausente (solo reportar, riesgo medio)
    try {
        $ip = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
        if (Test-Path $ip) {
            $n = 0
            Get-ChildItem $ip -EA SilentlyContinue | ForEach-Object {
                $prod = Join-Path $_.PSPath 'Products'
                if (-not (Test-Path $prod)) { return }
                Get-ChildItem $prod -EA SilentlyContinue | Select-Object -First 80 | ForEach-Object {
                    if ($n -ge 25) { return }
                    try {
                        $ip2 = Join-Path $_.PSPath 'InstallProperties'
                        if (-not (Test-Path $ip2)) { return }
                        $pr = Get-ItemProperty $ip2 -EA Stop
                        $loc = $pr.LocalPackage
                        $dn = $pr.DisplayName
                        if ($loc -and $dn -and -not (Test-Path -LiteralPath $loc -EA SilentlyContinue)) {
                            if ($dn -notmatch 'Update for|KB\d+|Security Update') {
                                $n++
                                Add-Finding 'Installer residual' 'medio' $ip2 $dn "LocalPackage ausente: $loc" 'report-only'
                            }
                        }
                    } catch { }
                }
            }
        }
    } catch { }

    # 5d) CLSIDs de App Paths ya cubiertos. Compatibilidad Application residual:
    try {
        $appCompat = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
        if (Test-Path $appCompat) {
            $props = Get-ItemProperty $appCompat -EA SilentlyContinue
            if ($props) {
                $n = 0
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match '^[A-Za-z]:\\' } | ForEach-Object {
                    if ($n -ge 20) { return }
                    if (-not (Test-Path -LiteralPath $_.Name -EA SilentlyContinue)) {
                        $n++
                        Add-Finding 'AppCompat Layers' 'bajo' $appCompat $_.Name 'Ruta de compatibilidad apunta a exe inexistente' 'remove-value'
                    }
                }
            }
        }
    } catch { }

    return $findings
}

function Show-WDMRegAudit {
    HR "AUDITORIA INTELIGENTE DEL REGISTRO"
    Write-Host "DeMente no inventa miles de errores. Solo lista lo verificable:"
    Write-Host "  - Inicio (Run/RunOnce) con .exe inexistente"
    Write-Host "  - App Paths rotos"
    Write-Host "  - Desinstaladores huerfanos (carpeta/uninstaller muertos)"
    Write-Host "  - SharedDLLs huerfanas (solo informe)"
    Write-Host ""
    Write-Host "NO se toca: servicios criticos, SAM, Classes del sistema, drivers."
    Write-Host ""

    $findings = @(Get-WDMRegAudit)
    if ($findings.Count -eq 0) {
        OK "No se encontraron residuos evidentes. El registro esta razonablemente limpio en las zonas seguras."
        INFO "Eso no significa '0 entradas': significa que no hay basura obvia y comprobable."
        return $true
    }

    $byArea = $findings | Group-Object Area
    foreach ($g in $byArea) {
        HR ("{0} ({1})" -f $g.Name, $g.Count)
        foreach ($f in $g.Group) {
            $tag = switch ($f.Risk) {
                'bajo' { '[bajo]' }
                'medio' { '[medio]' }
                default { '[rev]' }
            }
            ROW "$tag $($f.Name)" $f.Detail
        }
    }
    Write-Host ""
    $nLow = @($findings | Where-Object Risk -eq 'bajo').Count
    $nMed = @($findings | Where-Object Risk -eq 'medio').Count
    WARN ("Hallazgos: {0} total ({1} bajo riesgo, {2} medio). La limpieza segura solo toca 'bajo' + desinstaladores claramente huerfanos." -f $findings.Count, $nLow, $nMed)
    INFO "Siguiente paso: Limpieza segura de registro (crea backup .reg automatico)."
    return $true
}

function Clear-WDMRegSafe {
    HR "LIMPIEZA SEGURA DEL REGISTRO"
    Write-Host "1) Auditoria  2) Backup .reg  3) Solo borrar hallazgos de bajo riesgo / huerfanos claros"
    Write-Host ""

    $findings = @(Get-WDMRegAudit)
    # Filtro: bajo siempre; medio solo si Area es Desinstaladores o App Paths
    $toClean = @($findings | Where-Object {
        $_.Risk -eq 'bajo' -or ($_.Risk -eq 'medio' -and $_.Area -in @('Desinstaladores','App Paths') -and $_.Action -in @('remove-key','remove-value'))
    })
    # SharedDLLs: NO borrar automatico (puede romper instaladores viejos)
    $toClean = @($toClean | Where-Object { $_.Area -ne 'SharedDLLs' })

    if ($toClean.Count -eq 0) {
        OK "Nada seguro para borrar. Ejecuta primero la auditoria o el registro ya esta limpio."
        $all = @($findings)
        if ($all.Count -gt 0) {
            INFO ("Hay {0} hallazgo(s) de riesgo medio/compartido que DeMente NO borra solo (SharedDLLs u otros)." -f $all.Count)
        }
        return $true
    }

    HR "Se van a limpiar $($toClean.Count) entradas"
    foreach ($f in $toClean) {
        ROW $f.Name ("{0} | {1}" -f $f.Area, $f.Detail)
    }
    Write-Host ""

    $bakDir = Get-WDMRegBackupDir
    $stamp = Stamp
    $mergedList = Join-Path $bakDir ("reg_safe_clean_{0}_LIST.txt" -f $stamp)
    $toClean | ForEach-Object { "{0}`t{1}`t{2}`t{3}" -f $_.Area, $_.Key, $_.Name, $_.Detail } | Set-Content -Path $mergedList -Encoding UTF8
    OK "Lista de cambios: $mergedList"

    # Backup de cada clave unica
    $keys = @($toClean | Select-Object -ExpandProperty Key -Unique)
    foreach ($k in $keys) {
        $tag = "regclean_" + ($k -replace '[^\w]', '_').Substring(0, [Math]::Min(40, ($k -replace '[^\w]', '_').Length))
        Backup-Reg -HivePath $k -Tag $tag | Out-Null
    }

    $okN = 0; $failN = 0
    foreach ($f in $toClean) {
        try {
            if ($f.Action -eq 'remove-value') {
                if (Test-Path $f.Key) {
                    Remove-ItemProperty -Path $f.Key -Name $f.Name -Force -EA Stop
                    OK "Valor quitado: $($f.Name)"
                    $okN++
                }
            } elseif ($f.Action -eq 'remove-key') {
                if (Test-Path $f.Key) {
                    Remove-Item -Path $f.Key -Recurse -Force -EA Stop
                    OK "Clave quitada: $($f.Name)"
                    $okN++
                }
            }
        } catch {
            WARN "No se pudo limpiar $($f.Name): $($_.Exception.Message)"
            $failN++
        }
    }
    Write-Host ""
    OK ("Limpieza segura terminada: {0} ok, {1} fallos. Backups en Documents\DeMente\backups\registry" -f $okN, $failN)
    INFO "Para restaurar: usa 'Restaurar ultimo backup de registro' o regedit > Importar el .reg"
    return $true
}

function Restore-WDMRegLastBackup {
    HR "RESTAURAR BACKUP DE REGISTRO"
    $dir = Get-WDMRegBackupDir
    $regs = @(Get-ChildItem $dir -Filter *.reg -EA SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($regs.Count -eq 0) {
        WARN "No hay backups .reg en $dir"
        INFO "Se crean solos al ejecutar la limpieza segura."
        return $true
    }
    HR "Ultimos backups"
    $i = 0
    foreach ($r in ($regs | Select-Object -First 8)) {
        $i++
        ROW "#$i" ("{0} | {1}" -f $r.Name, $r.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    }
    # Restaurar el mas reciente de esta sesion de limpieza (todos los de la ultima hora o el set mas reciente)
    $latest = $regs[0]
    INFO "Importando el mas reciente: $($latest.FullName)"
    $p = Start-Process -FilePath "reg.exe" -ArgumentList @('import', $latest.FullName) -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) { OK "Backup importado: $($latest.Name)" }
    else { ERR "reg import fallo con codigo $($p.ExitCode)" }
    if ($regs.Count -gt 1) {
        INFO "Hay $($regs.Count) backups. Si necesitas otro, importa a mano desde: $dir"
    }
    return $true
}

function Show-WDMFullCheckup {
    HR "REVISION COMPLETA DEL SISTEMA (estilo DeMente)"
    Write-Host "Un solo vistazo: hardware, espacio, inicio, registro, lo que realmente importa."
    Write-Host "No es un puntaje magico tipo TuneUp: es un mapa de hallazgos."
    Write-Host ""

    # Hardware
    HR "1. Hardware"
    try {
        $cpu = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
        $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $cores = $cpu.NumberOfLogicalProcessors
        ROW 'Procesador' ("{0} ({1} nucleos logicos)" -f $cpu.Name.Trim(), $cores)
        ROW 'Memoria' ("{0} GB" -f $ram)
        if ($ram -lt 8) { WARN "RAM limitada para multitarea moderna (piso comodo: 8 GB)." }
        $pd = Get-PhysicalDisk -EA 0 | Select-Object -First 1
        if ($pd) {
            $media = $pd.MediaType
            ROW 'Disco' ("{0} | {1}" -f $pd.FriendlyName, $media)
            if ($media -match 'HDD|Unspecified') { WARN "HDD detectado: el mayor cuello de botella tipico al abrir programas." }
        }
    } catch { WARN "No se pudo leer hardware completo." }

    HR "2. Espacio y basura tipica"
    try {
        $sys = $env:SystemDrive.TrimEnd('\')
        $vol = Get-Volume -DriveLetter $sys[0] -EA 0
        if ($vol) {
            $freeGB = [math]::Round($vol.SizeRemaining/1GB, 1)
            $pct = [math]::Round(100 * $vol.SizeRemaining / $vol.Size, 0)
            ROW 'Espacio libre' ("{0} GB ({1}%)" -f $freeGB, $pct)
        }
        $tempBytes = 0
        foreach ($tp in @($env:TEMP, "$env:SystemRoot\Temp")) {
            if (Test-Path $tp) {
                $tempBytes += [double]((Get-ChildItem $tp -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
            }
        }
        ROW 'TEMP aproximado' (Human $tempBytes)
        if ($tempBytes -gt 500MB) { WARN "Hay basura temporal recuperable (Limpieza > Archivos temporales)." }
        else { OK "TEMP no esta desbordado." }
    } catch { }

    HR "3. Inicio (muestra rapida)"
    try {
        $n = 0
        foreach ($rp in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
            if (-not (Test-Path $rp)) { continue }
            $pr = Get-ItemProperty $rp -EA 0
            if ($pr) {
                $n += @($pr.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Value }).Count
            }
        }
        ROW 'Entradas Run' "$n"
        if ($n -gt 12) { WARN "Muchos programas al inicio. Usa Rendimiento > Auditar inicio o Herramientas > Autoruns." }
        else { OK "Inicio relativamente liviano en Run." }
    } catch { }

    HR "4. Registro (zonas seguras)"
    try {
        $reg = @(Get-WDMRegAudit)
        ROW 'Hallazgos verificables' "$($reg.Count)"
        if ($reg.Count -eq 0) { OK "Sin residuos evidentes en Run/Uninstall/App Paths." }
        else {
            WARN "Hay residuos comprobables. Corre 'Auditar registro' o 'Limpieza segura de registro'."
            $reg | Select-Object -First 5 | ForEach-Object { ROW $_.Name $_.Detail }
        }
    } catch { WARN "Auditoria de registro no disponible en este contexto." }

    HR "5. Uptime y estabilidad"
    try {
        $up = Get-WDMSessionUptime
        ROW 'Sesion' (Format-WDMUptime $up)
        if ($up.TotalDays -ge 7) { WARN "Lleva muchos dias sin reiniciar: la RAM se fragmenta en la practica diaria." }
    } catch { }

    Write-Host ""
    OK "Revision completa finalizada."
    INFO "Prioridad realista en PCs lentas: 1) SSD si hay HDD  2) mas RAM si hay 4 GB  3) inicio limpio  4) basura/registro."
    INFO "DeMente no promete milagros de registro: promete no mentirte."
    return $true
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        OK "$Name = $Value"
    }
    catch { ERR "No se pudo escribir $Path :: $Name" }
}

function Remove-Reg {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop; OK "Eliminado: $Name" }
        else { INFO "No existia la clave $Path" }
    }
    catch { INFO "No existia el valor $Name" }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

function Convert-RegDword {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        # PowerShell often returns DWORD -1 as UInt32 4294967295
        $u = [uint64]$Value
        if ($u -gt 0x7FFFFFFF) { return [int64]($u - 0x100000000) }
        return [int64]$u
    } catch {
        try { return [int64]$Value } catch { return $null }
    }
}

function Test-RegDwordEq {
    param($Value, [int64[]]$Expected)
    $v = Convert-RegDword $Value
    if ($null -eq $v) { return $false }
    return ($Expected -contains $v)
}

function Get-NtfsLastAccessCode {
    # Windows a veces guarda 0x80000002 (system managed). Solo importa el byte bajo: 0/1/2/3.
    param($Value)
    if ($null -eq $Value) { return $null }
    try { return [int]([uint64][uint32]$Value -band 0xFF) } catch {
        try { return [int]((Convert-RegDword $Value) -band 0xFF) } catch { return $null }
    }
}

function Test-NtfsOptimized {
    param($Value)
    $c = Get-NtfsLastAccessCode $Value
    return ($c -eq 1 -or $c -eq 3)
}


function Get-Folder-Size {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try { return [double]((Get-ChildItem $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }
    catch { return 0 }
}

function Purge-Folder {
    param([string]$Path, [string]$Label)
    if (-not $Label) { $Label = $Path }
    if (-not (Test-Path $Path)) { INFO "$Label : no existe"; return [double]0 }
    $before = Get-Folder-Size $Path
    $n = 0
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch { }
    }
    $freed = $before - (Get-Folder-Size $Path)
    if ($freed -lt 0) { $freed = 0 }
    OK ("{0}: {1} elementos, {2} liberados" -f $Label, $n, (Human $freed))
    return [double]$freed
}

<#
.SYNOPSIS
    Limpia archivos por patron/ruta y reporta cantidad + tamaño liberado.
.PARAMETER Paths
    Rutas exactas, carpetas o patrones con comodin (*, ?).
.PARAMETER Label
    Etiqueta para el log.
.PARAMETER Recurse
    Si se especifica, incluye subcarpetas.
.OUTPUTS
    System.Int32 -- cantidad de archivos eliminados.
#>
function Clear-WDMFiles {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][string]$Label,
        [switch]$Recurse
    )
    $before = [double]0
    $count = 0
    # Lista en vez de $items += @(...): evita reconstruir el array completo
    # en cada iteracion (O(n^2) con muchos elementos, notorio en carpetas
    # de cache grandes tipo AppData\Local\Temp).
    $items = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($p in $Paths) {
        try {
            if ($p -match '[\*\?]') {
                Get-ChildItem $p -Force -File -EA SilentlyContinue | ForEach-Object { $items.Add($_) }
            } elseif (Test-Path -LiteralPath $p) {
                Get-ChildItem -LiteralPath $p -Recurse:$Recurse -Force -File -EA SilentlyContinue | ForEach-Object { $items.Add($_) }
            }
        } catch {
            WARN "No se pudo enumerar '$p': $($_.Exception.Message)"
        }
    }
    foreach ($f in $items) {
        try { $before += [double]$f.Length } catch { }
        try { Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $count++ } catch { }
    }
    OK ("{0}: {1} archivos, {2} liberados" -f $Label, $count, (Human $before))
    if ($count -eq 0) { INFO "Nada borrable ahora (vacio o archivos en uso)." }
    return $count
}

function Stop-Svc { param([string[]]$Names) foreach ($s in $Names) { try { Stop-Service $s -Force -ErrorAction Stop; OK "Detenido: $s" } catch { WARN "No se pudo detener: $s" } } }
function Start-Svc { param([string[]]$Names) foreach ($s in $Names) { try { Start-Service $s -ErrorAction Stop; OK "Iniciado: $s" } catch { WARN "No se pudo iniciar: $s" } } }

function Get-RecycleBinBytes {
    # Tamaño real de la papelera (bytes). Preferir FolderItem.Size; fallback
    # columna localizada (suele ser 2) y, si Shell falla, $Recycle.Bin por volumen.
    $total = [double]0
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.Namespace(0x0a)
        if ($null -ne $rb) {
            foreach ($item in @($rb.Items())) {
                try {
                    if ($null -ne $item.Size -and [double]$item.Size -gt 0) {
                        $total += [double]$item.Size
                        continue
                    }
                    $sz = $null
                    try { $sz = $rb.GetDetailsOf($item, 2) } catch { }
                    if (-not $sz) { try { $sz = $rb.GetDetailsOf($item, 1) } catch { } }
                    if ($sz -match '([\d\.,]+)\s*(KB|MB|GB|TB)?') {
                        $n = [double](($Matches[1] -replace ',', '.'))
                        switch ($Matches[2]) {
                            'KB' { $total += $n * 1KB }
                            'MB' { $total += $n * 1MB }
                            'GB' { $total += $n * 1GB }
                            'TB' { $total += $n * 1TB }
                            default {
                                # sin unidad: en algunas locales ya viene en bytes o en KB
                                if ($n -gt 1048576) { $total += $n } else { $total += $n * 1KB }
                            }
                        }
                    }
                } catch { }
            }
        }
    } catch { }
    if ($total -le 0) {
        try {
            Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | ForEach-Object {
                $path = Join-Path $_.Root '$Recycle.Bin'
                if (Test-Path -LiteralPath $path) {
                    try {
                        $sum = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -EA SilentlyContinue |
                            Measure-Object Length -Sum).Sum
                        if ($null -ne $sum) { $total += [double]$sum }
                    } catch { }
                }
            }
        } catch { }
    }
    return [long][math]::Max(0, [math]::Round($total))
}

# -- FUNCIONES DE OPTIMIZACION -----------------------------------------------

function Get-IdealWin32Priority {
    param([int]$Cores)
    if ($Cores -le 2) { return 18 }
    elseif ($Cores -le 4) { return 26 }
    else { return 38 }
}

function Get-IdealSystemResponsiveness {
    param([int]$Cores)
    if ($Cores -le 4) { return 10 }
    else { return 0 }
}

function Get-IdealPrefetcher {
    param([object]$SSD)
    $esSSD = $false
    if ($null -ne $SSD) {
        if ($SSD -is [bool]) {
            $esSSD = [bool]$SSD
        } elseif ($SSD -is [string]) {
            $tmp = $false
            if ([bool]::TryParse($SSD, [ref]$tmp)) { $esSSD = $tmp }
            elseif ($SSD -match '^(1|si|yes|true)$') { $esSSD = $true }
        } elseif ($SSD -is [int] -or $SSD -is [long]) {
            $esSSD = ([int64]$SSD -ne 0)
        }
    }
    if ($esSSD) { return 2 }
    else { return 3 }
}

function Optimize-Win32PrioritySeparation {
    $ideal = Get-IdealWin32Priority -Cores $script:CPUCores
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $ideal -Type DWord -EA Stop
    OK ("Prioridad CPU: DEFAULT Windows variable | DeMente: {0} (segun {1} nucleos)" -f $ideal, $script:CPUCores)
    return $true
}

function Optimize-DisablePagingExecutive {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -EA Stop
    OK "Paging Executive: DEFAULT 0 | DeMente: 1 (kernel priorizado en RAM)"
    return $true
}

function Optimize-MenuShowDelay {
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -EA Stop
    OK "MenuShowDelay: DEFAULT 400ms | DeMente: 0 (menus instantaneos)"
    return $true
}

function Optimize-PowerPlan {
    if ($script:EsLaptop) {
        powercfg /setactive SCHEME_BALANCED 2>$null
        OK "Plan Equilibrado (correcto para laptop: menos calor y mas autonomia)"
    } else {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        OK "Plan Alto Rendimiento activado (escritorio)"
    }
    return $true
}

function Optimize-UltimatePerformance {
    # Plan oculto de Windows (como WinToys). En laptop puede gastar mas bateria.
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
    powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
    if ($LASTEXITCODE -eq 0 -or $?) {
        OK "Plan Rendimiento maximo (Ultimate Performance) activado"
        INFO "En portatil puede reducir la autonomia. Podes volver a Equilibrado cuando quieras."
    } else {
        WARN "No se pudo activar Ultimate Performance en este equipo"
    }
    return $true
}

function Optimize-FastStartup {
    # Fast Startup a veces deja el apagado "a medias" y complica actualizaciones.
    $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "HiberbootEnabled" -Value 0 -Type DWord -EA Stop
    OK "Inicio rapido: DEFAULT activado | DeMente: desactivado (apagado completo, updates mas predecibles)"
    return $true
}

function Optimize-StorageSense {
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "01" -Value 1 -Type DWord -EA 0   # Storage Sense on
    Set-ItemProperty $k -Name "04" -Value 1 -Type DWord -EA 0   # delete temp files
    Set-ItemProperty $k -Name "08" -Value 1 -Type DWord -EA 0   # recycle bin
    Set-ItemProperty $k -Name "32" -Value 0 -Type DWord -EA 0   # Downloads: 0 = DeMente no limpia Descargas
    Set-ItemProperty $k -Name "2048" -Value 7 -Type DWord -EA 0 # run every week
    OK "Storage Sense: DEFAULT a menudo off | DeMente: activado (temp + papelera; NO Descargas)"
    INFO "No borra Documentos ni Descargas. Solo temporales y papelera segun politica Windows."
    return $true
}

function Optimize-ClassicContextMenu {
    # Menu contextual clasico de Windows 10 en Windows 11
    $k = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "(Default)" -Value "" -EA 0
    OK "Menu contextual clasico activado (como en Windows 10)"
    INFO "Reinicia el Explorador o cierra sesion para ver el cambio completo."
    return $true
}

function Optimize-VisualEffects {
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not(Test-Path $k)) { New-Item $k -Force|Out-Null }
    Set-ItemProperty $k -Name "VisualFXSetting" -Value 2 -Type DWord -EA Stop
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty $adv -Name "ListviewAlphaSelect" -Value 0 -Type DWord -EA 0
    Set-ItemProperty $adv -Name "TaskbarAnimations"   -Value 0 -Type DWord -EA 0
    OK "Efectos visuales: DEFAULT Let Windows decide | DeMente: priorizar rendimiento"
    return $true
}

function Optimize-NetworkThrottling {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty $k -Name "NetworkThrottlingIndex" -Value ([int]-1) -Type DWord -EA Stop
    OK "NetworkThrottlingIndex: DEFAULT 10 | DeMente: FFFFFFFF (sin limite multimedia)"
    return $true
}

function Optimize-SystemResponsiveness {
    $ideal = Get-IdealSystemResponsiveness -Cores $script:CPUCores
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty $k -Name "SystemResponsiveness" -Value $ideal -Type DWord -EA Stop
    OK ("SystemResponsiveness: DEFAULT 20 | DeMente: {0}" -f $ideal)
    return $true
}

function Optimize-TimerResolution {
    WARN "La resolucion del temporizador de Windows no se fija de forma permanente mediante un valor de registro seguro."
    INFO "DeMente no va a falsear una optimizacion: para este parametro se recomienda dejar Windows DEFAULT."
    return $true
}

function Optimize-Prefetcher {
    $ideal = Get-IdealPrefetcher -SSD ([bool]$script:TieneSSD)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "EnablePrefetcher" -Value $ideal -Type DWord -EA Stop
    OK ("Prefetcher: DEFAULT 3 | DeMente: {0} (SSD/HDD)" -f $ideal)
    return $true
}

function Optimize-NtfsLastAccess {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 3 -Type DWord -EA Stop
    OK "NTFS LastAccess: DEFAULT system-managed (2) | DeMente: 3 (menos escrituras)"
    return $true
}

function Optimize-ExplorerSeparateProcess {
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty $adv -Name "SeparateProcess" -Value 1 -Type DWord -EA Stop
    OK "Explorador configurado en proceso separado - un fallo no arrastra al escritorio"
    return $true
}

function Optimize-Superfetch {
    $svc = Get-Service -Name "SysMain" -EA 0
    if ($null -eq $svc) { WARN "SysMain no encontrado"; return $true }
    if ($script:TieneSSD) {
        Stop-Service SysMain -Force -EA 0 | Out-Null
        Set-Service SysMain -StartupType Disabled -EA Stop | Out-Null
        OK "SysMain desactivado - en SSD puede generar actividad de disco innecesaria"
        return $true
    }
    if ($script:RAMTotalGB -lt 6) {
        Stop-Service SysMain -Force -EA 0 | Out-Null
        Set-Service SysMain -StartupType Disabled -EA Stop | Out-Null
        OK "SysMain desactivado - con poca RAM puede consumir más de lo que aporta"
        return $true
    }
    OK "SysMain se mantiene activo - HDD y memoria suficiente; no se fuerza un cambio"
    return $true
}

function Optimize-Indexacion {
    if ($script:TieneSSD) { WARN "SSD detectado - indexacion no es problema"; return $true }
    try {
        Stop-Service WSearch -Force -EA 0 | Out-Null
        Set-Service WSearch -StartupType Disabled -EA Stop | Out-Null
        OK "Indexación de Windows Search desactivada (HDD detectado)"
        return $true
    } catch { ERR "Error al desactivar indexacion: $_"; return $false }
}

function Optimize-Hibernación {
    powercfg /hibernate off 2>$null
    if (-not (Test-Path "$env:SystemRoot\hiberfil.sys")) {
        OK "Hibernación desactivada - hiberfil.sys eliminado"
        return $true
    }
    WARN "No se pudo eliminar hiberfil.sys"
    return $false
}

function Optimize-IPv6 {
    try {
        Get-NetAdapterBinding -ComponentID "ms_tcpip6" -EA 0 | Where-Object { $_.Enabled -eq $true } | ForEach-Object {
            Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -EA 0
        }
        OK "IPv6 desactivado en todos los adaptadores"
        return $true
    } catch {
        WARN "No se pudo desactivar IPv6: $_"
        return $false
    }
}

function Optimize-QoSReservado {
    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "NonBestEffortLimit" -Value 0 -Type DWord -EA Stop
    OK "QoS reservado a 0% - ancho de banda completo disponible"
    return $true
}

function Optimize-NagleAlgoritmo {
    $count = 0
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA 0 | ForEach-Object {
        try { Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -EA 0
              Set-ItemProperty $_.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -EA 0; $count++ } catch {}
    }
    OK "Algoritmo de Nagle desactivado en $count interfaz(es) - menor latencia"
    return $true
}

function Optimize-ApagadoRapido {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "5000" -Type String -EA 0
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "3000" -Type String -EA 0
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout"       -Value "3000" -Type String -EA 0
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks"         -Value "1"    -Type String -EA 0
    OK "Tiempos de espera de apagado: servicios=5 s, aplicaciones=3 s, cierre automático=activado"
    return $true
}

# -- FUNCIONES DE LIMPIEZA ----------------------------------------------------

function Clear-RecycleBin {
    # NO llamar a Clear-RecycleBin a secas: recursion. Usar cmdlet calificado.
    HR "VACIAR PAPELERA"
    # Contar antes: items via Shell + bytes via Get-RecycleBinBytes (misma fuente que el dashboard)
    $antesItems = 0
    $antesBytes = [double]0
    try { $antesBytes = [double](Get-RecycleBinBytes) } catch { $antesBytes = 0 }
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.NameSpace(0x0a)
        if ($null -ne $bin) {
            $items = @($bin.Items())
            $antesItems = $items.Count
            # Si Size COM falló en Get-RecycleBinBytes, sumar FolderItem.Size aquí como refuerzo
            if ($antesBytes -le 0) {
                foreach ($it in $items) {
                    try { $antesBytes += [double]$it.Size } catch { }
                }
            }
        }
    } catch { }
    if ($antesItems -eq 0) {
        # Fallback: contar archivos bajo $Recycle.Bin
        try {
            Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | ForEach-Object {
                $rb = Join-Path $_.Root '$Recycle.Bin'
                if (Test-Path -LiteralPath $rb) {
                    $antesItems += @(Get-ChildItem -LiteralPath $rb -Force -Recurse -File -EA SilentlyContinue).Count
                }
            }
        } catch { }
    }

    $ok = $false
    $metodo = ''
    try {
        Microsoft.PowerShell.Management\Clear-RecycleBin -Force -ErrorAction Stop
        $ok = $true
        $metodo = 'cmdlet Windows'
    } catch {
        WARN ("Cmdlet Clear-RecycleBin: {0}" -f $_.Exception.Message)
        try {
            $shell = New-Object -ComObject Shell.Application
            $bin = $shell.NameSpace(0x0a)
            if ($null -ne $bin) {
                try {
                    $bin.Self.InvokeVerb('Empty Recycle &Bin')
                } catch {
                    try { $bin.Self.InvokeVerb('Empty Recycle Bin') } catch { }
                }
                $ok = $true
                $metodo = 'Shell.Application'
            }
        } catch {
            WARN ("Shell.Application: {0}" -f $_.Exception.Message)
        }
        if (-not $ok) {
            $n = 0
            Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | ForEach-Object {
                $rb = Join-Path $_.Root '$Recycle.Bin'
                if (Test-Path -LiteralPath $rb) {
                    Get-ChildItem -LiteralPath $rb -Force -EA SilentlyContinue | ForEach-Object {
                        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -EA Stop; $n++ } catch { }
                    }
                }
            }
            if ($n -gt 0) {
                $ok = $true
                $metodo = 'por volumen'
                if ($antesItems -eq 0) { $antesItems = $n }
            }
        }
    }

    if ($ok) {
        if ($antesItems -gt 0) {
            $sz = if ($antesBytes -gt 0) { " ($(Human $antesBytes))" } else { '' }
            OK ("Papelera vaciada: {0} elemento(s){1}. Metodo: {2}." -f $antesItems, $sz, $metodo)
        } else {
            OK ("Papelera vaciada (estaba vacia o no se pudo contar). Metodo: {0}." -f $metodo)
        }
    } else {
        WARN "No se pudo vaciar la papelera (archivos en uso, permisos o ya vacia)."
    }
    return $ok
}

function Clear-WUCache {
    Stop-Svc wuauserv,bits | Out-Null
    $total = [double]0
    foreach ($p in @("$env:SystemRoot\SoftwareDistribution\Download", "$env:SystemRoot\SoftwareDistribution\DataStore\Logs")) {
        if (Test-Path $p) {
            $total += [double](Purge-Folder $p "WU $(Split-Path $p -Leaf)")
        }
    }
    Start-Svc bits,wuauserv | Out-Null
    OK ("Windows Update cache: {0} liberados (total aprox.)" -f (Human $total))
    return $true
}

function Clear-TempFiles {
    # CONFIANZA: solo TEMP reales. WU/CBS/WER/INetCache tienen sus propias herramientas.
    $before = [double]0
    $paths = @(
        "$env:TEMP",
        "$env:SystemRoot\Temp",
        "$env:LOCALAPPDATA\Temp"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try { $before += [double]((Get-ChildItem $p -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum) } catch { }
        }
    }
    $count = 0
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Force -EA SilentlyContinue | ForEach-Object {
            try {
                if ($_.PSIsContainer) {
                    $count += @(Get-ChildItem $_.FullName -Recurse -File -Force -EA SilentlyContinue).Count
                    Remove-Item $_.FullName -Recurse -Force -EA Stop
                } else {
                    $count++
                    Remove-Item $_.FullName -Force -EA Stop
                }
            } catch { }
        }
    }
    $after = [double]0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try { $after += [double]((Get-ChildItem $p -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum) } catch { }
        }
    }
    $freed = [math]::Max(0, $before - $after)
    OK ("Temporales (solo TEMP): {0} elementos tocados, {1} liberados (aprox.)" -f $count, (Human $freed))
    INFO "No toca Windows Update, CBS ni WER (usa esas herramientas si hace falta)."
    INFO "Si el numero es bajo, quedan archivos en uso. Cerra apps y repeti."
    return $true
}

function Clear-BrowserCache {
    $count = 0
    $running = @(Get-Process -Name 'msedge','chrome','brave','opera','firefox' -EA 0)
    if ($running.Count -gt 0) {
        WARN 'Hay navegadores abiertos. DeMente NO los cierra solo (Confianza v1.0.0.12).'
        INFO 'Cerra el navegador y volve a ejecutar esta limpieza para liberar todo el cache.'
        INFO 'Se intentara borrar igual lo que no este bloqueado.'
    }
    $roots = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:APPDATA\Opera Software\Opera Stable",
        "$env:APPDATA\Opera Software\Opera GX Stable"
    )
    foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem $root -Directory -EA 0 | ForEach-Object {
                foreach ($name in @('Cache','Code Cache','GPUCache','DawnCache','GrShaderCache','Service Worker\CacheStorage')) {
                    $p = Join-Path $_.FullName $name
                    if (Test-Path $p) { $count += @(Get-ChildItem $p -Recurse -File -EA 0).Count; Remove-Item "$p\*" -Recurse -Force -EA 0 }
                }
            }
        }
    }
    $ffBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffBase) {
        Get-ChildItem $ffBase -Directory -EA 0 | ForEach-Object {
            foreach ($name in @('cache2','startupCache','thumbnails')) {
                $p = Join-Path $_.FullName $name
                if (Test-Path $p) { $count += @(Get-ChildItem $p -Recurse -File -EA 0).Count; Remove-Item "$p\*" -Recurse -Force -EA 0 }
            }
        }
    }
    OK "Cachés de navegadores limpiadas ($count archivos; perfiles y contraseñas conservados)"
    return $true
}

function Clear-ThumbCache {
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $exp = ($null -ne (Get-Process explorer -EA 0))
    if ($exp) {
        WARN "AVISO: el escritorio va a parpadear un momento - es normal (hay que cerrar Explorer para liberar los .db)."
        Stop-Process -Name explorer -Force -EA 0
        Start-Sleep -Milliseconds 700
    }
    $files = @()
    if (Test-Path -LiteralPath $dir) {
        $files = @(Get-ChildItem -LiteralPath $dir -Force -File -EA SilentlyContinue |
            Where-Object { $_.Name -match '^(thumbcache_|iconcache_).+\.db$' -or $_.Name -eq 'iconcache.db' })
    }
    $bytes = [double]0
    $count = 0
    foreach ($f in $files) {
        try { $bytes += [double]$f.Length } catch { }
        try { Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $count++ } catch { }
    }
    if ($exp) { Start-Process explorer }
    OK ("Cache de miniaturas/iconos: {0} archivo(s), {1} liberados" -f $count, (Human $bytes))
    INFO "Incluye thumbcache_*.db (vistas previas de fotos/videos, tambien de archivos ya borrados) e iconcache si estaba libre."
    INFO "Windows regenera la cache al volver a abrir carpetas con imagenes."
    return $true
}

function Clear-CrashDumps {
    $n = 0
    $bytes = [double]0
    foreach ($p in @("$env:SystemRoot\Minidump", "$env:LOCALAPPDATA\CrashDumps")) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Force -File -EA SilentlyContinue | ForEach-Object {
            try { $bytes += [double]$_.Length; Remove-Item $_.FullName -Force -EA Stop; $n++ } catch { }
        }
    }
    if (Test-Path "$env:SystemRoot\MEMORY.DMP") {
        try {
            $f = Get-Item "$env:SystemRoot\MEMORY.DMP" -EA Stop
            $bytes += [double]$f.Length
            Remove-Item $f.FullName -Force -EA Stop
            $n++
        } catch { }
    }
    OK ("Volcados de error: {0} archivos, {1} liberados" -f $n, (Human $bytes))
    return $true
}

function Clear-InstallerLogs {
    $before = [double]0
    $patterns = @(
        "$env:SystemRoot\Logs\CBS\*.log",
        "$env:SystemRoot\Logs\CBS\*.cab",
        "$env:SystemRoot\Logs\DISM\*.log",
        "$env:SystemRoot\Logs\WindowsUpdate\*.etl",
        "$env:SystemRoot\Logs\WindowsUpdate\*.log",
        "$env:TEMP\*.log",
        "$env:SystemRoot\SoftwareDistribution\ReportingEvents.log",
        "$env:LOCALAPPDATA\Temp\*.log"
    )
    $count = 0
    foreach ($pat in $patterns) {
        $files = @(Get-ChildItem $pat -Force -File -EA SilentlyContinue)
        foreach ($f in $files) {
            try { $before += [double]$f.Length } catch { }
            try { Remove-Item $f.FullName -Force -EA Stop; $count++ } catch { }
        }
    }
    # Carpetas de panther / setup
    foreach ($dir in @("$env:SystemRoot\Panther","$env:SystemRoot\inf")) {
        if (Test-Path $dir) {
            Get-ChildItem $dir -Filter "*.log" -Recurse -Force -EA SilentlyContinue | ForEach-Object {
                try { $before += [double]$_.Length; Remove-Item $_.FullName -Force -EA Stop; $count++ } catch { }
            }
        }
    }
    OK ("Registros: {0} archivos eliminados, {1} liberados (aprox.)" -f $count, (Human $before))
    if ($count -lt 5) { INFO "Pocos logs borrables ahora. Es normal si el sistema esta limpio o los archivos estan bloqueados." }
    return $true
}

function Clear-StoreCache {
    wsreset.exe 2>$null
    Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache\*" -Recurse -Force -EA 0
    OK "Caché de Microsoft Store limpiada"
    return $true
}

function Clear-Prefetch {
    Clear-WDMFiles -Paths @("$env:SystemRoot\Prefetch\*.pf") -Label "Prefetch" | Out-Null
    return $true
}

function Clear-TeamsCache {
    $teamsRunning = $null -ne (Get-Process -Name "Teams","ms-teams" -EA 0 | Select-Object -First 1)
    if ($teamsRunning) {
        WARN "Teams esta corriendo - cerrandolo para limpiar..."
        Stop-Process -Name "Teams","ms-teams" -Force -EA 0
        Start-Sleep -Milliseconds 1500
    }
    $count = 0
    foreach ($p in @(
        "$env:APPDATA\Microsoft\Teams\Cache\*",
        "$env:APPDATA\Microsoft\Teams\blob_storage\*",
        "$env:APPDATA\Microsoft\Teams\GPUCache\*"
    )) { $count += (Get-ChildItem $p -File -EA 0).Count; Remove-Item $p -Recurse -Force -EA 0 }
    OK "Caché de Teams limpiada ($count archivos)"
    return $true
}

function Clear-DiscordCache {
    if(-not(Test-Path "$env:APPDATA\discord")){ WARN "Discord: no instalado"; return $false }
    Remove-Item "$env:APPDATA\discord\Cache\*" -Recurse -Force -EA 0
    OK "Caché de Discord limpiada"
    return $true
}

function Clear-SpotifyCache {
    if(-not(Test-Path "$env:LOCALAPPDATA\Spotify")){ WARN "Spotify: no instalado"; return $false }
    Remove-Item "$env:LOCALAPPDATA\Spotify\Storage\*" -Recurse -Force -EA 0
    OK "Caché de Spotify limpiada"
    return $true
}

function Clear-VSCodeCache {
    if(-not(Test-Path "$env:APPDATA\Code")){ WARN "VS Code: no instalado"; return $false }
    Remove-Item "$env:APPDATA\Code\Cache\*" -Recurse -Force -EA 0
    Remove-Item "$env:APPDATA\Code\CachedData\*" -Recurse -Force -EA 0
    OK "Caché de VS Code limpiada"
    return $true
}

function Clear-DeliveryOpt {
    $p="$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
    if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -EA 0 }
    OK "Delivery Optimization limpiado"
    return $true
}

function Clear-BitsCache {
    try {
        Get-BitsTransfer -AllUsers -EA SilentlyContinue | Where-Object { $_.JobState -in @('Transferred','Error','Cancelled','Acknowledged') } | ForEach-Object {
            try { Remove-BitsTransfer -BitsJob $_ -Confirm:$false -EA SilentlyContinue } catch { }
        }
    } catch { }
    $p = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"
    if (Test-Path $p) {
        Get-ChildItem $p -Force -EA SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue } catch { }
        }
    }
    OK "Cache BITS limpiada (trabajos terminados + Downloader)"
    return $true
}

function Clear-OfficeCache {
    $count = 0
    foreach ($ver in @("16.0","15.0","14.0")) {
        $p = "$env:LOCALAPPDATA\Microsoft\Office$ver\OfficeFileCache"
        if (Test-Path $p) { $count += (Get-ChildItem $p -Recurse -File -EA 0).Count; Remove-Item "$p\*" -Recurse -Force -EA 0 }
    }
    OK "Caché de Office limpiada ($count archivos)"
    return $true
}

function Clear-DxDiagLogs {
    $count = 0
    foreach ($p in @("$env:TEMP\DxDiag*.txt","$env:USERPROFILE\Desktop\DxDiag*.txt")) {
        $files = Get-ChildItem $p -EA 0
        foreach ($f in $files) { try { Remove-Item $f.FullName -Force -EA Stop; $count++ } catch {} }
    }
    OK "$count archivo(s) DxDiag eliminados"
    return $true
}

function Clear-FontCache {
    Stop-Service FontCache -Force -EA 0 | Out-Null
    $dirs = @(
        "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache",
        "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache3.0.0.0"
    )
    foreach ($d in $dirs) { if (Test-Path $d) { Remove-Item "$d\*" -Force -EA 0 } }
    Start-Service FontCache -EA 0 | Out-Null
    OK "Caché de fuentes limpiada y regenerada"
    return $true
}

function Clear-ThumbnailDB {
    $c=0
    Get-ChildItem "$env:USERPROFILE" -Recurse -Filter "Thumbs.db" -Force -EA 0 | ForEach-Object { Remove-Item $_.FullName -Force -EA 0; $c++ }
    OK "$c archivos Thumbs.db eliminados"
    return $true
}

function Clear-StandbyMem {
    try {
        Add-Type -TypeDefinition @"
using System;using System.Runtime.InteropServices;
public class MemHelper {
    [DllImport("kernel32.dll")] public static extern bool SetSystemFileCacheSize(IntPtr mn,IntPtr mx,uint f);
    public static void Flush(){SetSystemFileCacheSize(new IntPtr(-1),new IntPtr(-1),0);}
}
"@ -EA 0
        [MemHelper]::Flush()
        OK "Memoria en espera (caché de RAM del sistema) liberada"
    } catch {
        INFO "Memoria en espera: se libera sola en el próximo reinicio"
    }
    return $true
}

<#
.SYNOPSIS
    Ejecuta un .exe SIN ventana externa, con salida a archivo temporal (no hay
    deadlock de buffer), progreso en % cada 10 puntos, latido cada 30 s y
    timeout con corte del arbol de procesos. Devuelve el ExitCode (-1 = timeout/fallo).
#>

<#
.SYNOPSIS
    Mata un arbol de procesos sin imprimir "CORRECTO: el proceso ... ha sido terminado"
    (mensaje localizado de taskkill que asusta en la consola de DeMente).
#>
function Stop-WDMProcessTree {
    param([Parameter(Mandatory)][int]$ProcessId)
    if ($ProcessId -le 0) { return }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $psi.Arguments = "/PID $ProcessId /T /F"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($p) {
            $null = $p.StandardOutput.ReadToEnd()
            $null = $p.StandardError.ReadToEnd()
            $p.WaitForExit(15000) | Out-Null
        }
    } catch { }
}

function Invoke-WDMExe {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @(),
        [int]$TimeoutMin = 20,
        [string]$Label = ''
    )
    if (-not $Label) { $Label = Split-Path $File -Leaf }
    $out = Join-Path $env:TEMP ("dm_exe_" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + ".log")
    $err = $out + ".err"
    $p = $null
    $code = -1
    try {
        $sp = @{ FilePath = $File; RedirectStandardOutput = $out; RedirectStandardError = $err; NoNewWindow = $true; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments.Count -gt 0) { $sp['ArgumentList'] = $Arguments }
        $p = Start-Process @sp
        $null = $p.Handle   # evita ExitCode nulo en Windows PowerShell 5.1
        $inicio = Get-Date
        $ultimoPct = -10
        $ultimoLatido = Get-Date
        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 1000
            $txt = ''
            try {
                $fs = [System.IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
                try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Default); $txt = $sr.ReadToEnd() } finally { $fs.Close() }
            } catch { }
            $m = [regex]::Matches($txt, '(\d{1,3})(?:[.,]\d)?\s*%')
            if ($m.Count -gt 0) {
                $pct = [int]$m[$m.Count - 1].Groups[1].Value
                if ($pct -le 100 -and $pct -ge ($ultimoPct + 10)) {
                    INFO ("{0}: {1}%" -f $Label, $pct)
                    $ultimoPct = $pct
                    $ultimoLatido = Get-Date
                }
            }
            if (((Get-Date) - $ultimoLatido).TotalSeconds -ge 20) {
                INFO ("{0}: sigue trabajando ({1} min). No canceles: sigue en curso." -f $Label, [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1))
                $ultimoLatido = Get-Date
            }
            if (((Get-Date) - $inicio).TotalMinutes -ge $TimeoutMin) {
                WARN ("{0}: tiempo maximo ({1} min) superado, se corta." -f $Label, $TimeoutMin)
                try { Stop-WDMProcessTree -ProcessId $p.Id } catch { }
                return -1
            }
        }
        $p.WaitForExit()
        $code = $p.ExitCode
        if ($null -eq $code) { $code = 0 }
    } catch {
        WARN ("{0}: no se pudo ejecutar ({1})" -f $Label, $_.Exception.Message)
        return -1
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }
    return [int]$code
}

function Clear-WindowsOld {
    INFO "Limpieza de componentes via DISM (puede tardar varios minutos, todo dentro de DeMente)..."
    $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
    if (Test-Path $dism) {
        $rc = Invoke-WDMExe -File $dism -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart') -TimeoutMin 30 -Label 'DISM'
        if ($rc -eq 0 -or $rc -eq 3010) { OK "DISM StartComponentCleanup finalizado" }
        else { WARN "DISM termino con codigo $rc (puede haber un reinicio pendiente)" }
    } else { WARN "dism.exe no encontrado" }
    $wo = Join-Path $env:SystemDrive 'Windows.old'
    if (Test-Path $wo) {
        INFO "Tomando permisos sobre Windows.old y eliminandolo..."
        $null = Invoke-WDMExe -File (Join-Path $env:SystemRoot 'System32\takeown.exe') -Arguments @('/F', $wo, '/R', '/A', '/D', 'S') -TimeoutMin 15 -Label 'takeown'
        $null = Invoke-WDMExe -File (Join-Path $env:SystemRoot 'System32\icacls.exe') -Arguments @($wo, '/grant', '*S-1-5-32-544:(OI)(CI)F', '/T', '/C', '/Q') -TimeoutMin 15 -Label 'icacls'
        $null = Invoke-WDMExe -File (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments @('/c', 'rd', '/s', '/q', "`"$wo`"") -TimeoutMin 20 -Label 'Windows.old'
    }
    if (-not (Test-Path $wo)) { OK "Windows.old eliminado / no presente" }
    else { WARN "Windows.old parcialmente eliminado - reinicia y vuelve a ejecutar" }
    return $true
}

function Clear-CBSLogs {
    $count=(Get-ChildItem "$env:SystemRoot\Logs\CBS\*.log" -File -EA 0).Count
    Remove-Item "$env:SystemRoot\Logs\CBS\*.log" -Force -EA 0
    OK "Registros de CBS limpiados ($count archivos)"
    return $true
}

function Clear-D3DCache {
    $rutas = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\VkCache"
    )
    $total = 0
    foreach ($r in $rutas) {
        if (Test-Path $r) {
            $n = (Get-ChildItem $r -Recurse -File -EA 0).Count
            Remove-Item "$r\*" -Recurse -Force -EA 0
            $total += $n
        }
    }
    OK "Caché de sombreadores limpiada ($total archivos)"
    return $true
}

# -- FUNCIONES YARA ------------------------------------------------------------

function Get-WDMYaraExe {
    $yaraHome=Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    $bin=Join-Path $yaraHome 'bin'
    foreach($n in @('yara64.exe','yara.exe')){ $p=Join-Path $bin $n; if(Test-Path $p){return $p} }
    return $null
}

function Get-WDMProxy {
    try{
        $p=[System.Net.WebRequest]::DefaultWebProxy
        if($p){$u=$p.GetProxy([Uri]'https://api.github.com/');if($u -and $u.AbsoluteUri -ne 'https://api.github.com/'){return $u.AbsoluteUri}}
    }catch{}
    return ''
}

function Update-WDMYara {
    HR "ACTUALIZACION DEL MOTOR YARA"
    $yaraHome=Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    $bin=Join-Path $yaraHome 'bin'; $rules=Join-Path $yaraHome 'rules'
    foreach($d in @($yaraHome,$bin,$rules)){if(-not(Test-Path $d)){New-Item $d -ItemType Directory -Force|Out-Null}}
    $proxy=Get-WDMProxy;if($proxy){INFO "Proxy detectado: $proxy"}else{INFO "Usando la configuracion de red de Windows."}
    try{
        $api='https://api.github.com/repos/VirusTotal/yara/releases?per_page=15'
        $rels=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='DeMente-Windows'} -UseBasicParsing -EA Stop
        $rel=$null; $asset=$null
        foreach($candidate in @($rels)){
            $todos=@($candidate.assets|Where-Object{$_.name -match 'win(32|64).*\.zip$|windows.*\.zip$'})
            if($todos.Count -eq 0){continue}
            $a=@($todos|Where-Object{$_.name -match 'win64|x64|amd64'}|Select-Object -First 1)[0]
            if(-not $a){$a=$todos[0]}
            if($a){$rel=$candidate;$asset=$a;break}
        }
        if(-not $rel){throw 'Ninguna de las ultimas versiones publicadas trae un paquete Windows reconocible.'}
        if($rel -ne $rels[0]){INFO "La ultima version ($($rels[0].tag_name)) no trae ZIP de Windows. Usando $($rel.tag_name) en su lugar."}

        $zip=Join-Path $env:TEMP ('demente_yara_'+[guid]::NewGuid().ToString('N')+'.zip')
        INFO "Descargando YARA $($rel.tag_name) ($([math]::Round($asset.size/1KB,0)) KB esperados)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -EA Stop

        if (-not (Test-Path $zip)) { throw 'La descarga no genero ningun archivo.' }
        $tamDescargado = (Get-Item $zip).Length
        INFO "Descargado: $(Human $tamDescargado)"
        if ($asset.size -and $tamDescargado -lt ($asset.size * 0.9)) {
            $muestra = ''
            try { $muestra = (Get-Content $zip -Raw -Encoding Byte -TotalCount 200 -EA 0) } catch {}
            $esTexto = $false
            try { $esTexto = ([System.Text.Encoding]::ASCII.GetString((Get-Content $zip -Raw -Encoding Byte -TotalCount 4 -EA 0)) -notmatch 'PK') } catch {}
            if ($esTexto) {
                throw "La descarga parece haber sido interceptada (llego un archivo mas chico y no es un ZIP valido). Es probable que el proxy/firewall ($proxy) este bloqueando la descarga del binario aunque permite consultar la API de GitHub. Proba descargarlo manualmente desde $($asset.browser_download_url) y copialo a: $bin\yara64.exe"
            } else {
                throw "La descarga llego incompleta ($(Human $tamDescargado) de $(Human $asset.size) esperados). Puede ser un corte de red o del proxy. Volve a intentar."
            }
        }

        $tmp=Join-Path $env:TEMP ('demente_yara_'+[guid]::NewGuid().ToString('N'))
        try {
            Expand-Archive $zip $tmp -Force -EA Stop
        } catch {
            throw "El archivo descargado no es un ZIP valido (posible bloqueo del proxy en la descarga del binario). Detalle: $($_.Exception.Message)"
        }
        $exe=Get-ChildItem $tmp -Recurse -File -EA 0|Where-Object{$_.Name -match '^yara(32|64)?\.exe$'}|Select-Object -First 1
        if(-not $exe){
            $encontrados = @(Get-ChildItem $tmp -Recurse -File -EA 0 | Select-Object -ExpandProperty Name)
            $detalle = if ($encontrados.Count -gt 0) { "Archivos encontrados en el paquete: $($encontrados -join ', ')" } else { "El paquete extraido esta vacio." }
            throw "El paquete no contiene yara.exe/yara64.exe. $detalle"
        }
        if ($exe.Name -match '32') { WARN "Se instalo la version de 32 bits (no se encontro la de 64 bits para $($rel.tag_name)). Funciona igual en Windows de 64 bits." }
        Copy-Item $exe.FullName (Join-Path $bin 'yara64.exe') -Force
        Set-Content (Join-Path $bin 'version.txt') $rel.tag_name -Encoding UTF8
        Remove-Item $zip,$tmp -Recurse -Force -EA 0
        OK "Motor YARA actualizado: $($rel.tag_name)"

        $reglasExistentes = @(Get-ChildItem $rules -Filter '*.yar*' -File -EA 0)
        if ($reglasExistentes.Count -eq 0) {
            INFO "No hay reglas instaladas todavia. Descargando un set de reglas por defecto..."
            Update-WDMYaraRules | Out-Null
        }
        return $true
    }catch{ERR "No se pudo actualizar YARA: $($_.Exception.Message)";return $false}
}

function Update-WDMYaraRules {
    HR "DESCARGA DE REGLAS YARA (YARA Forge - set Core)"
    $yaraHome=Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    $rules=Join-Path $yaraHome 'rules'
    if(-not(Test-Path $rules)){New-Item $rules -ItemType Directory -Force|Out-Null}
    try{
        $url='https://github.com/YARAHQ/yara-forge/releases/latest/download/yara-forge-rules-core.zip'
        $zip=Join-Path $env:TEMP ('demente_yararules_'+[guid]::NewGuid().ToString('N')+'.zip')
        INFO "Descargando set de reglas 'Core' de YARA Forge (alta precision, bajo falso positivo)..."
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -EA Stop

        if(-not (Test-Path $zip)){throw 'La descarga no genero ningun archivo.'}
        $tam=(Get-Item $zip).Length
        INFO "Descargado: $(Human $tam)"
        if($tam -lt 10KB){throw "La descarga parece incompleta o bloqueada por el proxy ($(Human $tam)). Proba de nuevo o descargala manualmente desde $url y copia los archivos .yar a: $rules"}

        $tmp=Join-Path $env:TEMP ('demente_yararules_'+[guid]::NewGuid().ToString('N'))
        try { Expand-Archive $zip $tmp -Force -EA Stop } catch { throw "El archivo descargado no es un ZIP valido (posible bloqueo del proxy). Detalle: $($_.Exception.Message)" }

        $peligrosos = @(Get-ChildItem $tmp -Recurse -File -EA 0 | Where-Object { $_.Extension -match '^\.(exe|dll|bat|cmd|com|scr|ps1|vbs|js|msi|jar|hta)$' })
        if ($peligrosos.Count -gt 0) {
            throw "El paquete descargado contiene archivos ejecutables inesperados ($($peligrosos.Name -join ', ')). Se aborta por seguridad: un paquete de reglas legitimo nunca deberia traer ejecutables."
        }

        $yars = @(Get-ChildItem $tmp -Recurse -File -EA 0 | Where-Object { $_.Extension -match '^\.(yar|yara)$' })
        if ($yars.Count -eq 0) { throw 'El paquete no contiene archivos de reglas (.yar/.yara).' }
        foreach ($f in $yars) { Copy-Item $f.FullName (Join-Path $rules $f.Name) -Force }
        Remove-Item $zip,$tmp -Recurse -Force -EA 0
        OK "$($yars.Count) archivo(s) de reglas instalados (set 'Core' de YARA Forge)."
        INFO "Fuente: https://github.com/YARAHQ/yara-forge (proyecto publico de la comunidad de seguridad)."
        return $true
    } catch { ERR "No se pudieron descargar las reglas YARA: $($_.Exception.Message)"; return $false }
}

function Get-WDMYaraStatus {
    $yaraHome=Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    $bin=Join-Path $yaraHome 'bin'; $rules=Join-Path $yaraHome 'rules'
    $exe=Get-WDMYaraExe;$v=''
    $vf=Join-Path $bin 'version.txt';if(Test-Path $vf){$v=(Get-Content $vf -Raw -EA 0).Trim()}
    [pscustomobject]@{Installed=[bool]$exe;Path=$exe;Version=$v;Rules=@(Get-ChildItem $rules -Filter '*.yar*' -File -EA 0).Count;Proxy=(Get-WDMProxy)}
}

function Invoke-WDMYaraScan {
    param([string[]]$Paths,[switch]$Recursive)
    $yaraHome=Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    $rules=@(Get-ChildItem (Join-Path $yaraHome 'rules') -Filter '*.yar*' -File -EA 0)
    $exe=Get-WDMYaraExe
    if(-not $exe){WARN "El motor YARA no esta instalado. Ejecuta la actualizacion.";return @()}
    if($rules.Count -eq 0){WARN "No hay reglas YARA instaladas.";return @()}
    $targets=@()
    foreach($p in $Paths){
        if(Test-Path $p -PathType Leaf){ $targets+=$p }
        elseif(Test-Path $p -PathType Container){
            if($Recursive){ $targets+=@(Get-ChildItem $p -Recurse -File -EA 0 | Select-Object -ExpandProperty FullName) }
            else { $targets+=@(Get-ChildItem $p -File -EA 0 | Select-Object -ExpandProperty FullName) }
        }
    }
    INFO ("YARA: {0} regla(s), {1} archivo(s). Puede tardar; avisos cada ~20 s." -f $rules.Count, $targets.Count)
    $hits=@()
    $i=0
    $lastBeat=Get-Date
    foreach($t in $targets){
        $i++
        if(((Get-Date)-$lastBeat).TotalSeconds -ge 20){
            INFO ("YARA: {0}/{1} archivos..." -f $i, $targets.Count)
            $lastBeat=Get-Date
        }
        foreach($r in $rules){
            try{
                $o=& $exe $r.FullName $t 2>$null
                foreach($line in @($o)){
                    if($line){
                        $parts=$line -split '\s+',2
                        $hits+=[pscustomobject]@{Rule=$parts[0];Path=$(if($parts.Count -gt 1){$parts[1]}else{$t})}
                    }
                }
            }catch{}
        }
    }
    return $hits
}

function Show-WDMYaraQuick {
    HR "ESCANEO YARA RAPIDO"
    Write-Host "Solo Descargas y TEMP (no todo el disco)."
    INFO "Si no ves %: igual esta en curso. Avisos cada ~20 s."
    $hits=@(Invoke-WDMYaraScan -Paths @("$env:USERPROFILE\Downloads", $env:TEMP))
    if($hits.Count -eq 0){ OK "Escaneo YARA completado: 0 coincidencias. Sin amenazas segun las reglas instaladas." }
    else {
        ERR ("Escaneo YARA: {0} coincidencia(s)." -f $hits.Count)
        $hits | ForEach-Object { ERR ("{0} -> {1}" -f $_.Rule, $_.Path) }
    }
    return $true
}

function Show-WDMYaraCustom {
    HR "ESCANEO YARA PERSONALIZADO"
    try { Add-Type -AssemblyName System.Windows.Forms -EA 0 } catch { }
    $dlg=New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description='Elegi una carpeta para escanear con YARA'
    $dlg.ShowNewFolderButton=$false
    if($dlg.ShowDialog() -ne 'OK'){ INFO "Cancelado por el usuario."; return $true }
    INFO ("Carpeta: {0} (incluye subcarpetas)." -f $dlg.SelectedPath)
    $hits=@(Invoke-WDMYaraScan -Paths @($dlg.SelectedPath) -Recursive)
    if($hits.Count -eq 0){ OK "Escaneo YARA completado: 0 coincidencias." }
    else {
        ERR ("Escaneo YARA: {0} coincidencia(s)." -f $hits.Count)
        $hits | ForEach-Object { ERR ("{0} -> {1}" -f $_.Rule, $_.Path) }
    }
    return $true
}

# -- FUNCIONES DE SEGURIDAD ----------------------------------------------------

function Get-DefenderStatus {
    try {
        $status = Get-MpComputerStatus -EA Stop
        $threats = Get-MpThreatDetection -EA 0
        [pscustomobject]@{
            RealTimeProtection = $status.RealTimeProtectionEnabled
            AntivirusEnabled = $status.AntivirusEnabled
            SignatureVersion = $status.AntivirusSignatureVersion
            SignatureAge = $status.AntivirusSignatureAge
            Threats = @($threats).Count
        }
    } catch {
        [pscustomobject]@{RealTimeProtection=$false; AntivirusEnabled=$false; SignatureVersion="Error"; SignatureAge=999; Threats=0}
    }
}

function Show-DefenderStatus {
    HR "ESTADO DE MICROSOFT DEFENDER"
    Write-Host "Resumen legible del antivirus integrado de Windows. No cambia nada: solo informa."
    Write-Host ""
    $s = Get-DefenderStatus
    $rtp = if ($s.RealTimeProtection) { "Activa" } else { "Desactivada" }
    $av  = if ($s.AntivirusEnabled) { "Si" } else { "No" }
    ROW "Proteccion en tiempo real" $rtp
    ROW "Antivirus habilitado" $av
    ROW "Version de firmas" $s.SignatureVersion
    if ($null -ne $s.SignatureAge) {
        $edad = if ([int]$s.SignatureAge -eq 0) { "Al dia (hoy)" } elseif ([int]$s.SignatureAge -eq 1) { "1 dia" } else { "$($s.SignatureAge) dias" }
        ROW "Antiguedad de firmas" $edad
    }
    ROW "Amenazas en historial" $s.Threats
    Write-Host ""
    if (-not $s.RealTimeProtection) {
        ERR "La proteccion en tiempo real esta apagada. Conviene activarla en Seguridad de Windows."
    } elseif ([int]$s.SignatureAge -gt 7) {
        WARN "Las firmas tienen mas de una semana. Actualiza desde Seguridad de Windows o con un escaneo."
    } else {
        OK "Defender responde bien: tiempo real activo y firmas recientes."
    }
    return $true
}

function Show-WDMYaraStatus {
    HR "ESTADO DEL MOTOR YARA"
    Write-Host "YARA es el motor de reglas local de DeMente (gratis, sin suscripcion)."
    Write-Host "No reemplaza a Defender: lo complementa para busquedas con reglas propias."
    Write-Host ""
    $s = Get-WDMYaraStatus
    if ($s.Installed) {
        ROW "Motor" "Instalado"
        ROW "Ruta" $s.Path
        ROW "Version" $(if ($s.Version) { $s.Version } else { "No informada" })
        ROW "Reglas cargadas" $s.Rules
        if ($s.Proxy) { ROW "Proxy detectado" $s.Proxy }
        Write-Host ""
        if ([int]$s.Rules -lt 1) {
            WARN "El motor esta, pero no hay reglas .yar. Usa Actualizar YARA o carga reglas en Documents\DeMente\security\yara\rules"
        } else {
            OK "YARA listo para escanear con $($s.Rules) regla(s)."
        }
    } else {
        ROW "Motor" "No instalado"
        Write-Host ""
        WARN "Todavia no esta el binario de YARA en este usuario."
        INFO "Desde Seguridad podes usar Actualizar YARA (descarga el motor gratis desde GitHub)."
    }
    return $true
}

function Scan-Defender {
    HR "ESCANEO DE WINDOWS DEFENDER"
    Write-Host "Escaneo RAPIDO (no revisa todo el disco). Puede tardar de 1 a 10 minutos."
    Write-Host "Vas a ver un aviso cada ~20 s mientras trabaja. El silencio total no deberia durar mucho."
    Write-Host ""
    try {
        INFO "1/3 Actualizando firmas..."
        Update-MpSignature -EA 0
        OK "Firmas actualizadas (o ya estaban al dia)"

        INFO "2/3 Escaneo rapido en curso..."
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $okScan = $false
        $errMsg = $null

        # Preferir MpCmdRun (suele existir y no traba la consola de la misma forma)
        $mpCmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
        if (-not (Test-Path $mpCmd)) {
            $mpCmd = Join-Path ${env:ProgramFiles(x86)} 'Windows Defender\MpCmdRun.exe'
        }
        if (Test-Path $mpCmd) {
            $outLog = Join-Path $env:TEMP ("demente_mpcmd_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".log")
            $p = Start-Process -FilePath $mpCmd -ArgumentList @('-Scan','-ScanType','1') -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError ($outLog + '.err')
            if ($p) { $null = $p.Handle }
            $lastBeat = Get-Date
            while (-not $p.HasExited) {
                Start-Sleep -Seconds 5
                if (((Get-Date) - $lastBeat).TotalSeconds -ge 20) {
                    INFO ("Escaneo en curso... {0:N0} s. Segui esperando." -f $sw.Elapsed.TotalSeconds)
                    $lastBeat = Get-Date
                }
            }
            $code = $p.ExitCode
            if ($null -eq $code) { $code = 0 }
            if ($code -eq 0) { $okScan = $true }
            else { $errMsg = "MpCmdRun termino con codigo $code" }
            Remove-Item $outLog, ($outLog + '.err') -Force -EA SilentlyContinue
        } else {
            # Fallback: Start-MpScan en Job + latido en este proceso
            $job = Start-Job -ScriptBlock {
                try {
                    Start-MpScan -ScanType QuickScan -ErrorAction Stop
                    'OK'
                } catch {
                    'ERR:' + $_.Exception.Message
                }
            }
            $lastBeat = Get-Date
            while ($job.State -eq 'Running') {
                Start-Sleep -Seconds 5
                if (((Get-Date) - $lastBeat).TotalSeconds -ge 20) {
                    INFO ("Escaneo en curso... {0:N0} s. Segui esperando." -f $sw.Elapsed.TotalSeconds)
                    $lastBeat = Get-Date
                }
            }
            $recv = @(Receive-Job $job -EA SilentlyContinue)
            Remove-Job $job -Force -EA SilentlyContinue
            $joined = ($recv -join ' ')
            if ($joined -match '^ERR:') { $errMsg = $joined.Substring(4) }
            else { $okScan = $true }
        }

        $mins = [math]::Round($sw.Elapsed.TotalMinutes, 1)
        if ($okScan) {
            OK ("Escaneo rapido completado en {0} min." -f $mins)
        } else {
            WARN ("El escaneo termino con avisos ({0}). Minutos: {1}" -f $(if($errMsg){$errMsg}else{'desconocido'}), $mins)
        }

        INFO "3/3 Historial reciente de amenazas..."
        $threats = @(Get-MpThreatDetection -EA SilentlyContinue)
        if ($threats.Count -gt 0) {
            foreach ($t in $threats) {
                ERR ("AMENAZA: {0} en {1}" -f $t.ThreatName, (($t.Resources) -join ', '))
            }
            WARN "Revisa Seguridad de Windows para cuarentena o detalles."
        } else {
            OK "Sin amenazas en el historial reciente de Defender."
        }
        return $true
    } catch {
        ERR "Error en escaneo: $($_.Exception.Message)"
        INFO "Si Defender lo administra la organizacion, la politica puede bloquear el escaneo."
        return $false
    }
}




function Show-SystemEventsHuman {
    HR "EVENTOS DEL SISTEMA (ultimas 48 h)"
    Write-Host "Solo errores y criticos. Muchos mensajes se repiten y no significan que la PC este rota."
    Write-Host ""
    $desde = (Get-Date).AddHours(-48)
    $ev = @()
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System','Application'; Level = 1,2; StartTime = $desde } -MaxEvents 40 -EA Stop)
    } catch {
        try {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1,2; StartTime = $desde } -MaxEvents 40 -EA Stop)
        } catch {
            WARN "No se pudieron leer los eventos: $($_.Exception.Message)"
            return $true
        }
    }
    if ($ev.Count -eq 0) {
        OK "No hay errores/criticos en las ultimas 48 horas."
        return $true
    }

    # Agrupar por proveedor + Id para no inundar
    $grupos = $ev | Group-Object { "{0}|{1}" -f $_.ProviderName, $_.Id } | Sort-Object Count -Descending
    $explicados = 0
    foreach ($g in ($grupos | Select-Object -First 15)) {
        $sample = $g.Group | Select-Object -First 1
        $prov = [string]$sample.ProviderName
        $id = [int]$sample.Id
        $nivel = [string]$sample.LevelDisplayName
        $msg = ([string]$sample.Message) -replace '\s+', ' '
        if ($msg.Length -gt 140) { $msg = $msg.Substring(0, 137) + '...' }
        $hint = $null
        if ($prov -match 'TPM' -and $id -eq 1801) {
            $hint = 'Aviso de Secure Boot/TPM (claves). Suele ser informativo; no explica lentitud diaria.'
        } elseif ($prov -match 'NETLOGON' -and $id -eq 3095) {
            $hint = 'PC en grupo de trabajo (no dominio). Normal en casa; se puede ignorar si no usas dominio.'
        } elseif ($prov -match 'Kernel-Power' -and $id -eq 41) {
            $hint = 'Apagado o reinicio brusco (corte de luz, forzado, BSOD). Si se repite, revisa fuente/estabilidad.'
        } elseif ($prov -match 'EventLog' -and $id -eq 6008) {
            $hint = 'El apagado anterior no fue limpio (relacionado con Kernel-Power 41).'
        } elseif ($prov -match 'DistributedCOM' -and $id -eq 10010) {
            $hint = 'Un componente COM no respondio a tiempo. Muy frecuente y casi nunca grave por si solo.'
        }
        ROW ("{0} x{1}" -f $nivel, $g.Count) ("{0} (Id {1})" -f $prov, $id)
        Write-Host ("      {0}" -f $msg) -ForegroundColor DarkGray
        if ($hint) {
            INFO ("  Que significa: {0}" -f $hint)
            $explicados++
        }
        Write-Host ""
    }
    if ($grupos.Count -gt 15) {
        INFO ("Hay {0} tipos de evento mas (no listados). Usa el Visor de eventos para el detalle completo." -f ($grupos.Count - 15))
    }
    OK ("Resumen: {0} eventos leidos, {1} tipos distintos." -f $ev.Count, $grupos.Count)
    if ($explicados -gt 0) {
        INFO "Los avisos TPM/NETLOGON/DCOM son ruido tipico en muchas PCs y no equivalen a 'virus' ni a fallo grave."
    }
    return $true
}

function Get-LocalUsers {
    HR "CUENTAS LOCALES"
    Get-LocalUser -EA 0 | ForEach-Object {
        $flags=@()
        if(-not $_.Enabled){$flags+="deshabilitada"}
        if($_.PasswordRequired -eq $false -and $_.Enabled){$flags+="SIN CONTRASENA"}
        ROW $_.Name ("$($_.Description)  [" + ($flags -join ", ") + "]")
        if ($_.PasswordRequired -eq $false -and $_.Enabled) { ERR "  Cuenta $($_.Name) activa y sin contrasena." }
    }
    Step "Miembros del grupo Administradores"
    Get-LocalGroupMember -Group "Administradores" -EA 0 | ForEach-Object { ROW $_.Name $_.ObjectClass }
}

# =============================================================================
# TRANSPARENCIA DE ARTEFACTOS DEL SISTEMA (antes: purga forense)
# -----------------------------------------------------------------------------
# Amcache, USBSTOR, ShellBags y los perfiles Wi-Fi guardados son los
# artefactos estandar que Windows usa para poder reconstruir que programas
# se ejecutaron, que dispositivos USB se conectaron y que carpetas se
# abrieron. Son exactamente lo que un peritaje o una auditoria de seguridad
# revisan primero. Por eso DeMente ya NO ofrece purgarlos: solo los muestra,
# para que el usuario entienda que datos guarda Windows sobre el uso de su
# propio equipo. Si necesitas gestionar retencion real de estos datos, la
# via correcta es la politica de auditoria de Windows, no borrar el pasado.
# =============================================================================

<#
.SYNOPSIS
    Muestra informacion sobre Amcache (historial de ejecutables) sin modificarlo.
#>
function Get-DMAmcacheInfo {
    HR "AMCACHE - HISTORIAL DE EJECUTABLES (SOLO LECTURA)"
    $amcPath = "C:\Windows\AppCompat\Programs\Amcache.hve"
    if (Test-Path -LiteralPath $amcPath) {
        try {
            $item = Get-Item -LiteralPath $amcPath -ErrorAction Stop
            ROW "Archivo" $amcPath
            ROW "Tamaño" (Human $item.Length)
            ROW "Ultima escritura" $item.LastWriteTime
            INFO "Amcache registra que ejecutables corrieron en este equipo. DeMente no lo modifica ni lo elimina."
        } catch {
            WARN "No se pudo leer metadatos de Amcache: $($_.Exception.Message)"
        }
    } else {
        INFO "Amcache no encontrado en la ruta esperada."
    }
}

<#
.SYNOPSIS
    Muestra los dispositivos USB registrados en USBSTOR sin modificarlos.
#>
function Get-DMUSBHistoryInfo {
    HR "USBSTOR - HISTORIAL DE DISPOSITIVOS USB (SOLO LECTURA)"
    $usbPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
    if (Test-Path -LiteralPath $usbPath) {
        try {
            $devices = @(Get-ChildItem -LiteralPath $usbPath -ErrorAction Stop)
            OK "$($devices.Count) dispositivo(s) USB con historial en el registro."
            foreach ($dev in $devices) { ROW "  Dispositivo" $dev.PSChildName }
        } catch {
            WARN "No se pudo leer USBSTOR: $($_.Exception.Message)"
        }
    } else {
        INFO "USBSTOR no encontrado (sin historial de USB)."
    }
}

<#
.SYNOPSIS
    Muestra cuantas claves ShellBags (memoria de carpetas) existen, sin borrarlas.
#>
function Get-DMShellBagsInfo {
    HR "SHELLBAGS - MEMORIA DE CARPETAS (SOLO LECTURA)"
    $shellPaths = @(
        "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        "HKCU:\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU:\Software\Microsoft\Windows\Shell\Bags"
    )
    $present = 0
    foreach ($p in $shellPaths) {
        if (Test-Path -LiteralPath $p) { $present++; ROW "  Clave presente" $p }
    }
    OK "$present de $($shellPaths.Count) claves ShellBags presentes."
    INFO "ShellBags recuerda que carpetas abriste y como las viste (iconos, orden). DeMente no las elimina."
}

<#
.SYNOPSIS
    Lista los perfiles Wi-Fi guardados sin eliminarlos.
#>
function Get-DMWiFiProfilesInfo {
    HR "REDES WIFI GUARDADAS (SOLO LECTURA)"
    try {
        $perfiles = netsh wlan show profiles 2>$null |
            Select-String "Perfil de usuario|All User Profile" |
            ForEach-Object { ($_ -split ":")[1].Trim() }
    } catch {
        WARN "No se pudo consultar netsh wlan: $($_.Exception.Message)"
        return
    }
    if (-not $perfiles) { INFO "No hay perfiles WiFi guardados."; return }
    OK "$(@($perfiles).Count) perfil(es) WiFi guardado(s)."
    foreach ($p in $perfiles) { ROW "  Red" $p }
    INFO "Para eliminar una red especifica: Configuracion > Red e Internet > Wi-Fi > Administrar redes conocidas."
}

# -- FUNCIONES DE PRIVACIDAD --------------------------------------------------

function Privacy-AdvertisingId {
    $k="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "Enabled" -Value 0 -Type DWord -EA 0
    OK "ID de publicidad desactivado"; return $true
}

function Privacy-Location {
    $k="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "Value" -Value "Deny" -Type String -EA 0
    OK "Ubicación bloqueada"; return $true
}

function Privacy-Telemetry {
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -EA 0
    Stop-Service DiagTrack -Force -EA 0 | Out-Null
    Set-Service DiagTrack -StartupType Disabled -EA 0 | Out-Null
    OK "Telemetría desactivada"; return $true
}

function Privacy-ActivityHistory {
    $k="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "EnableActivityFeed"    -Value 0 -Type DWord -EA 0
    Set-ItemProperty $k -Name "PublishUserActivities" -Value 0 -Type DWord -EA 0
    Set-ItemProperty $k -Name "UploadUserActivities"  -Value 0 -Type DWord -EA 0
    OK "Historial de actividad desactivado"; return $true
}

function Privacy-Microphone {
    $k="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "Value" -Value "Deny" -Type String -EA 0
    OK "Micrófono bloqueado"; return $true
}

function Privacy-Camera {
    $k="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "Value" -Value "Deny" -Type String -EA 0
    OK "Cámara bloqueada"; return $true
}

function Privacy-BingSearch {
    $k="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "BingSearchEnabled" -Value 0 -Type DWord -EA 0
    Set-ItemProperty $k -Name "CortanaConsent" -Value 0 -Type DWord -EA 0
    OK "Bing desactivado del menu inicio"; return $true
}

function Privacy-GameDVR {
    $k="HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "AppCaptureEnabled" -Value 0 -Type DWord -EA 0
    $k2="HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if(-not(Test-Path $k2)){New-Item $k2 -Force|Out-Null}
    Set-ItemProperty $k2 -Name "AllowGameDVR" -Value 0 -Type DWord -EA 0
    OK "GameDVR/Xbox Game Bar desactivado"; return $true
}

function Privacy-CloudClipboard {
    Set-ItemProperty "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 0 -Type DWord -EA 0
    $kp="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if(-not(Test-Path $kp)){New-Item $kp -Force|Out-Null}
    Set-ItemProperty $kp -Name "AllowClipboardHistory" -Value 0 -Type DWord -EA 0
    OK "Portapapeles en la nube desactivado"; return $true
}

function Privacy-SearchHighlights {
    $k="HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
    if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
    Set-ItemProperty $k -Name "IsDynamicSearchBoxEnabled" -Value 0 -Type DWord -EA 0
    OK "Destacados de búsqueda desactivados"; return $true
}

function Privacy-CEIP {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Value 0 -Type DWord -EA 0
    OK "Programa de mejora de la experiencia del cliente (CEIP) desactivado"
    INFO "Windows deja de enviar datos de uso 'para mejorar el producto'."
    return $true
}

function Privacy-TipsNotifications {
    $paths = @(
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338389Enabled"; V=0},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-310093Enabled"; V=0},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SoftLandingEnabled"; V=0},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"; N="ScoobeSystemSettingEnabled"; V=0},
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ShowSyncProviderNotifications"; V=0}
    )
    foreach ($x in $paths) {
        if (-not (Test-Path $x.P)) { New-Item $x.P -Force | Out-Null }
        Set-ItemProperty $x.P -Name $x.N -Value $x.V -Type DWord -EA 0
    }
    OK "Sugerencias, tips y notificaciones promocionales reducidas"
    INFO "Siguen las notificaciones importantes del sistema; se cortan los 'tips' y publicidad en el shell."
    return $true
}

function Privacy-Copilot {
    # Desactiva atajos y anclajes de Copilot / AI shell sin romper el sistema
    $keys = @(
        @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="ShowCopilotButton"; V=0},
        @{P="HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; N="TurnOffWindowsCopilot"; V=1},
        @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; N="TurnOffWindowsCopilot"; V=1}
    )
    foreach ($x in $keys) {
        if (-not (Test-Path $x.P)) { New-Item $x.P -Force | Out-Null }
        Set-ItemProperty $x.P -Name $x.N -Value $x.V -Type DWord -EA 0
    }
    OK "Copilot / atajos de IA del shell desactivados (donde el sistema lo permite)"
    INFO "No desinstala componentes del sistema; solo apaga la integracion visible."
    return $true
}

function Privacy-BackgroundApps {
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty $k -Name "GlobalUserDisabled" -Value 1 -Type DWord -EA 0
    OK "Apps en segundo plano limitadas de forma global"
    INFO "Algunas apps (Teams, correo) pueden tardar mas en avisar. Podes revertirlo si te molesta."
    return $true
}

function Clear-RecentDocs {
    try {
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -EA 0
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -EA 0
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -EA 0
        $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
        if (Test-Path $k) { Remove-Item $k -Recurse -Force -EA 0 }
        OK "Documentos recientes y listas de salto limpiados"
        INFO "No borra los archivos: solo la lista de 'archivos recientes' del menu Inicio y el Explorador."
    } catch {
        WARN "Limpieza parcial de recientes: $_"
    }
    return $true
}

function Clear-ClipboardData {
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA 0
        [System.Windows.Forms.Clipboard]::Clear()
        OK "Portapapeles vaciado"
    } catch {
        cmd /c "echo off | clip" 2>$null
        OK "Portapapeles vaciado (metodo alterno)"
    }
    return $true
}

function Clear-ErrorReports {
    $n = 0
    foreach ($p in @(
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\*"
    )) {
        $items = @(Get-ChildItem $p -Force -EA 0)
        $n += $items.Count
        Remove-Item $p -Recurse -Force -EA 0
    }
    OK "Informes de errores de Windows limpiados ($n elementos)"
    INFO "Son reportes tecnicos ya enviados o en cola; no afectan tus documentos."
    return $true
}

function Clear-DnsCache {
    ipconfig /flushdns 2>$null | Out-Null
    OK "Cache DNS vaciada"
    INFO "Util si una web 'no carga' o apunta al servidor viejo. No cambia tu configuracion de red."
    return $true
}

<#
.SYNOPSIS
    Borra los respaldos .reg propios de DeMente con mas de $DiasAConservar dias.
.DESCRIPTION
    Cada vez que DeMente cambia una clave de registro, guarda un .reg de
    respaldo (ver Backup-Reg). Es la red de seguridad para poder revertir
    a mano, pero con meses de uso se acumulan cientos de archivos chicos.
    Esta funcion informa cuanto ocupan y borra solo los mas viejos que
    $DiasAConservar dias, dejando siempre los recientes (los que de verdad
    sirven si algo salio mal hace poco). NO toca HealthHistory ni otros
    datos de diagnostico: solo .reg bajo Documents\DeMente\backups\registry.
.PARAMETER DiasAConservar
    Cuantos dias de respaldo se conservan sin tocar. Default: 30.
#>
function Clear-WDMOwnBackups {
    param(
        [int]$DiasAConservar = 7,
        [switch]$Todo
    )
    HR "RESPALDOS PROPIOS DE DEMENTE"
    $carpeta = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\registry'
    if (-not (Test-Path -LiteralPath $carpeta)) {
        INFO "Todavia no hay respaldos guardados."
        return
    }
    try {
        $todos = @(Get-ChildItem -LiteralPath $carpeta -Filter '*.reg' -File -EA Stop)
        $totalSize = ($todos | Measure-Object Length -Sum).Sum
        if ($Todo) {
            $viejos = $todos
            $etiqueta = 'todos'
        } else {
            $limite = (Get-Date).AddDays(-1 * $DiasAConservar)
            $viejos = @($todos | Where-Object { $_.LastWriteTime -lt $limite })
            $etiqueta = "de mas de $DiasAConservar dias"
        }
        $freedSize = ($viejos | Measure-Object Length -Sum).Sum

        OK "Respaldos totales: $($todos.Count) archivos, $(Human $totalSize)."
        if ($viejos.Count -eq 0) {
            INFO "Ninguno para borrar ($etiqueta). Nada que hacer."
        } else {
            $borrados = 0
            foreach ($f in $viejos) {
                try { Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $borrados++ }
                catch { WARN "No se pudo borrar '$($f.Name)': $($_.Exception.Message)" }
            }
            OK "Borrados $borrados respaldo(s) ($etiqueta) ($(Human $freedSize) liberados)."
            if (-not $Todo) {
                INFO "Quedan $($todos.Count - $borrados) respaldos recientes por si necesitas revertir algo."
            }
        }
    } catch {
        WARN "No se pudo revisar la carpeta de respaldos: $($_.Exception.Message)"
    }
}

function Clear-WDMSessionLogs {
    param(
        [int]$DiasAConservar = 7,
        [switch]$Todo
    )
    HR "REGISTROS DE SESION DE DEMENTE"
    $carpeta = Join-Path $env:USERPROFILE 'Documents\DeMente\registros'
    if (-not (Test-Path -LiteralPath $carpeta)) {
        INFO "Todavia no hay registros de sesion."
        return $true
    }
    try {
        $todos = @(Get-ChildItem -LiteralPath $carpeta -Filter 'sesion_*.log' -File -EA SilentlyContinue)
        $todos += @(Get-ChildItem -LiteralPath $carpeta -Filter '*.log' -File -EA SilentlyContinue | Where-Object { $_.Name -notmatch '^sesion_' })
        $todos = @($todos | Sort-Object FullName -Unique)
        $totalSize = ($todos | Measure-Object Length -Sum).Sum
        if ($Todo) {
            $viejos = $todos
            $etiqueta = 'todos'
        } else {
            $limite = (Get-Date).AddDays(-1 * $DiasAConservar)
            $viejos = @($todos | Where-Object { $_.LastWriteTime -lt $limite })
            $etiqueta = "de mas de $DiasAConservar dias"
        }
        $freedSize = ($viejos | Measure-Object Length -Sum).Sum
        OK "Registros totales: $($todos.Count) archivo(s), $(Human $totalSize)."
        if ($viejos.Count -eq 0) {
            INFO "Ninguno para borrar ($etiqueta)."
            return $true
        }
        $borrados = 0
        foreach ($f in $viejos) {
            try { Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $borrados++ }
            catch { WARN "No se pudo borrar '$($f.Name)': $($_.Exception.Message)" }
        }
        OK "Borrados $borrados registro(s) ($etiqueta) ($(Human $freedSize) liberados)."
        if (-not $Todo) {
            INFO "Quedan $($todos.Count - $borrados) recientes. Usa la opcion TODOS si queres vaciar la carpeta."
        }
    } catch {
        WARN "No se pudo limpiar registros: $($_.Exception.Message)"
    }
    return $true
}

function Clear-WDMAppsDeep {
    HR "CACHES DE APPS (lista blanca de cache)"
    Write-Host "Solo subcarpetas de cache conocidas. No se tocan cookies, historial, contraseñas ni datos de usuario."
    Write-Host "No se vacia Explorer, ni residuos genericos de AppData."
    Write-Host ""
    $u = $env:USERNAME
    $paths = @(
        "$env:APPDATA\discord\Cache",
        "$env:APPDATA\discord\Code Cache",
        "$env:APPDATA\discord\GPUCache",
        "$env:APPDATA\discord\Cache",
        "$env:LOCALAPPDATA\Discord\Cache",
        "$env:LOCALAPPDATA\Spotify\Cache",
        "$env:APPDATA\Spotify\Cache",
        "$env:APPDATA\Code\Cache",
        "$env:APPDATA\Code\CachedData",
        "$env:APPDATA\Code\GPUCache",
        "$env:APPDATA\Code\CachedExtensions",
        "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
        "$env:LOCALAPPDATA\Microsoft\Office\Cache",
        "$env:APPDATA\Microsoft\Teams\Cache",
        "$env:APPDATA\Microsoft\Teams\Code Cache",
        "$env:APPDATA\Microsoft\Teams\GPUCache",
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\DxcCache",
        "$env:LOCALAPPDATA\AMD\OglCache",
        "$env:LOCALAPPDATA\AMD\VkCache",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\Steam\htmlcache",
        "$env:LOCALAPPDATA\Steam\shadercache",
        "$env:LOCALAPPDATA\Steam\cache",
        "${env:ProgramFiles(x86)}\Steam\appcache",
        "${env:ProgramFiles(x86)}\Steam\depotcache",
        "${env:ProgramFiles(x86)}\Steam\logs",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs",
        "$env:LOCALAPPDATA\Battle.net\Cache",
        "$env:LOCALAPPDATA\Battle.net\Logs",
        "$env:APPDATA\Slack\Cache",
        "$env:APPDATA\Slack\GPUCache",
        "$env:APPDATA\Telegram Desktop\tdata\cache",
        "$env:APPDATA\Notion\Cache",
        "$env:LOCALAPPDATA\Notion\Cache",
        "$env:APPDATA\obs-studio\logs",
        "$env:APPDATA\obs-studio\Cache",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Adobe\Cache",
        "$env:LOCALAPPDATA\Adobe\Logs",
        "$env:LOCALAPPDATA\Adobe\Acrobat\Cache",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\cache",
        "$env:LOCALAPPDATA\Temp\Adobe",
        "$env:LOCALAPPDATA\Temp\Nvidia",
        "$env:LOCALAPPDATA\Temp\NVIDIA",
        "$env:LOCALAPPDATA\Temp\Steam",
        "$env:LOCALAPPDATA\Temp\Discord",
        "$env:LOCALAPPDATALow\Sun\Java\Deployment\cache",
        "$env:APPDATA\vlc\cache",
        "$env:APPDATA\obs-studio\logs",
        "C:\AMD",
        "$env:ProgramData\NVIDIA Corporation\Downloader",
        "$env:ProgramData\NVIDIA Corporation\GeForce Experience\logs"
    )
    $total = [double]0
    $n = 0
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not (Test-Path $p)) { continue }
        try {
            $sz = Get-Folder-Size $p
            $freed = Purge-Folder $p (Split-Path $p -Leaf)
            $total += [double]$freed
            $n++
        } catch { }
    }
    OK ("Caches de apps: {0} rutas tocadas, {1} liberados (aprox.)" -f $n, (Human $total))
    INFO "Si alguna app estaba abierta, parte de su cache pudo quedar bloqueada. Cerra y repetí."
    return $true
}

function Start-WDMCleanMgr {
    HR "LIMPIEZA PROFUNDA DE WINDOWS (integrada)"
    Write-Host "Reemplaza a cleanmgr: hace la limpieza equivalente dentro de DeMente,"
    Write-Host "sin ventanas externas. No toca documentos, drivers ni Windows.old."
    Write-Host ""
    $drv = $env:SystemDrive.TrimEnd('\')
    $libreAntes = [double]0
    try { $libreAntes = [double](New-Object System.IO.DriveInfo($drv)).AvailableFreeSpace } catch { }
    $total = [double]0
    $sys = $env:SystemRoot

    # 1) Temporales
    Step "Archivos temporales"
    foreach ($p in @($env:TEMP, "$sys\Temp")) {
        try { if ($p -and (Test-Path -LiteralPath $p)) { $total += [double](Purge-Folder $p $p) } } catch { }
    }

    # 2) Windows Update (descargas ya instaladas)
    Step "Cache de Windows Update"
    try {
        Stop-Svc wuauserv, bits | Out-Null
        foreach ($p in @("$sys\SoftwareDistribution\Download")) {
            if (Test-Path -LiteralPath $p) { $total += [double](Purge-Folder $p "WU Download") }
        }
    } catch { WARN "WU: $($_.Exception.Message)" }
    finally { try { Start-Svc bits, wuauserv | Out-Null } catch { } }

    # 3) Delivery Optimization
    Step "Optimizacion de distribucion"
    try {
        $p = "$sys\SoftwareDistribution\DeliveryOptimization"
        if (Test-Path -LiteralPath $p) { $total += [double](Purge-Folder $p "Delivery Optimization") }
    } catch { }

    # 4) Informes de error y volcados
    Step "Informes de error y volcados"
    foreach ($p in @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                     "$env:ProgramData\Microsoft\Windows\WER\Temp", "$sys\Minidump", "$env:LOCALAPPDATA\CrashDumps")) {
        try { if (Test-Path -LiteralPath $p) { $total += [double](Purge-Folder $p (Split-Path $p -Leaf)) } } catch { }
    }
    try {
        $md = "$sys\MEMORY.DMP"
        if (Test-Path -LiteralPath $md) {
            $len = [double](Get-Item -LiteralPath $md -Force).Length
            Remove-Item -LiteralPath $md -Force -ErrorAction Stop
            $total += $len
            OK ("MEMORY.DMP eliminado ({0})" -f (Human $len))
        }
    } catch { INFO "MEMORY.DMP en uso o sin permisos; se omite." }

    # 5) Miniaturas (sin cerrar el Explorador: lo que este en uso se omite)
    Step "Miniaturas"
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
        $n = 0; $bytes = [double]0
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^thumbcache_.+\.db$' } | ForEach-Object {
                    try { $l = [double]$_.Length; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $bytes += $l; $n++ } catch { }
                }
        }
        $total += $bytes
        OK ("Miniaturas: {0} archivos, {1} liberados" -f $n, (Human $bytes))
    } catch { }

    # 6) Historial de escaneos de Defender (cache, no afecta la proteccion)
    Step "Historial de escaneos de Defender"
    try {
        $p = "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Service"
        if (Test-Path -LiteralPath $p) { $total += [double](Purge-Folder $p "Defender historial") }
        else { INFO "Sin historial accesible." }
    } catch { INFO "Defender protege esa carpeta; se omite." }

    # 7) Papelera
    Step "Papelera de reciclaje"
    try { $null = Clear-RecycleBin } catch { WARN "Papelera: $($_.Exception.Message)" }

    # 8) Componentes de Windows (WinSxS) - sin ventana externa, con timeout
    Step "Componentes de Windows (DISM StartComponentCleanup)"
    $dism = Join-Path $sys 'System32\dism.exe'
    if (Test-Path -LiteralPath $dism) {
        $rc = Invoke-WDMExe -File $dism -Arguments @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart') -TimeoutMin 30 -Label 'DISM'
        if ($rc -eq 0 -or $rc -eq 3010) { OK "Componentes limpiados" }
        elseif ($rc -eq -1) { WARN "DISM no finalizo a tiempo; reintenta luego." }
        else { WARN "DISM codigo $rc (reinicio pendiente u otra operacion en curso)." }
    } else { WARN "dism.exe no encontrado" }

    # Resumen real por espacio libre del disco
    Write-Host ""
    try {
        $libreDespues = [double](New-Object System.IO.DriveInfo($drv)).AvailableFreeSpace
        $delta = [math]::Max(0, $libreDespues - $libreAntes)
        OK ("Espacio libre en {0}: {1} -> {2} (ganado: {3})" -f $drv, (Human $libreAntes), (Human $libreDespues), (Human $delta))
    } catch { OK ("Limpieza profunda finalizada (aprox. {0} liberados)" -f (Human $total)) }
    return $true
}


function Show-DMSystemInfo {
    HR "INFORMACION DEL SISTEMA"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA Stop
        $cpu = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
        $ram = Get-CimInstance Win32_PhysicalMemory -EA 0
        $ramGB = if ($ram) { [math]::Round((($ram | Measure-Object Capacity -Sum).Sum)/1GB, 1) } else { '?' }
        ROW 'Windows' ("{0} ({1})" -f $os.Caption, $os.Version)
        ROW 'Equipo' $env:COMPUTERNAME
        ROW 'Usuario' $env:USERNAME
        if ($cpu) { ROW 'CPU' ("{0} ({1} fisicos / {2} logicos)" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors) }
        ROW 'RAM' ("{0} GB" -f $ramGB)
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA 0
        if ($disk) {
            ROW 'Disco C:' ("{0:N0} GB libres de {1:N0} GB" -f ($disk.FreeSpace/1GB), ($disk.Size/1GB))
        }
        try {
            $up = Get-WDMSessionUptime
            ROW 'Sesion' (Format-WDMUptime $up)
        } catch { }
        OK "Resumen listo. Para el mapa completo usa 'Revision completa del sistema'."
    } catch {
        ERR "No se pudo leer info del sistema: $($_.Exception.Message)"
    }
}

function Show-StartupSafeAudit {
    HR "AUDITORIA DE INICIO (SEGURO - no borra)"
    INFO "Solo lectura: no se elimina ni deshabilita ninguna entrada."
    INFO "Una ruta ausente puede ser USB, red o un portable temporal."
    Write-Host ""
    $runKeys = @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    )
    $suspect = 0
    $heavy = New-Object System.Collections.Generic.List[string]
    foreach ($rk in $runKeys) {
        if (-not (Test-Path $rk.Path)) { continue }
        $props = Get-ItemProperty $rk.Path -EA SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^PS' -and $null -ne $_.Value -and "$($_.Value)" -ne '' -and $_.Name -notlike 'DeMente_OFF_*'
        } | ForEach-Object {
            $name = $_.Name
            $val = [string]$_.Value
            $pathGuess = $null
            if ($val -match '^"([^"]+)"') { $pathGuess = $Matches[1] }
            elseif ($val -match '(?i)^([A-Za-z]:\\[^\s"]+\.exe)') { $pathGuess = $Matches[1] }
            elseif ($val -match '(?i)((?:[A-Za-z]:\\|\\\\)[^\s"]+\.exe)') { $pathGuess = $Matches[1].Trim('"') }
            if ($pathGuess) {
                try { $pathGuess = [Environment]::ExpandEnvironmentVariables($pathGuess) } catch { }
            }
            if ($pathGuess -and -not (Test-Path -LiteralPath $pathGuess -EA SilentlyContinue)) {
                WARN ("Ruta no encontrada ahora: {0} -> {1}" -f $name, $pathGuess)
                INFO "  No se borra. Para apagarla: Administrador de tareas > Inicio, o Rendimiento > Inicio."
                $suspect++
            } elseif ($val -match '(?i)Teams|Spotify|Discord|Steam|Epic|Adobe|Update|Updater') {
                [void]$heavy.Add($name)
            } else {
                ROW $name $val
            }
        }
    }
    $folder = [Environment]::GetFolderPath('Startup')
    if ($folder -and (Test-Path $folder)) {
        Get-ChildItem $folder -Force -EA SilentlyContinue | ForEach-Object {
            if ($_.Extension -match '\.lnk$') {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $sc = $sh.CreateShortcut($_.FullName)
                    if ($sc.TargetPath -and -not (Test-Path -LiteralPath $sc.TargetPath -EA SilentlyContinue)) {
                        WARN ("Acceso directo con destino ausente: {0} -> {1}" -f $_.Name, $sc.TargetPath)
                        INFO "  No se elimina automaticamente."
                        $suspect++
                    }
                } catch { }
            }
        }
    }
    Write-Host ""
    if ($suspect -gt 0) { WARN ("Entradas a revisar: {0} (ninguna fue borrada)." -f $suspect) }
    else { OK "No se vieron rutas ausentes obvias en Run/Inicio." }
    if ($heavy.Count -gt 0) {
        WARN "Programas que suelen retrasar el inicio (revision manual):"
        $heavy | Select-Object -Unique | ForEach-Object { ROW '  ' $_ }
        INFO "Usa Herramientas > Autoruns o Administrador de tareas > Inicio para deshabilitar."
    }
    OK "Auditoria de inicio completada (modo seguro: solo lectura + avisos)."
    return $true
}

function Show-StartupList {
    HR "PROGRAMAS AL INICIO (auditoria completa)"
    Write-Host "Run, RunOnce, StartupApproved, carpetas Inicio, tareas programadas al logon y WMI."
    Write-Host "No se desinstala nada: solo informacion."
    Write-Host ""
    $total = 0
    $runKeys = @(
        @{Hive='HKLM Run'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'},
        @{Hive='HKLM RunOnce'; Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'},
        @{Hive='HKCU Run'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'},
        @{Hive='HKCU RunOnce'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'},
        @{Hive='HKLM Run (32-bit Wow6432)'; Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'},
        @{Hive='HKLM RunOnce (32-bit)'; Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'}
    )
    foreach ($rk in $runKeys) {
        HR $rk.Hive
        if (-not (Test-Path $rk.Path)) { INFO "Sin clave"; continue }
        $props = Get-ItemProperty $rk.Path -EA 0
        $any = $false
        if ($props) {
            $props.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^PS' -and $null -ne $_.Value -and "$($_.Value)" -ne ''
            } | ForEach-Object {
                $any = $true; $total++
                ROW $_.Name ([string]$_.Value)
            }
        }
        if (-not $any) { INFO "Sin entradas" }
    }
    # StartupApproved (estado habilitado/deshabilitado del Administrador de tareas)
    try {
        HR "StartupApproved (estado en Administrador de tareas)"
        $saPaths = @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        )
        $anySa = $false
        foreach ($sp in $saPaths) {
            if (-not (Test-Path $sp)) { continue }
            Get-ItemProperty $sp -EA 0 | ForEach-Object {
                $_.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $anySa = $true
                    $bytes = $_.Value
                    $disabled = $false
                    if ($bytes -is [byte[]] -and $bytes.Length -ge 4) {
                        # 0x03... = disabled tipico; 0x02 = enabled (simplificado)
                        $disabled = ($bytes[0] -eq 3 -or $bytes[0] -eq 1)
                    }
                    $st = if ($disabled) { 'Deshabilitado' } else { 'Habilitado/otro' }
                    ROW $_.Name $st
                }
            }
        }
        if (-not $anySa) { INFO "Sin datos StartupApproved" }
    } catch { INFO "StartupApproved no legible" }

    foreach ($pair in @(
        @{Tit='Carpeta Inicio del usuario'; Path=[Environment]::GetFolderPath('Startup')},
        @{Tit='Carpeta Inicio (comun)'; Path="$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"}
    )) {
        HR $pair.Tit
        if (-not (Test-Path $pair.Path)) { INFO "No existe"; continue }
        $files = @(Get-ChildItem $pair.Path -Force -EA 0 | Where-Object { $_.Name -ne 'desktop.ini' })
        if ($files.Count -eq 0) { INFO "Vacia (solo system files)" }
        else {
            foreach ($f in $files) { $total++; ROW $f.Name $f.FullName }
        }
    }

    HR "Tareas programadas de terceros (logon/arranque)"
    Write-Host "Solo terceros (sin Microsoft\Windows). El color del icono en Rendimiento > Inicio indica si conviene apagar."
    try {
        $tasks = @(Get-ScheduledTask -EA 0 | Where-Object {
            $_.State -ne 'Disabled' -and
            $_.TaskPath -notmatch '(?i)\\Microsoft\\Windows\\' -and (
                $_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }
            )
        } | Select-Object -First 30)
        if ($tasks.Count -eq 0) { INFO "Sin tareas de terceros al logon (o ninguna visible)." }
        else {
            foreach ($tk in $tasks) {
                $total++
                $exe = $null
                try { foreach ($a in @($tk.Actions)) { if ($a.Execute) { $exe = [string]$a.Execute; break } } } catch { }
                $fake = [pscustomobject]@{ Name=$tk.TaskName; Command=$exe; FilePath=$exe; Kind='task' }
                $adv = $null
                try { $adv = Get-DMStartupAdvice -Item $fake } catch { }
                $tag = if ($adv) { switch ($adv.Level) { 'verde' {'[Verde]'} 'rojo' {'[Rojo]'} default {'[Amarillo]'} } } else { '[?]' }
                ROW "$tag $($tk.TaskName)" ("{0} | {1}" -f $tk.TaskPath, $tk.State)
            }
            INFO "Solo terceros. Para apagar con un clic: Rendimiento > Inicio (semaforos)."
        }
    } catch { WARN "No se pudieron leer tareas programadas: $_" }

    HR "WMI Win32_StartupCommand"
    try {
        $wmi = @(Get-CimInstance Win32_StartupCommand -EA 0)
        foreach ($w in $wmi) {
            $total++
            ROW $w.Name ("{0} [{1}]" -f $w.Command, $w.Location)
        }
        if ($wmi.Count -eq 0) { INFO "Sin comandos WMI" }
    } catch { INFO "WMI StartupCommand no disponible" }

    Write-Host ""
    OK "Auditoria de inicio: $total entradas visibles en total."
    INFO "Intel igfxpers / hkcmd son del driver de video. SecurityHealth es Defender (no quitar)."
    INFO "Para deshabilitar con GUI completa: Herramientas > Autoruns o Administrador de tareas > Inicio."
    return $true
}

# -- SALUD DE ALMACENAMIENTO (copia disponible dentro del proceso aislado) ----
function Get-WDMDiskHealth {
    $discos = @()
    try { $fisicos = @(Get-PhysicalDisk -EA Stop) } catch { $fisicos = @() }
    try { $particiones = @(Get-CimInstance Win32_DiskPartition -EA Stop) } catch { $particiones = @() }

    foreach ($pd in $fisicos) {
        $obj = [pscustomobject]@{
            Numero = $pd.DeviceId
            Modelo = ($pd.FriendlyName).Trim()
            NumeroSerie = ($pd.SerialNumber -as [string]).Trim()
            TipoMedio = 'Desconocido'
            Interfaz = [string]$pd.BusType
            CapacidadGB = [math]::Round($pd.Size / 1GB, 1)
            EstadoSalud = [string]$pd.HealthStatus
            Temperatura = $null
            TemperaturaMax = $null
            DesgastePct = $null
            HorasEncendido = $null
            CiclosEncendido = $null
            ErroresLecturaTotal = $null
            ErroresLecturaNoCorregidos = $null
            ErroresEscrituraTotal = $null
            ErroresEscrituraNoCorregidos = $null
            FuenteSMART = 'No disponible'
            Volumenes = @()
            EstadoLabel = 'No disponible'
            EstadoDetalle = 'Este disco no expone informacion SMART fiable a Windows.'
        }

        if ($pd.MediaType -match 'SSD') { $obj.TipoMedio = if ($obj.Interfaz -match 'NVMe') { 'NVMe' } else { 'SSD' } }
        elseif ($pd.MediaType -match 'HDD') { $obj.TipoMedio = 'HDD' }
        elseif ($obj.Interfaz -match 'NVMe') { $obj.TipoMedio = 'NVMe' }
        elseif ($obj.Modelo -match 'NVMe') { $obj.TipoMedio = 'NVMe' }
        elseif ($obj.Modelo -match 'SSD|M\.2|Solid State') { $obj.TipoMedio = 'SSD' }

        try {
            $rel = $pd | Get-StorageReliabilityCounter -EA Stop
            if ($rel) {
                $obj.FuenteSMART = 'StorageReliabilityCounter'
                if ($rel.Temperature -gt 0) { $obj.Temperatura = [int]$rel.Temperature }
                if ($rel.TemperatureMax -gt 0) { $obj.TemperaturaMax = [int]$rel.TemperatureMax }
                if ($null -ne $rel.Wear) { $obj.DesgastePct = [int]$rel.Wear }
                if ($rel.PowerOnHours -gt 0) { $obj.HorasEncendido = [int]$rel.PowerOnHours }
                if ($rel.StartStopCount -gt 0) { $obj.CiclosEncendido = [int]$rel.StartStopCount }
                elseif ($rel.LoadUnloadCycleCount -gt 0) { $obj.CiclosEncendido = [int]$rel.LoadUnloadCycleCount }
                $obj.ErroresLecturaTotal = $rel.ReadErrorsTotal
                $obj.ErroresLecturaNoCorregidos = $rel.ReadErrorsUncorrected
                $obj.ErroresEscrituraTotal = $rel.WriteErrorsTotal
                $obj.ErroresEscrituraNoCorregidos = $rel.WriteErrorsUncorrected
            }
        } catch { }

        $indicadores = @()
        if ($obj.ErroresLecturaNoCorregidos -gt 0) { $indicadores += 'errores de lectura no corregidos' }
        if ($obj.ErroresEscrituraNoCorregidos -gt 0) { $indicadores += 'errores de escritura no corregidos' }
        if ($obj.EstadoSalud -eq 'Unhealthy') { $indicadores += 'estado reportado como no saludable por Windows' }
        if ($null -ne $obj.DesgastePct -and $obj.DesgastePct -ge 90) { $indicadores += "desgaste elevado ($($obj.DesgastePct)%)" }

        if ($indicadores.Count -gt 0) {
            $obj.EstadoLabel = 'Riesgo'
            $obj.EstadoDetalle = 'Se detectaron indicadores compatibles con degradacion: ' + ($indicadores -join ', ') + '.'
        } elseif ($obj.EstadoSalud -eq 'Warning' -or ($null -ne $obj.DesgastePct -and $obj.DesgastePct -ge 70)) {
            $obj.EstadoLabel = 'Atencion'
            $obj.EstadoDetalle = 'Hay indicadores que conviene monitorear con el tiempo.'
        } elseif ($obj.FuenteSMART -ne 'No disponible' -or $obj.EstadoSalud -eq 'Healthy') {
            $obj.EstadoLabel = 'Bueno'
            $obj.EstadoDetalle = 'No se detectan indicadores de degradacion.'
        }

        $discos += $obj
    }

    foreach ($part in $particiones) {
        $disco = $discos | Where-Object { $_.Numero -eq $part.DiskIndex }
        if (-not $disco) { continue }
        try { $vols = @(Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk -EA Stop) } catch { $vols = @() }
        foreach ($v in $vols) {
            if (-not $v.Size -or $v.Size -eq 0) { continue }
            $pct = [math]::Round((($v.Size - $v.FreeSpace) / $v.Size) * 100)
            $disco.Volumenes += [pscustomobject]@{
                Letra = $v.DeviceID
                TotalGB = [math]::Round($v.Size / 1GB, 1)
                LibreGB = [math]::Round($v.FreeSpace / 1GB, 1)
                PorcentajeUsado = $pct
            }
        }
    }
    return $discos
}

function Save-WDMDiskHealthSnapshot {
    param([array]$Discos)
    try {
        $carpeta = WDM-Dir '\HealthHistory'
        $archivo = Join-Path $carpeta 'disk_health.json'
        $historial = @()
        if (Test-Path $archivo) {
            try { $historial = @(Get-Content $archivo -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $historial = @() }
        }
        $fecha = Get-Date -Format 'yyyy-MM-dd'
        $historial = @($historial | Where-Object { -not ($_.Fecha -eq $fecha -and ($Discos.NumeroSerie -contains $_.Serie)) })
        foreach ($d in $Discos) {
            if (-not $d.NumeroSerie) { continue }
            $historial += [pscustomobject]@{ Fecha = $fecha; Serie = $d.NumeroSerie; Desgaste = $d.DesgastePct; Temperatura = $d.Temperatura }
        }
        $limite = (Get-Date).AddDays(-400).ToString('yyyy-MM-dd')
        $historial = @($historial | Where-Object { $_.Fecha -ge $limite })
        $historial | ConvertTo-Json -Depth 4 | Set-Content $archivo -Encoding UTF8
    } catch { }
}

function Get-WDMDiskHealthTrend {
    param([string]$Serie)
    try {
        $archivo = Join-Path (WDM-Dir '\HealthHistory') 'disk_health.json'
        if (-not (Test-Path $archivo)) { return $null }
        $historial = @(Get-Content $archivo -Raw -Encoding UTF8 | ConvertFrom-Json)
        $registros = @($historial | Where-Object { $_.Serie -eq $Serie -and $null -ne $_.Desgaste } | Sort-Object Fecha)
        if ($registros.Count -lt 2) { return $null }
        $hoy = $registros[-1]
        $hace30 = $registros | Where-Object { ([datetime]$hoy.Fecha - [datetime]$_.Fecha).Days -ge 25 } | Select-Object -Last 1
        $hace90 = $registros | Where-Object { ([datetime]$hoy.Fecha - [datetime]$_.Fecha).Days -ge 85 } | Select-Object -Last 1
        return [pscustomobject]@{
            Hoy = $hoy.Desgaste
            Hace30d = if ($hace30) { $hace30.Desgaste } else { $null }
            Hace90d = if ($hace90) { $hace90.Desgaste } else { $null }
        }
    } catch { return $null }
}

function Show-WDMDiskHealthReport {
    $discos = Get-WDMDiskHealth
    if (@($discos).Count -eq 0) { ERR 'No se pudo consultar informacion de discos.'; return }
    Save-WDMDiskHealthSnapshot -Discos $discos
    foreach ($d in $discos) {
        HR ("DISCO $($d.Numero) - $($d.Modelo)")
        ROW 'Tipo' $d.TipoMedio
        ROW 'Interfaz' $d.Interfaz
        ROW 'Capacidad' ("$($d.CapacidadGB) GB")
        foreach ($v in $d.Volumenes) {
            ROW ("Volumen $($v.Letra)") ("{0} GB usados de {1} GB ({2}% usado)" -f [math]::Round($v.TotalGB - $v.LibreGB, 1), $v.TotalGB, $v.PorcentajeUsado)
        }
        Write-Host ''
        switch ($d.EstadoLabel) {
            'Bueno'    { OK   "Estado: Bueno" }
            'Atencion' { WARN "Estado: Atencion" }
            'Riesgo'   { ERR  "Estado: Riesgo" }
            default    { INFO "Estado: No disponible" }
        }
        ROW '  Detalle' $d.EstadoDetalle
        if ($null -ne $d.DesgastePct) { ROW 'Vida util restante estimada' ("$(100 - $d.DesgastePct)%") }
        if ($null -ne $d.Temperatura) { ROW 'Temperatura' ("$($d.Temperatura) C") }
        if ($null -ne $d.HorasEncendido) { ROW 'Horas de funcionamiento' $d.HorasEncendido }
        if ($null -ne $d.CiclosEncendido) { ROW 'Ciclos de encendido' $d.CiclosEncendido }
        if ($null -ne $d.ErroresLecturaNoCorregidos) { ROW 'Errores de lectura no corregidos' $d.ErroresLecturaNoCorregidos }
        if ($null -ne $d.ErroresEscrituraNoCorregidos) { ROW 'Errores de escritura no corregidos' $d.ErroresEscrituraNoCorregidos }
        if ($d.FuenteSMART -eq 'No disponible') { ROW 'SMART' 'No disponible en este dispositivo/controlador' }
        if ($d.NumeroSerie) {
            $tend = Get-WDMDiskHealthTrend -Serie $d.NumeroSerie
            if ($tend -and $null -ne $tend.Hace30d) {
                Write-Host ''
                Write-Host '    Tendencia de desgaste:'
                ROW '  Hoy' ("$($tend.Hoy)%")
                ROW '  Hace ~30 dias' ("$($tend.Hace30d)%")
                if ($null -ne $tend.Hace90d) { ROW '  Hace ~90 dias' ("$($tend.Hace90d)%") }
            }
        }
        Write-Host ''
    }
    OK 'Analisis de salud de almacenamiento completado.'
}


# -- HERRAMIENTAS DE TERCEROS (descarga / ejecucion local) --------------------
function Get-WDMToolsDir {
    $p = Join-Path $env:USERPROFILE 'Documents\DeMente\tools'
    if (-not (Test-Path $p)) { New-Item $p -ItemType Directory -Force | Out-Null }
    return $p
}

function Find-WDMTool {
    param([string[]]$Names)
    $root = Get-WDMToolsDir
    foreach ($n in $Names) {
        $p = Join-Path $root $n
        if (Test-Path $p) { return $p }
        $hit = Get-ChildItem $root -Recurse -Filter $n -File -EA 0 | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Start-WDMTool {
    param([string]$Path, [string]$Args = '')
    if (-not $Path -or -not (Test-Path $Path)) { ERR "No se encontro el ejecutable."; return $false }
    try {
        if ($Args) { Start-Process -FilePath $Path -ArgumentList $Args }
        else { Start-Process -FilePath $Path }
        OK "Lanzado: $Path"
        return $true
    } catch { ERR "No se pudo lanzar: $_"; return $false }
}

function Get-WDMToolZip {
    param([string]$Url, [string]$ZipName, [string[]]$ExeNames, [string]$Label)
    $root = Get-WDMToolsDir
    $exe = Find-WDMTool $ExeNames
    if ($exe) { OK ("{0} ya esta en: {1}" -f $Label, $exe); return $exe }
    $zip = Join-Path $env:TEMP ("demente_tool_" + [guid]::NewGuid().ToString('N') + ".zip")
    INFO ("Descargando {0}..." -f $Label)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -EA Stop
        $dest = Join-Path $root $ZipName
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -EA 0 }
        Expand-Archive $zip $dest -Force -EA Stop
        Remove-Item $zip -Force -EA 0
        $exe = Find-WDMTool $ExeNames
        if ($exe) { OK ("{0} listo: {1}" -f $Label, $exe); return $exe }
        ERR ("Se descargo {0} pero no se encontro el .exe esperado ({1})." -f $Label, ($ExeNames -join ', '))
        return $null
    } catch {
        ERR ("No se pudo obtener {0}: {1}" -f $Label, $_.Exception.Message)
        INFO "Descarga manual y coloca el exe en: $root"
        return $null
    }
}

# -- DIAGNOSTICO: la version completa vive solo en el proceso principal.
# Las herramientas aisladas no deben llamar a Get-DiagnosticoCompleto del Prelude.
# Si una herramienta necesita diagnostico, usa los campos ya calculados o llama
# a las funciones de hardware/registro individuales definidas arriba.



# ===== SALUD v1.0.0.1 (disponible en tareas aisladas) =====
function Get-SaludDeMente {
    $ErrorActionPreference = 'SilentlyContinue'
    $t0 = Get-Date
    $Hallazgos = [System.Collections.Generic.List[object]]::new()
    $Puentes = [System.Collections.Generic.List[string]]::new()
    $CompCount = 0; $ElemCount = 0
    function Add-H([string]$Texto, [int]$Peso, [string]$Puente = '') {
        $Hallazgos.Add([pscustomobject]@{ Texto=$Texto; Peso=$Peso; Puente=$Puente })
        if ($Puente -and $Puentes -notcontains $Puente) { [void]$Puentes.Add($Puente) }
    }
    function Get-ExeS([string]$cmd) {
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
        $c = $cmd.Trim()
        if ($c.StartsWith('"')) { $e=$c.IndexOf('"',1); if($e -gt 1){ return $c.Substring(1,$e-1) } }
        $exp = [Environment]::ExpandEnvironmentVariables($c)
        if ($exp -match '(?i)(^|")([^"]+\.(exe|dll|sys|com|bat|cmd))("|\s|$)') { return $Matches[2] }
        if ($exp -notmatch ' ') { return $exp.Trim('"') }
        return ($exp -split ' ',2)[0].Trim('"')
    }
    function Test-SafeS([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return $false }
        $e = [Environment]::ExpandEnvironmentVariables($p.Trim('"'))
        return (Test-Path -LiteralPath $e -EA SilentlyContinue)
    }
    function Get-RV([string]$Path,[string]$Name) {
        try { return (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name } catch { return $null }
    }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ramMods = @(Get-CimInstance Win32_PhysicalMemory)
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA 0
    $totalRamGB = [math]::Round(($ramMods | Measure-Object Capacity -Sum).Sum / 1GB, 1)
    $winVer = "$($cv.ProductName) $($cv.DisplayVersion)".Trim()
    $build = $cv.CurrentBuildNumber
    $arch = $os.OSArchitecture
    $esLaptop = [bool](Get-CimInstance Win32_Battery -EA 0)
    $cores = [int]$cpu.NumberOfCores
    $CompCount += 8; $ElemCount += 8
    $pending = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'Windows Update' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'Componentes' }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations') { $pending += 'Archivos' }
    $CompCount += 3
    $svcDown = @()
    foreach ($n in @('Winmgmt','EventLog','RpcSs','Dnscache','BFE','mpssvc','wuauserv','BITS','CryptSvc','Schedule')) {
        $s = Get-Service -Name $n -EA 0; $CompCount++
        if ($s -and $s.StartType -eq 'Automatic' -and $s.Status -ne 'Running') { $svcDown += $s.DisplayName }
    }
    $bWindows = "$winVer (build $build, $arch) responde con normalidad."
    if ($pending.Count -gt 0) {
        $bWindows = "Windows esta operativo, pero hay operaciones pendientes de reinicio ($($pending -join ', '))."
        Add-H "Hay operaciones pendientes de reinicio ($($pending -join ', '))." 2 'Ver en Reparacion'
    }
    if ($svcDown.Count -gt 0) {
        $bWindows = 'Windows esta operativo, pero hay servicios importantes detenidos.'
        Add-H "Servicios importantes detenidos: $($svcDown -join ', ')." 2 'Ver en Reparacion'
    }
    $usedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)
    $freeMB = [math]::Round($os.FreePhysicalMemory / 1KB)
    $CompCount += 2
    $pagesPerSec = $null
    try { $pagesPerSec = [math]::Round((Get-Counter '\Memory\Pages/sec' -EA Stop).CounterSamples.CookedValue, 0) } catch {}
    $CompCount++
    $paginaActiva = ($null -ne $pagesPerSec -and $pagesPerSec -gt 80)
    $tweakPerf = @()
    $wps = Get-RV 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
    $idealPrio = if ($cores -le 2) { 18 } elseif ($cores -le 4) { 26 } else { 38 }
    if ($null -ne $wps -and [int]$wps -ne $idealPrio -and [int]$wps -ne 2) { $tweakPerf += "Prioridad CPU modificada (actual: $wps)" }
    $vfx = Get-RV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
    if ($null -ne $vfx -and [int]$vfx -eq 2) { $tweakPerf += 'Efectos visuales en modo rendimiento' }
    $CompCount += 2
    $runTotal = 0; $runRotos = 0
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        $p = Get-ItemProperty $k -EA 0
        if ($p) {
            $props = @($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Value })
            $runTotal += $props.Count
            foreach ($pr in $props) {
                $exe = Get-ExeS $pr.Value; $ElemCount++
                if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)rundll32|SecurityHealth') { $runRotos++ }
            }
        }
    }
    Get-CimInstance Win32_StartupCommand | ForEach-Object {
        $exe = Get-ExeS $_.Command; $ElemCount++
        if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)SecurityHealth|RUNDLL32|explorer') { $runRotos++ }
    }
    $CompCount += 4
    $bRendimiento = 'No se observo un cuello de botella unico en este escaneo.'
    if ($usedPct -ge 92 -and $paginaActiva) {
        $bRendimiento = 'La memoria tiene muy poco margen y se observa actividad de paginacion.'
        Add-H "Memoria bajo presion ($usedPct% en uso) con paginacion activa." 2 'Ver en Rendimiento'
    } elseif ($usedPct -ge 92) {
        $bRendimiento = 'La memoria esta muy cargada en este momento.'
        Add-H "La memoria esta muy cargada ahora mismo ($usedPct%)." 2 'Ver en Rendimiento'
    } elseif ($totalRamGB -lt 8 -and $paginaActiva) {
        $bRendimiento = "Con $totalRamGB GB de RAM se observa paginacion."
        Add-H "Hay paginacion activa en un equipo con $totalRamGB GB de RAM." 1 'Ver en Rendimiento'
    } elseif ($totalRamGB -lt 8) {
        $bRendimiento = "El equipo tiene $totalRamGB GB de RAM. En este escaneo no se midio presion extrema sostenida."
    }
    if ($tweakPerf.Count -gt 0) { $bRendimiento += ' Se detectaron ajustes de rendimiento diferentes a los valores predeterminados de Windows.' }
    $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $librePct = [math]::Round($vol.FreeSpace / $vol.Size * 100)
    $libreGB = [math]::Round($vol.FreeSpace / 1GB, 1)
    $pds = @(Get-PhysicalDisk -EA 0)
    $tieneSSD = $false; $discoAlerta = $null
    foreach ($pd in $pds) {
        $ElemCount++
        if ($pd.MediaType -match 'SSD' -or $pd.Model -match 'SSD|NVMe|Solid') { $tieneSSD = $true }
        if ($pd.HealthStatus -eq 'Unhealthy') { $discoAlerta = 'no saludable' }
        elseif ($pd.HealthStatus -eq 'Warning' -and -not $discoAlerta) { $discoAlerta = 'con advertencia' }
    }
    $CompCount += 4
    if ($discoAlerta) {
        $bAlmacenamiento = "Windows reporta un disco $discoAlerta."
        Add-H "Windows reporta un disco $discoAlerta." 3 'Ver en Reparacion'
    } elseif ($librePct -lt 10) {
        $bAlmacenamiento = "Queda muy poco espacio libre ($librePct%)."
        Add-H "Espacio critico en el disco del sistema ($librePct% libre)." 2 'Ver en Limpieza'
    } elseif ($librePct -lt 18) {
        $bAlmacenamiento = "Espacio libre bajo ($librePct%). Windows no reporta una alerta fisica evidente."
        Add-H "Espacio libre bajo en el disco del sistema ($librePct%)." 1 'Ver en Limpieza'
    } elseif (-not $tieneSSD -and $paginaActiva) {
        $bAlmacenamiento = 'Disco HDD. Windows no reporta una alerta fisica evidente. Hay paginacion activa. No se midio latencia elevada.'
        Add-H 'Hay paginacion activa sobre almacenamiento HDD.' 1 'Ver en Rendimiento'
    } elseif (-not $tieneSSD) {
        $bAlmacenamiento = 'Disco HDD. Windows no reporta una alerta fisica evidente y hay espacio aceptable. No se midio latencia elevada.'
    } else {
        $bAlmacenamiento = "Almacenamiento SSD/NVMe. Windows no reporta una alerta fisica evidente. Espacio libre: $librePct%."
    }
    $secTexto = 'No se pudo comprobar la proteccion en tiempo real.'; $secOk = $false
    try {
        $def = Get-MpComputerStatus -EA Stop; $CompCount += 2
        if ($def.RealTimeProtectionEnabled) { $secTexto = 'Proteccion en tiempo real activa.'; $secOk = $true }
        else { $secTexto = 'La proteccion en tiempo real no esta activa.'; Add-H 'Defender sin proteccion en tiempo real.' 2 'Ver en Seguridad' }
    } catch { $CompCount++ }
    $privPend = 0
    foreach ($i in @(
        @{P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection';N='AllowTelemetry';G=0},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';N='Enabled';G=0},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';N='TailoredExperiencesWithDiagnosticDataEnabled';G=0},
        @{P='HKCU:\Software\Microsoft\Siuf\Rules';N='NumberOfSIUFInPeriod';G=0}
    )) {
        $CompCount++
        try {
            if (Test-Path $i.P) { $v = Get-RV $i.P $i.N; if ($null -eq $v -or $v -ne $i.G) { $privPend++ } } else { $privPend++ }
        } catch { $privPend++ }
    }
    $yaraTxt = 'YARA: no comprobado.'
    $yaraHome = Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    if (Test-Path $yaraHome) {
        $bin = Test-Path (Join-Path $yaraHome 'bin'); $rules = Test-Path (Join-Path $yaraHome 'rules'); $CompCount += 2
        if ($bin -and $rules) { $yaraTxt = 'YARA: motor y reglas presentes (sin escaneo profundo en Salud).' }
        elseif ($bin -or $rules) { $yaraTxt = 'YARA: instalacion parcial.' }
    }
    $bSegPriv = $secTexto
    if ($privPend -gt 0) {
        $bSegPriv = $(if ($secOk) { 'Proteccion activa. ' } else { "$secTexto " }) + "Hay $privPend ajuste(s) de privacidad distintos del DEFAULT de Windows."
        Add-H "Hay $privPend configuracion(es) de privacidad distintas del DEFAULT de Windows." 1 'Ver en Privacidad'
    }
    $bSegPriv += " $yaraTxt"
    $svcBroken = 0
    Get-CimInstance Win32_Service | ForEach-Object {
        $exe = Get-ExeS $_.PathName; $ElemCount++
        if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)\\System32\\|\\SysWOW64\\|svchost|dllhost') { $svcBroken++ }
    }
    $CompCount += 2
    $residuos = $runRotos + $svcBroken
    $apagados = 0
    try {
        $kp = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=(Get-Date).AddDays(-14) } -MaxEvents 30 -EA 0
        $apagados = @($kp | Where-Object { $_.Id -in 41,109 }).Count; $CompCount++
    } catch {}
    $netTexto = 'Red no comprobada por completo.'
    try {
        $ads = @(Get-NetAdapter -EA 0 | Where-Object Status -eq 'Up'); $CompCount++
        if ($ads.Count -eq 0) { $netTexto = 'Sin adaptador de red activo.' }
        else {
            $ip = @(Get-NetIPConfiguration -EA 0 | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
            $hasGw = $ip.Count -gt 0; $dnsOk = $false
            try { if (Resolve-DnsName 'www.microsoft.com' -Type A -DnsOnly -EA Stop -QuickTimeout) { $dnsOk = $true } } catch {}
            $CompCount += 2
            if ($hasGw -and $dnsOk) { $netTexto = 'Red operativa (adaptador, puerta de enlace y DNS).' }
            elseif ($hasGw) { $netTexto = 'Red local presente; DNS a internet no confirmado.'; Add-H 'Red local OK; no se confirmo internet (DNS).' 1 'Ver en Reparacion' }
            else { $netTexto = 'Adaptador activo sin puerta de enlace clara.'; Add-H 'Configuracion de red incompleta.' 1 'Ver en Reparacion' }
        }
    } catch {}
    $configBase = 'Inicio y servicios sin residuos evidentes.'
    if ($residuos -ge 3) { $configBase = 'Hay varias referencias residuales (inicio/servicios).'; Add-H "Se encontraron $residuos referencias residuales." 1 'Ver en Limpieza' }
    elseif ($residuos -gt 0) { $configBase = 'Hay algunas referencias residuales de bajo impacto.'; Add-H "Hay referencias residuales ($residuos)." 1 'Ver en Limpieza' }
    elseif ($runTotal -ge 15) { $configBase = "Hay muchos programas al inicio ($runTotal)."; Add-H "Hay muchos programas al inicio ($runTotal)." 1 'Ver en Rendimiento' }
    $estabilidadTxt = ''
    if ($apagados -gt 0) {
        Add-H "Windows registro $apagados apagado(s)/reinicio(s) inesperado(s) en 14 dias. La causa no esta determinada en este escaneo." 1 'Ver en Reparacion'
        $estabilidadTxt = 'Hay senales de estabilidad a tener en cuenta.'
    }
    $bConfig = $configBase
    if ($estabilidadTxt) { $bConfig += " $estabilidadTxt" }
    $bConfig += " $netTexto"
    $dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $maxPeso = 0
    if ($Hallazgos.Count -gt 0) { $maxPeso = ($Hallazgos | Measure-Object Peso -Maximum).Maximum }
    $titulo = 'No encontramos nada que requiera atencion inmediata.'
    if ($maxPeso -ge 3) { $titulo = 'Encontramos un problema que merece atencion.' }
    elseif ($maxPeso -eq 2) { $titulo = 'Encontramos algo que conviene revisar.' }
    elseif ($maxPeso -eq 1) { $titulo = 'Encontramos algunas condiciones que conviene tener en cuenta.' }
    $top = @($Hallazgos | Sort-Object Peso -Descending | Select-Object -First 4)
    return [pscustomobject]@{
        Version='1.0.0.1'; Titulo=$titulo; MaxPeso=$maxPeso
        Equipo="$($cs.Manufacturer) $($cs.Model)".Trim(); WinVer=$winVer; RAMGB=$totalRamGB
        TieneSSD=$tieneSSD; EsLaptop=$esLaptop; CPUName=$cpu.Name.Trim()
        BloqueWindows=$bWindows; BloqueRendimiento=$bRendimiento; BloqueAlmacenamiento=$bAlmacenamiento
        BloqueSegPriv=$bSegPriv; BloqueConfig=$bConfig; TweaksPerf=$tweakPerf
        Hallazgos=$top; HallazgosTotal=$Hallazgos.Count; Puentes=@($Puentes)
        CompCount=$CompCount; ElemCount=$ElemCount; DuracionSeg=$dur
    }
}
function Show-SaludDeMenteConsole {
    HR 'SALUD · Como esta realmente tu PC'
    $s = Get-SaludDeMente
    Write-Host ''
    Write-Host "  $($s.Titulo)" -ForegroundColor Yellow
    Write-Host "  $($s.Equipo) · $($s.WinVer) · $($s.RAMGB) GB · $(if($s.TieneSSD){'SSD'}else{'HDD'})" -ForegroundColor DarkGray
    Write-Host "  $($s.CPUName)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  WINDOWS' -ForegroundColor Cyan; Write-Host "     $($s.BloqueWindows)" -ForegroundColor Gray
    Write-Host '  RENDIMIENTO' -ForegroundColor Cyan; Write-Host "     $($s.BloqueRendimiento)" -ForegroundColor Gray
    if ($s.TweaksPerf -and $s.TweaksPerf.Count -gt 0) { Write-Host "     Tweaks: $($s.TweaksPerf -join ' · ')" -ForegroundColor DarkGray }
    Write-Host '  ALMACENAMIENTO' -ForegroundColor Cyan; Write-Host "     $($s.BloqueAlmacenamiento)" -ForegroundColor Gray
    Write-Host '  SEGURIDAD Y PRIVACIDAD' -ForegroundColor Cyan; Write-Host "     $($s.BloqueSegPriv)" -ForegroundColor Gray
    Write-Host '  INICIO Y ESTABILIDAD' -ForegroundColor Cyan; Write-Host "     $($s.BloqueConfig)" -ForegroundColor Gray
    Write-Host ''
    Write-Host '  LO QUE DEBERIAS SABER' -ForegroundColor White
    if (-not $s.Hallazgos -or $s.Hallazgos.Count -eq 0) { INFO 'No hay puntos destacados.' }
    else {
        $i=1
        foreach ($h in $s.Hallazgos) {
            Write-Host "  $i  $($h.Texto)" -ForegroundColor White
            if ($h.Puente) { Write-Host "     [$($h.Puente)]" -ForegroundColor DarkCyan }
            $i++
        }
    }
    Write-Host ''
    Write-Host '  QUE PODES HACER DESDE DEMENTE' -ForegroundColor White
    if (-not $s.Puentes -or $s.Puentes.Count -eq 0) { INFO 'No hay secciones sugeridas por ahora.' }
    else { $s.Puentes | ForEach-Object { Write-Host "     ->  $_" -ForegroundColor White } }
    Write-Host ''
    OK ("Salud: 5 bloques · {0} comprobaciones · {1} elementos · {2}s" -f $s.CompCount, $s.ElemCount, $s.DuracionSeg)
    INFO 'DeMente no llama problema a todo lo que encuentra. Primero intenta entender que significa.'
    return $true
}

# =============================================================================
# DESINSTALADOR (programas de escritorio + apps de Store del usuario)
# -----------------------------------------------------------------------------
# Vive dentro de "Limpieza" como una sub-vista (chip "Desinstalar programas"),
# no como seccion nueva. Las entradas se generan al abrir la app leyendo lo
# que de verdad esta instalado en ESTA PC (no es un catalogo fijo como el
# resto de las herramientas).
# =============================================================================

<#
.SYNOPSIS
    Enumera programas de escritorio instalados (HKLM 64/32-bit + HKCU).
.OUTPUTS
    PSCustomObject[] con Name, Publisher, Version, SizeKB, UninstallCmd, Quiet, RegPath, IsStore=$false
#>
function Get-DMInstalledPrograms {
    [CmdletBinding()]
    param()
    $raices = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $vistos = [System.Collections.Generic.HashSet[string]]::new()
    $out = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($raiz in $raices) {
        try {
            $claves = Get-ItemProperty -Path $raiz -ErrorAction SilentlyContinue
        } catch { continue }
        foreach ($k in $claves) {
            try {
                $nombre = [string]$k.DisplayName
                if ([string]::IsNullOrWhiteSpace($nombre)) { continue }
                if ($k.SystemComponent -eq 1) { continue }
                if ($k.PSObject.Properties.Name -contains 'ParentKeyName' -and $k.ParentKeyName) { continue }
                if ($nombre -match '^(Security Update|Update for|Hotfix|Service Pack|Actualizaci[oó]n)') { continue }
                if (-not $vistos.Add($nombre.ToLower())) { continue }  # evitar duplicados HKLM/WOW6432

                $uninstall = [string]$k.UninstallString
                if ([string]::IsNullOrWhiteSpace($uninstall)) { continue }

                $sizeKB = 0
                try { if ($k.EstimatedSize) { $sizeKB = [int]$k.EstimatedSize } } catch { }

                $out.Add([pscustomobject]@{
                    Name         = $nombre
                    Publisher    = [string]$k.Publisher
                    Version      = [string]$k.DisplayVersion
                    SizeKB       = $sizeKB
                    UninstallCmd = $uninstall
                    QuietCmd     = [string]$k.QuietUninstallString
                    RegPath      = $k.PSPath
                    IsStore      = $false
                    PackageId    = $null
                })
            } catch { continue }
        }
    }
    return @($out | Sort-Object Name)
}

<#
.SYNOPSIS
    Enumera apps de Microsoft Store instaladas para el usuario actual,
    excluyendo componentes propios de Windows (solo apps de terceros reales).
.DESCRIPTION
    A proposito NO incluye nada con PackageFamilyName que empiece con
    'Microsoft.' / 'MicrosoftWindows.' / 'Windows.': son componentes del
    sistema (Edge WebView, Store, Calculadora del sistema, etc.). Mostrar
    solo terceros evita que alguien borre por error algo que Windows
    necesita para funcionar.
#>
function Get-DMInstalledStoreApps {
    [CmdletBinding()]
    param()
    $out = [System.Collections.Generic.List[pscustomobject]]::new()
    try {
        $paquetes = @()
        $prevEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
                $paquetes = @(Get-AppxPackage -ErrorAction Stop | Where-Object {
                    -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable -and
                    $_.PackageFamilyName -notmatch '^(Microsoft\.|MicrosoftWindows\.|Windows\.)'
                })
            }
        } catch {
            $paquetes = @()
        } finally {
            $ErrorActionPreference = $prevEap
        }
        if (-not $paquetes -or $paquetes.Count -eq 0) {
            Write-Verbose "Apps de Store no enumerables (modulo Appx). Solo programas de escritorio."
            return @()
        }
    } catch {
        INFO "Apps de Store omitidas."
        return @()
    }
    foreach ($p in $paquetes) {
        $nombre = $p.Name
        try {
            $manifest = Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction SilentlyContinue
            $dn = $manifest.Package.Properties.DisplayName
            if ($dn -and $dn -notmatch '^ms-resource:') { $nombre = $dn }
        } catch { }
        $out.Add([pscustomobject]@{
            Name         = $nombre
            Publisher    = $p.Publisher
            Version      = [string]$p.Version
            SizeKB       = 0
            UninstallCmd = $null
            QuietCmd     = $null
            RegPath      = $null
            IsStore      = $true
            PackageId    = $p.PackageFullName
        })
    }
    return @($out | Sort-Object Name)
}

<#
.SYNOPSIS
    Busca y borra residuos seguros (cache/config en AppData) de un programa ya desinstalado.
.DESCRIPTION
    Solo toca AppData\Local y AppData\Roaming (cache/config tipicos, seguros
    de borrar una vez que el programa ya no esta). NO toca Archivos de
    programa ni ProgramData: ahi a veces queda licencia o datos de usuario
    que el desinstalador dejo a proposito, y no es DeMente quien debe
    decidir borrarlos sin preguntar.
.PARAMETER NombrePrograma
    Nombre visible del programa (se usa para buscar carpetas parecidas).
#>
function Clear-DMAppResidue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NombrePrograma)

    # Palabra clave: primera palabra "significativa" del nombre (4+ letras)
    # para evitar falsos positivos con palabras cortas tipo "Go", "3D", etc.
    $palabras = $NombrePrograma -split '[\s\-_]+' | Where-Object { $_.Length -ge 4 }
    if (-not $palabras) { $palabras = @($NombrePrograma) }
    $clave = $palabras[0]

    $bytesFreed = [double]0
    $carpetasBorradas = 0
    $accesosBorrados = 0
    $entradasInicioBorradas = 0

    # 1) AppData: SOLO informar (Confianza). Borrar por primera palabra del nombre
    #    es peligroso (Adobe*, Microsoft*, etc.). El usuario decide fuera de aca.
    $raices = @($env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($raiz in $raices) {
        try {
            $coincidencias = Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$clave*" }
            foreach ($c in $coincidencias) {
                INFO "  Posible residuo (NO se borra solo): $($c.FullName)"
            }
        } catch { }
    }

    # 2) Accesos directos huerfanos en Escritorio y Menu Inicio (usuario y
    #    todos los usuarios): apuntan a un programa que ya no existe, asi
    #    que borrarlos es seguro y evita el tipico icono roto.
    $carpetasAccesos = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($carpeta in $carpetasAccesos) {
        try {
            $lnks = @(Get-ChildItem -LiteralPath $carpeta -Recurse -File -Filter '*.lnk' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$clave*" })
            foreach ($l in $lnks) {
                try {
                    Remove-Item -LiteralPath $l.FullName -Force -ErrorAction Stop
                    $accesosBorrados++
                    INFO "  Acceso directo huerfano borrado: $($l.FullName)"
                } catch { }
            }
        } catch { }
    }

    # 3) Entradas de inicio (Run) que quedaron apuntando a un .exe que ya no
    #    existe: no son peligrosas, pero ensucian y a veces tiran un error
    #    de "no se encuentra el archivo" en cada arranque.
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        try {
            $props = Get-ItemProperty -Path $rk -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
                if ($prop.Name -notlike "*$clave*" -and [string]$prop.Value -notlike "*$clave*") { continue }
                if (Test-WDMExePath ([string]$prop.Value)) { continue }  # el exe todavia existe: no tocar
                try {
                    Remove-ItemProperty -Path $rk -Name $prop.Name -ErrorAction Stop
                    $entradasInicioBorradas++
                    INFO "  Entrada de inicio rota borrada: $($prop.Name)"
                } catch { }
            }
        } catch { }
    }

    # 4) Program Files / ProgramData: solo se REPORTA, no se borra. A veces
    #    ahi queda una licencia o datos que el usuario podria necesitar, y
    #    no le corresponde a DeMente decidir borrarlos sin preguntar.
    $reportados = [System.Collections.Generic.List[string]]::new()
    foreach ($raizPF in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
        try {
            Get-ChildItem -LiteralPath $raizPF -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$clave*" } |
                ForEach-Object { $reportados.Add($_.FullName) }
        } catch { }
    }

    $partes = [System.Collections.Generic.List[string]]::new()
    if ($carpetasBorradas -gt 0) { $partes.Add("$carpetasBorradas carpeta(s) de cache/config") }
    if ($accesosBorrados -gt 0) { $partes.Add("$accesosBorrados acceso(s) directo(s) huerfano(s)") }
    if ($entradasInicioBorradas -gt 0) { $partes.Add("$entradasInicioBorradas entrada(s) de inicio rota(s)") }

    if ($partes.Count -gt 0) {
        OK "Residuos de '$NombrePrograma': $($partes -join ', '). $(Human $bytesFreed) liberados."
    } else {
        INFO "Sin residuos de cache/config/accesos para '$NombrePrograma' (o el desinstalador ya los borro)."
    }
    if ($reportados.Count -gt 0) {
        INFO "Ademas queda esto en Archivos de programa (no se borra solo, puede tener datos tuyos):"
        foreach ($r in $reportados) { ROW '  Carpeta' $r }
    }
}

# Helper chico local: igual que Get-DMFolderSize pero sin depender de otro
# nombre para que Clear-DMAppResidue no rompa si esa funcion cambia.
function Get-DMFolderSizeSafe([string]$Path) {
    try {
        $s = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        return [double]($s.Sum)
    } catch { return [double]0 }
}

<#
.SYNOPSIS
    Desinstala un programa (escritorio o Store) y limpia sus residuos.
.PARAMETER Programa
    Uno de los objetos devueltos por Get-DMInstalledPrograms/Get-DMInstalledStoreApps.
#>
function Remove-DMProgram {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param([Parameter(Mandatory)][pscustomobject]$Programa)

    HR "DESINSTALAR: $($Programa.Name)"
    if (-not $PSCmdlet.ShouldProcess($Programa.Name, 'Desinstalar')) { return }

    if ($Programa.IsStore) {
        try {
            Remove-AppxPackage -Package $Programa.PackageId -ErrorAction Stop
            OK "'$($Programa.Name)' desinstalada (app de Store)."
        } catch {
            ERR "No se pudo desinstalar '$($Programa.Name)': $($_.Exception.Message)"
            return
        }
    } else {
        $cmd = if ($Programa.QuietCmd) { $Programa.QuietCmd } else { $Programa.UninstallCmd }
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            ERR "'$($Programa.Name)' no tiene comando de desinstalacion valido."
            return
        }
        INFO "Ejecutando desinstalador de Windows para '$($Programa.Name)'..."
        INFO "Si aparece una ventana del propio instalador, es normal: seguila ahi."
        try {
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd" -Wait -PassThru -ErrorAction Stop
            if ($p.ExitCode -eq 0) { OK "'$($Programa.Name)' desinstalado (codigo 0)." }
            else { WARN "'$($Programa.Name)': el desinstalador termino con codigo $($p.ExitCode). Puede que igual haya funcionado; revisa en Windows si sigue apareciendo." }
        } catch {
            ERR "No se pudo lanzar el desinstalador de '$($Programa.Name)': $($_.Exception.Message)"
            return
        }
    }

    Clear-DMAppResidue -NombrePrograma $Programa.Name
}

# =============================================================================
# APPS DE INICIO (elegibles por el usuario)
# -----------------------------------------------------------------------------
# Vive dentro de "Rendimiento" con su propio chip, igual que el desinstalador
# vive dentro de "Limpieza". Deshabilitar, nunca borrar: el dato original
# queda guardado (como valor 'DeMente_OFF_<nombre>' en el registro, o el
# .lnk movido a una carpeta propia) para poder reactivarlo con un clic.
# =============================================================================

<#
.SYNOPSIS
    Enumera programas que arrancan con Windows (Run keys + carpetas de inicio),
    incluyendo los que ya deshabilito DeMente antes (para poder reactivarlos).
.OUTPUTS
    PSCustomObject[] con Name, Command, Kind ('registry'|'shortcut'), RegPath,
    RegLabel, ValueName, IsDisabled, FilePath
#>

function Test-DMStartupApprovedDisabled {
    param([string]$ValueName)
    if ([string]::IsNullOrWhiteSpace($ValueName)) { return $false }
    # Quitar prefijo DeMente_OFF_ para buscar el nombre "real" en StartupApproved
    $nm = $ValueName -replace '^DeMente_OFF_', ''
    $paths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    )
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $prop = Get-ItemProperty -LiteralPath $p -Name $nm -ErrorAction Stop
            $raw = $prop.$nm
            if ($null -eq $raw) { continue }
            # Task Manager: primer byte 0x03 = deshabilitado; 0x02 = habilitado
            if ($raw -is [byte[]] -and $raw.Length -ge 1) {
                if ($raw[0] -eq 3) { return $true }
            } elseif ($raw -is [byte] -and [int]$raw -eq 3) {
                return $true
            }
        } catch { }
    }
    return $false
}

function Set-DMStartupApprovedState {
    param([string]$ValueName, [ValidateSet('disable','enable')][string]$Accion)
    if ([string]::IsNullOrWhiteSpace($ValueName)) { return }
    $nm = $ValueName -replace '^DeMente_OFF_', ''
    $paths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    )
    # 12 bytes tipicos: 03 00 00 00 + timestamp (disabled) / 02 00 00 00 + ts (enabled)
    $disabled = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
    $enabled  = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0)
    $blob = if ($Accion -eq 'disable') { $disabled } else { $enabled }
    foreach ($p in $paths) {
        try {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            # Solo tocar si ya existe la entrada (no inventar claves ajenas)
            $exists = $false
            try { $null = Get-ItemProperty -LiteralPath $p -Name $nm -ErrorAction Stop; $exists = $true } catch { }
            if (-not $exists) { continue }
            New-ItemProperty -LiteralPath $p -Name $nm -Value $blob -PropertyType Binary -Force -ErrorAction Stop | Out-Null
        } catch { }
    }
}

function Get-DMStartupItems {
    [CmdletBinding()]
    param()
    $out = [System.Collections.Generic.List[pscustomobject]]::new()

    $raices = @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Label = 'Inicio (tu usuario)' },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Label = 'RunOnce (tu usuario)' },
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Label = 'Inicio (todos los usuarios)' },
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Label = 'RunOnce (todos los usuarios)' },
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Label = 'Inicio (32-bit)' },
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Label = 'RunOnce (32-bit)' }
    )
    foreach ($r in $raices) {
        if (-not (Test-Path -LiteralPath $r.Path)) { continue }
        try {
            $props = Get-ItemProperty -Path $r.Path -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
                $isOff = $prop.Name -like 'DeMente_OFF_*'
                $displayName = if ($isOff) { $prop.Name -replace '^DeMente_OFF_', '' } else { $prop.Name }
                $cmd = [string]$prop.Value
                $exePath = $null
                if ($cmd -match '^"([^"]+)"') { $exePath = $Matches[1] }
                elseif ($cmd -match '^(.*?\.exe)') { $exePath = $Matches[1].Trim().Trim('"') }
                elseif ($cmd -match '^[A-Za-z]:\\') { $exePath = ($cmd -split '\s+')[0].Trim('"') }
                $approvedOff = $false
                try { $approvedOff = Test-DMStartupApprovedDisabled -ValueName $displayName } catch { }
                $out.Add([pscustomobject]@{
                    Name = $displayName; Command = $cmd; Kind = 'registry'
                    RegPath = $r.Path; RegLabel = $r.Label; ValueName = $prop.Name
                    IsDisabled = ($isOff -or $approvedOff); FilePath = $exePath; TaskPath = $null
                })
            }
        } catch { }
    }

    $carpetaUsuario = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    $carpetaComun   = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
    $carpetaOff     = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\startup-disabled'
    foreach ($par in @(@{P=$carpetaUsuario;L='Carpeta de inicio (tu usuario)'}, @{P=$carpetaComun;L='Carpeta de inicio (todos los usuarios)'})) {
        if (-not (Test-Path -LiteralPath $par.P)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $par.P -File -Filter '*.lnk' -EA SilentlyContinue)) {
            $target = $null
            try { $target = (New-Object -ComObject WScript.Shell).CreateShortcut($f.FullName).TargetPath } catch { }
            $out.Add([pscustomobject]@{
                Name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                Command = $f.FullName; Kind = 'shortcut'
                RegPath = $null; RegLabel = $par.L; ValueName = $null
                IsDisabled = $false; FilePath = $(if ($target) { $target } else { $f.FullName }); TaskPath = $null
            })
        }
    }
    if (Test-Path -LiteralPath $carpetaOff) {
        foreach ($f in @(Get-ChildItem -LiteralPath $carpetaOff -File -Filter '*.lnk' -EA SilentlyContinue)) {
            $out.Add([pscustomobject]@{
                Name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                Command = $f.FullName; Kind = 'shortcut'
                RegPath = $null; RegLabel = 'Deshabilitado por DeMente'; ValueName = $null
                IsDisabled = $true; FilePath = $f.FullName; TaskPath = $null
            })
        }
    }

    # Tareas de terceros al logon (excluye Microsoft\Windows)
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '(?i)\\Microsoft\\Windows\\'
        })) {
            $isLogon = $false
            try {
                foreach ($tr in @($t.Triggers)) {
                    if ($tr.CimClass.CimClassName -match 'Logon|Boot') { $isLogon = $true; break }
                }
            } catch { }
            if (-not $isLogon) {
                try {
                    $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -EA Stop
                    if ($xml -match 'LogonTrigger|BootTrigger') { $isLogon = $true }
                } catch { }
            }
            if (-not $isLogon) { continue }
            $exe = $null
            try { foreach ($a in @($t.Actions)) { if ($a.Execute) { $exe = [string]$a.Execute.Trim('"'); break } } } catch { }
            if ($exe) { try { $exe = [Environment]::ExpandEnvironmentVariables($exe) } catch { } }
            $fullId = ($t.TaskPath.TrimEnd('\') + '\' + $t.TaskName)
            $taskOff = ([string]$t.State -eq 'Disabled')
            $out.Add([pscustomobject]@{
                Name = $t.TaskName; Command = $(if ($exe) { $exe } else { $fullId }); Kind = 'task'
                RegPath = $null; RegLabel = 'Tarea (logon/arranque)'; ValueName = $null
                IsDisabled = $taskOff; FilePath = $exe; TaskPath = $fullId
            })
        }
    } catch { }

    # WMI: entradas de otros SIDs / ubicaciones; mapear Location a ruta de registro real
    try {
        $seenCmd = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($x in $out) {
            if ($x.Command) { [void]$seenCmd.Add([string]$x.Command) }
            if ($x.Name) { [void]$seenCmd.Add([string]$x.Name) }
        }
        foreach ($sc in @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)) {
            $cmd = [string]$sc.Command
            $nm  = [string]$sc.Name
            if ([string]::IsNullOrWhiteSpace($nm)) { continue }
            if ($seenCmd.Contains($nm) -and $seenCmd.Contains($cmd)) { continue }
            $loc = [string]$sc.Location
            # Convertir Location WMI -> ruta PowerShell usable
            $regPath = $null
            if ($loc -match '(?i)^HKU\\(.+)$') {
                $regPath = 'Registry::HKEY_USERS\' + $Matches[1]
            } elseif ($loc -match '(?i)^HKLM\\(.+)$') {
                $regPath = 'HKLM:\' + $Matches[1]
            } elseif ($loc -match '(?i)^HKCU\\(.+)$') {
                $regPath = 'HKCU:\' + $Matches[1]
            } elseif ($loc -match '(?i)^Registry::') {
                $regPath = $loc
            } elseif ($loc -match '(?i)Startup' -or $loc -match '(?i)Common Startup') {
                # Carpeta: ya cubierto por shortcuts
                continue
            }
            if (-not $regPath) { continue }
            # Si ya tenemos el mismo Name en esa clave, skip
            $dup = $false
            foreach ($x in $out) {
                if ($x.Name -eq $nm -and $x.RegPath -eq $regPath) { $dup = $true; break }
            }
            if ($dup) { continue }
            $exePath = $null
            if ($cmd -match '^"([^"]+)"') { $exePath = $Matches[1] }
            elseif ($cmd -match '^(.*?\.exe)') { $exePath = $Matches[1].Trim().Trim('"') }
            $out.Add([pscustomobject]@{
                Name = $nm; Command = $cmd; Kind = 'registry'
                RegPath = $regPath
                RegLabel = ('Registro: {0}' -f $loc)
                ValueName = $nm; IsDisabled = $false; FilePath = $exePath; TaskPath = $null
            })
            [void]$seenCmd.Add($cmd); [void]$seenCmd.Add($nm)
        }
    } catch { }

    # Servicios Automatic (terceros)  -  desactivables con semaforo
    try {
        $crit = @(
            'EventLog','RpcSs','RpcEptMapper','DcomLaunch','LSM','SamSs','Winmgmt',
            'Power','ProfSvc','UserManager','Schedule','SystemEventsBroker','BrokerInfrastructure',
            'gpsvc','LanmanServer','LanmanWorkstation','nsi','Dhcp','Dnscache','NlaSvc','netprofm',
            'BFE','mpssvc','WinDefend','SecurityHealthService','WdNisSvc','Sense',
            'AudioEndpointBuilder','Audiosrv','FontCache','Themes','DPS','DiagTrack'
        )
        foreach ($svc in @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.StartType -eq 'Automatic' -or $_.StartType -eq 'AutomaticDelayedStart'
        })) {
            $name = $svc.Name
            if ($crit -contains $name) { continue }
            if ($name -match '^(Wmi|Win|BITS|CryptSvc|TrustedInstaller|sppsvc|wuauserv|UsoSvc)') { continue }
            $disp = $svc.DisplayName
            $path = $null
            try {
                $cfg = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name.Replace("'","''")) -EA 0
                if ($cfg) { $path = [string]$cfg.PathName }
            } catch { }
            # Filtrar casi-seguro Microsoft por path
            $isMs = $false
            if ($path -and ($path -match '(?i)\\Windows\\System32\\|\\Windows\\SysWOW64\\|Microsoft')) {
                # muchos servicios MS viven ahi; solo listar si el nombre no parece MS
                if ($disp -match '(?i)^Microsoft|^Windows |^Hyper-V|^Update Orchestrator') { $isMs = $true }
            }
            if ($isMs) { continue }
            # Evitar duplicados por nombre
            $exists = $false
            foreach ($x in $out) { if ($x.Kind -eq 'service' -and $x.Name -eq $name) { $exists = $true; break } }
            if ($exists) { continue }
            $out.Add([pscustomobject]@{
                Name = $(if ($disp) { $disp } else { $name })
                Command = $(if ($path) { $path } else { $name })
                Kind = 'service'
                RegPath = $null
                RegLabel = 'Servicio (Automatic)'
                ValueName = $name   # Service Name real
                IsDisabled = $false
                FilePath = $path
                TaskPath = $null
            })
        }
    } catch { }

    return @($out | Sort-Object Name)
}

function Get-DMStartupDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Item)

    $cmd  = [string]$Item.Command
    $path = [string]$Item.FilePath
    if ([string]::IsNullOrWhiteSpace($path) -and $cmd) {
        if ($cmd -match '^"([^"]+)"') { $path = $Matches[1] }
        elseif ($cmd -match '^(.*?\.exe\b)') { $path = $Matches[1].Trim().Trim('"') }
        else { $path = ($cmd -split '\s+')[0].Trim('"') }
    }
    try {
        if ($path -and $path.StartsWith('%')) {
            $path = [Environment]::ExpandEnvironmentVariables($path)
        }
    } catch { }

    $exists = $false
    $company = $null
    $product = $null
    $fileDesc = $null
    $fileVer = $null
    $sizeMB = $null
    if ($path -and ($path -match '^[A-Za-z]:\\' -or $path.StartsWith('\\'))) {
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue) {
                $exists = $true
                try {
                    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                    if ($vi.CompanyName) { $company = $vi.CompanyName.Trim() }
                    if ($vi.ProductName) { $product = $vi.ProductName.Trim() }
                    if ($vi.FileDescription) { $fileDesc = $vi.FileDescription.Trim() }
                    if ($vi.FileVersion) { $fileVer = $vi.FileVersion.Trim() }
                } catch { }
                try {
                    $len = (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).Length
                    if ($null -ne $len) { $sizeMB = [math]::Round($len / 1MB, 2) }
                } catch { }
            } elseif (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
                $exists = $true
            }
        } catch { }
    }

    $tipo = switch ([string]$Item.Kind) {
        'registry' { 'Clave Run/RunOnce del registro' }
        'shortcut' { 'Acceso directo en carpeta de Inicio' }
        'task'     { 'Tarea programada (logon/arranque)' }
        'service'  { 'Servicio de Windows (inicio Automatic)' }
        default    { [string]$Item.Kind }
    }

    $estado = if ($Item.IsDisabled) { 'Deshabilitado por DeMente (reactivable)' } else { 'Activo: arranca con Windows' }

    return [pscustomobject]@{
        Path        = $path
        Exists      = $exists
        Company     = $company
        Product     = $product
        FileDesc    = $fileDesc
        FileVersion = $fileVer
        SizeMB      = $sizeMB
        TipoHumano  = $tipo
        Estado      = $estado
        Origen      = [string]$Item.RegLabel
        ServiceName = $(if ($Item.Kind -eq 'service') { [string]$Item.ValueName } else { $null })
        TaskPath    = $(if ($Item.Kind -eq 'task') { [string]$Item.TaskPath } else { $null })
        RegPath     = [string]$Item.RegPath
        ValueName   = [string]$Item.ValueName
        Command     = $cmd
    }
}

function New-DMAdvice {
    param(
        [string]$Level,
        [string]$WhatIs,
        [string]$WinWants,
        [string]$DmSays,
        [string]$IfOff
    )
    return [pscustomobject]@{
        Level    = $Level
        Label    = $(switch ($Level) { 'verde' { 'Se puede apagar' } 'rojo' { 'No tocar' } default { 'Revisar' } })
        WhatIs   = $WhatIs
        WinWants = $WinWants
        DmSays   = $DmSays
        Phrase   = $IfOff
        Color    = $(switch ($Level) { 'verde' { 'AccentGreen' } 'rojo' { 'AccentRed' } default { 'AccentYellow' } })
    }
}

function Get-DMStartupAdvice {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Item)

    $name = [string]$Item.Name
    $cmd  = [string]$Item.Command
    $path = [string]$Item.FilePath
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $cmd }
    $svc  = [string]$Item.ValueName
    $blob = ("$name $cmd $path $svc $([string]$Item.TaskPath)").ToLowerInvariant()

    # Empresa / producto del .exe (para explicar en humano)
    $empresa = $null
    $producto = $null
    $exe = $null
    try {
        $exe = $path
        if ($exe -match '^"([^"]+)"') { $exe = $Matches[1] }
        elseif ($exe -match '^(.*?\.exe)') { $exe = $Matches[1].Trim().Trim('"') }
        if ($exe -and $exe.StartsWith('%')) { $exe = [Environment]::ExpandEnvironmentVariables($exe) }
        if ($exe -and ($exe -match '^[A-Za-z]:\\') -and (Test-Path -LiteralPath $exe -PathType Leaf -EA SilentlyContinue)) {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
            if ($vi.CompanyName) { $empresa = $vi.CompanyName.Trim() }
            if ($vi.ProductName) { $producto = $vi.ProductName.Trim() }
            if (-not $producto -and $vi.FileDescription) { $producto = $vi.FileDescription.Trim() }
        }
    } catch { }

    $winOk = 'lo deja activo, pero no es critico del sistema.'
    $winNeed = 'lo necesita activo.'
    $winNeedOrOk = 'lo deja activo por defecto.'

    if ($Item.Kind -eq 'service') {
        if ($blob -match 'brave') {
            return New-DMAdvice -Level 'verde' -WhatIs 'Actualizador de Brave: busca versiones nuevas del navegador en segundo plano.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Brave no se actualiza solo; podes actualizarlo abriendo el navegador.'
        }
        if ($blob -match 'edgeupdate|microsoft edge') {
            return New-DMAdvice -Level 'verde' -WhatIs 'Actualizador de Microsoft Edge: mantiene el navegador al dia.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Edge no se actualiza solo hasta que lo abras.'
        }
        if ($blob -match 'google|gupdate') {
            return New-DMAdvice -Level 'verde' -WhatIs 'Actualizador de Google Chrome.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Chrome no se actualiza en segundo plano.'
        }
        if ($blob -match 'spooler' -and $blob -notmatch 'epson|hp|canon|brother') {
            return New-DMAdvice -Level 'rojo' -WhatIs 'Cola de impresion de Windows: sin esto casi no se imprime.' -WinWants $winNeed -DmSays 'DeMente: no lo toques.' -IfOff 'Dejan de funcionar la mayoria de las impresoras.'
        }
        if ($blob -match 'epson|hp |canon|brother|lexmark|scanner|scan') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'Servicio de impresora o escaner (Epson, HP, Canon, etc.).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no imprimis ni escaneas a diario.' -IfOff 'La impresora o el escaner pueden no responder hasta reactivar el servicio.'
        }
        if ($blob -match 'nvidia|nvsvc|nvcontainer|nvtelemetry') {
            return New-DMAdvice -Level 'rojo' -WhatIs 'Driver de video NVIDIA: controla la placa grafica.' -WinWants $winNeed -DmSays 'DeMente: no lo toques.' -IfOff 'Puede fallar la pantalla, el panel NVIDIA o los juegos.'
        }
        if ($blob -match 'intel|igfx') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'Utilidad de graficos Intel (iconos de pantalla).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no usas esos iconos.' -IfOff 'Puede faltar el icono Intel; el video sigue.'
        }
        if ($blob -match 'termservice|escritorio remoto|remote desktop|umrdpservice') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'Escritorio remoto: permite que otra PC se conecte a esta por red.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si nunca usas Escritorio remoto.' -IfOff 'Nadie podra conectarse a esta PC por Escritorio remoto.'
        }
        if ($blob -match 'onedrive') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'OneDrive: sincroniza carpetas con la nube de Microsoft.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no usas OneDrive.' -IfOff 'La nube puede no sincronizar sola.'
        }
        if ($blob -match 'adobe') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'Servicio de Adobe (PDF o Creative Cloud).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no usas Adobe a diario.' -IfOff 'Adobe puede tardar mas en abrir.'
        }
        if ($blob -match 'vpn|wireguard|openvpn|nord|expressvpn') {
            return New-DMAdvice -Level 'amarillo' -WhatIs 'Servicio de VPN (conexion privada a internet).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si conectas la VPN solo cuando la necesitas.' -IfOff 'La VPN no se conecta sola al iniciar.'
        }
        # --- Servicios PROPIOS de Windows (empresa Microsoft): consejo real, no generico ---
        $esWindows = ($empresa -match 'Microsoft') -or ($path -match '(?i)\\windows\\system32\\')
        if ($esWindows) {
            $ms = @(
                @{ Rx='officeclicktorun|click-to-run|clicktorun'; Nivel='verde'; Que='Actualizador de Microsoft Office (Click-to-Run): mantiene Word, Excel y demás al día.'; Dm='Podés apagarlo si no usás Office seguido: Office se actualiza igual cuando lo abrís.'; Off='Office no se actualiza en segundo plano; lo hace al abrirlo.' },
                @{ Rx='xbl|xbox|gamesave|gipsvc'; Nivel='verde'; Que='Servicios de Xbox: sirven para iniciar sesión en Xbox, guardar partidas en la nube y usar mandos de Xbox.'; Dm='Podés apagarlo si no jugás juegos de la tienda de Microsoft ni usás la app Xbox.'; Off='Los juegos de Xbox/Microsoft Store pueden no guardar partidas en la nube.' },
                @{ Rx='^wsearch$|windows search'; Nivel='amarillo'; Que='Búsqueda de Windows: mantiene un índice para que el buscador del menú Inicio y del Explorador encuentre archivos rápido.'; Dm='Podés apagarlo en una PC lenta con disco mecánico, pero las búsquedas de archivos van a ser más lentas.'; Off='Buscar archivos tarda más y el menú Inicio puede encontrar menos cosas.' },
                @{ Rx='^sysmain$|superfetch'; Nivel='amarillo'; Que='SysMain (Superfetch): aprende qué programas usás y los precarga para que abran más rápido.'; Dm='En discos SSD casi no aporta: podés apagarlo. En discos mecánicos conviene dejarlo.'; Off='Algunos programas pueden tardar un poco más en abrir la primera vez.' },
                @{ Rx='diagtrack|connected user experiences'; Nivel='verde'; Que='Telemetría de Windows: envía datos de uso y errores a Microsoft.'; Dm='Podés apagarlo tranquilo si querés más privacidad; Windows funciona igual.'; Off='Microsoft no recibe datos de diagnóstico de tu PC.' },
                @{ Rx='mapsbroker|downloaded maps'; Nivel='verde'; Que='Mapas descargados: actualiza mapas sin conexión de la app Mapas.'; Dm='Podés apagarlo si no usás la app Mapas de Windows.'; Off='La app Mapas no actualiza los mapas descargados.' },
                @{ Rx='^lfsvc$|geolocation'; Nivel='verde'; Que='Ubicación: permite que las apps sepan dónde estás.'; Dm='Podés apagarlo si no querés que ninguna app use tu ubicación.'; Off='Apps como Clima o Mapas no podrán detectar dónde estás.' },
                @{ Rx='^fax$'; Nivel='verde'; Que='Fax: permite enviar y recibir faxes desde la PC.'; Dm='Podés apagarlo: casi nadie lo usa hoy.'; Off='No vas a poder mandar faxes desde esta PC (probablemente nunca lo hiciste).' },
                @{ Rx='remoteregistry'; Nivel='verde'; Que='Registro remoto: permite que otra persona modifique el registro de esta PC por red.'; Dm='Conviene tenerlo apagado por seguridad. Podés apagarlo.'; Off='Nadie podrá administrar el registro de esta PC desde otra computadora.' },
                @{ Rx='retaildemo'; Nivel='verde'; Que='Modo demostración para tiendas: solo se usa en computadoras de exhibición.'; Dm='Podés apagarlo sin problema.'; Off='No pasa nada: es para PCs de vidriera.' },
                @{ Rx='wersvc|error reporting'; Nivel='verde'; Que='Informe de errores: cuando un programa falla, ofrece enviar el reporte a Microsoft.'; Dm='Podés apagarlo si no querés enviar reportes de fallos.'; Off='Los programas que fallen no van a generar reportes para Microsoft.' },
                @{ Rx='wmpnetworksvc|media player network'; Nivel='verde'; Que='Compartir biblioteca de Windows Media Player con otros equipos de la red.'; Dm='Podés apagarlo si no compartís música o videos por red.'; Off='Otros dispositivos de tu red no verán tu biblioteca multimedia.' },
                @{ Rx='^wuauserv$|windows update'; Nivel='rojo'; Que='Windows Update: descarga e instala actualizaciones y parches de seguridad.'; Dm='No lo apagues: sin actualizaciones tu PC queda expuesta a fallas y virus nuevos.'; Off='Tu PC deja de recibir parches de seguridad.' },
                @{ Rx='windefend|^sense$|securityhealth|wscsvc|security center'; Nivel='rojo'; Que='Protección de Windows (antivirus y centro de seguridad).'; Dm='No lo apagues: es lo que te protege de virus.'; Off='Tu PC queda sin antivirus ni avisos de seguridad.' },
                @{ Rx='mpssvc|firewall'; Nivel='rojo'; Que='Firewall de Windows: filtra las conexiones que entran y salen de tu PC.'; Dm='No lo apagues: es tu primera barrera contra intrusos en la red.'; Off='Tu PC queda expuesta a conexiones no deseadas.' },
                @{ Rx='eventlog|^bits$|cryptsvc|^rpcss$|dcomlaunch|^power$|profsvc|^dhcp$|dnscache|^themes$|audiosrv|audioendpointbuilder'; Nivel='rojo'; Que="«$name» es una pieza básica de Windows (arranque, red, audio o seguridad)."; Dm='No lo toques: Windows lo necesita para funcionar bien.'; Off='Pueden fallar la red, el sonido, las actualizaciones o el propio arranque.' }
            )
            foreach ($m in $ms) {
                if ($blob -match $m.Rx) {
                    return New-DMAdvice -Level $m.Nivel -WhatIs $m.Que -WinWants $(if ($m.Nivel -eq 'rojo') { $winNeed } else { $winOk }) -DmSays $m.Dm -IfOff $m.Off
                }
            }
            # Servicio de Windows que no conocemos: NO sugerir apagarlo a ciegas.
            return New-DMAdvice -Level 'rojo' -WhatIs "«$name» es un servicio propio de Windows." -WinWants $winNeed -DmSays 'Dejalo como está: Windows lo administra solo. Apagar servicios sin saber para qué sirven es una de las causas más comunes de fallas raras.' -IfOff 'Alguna función de Windows puede dejar de andar, y a veces cuesta descubrir cuál.'
        }
        if ($blob -match 'update|telemetry|diagtrack') {
            return New-DMAdvice -Level 'verde' -WhatIs 'Actualizacion o telemetria de un programa instalado (no es Windows critico).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Ese programa no se actualiza ni reporta datos al arrancar.'
        }
        # Fallback servicio CON identidad concreta
        $quien = if ($empresa) { $empresa } elseif ($producto) { $producto } else { $null }
        if ($quien) {
            $what = "Servicio de «$quien»: $name."
            $dm = "DeMente: si no usas programas de $quien, lo podes apagar."
        } else {
            $what = "Servicio de fondo llamado «$name» (Windows lo enciende solo al iniciar)."
            $dm = "DeMente: mira el nombre «$name». Si no te suena, mejor dejarlo."
        }
        return New-DMAdvice -Level 'amarillo' -WhatIs $what -WinWants $winOk -DmSays $dm -IfOff "«$name» deja de estar listo al iniciar; si algo falla, reactivalo."
    }

    # Ruta rota
    $resolved = $null; $exeExists = $true
    if ($path -match '\.exe' -or $path -match '^[A-Za-z]:\\') {
        $candidate = $path
        if ($candidate -match '^"([^"]+)"') { $candidate = $Matches[1] }
        elseif ($candidate -match '^(.*?\.exe)') { $candidate = $Matches[1].Trim().Trim('"') }
        try { if ($candidate.StartsWith('%')) { $candidate = [Environment]::ExpandEnvironmentVariables($candidate) } } catch { }
        $resolved = $candidate
        if ($candidate -match '^[A-Za-z]:\\') {
            try { $exeExists = [bool](Test-Path -LiteralPath $candidate -EA SilentlyContinue) } catch { $exeExists = $true }
        }
    }
    if (-not $exeExists -and $resolved) {
        return New-DMAdvice -Level 'verde' -WhatIs 'Resto de un programa que ya desinstalaste (el archivo no existe).' -WinWants 'todavia intenta abrirlo al iniciar.' -DmSays 'DeMente: lo podes apagar; no pasa nada.' -IfOff 'Solo se limpia basura de inicio.'
    }

    if ($blob -match 'securityhealth|msascuil|windows defender|antimalware') {
        return New-DMAdvice -Level 'rojo' -WhatIs 'Icono de Seguridad de Windows (Defender) en la bandeja.' -WinWants $winNeed -DmSays 'DeMente: no lo toques.' -IfOff 'Perdes los avisos de amenazas en la bandeja.'
    }
    if ($path -match '(?i)[\\/]Windows[\\/](System32|SysWOW64)[\\/]' -and $path -notmatch '(?i)OneDrive|Teams') {
        return New-DMAdvice -Level 'rojo' -WhatIs ("Parte de Windows: $name.") -WinWants $winNeed -DmSays 'DeMente: no lo toques.' -IfOff 'Puede romperse alguna funcion del sistema.'
    }
    if ($blob -match 'igfxtray|igfxpers|hkcmd|hotkey') {
        return New-DMAdvice -Level 'amarillo' -WhatIs 'Iconos y atajos del driver de video Intel.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no usas esos iconos.' -IfOff 'Puede faltar el icono Intel; la pantalla sigue.'
    }
    if ($blob -match 'onedrive') {
        return New-DMAdvice -Level 'amarillo' -WhatIs 'OneDrive: sincroniza carpetas con la nube de Microsoft.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no usas OneDrive.' -IfOff 'OneDrive no abre solo; tus archivos locales no se borran.'
    }
    if ($blob -match 'brave') {
        return New-DMAdvice -Level 'verde' -WhatIs 'Actualizador o acceso de Brave.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Brave no se actualiza ni abre solo.'
    }
    if ($blob -match 'edgeupdate|microsoftedgeupdate') {
        return New-DMAdvice -Level 'verde' -WhatIs 'Actualizador de Microsoft Edge.' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'Edge no se actualiza hasta que lo abras.'
    }
    if ($blob -match 'discord') {
        return New-DMAdvice -Level 'verde' -WhatIs 'Discord (chat y voz).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada.' -IfOff 'Discord no abre solo.'
    }
    if ($blob -match 'spotify') {
        return New-DMAdvice -Level 'verde' -WhatIs 'Spotify (musica).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada.' -IfOff 'Spotify no inicia solo.'
    }
    if ($blob -match 'steam') {
        return New-DMAdvice -Level 'verde' -WhatIs 'Steam (juegos).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada.' -IfOff 'Steam no abre al iniciar.'
    }
    if ($blob -match 'teams') {
        return New-DMAdvice -Level 'amarillo' -WhatIs 'Microsoft Teams (trabajo o estudio).' -WinWants $winOk -DmSays 'DeMente: lo podes apagar si no lo usas todos los dias.' -IfOff 'Teams no arranca solo.'
    }
    if ($blob -match 'updater|update|helper|tray|launcher') {
        $titulo = if ($producto) { $producto } elseif ($empresa) { $empresa } else { $name }
        return New-DMAdvice -Level 'verde' -WhatIs ("Ayudante o actualizador de «$titulo».") -WinWants $winOk -DmSays 'DeMente: lo podes apagar; no pasa nada grave.' -IfOff 'No se abre ni se actualiza solo; lo usas cuando quieras.'
    }

    # Fallback final CON nombre y empresa
    if ($empresa -match 'Microsoft') {
        $etiqueta = if ($producto) { $producto } else { $name }
        $what = "«$etiqueta»: programa de Windows o de Office que se abre al iniciar."
        $dm = "Si es parte de Windows (íconos de seguridad, audio, red), dejalo. Si es una app que no usás apenas prendés la PC (Office, Edge, Teams), podés apagarlo."
    } elseif ($empresa -or $producto) {
        $etiqueta = if ($producto) { $producto } else { $empresa }
        $what = "Programa de «$etiqueta» que se abre al iniciar: $name."
        $dm = "Si no usás «$etiqueta» apenas prendés la PC, podés apagarlo: lo abrís vos cuando lo necesites."
    } else {
        $what = "Programa que se abre al iniciar Windows: «$name»."
        $dm = "DeMente: si «$name» no te suena o no lo necesitas al inicio, lo podes apagar."
    }
    return New-DMAdvice -Level 'amarillo' -WhatIs $what -WinWants $winOk -DmSays $dm -IfOff "«$name» deja de abrirse solo con Windows."
}

function Set-DMStartupItemState {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][ValidateSet('disable','enable')][string]$Accion
    )
    $verbo = if ($Accion -eq 'disable') { 'DESHABILITAR' } else { 'REACTIVAR' }
    HR "$verbo INICIO: $($Item.Name)"
    if (-not $PSCmdlet.ShouldProcess($Item.Name, $Accion)) { return }
    try {
        if ($Item.Kind -eq 'registry') {
            if ([string]::IsNullOrWhiteSpace([string]$Item.RegPath)) {
                ERR "Sin ruta de registro para '$($Item.Name)'."
                return
            }
            $valName = if ($Item.ValueName) { [string]$Item.ValueName } else { [string]$Item.Name }
            if (-not (Test-Path -LiteralPath $Item.RegPath)) {
                ERR "No se abre $($Item.RegPath) (permisos o ya no existe)."
                return
            }
            $offName = "DeMente_OFF_$valName"
            if ($Accion -eq 'disable') {
                $cur = $null
                try {
                    $p = Get-ItemProperty -LiteralPath $Item.RegPath -Name $valName -ErrorAction Stop
                    $cur = $p.$valName
                } catch {
                    try {
                        $valName = [string]$Item.Name
                        $offName = "DeMente_OFF_$valName"
                        $p = Get-ItemProperty -LiteralPath $Item.RegPath -Name $valName -ErrorAction Stop
                        $cur = $p.$valName
                    } catch {
                        $cur = $Item.Command
                    }
                }
                if (-not $cur) { $cur = $Item.Command }
                New-ItemProperty -LiteralPath $Item.RegPath -Name $offName -Value $cur -PropertyType String -Force -ErrorAction Stop | Out-Null
                Remove-ItemProperty -LiteralPath $Item.RegPath -Name $valName -ErrorAction Stop
                try { Set-DMStartupApprovedState -ValueName $valName -Accion 'disable' } catch { }
                OK "'$($Item.Name)' deshabilitado. Reactivable desde DeMente (titulo: Ya apagado)."
            } else {
                $saved = $null
                try {
                    $p = Get-ItemProperty -LiteralPath $Item.RegPath -Name $offName -ErrorAction Stop
                    $saved = $p.$offName
                } catch {
                    $offName = "DeMente_OFF_$($Item.Name)"
                    try {
                        $p = Get-ItemProperty -LiteralPath $Item.RegPath -Name $offName -ErrorAction Stop
                        $saved = $p.$offName
                    } catch { $saved = $Item.Command }
                }
                if (-not $saved) { $saved = $Item.Command }
                New-ItemProperty -LiteralPath $Item.RegPath -Name $valName -Value $saved -PropertyType String -Force -ErrorAction Stop | Out-Null
                Remove-ItemProperty -LiteralPath $Item.RegPath -Name $offName -ErrorAction SilentlyContinue
                try { Set-DMStartupApprovedState -ValueName $valName -Accion 'enable' } catch { }
                OK "'$($Item.Name)' reactivado."
            }
        }
        elseif ($Item.Kind -eq 'service') {
            $svcName = if ($Item.ValueName) { [string]$Item.ValueName } else { [string]$Item.Name }
            $snapDir = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\startup-state'
            if (-not (Test-Path -LiteralPath $snapDir)) { New-Item -Path $snapDir -ItemType Directory -Force | Out-Null }
            $snapFile = Join-Path $snapDir ("svc_{0}.txt" -f ($svcName -replace '[^\w\-]','_'))
            if ($Accion -eq 'disable') {
                $prev = 'Automatic'
                try {
                    $s = Get-Service -Name $svcName -EA Stop
                    $prev = [string]$s.StartType
                    if ($prev -eq 'AutomaticDelayedStart') { $prev = 'AutomaticDelayedStart' }
                } catch { }
                try { Set-Content -LiteralPath $snapFile -Value $prev -Encoding UTF8 -Force } catch { }
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
                OK "Servicio '$svcName' deshabilitado (antes: $prev). Snapshot guardado."
            } else {
                $restore = 'Manual'
                if (Test-Path -LiteralPath $snapFile) {
                    try { $restore = (Get-Content -LiteralPath $snapFile -Raw -EA Stop).Trim() } catch { }
                }
                if ($restore -notmatch '^(Automatic|AutomaticDelayedStart|Manual|Disabled)$') { $restore = 'Manual' }
                if ($restore -eq 'AutomaticDelayedStart') {
                    try { Set-Service -Name $svcName -StartupType Automatic -EA Stop; sc.exe config $svcName start= delayed-auto | Out-Null }
                    catch { Set-Service -Name $svcName -StartupType Automatic -EA 0 }
                } else {
                    Set-Service -Name $svcName -StartupType $restore -ErrorAction Stop
                }
                if ($restore -match 'Automatic') { Start-Service -Name $svcName -ErrorAction SilentlyContinue }
                OK "Servicio '$svcName' restaurado a: $restore"
            }
        }
        elseif ($Item.Kind -eq 'shortcut') {
            $carpetaOff = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\startup-disabled'
            $lnk = [string]$Item.Command
            if ($Accion -eq 'disable') {
                if (-not (Test-Path -LiteralPath $carpetaOff)) { New-Item -Path $carpetaOff -ItemType Directory -Force | Out-Null }
                if (-not ($lnk -match '\.lnk$') -or -not (Test-Path -LiteralPath $lnk)) { throw 'No se encontro el .lnk' }
                Move-Item -LiteralPath $lnk -Destination (Join-Path $carpetaOff (Split-Path $lnk -Leaf)) -Force -ErrorAction Stop
                OK "Acceso directo movido a backups."
            } else {
                $dest = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
                if (-not (Test-Path -LiteralPath $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }
                Move-Item -LiteralPath $lnk -Destination (Join-Path $dest (Split-Path $lnk -Leaf)) -Force -ErrorAction Stop
                OK "Acceso directo restaurado."
            }
        }
        elseif ($Item.Kind -eq 'task') {
            $taskId = [string]$Item.TaskPath
            if ([string]::IsNullOrWhiteSpace($taskId)) { $taskId = [string]$Item.Command }
            $taskName = [string]$Item.Name
            $taskFolder = '\'
            if ($taskId -match '^(.*)\\([^\\]+)$') {
                $taskFolder = $Matches[1]
                $taskName = $Matches[2]
            }
            if (-not $taskFolder.EndsWith('\')) { $taskFolder = $taskFolder + '\' }
            if ($Accion -eq 'disable') {
                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -ErrorAction Stop | Out-Null
                OK "Tarea '$taskName' deshabilitada."
            } else {
                Enable-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -ErrorAction Stop | Out-Null
                OK "Tarea '$taskName' reactivada."
            }
        }
        else {
            WARN "Tipo no soportado: $($Item.Kind)"
        }
    } catch {
        ERR "No se pudo $verbo '$($Item.Name)': $($_.Exception.Message)"
    }
}

function Get-DMFindTorBrowser {
    [CmdletBinding()]
    param()

    function Test-DMExistingPath([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return $false }
        try {
            if ($p -match '^[A-Za-z]:') {
                $drive = $p.Substring(0, 2)
                if (-not (Test-Path -LiteralPath ($drive + '\') -ErrorAction SilentlyContinue)) { return $false }
            }
            return [bool](Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)
        } catch { return $false }
    }
    function Test-DMIsTorRoot([string]$c) {
        if ([string]::IsNullOrWhiteSpace($c)) { return $false }
        try {
            if (Test-DMExistingPath (Join-Path $c 'Browser\firefox.exe')) { return $true }
            if (Test-DMExistingPath (Join-Path $c 'Browser\TorBrowser\Data')) { return $true }
            if (Test-DMExistingPath (Join-Path $c 'Browser\TorBrowser')) { return $true }
            if (Test-DMExistingPath (Join-Path $c 'firefox.exe')) { return $true }
            # A veces el usuario apunta al subfolder Browser
            if (Test-DMExistingPath (Join-Path $c 'TorBrowser\Data')) { return $true }
            if ((Split-Path $c -Leaf) -eq 'Browser' -and (Test-DMExistingPath (Join-Path $c 'firefox.exe'))) { return $true }
        } catch { }
        return $false
    }
    function Save-DMTorPath([string]$root) {
        if (-not $root) { return }
        try {
            $cfgDir = Join-Path $env:USERPROFILE 'Documents\DeMente'
            if (-not (Test-Path -LiteralPath $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null }
            Set-Content -LiteralPath (Join-Path $cfgDir 'tor-path.txt') -Value $root -Encoding UTF8 -Force
        } catch { }
    }
    function Normalize-DMTorRoot([string]$c) {
        if (-not $c) { return $null }
        # Si apuntaron a ...\Browser, subir un nivel
        try {
            if ((Split-Path $c -Leaf) -eq 'Browser' -and (Test-DMExistingPath (Join-Path $c 'firefox.exe'))) {
                $up = Split-Path $c -Parent
                if ($up) { return $up }
            }
        } catch { }
        return $c
    }

    $candidatos = [System.Collections.Generic.List[string]]::new()

    # 1) Ruta guardada (prioridad)
    try {
        $cfg = Join-Path $env:USERPROFILE 'Documents\DeMente\tor-path.txt'
        if (Test-DMExistingPath $cfg) {
            $line = (Get-Content -LiteralPath $cfg -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($line) {
                $line = ([string]$line).Trim().Trim('"')
                if ($line) { [void]$candidatos.Add($line) }
            }
        }
    } catch { }

    # 2) Rutas tipicas
    foreach ($c in @(
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Desktop\Tor Browser' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Downloads\Tor Browser' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Documents\Tor Browser' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Tor Browser' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Tor Browser' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Tor Browser' }),
        'C:\Tor Browser'
    )) {
        if ($c) { [void]$candidatos.Add($c) }
    }
    if ($env:ProgramFiles) { [void]$candidatos.Add((Join-Path $env:ProgramFiles 'Tor Browser')) }
    $pfx86 = ${env:ProgramFiles(x86)}
    if ($pfx86) { [void]$candidatos.Add((Join-Path $pfx86 'Tor Browser')) }
    foreach ($letter in @('D','E','F')) {
        if (Test-DMExistingPath "${letter}:\") {
            [void]$candidatos.Add((Join-Path "${letter}:" 'Tor Browser'))
        }
    }

    # 3) Proceso firefox con path Tor
    try {
        foreach ($proc in @(Get-Process -Name firefox -ErrorAction SilentlyContinue)) {
            try {
                $pp = [string]$proc.Path
                if ($pp -and ($pp -match '(?i)Tor Browser|TorBrowser') -and (Test-DMExistingPath $pp)) {
                    $parent = Split-Path $pp -Parent
                    $base = Split-Path $parent -Parent
                    if ($base) { [void]$candidatos.Add($base) }
                    if ($parent) { [void]$candidatos.Add($parent) }
                }
            } catch { }
        }
    } catch { }

    # 4) Registro Uninstall
    try {
        foreach ($rp in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )) {
            foreach ($k in @(Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue)) {
                $dn = [string]$k.DisplayName
                if ($dn -notmatch '(?i)tor browser') { continue }
                foreach ($prop in @('InstallLocation','DisplayIcon','UninstallString')) {
                    $v = [string]$k.$prop
                    if (-not $v) { continue }
                    if ($v -match '^"([^"]+)"') { $v = $Matches[1] }
                    $v = ($v -split '\s+')[0].Trim('"')
                    if ($v -match '\.exe$') { $v = Split-Path $v -Parent }
                    if ($v -match '(?i)\\Browser$') { $v = Split-Path $v -Parent }
                    if ($v) { [void]$candidatos.Add($v) }
                }
            }
        }
    } catch { }

    # 5) Busqueda liviana bajo perfil
    foreach ($sr in @($env:USERPROFILE, $env:LOCALAPPDATA)) {
        if (-not $sr -or -not (Test-DMExistingPath $sr)) { continue }
        try {
            foreach ($h in @(Get-ChildItem -LiteralPath $sr -Directory -Filter '*Tor*' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 30)) {
                if ($h.FullName) { [void]$candidatos.Add($h.FullName) }
            }
        } catch { }
    }

    # 6) Accesos directos
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($m in @(
            $(if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' }),
            $(if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs' }),
            $([Environment]::GetFolderPath('Desktop')),
            $(if ($env:PUBLIC) { Join-Path $env:PUBLIC 'Desktop' })
        )) {
            if (-not $m -or -not (Test-DMExistingPath $m)) { continue }
            foreach ($l in @(Get-ChildItem -LiteralPath $m -Recurse -Filter '*Tor*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 20)) {
                try {
                    $target = [string]$shell.CreateShortcut($l.FullName).TargetPath
                    if (-not $target -or -not (Test-DMExistingPath $target)) { continue }
                    if ($target -notmatch '(?i)firefox\.exe$') { continue }
                    $parent = Split-Path $target -Parent
                    $base = Split-Path $parent -Parent
                    if ($base) { [void]$candidatos.Add($base) }
                } catch { }
            }
        }
    } catch { }

    foreach ($c in $candidatos) {
        $c2 = Normalize-DMTorRoot $c
        if (Test-DMIsTorRoot $c2) {
            Save-DMTorPath $c2
            return $c2
        }
        if ($c2 -ne $c -and (Test-DMIsTorRoot $c)) {
            $n = Normalize-DMTorRoot $c
            Save-DMTorPath $n
            return $n
        }
    }
    return $null
}

<#
.SYNOPSIS
    Detecta los navegadores instalados en esta PC y sus carpetas de perfil.
#>

function Get-DMBrowserDefinitions {
    [CmdletBinding()]
    param()
    $defs = [System.Collections.Generic.List[pscustomobject]]::new()
    $seenRoots = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # Resolver User Data a partir del .exe (App Paths / instalacion real)
    function Get-DMUserDataFromExe([string]$exePath) {
        if ([string]::IsNullOrWhiteSpace($exePath)) { return $null }
        try {
            if ($exePath -match '^[A-Za-z]:' -and -not (Test-Path -LiteralPath ($exePath.Substring(0,2) + '') -EA SilentlyContinue)) { return $null }
            if (-not (Test-Path -LiteralPath $exePath -ErrorAction SilentlyContinue)) { return $null }
        } catch { return $null }
        try {
            $dir = Split-Path $exePath -Parent
            # Chrome/Edge/Brave: .../Application/chrome.exe -> ../../User Data no; User Data esta en LocalAppData
            # Portable: a veces User Data al lado del Application
            $cand = @(
                (Join-Path $dir 'User Data'),
                (Join-Path (Split-Path $dir -Parent) 'User Data')
            )
            foreach ($c in $cand) {
                if (Test-Path -LiteralPath $c) { return $c }
            }
        } catch { }
        return $null
    }
    function Get-DMAppPathExe([string]$exeName) {
        foreach ($ap in @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exeName",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$exeName",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exeName"
        )) {
            if (-not (Test-Path -LiteralPath $ap)) { continue }
            try {
                $p = (Get-ItemProperty -LiteralPath $ap -EA Stop).'(default)'
                if ($p) {
                    $p = [Environment]::ExpandEnvironmentVariables([string]$p).Trim('"')
                    if (Test-Path -LiteralPath $p) { return $p }
                }
            } catch { }
        }
        return $null
    }

    function Add-DMChromiumDef {
        param([string]$Name, [string[]]$Proc, [string]$Root)
        if ([string]::IsNullOrWhiteSpace($Root)) { return }
        try {
            if ($Root -match '^[A-Za-z]:' -and -not (Test-Path -LiteralPath ($Root.Substring(0,2) + '') -EA SilentlyContinue)) { return }
            if (-not (Test-Path -LiteralPath $Root -ErrorAction SilentlyContinue)) { return }
        } catch { return }
        if ($seenRoots.Contains($Root)) { return }
        [void]$seenRoots.Add($Root)
        $perfiles = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'User Data' })
        # Perfiles Chromium reales viven DENTRO de User Data
        if ($Root -match '(?i)\\User Data$') {
            $perfiles = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        }
        if ($perfiles.Count -eq 0) {
            # Si no hay Default/Profile, usar el root (a veces portable plano)
            $perfiles = @(Get-Item -LiteralPath $Root -ErrorAction SilentlyContinue)
        }
        if ($perfiles.Count -eq 0) { return }
        $defs.Add([pscustomobject]@{
            Name = $Name; Proc = @($Proc); Roots = @($perfiles.FullName); Engine = 'chromium'; TorRoot = $null
        })
    }

    function Add-DMFirefoxDef {
        param([string]$Name, [string[]]$Proc, [string]$ProfilesBase)
        if ([string]::IsNullOrWhiteSpace($ProfilesBase)) { return }
        try {
            if ($ProfilesBase -match '^[A-Za-z]:' -and -not (Test-Path -LiteralPath ($ProfilesBase.Substring(0,2) + '') -EA SilentlyContinue)) { return }
            if (-not (Test-Path -LiteralPath $ProfilesBase -ErrorAction SilentlyContinue)) { return }
        } catch { return }
        if ($seenRoots.Contains($ProfilesBase)) { return }
        $perfiles = @(Get-ChildItem -LiteralPath $ProfilesBase -Directory -ErrorAction SilentlyContinue)
        if ($perfiles.Count -eq 0) { return }
        [void]$seenRoots.Add($ProfilesBase)
        $defs.Add([pscustomobject]@{
            Name = $Name; Proc = @($Proc); Roots = @($perfiles.FullName); Engine = 'firefox'; TorRoot = $null
        })
    }

    # --- Chromium conocidos (LocalAppData / AppData) ---
    Add-DMChromiumDef 'Google Chrome' @('chrome') (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')
    Add-DMChromiumDef 'Chrome Beta'   @('chrome') (Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data')
    Add-DMChromiumDef 'Chrome Dev'    @('chrome') (Join-Path $env:LOCALAPPDATA 'Google\Chrome Dev\User Data')
    Add-DMChromiumDef 'Chrome Canary' @('chrome') (Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\User Data')
    Add-DMChromiumDef 'Chromium'      @('chrome','chromium') (Join-Path $env:LOCALAPPDATA 'Chromium\User Data')


    # App Paths: captura installs cuyos datos no estan en la ruta tipica
    try {
        $chromeExe = Get-DMAppPathExe 'chrome.exe'
        if ($chromeExe) {
            $ud = Get-DMUserDataFromExe $chromeExe
            if (-not $ud) { $ud = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
            Add-DMChromiumDef 'Google Chrome' @('chrome') $ud
        }
        $edgeExe = Get-DMAppPathExe 'msedge.exe'
        if ($edgeExe) {
            $ud = Get-DMUserDataFromExe $edgeExe
            if (-not $ud) { $ud = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') }
            Add-DMChromiumDef 'Microsoft Edge' @('msedge') $ud
        }
        $braveExe = Get-DMAppPathExe 'brave.exe'
        if ($braveExe) {
            $ud = Get-DMUserDataFromExe $braveExe
            if (-not $ud) { $ud = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data') }
            Add-DMChromiumDef 'Brave' @('brave') $ud
        }
        $operaExe = Get-DMAppPathExe 'opera.exe'
        if ($operaExe) {
            $ud = Get-DMUserDataFromExe $operaExe
            if ($ud) { Add-DMChromiumDef 'Opera' @('opera') $ud }
            # Opera clasico: perfil en AppData
            $opStable = Join-Path $env:APPDATA 'Opera Software\Opera Stable'
            Add-DMChromiumDef 'Opera' @('opera') $opStable
        }
        $ffExe = Get-DMAppPathExe 'firefox.exe'
        if ($ffExe -and $ffExe -notmatch '(?i)Tor') {
            Add-DMFirefoxDef 'Firefox' @('firefox') (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')
        }
    } catch { }
    Add-DMChromiumDef 'Microsoft Edge' @('msedge') (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
    Add-DMChromiumDef 'Edge Beta'     @('msedge') (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Beta\User Data')
    Add-DMChromiumDef 'Brave'         @('brave') (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')
    Add-DMChromiumDef 'Vivaldi'       @('vivaldi') (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data')
    Add-DMChromiumDef 'Arc'           @('Arc') (Join-Path $env:LOCALAPPDATA 'Arc\User Data')

    # Opera: varias carpetas bajo "Opera Software"
    $operaBase = Join-Path $env:APPDATA 'Opera Software'
    if (Test-Path -LiteralPath $operaBase) {
        foreach ($od in @(Get-ChildItem -LiteralPath $operaBase -Directory -EA SilentlyContinue)) {
            $n = $od.Name
            $label = if ($n -match '(?i)GX') { 'Opera GX' }
                     elseif ($n -match '(?i)beta') { 'Opera Beta' }
                     elseif ($n -match '(?i)developer') { 'Opera Developer' }
                     else { 'Opera' }
            # Opera no usa "User Data"; el perfil es la carpeta misma (o subperfil)
            $root = $od.FullName
            if ($seenRoots.Contains($root)) { continue }
            [void]$seenRoots.Add($root)
            $defs.Add([pscustomobject]@{
                Name = $label; Proc = @('opera'); Roots = @($root); Engine = 'chromium'; TorRoot = $null
            })
        }
    }
    # Opera tambien a veces en LocalAppData
    Add-DMChromiumDef 'Opera (Local)' @('opera') (Join-Path $env:LOCALAPPDATA 'Opera Software\Opera Stable\User Data')
    Add-DMChromiumDef 'Opera GX (Local)' @('opera') (Join-Path $env:LOCALAPPDATA 'Opera Software\Opera GX Stable\User Data')

    # Escaneo extra: cualquier *\User Data\Default\Cache bajo LocalAppData (portables / forks)
    try {
        $la = $env:LOCALAPPDATA
        if ($la -and (Test-Path -LiteralPath $la)) {
            foreach ($vendor in @(Get-ChildItem -LiteralPath $la -Directory -EA SilentlyContinue | Select-Object -First 80)) {
                foreach ($app in @(Get-ChildItem -LiteralPath $vendor.FullName -Directory -EA SilentlyContinue | Select-Object -First 30)) {
                    $ud = Join-Path $app.FullName 'User Data'
                    if (-not (Test-Path -LiteralPath $ud)) { continue }
                    if ($seenRoots.Contains($ud)) { continue }
                    $hasCache = Test-Path -LiteralPath (Join-Path $ud 'Default\Cache')
                    if (-not $hasCache) { continue }
                    # Evitar duplicar los ya nombrados
                    $label = $app.Name
                    if ($label -match '(?i)chrome|edge|brave|vivaldi|chromium|opera|arc') { continue }
                    $procGuess = @('chrome')
                    if ($label -match '(?i)msedge|edge') { $procGuess = @('msedge') }
                    Add-DMChromiumDef $label $procGuess $ud
                }
            }
        }
    } catch { }

    # Firefox + forks
    Add-DMFirefoxDef 'Firefox'   @('firefox')   (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')
    Add-DMFirefoxDef 'LibreWolf' @('librewolf') (Join-Path $env:APPDATA 'librewolf\Profiles')
    Add-DMFirefoxDef 'Waterfox'  @('waterfox')  (Join-Path $env:APPDATA 'Waterfox\Profiles')
    Add-DMFirefoxDef 'Floorp'    @('floorp')    (Join-Path $env:APPDATA 'Floorp\Profiles')

    # Tor Browser  -  deteccion + forzados
    $torRoot = $null
    try { $torRoot = Get-DMFindTorBrowser } catch { $torRoot = $null }
    if (-not $torRoot) {
        # Ultimo recurso: tor-path.txt aunque Test-DMIsTorRoot haya fallado
        try {
            $cfg = Join-Path $env:USERPROFILE 'Documents\DeMente\tor-path.txt'
            if (Test-Path -LiteralPath $cfg -ErrorAction SilentlyContinue) {
                $line = (Get-Content -LiteralPath $cfg -TotalCount 1 -ErrorAction SilentlyContinue)
                if ($line) {
                    $line = ([string]$line).Trim().Trim('"')
                    if ($line -and (Test-Path -LiteralPath $line -ErrorAction SilentlyContinue)) {
                        $torRoot = $line
                    }
                }
            }
        } catch { }
    }
    if ($torRoot) {
        $rootsTor = [System.Collections.Generic.List[string]]::new()
        foreach ($cand in @(
            (Join-Path $torRoot 'Browser\TorBrowser\Data\Browser\profile.default'),
            (Join-Path $torRoot 'Browser\TorBrowser\Data\Browser'),
            (Join-Path $torRoot 'TorBrowser\Data\Browser\profile.default'),
            (Join-Path $torRoot 'TorBrowser\Data\Browser')
        )) {
            try {
                if ($cand -and (Test-Path -LiteralPath $cand -ErrorAction SilentlyContinue)) {
                    [void]$rootsTor.Add($cand)
                }
            } catch { }
        }
        try {
            $bd = Join-Path $torRoot 'Browser\TorBrowser\Data\Browser'
            if (-not (Test-Path -LiteralPath $bd -ErrorAction SilentlyContinue)) {
                $bd = Join-Path $torRoot 'TorBrowser\Data\Browser'
            }
            if (Test-Path -LiteralPath $bd -ErrorAction SilentlyContinue) {
                foreach ($sub in @(Get-ChildItem -LiteralPath $bd -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'profile*' })) {
                    if (-not ($rootsTor -contains $sub.FullName)) { [void]$rootsTor.Add($sub.FullName) }
                }
            }
        } catch { }
        if ($rootsTor.Count -eq 0) {
            # Listar igual con la raiz: Clear-DMBrowserCache busca subcarpetas de cache
            [void]$rootsTor.Add($torRoot)
        }
        $defs.Add([pscustomobject]@{
            Name = 'Tor Browser'
            Proc = @('firefox')
            Roots = @($rootsTor)
            Engine = 'firefox'
            TorRoot = $torRoot
        })
        try {
            $cfgDir = Join-Path $env:USERPROFILE 'Documents\DeMente'
            if (-not (Test-Path -LiteralPath $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null }
            Set-Content -LiteralPath (Join-Path $cfgDir 'tor-path.txt') -Value $torRoot -Encoding UTF8 -Force
        } catch { }
    }

    return @($defs)
}

<#
.SYNOPSIS
    Limpia SOLO la cache tecnica de UN navegador puntual (no contraseñas,
    favoritos, cookies ni historial) y cierra SOLO ese navegador.
#>
function Clear-DMBrowserCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string[]]$ProcessNames,
        [Parameter(Mandatory)][string[]]$ProfileRoots,
        [Parameter(Mandatory)][ValidateSet('chromium','firefox')][string]$Engine,
        [string]$TorRoot = ''
    )
    HR "CACHÉ DE $DisplayName"
    try {
        $procs = @(Get-Process -Name $ProcessNames -ErrorAction SilentlyContinue)
        if ($DisplayName -eq 'Tor Browser') {
            $procs = @($procs | Where-Object {
                try {
                    $pp = $_.Path
                    if (-not $pp) { return $false }
                    if ($TorRoot -and $pp.StartsWith($TorRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                    return ($pp -match 'Tor Browser|TorBrowser')
                } catch { $false }
            })
        }
        if ($procs.Count -gt 0) {
            WARN "Cerrando $DisplayName para poder limpiar su cache (solo este navegador, no los demas)..."
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 900
        }
    } catch { }

    $subs = if ($Engine -eq 'firefox') {
        @('cache2', 'startupCache', 'thumbnails', 'shader-cache')
    } else {
        @(
            'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache',
            'ShaderCache', 'GraphiteDawnCache',
            'Service Worker\CacheStorage', 'blob_storage'
        )
    }

    $count = 0
    $bytes = [double]0
    function Clear-DMCacheFolder([string]$p) {
        if (-not $p -or -not (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { return @{n=0;b=0} }
        try {
            $items = @(Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue)
            $sum = ($items | Measure-Object Length -Sum).Sum
            $b = if ($null -ne $sum) { [double]$sum } else { 0 }
            Remove-Item -LiteralPath (Join-Path $p '*') -Recurse -Force -ErrorAction SilentlyContinue
            return @{ n = $items.Count; b = $b }
        } catch { return @{n=0;b=0} }
    }
    foreach ($root in $ProfileRoots) {
        if (-not $root) { continue }
        try { if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue } } catch { continue }
        $scanDirs = [System.Collections.Generic.List[string]]::new()
        [void]$scanDirs.Add($root)
        # Firefox/Tor: perfiles anidados; Chromium: Default / Profile N
        try {
            foreach ($subDir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -First 40)) {
                $n = $subDir.Name
                if ($Engine -eq 'firefox' -or $n -eq 'Default' -or $n -like 'Profile *' -or $n -like 'profile*') {
                    [void]$scanDirs.Add($subDir.FullName)
                }
            }
        } catch { }
        foreach ($dir in $scanDirs) {
            foreach ($s in $subs) {
                $r = Clear-DMCacheFolder (Join-Path $dir $s)
                $count += [int]$r.n
                $bytes += [double]$r.b
            }
        }
    }
OK "$DisplayName`: $count archivos, $(Human $bytes) liberados. Perfiles, contraseñas, favoritos, cookies e historial intactos."
}

<#
.SYNOPSIS
    Escape hatch cuando la busqueda automatica de Tor Browser no lo encuentra:
    el usuario elige la carpeta a mano, una sola vez, y queda guardada para
    siempre en Documents\DeMente\tor-path.txt (que Get-DMFindTorBrowser ya
    lee como primera prioridad).
#>
function Set-DMTorPathManual {
    [CmdletBinding()]
    param()
    HR "ELEGIR CARPETA DE TOR BROWSER"
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Selecciona la carpeta 'Tor Browser' (la que tiene adentro la carpeta 'Browser')"
        $dlg.ShowNewFolderButton = $false
        $resultado = $dlg.ShowDialog()
        if ($resultado -ne [System.Windows.Forms.DialogResult]::OK -or -not $dlg.SelectedPath) {
            INFO "Cancelado, no se eligio ninguna carpeta."
            return
        }
        $elegida = $dlg.SelectedPath
        # Si el usuario selecciono la subcarpeta "Browser" directamente, subir un nivel.
        if ((Split-Path $elegida -Leaf) -eq 'Browser' -and (Test-Path -LiteralPath (Join-Path $elegida 'firefox.exe'))) {
            $elegida = Split-Path $elegida -Parent
        }
        $exeEsperado = Join-Path $elegida 'Browser\firefox.exe'
        if (-not (Test-Path -LiteralPath $exeEsperado)) {
            WARN "Esa carpeta no parece ser Tor Browser (no se encontro Browser\firefox.exe adentro)."
            WARN "Si estas seguro que es la correcta, revisa que no falte un nivel de carpeta."
            return
        }
        $cfgDir = Join-Path $env:USERPROFILE 'Documents\DeMente'
        if (-not (Test-Path -LiteralPath $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        Set-Content -LiteralPath (Join-Path $cfgDir 'tor-path.txt') -Value $elegida -Encoding UTF8 -Force -ErrorAction Stop
        OK "Guardado: $elegida"
        OK "La proxima vez que abras DeMente, Tor Browser va a aparecer solo en Limpieza."
    } catch {
        ERR "No se pudo completar la seleccion: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Lee el resultado REAL de un SFC recien terminado (idioma-independiente).
.DESCRIPTION
    sfc.exe escribe su veredicto en el idioma de Windows y en UTF-16, lo que
    lo hace fragil de leer. En cambio CBS.log siempre usa marcas [SR] en
    ingles. Se revisan solo las lineas posteriores al inicio de esta corrida.
.PARAMETER Desde
    Momento en que arranco SFC (para ignorar corridas anteriores).
.OUTPUTS
    'limpio' | 'reparado' | 'noreparado' | 'desconocido'
#>
function Get-DMSfcResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$Desde)
    try {
        $log = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
        if (-not (Test-Path -LiteralPath $log)) { return 'desconocido' }
        $lineas = @(Get-Content -LiteralPath $log -Tail 6000 -ErrorAction Stop | Where-Object { $_ -match '\[SR\]' })
        $noRep = $false; $rep = $false; $verificado = $false
        foreach ($l in $lineas) {
            $ts = [datetime]::MinValue
            if ($l.Length -lt 19 -or -not [datetime]::TryParse($l.Substring(0, 19), [ref]$ts)) { continue }
            if ($ts -lt $Desde.AddSeconds(-5)) { continue }
            if ($l -match 'Cannot repair member file') { $noRep = $true }
            elseif ($l -match 'Repairing (\d+) components' -and [int]$Matches[1] -gt 0) { $rep = $true }
            elseif ($l -match 'Repairing corrupted file') { $rep = $true }
            elseif ($l -match 'Verify complete') { $verificado = $true }
        }
        # Marcas extra frecuentes en CBS.log (ingles fijo de [SR])
        foreach ($l in $lineas) {
            $ts = [datetime]::MinValue
            if ($l.Length -lt 19 -or -not [datetime]::TryParse($l.Substring(0, 19), [ref]$ts)) { continue }
            if ($ts -lt $Desde.AddSeconds(-5)) { continue }
            if ($l -match 'found corrupt files|Unable to fix|failed to repair') { $noRep = $true }
            elseif ($l -match 'Successfully repaired|Repaired file|Beginning repair') { $rep = $true }
            elseif ($l -match 'did not find any integrity|no integrity violations|verification successfully') { $verificado = $true }
        }
        if ($noRep) { return 'noreparado' }
        if ($rep) { return 'reparado' }
        if ($verificado) { return 'limpio' }
        return 'desconocido'
    } catch { return 'desconocido' }
}

<#
.SYNOPSIS
    Explica en criollo que paso con SFC, segun Get-DMSfcResult.
#>
function Write-DMSfcVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Resultado, [int]$ExitCode = 0)
    Write-Host ""
    Write-Host "=== RESULTADO DE SFC ==="
    switch ($Resultado) {
        'limpio' {
            OK "RESULTADO: sistema sano"
            OK "Windows reviso todos sus archivos importantes y no encontro ninguno danado."
            INFO "No hace falta reiniciar ni hacer nada mas por este escaneo."
        }
        'reparado' {
            OK "RESULTADO: se repararon archivos danados"
            OK "Windows encontro archivos del sistema danados y los reparo."
            WARN "Conviene reiniciar la PC para que todo quede aplicado del todo."
            INFO "Si despues de reiniciar seguis con problemas, volve a correr SFC."
        }
        'noreparado' {
            WARN "RESULTADO: hay danos que SFC no pudo arreglar solo"
            WARN "Windows encontro archivos danados pero no pudo reparar todos."
            INFO "Siguiente paso: ejecuta 'Reparar la base de Windows (DISM)', reinicia, y despues repeti SFC."
        }
        default {
            if ($ExitCode -eq 0) {
                INFO "RESULTADO: SFC termino (codigo 0) pero no pude leer el detalle en CBS.log"
                INFO "Si tu PC anda bien, no hace falta nada mas. Si notas fallas, corre DISM y despues SFC de nuevo."
            } else {
                WARN "RESULTADO: SFC termino de forma inesperada (codigo $ExitCode)"
                INFO "Proba 'Reparar la base de Windows (DISM)' y despues repeti SFC."
            }
        }
    }
    Write-Host "========================"
}


'@

# -- CARGA DEL PRELUDIO EN EL PROCESO PRINCIPAL -------------------------------
# El bloque anterior (Step/OK/WARN/ERR/Get-RegValue/Set-Reg/Remove-Reg/etc.)
# es el preludio que se antepone al codigo de cada herramienta cuando corre
# en su propio proceso powershell.exe (ver usos en Set-Content mas abajo).
# Pero el propio motor principal (GUI: Get-WDMPrivacyState, Get-DiagnosticoCompleto,
# Get-WDMAppliedState, etc.) tambien llama a esas mismas funciones, y como solo
# existian dentro del string nunca quedaban definidas en este proceso. Por eso
# fallaban con "el termino Get-RegValue no se reconoce...". Se cargan aqui una
# sola vez para que el proceso principal tenga las mismas funciones.
Invoke-Expression $Global:Prelude

# -- SALUD DE ALMACENAMIENTO (proceso principal / Dashboard / F5) ------------
function Get-WDMDiskHealth {
    $discos = @()
    try { $fisicos = @(Get-PhysicalDisk -EA Stop) } catch { $fisicos = @() }
    try { $particiones = @(Get-CimInstance Win32_DiskPartition -EA Stop) } catch { $particiones = @() }

    foreach ($pd in $fisicos) {
        $obj = [pscustomobject]@{
            Numero = $pd.DeviceId
            Modelo = ($pd.FriendlyName).Trim()
            NumeroSerie = ($pd.SerialNumber -as [string]).Trim()
            TipoMedio = 'Desconocido'
            Interfaz = [string]$pd.BusType
            CapacidadGB = [math]::Round($pd.Size / 1GB, 1)
            EstadoSalud = [string]$pd.HealthStatus
            Temperatura = $null
            TemperaturaMax = $null
            DesgastePct = $null
            HorasEncendido = $null
            CiclosEncendido = $null
            ErroresLecturaTotal = $null
            ErroresLecturaNoCorregidos = $null
            ErroresEscrituraTotal = $null
            ErroresEscrituraNoCorregidos = $null
            FuenteSMART = 'No disponible'
            Volumenes = @()
            EstadoLabel = 'No disponible'
            EstadoDetalle = 'Este disco no expone informacion SMART fiable a Windows.'
        }

        if ($pd.MediaType -match 'SSD') { $obj.TipoMedio = if ($obj.Interfaz -match 'NVMe') { 'NVMe' } else { 'SSD' } }
        elseif ($pd.MediaType -match 'HDD') { $obj.TipoMedio = 'HDD' }
        elseif ($obj.Interfaz -match 'NVMe') { $obj.TipoMedio = 'NVMe' }
        elseif ($obj.Modelo -match 'NVMe') { $obj.TipoMedio = 'NVMe' }
        elseif ($obj.Modelo -match 'SSD|M\.2|Solid State') { $obj.TipoMedio = 'SSD' }

        try {
            $rel = $pd | Get-StorageReliabilityCounter -EA Stop
            if ($rel) {
                $obj.FuenteSMART = 'StorageReliabilityCounter'
                if ($rel.Temperature -gt 0) { $obj.Temperatura = [int]$rel.Temperature }
                if ($rel.TemperatureMax -gt 0) { $obj.TemperaturaMax = [int]$rel.TemperatureMax }
                if ($null -ne $rel.Wear) { $obj.DesgastePct = [int]$rel.Wear }
                if ($rel.PowerOnHours -gt 0) { $obj.HorasEncendido = [int]$rel.PowerOnHours }
                if ($rel.StartStopCount -gt 0) { $obj.CiclosEncendido = [int]$rel.StartStopCount }
                elseif ($rel.LoadUnloadCycleCount -gt 0) { $obj.CiclosEncendido = [int]$rel.LoadUnloadCycleCount }
                $obj.ErroresLecturaTotal = $rel.ReadErrorsTotal
                $obj.ErroresLecturaNoCorregidos = $rel.ReadErrorsUncorrected
                $obj.ErroresEscrituraTotal = $rel.WriteErrorsTotal
                $obj.ErroresEscrituraNoCorregidos = $rel.WriteErrorsUncorrected
            }
        } catch { }

        $indicadores = @()
        if ($obj.ErroresLecturaNoCorregidos -gt 0) { $indicadores += 'errores de lectura no corregidos' }
        if ($obj.ErroresEscrituraNoCorregidos -gt 0) { $indicadores += 'errores de escritura no corregidos' }
        if ($obj.EstadoSalud -eq 'Unhealthy') { $indicadores += 'estado reportado como no saludable por Windows' }
        if ($null -ne $obj.DesgastePct -and $obj.DesgastePct -ge 90) { $indicadores += "desgaste elevado ($($obj.DesgastePct)%)" }

        if ($indicadores.Count -gt 0) {
            $obj.EstadoLabel = 'Riesgo'
            $obj.EstadoDetalle = 'Se detectaron indicadores compatibles con degradacion: ' + ($indicadores -join ', ') + '.'
        } elseif ($obj.EstadoSalud -eq 'Warning' -or ($null -ne $obj.DesgastePct -and $obj.DesgastePct -ge 70)) {
            $obj.EstadoLabel = 'Atencion'
            $obj.EstadoDetalle = 'Hay indicadores que conviene monitorear con el tiempo.'
        } elseif ($obj.FuenteSMART -ne 'No disponible' -or $obj.EstadoSalud -eq 'Healthy') {
            $obj.EstadoLabel = 'Bueno'
            $obj.EstadoDetalle = 'No se detectan indicadores de degradacion.'
        }

        $discos += $obj
    }

    foreach ($part in $particiones) {
        $disco = $discos | Where-Object { $_.Numero -eq $part.DiskIndex }
        if (-not $disco) { continue }
        try { $vols = @(Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk -EA Stop) } catch { $vols = @() }
        foreach ($v in $vols) {
            if (-not $v.Size -or $v.Size -eq 0) { continue }
            $pct = [math]::Round((($v.Size - $v.FreeSpace) / $v.Size) * 100)
            $disco.Volumenes += [pscustomobject]@{
                Letra = $v.DeviceID
                TotalGB = [math]::Round($v.Size / 1GB, 1)
                LibreGB = [math]::Round($v.FreeSpace / 1GB, 1)
                PorcentajeUsado = $pct
            }
        }
    }
    return $discos
}

function Save-WDMDiskHealthSnapshot {
    param([array]$Discos)
    try {
        $carpeta = WDM-Dir '\HealthHistory'
        $archivo = Join-Path $carpeta 'disk_health.json'
        $historial = @()
        if (Test-Path $archivo) {
            try { $historial = @(Get-Content $archivo -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $historial = @() }
        }
        $fecha = Get-Date -Format 'yyyy-MM-dd'
        $historial = @($historial | Where-Object { -not ($_.Fecha -eq $fecha -and ($Discos.NumeroSerie -contains $_.Serie)) })
        foreach ($d in $Discos) {
            if (-not $d.NumeroSerie) { continue }
            $historial += [pscustomobject]@{ Fecha = $fecha; Serie = $d.NumeroSerie; Desgaste = $d.DesgastePct; Temperatura = $d.Temperatura }
        }
        $limite = (Get-Date).AddDays(-400).ToString('yyyy-MM-dd')
        $historial = @($historial | Where-Object { $_.Fecha -ge $limite })
        $historial | ConvertTo-Json -Depth 4 | Set-Content $archivo -Encoding UTF8
    } catch { }
}

function Get-WDMDiskHealthTrend {
    param([string]$Serie)
    try {
        $archivo = Join-Path (WDM-Dir '\HealthHistory') 'disk_health.json'
        if (-not (Test-Path $archivo)) { return $null }
        $historial = @(Get-Content $archivo -Raw -Encoding UTF8 | ConvertFrom-Json)
        $registros = @($historial | Where-Object { $_.Serie -eq $Serie -and $null -ne $_.Desgaste } | Sort-Object Fecha)
        if ($registros.Count -lt 2) { return $null }
        $hoy = $registros[-1]
        $hace30 = $registros | Where-Object { ([datetime]$hoy.Fecha - [datetime]$_.Fecha).Days -ge 25 } | Select-Object -Last 1
        $hace90 = $registros | Where-Object { ([datetime]$hoy.Fecha - [datetime]$_.Fecha).Days -ge 85 } | Select-Object -Last 1
        return [pscustomobject]@{
            Hoy = $hoy.Desgaste
            Hace30d = if ($hace30) { $hace30.Desgaste } else { $null }
            Hace90d = if ($hace90) { $hace90.Desgaste } else { $null }
        }
    } catch { return $null }
}

function Show-WDMDiskHealthReport {
    $discos = Get-WDMDiskHealth
    if (@($discos).Count -eq 0) { ERR 'No se pudo consultar informacion de discos.'; return }
    Save-WDMDiskHealthSnapshot -Discos $discos
    foreach ($d in $discos) {
        HR ("DISCO $($d.Numero) - $($d.Modelo)")
        ROW 'Tipo' $d.TipoMedio
        ROW 'Interfaz' $d.Interfaz
        ROW 'Capacidad' ("$($d.CapacidadGB) GB")
        foreach ($v in $d.Volumenes) {
            ROW ("Volumen $($v.Letra)") ("{0} GB usados de {1} GB ({2}% usado)" -f [math]::Round($v.TotalGB - $v.LibreGB, 1), $v.TotalGB, $v.PorcentajeUsado)
        }
        Write-Host ''
        switch ($d.EstadoLabel) {
            'Bueno'    { OK   "Estado: Bueno" }
            'Atencion' { WARN "Estado: Atencion" }
            'Riesgo'   { ERR  "Estado: Riesgo" }
            default    { INFO "Estado: No disponible" }
        }
        ROW '  Detalle' $d.EstadoDetalle
        if ($null -ne $d.DesgastePct) { ROW 'Vida util restante estimada' ("$(100 - $d.DesgastePct)%") }
        if ($null -ne $d.Temperatura) { ROW 'Temperatura' ("$($d.Temperatura) C") }
        if ($null -ne $d.HorasEncendido) { ROW 'Horas de funcionamiento' $d.HorasEncendido }
        if ($null -ne $d.CiclosEncendido) { ROW 'Ciclos de encendido' $d.CiclosEncendido }
        if ($null -ne $d.ErroresLecturaNoCorregidos) { ROW 'Errores de lectura no corregidos' $d.ErroresLecturaNoCorregidos }
        if ($null -ne $d.ErroresEscrituraNoCorregidos) { ROW 'Errores de escritura no corregidos' $d.ErroresEscrituraNoCorregidos }
        if ($d.FuenteSMART -eq 'No disponible') { ROW 'SMART' 'No disponible en este dispositivo/controlador' }
        if ($d.NumeroSerie) {
            $tend = Get-WDMDiskHealthTrend -Serie $d.NumeroSerie
            if ($tend -and $null -ne $tend.Hace30d) {
                Write-Host ''
                Write-Host '    Tendencia de desgaste:'
                ROW '  Hoy' ("$($tend.Hoy)%")
                ROW '  Hace ~30 dias' ("$($tend.Hace30d)%")
                if ($null -ne $tend.Hace90d) { ROW '  Hace ~90 dias' ("$($tend.Hace90d)%") }
            }
        }
        Write-Host ''
    }
    OK 'Analisis de salud de almacenamiento completado.'
}

# -- ESTADO REAL DE PRIVACIDAD (lectura, nunca modifica nada) -----------------
function Get-WDMPrivacyState {
    # Refleja, para cada sector de privacidad, si el valor actual de Windows ya
    # coincide con lo que DeMente propone. No modifica nada: solo lee.
    $items = @()

    $adv = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
    $items += [pscustomobject]@{ Id='privacy-advertising'; Nombre='ID de publicidad'; Aplicado=($adv -eq 0) }

    $loc = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value'
    $items += [pscustomobject]@{ Id='privacy-location'; Nombre='Ubicación'; Aplicado=($loc -eq 'Deny') }

    $tel = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    $items += [pscustomobject]@{ Id='privacy-telemetry'; Nombre='Telemetría'; Aplicado=($tel -eq 0) }

    $af = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed'
    $pu = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities'
    $uu = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities'
    $items += [pscustomobject]@{ Id='privacy-activity'; Nombre='Historial de actividad'; Aplicado=($af -eq 0 -and $pu -eq 0 -and $uu -eq 0) }

    $mic = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone' 'Value'
    $items += [pscustomobject]@{ Id='privacy-microphone'; Nombre='Micrófono'; Aplicado=($mic -eq 'Deny') }

    $cam = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' 'Value'
    $items += [pscustomobject]@{ Id='privacy-camera'; Nombre='Cámara'; Aplicado=($cam -eq 'Deny') }

    $bing = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled'
    $items += [pscustomobject]@{ Id='privacy-bing'; Nombre='Bing en búsqueda'; Aplicado=($bing -eq 0) }

    $gdvr1 = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    $gdvr2 = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
    $items += [pscustomobject]@{ Id='privacy-gamedvr'; Nombre='GameDVR'; Aplicado=($gdvr1 -eq 0 -and $gdvr2 -eq 0) }

    $cc1 = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    $cc2 = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowClipboardHistory'
    $items += [pscustomobject]@{ Id='privacy-clipboard'; Nombre='Portapapeles en la nube'; Aplicado=($cc1 -eq 0 -and $cc2 -eq 0) }

    $sh = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled'
    $items += [pscustomobject]@{ Id='privacy-searchhighlights'; Nombre='Destacados de búsqueda'; Aplicado=($sh -eq 0) }

    $ceip = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable'
    $items += [pscustomobject]@{ Id='privacy-ceip'; Nombre='CEIP/SQM'; Aplicado=($ceip -eq 0) }

    return $items
}

# -- FUNCIONES DE DIAGNOSTICO --------------------------------------------------
# Multiescaneo inicial por areas. No inventa un puntaje 0-100.
# Devuelve hallazgos reales por seccion para el resumen del sistema.
# ========== DEMENTE SALUD v1.0.0.1 (motor) ==========
function Get-SaludDeMente {
    $ErrorActionPreference = 'SilentlyContinue'
    $t0 = Get-Date
    $Hallazgos = [System.Collections.Generic.List[object]]::new()
    $Puentes = [System.Collections.Generic.List[string]]::new()
    $CompCount = 0; $ElemCount = 0
    function Add-H([string]$Texto, [int]$Peso, [string]$Puente = '') {
        $Hallazgos.Add([pscustomobject]@{ Texto=$Texto; Peso=$Peso; Puente=$Puente })
        if ($Puente -and $Puentes -notcontains $Puente) { [void]$Puentes.Add($Puente) }
    }
    function Get-ExeS([string]$cmd) {
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
        $c = $cmd.Trim()
        if ($c.StartsWith('"')) { $e=$c.IndexOf('"',1); if($e -gt 1){ return $c.Substring(1,$e-1) } }
        $exp = [Environment]::ExpandEnvironmentVariables($c)
        if ($exp -match '(?i)(^|")([^"]+\.(exe|dll|sys|com|bat|cmd))("|\s|$)') { return $Matches[2] }
        if ($exp -notmatch ' ') { return $exp.Trim('"') }
        return ($exp -split ' ',2)[0].Trim('"')
    }
    function Test-SafeS([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return $false }
        $e = [Environment]::ExpandEnvironmentVariables($p.Trim('"'))
        return (Test-Path -LiteralPath $e -EA SilentlyContinue)
    }
    function Get-RV([string]$Path,[string]$Name) {
        try { return (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name } catch { return $null }
    }

    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ramMods = @(Get-CimInstance Win32_PhysicalMemory)
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA 0
    $totalRamGB = [math]::Round(($ramMods | Measure-Object Capacity -Sum).Sum / 1GB, 1)
    $winVer = "$($cv.ProductName) $($cv.DisplayVersion)".Trim()
    $build = $cv.CurrentBuildNumber
    $arch = $os.OSArchitecture
    $esLaptop = [bool](Get-CimInstance Win32_Battery -EA 0)
    $cores = [int]$cpu.NumberOfCores
    $CompCount += 8; $ElemCount += 8

    $uptime = [TimeSpan]::FromSeconds(0)
    try {
        $evBoot = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12 } -MaxEvents 1 -EA 0
        if ($evBoot) { $uptime = (Get-Date) - $evBoot.TimeCreated }
    } catch { try { $uptime = [TimeSpan]::FromMilliseconds([Environment]::TickCount64) } catch {} }

    # WINDOWS
    $pending = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'Windows Update' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'Componentes' }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations') { $pending += 'Archivos' }
    $CompCount += 3
    $crit = @('Winmgmt','EventLog','RpcSs','Dnscache','BFE','mpssvc','wuauserv','BITS','CryptSvc','Schedule')
    $svcDown = @()
    foreach ($n in $crit) {
        $s = Get-Service -Name $n -EA 0; $CompCount++
        if ($s -and $s.StartType -eq 'Automatic' -and $s.Status -ne 'Running') { $svcDown += $s.DisplayName }
    }
    $bWindows = "$winVer (build $build, $arch) responde con normalidad."
    if ($pending.Count -gt 0) {
        $bWindows = "Windows esta operativo. Hay una reparacion aplicada que se termina de completar recien al reiniciar ($($pending -join ', '))."
        # Peso 1 (no 2): esto NO es "sigue roto". Windows deja esta marca cada vez
        # que DISM/SFC/Windows Update tocan componentes, y solo se borra con un
        # reinicio REAL del equipo (relanzar este script no cuenta). Por eso
        # puede verse igual escaneo tras escaneo hasta que el usuario reinicie.
        Add-H "Reinicio pendiente para terminar una reparacion/actualizacion ($($pending -join ', ')). No significa que algo siga roto: reinicia Windows (no solo DeMente) para que se aplique del todo." 1 'Ver en Reparación'
    }
    if ($svcDown.Count -gt 0) {
        $bWindows = 'Windows está operativo, pero hay servicios importantes detenidos.'
        Add-H "Servicios importantes detenidos: $($svcDown -join ', ')." 2 'Ver en Reparación'
    }

    # RENDIMIENTO
    $usedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)
    $freeMB = [math]::Round($os.FreePhysicalMemory / 1KB)
    $CompCount += 2
    $pagesPerSec = $null
    try { $pagesPerSec = [math]::Round((Get-Counter '\Memory\Pages/sec' -EA Stop).CounterSamples.CookedValue, 0) } catch {}
    $CompCount++
    $paginaActiva = ($null -ne $pagesPerSec -and $pagesPerSec -gt 80)
    $tweakPerf = @()
    $wps = Get-RV 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
    $idealPrio = if ($cores -le 2) { 18 } elseif ($cores -le 4) { 26 } else { 38 }
    if ($null -ne $wps -and [int]$wps -ne $idealPrio -and [int]$wps -ne 2) { $tweakPerf += "Prioridad CPU modificada (actual: $wps)" }
    $vfx = Get-RV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
    if ($null -ne $vfx -and [int]$vfx -eq 2) { $tweakPerf += 'Efectos visuales en modo rendimiento' }
    $ntfs = Get-RV 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
    if ($null -ne $ntfs) {
        $ntfsLow = [int]([uint32]$ntfs -band 0xFF)
        if ($ntfsLow -eq 1 -or $ntfsLow -eq 3) { $tweakPerf += 'NTFS last-access desactivado' }
    }
    $CompCount += 3
    $runTotal = 0; $runRotos = 0
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
        $p = Get-ItemProperty $k -EA 0
        if ($p) {
            $props = @($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Value })
            $runTotal += $props.Count
            foreach ($pr in $props) {
                $exe = Get-ExeS $pr.Value; $ElemCount++
                if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)rundll32|SecurityHealth') { $runRotos++ }
            }
        }
    }
    Get-CimInstance Win32_StartupCommand | ForEach-Object {
        $exe = Get-ExeS $_.Command; $ElemCount++
        if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)SecurityHealth|RUNDLL32|explorer') { $runRotos++ }
    }
    $CompCount += 4
    $bRendimiento = 'No se observó un cuello de botella único en este escaneo.'
    if ($usedPct -ge 92 -and $paginaActiva) {
        $bRendimiento = 'La memoria tiene muy poco margen y se observa actividad de paginación.'
        Add-H "Memoria bajo presión ($usedPct% en uso) con paginación activa." 2 'Ver en Rendimiento'
    } elseif ($usedPct -ge 92) {
        $bRendimiento = 'La memoria está muy cargada en este momento.'
        Add-H "La memoria está muy cargada ahora mismo ($usedPct%, ~$freeMB MB libres)." 2 'Ver en Rendimiento'
    } elseif ($usedPct -ge 85 -and $paginaActiva) {
        $bRendimiento = 'Hay uso elevado de memoria y actividad de paginación.'
        Add-H 'Uso elevado de memoria con paginación activa.' 1 'Ver en Rendimiento'
    } elseif ($totalRamGB -lt 8 -and $paginaActiva) {
        $bRendimiento = "Con $totalRamGB GB de RAM se observa paginación; el impacto depende del uso."
        Add-H "Hay paginación activa en un equipo con $totalRamGB GB de RAM." 1 'Ver en Rendimiento'
    } elseif ($totalRamGB -lt 8) {
        $bRendimiento = "El equipo tiene $totalRamGB GB de RAM. En este escaneo no se midió presión extrema sostenida."
    }
    if ($tweakPerf.Count -gt 0) {
        $bRendimiento += ' Se detectaron ajustes de rendimiento diferentes a los valores predeterminados de Windows.'
    }

    # ALMACENAMIENTO
    $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $librePct = [math]::Round($vol.FreeSpace / $vol.Size * 100)
    $libreGB = [math]::Round($vol.FreeSpace / 1GB, 1)
    $pds = @(Get-PhysicalDisk -EA 0)
    $tieneSSD = $false; $discoAlerta = $null
    foreach ($pd in $pds) {
        $ElemCount++
        if ($pd.MediaType -match 'SSD' -or $pd.Model -match 'SSD|NVMe|Solid') { $tieneSSD = $true }
        if ($pd.HealthStatus -eq 'Unhealthy') { $discoAlerta = 'no saludable' }
        elseif ($pd.HealthStatus -eq 'Warning' -and -not $discoAlerta) { $discoAlerta = 'con advertencia' }
    }
    $CompCount += 4
    if ($discoAlerta) {
        $bAlmacenamiento = "Windows reporta un disco $discoAlerta. El volumen del sistema tiene $librePct% libre."
        Add-H "Windows reporta un disco $discoAlerta." 3 'Ver en Reparación'
    } elseif ($librePct -lt 10) {
        $bAlmacenamiento = "Queda muy poco espacio libre en el disco del sistema ($librePct%)."
        Add-H "Espacio crítico en el disco del sistema ($librePct% libre)." 2 'Ver en Limpieza'
    } elseif ($librePct -lt 18) {
        $bAlmacenamiento = "Espacio libre bajo ($librePct%). Windows no reporta una alerta física evidente."
        Add-H "Espacio libre bajo en el disco del sistema ($librePct%)." 1 'Ver en Limpieza'
    } elseif (-not $tieneSSD -and $paginaActiva) {
        $bAlmacenamiento = 'Disco HDD. Windows no reporta una alerta física evidente. Hay paginación activa. En este escaneo no se midió latencia elevada.'
        Add-H 'Hay paginación activa sobre almacenamiento HDD.' 1 'Ver en Rendimiento'
    } elseif (-not $tieneSSD) {
        $bAlmacenamiento = 'Disco HDD. Windows no reporta una alerta física evidente y hay espacio aceptable. En este escaneo no se midió latencia elevada.'
    } else {
        $bAlmacenamiento = "Almacenamiento SSD/NVMe. Windows no reporta una alerta física evidente. Espacio libre: $librePct% ($libreGB GB)."
    }

    # SEGURIDAD / PRIVACIDAD
    $secTexto = 'No se pudo comprobar la protección en tiempo real.'; $secOk = $false
    try {
        $def = Get-MpComputerStatus -EA Stop; $CompCount += 2
        if ($def.RealTimeProtectionEnabled) { $secTexto = 'Protección en tiempo real activa.'; $secOk = $true }
        else { $secTexto = 'La protección en tiempo real no está activa.'; Add-H 'Microsoft Defender no tiene la protección en tiempo real activa.' 2 'Ver en Seguridad' }
    } catch { $CompCount++ }
    try {
        $fw = @(Get-NetFirewallProfile -EA 0 | Where-Object { $_.Enabled -eq $false }); $CompCount++
        if ($fw.Count -gt 0) {
            Add-H "Hay perfiles de Firewall desactivados ($(($fw | ForEach-Object Name) -join ', '))." 2 'Ver en Seguridad'
            $secTexto += ' Firewall con perfiles desactivados.'
        }
    } catch {}
    $privPend = 0
    foreach ($i in @(
        @{P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection';N='AllowTelemetry';G=0},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';N='Enabled';G=0},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';N='TailoredExperiencesWithDiagnosticDataEnabled';G=0},
        @{P='HKCU:\Software\Microsoft\Siuf\Rules';N='NumberOfSIUFInPeriod';G=0}
    )) {
        $CompCount++
        try {
            if (Test-Path $i.P) { $v = Get-RV $i.P $i.N; if ($null -eq $v -or $v -ne $i.G) { $privPend++ } }
            else { $privPend++ }
        } catch { $privPend++ }
    }
    $yaraTxt = 'YARA: no comprobado en este equipo.'
    $yaraHome = Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara'
    if (Test-Path $yaraHome) {
        $bin = Test-Path (Join-Path $yaraHome 'bin'); $rules = Test-Path (Join-Path $yaraHome 'rules'); $CompCount += 2
        if ($bin -and $rules) { $yaraTxt = 'YARA: motor y reglas presentes (sin escaneo profundo en Salud).' }
        elseif ($bin -or $rules) { $yaraTxt = 'YARA: instalación parcial.' }
        else { $yaraTxt = 'YARA: carpeta presente, sin motor/reglas claros.' }
    }
    $bSegPriv = $secTexto
    if ($privPend -gt 0) {
        $bSegPriv = $(if ($secOk) { 'Protección activa. ' } else { "$secTexto " }) + "Hay $privPend ajuste(s) de privacidad distintos de los valores predeterminados de Windows."
        Add-H "Hay $privPend configuración(es) de privacidad distintas de los valores predeterminados de Windows." 1 'Ver en Privacidad'
    }
    $bSegPriv += " $yaraTxt"

    # CONFIG / ESTABILIDAD
    $svcBroken = 0
    Get-CimInstance Win32_Service | ForEach-Object {
        $exe = Get-ExeS $_.PathName; $ElemCount++
        if ($exe -and -not (Test-SafeS $exe) -and $exe -notmatch '(?i)\\System32\\|\\SysWOW64\\|svchost|dllhost') { $svcBroken++ }
    }
    $CompCount += 2
    $residuos = $runRotos + $svcBroken
    $apagados = 0; $whea = 0
    try {
        $kp = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=(Get-Date).AddDays(-14) } -MaxEvents 30 -EA 0
        $apagados = @($kp | Where-Object { $_.Id -in 41,109 }).Count; $CompCount++
    } catch {}
    try {
        $wh = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-14) } -MaxEvents 15 -EA 0
        $whea = @($wh).Count; $CompCount++
    } catch {}
    $netTexto = 'Red no comprobada por completo.'
    try {
        $ads = @(Get-NetAdapter -EA 0 | Where-Object Status -eq 'Up'); $CompCount++
        if ($ads.Count -eq 0) { $netTexto = 'Sin adaptador de red activo.'; Add-H 'No hay adaptadores de red activos.' 1 '' }
        else {
            $ip = @(Get-NetIPConfiguration -EA 0 | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
            $hasGw = $ip.Count -gt 0; $dnsOk = $false
            try { $r = Resolve-DnsName 'www.microsoft.com' -Type A -DnsOnly -EA Stop -QuickTimeout; if ($r) { $dnsOk = $true } } catch {}
            $CompCount += 2
            if ($hasGw -and $dnsOk) { $netTexto = 'Red operativa (adaptador, puerta de enlace y DNS).' }
            elseif ($hasGw -and -not $dnsOk) { $netTexto = 'Red local presente; no se confirmó resolución DNS.'; Add-H 'Hay red local, pero no se confirmó acceso a internet (DNS).' 1 'Ver en Reparación' }
            elseif (-not $hasGw) { $netTexto = 'Adaptador activo sin puerta de enlace clara.'; Add-H 'Configuración de red parece incompleta.' 1 'Ver en Reparación' }
        }
    } catch {}
    $configBase = 'Inicio y servicios sin residuos evidentes.'
    if ($residuos -ge 3) {
        $configBase = 'Hay varias referencias residuales (inicio/servicios).'
        Add-H "Se encontraron $residuos referencias residuales en inicio o servicios." 1 'Ver en Limpieza'
    } elseif ($residuos -gt 0) {
        $configBase = 'Hay algunas referencias residuales de bajo impacto.'
        Add-H "Hay referencias residuales en inicio o servicios ($residuos)." 1 'Ver en Limpieza'
    } elseif ($runTotal -ge 15) {
        $configBase = "Hay muchos programas al inicio ($runTotal en Run)."
        Add-H "Hay muchos programas al inicio ($runTotal)." 1 'Ver en Rendimiento'
    }
    $estabilidadTxt = ''
    if ($apagados -gt 0) {
        Add-H "Windows registró $apagados apagado(s) o reinicio(s) inesperado(s) en 14 días. La causa no está determinada en este escaneo." 1 'Ver en Reparación'
        $estabilidadTxt = 'Hay señales de estabilidad a tener en cuenta.'
    }
    if ($whea -gt 0) {
        Add-H "Hay eventos WHEA (hardware) recientes ($whea)." 2 'Ver en Reparación'
        if (-not $estabilidadTxt) { $estabilidadTxt = 'Hay señales de hardware a tener en cuenta.' }
    }
    $bConfig = $configBase
    if ($estabilidadTxt) { $bConfig += " $estabilidadTxt" }
    $bConfig += " $netTexto"

    $dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $maxPeso = 0
    if ($Hallazgos.Count -gt 0) { $maxPeso = ($Hallazgos | Measure-Object Peso -Maximum).Maximum }
    $titulo = 'No encontramos nada que requiera atención inmediata.'
    if ($maxPeso -ge 3) { $titulo = 'Encontramos un problema que merece atención.' }
    elseif ($maxPeso -eq 2) { $titulo = 'Encontramos algo que conviene revisar.' }
    elseif ($maxPeso -eq 1) { $titulo = 'Encontramos algunas condiciones que conviene tener en cuenta.' }
    $top = @($Hallazgos | Sort-Object Peso -Descending | Select-Object -First 4)

    return [pscustomobject]@{
        Version = '1.0.0.1'
        Titulo = $titulo
        MaxPeso = $maxPeso
        Equipo = "$($cs.Manufacturer) $($cs.Model)".Trim()
        WinVer = $winVer
        RAMGB = $totalRamGB
        TieneSSD = $tieneSSD
        EsLaptop = $esLaptop
        CPUName = $cpu.Name.Trim()
        Uptime = $uptime
        BloqueWindows = $bWindows
        BloqueRendimiento = $bRendimiento
        BloqueAlmacenamiento = $bAlmacenamiento
        BloqueSegPriv = $bSegPriv
        BloqueConfig = $bConfig
        TweaksPerf = $tweakPerf
        Hallazgos = $top
        HallazgosTotal = $Hallazgos.Count
        Puentes = @($Puentes)
        CompCount = $CompCount
        ElemCount = $ElemCount
        DuracionSeg = $dur
    }
}

function Show-SaludDeMenteConsole {
    param($SaludObj)
    $s = if ($SaludObj) { $SaludObj } else { Get-SaludDeMente }
    $Global:Salud = $s
    $col = switch ([int]$s.MaxPeso) { 3 {'Red'} 2 {'DarkYellow'} 1 {'Yellow'} default {'Green'} }
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║                         INFORME DE SALUD DEMENTE                            ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host "  Equipo: $($s.Equipo)" -ForegroundColor White
    Write-Host "  CPU:    $($s.CPUName)" -ForegroundColor Gray
    Write-Host "  RAM:    $($s.RAMGB) GB    Disco: $(if($s.TieneSSD){'SSD/NVMe'}else{'HDD'})    SO: $($s.WinVer)" -ForegroundColor Gray
    Write-Host "  ESTADO GENERAL: $($s.Titulo)" -ForegroundColor $col
    Write-Host ''
    $areas = @(
      @{N='Windows'; T=$s.BloqueWindows; P='Windows'},
      @{N='Rendimiento'; T=$s.BloqueRendimiento; P='Rendimiento'},
      @{N='Almacenamiento'; T=$s.BloqueAlmacenamiento; P='Almacenamiento|Limpieza'},
      @{N='Seguridad/Priv.'; T=$s.BloqueSegPriv; P='Seguridad|Privacidad'},
      @{N='Inicio y estabilidad'; T=$s.BloqueConfig; P='Limpieza|Rendimiento|Reparación|Reparacion'}
    )
    Write-Host '  ┌─────────────────┬────────────┬──────────────────────────────────────────────┐' -ForegroundColor DarkGray
    Write-Host '  │ Área            │ Estado     │ Detalle                                      │' -ForegroundColor DarkGray
    Write-Host '  ├─────────────────┼────────────┼──────────────────────────────────────────────┤' -ForegroundColor DarkGray
    foreach ($a in $areas) {
      $peso = 0; foreach ($h in @($s.Hallazgos)) { if ($h.Puente -match $a.P) { $peso = [Math]::Max($peso,[int]$h.Peso) } }
      $estado = switch ($peso) { 3 {'X Crítico'} 2 {'! Atención'} 1 {'i Revisar'} default {'  OK'} }
      $ec = switch ($peso) { 3 {'Red'} 2 {'Yellow'} 1 {'DarkYellow'} default {'Green'} }
      $detalle = [string]$a.T; if ($detalle.Length -gt 44) { $detalle = $detalle.Substring(0,41) + '...' }
      Write-Host '  │ ' -NoNewline -ForegroundColor DarkGray; Write-Host ('{0,-15}' -f $a.N) -NoNewline -ForegroundColor White; Write-Host ' │ ' -NoNewline -ForegroundColor DarkGray; Write-Host ('{0,-10}' -f $estado) -NoNewline -ForegroundColor $ec; Write-Host ' │ ' -NoNewline -ForegroundColor DarkGray; Write-Host ('{0,-44}' -f $detalle) -NoNewline -ForegroundColor Gray; Write-Host ' │' -ForegroundColor DarkGray
    }
    Write-Host '  └─────────────────┴────────────┴──────────────────────────────────────────────┘' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  HALLAZGOS DETALLADOS ($($s.HallazgosTotal))" -ForegroundColor White
    $i=1; foreach ($h in @($s.Hallazgos)) { $hc = switch ([int]$h.Peso) { 3 {'Red'} 2 {'Yellow'} 1 {'DarkYellow'} default {'Gray'} }; Write-Host "  $i. $($h.Texto)" -ForegroundColor $hc; if ($h.Puente) { Write-Host "     -> $($h.Puente)" -ForegroundColor DarkCyan }; $i++ }
    if (@($s.Hallazgos).Count -eq 0) { Write-Host '  No se encontraron hallazgos que requieran atención.' -ForegroundColor Green }
    Write-Host "  Resumen: $($s.CompCount) comprobaciones · $($s.ElemCount) elementos · $($s.DuracionSeg)s" -ForegroundColor DarkGray
    Write-Host '  DeMente no llama problema a todo lo que encuentra. Primero intenta entender qué significa.' -ForegroundColor DarkGray
    return $true
}
# ========== FIN MOTOR SALUD ==========


function Get-DiagnosticoCompleto {
    param(
        [scriptblock]$OnProgress = $null
    )
    $inicio = Get-Date
    $diag = [PSCustomObject]@{
        CPUName=""; CPUCores=0; CPUFreqGHz=0; RAMTotalGB=0; RAMSlots=0; RAMSpeedMHz=0
        TieneSSD=$false; EsLaptop=$false; DiscoLibreGB=0; DiscoTotalGB=0; DiscoLibrePct=0; DiscoPocoEspacio=$false
        WinVersion=""; WinBuild=0; UptimeDias=0
        ProblemasGraves=@(); Advertencias=@(); Comprobaciones=@()
        Win32PrioOK=$true; NtfsLastAccessOK=$true; NetworkThrottling=$false
        VisualEffectsOptimized=$true; SystemResponsivenessOK=$true; TimerResOK=$true
        WSearchEstado="No comprobado"; WSearchProblema=$false; ErroresRecientes=0
        SaludScore=100; DiagnosticoCompleto=$false; DuracionSeg=0
        DiscosSalud=@()
        # Resumen por area (para el dashboard)
        Areas = [ordered]@{}
        ResumenAreas = @()
        MejorasDisponibles = 0
        StartupCount = 0
        DefenderOk = $true
        YaraEstado = 'No comprobado'
        TempCacheMB = 0
        CleanRapidMB = 0
        CleanDeepMB = 0
        CleanMgrMB = 0
        PerfApplied = 0
        PerfTotal = 0
        PerfDefault = 0
        RegFindings = 0
    }

    function Add-Check([string]$Area,[string]$Nombre,[string]$Estado,[string]$Detalle,[string]$Severidad='ok') {
        $diag.Comprobaciones += [pscustomobject]@{
            Area=$Area; Nombre=$Nombre; Estado=$Estado; Detalle=$Detalle; Severidad=$Severidad
        }
    }
    function Set-Area([string]$Key,[string]$Titulo,[string]$Estado,[string]$Detalle,[string]$Severidad='ok') {
        $diag.Areas[$Key] = [pscustomobject]@{
            Key=$Key; Titulo=$Titulo; Estado=$Estado; Detalle=$Detalle; Severidad=$Severidad
        }
    }
    function Progress([string]$msg,[int]$pct) {
        if ($OnProgress) { & $OnProgress $msg $pct }
        Write-Host "[i] $msg"
    }

    # ========== 1. HARDWARE / CPU / RAM ==========
    Progress 'Hardware: CPU, memoria y equipo...' 8
    try {
        $cpu = Get-CimInstance Win32_Processor -EA Stop | Select-Object -First 1
        if ($cpu) {
            $diag.CPUName = $cpu.Name.Trim()
            $diag.CPUCores = [int]$cpu.NumberOfCores
            $diag.CPUFreqGHz = [math]::Round($cpu.MaxClockSpeed/1000,1)
            Add-Check 'Hardware' 'Procesador' 'OK' "$($diag.CPUName) | $($diag.CPUCores) nucleos | $($diag.CPUFreqGHz) GHz" 'ok'
        } else {
            Add-Check 'Hardware' 'Procesador' 'NO DISPONIBLE' 'No se pudo consultar WMI.' 'warn'
        }
        $ram = Get-CimInstance Win32_PhysicalMemory -EA Stop
        if ($ram) {
            $diag.RAMTotalGB = [math]::Round(($ram|Measure-Object Capacity -Sum).Sum/1GB,1)
            $diag.RAMSlots = @($ram).Count
            $diag.RAMSpeedMHz = [int](($ram|Measure-Object Speed -Average).Average)
            $sev = if ($diag.RAMTotalGB -lt 4) { 'critical' } elseif ($diag.RAMTotalGB -lt 8) { 'warn' } else { 'ok' }
            $est = if ($sev -eq 'ok') { 'OK' } elseif ($sev -eq 'warn') { 'ATENCION' } else { 'CRITICO' }
            Add-Check 'Hardware' 'Memoria' $est "$($diag.RAMTotalGB) GB en $($diag.RAMSlots) modulo(s) | ~$($diag.RAMSpeedMHz) MHz" $sev
            if ($sev -eq 'critical') { $diag.ProblemasGraves += 'Poca memoria RAM' }
            elseif ($sev -eq 'warn') { $diag.Advertencias += 'RAM limitada (<8 GB)' }
        } else {
            Add-Check 'Hardware' 'Memoria' 'NO DISPONIBLE' 'No se pudo consultar WMI.' 'warn'
        }
        $bat = Get-CimInstance Win32_Battery -EA 0
        $diag.EsLaptop = [bool]$bat
        $cs = Get-CimInstance Win32_ComputerSystem -EA 0
        $hwDetail = "$(if($diag.EsLaptop){'Portatil'}else{'Escritorio'})"
        if ($cs) { $hwDetail += " | $($cs.Manufacturer) $($cs.Model)".Trim() }
        Set-Area 'hardware' 'Hardware' 'OK' "$($diag.CPUCores) nucleos | $($diag.RAMTotalGB) GB RAM | $hwDetail" 'ok'
    } catch {
        Set-Area 'hardware' 'Hardware' 'PARCIAL' 'Consulta WMI incompleta.' 'warn'
        Add-Check 'Hardware' 'Equipo' 'PARCIAL' "$_" 'warn'
    }

    # ========== 2. DISCO / ALMACENAMIENTO ==========
    Progress 'Almacenamiento: discos, espacio y tipo de medio...' 16
    try {
        $disks = Get-CimInstance Win32_DiskDrive -EA Stop
        if ($disks) {
            $diag.TieneSSD = (@($disks)|Where-Object{ $_.Model -match 'SSD|NVMe|M\.2|Solid' }).Count -gt 0
            Add-Check 'Almacenamiento' 'Tipo de medio' 'OK' $(if($diag.TieneSSD){'SSD/NVMe detectado'}else{'HDD u otro almacenamiento'}) 'ok'
        }
        $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -EA Stop
        if ($vol) {
            $diag.DiscoLibreGB = [math]::Round($vol.FreeSpace/1GB,1)
            $diag.DiscoTotalGB = [math]::Round($vol.Size/1GB,1)
            $diag.DiscoLibrePct = if ($vol.Size -gt 0) { [math]::Round($vol.FreeSpace/$vol.Size*100) } else { 0 }
            $diag.DiscoPocoEspacio = $diag.DiscoLibrePct -lt 10
            if ($diag.DiscoLibrePct -lt 10) {
                Add-Check 'Almacenamiento' 'Espacio en disco' 'CRITICO' "Solo $($diag.DiscoLibrePct)% libre ($($diag.DiscoLibreGB) GB de $($diag.DiscoTotalGB) GB)" 'critical'
                $diag.ProblemasGraves += 'Espacio en disco'
                Set-Area 'disco' 'Almacenamiento' 'CRITICO' "Sistema: $($diag.DiscoLibrePct)% libre" 'critical'
            } elseif ($diag.DiscoLibrePct -lt 20) {
                Add-Check 'Almacenamiento' 'Espacio en disco' 'ATENCION' "$($diag.DiscoLibrePct)% libre ($($diag.DiscoLibreGB) GB)" 'warn'
                $diag.Advertencias += 'Poco espacio en disco'
                Set-Area 'disco' 'Almacenamiento' 'ATENCION' "Sistema: $($diag.DiscoLibrePct)% libre" 'warn'
            } else {
                Add-Check 'Almacenamiento' 'Espacio en disco' 'OK' "$($diag.DiscoLibrePct)% libre ($($diag.DiscoLibreGB) GB de $($diag.DiscoTotalGB) GB)" 'ok'
                Set-Area 'disco' 'Almacenamiento' 'OK' "$(if($diag.TieneSSD){'SSD/NVMe'}else{'HDD'}) | $($diag.DiscoLibrePct)% libre" 'ok'
            }
        } else {
            Set-Area 'disco' 'Almacenamiento' 'NO DISPONIBLE' 'No se pudo leer el volumen del sistema.' 'warn'
        }
        # Salud basica de discos fisicos
        try {
            $pds = @(Get-PhysicalDisk -EA Stop)
            foreach ($pd in $pds) {
                $hs = [string]$pd.HealthStatus
                $sev = if ($hs -eq 'Unhealthy') { 'critical' } elseif ($hs -eq 'Warning') { 'warn' } else { 'ok' }
                Add-Check 'Almacenamiento' ("Disco: " + $pd.FriendlyName) $(if($sev -eq 'ok'){'OK'}elseif($sev -eq 'warn'){'ATENCION'}else{'RIESGO'}) "Salud Windows: $hs | $([math]::Round($pd.Size/1GB,0)) GB" $sev
                if ($sev -eq 'critical') { $diag.ProblemasGraves += "Disco $($pd.FriendlyName) no saludable" }
            }
        } catch { }
    } catch {
        Set-Area 'disco' 'Almacenamiento' 'PARCIAL' 'Consulta incompleta.' 'warn'
    }

    # ========== 3. WINDOWS / COMPONENTES ==========
    Progress 'Windows: version, uptime y componentes...' 24
    try {
        $wv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA Stop
        $diag.WinVersion = "$($wv.ProductName) $($wv.DisplayVersion)".Trim()
        $diag.WinBuild = [int]$wv.CurrentBuildNumber
        $os = Get-CimInstance Win32_OperatingSystem -EA Stop
        # TickCount64 = tiempo real de esta sesion de arranque (no lo engaña tanto el Inicio rapido).
        # LastBootUpTime de WMI a veces queda en el ultimo apagado "completo" y muestra dias de mas.
        $upTs = Get-WDMSessionUptime
        $diag.UptimeDias = [math]::Round($upTs.TotalDays, 2)
        $uptimeTxt = Format-WDMUptime $upTs
        Add-Check 'Windows' 'Sistema' 'OK' "$($diag.WinVersion) | Build $($diag.WinBuild)" 'ok'
        if ($diag.UptimeDias -ge 14) {
            Add-Check 'Windows' 'Tiempo encendido' 'ATENCION' $uptimeTxt 'warn'
            $diag.Advertencias += 'Muchos dias sin reiniciar'
        } elseif ($diag.UptimeDias -ge 7) {
            Add-Check 'Windows' 'Tiempo encendido' 'REVISAR' $uptimeTxt 'info'
        } else {
            Add-Check 'Windows' 'Tiempo encendido' 'OK' $uptimeTxt 'ok'
        }
        Set-Area 'windows' 'Windows' 'OK' "$($diag.WinVersion) | $uptimeTxt" 'ok'
    } catch {
        Set-Area 'windows' 'Windows' 'PARCIAL' 'No se pudo leer version/uptime.' 'warn'
    }

    # ========== 4. SERVICIOS ==========
    Progress 'Servicios: Search, Update, SysMain...' 32
    $svcIssues = 0
    try {
        $svc = Get-Service WSearch -EA Stop
        $diag.WSearchEstado = $svc.Status.ToString()
        if ($svc.StartType -eq 'Automatic' -and $svc.Status -ne 'Running') {
            $diag.WSearchProblema = $true
            $diag.ProblemasGraves += 'Windows Search no esta ejecutandose'
            Add-Check 'Servicios' 'Windows Search' 'ATENCION' "Inicio automatico, estado $($svc.Status)" 'critical'
            $svcIssues++
        } else {
            Add-Check 'Servicios' 'Windows Search' 'OK' "Estado: $($svc.Status) | Inicio: $($svc.StartType)" 'ok'
        }
    } catch {
        Add-Check 'Servicios' 'Windows Search' 'NO DISPONIBLE' 'No se pudo consultar.' 'warn'
    }
    foreach ($pair in @(@('wuauserv','Windows Update'),@('WinDefend','Microsoft Defender'),@('mpssvc','Firewall'))) {
        try {
            $s = Get-Service -Name $pair[0] -EA Stop
            if ($s.Status -ne 'Running' -and $s.StartType -eq 'Automatic') {
                Add-Check 'Servicios' $pair[1] 'ATENCION' "Deberia estar en ejecucion (estado: $($s.Status))" 'warn'
                $svcIssues++
                $diag.Advertencias += "$($pair[1]) detenido"
            } else {
                Add-Check 'Servicios' $pair[1] 'OK' "$($s.Status)" 'ok'
            }
        } catch {
            Add-Check 'Servicios' $pair[1] 'NO DISPONIBLE' 'Servicio no encontrado.' 'info'
        }
    }
    if ($svcIssues -gt 0) {
        Set-Area 'servicios' 'Servicios' 'ATENCION' "$svcIssues servicio(s) con anomalia" 'warn'
    } else {
        Set-Area 'servicios' 'Servicios' 'OK' 'Servicios criticos en estado esperado' 'ok'
    }

    # ========== 5. RED / TCP ==========
    Progress 'Red: adaptadores y conectividad basica...' 40
    try {
        $adapters = @(Get-NetAdapter -EA Stop | Where-Object Status -eq 'Up')
        if ($adapters.Count -eq 0) {
            Add-Check 'Red' 'Adaptadores' 'ATENCION' 'Ningun adaptador activo' 'warn'
            $diag.Advertencias += 'Sin adaptador de red activo'
            Set-Area 'red' 'Red' 'ATENCION' 'Sin adaptadores activos' 'warn'
        } else {
            $names = ($adapters | ForEach-Object { $_.Name }) -join ', '
            Add-Check 'Red' 'Adaptadores' 'OK' "$($adapters.Count) activo(s): $names" 'ok'
            Set-Area 'red' 'Red' 'OK' "$($adapters.Count) adaptador(es) activo(s)" 'ok'
        }
    } catch {
        Set-Area 'red' 'Red' 'PARCIAL' 'No se pudo enumerar adaptadores.' 'warn'
        Add-Check 'Red' 'Adaptadores' 'PARCIAL' 'Consulta incompleta.' 'warn'
    }

    # ========== 6. RENDIMIENTO (config vs propuesta) ==========
    Progress 'Rendimiento: prioridad, NTFS, red, efectos...' 48
    $mejorasPerf = 0
    try {
        $wps = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name Win32PrioritySeparation -EA Stop).Win32PrioritySeparation
        $ideal = if ($diag.CPUCores -le 2) { 18 } elseif ($diag.CPUCores -le 4) { 26 } else { 38 }
        $diag.Win32PrioOK = ($wps -eq $ideal)
        if (-not $diag.Win32PrioOK) {
            Add-Check 'Rendimiento' 'Prioridad CPU' 'MEJORA DISPONIBLE' "Actual: $wps | Propuesta DeMente: $ideal" 'info'
            $mejorasPerf++
        } else {
            Add-Check 'Rendimiento' 'Prioridad CPU' 'EN PROPUESTA' "Valor $wps" 'ok'
        }

        $ntfsRaw = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name NtfsDisableLastAccessUpdate -EA Stop).NtfsDisableLastAccessUpdate
        # Windows a veces guarda 0x80000002 (system managed). Nos quedamos con el byte bajo.
        $ntfsVal = 0
        try {
            $u = [uint64][uint32]$ntfsRaw
            $ntfsVal = [int]($u -band 0xFF)
        } catch {
            try { $ntfsVal = [int](Convert-RegDword $ntfsRaw) } catch { $ntfsVal = 0 }
        }
        # 1 o 3 = last-access desactivado (propuesta DeMente = 3). 2 = system managed (default).
        $diag.NtfsLastAccessOK = ($ntfsVal -eq 1 -or $ntfsVal -eq 3)
        $ntfsLabel = switch ($ntfsVal) {
            0 { '0 (actualiza last-access)' }
            1 { '1 (desactivado)' }
            2 { '2 (system managed)' }
            3 { '3 (desactivado, propuesta DeMente)' }
            default { "$ntfsVal" }
        }
        if (-not $diag.NtfsLastAccessOK) {
            Add-Check 'Rendimiento' 'NTFS Last Access' 'MEJORA DISPONIBLE' "Actual: $ntfsLabel | Propuesta: 3" 'info'
            $mejorasPerf++
        } else {
            Add-Check 'Rendimiento' 'NTFS Last Access' 'EN PROPUESTA' "Valor $ntfsLabel" 'ok'
        }

        $nt = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name NetworkThrottlingIndex -EA Stop).NetworkThrottlingIndex
        $ntOk = ($null -ne $nt -and ($nt -eq -1 -or $nt -eq 4294967295 -or [uint32]$nt -eq [uint32]::MaxValue))
        $diag.NetworkThrottling = -not $ntOk
        if ($diag.NetworkThrottling) {
            Add-Check 'Rendimiento' 'Limitación de red' 'MEJORA DISPONIBLE' 'Throttling multimedia activo' 'info'
            $mejorasPerf++
        } else {
            Add-Check 'Rendimiento' 'Limitación de red' 'EN PROPUESTA' 'Sin limite artificial' 'ok'
        }

        $vfx = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -EA 0).VisualFXSetting
        $diag.VisualEffectsOptimized = ($vfx -eq 2)
        if (-not $diag.VisualEffectsOptimized) {
            Add-Check 'Rendimiento' 'Efectos visuales' 'MEJORA DISPONIBLE' "Actual: $vfx | Propuesta: 2 (rendimiento)" 'info'
            $mejorasPerf++
        } else {
            Add-Check 'Rendimiento' 'Efectos visuales' 'OPTIMIZADO' "Valor $vfx" 'ok'
        }

        $tr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name SystemResponsiveness -EA Stop).SystemResponsiveness
        $idealResp = if ($diag.CPUCores -le 4) { 10 } else { 0 }
        $diag.SystemResponsivenessOK = ($tr -eq $idealResp)
        $diag.TimerResOK = $diag.SystemResponsivenessOK
        if (-not $diag.SystemResponsivenessOK) {
            Add-Check 'Rendimiento' 'Respuesta multimedia' 'MEJORA DISPONIBLE' "Actual: $tr | Propuesta: $idealResp" 'info'
            $mejorasPerf++
        } else {
            Add-Check 'Rendimiento' 'Respuesta multimedia' 'EN PROPUESTA' "Valor $tr" 'ok'
        }
    } catch {
        Add-Check 'Rendimiento' 'Configuracion' 'PARCIAL' 'No se pudieron leer todas las claves.' 'warn'
    }
    $diag.MejorasDisponibles += $mejorasPerf
    if ($mejorasPerf -gt 0) {
        Set-Area 'rendimiento' 'Rendimiento' 'MEJORAS' "$mejorasPerf ajuste(s) opcionales disponibles" 'info'
    } else {
        Set-Area 'rendimiento' 'Rendimiento' 'OK' 'Valores alineados con la propuesta DeMente' 'ok'
    }

    # ========== 7. INICIO (startup) ==========
    Progress 'Inicio: programas al arrancar...' 56
    try {
        $runKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        )
        $startup = @()
        foreach ($rk in $runKeys) {
            if (Test-Path $rk) {
                $props = Get-ItemProperty $rk -EA 0
                if ($props) {
                    $props.PSObject.Properties | Where-Object {
                        $_.Name -notmatch '^PS' -and $null -ne $_.Value -and "$_.Value" -ne ''
                    } | ForEach-Object { $startup += $_.Name }
                }
            }
        }
        $diag.StartupCount = $startup.Count
        if ($startup.Count -ge 12) {
            Add-Check 'Inicio' 'Programas al arrancar' 'ATENCION' "$($startup.Count) entradas en Run (HKLM/HKCU)" 'warn'
            $diag.Advertencias += 'Muchos programas de inicio'
            Set-Area 'inicio' 'Inicio' 'ATENCION' "$($startup.Count) programas en Run" 'warn'
        } elseif ($startup.Count -ge 8) {
            Add-Check 'Inicio' 'Programas al arrancar' 'REVISAR' "$($startup.Count) entradas en Run" 'info'
            Set-Area 'inicio' 'Inicio' 'REVISAR' "$($startup.Count) programas en Run" 'info'
        } else {
            Add-Check 'Inicio' 'Programas al arrancar' 'OK' "$($startup.Count) entradas en Run" 'ok'
            Set-Area 'inicio' 'Inicio' 'OK' "$($startup.Count) programas en Run" 'ok'
        }
    } catch {
        Set-Area 'inicio' 'Inicio' 'PARCIAL' 'No se pudo enumerar Run.' 'warn'
    }

    # ========== 8. PRIVACIDAD (muestra) ==========
    Progress 'Privacidad: telemetria, ads, sensores...' 64
    $privPend = 0
    try {
        $items = @(Get-WDMPrivacyState)
        if ($items) {
            foreach ($p in $items) {
                if (-not $p.Aplicado) {
                    $privPend++
                    Add-Check 'Privacidad' $p.Nombre 'MEJORA DISPONIBLE' 'Aun en valor DEFAULT de Windows / no endurecido' 'info'
                } else {
                    Add-Check 'Privacidad' $p.Nombre 'APLICADO' 'Ajuste de privacidad activo' 'ok'
                }
            }
        }
    } catch {
        Add-Check 'Privacidad' 'Estado' 'PARCIAL' 'No se pudo leer el estado de privacidad.' 'warn'
    }
    $diag.MejorasDisponibles += $privPend
    if ($privPend -gt 0) {
        Set-Area 'privacidad' 'Privacidad' 'MEJORAS' "$privPend opcion(es) aun en DEFAULT" 'info'
    } else {
        Set-Area 'privacidad' 'Privacidad' 'OK' 'Ajustes de privacidad alineados' 'ok'
    }

    # ========== 9. SEGURIDAD / DEFENDER ==========
    Progress 'Seguridad: Defender y proteccion...' 72
    try {
        $def = Get-MpComputerStatus -EA Stop
        $diag.DefenderOk = [bool]$def.RealTimeProtectionEnabled
        if (-not $def.RealTimeProtectionEnabled) {
            Add-Check 'Seguridad' 'Proteccion en tiempo real' 'ATENCION' 'Desactivada' 'critical'
            $diag.ProblemasGraves += 'Defender sin proteccion en tiempo real'
            Set-Area 'seguridad' 'Seguridad' 'ATENCION' 'Proteccion en tiempo real OFF' 'critical'
        } elseif ($def.AntivirusSignatureAge -gt 7) {
            Add-Check 'Seguridad' 'Firmas antivirus' 'ATENCION' "Firmas con $($def.AntivirusSignatureAge) dias de antigüedad" 'warn'
            $diag.Advertencias += 'Firmas de Defender desactualizadas'
            Set-Area 'seguridad' 'Seguridad' 'ATENCION' "Firmas: $($def.AntivirusSignatureAge)d" 'warn'
        } else {
            Add-Check 'Seguridad' 'Microsoft Defender' 'OK' "Tiempo real ON | Firmas: $($def.AntivirusSignatureAge)d | Ultimo scan: $($def.QuickScanAge)d" 'ok'
            Set-Area 'seguridad' 'Seguridad' 'OK' 'Defender activo y firmas recientes' 'ok'
        }
    } catch {
        Add-Check 'Seguridad' 'Microsoft Defender' 'NO COMPROBADO' 'Get-MpComputerStatus no disponible (permisos o edicion).' 'info'
        Set-Area 'seguridad' 'Seguridad' 'PARCIAL' 'No se pudo consultar Defender' 'info'
    }

    # ========== 10. YARA ==========
    Progress 'YARA: motor y reglas...' 78
    try {
        $yaraExe = $null
        if (Get-Command Get-WDMYaraExe -EA 0) { $yaraExe = Get-WDMYaraExe }
        if (-not $yaraExe) {
            $cand = Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara\bin\yara64.exe'
            if (Test-Path $cand) { $yaraExe = $cand }
        }
        $rulesDir = Join-Path $env:USERPROFILE 'Documents\DeMente\security\yara\rules'
        $nRules = 0
        if (Test-Path $rulesDir) { $nRules = @(Get-ChildItem $rulesDir -Filter *.yar* -EA 0).Count }
        if ($yaraExe -and (Test-Path $yaraExe)) {
            $diag.YaraEstado = "Instalado | $nRules regla(s)"
            Add-Check 'YARA' 'Motor' 'OK' $diag.YaraEstado 'ok'
            Set-Area 'yara' 'YARA' 'OK' $diag.YaraEstado 'ok'
        } else {
            $diag.YaraEstado = 'No instalado'
            Add-Check 'YARA' 'Motor' 'NO INSTALADO' 'Usa Actualizar YARA en Seguridad si queres el motor.' 'info'
            Set-Area 'yara' 'YARA' 'OPCIONAL' 'Motor no instalado' 'info'
        }
    } catch {
        Set-Area 'yara' 'YARA' 'OPCIONAL' 'No se pudo comprobar (no es un fallo del PC).' 'info'
    }

    # ========== 11. LIMPIEZA / CACHES (estimacion recuperable) ==========
    Progress 'Limpieza: estimacion de temporales y caches...' 86
    try {
        $bytes = [double]0
        # Temporales de usuario y sistema (solo archivos de primer nivel + un nivel; evita recorrer todo el arbol)
        foreach ($p in @("$env:TEMP","$env:SystemRoot\Temp","$env:LOCALAPPDATA\Temp")) {
            if (Test-Path $p) {
                try {
                    $bytes += [double]((Get-ChildItem $p -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
                    Get-ChildItem $p -Force -Directory -EA SilentlyContinue | Select-Object -First 40 | ForEach-Object {
                        try { $bytes += [double]((Get-ChildItem $_.FullName -Force -File -Recurse -EA SilentlyContinue | Measure-Object Length -Sum).Sum) } catch { }
                    }
                } catch { }
            }
        }
        # Prefetch
        if (Test-Path "$env:SystemRoot\Prefetch") {
            try { $bytes += [double]((Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum) } catch { }
        }
        # Caches de navegadores (solo carpetas Cache conocidas, sin perfiles completos)
        $browserCaches = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
            "$env:APPDATA\Mozilla\Firefox\Profiles"
        )
        foreach ($bc in $browserCaches) {
            if (Test-Path $bc) {
                try {
                    if ($bc -match 'Firefox') {
                        Get-ChildItem $bc -Directory -EA SilentlyContinue | ForEach-Object {
                            $c2 = Join-Path $_.FullName 'cache2'
                            if (Test-Path $c2) {
                                $bytes += [double]((Get-ChildItem $c2 -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
                            }
                        }
                    } else {
                        $bytes += [double]((Get-ChildItem $bc -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
                    }
                } catch { }
            }
        }
        # Papelera: misma fuente que hints y Clear-RecycleBin
        try {
            $rbBytes = [double](Get-RecycleBinBytes)
            if ($rbBytes -gt 0) { $bytes += $rbBytes }
        } catch { }

        $diag.TempCacheMB = [math]::Round($bytes / 1MB, 1)
        $gbTxt = if ($diag.TempCacheMB -ge 1024) { "{0:N1} GB" -f ($diag.TempCacheMB/1024) } else { "{0:N0} MB" -f $diag.TempCacheMB }
        if ($diag.TempCacheMB -gt 2048) {
            Add-Check 'Limpieza' 'Recuperable estimado' 'ATENCION' "Aprox. $gbTxt (temp + caches + papelera)" 'warn'
            $diag.Advertencias += 'Muchos archivos temporales/caches'
            Set-Area 'limpieza' 'Limpieza' 'ATENCION' "~$gbTxt recuperables" 'warn'
        } elseif ($diag.TempCacheMB -gt 200) {
            Add-Check 'Limpieza' 'Recuperable estimado' 'REVISAR' "Aprox. $gbTxt (temp + caches + papelera)" 'info'
            Set-Area 'limpieza' 'Limpieza' 'REVISAR' "~$gbTxt recuperables" 'info'
        } else {
            Add-Check 'Limpieza' 'Recuperable estimado' 'OK' "Aprox. $gbTxt" 'ok'
            Set-Area 'limpieza' 'Limpieza' 'OK' "~$gbTxt recuperables" 'ok'
        }

        # Capas de limpieza para el dashboard (rapido / profundo / cleanmgr)
        $diag.CleanRapidMB = [math]::Round($diag.TempCacheMB, 1)
        $deepExtra = [double]0
        foreach ($p in @(
            "$env:LOCALAPPDATA\D3DSCache",
                    "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
                "$env:SystemRoot\Logs",
            "$env:SystemRoot\SoftwareDistribution\Download",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Discord\Cache",
            "$env:APPDATA\discord\Cache",
            "$env:APPDATA\discord\Code Cache",
            "$env:APPDATA\discord\GPUCache",
                    "$env:APPDATA\Code\Cache",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\GPUCache",
            "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:ProgramData\Microsoft\Windows\WER"
        )) {
            if (Test-Path $p) {
                try {
                    $deepExtra += [double]((Get-ChildItem $p -Recurse -Force -File -EA SilentlyContinue | Select-Object -First 8000 | Measure-Object Length -Sum).Sum)
                } catch { }
            }
        }
        $diag.CleanDeepMB = [math]::Round(($diag.TempCacheMB + ($deepExtra / 1MB)), 1)
        # cleanmgr tipico: temp + WU + Delivery + thumbnails + residual aproximado
        $cm = [double]$diag.TempCacheMB
        foreach ($p in @(
            "$env:SystemRoot\SoftwareDistribution\Download",
            "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization",
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        )) {
            if (Test-Path $p) {
                try { $cm += [double]((Get-ChildItem $p -Recurse -Force -File -EA SilentlyContinue | Select-Object -First 4000 | Measure-Object Length -Sum).Sum) / 1MB } catch { }
            }
        }
        # Windows.old si existe suma mucho
        if (Test-Path 'C:\Windows.old') {
            try {
                $wo = Get-ChildItem 'C:\Windows.old' -Force -EA SilentlyContinue | Measure-Object Length -Sum -EA SilentlyContinue
                # no recursivo profundo: estimar por directorio de primer nivel
                $woBytes = [double]0
                Get-ChildItem 'C:\Windows.old' -Force -EA SilentlyContinue | Select-Object -First 30 | ForEach-Object {
                    try {
                        if ($_.PSIsContainer) {
                            $woBytes += [double]((Get-ChildItem $_.FullName -Recurse -Force -File -EA SilentlyContinue | Select-Object -First 2000 | Measure-Object Length -Sum).Sum)
                        } else { $woBytes += [double]$_.Length }
                    } catch { }
                }
                $cm += $woBytes / 1MB
            } catch { }
        }
        $diag.CleanMgrMB = [math]::Round([math]::Max($cm, $diag.CleanDeepMB * 0.7), 1)
    } catch {
        Set-Area 'limpieza' 'Limpieza' 'PARCIAL' 'Estimacion incompleta.' 'warn'
    }

    # ========== 12. EVENTOS / ESTABILIDAD ==========
    Progress 'Estabilidad: eventos criticos recientes...' 92
    try {
        $desde = (Get-Date).AddHours(-48)
        # Timeout: Get-WinEvent a veces se cuelga minutos y deja el panel en "Preparando..."
        $ev = @()
        $job = Start-Job -ScriptBlock {
            param($d)
            @(Get-WinEvent -FilterHashtable @{LogName='System';Level=1;StartTime=$d} -MaxEvents 30 -EA 0)
        } -ArgumentList $desde
        if (Wait-Job $job -Timeout 8) {
            $ev = @(Receive-Job $job -EA 0)
        } else {
            Stop-Job $job -EA 0
            Write-Host '[!] Lectura de eventos criticos: timeout (8s), se omite'
        }
        Remove-Job $job -Force -EA 0
        $diag.ErroresRecientes = $ev.Count
        if ($ev.Count -gt 5) {
            Add-Check 'Estabilidad' 'Eventos criticos' 'ATENCION' "$($ev.Count) eventos Level=1 en 48h" 'warn'
            $diag.Advertencias += "$($ev.Count) eventos criticos recientes"
            Set-Area 'estabilidad' 'Estabilidad' 'ATENCION' "$($ev.Count) eventos criticos (48h)" 'warn'
        } elseif ($ev.Count -gt 0) {
            Add-Check 'Estabilidad' 'Eventos criticos' 'REVISAR' "$($ev.Count) eventos Level=1 en 48h" 'info'
            Set-Area 'estabilidad' 'Estabilidad' 'REVISAR' "$($ev.Count) eventos (48h)" 'info'
        } else {
            Add-Check 'Estabilidad' 'Eventos criticos' 'OK' 'Sin eventos criticos recientes en System' 'ok'
            Set-Area 'estabilidad' 'Estabilidad' 'OK' 'Sin eventos criticos recientes' 'ok'
        }
    } catch {
        Set-Area 'estabilidad' 'Estabilidad' 'NO COMPROBADO' 'No se pudo leer el registro de eventos.' 'warn'
        Add-Check 'Estabilidad' 'Eventos criticos' 'NO COMPROBADO' 'Acceso al log denegado o no disponible.' 'warn'
    }

    # ========== 12b. CONTEO DE TWEAKS / REGISTRO ==========
    Progress 'Conteo de optimizaciones y registro...' 94
    try {
        $perfIds = @(
            'perf-priority','perf-paging','perf-menu','perf-power','perf-ultimate','perf-faststartup',
            'perf-storage-sense','perf-classic-menu','perf-visual','perf-network-throttle','perf-systemresp',
            'perf-prefetcher','perf-ntfs','perf-explorer','perf-superfetch','perf-indexacion','perf-hibernacion',
            'perf-ipv6','perf-qos','perf-nagle','perf-shutdown','perf-mmcss','perf-fullscreen-opt',
            'perf-mouse-accel','perf-disable-sticky','perf-xbox-services','perf-sysmain-hint',
            'perf-startup-safe','perf-startup-delay'
        )
        $diag.PerfTotal = $perfIds.Count
        # Conteo ligero sin depender de Get-WDMAppliedState (puede no existir aun en CLI)
        $applied = 0
        $checkable = 0
        try {
            $wps = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
            $idealWps = if ($diag.CPUCores -le 2) { 18 } elseif ($diag.CPUCores -le 4) { 26 } else { 38 }
            if ($null -ne $wps) { $checkable++; if (Test-RegDwordEq $wps $idealWps) { $applied++ } }
        } catch { }
        try {
            $ntfs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
            if ($null -ne $ntfs) { $checkable++; if (Test-NtfsOptimized $ntfs) { $applied++ } }
        } catch { }
        try {
            $nt = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
            if ($null -ne $nt) { $checkable++; if (Test-RegDwordEq $nt -1) { $applied++ } }
        } catch { }
        try {
            $vfx = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
            if ($null -ne $vfx) { $checkable++; if (Test-RegDwordEq $vfx 2) { $applied++ } }
        } catch { }
        try {
            $sr = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
            $idealSr = if ($diag.CPUCores -le 4) { 10 } else { 0 }
            if ($null -ne $sr) { $checkable++; if (Test-RegDwordEq $sr $idealSr) { $applied++ } }
        } catch { }
        try {
            $menu = Get-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
            if ($null -ne $menu) { $checkable++; if (Test-RegDwordEq $menu 0) { $applied++ } }
        } catch { }
        try {
            $expl = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'SeparateProcess'
            if ($null -ne $expl) { $checkable++; if (Test-RegDwordEq $expl 1) { $applied++ } }
        } catch { }
        try {
            $qos = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'NonBestEffortLimit'
            if ($null -ne $qos) { $checkable++; if (Test-RegDwordEq $qos 0) { $applied++ } }
        } catch { }
        try {
            $paging = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive'
            if ($null -ne $paging) { $checkable++; if (Test-RegDwordEq $paging 1) { $applied++ } }
        } catch { }
        try {
            $pref = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher'
            if ($null -ne $pref) {
                $checkable++
                $idealPref = Get-IdealPrefetcher -SSD ([bool]$diag.TieneSSD)
                if (Test-RegDwordEq $pref $idealPref) { $applied++ }
            }
        } catch { }
        # Proyectar proporcion al total de tweaks de catalogo
        if ($checkable -gt 0) {
            $ratio = $applied / [double]$checkable
            $diag.PerfApplied = [int][math]::Round($ratio * $diag.PerfTotal)
        } else {
            $diag.PerfApplied = $applied
        }
        $diag.PerfDefault = [math]::Max(0, $diag.PerfTotal - $diag.PerfApplied)
        Add-Check 'Rendimiento' 'Tweaks DeMente' 'INFO' ("{0} de {1} aplicados | {2} en DEFAULT Windows" -f $diag.PerfApplied, $diag.PerfTotal, $diag.PerfDefault) 'info'
    } catch { }

    try {
        $rf = @(Get-WDMRegAudit)
        $diag.RegFindings = $rf.Count
        if ($rf.Count -gt 0) {
            Add-Check 'Registro' 'Residuos verificables' 'REVISAR' "$($rf.Count) hallazgo(s) en zonas seguras" 'info'
        } else {
            Add-Check 'Registro' 'Residuos verificables' 'OK' 'Sin residuos evidentes en zonas seguras' 'ok'
        }
    } catch { }

    # ========== CIERRE ==========
    Progress 'Armando resumen por areas...' 96
    $diag.ResumenAreas = @($diag.Areas.Values)
    # SaludScore se mantiene solo como interno legado; el UI NO lo muestra como nota.
    $score = 100 - ([math]::Min(40, $diag.ProblemasGraves.Count * 20)) - ([math]::Min(25, $diag.Advertencias.Count * 5))
    $diag.SaludScore = [math]::Max(0, [math]::Min(100, $score))
    $diag.DiagnosticoCompleto = $true
    $diag.DuracionSeg = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)

    $nCrit = @($diag.Comprobaciones | Where-Object Severidad -eq 'critical').Count
    $nWarn = @($diag.Comprobaciones | Where-Object Severidad -eq 'warn').Count
    $nInfo = @($diag.Comprobaciones | Where-Object { $_.Severidad -eq 'info' -and $_.Estado -eq 'MEJORA DISPONIBLE' }).Count
    Write-Host "[OK] Multiescaneo completado: $($diag.Comprobaciones.Count) comprobaciones en $($diag.Areas.Count) areas | $nCrit problema(s) | $nWarn advertencia(s) | $nInfo mejora(s) | $($diag.DuracionSeg)s"
    return $diag
}


# -- CAUSAS DE LENTITUD (diagnostico explicativo, no un puntaje) --------------
# DeMente no inventa un "95/100". Esto cruza lo que realmente encontro el
# diagnostico y lo clasifica en 4 niveles, con una sugerencia concreta cuando
# corresponde. No es otro optimizador: es la explicacion de "por que".
function Get-CausasLentitud {
    param($Diag)
    if (-not $Diag) { $Diag = Get-DiagnosticoCompleto }

    $sugerencias = @{
        'Espacio en disco'      = 'Seccion Limpieza: temporales, caches, Papelera.'
        'Salud del disco'       = 'Respalda datos importantes y planifica reemplazo del disco.'
        'Windows Search'        = 'Revisa el servicio WSearch o reconstruye el indice.'
        'Eventos criticos'      = 'Visor de eventos (System) o seccion Reparacion.'
        'Prioridad CPU'         = 'Seccion Rendimiento: Prioridad del procesador.'
        'NTFS Last Access'      = 'Seccion Rendimiento: Ultimo acceso de NTFS (propuesta 3).'
        'Limitacion de red'     = 'Opcional si usas audio/video en tiempo real.'
        'Limitación de red'     = 'Opcional si usas audio/video en tiempo real.'
        'Efectos visuales'      = 'Seccion Rendimiento: modo rendimiento.'
        'Respuesta multimedia'  = 'Seccion Rendimiento: SystemResponsiveness.'
        'Memoria'               = 'Ampliar RAM si es posible; cierra programas innecesarios.'
        'Tiempo sin reiniciar'  = 'Reinicia el equipo para liberar memoria y procesos.'
        'Programas al arrancar' = 'Administrador de tareas > Inicio.'
        'Recuperable estimado'  = 'Seccion Limpieza.'
    }
    $causas = New-Object System.Collections.Generic.List[object]
    function Add-Causa($Nivel, $Nombre, $Detalle) {
        $sug = $null
        foreach ($k in $sugerencias.Keys) {
            if ($Nombre -like "*$k*" -or $k -like "*$Nombre*") { $sug = $sugerencias[$k]; break }
        }
        $causas.Add([pscustomobject]@{ Nivel=$Nivel; Nombre=$Nombre; Detalle=$Detalle; Sugerencia=$sug })
    }

    # Solo lo que NO esta OK: no listamos "Descartado" (ensucia el informe)
    foreach ($c in $Diag.Comprobaciones) {
        switch ($c.Severidad) {
            'critical' { Add-Causa 'Causa probable' $c.Nombre $c.Detalle }
            'warn'     { Add-Causa 'Factor contribuyente' $c.Nombre $c.Detalle }
            'info'     {
                if ($c.Estado -eq 'MEJORA DISPONIBLE' -or $c.Estado -eq 'REVISAR' -or $c.Estado -eq 'ATENCION') {
                    Add-Causa 'Condicion a revisar' $c.Nombre $c.Detalle
                }
            }
        }
    }
    if ($Diag.UptimeDias -ge 7) {
        Add-Causa 'Factor contribuyente' 'Tiempo sin reiniciar' (Format-WDMUptime ([TimeSpan]::FromDays([double]$Diag.UptimeDias)))
    } elseif ($Diag.UptimeDias -ge 3) {
        Add-Causa 'Condicion a revisar' 'Tiempo sin reiniciar' (Format-WDMUptime ([TimeSpan]::FromDays([double]$Diag.UptimeDias)))
    }
    if ($Diag.RAMTotalGB -gt 0 -and $Diag.RAMTotalGB -lt 4) {
        Add-Causa 'Causa probable' 'Memoria' "$($Diag.RAMTotalGB) GB (muy poca para Windows actual)"
    } elseif ($Diag.RAMTotalGB -ge 4 -and $Diag.RAMTotalGB -lt 8) {
        # Ya puede venir como warn en Comprobaciones; evitar duplicar si ya esta
        $ya = @($causas | Where-Object { $_.Nombre -match 'Memoria' }).Count
        if ($ya -eq 0) { Add-Causa 'Factor contribuyente' 'Memoria' "$($Diag.RAMTotalGB) GB (limitada para multitarea)" }
    }

    return @($causas)
}

function Show-CausasLentitud {
    param($Diag)
    HR 'POR QUE ESTA LENTA MI PC?'
    Write-Host 'DeMente cruza el diagnostico: causas reales, no un puntaje generico.'
    $causas = @(Get-CausasLentitud -Diag $Diag)
    $orden = @{ 'Causa probable'=0; 'Factor contribuyente'=1; 'Condicion a revisar'=2 }
    $grupos = @($causas | Group-Object Nivel | Sort-Object { $orden[$_.Name] })
    if ($grupos.Count -eq 0) {
        OK 'No se detectaron causas de lentitud relevantes.'
        return
    }
    foreach ($g in $grupos) {
        Write-Host ''
        HR ("$($g.Name.ToUpper()) ($($g.Count))")
        foreach ($item in $g.Group) {
            ROW $item.Nombre $item.Detalle
            if ($item.Sugerencia) { ROW '  Sugerencia' $item.Sugerencia }
        }
    }
    Write-Host ''
    $probables = @($causas | Where-Object { $_.Nivel -eq 'Causa probable' }).Count
    $contrib   = @($causas | Where-Object { $_.Nivel -eq 'Factor contribuyente' }).Count
    $cond      = @($causas | Where-Object { $_.Nivel -eq 'Condicion a revisar' }).Count
    if ($probables -gt 0) { ERR "$probables causa(s) probable(s). Atendelas primero." }
    elseif ($contrib -gt 0) { WARN "$contrib factor(es) contribuyente(s). Explican parte de la lentitud." }
    elseif ($cond -gt 0) { INFO "$cond condicion(es) a revisar (ajustes opcionales o habitos)." }
    else { OK 'Sin causas de lentitud relevantes.' }
}

# -- CATALOGO DE HERRAMIENTAS --------------------------------------------------
function T {
    param([string]$Id, [string]$Name, [string]$Desc, [string]$Icon, [string]$Cat,
          [string]$Risk='safe', [string]$Run='inline', [string]$Code, [string]$Revert, [string]$Sub='')
    [pscustomobject]@{ Id=$Id; Name=$Name; Desc=$Desc; Icon=$Icon; Cat=$Cat; Risk=$Risk; Run=$Run; Code=$Code; Revert=$Revert; Sub=$Sub }
}

$Global:Catalog = @()

# -- OPTIMIZACIONES (PERF) -----------------------------------------------------
$Global:Catalog += (T -Id 'perf-priority' -Name 'Prioridad del procesador' -Desc 'DEFAULT Windows: segun edicion | DeMente: valor ideal por nucleos (18/26/38). Mejora el balance primer plano/fondo.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Win32PrioritySeparation' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 2')
$Global:Catalog += (T -Id 'perf-paging' -Name 'Mantener el núcleo en RAM' -Desc 'Windows a veces manda partes del núcleo del sistema al disco para ahorrar RAM, aunque sobre memoria. Con 8 GB o más, DeMente lo mantiene todo en RAM: el sistema responde un poco más rápido y no hay downside real con esa cantidad de memoria.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-DisablePagingExecutive' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 0')
$Global:Catalog += (T -Id 'perf-menu' -Name 'Menús más rápidos' -Desc 'DEFAULT: ~400 ms | DeMente: 0. Menus del sistema sin retardo.' -Icon 'E790' -Cat 'perf' -Code 'Optimize-MenuShowDelay' -Revert 'Set-ItemProperty "HKCU:\Control Panel\Desktop" "MenuShowDelay" "400"')
$Global:Catalog += (T -Id 'perf-power' -Name 'Plan de energía' -Desc 'DEFAULT Windows: Equilibrado. DeMente: Alto rendimiento en escritorio (en portátil deja Equilibrado). Más velocidad, más consumo.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-PowerPlan' -Revert 'powercfg /setactive SCHEME_BALANCED')
$Global:Catalog += (T -Id 'perf-ultimate' -Name 'Rendimiento máximo (Ultimate)' -Desc 'DEFAULT Windows: oculto. DeMente: activa el plan Ultimate Performance. Ideal en PC de escritorio; en portátil gasta más batería.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-UltimatePerformance' -Revert 'powercfg /setactive SCHEME_BALANCED')
$Global:Catalog += (T -Id 'perf-faststartup' -Name 'Inicio rápido' -Desc 'DEFAULT: activado | DeMente: desactivado. Apagado completo y updates mas predecibles.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-FastStartup' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1')
$Global:Catalog += (T -Id 'perf-storage-sense' -Name 'Storage Sense' -Desc 'DEFAULT: a menudo desactivado | DeMente: activado. Windows limpia basura cuando conviene.' -Icon 'E74D' -Cat 'perf' -Code 'Optimize-StorageSense' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01" 0')
$Global:Catalog += (T -Id 'perf-classic-menu' -Name 'Menú contextual clásico' -Desc 'DEFAULT Windows 11: menú nuevo. DeMente: menú clásico (estilo Windows 10). Más directo; requiere reiniciar Explorador.' -Icon 'E8A5' -Cat 'perf' -Code 'Optimize-ClassicContextMenu' -Revert 'Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -EA 0')
$Global:Catalog += (T -Id 'perf-visual' -Name 'Efectos visuales' -Desc 'DEFAULT: dejar que Windows decida | DeMente: priorizar rendimiento (menos animaciones).' -Icon 'E790' -Cat 'perf' -Code 'Optimize-VisualEffects' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 0')
$Global:Catalog += (T -Id 'perf-network-throttle' -Name 'Limitación de red' -Desc 'DEFAULT: 10 | DeMente: sin limite (-1). Util con audio/video en tiempo real.' -Icon 'E839' -Cat 'perf' -Code 'Optimize-NetworkThrottling' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 10')
$Global:Catalog += (T -Id 'perf-timer' -Name 'Resolución del temporizador' -Desc 'Windows administra este valor dinámicamente | DeMente no fuerza un valor permanente | Evita una falsa optimización del temporizador.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-TimerResolution')
$Global:Catalog += (T -Id 'perf-systemresp' -Name 'Respuesta multimedia' -Desc 'DEFAULT: 20 | DeMente: 10 o 0 segun CPU. Reserva menos CPU a tareas multimedia de fondo.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-SystemResponsiveness' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 20')
$Global:Catalog += (T -Id 'perf-prefetcher' -Name 'Prefetcher de Windows' -Desc 'DEFAULT: 3 | DeMente: 2 en SSD, 3 en HDD. Ajuste segun tipo de disco.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Prefetcher' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 3')
$Global:Catalog += (T -Id 'perf-ntfs' -Name 'Último acceso de NTFS' -Desc 'DEFAULT: LastAccess system-managed (2) | DeMente: 3. Menos escrituras de marca de acceso en disco.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-NtfsLastAccess' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisableLastAccessUpdate" 0')
$Global:Catalog += (T -Id 'perf-explorer' -Name 'Explorador en proceso separado' -Desc 'El Explorador de archivos corre pegado a otras tareas de Windows. Separarlo en su propio proceso hace que si el Explorador se cuelga (por ejemplo abriendo una carpeta con muchos archivos), no arrastre al resto del escritorio con él.' -Icon 'E8B7' -Cat 'perf' -Code 'Optimize-ExplorerSeparateProcess' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "SeparateProcess" 0')
$Global:Catalog += (T -Id 'perf-superfetch' -Name 'Superfetch (SysMain)' -Desc 'SysMain aprende qué programas abrís seguido y los precarga en RAM para que abran más rápido. En un disco SSD casi no suma (son igual de rápidos ya) y consume recursos de fondo; en un disco mecánico sí ayuda. DeMente lo decide según qué disco tenés.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Superfetch' -Revert 'Set-Service SysMain -StartupType Automatic -EA 0; Start-Service SysMain -EA 0')
$Global:Catalog += (T -Id 'perf-indexacion' -Name 'Indexación de Windows Search' -Desc 'Windows Search mantiene un índice de tus archivos para que las búsquedas sean instantáneas, pero eso implica actividad constante de disco. En un disco mecánico (HDD) ese costo se nota; DeMente lo puede desactivar ahí. Buscar archivos será un poco más lento, pero el disco sufre menos.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Indexacion' -Revert 'Set-Service WSearch -StartupType Automatic -EA 0; Start-Service WSearch -EA 0')
$Global:Catalog += (T -Id 'perf-hibernacion' -Name 'Hibernación' -Desc 'Hibernar guarda todo lo que tenías abierto en un archivo del disco (hiberfil.sys) del tamaño de tu RAM, para poder apagar sin cerrar nada. Si nunca usás ''Hibernar'' (solo Suspender o Apagar), ese archivo es espacio de disco tirado. DeMente lo libera.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Hibernación' -Revert 'powercfg /hibernate on')
$Global:Catalog += (T -Id 'perf-ipv6' -Name 'IPv6' -Desc 'IPv6 es la versión nueva del protocolo de internet. Casi ningún router hogareño ni sitio lo necesita todavía, y a veces genera demoras raras al conectar. Desactivarlo no te deja sin internet: seguís usando IPv4, que es lo que usa casi todo hoy.' -Icon 'E839' -Cat 'perf' -Code 'Optimize-IPv6' -Revert 'Get-NetAdapterBinding -ComponentID ms_tcpip6 -EA 0 | Enable-NetAdapterBinding -ComponentID ms_tcpip6 -EA 0')
$Global:Catalog += (T -Id 'perf-qos' -Name 'Reserva de ancho de banda (QoS)' -Desc 'Windows reserva de entrada un 20% del ancho de banda de tu red ''por si'' algún programa lo pide con prioridad (QoS), algo que casi ninguna app hogareña usa. Esa reserva no se usa en la práctica en la mayoría de las casas, así que liberarla te devuelve ese 20% para todo lo demás.' -Icon 'E839' -Cat 'perf' -Code 'Optimize-QoSReservado' -Revert 'Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" -EA 0')
$Global:Catalog += (T -Id 'perf-nagle' -Name 'Algoritmo de Nagle' -Desc 'El algoritmo de Nagle agrupa paquetes chicos de red para mandarlos juntos, lo que ahorra tráfico pero agrega una demora mínima. Para juegos online o escritorio remoto, esa demora se nota; para uso general no cambia casi nada. Solo tiene sentido tocarlo si jugás online.' -Icon 'E839' -Cat 'perf' -Code 'Optimize-NagleAlgoritmo' -Revert 'Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -EA 0 | ForEach-Object { Remove-ItemProperty $_.PSPath -Name TcpAckFrequency -EA 0; Remove-ItemProperty $_.PSPath -Name TCPNoDelay -EA 0 }')
$Global:Catalog += (T -Id 'perf-shutdown' -Name 'Apagado más rápido' -Desc 'Windows espera unos segundos a que cada programa cierre solo antes de forzar el apagado, por si tenías algo sin guardar. Reducir esa espera hace que apagar sea más rápido, a costa de menos margen para que un programa trabado cierre bien solo.' -Icon 'E945' -Cat 'perf' -Code 'Optimize-ApagadoRapido' -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "5000"; Set-ItemProperty "HKCU:\Control Panel\Desktop" "WaitToKillAppTimeout" "5000"; Set-ItemProperty "HKCU:\Control Panel\Desktop" "HungAppTimeout" "5000"; Set-ItemProperty "HKCU:\Control Panel\Desktop" "AutoEndTasks" "0"')

# -- LIMPIEZA (LIMP) ----------------------------------------------------------
$Global:Catalog += (T -Id 'clean-temp' -Name 'Archivos temporales (solo TEMP)' -Desc 'DEFAULT: se acumulan solos | DeMente: purga TEMP usuario/Windows y reporta MB liberados.' -Icon 'E74D' -Cat 'clean' -Code 'Clear-TempFiles')
$Global:Catalog += (T -Id 'clean-recycle' -Name 'Vaciar papelera' -Desc 'DEFAULT: guarda lo borrado. DeMente: vaciar ahora. Lo de la Papelera se elimina de forma permanente.' -Icon 'E74D' -Cat 'clean' -Risk 'care' -Code 'Clear-RecycleBin')
$Global:Catalog += (T -Id 'clean-thumbnail' -Name 'Cache miniaturas' -Desc 'Windows guarda miniaturas (thumbcache_*.db) de imagenes y videos, incluso de fotos que ya borraste: son copias chiquitas en %LOCALAPPDATA%\Microsoft\Windows\Explorer. Borrarlas no afecta tus archivos originales; solo regenera vistas previas la proxima vez. Util por privacidad y espacio.' -Icon 'E8B7' -Cat 'clean' -Code 'Clear-ThumbCache')
$Global:Catalog += (T -Id 'clean-dumps' -Name 'Volcados de error' -Desc 'Cuando un programa se cuelga feo, Windows guarda un ''volcado de memoria'' con el estado exacto del error, pensado para que un técnico lo analice. Si nadie los va a revisar, solo ocupan espacio (a veces varios GB). Borrarlos no afecta nada de tu uso normal.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-CrashDumps')
$Global:Catalog += (T -Id 'clean-logs' -Name 'Registros del sistema' -Desc 'Windows guarda registros de eventos del sistema (qué pasó, cuándo, con qué programa) para poder diagnosticar problemas después. Son útiles si estás investigando una falla puntual; si no, se acumulan con los años. Borrarlos no rompe nada, solo perdés el historial viejo.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-InstallerLogs')
$Global:Catalog += (T -Id 'clean-store' -Name 'Caché de Microsoft Store' -Desc 'La Microsoft Store guarda copias de instalación y datos temporales de las apps para instalar/actualizar más rápido la próxima vez. Es cache pura: se reconstruye sola. No borra las apps que ya tenés instaladas.' -Icon 'E710' -Cat 'clean' -Code 'Clear-StoreCache')
$Global:Catalog += (T -Id 'clean-prefetch' -Name 'Prefetch' -Desc 'DEFAULT: Windows guarda pistas de arranque. DeMente: limpiar. En SSD el beneficio es bajo; en HDD a veces ayuda.' -Icon 'E74D' -Cat 'clean' -Code 'Clear-Prefetch')
# Caches de apps: solo si estan instaladas (misma idea que navegadores)
foreach ($appClean in @(
    @{ Id='clean-teams';   Name='Caché de Teams';   Code='Clear-TeamsCache';   Paths=@("$env:APPDATA\Microsoft\Teams","$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe") },
    @{ Id='clean-discord'; Name='Caché de Discord'; Code='Clear-DiscordCache'; Paths=@("$env:APPDATA\discord") },
    @{ Id='clean-spotify'; Name='Caché de Spotify'; Code='Clear-SpotifyCache'; Paths=@("$env:LOCALAPPDATA\Spotify","$env:APPDATA\Spotify") },
    @{ Id='clean-vscode';  Name='Caché de VS Code'; Code='Clear-VSCodeCache';  Paths=@("$env:APPDATA\Code") },
    @{ Id='clean-office';  Name='Caché de Office';  Code='Clear-OfficeCache';  Paths=@("$env:LOCALAPPDATA\Microsoft\Office") }
)) {
    $presente = $false
    foreach ($p in $appClean.Paths) {
        if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { $presente = $true; break }
    }
    if (-not $presente) { continue }
    $Global:Catalog += (T -Id $appClean.Id -Name $appClean.Name -Desc 'Solo cache de esta app (detectada en esta PC).' -Icon 'E74D' -Cat 'clean' -Code $appClean.Code)
}
$Global:Catalog += (T -Id 'clean-wu' -Name 'Caché de Windows Update' -Desc 'Windows Update guarda las actualizaciones ya descargadas e instaladas por si las necesita de nuevo. Una vez instaladas, esos archivos no sirven para nada más. Borrarlos no desinstala ninguna actualización; solo libera espacio.' -Icon 'E895' -Cat 'clean' -Code 'Clear-WUCache')
$Global:Catalog += (T -Id 'clean-bits' -Name 'Cache BITS' -Desc 'DEFAULT: cola de transferencias BITS | DeMente: limpia jobs completados/errores y carpeta Downloader. No toca descargas activas de Update.' -Icon 'E895' -Cat 'clean' -Code 'Clear-BitsCache')
$Global:Catalog += (T -Id 'clean-shader' -Name 'Caché de sombreadores' -Desc 'Los juegos y algunas apps guardan sombreadores (shaders) ya compilados para que la próxima vez carguen más rápido. Si los borrás, el juego los vuelve a generar solo la próxima vez que lo abras (puede tardar un poco más esa primera vez, nada más).' -Icon 'E7FC' -Cat 'clean' -Code 'Clear-D3DCache')
$Global:Catalog += (T -Id 'clean-thumbsdb' -Name 'Thumbs.db' -Desc 'Son los mismos archivos de miniaturas que ''Cache miniaturas'', pero el formato viejo que usan carpetas de red y discos externos (Thumbs.db). Mismo caso: solo vistas previas, se regeneran solas.' -Icon 'E8B7' -Cat 'clean' -Code 'Clear-ThumbnailDB')
$Global:Catalog += (T -Id 'clean-standby' -Name 'Memoria en espera' -Desc 'Windows guarda en RAM copias de archivos que usaste hace poco, ''por si los volvés a abrir'' (memoria en espera). Esa RAM se libera sola apenas un programa la necesita de verdad, así que no es ''memoria ocupada'' en el sentido de que te falte: liberarla a mano no mejora el rendimiento salvo casos puntuales donde Windows tarda en soltarla.' -Icon 'E945' -Cat 'clean' -Code 'Clear-StandbyMem')
$Global:Catalog += (T -Id 'clean-cbs' -Name 'Registros de CBS' -Desc 'Son registros técnicos de cada vez que Windows instaló o reparó componentes del sistema (los mismos que usa DeMente para saber si SFC reparó algo). Útiles para diagnóstico técnico; si no los vas a revisar, se pueden borrar sin problema.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-CBSLogs')
$Global:Catalog += (T -Id 'clean-dxdiag' -Name 'Registros de DxDiag' -Desc 'DEFAULT: se acumulan. DeMente: borrar logs de diagnóstico gráfico. Seguros de eliminar.' -Icon 'E7FC' -Cat 'clean' -Code 'Clear-DxDiagLogs')
$Global:Catalog += (T -Id 'clean-recent' -Name 'Documentos recientes' -Desc 'DEFAULT: Windows guarda qué abriste. DeMente: limpia la lista (no borra tus archivos). Útil por privacidad en PCs compartidas.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-RecentDocs')
$Global:Catalog += (T -Id 'clean-clipboard' -Name 'Portapapeles' -Desc 'DEFAULT: conserva lo último copiado. DeMente: vaciar ahora. No toca el historial en la nube (eso está en Privacidad).' -Icon 'E8C8' -Cat 'clean' -Code 'Clear-ClipboardData')
$Global:Catalog += (T -Id 'clean-wer' -Name 'Informes de errores (WER)' -Desc 'DEFAULT: se guardan reportes de fallos. DeMente: limpiar cola y archivo. No afecta programas instalados.' -Icon 'E7BA' -Cat 'clean' -Code 'Clear-ErrorReports')
$Global:Catalog += (T -Id 'clean-dns' -Name 'Caché DNS' -Desc 'DEFAULT: se rellena sola. DeMente: vaciar. Sirve cuando una web apunta mal o no carga tras cambiar de red.' -Icon 'E839' -Cat 'clean' -Code 'Clear-DnsCache')
$Global:Catalog += (T -Id 'clean-apps-deep' -Name 'Caches de apps (base ampliada)' -Desc 'DEFAULT: cada app guarda cache. DeMente: limpia caches seguras de Discord, Spotify, Office, Steam, NVIDIA/AMD, Teams, VS Code, Edge/Chrome code-cache. No borra historial ni contraseñas.' -Icon 'E74D' -Cat 'clean' -Code 'Clear-WDMAppsDeep')
$Global:Catalog += (T -Id 'clean-dm-backups' -Name 'Respaldos DeMente (>7 dias)' -Desc 'DeMente guarda un .reg por cada cambio de registro. Esto borra los de mas de 7 dias y deja los recientes por si hay que revertir algo reciente.' -Icon 'E74D' -Cat 'clean' -Code 'Clear-WDMOwnBackups')
$Global:Catalog += (T -Id 'clean-dm-backups-all' -Name 'Respaldos DeMente (TODOS)' -Desc 'Borra TODOS los .reg de respaldo que DeMente guardo. Usa esto si queres vaciar la carpeta de backups; despues no podras restaurar cambios viejos desde ahi.' -Icon 'E74D' -Cat 'clean' -Code 'Clear-WDMOwnBackups -Todo')
$Global:Catalog += (T -Id 'clean-dm-logs' -Name 'Registros de sesion DeMente (>7 dias)' -Desc 'Cada ejecucion deja un .log en Documents\DeMente\registros. Esto borra los de mas de 7 dias.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-WDMSessionLogs')
$Global:Catalog += (T -Id 'clean-dm-logs-all' -Name 'Registros de sesion DeMente (TODOS)' -Desc 'Borra TODOS los logs de sesion de DeMente en Documents\DeMente\registros. No toca Windows ni tus documentos.' -Icon 'E8A5' -Cat 'clean' -Code 'Clear-WDMSessionLogs -Todo')
$Global:Catalog += (T -Id 'clean-cleanmgr' -Name 'Limpieza profunda de Windows' -Desc 'Equivale al Liberador de espacio de Windows, pero corre dentro de DeMente (sin ventanas externas): temporales, Windows Update, Delivery Optimization, informes de error, volcados, miniaturas, historial de Defender, papelera y limpieza de componentes (DISM). No toca documentos, drivers ni Windows.old.' -Icon 'E74D' -Cat 'clean' -Code 'Start-WDMCleanMgr')

# -- SEGURIDAD (SEC) ----------------------------------------------------------
$Global:Catalog += (T -Id 'sec-defender-status' -Name 'Estado de Defender' -Desc 'Solo lectura: proteccion en tiempo real, firmas y amenazas. No cambia nada.' -Icon 'EA18' -Cat 'sec' -Code 'Show-DefenderStatus')
$Global:Catalog += (T -Id 'sec-defender-scan' -Name 'Escaneo rapido de Defender' -Desc 'Ejecuta un escaneo RAPIDO de Microsoft Defender (no es escaneo completo de todo el disco). Actualiza firmas si puede y reporta amenazas del historial reciente.' -Icon 'E721' -Cat 'sec' -Code 'Scan-Defender')
$Global:Catalog += (T -Id 'sec-accounts' -Name 'Auditar cuentas' -Desc 'Muestra todas las cuentas de usuario que existen en esta PC, para detectar alguna que no reconozcas (por ejemplo, una cuenta que alguien creó sin avisarte) o que tenga permisos de administrador sin necesitarlos.' -Icon 'E77B' -Cat 'sec' -Code 'Get-LocalUsers')
$Global:Catalog += (T -Id 'sec-transparency-amcache' -Name 'Transparencia: Amcache' -Desc 'Solo lectura: muestra si Windows guarda historial de ejecutables y desde cuando. No elimina nada.' -Icon 'E8D7' -Cat 'sec' -Code 'Get-DMAmcacheInfo')
$Global:Catalog += (T -Id 'sec-transparency-usbstor' -Name 'Transparencia: USB conectados' -Desc 'Solo lectura: lista los dispositivos USB con historial en el registro. No elimina nada.' -Icon 'ECF0' -Cat 'sec' -Code 'Get-DMUSBHistoryInfo')
$Global:Catalog += (T -Id 'sec-transparency-shellbags' -Name 'Transparencia: carpetas recordadas' -Desc 'Solo lectura: cuantas claves ShellBags (memoria de carpetas abiertas) existen. No elimina nada.' -Icon 'E8B7' -Cat 'sec' -Code 'Get-DMShellBagsInfo')
$Global:Catalog += (T -Id 'sec-transparency-wifi' -Name 'Transparencia: redes Wi-Fi guardadas' -Desc 'Solo lectura: lista los perfiles Wi-Fi guardados y como borrar uno puntual desde Windows. No elimina nada.' -Icon 'E701' -Cat 'sec' -Code 'Get-DMWiFiProfilesInfo')

# -- YARA ----------------------------------------------------------------------
$Global:Catalog += (T -Id 'sec-yara-update' -Name 'Actualizar motor YARA' -Desc 'YARA es un motor gratuito para detectar patrones de malware conocido, como una segunda opinión además de Windows Defender. Esto descarga el programa en sí (el motor); las reglas de detección van aparte.' -Icon 'E72E' -Cat 'sec' -Code 'Update-WDMYara')
$Global:Catalog += (T -Id 'sec-yara-rules' -Name 'Actualizar reglas YARA' -Desc 'Descarga el ''diccionario'' de patrones que YARA usa para reconocer malware (las reglas). Sin esto, el motor está instalado pero no sabe qué buscar.' -Icon 'E72E' -Cat 'sec' -Code 'Update-WDMYaraRules')
$Global:Catalog += (T -Id 'sec-yara-status' -Name 'Estado del motor YARA' -Desc 'Solo lectura: si el motor esta instalado, version y cantidad de reglas. Gratis, sin suscripcion.' -Icon 'E72E' -Cat 'sec' -Code 'Show-WDMYaraStatus')
$Global:Catalog += (T -Id 'sec-yara-quick' -Name 'Escaneo YARA rápido' -Desc 'Revisa las carpetas más típicas donde cae malware descargado (Descargas y Temporales) contra las reglas de YARA ya instaladas. Es rápido porque no revisa todo el disco, solo los lugares de mayor riesgo.' -Icon 'E721' -Cat 'sec' -Code 'Show-WDMYaraQuick')
$Global:Catalog += (T -Id 'sec-yara-full' -Name 'Escaneo YARA personalizado' -Desc 'Igual que el escaneo rápido, pero elegís vos qué carpeta revisar (por ejemplo, un pendrive o una carpeta que te generó dudas).' -Icon 'E721' -Cat 'sec' -Code 'Show-WDMYaraCustom')

# -- PRIVACIDAD (PRIVACY) ------------------------------------------------------
$Global:Catalog += (T -Id 'privacy-advertising' -Name 'ID de Publicidad' -Desc 'DEFAULT: ID de publicidad activado. DeMente: desactivar para menos anuncios personalizados.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-AdvertisingId' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1')
$Global:Catalog += (T -Id 'privacy-location' -Name 'Ubicación' -Desc 'Windows sabe en qué ubicación aproximada estás y se la puede pasar a las apps que la pidan (clima, mapas, fotos con geoetiqueta). Bloquearla no rompe nada; apps como Mapas van a pedirte la ubicación manualmente cuando la necesiten.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-Location' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Allow"')
$Global:Catalog += (T -Id 'privacy-telemetry' -Name 'Telemetría' -Desc 'DEFAULT: telemetría según edición. DeMente: reducir al mínimo permitido por políticas.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-Telemetry' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 1 -Type DWord -EA 0; Set-Service DiagTrack -StartupType Automatic -EA 0; Start-Service DiagTrack -EA 0')
$Global:Catalog += (T -Id 'privacy-activity' -Name 'Historial de actividad' -Desc 'Windows guarda un historial de qué apps y archivos usaste, para poder ''continuar donde quedaste'' incluso en otra PC con la misma cuenta. Si no usás esa función entre varios equipos, es puro historial que no necesitás.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-ActivityHistory' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 1; Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 1; Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 1')
$Global:Catalog += (T -Id 'privacy-microphone' -Name 'Micrófono' -Desc 'Controla si las apps (no las llamadas de Windows en sí) pueden prender tu micrófono. Bloquearlo a nivel sistema corta el acceso a todas las apps que lo usen; si necesitás videollamadas, después lo volvés a permitir para esa app puntual.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-Microphone' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone" "Value" "Allow"')
$Global:Catalog += (T -Id 'privacy-camera' -Name 'Cámara' -Desc 'Lo mismo que el micrófono pero para la cámara: controla qué apps pueden prenderla. Bloquearlo es la opción más privada; si usás videollamadas seguido, quizás prefieras dejarlo permitido.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-Camera' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam" "Value" "Allow"')
$Global:Catalog += (T -Id 'privacy-bing' -Name 'Bing en busqueda' -Desc 'Hace que el buscador del menú Inicio de Windows solo busque en tu PC, sin mandar lo que escribís a Bing por internet ni mostrarte resultados web mezclados con tus archivos.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-BingSearch' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 1; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 1')
$Global:Catalog += (T -Id 'privacy-gamedvr' -Name 'GameDVR' -Desc 'Es la función que graba clips de tus partidas y toma capturas (Xbox Game Bar). Si no la usás, queda corriendo de fondo sin sentido y a veces le saca rendimiento a los juegos.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-GameDVR' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 1 -EA 0; Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" -EA 0')
$Global:Catalog += (T -Id 'privacy-clipboard' -Name 'Portapapeles en nube' -Desc 'El portapapeles en la nube sincroniza lo que copiás y pegás entre varios dispositivos con la misma cuenta Microsoft. Si usás una sola PC, no te sirve de nada tenerlo activo.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-CloudClipboard' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Clipboard" "EnableClipboardHistory" 1 -EA 0; Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowClipboardHistory" -EA 0')
$Global:Catalog += (T -Id 'privacy-searchhighlights' -Name 'Destacados de búsqueda' -Desc 'Son esas noticias, efemérides y tips que aparecen mezclados en la caja de búsqueda del menú Inicio. Es contenido que Windows te muestra, no resultados de tus archivos: desactivarlo deja la búsqueda más limpia y directa.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-SearchHighlights' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" "IsDynamicSearchBoxEnabled" 1')
$Global:Catalog += (T -Id 'privacy-ceip' -Name 'CEIP / datos de uso' -Desc 'DEFAULT: Windows puede enviar datos de uso. DeMente: desactivar el programa de mejora (CEIP).' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-CEIP' -Revert 'Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" "CEIPEnable" 1')
$Global:Catalog += (T -Id 'privacy-tips' -Name 'Tips y sugerencias' -Desc 'DEFAULT: tips y sugerencias en el shell. DeMente: reducir publicidad y tips promocionales. Las alertas importantes siguen.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-TipsNotifications' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 1 -EA 0; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" 1 -EA 0')
$Global:Catalog += (T -Id 'privacy-copilot' -Name 'Copilot / IA del shell' -Desc 'DEFAULT: botón y atajos de Copilot según edición. DeMente: apagar integración visible sin desinstalar el sistema.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-Copilot' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 1 -EA 0; Remove-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" -EA 0; Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" -EA 0')
$Global:Catalog += (T -Id 'privacy-background' -Name 'Apps en segundo plano' -Desc 'DEFAULT: muchas apps siguen activas. DeMente: limitar en segundo plano. Puede retrasar avisos de Teams/correo.' -Icon 'E72E' -Cat 'privacy' -Code 'Privacy-BackgroundApps' -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 0')

# -- REPARACION (REPAIR) ------------------------------------------------------
$Global:Catalog += (T -Id 'repair-sequence' -Name 'Reparacion completa (recomendada)' -Desc 'Hace las dos reparaciones de Windows en el orden correcto: primero la base (DISM) y despues los archivos (SFC). Es lo que recomienda Microsoft cuando Windows anda raro. Tarda 15 a 45 minutos. Conviene reiniciar al final.' -Icon 'E90F' -Cat 'repair' -Code @'
HR "REPARACION COMPLETA DE WINDOWS"
INFO "Orden Microsoft: 1) DISM (base)  2) SFC (archivos)."
INFO "Necesita internet. Puede tardar 15-45 min. Podes usar la PC; no la apagues."
INFO "Vas a ver un aviso cada ~30 s mientras trabaja. Si no hay % aun, igual esta en curso."
Write-Host ""
$dism = Join-Path $env:SystemRoot 'System32\dism.exe'
$sfc  = Join-Path $env:SystemRoot 'System32\sfc.exe'
Step "Paso 1 de 2 - Base de Windows (DISM)"
INFO "1a) CheckHealth (suele ser rapido)..."
$rc1 = Invoke-WDMExe -File $dism -Arguments @('/Online','/Cleanup-Image','/CheckHealth') -TimeoutMin 15 -Label 'DISM-Check'
if ($rc1 -eq 0) { OK "CheckHealth: sin danos marcados (o revision OK)." }
elseif ($rc1 -eq -1) { WARN "CheckHealth corto por tiempo; igual se intenta RestoreHealth." }
else { WARN "CheckHealth codigo $rc1; se intenta reparar igual." }
INFO "1b) RestoreHealth (el paso largo: 10-40 min). No cierres DeMente."
$rc2 = Invoke-WDMExe -File $dism -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') -TimeoutMin 60 -Label 'DISM-Restore'
if ($rc2 -eq 0 -or $rc2 -eq 3010) { OK "Base de Windows en buen estado." }
elseif ($rc2 -eq -1) { WARN "DISM RestoreHealth no termino a tiempo. Revisa internet y reintenta luego." }
else { WARN "DISM RestoreHealth codigo $rc2 (a menudo falta internet o Windows Update trabado)." }
Write-Host ""
Step "Paso 2 de 2 - Archivos del sistema (SFC)"
INFO "SFC /scannow (5-20 min). Latido cada 30 s; el % a veces tarda en aparecer."
$inicioSfc = Get-Date
$rc3 = Invoke-WDMExe -File $sfc -Arguments @('/scannow') -TimeoutMin 35 -Label 'SFC'
Start-Sleep -Seconds 1
try { Write-DMSfcVerdict -Resultado (Get-DMSfcResult -Desde $inicioSfc) -ExitCode $rc3 } catch {
    if ($rc3 -eq 0) { OK "SFC termino (codigo 0)." } else { WARN "SFC codigo $rc3." }
}
Write-Host ""
OK "Reparacion completa terminada (o lo maximo posible en esta corrida)."
INFO "Reinicia la PC cuando puedas para aplicar cambios pendientes."
'@)

$Global:Catalog += (T -Id 'repair-sfc' -Name 'Revisar archivos de Windows (SFC)' -Desc 'Windows compara cada archivo importante del sistema con su copia original y arregla los que esten danados. No borra tus archivos personales. Tarda entre 5 y 15 minutos; podes seguir usando la PC.' -Icon 'E898' -Cat 'repair' -Code @'
HR "REVISAR ARCHIVOS DE WINDOWS (SFC)"
INFO "Tarda varios minutos. Vas a ver un aviso cada ~30 s: eso significa que sigue trabajando."
INFO "No apagues la PC hasta el mensaje final."
$sfc = Join-Path $env:SystemRoot 'System32\sfc.exe'
$inicioSfc = Get-Date
$rc = Invoke-WDMExe -File $sfc -Arguments @('/scannow') -TimeoutMin 35 -Label 'SFC'
Start-Sleep -Seconds 1
try { Write-DMSfcVerdict -Resultado (Get-DMSfcResult -Desde $inicioSfc) -ExitCode $rc } catch {
    if ($rc -eq 0) { OK "SFC termino (codigo 0)." } else { WARN "SFC codigo $rc." }
}
'@)
$Global:Catalog += (T -Id 'repair-dism' -Name 'Reparar la base de Windows (DISM)' -Desc 'Revisa la "imagen" de Windows (la copia base que usa SFC para arreglar cosas) y la repara si hace falta, bajando piezas de Windows Update. Necesita internet. Puede tardar 10 a 30 minutos.' -Icon 'E898' -Cat 'repair' -Code @'
HR "REPARAR LA BASE DE WINDOWS (DISM)"
INFO "Necesita internet. El paso RestoreHealth puede tardar 10-40 min."
INFO "Latido cada ~30 s en la consola = sigue en curso (no esta colgado)."
$dism = Join-Path $env:SystemRoot 'System32\dism.exe'
INFO "Paso 1 de 2: CheckHealth (rapido)..."
$rc1 = Invoke-WDMExe -File $dism -Arguments @('/Online','/Cleanup-Image','/CheckHealth') -TimeoutMin 15 -Label 'DISM-Check'
if ($rc1 -eq 0) { OK "CheckHealth OK." }
else { WARN "CheckHealth codigo $rc1; se intenta reparar igual." }
INFO "Paso 2 de 2: RestoreHealth (aca es donde tarda de verdad)..."
$rc2 = Invoke-WDMExe -File $dism -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') -TimeoutMin 60 -Label 'DISM-Restore'
if ($rc2 -eq 0 -or $rc2 -eq 3010) {
    OK "Listo: la base de Windows esta en buen estado."
    INFO "Recomendado despues: 'Revisar archivos de Windows (SFC)'."
} elseif ($rc2 -eq -1) {
    WARN "RestoreHealth corto por tiempo maximo. Reintenta con buena conexion."
} else {
    WARN "RestoreHealth codigo $rc2. Suele ser internet o Windows Update trabado."
}
'@)
$Global:Catalog += (T -Id 'repair-chkdsk' -Name 'CHKDSK' -Desc 'DEFAULT: no se ejecuta solo. DeMente: programa chkdsk /f en el proximo arranque (sin /r por defecto; /r tarda horas).' -Icon 'E7BA' -Cat 'repair' -Risk 'care' -Code @'
HR "CHKDSK (proximo arranque)"
INFO "No se ejecuta ahora: se programa /f en el volumen del sistema."
$drive = $env:SystemDrive.TrimEnd('\')
try {
    # /x no siempre aplica en sistema en uso; yes via stdin para programar
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "chkdsk.exe"
    $psi.Arguments = "$drive /f"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine("S")
    $proc.StandardInput.Close()
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit(60000) | Out-Null
    if ($out -match 'program|next|proximo|reinicio|reboot|scheduled|will be checked') {
        OK "CHKDSK /f programado para el proximo reinicio en $drive"
    } else {
        INFO "Salida chkdsk: $($out.Trim().Substring(0, [Math]::Min(200, $out.Trim().Length)))"
        WARN "Si el volumen esta en uso, Windows pedira programarlo al reiniciar. Confirma en el dialogo del sistema si aparece."
        OK "Solicitud CHKDSK enviada para $drive"
    }
} catch {
    WARN "No se pudo invocar chkdsk: $($_.Exception.Message)"
    INFO "Alternativa: cmd como admin -> chkdsk $drive /f  y aceptar programar al reiniciar."
}
'@)
$Global:Catalog += (T -Id 'repair-wmi' -Name 'Reconstruir WMI' -Desc 'WMI es una pieza interna de Windows que usan muchos programas (incluido este) para leer información del sistema (procesador, discos, red). Si algo la corrompió, procesos que dependen de WMI pueden fallar de forma rara. Reconstruirla la deja como recién instalada Windows.' -Icon 'E950' -Cat 'repair' -Risk 'danger' -Code 'Stop-Service winmgmt -Force -EA 0; Remove-Item "$env:SystemRoot\System32\wbem\Repository\*" -Recurse -Force -EA 0; Start-Service winmgmt -EA 0')
$Global:Catalog += (T -Id 'repair-network' -Name 'Reparar DNS (seguro)' -Desc 'DEFAULT: cache DNS de Windows. DeMente: flush DNS + reinicio del servicio Dnscache. NO toca IP fija, gateway ni adaptador.' -Icon 'E839' -Cat 'repair' -Code @'
HR "REPARACION DE RED SEGURA"
INFO "Solo limpia cache DNS. Tu IP fija / gateway / DNS manual NO se modifican."
try {
    ipconfig /flushdns | Out-Null
    OK "Cache DNS vaciada"
} catch { WARN "flushdns: $($_.Exception.Message)" }
try {
    Restart-Service Dnscache -Force -ErrorAction Stop
    OK "Servicio DNS Client reiniciado"
} catch {
    try { Restart-Service Dnscache -ErrorAction SilentlyContinue; OK "Servicio DNS Client reiniciado (parcial)" } catch { WARN "No se pudo reiniciar Dnscache: $_" }
}
try { netsh int ip delete arpcache 2>$null | Out-Null; OK "Cache ARP limpiada (opcional)" } catch { }
OK "Listo. Configuracion del adaptador intacta."
'@)
$Global:Catalog += (T -Id 'repair-network-hard' -Name 'Reset de pila de red (agresivo)' -Desc 'PELIGRO: netsh int ip reset + winsock reset. Puede BORRAR IP fija, gateway y DNS manuales. Solo si internet esta rota de verdad. Requiere reinicio.' -Icon 'E839' -Cat 'repair' -Risk 'danger' -Code @'
HR "RESET AGRESIVO DE RED"
WARN "Esto puede borrar IP fija, mascara, gateway y DNS manuales del adaptador."
WARN "Usa solo si la red esta realmente rota. Preferi 'Reparar DNS (seguro)' primero."
Write-Host ""
INFO "Ejecutando: netsh winsock reset"
netsh winsock reset
INFO "Ejecutando: netsh int ip reset"
netsh int ip reset
ipconfig /flushdns | Out-Null
Write-Host ""
WARN "Reinicia Windows para completar. Luego reconfigura IP fija si la usabas."
OK "Reset agresivo solicitado. Reinicio necesario."
'@)

# -- INFORMACION (INFO) ------------------------------------------------------
$Global:Catalog += (T -Id 'info-salud' -Name 'Salud del sistema' -Desc 'Escaneo inicial DeMente: Windows, rendimiento, almacenamiento, seguridad/privacidad, inicio y estabilidad. Solo lectura.' -Icon 'E95E' -Cat 'salud' -Code 'Show-SaludDeMenteConsole')
$Global:Catalog += (T -Id 'info-salud-run' -Name 'Ejecutar escaneo Salud' -Desc 'Lanza el multiescaneo Salud y muestra el informe humano.' -Icon 'E9D9' -Cat 'salud' -Code 'Show-SaludDeMenteConsole')
$Global:Catalog += (T -Id 'info-system' -Name 'Información del sistema' -Desc 'Hardware y Windows en un vistazo (sin JSON tecnico).' -Icon 'E946' -Cat 'info' -Code 'Show-DMSystemInfo')
$Global:Catalog += (T -Id 'info-disks' -Name 'Salud de los discos' -Desc 'Revisa cada disco por dentro: temperatura, señales tempranas de falla (SMART) y cuánto ''desgaste'' lleva. Es información de solo lectura, pensada para detectar un disco que se está por morir antes de que pierdas archivos.' -Icon 'EDA2' -Cat 'info' -Code 'Show-WDMDiskHealthReport')
$Global:Catalog += (T -Id 'info-events' -Name 'Eventos del sistema' -Desc 'DEFAULT: ver en Visor de eventos. DeMente: errores/criticos de 48h agrupados, con explicacion en lenguaje claro (sin volcar la tabla cruda).' -Icon 'E8F1' -Cat 'info' -Code 'Show-SystemEventsHuman')
$Global:Catalog += (T -Id 'info-startup' -Name 'Programas al inicio' -Desc 'Solo lectura: lista que se ejecuta al iniciar sesion (registro + carpeta Inicio). No desinstala nada; vos decis en el Administrador de tareas.' -Icon 'E7E8' -Cat 'info' -Code 'Show-StartupList')
$Global:Catalog += (T -Id 'info-porque-lenta' -Name '¿Por qué está lenta mi PC?' -Desc 'Diagnostico explicativo: cruza hardware, espacio, RAM, inicio, rendimiento y estabilidad. Clasifica causas reales, no un puntaje generico.' -Icon 'E9CE' -Cat 'info' -Code @'
# Diagnostico explicativo (proceso hijo: solo Prelude)
HR "POR QUE ESTA LENTA MI PC?"
Write-Host "DeMente cruza hardware, configuracion y estado real."
Write-Host "No es un puntaje generico: es lo que se encontro y donde."
Write-Host ""

$causas = New-Object System.Collections.Generic.List[object]
function Add-Causa($Nivel, $Nombre, $Detalle, $Sugerencia) {
    $causas.Add([pscustomobject]@{ Nivel=$Nivel; Nombre=$Nombre; Detalle=$Detalle; Sugerencia=$Sugerencia })
}

# --- Hardware ---
$cpu = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
$cores = if ($cpu) { [int]$cpu.NumberOfCores } else { 0 }
$ram = Get-CimInstance Win32_PhysicalMemory -EA 0
$ramGB = if ($ram) { [math]::Round(($ram | Measure-Object Capacity -Sum).Sum / 1GB, 1) } else { 0 }
$disks = Get-CimInstance Win32_DiskDrive -EA 0
$tieneSSD = if ($disks) { (@($disks) | Where-Object { $_.Model -match 'SSD|NVMe|M\.2|Solid' }).Count -gt 0 } else { $false }
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -EA 0
$librePct = 0; $libreGB = 0
if ($vol -and $vol.Size -gt 0) {
    $libreGB = [math]::Round($vol.FreeSpace / 1GB, 1)
    $librePct = [math]::Round($vol.FreeSpace / $vol.Size * 100)
}

if ($ramGB -gt 0 -and $ramGB -lt 4) {
    Add-Causa 'Causa probable' 'Memoria RAM' "$ramGB GB (muy poca para Windows actual)" 'Ampliar RAM si es posible. Evita muchas pestanas y programas a la vez.'
} elseif ($ramGB -ge 4 -and $ramGB -lt 8) {
    Add-Causa 'Factor contribuyente' 'Memoria RAM' "$ramGB GB (limitada para multitarea moderna)" 'Cierra programas que no uses. 8 GB o mas es el piso comodo hoy.'
}

if ($cores -gt 0 -and $cores -le 2) {
    Add-Causa 'Factor contribuyente' 'Procesador' "$cores nucleos (equipo de entrada)" 'Evita muchas tareas pesadas en paralelo. No es un fallo: es el techo del hardware.'
}

if (-not $tieneSSD) {
    Add-Causa 'Factor contribuyente' 'Tipo de disco' 'HDD detectado (mas lento que SSD/NVMe)' 'El cuello de botella tipico al abrir programas y arrancar. Un SSD mejora mucho la sensacion de velocidad.'
}

if ($librePct -gt 0 -and $librePct -lt 10) {
    Add-Causa 'Causa probable' 'Espacio en disco' "Solo $librePct% libre ($libreGB GB)" 'Seccion Limpieza: temporales, caches, Papelera. Libera espacio urgente.'
} elseif ($librePct -gt 0 -and $librePct -lt 20) {
    Add-Causa 'Factor contribuyente' 'Espacio en disco' "$librePct% libre ($libreGB GB)" 'Conviene liberar algo de espacio (Limpieza) para que Windows respire.'
}

# --- Uptime ---
$upTs = Get-WDMSessionUptime
$uptimeTxt = Format-WDMUptime $upTs
$uptimeDias = $upTs.TotalDays
if ($uptimeDias -ge 7) {
    Add-Causa 'Factor contribuyente' 'Tiempo sin reiniciar' $uptimeTxt 'Reinicia el equipo. La memoria y los procesos en segundo plano se acumulan.'
} elseif ($uptimeDias -ge 3) {
    Add-Causa 'Condicion a revisar' 'Tiempo sin reiniciar' $uptimeTxt 'Un reinicio periodico ayuda a liberar recursos.'
}
# Si WMI dice mucho mas, no lo usamos como causa (Inicio rapido miente el LastBootUpTime).

# --- Rendimiento (DWORD seguros) ---
function Local-Dword($Path, $Name) {
    try {
        $v = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
        $u = [uint64][uint32]$v
        if ($u -gt 0x7FFFFFFF) { return [int64]($u - 0x100000000) }
        return [int64]$u
    } catch { return $null }
}
function Local-DwordLow($Path, $Name) {
    try {
        $v = (Get-ItemProperty -Path $Path -Name $Name -EA Stop).$Name
        return [int]([uint64][uint32]$v -band 0xFF)
    } catch { return $null }
}

$idealPrio = if ($cores -le 2) { 18 } elseif ($cores -le 4) { 26 } else { 38 }
$wps = Local-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
if ($null -ne $wps -and $wps -ne $idealPrio) {
    Add-Causa 'Condicion a revisar' 'Prioridad del procesador' "Actual: $wps | Propuesta DeMente: $idealPrio (para $cores nucleos)" 'Seccion Rendimiento: Prioridad del procesador.'
}

$ntfs = Local-DwordLow 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
if ($null -ne $ntfs -and $ntfs -ne 1 -and $ntfs -ne 3) {
    $lab = switch ($ntfs) { 0 { '0 (actualiza last-access)' } 2 { '2 (system managed)' } default { "$ntfs" } }
    Add-Causa 'Condicion a revisar' 'NTFS Last Access' "Actual: $lab | Propuesta: 3" 'Reduce escrituras administrativas en disco. Seccion Rendimiento.'
}

$nt = Local-Dword 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
# -1 o 4294967295 = sin limite
if ($null -ne $nt -and $nt -ne -1 -and $nt -ne [int64]4294967295) {
    Add-Causa 'Condicion a revisar' 'Limitacion de red' "Throttling activo (valor $nt)" 'Opcional: desactivar si usas audio/video en tiempo real.'
}

$vfx = Local-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
if ($null -ne $vfx -and $vfx -ne 2 -and $ramGB -lt 8) {
    Add-Causa 'Condicion a revisar' 'Efectos visuales' "Actual: $vfx | Con poca RAM conviene modo rendimiento (2)" 'Seccion Rendimiento: Efectos visuales.'
}

# --- Startup ---
$startup = 0
foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
    if (Test-Path $rk) {
        $props = Get-ItemProperty $rk -EA 0
        if ($props) {
            $startup += @($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $null -ne $_.Value -and "$($_.Value)" -ne '' }).Count
        }
    }
}
if ($startup -ge 12) {
    Add-Causa 'Factor contribuyente' 'Programas al inicio' "$startup entradas en el registro Run" 'Administrador de tareas > Inicio: deshabilita lo que no necesites.'
} elseif ($startup -ge 8) {
    Add-Causa 'Condicion a revisar' 'Programas al inicio' "$startup entradas en Run" 'Revisa si todos hacen falta al arrancar.'
}

# --- Eventos ---
try {
    $desde = (Get-Date).AddHours(-48)
    $ev = @(Get-WinEvent -FilterHashtable @{LogName='System'; Level=1; StartTime=$desde} -MaxEvents 30 -EA 0)
    if ($ev.Count -gt 5) {
        Add-Causa 'Factor contribuyente' 'Eventos criticos' "$($ev.Count) eventos Level=1 en 48h" 'Revisa el Visor de eventos (System) o la seccion Reparacion.'
    } elseif ($ev.Count -gt 0) {
        Add-Causa 'Condicion a revisar' 'Eventos del sistema' "$($ev.Count) evento(s) critico(s) en 48h" 'Si se repiten, anota el origen en el Visor de eventos.'
    }
} catch { }

# --- Temp rough ---
try {
    $tb = [double]0
    foreach ($p in @("$env:TEMP","$env:SystemRoot\Temp")) {
        if (Test-Path $p) {
            $tb += [double]((Get-ChildItem $p -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
        }
    }
    $tmb = [math]::Round($tb/1MB,0)
    if ($tmb -gt 2048) {
        Add-Causa 'Factor contribuyente' 'Archivos temporales' "Aprox. $tmb MB en carpetas TEMP" 'Seccion Limpieza: temporales y caches.'
    } elseif ($tmb -gt 512) {
        Add-Causa 'Condicion a revisar' 'Archivos temporales' "Aprox. $tmb MB en TEMP" 'Una limpieza rapida puede ayudar.'
    }
} catch { }

# --- Salida ordenada (sin emojis rotos en consola) ---
$orden = @{'Causa probable'=0; 'Factor contribuyente'=1; 'Condicion a revisar'=2}
$grupos = @($causas | Group-Object Nivel | Sort-Object { $orden[$_.Name] })
if ($grupos.Count -eq 0) {
    OK 'No se detectaron causas de lentitud relevantes en este equipo.'
    INFO "Hardware: $cores nucleos | $ramGB GB RAM | $(if($tieneSSD){'SSD/NVMe'}else{'HDD'}) | disco $librePct% libre | $uptimeTxt"
} else {
    foreach ($g in $grupos) {
        Write-Host ''
        HR ("$($g.Name.ToUpper()) ($($g.Count))")
        foreach ($item in $g.Group) {
            ROW $item.Nombre $item.Detalle
            if ($item.Sugerencia) { ROW '  Sugerencia' $item.Sugerencia }
        }
    }
    Write-Host ''
    $nP = @($causas | Where-Object Nivel -eq 'Causa probable').Count
    $nF = @($causas | Where-Object Nivel -eq 'Factor contribuyente').Count
    $nC = @($causas | Where-Object Nivel -eq 'Condicion a revisar').Count
    if ($nP -gt 0) {
        ERR "$nP causa(s) probable(s). Atendelas primero (hardware o espacio)."
    } elseif ($nF -gt 0) {
        WARN "$nF factor(es) contribuyente(s). No son fallos graves, pero explican parte de la lentitud."
    } else {
        INFO "$nC condicion(es) a revisar. Son ajustes opcionales o habitos (reinicio, inicio, etc.)."
    }
    INFO "Resumen equipo: $cores nucleos | $ramGB GB RAM | $(if($tieneSSD){'SSD/NVMe'}else{'HDD'}) | $librePct% libre | $uptimeTxt | $startup programas al inicio"
}
'@)



# -- HERRAMIENTAS DE TERCEROS (TOOLS) ----------------------------------------
# Se descargan o se lanzan desde Documents\DeMente\tools (como YARA).
# No se empaquetan binarios dentro del .ps1.

$Global:Catalog += (T -Id 'tool-autoruns' -Name 'Autoruns (Sysinternals)' -Desc 'Lista TODO lo que arranca con Windows (servicios, tareas, Run, drivers). Oficial Microsoft. Se descarga si no esta.' -Icon 'E8A5' -Cat 'tools' -Run 'term' -Code @'
HR "AUTORUNS (Sysinternals)"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/Autoruns.zip' -ZipName 'Autoruns' -ExeNames @('Autoruns64.exe','Autoruns.exe') -Label 'Autoruns'
if ($exe) { Start-WDMTool $exe }
'@)
$Global:Catalog += (T -Id 'tool-procexp' -Name 'Process Explorer' -Desc 'Administrador de tareas avanzado (Sysinternals). Ver CPU, handles, DLLs y arbol de procesos.' -Icon 'E8A5' -Cat 'tools' -Run 'term' -Code @'
HR "PROCESS EXPLORER"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/ProcessExplorer.zip' -ZipName 'ProcessExplorer' -ExeNames @('procexp64.exe','procexp.exe') -Label 'Process Explorer'
if ($exe) { Start-WDMTool $exe }
'@)
$Global:Catalog += (T -Id 'tool-procmon' -Name 'Process Monitor' -Desc 'Monitor en tiempo real de registro, archivo y proceso (Sysinternals). Para cazar que traba el sistema.' -Icon 'E8A5' -Cat 'tools' -Run 'term' -Code @'
HR "PROCESS MONITOR"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/ProcessMonitor.zip' -ZipName 'ProcessMonitor' -ExeNames @('Procmon64.exe','Procmon.exe') -Label 'Process Monitor'
if ($exe) { Start-WDMTool $exe }
'@)
$Global:Catalog += (T -Id 'tool-tcpview' -Name 'TCPView' -Desc 'Conexiones de red por proceso (Sysinternals). Util si algo satura la red.' -Icon 'E839' -Cat 'tools' -Run 'term' -Code @'
HR "TCPVIEW"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/TCPView.zip' -ZipName 'TCPView' -ExeNames @('tcpview64.exe','tcpview.exe') -Label 'TCPView'
if ($exe) { Start-WDMTool $exe }
'@)
$Global:Catalog += (T -Id 'tool-bginfo' -Name 'BGInfo' -Desc 'Muestra datos del equipo en el fondo de escritorio (Sysinternals). Ideal en aulas o labs.' -Icon 'E946' -Cat 'tools' -Run 'term' -Code @'
HR "BGINFO"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/BGInfo.zip' -ZipName 'BGInfo' -ExeNames @('Bginfo64.exe','Bginfo.exe') -Label 'BGInfo'
if ($exe) { Start-WDMTool $exe }
'@)
$Global:Catalog += (T -Id 'tool-sdelete' -Name 'SDelete (borrado seguro)' -Desc 'Sysinternals: limpia espacio libre o borra archivos de forma segura. Uso avanzado.' -Icon 'E74D' -Cat 'tools' -Risk 'care' -Run 'term' -Code @'
HR "SDELETE"
$exe = Get-WDMToolZip -Url 'https://download.sysinternals.com/files/SDelete.zip' -ZipName 'SDelete' -ExeNames @('sdelete64.exe','sdelete.exe') -Label 'SDelete'
if ($exe) {
    INFO "Ejemplo: sdelete -z C:  (limpia espacio libre, no borra tus archivos)."
    Start-WDMTool $exe
}
'@)
$Global:Catalog += (T -Id 'tool-nvclean' -Name 'NVCleanstall (lanzador)' -Desc 'Instalador limpio de drivers NVIDIA (TechPowerUp). Si no esta descargado, abre la pagina oficial.' -Icon 'E7F4' -Cat 'tools' -Run 'term' -Code @'
HR "NVCLEANSTALL"
$exe = Find-WDMTool @('NVCleanstall.exe','nvcleanstall.exe')
if ($exe) { Start-WDMTool $exe }
else {
    WARN "NVCleanstall no esta en Documents\DeMente\tools"
    INFO "TechPowerUp no ofrece ZIP estable por API; descarga manual:"
    INFO "https://www.techpowerup.com/download/techpowerup-nvcleanstall/"
    INFO "Copia NVCleanstall.exe a: $(Get-WDMToolsDir)"
    try { Start-Process 'https://www.techpowerup.com/download/techpowerup-nvcleanstall/' } catch {}
}
'@)
$Global:Catalog += (T -Id 'tool-ddu' -Name 'DDU - Display Driver Uninstaller' -Desc 'Desinstala drivers de GPU en modo seguro. Solo si vas a reinstalar video. Abre guia/descarga oficial.' -Icon 'E7F4' -Cat 'tools' -Risk 'danger' -Run 'term' -Code @'
HR "DDU (Display Driver Uninstaller)"
$exe = Find-WDMTool @('Display Driver Uninstaller.exe','DDU.exe')
if ($exe) { Start-WDMTool $exe }
else {
    WARN "DDU no esta en Documents\DeMente\tools"
    INFO "Descarga: https://www.guru3d.com/files-details/display-driver-uninstaller-download.html"
    INFO "Usar en Modo seguro antes de reinstalar GPU."
    try { Start-Process 'https://www.guru3d.com/files-details/display-driver-uninstaller-download.html' } catch {}
}
'@)
$Global:Catalog += (T -Id 'tool-crystal' -Name 'CrystalDiskInfo (salud disco)' -Desc 'SMART, temperatura y salud del disco. Si no esta, abre la pagina de descarga.' -Icon 'EDA2' -Cat 'tools' -Run 'term' -Code @'
HR "CRYSTALDISKINFO"
$exe = Find-WDMTool @('DiskInfo64.exe','DiskInfoA64.exe','CrystalDiskInfo.exe')
if ($exe) { Start-WDMTool $exe }
else {
    WARN "CrystalDiskInfo no encontrado en Documents\DeMente\tools"
    INFO "https://crystalmark.info/en/software/crystaldiskinfo/"
    try { Start-Process 'https://crystalmark.info/en/software/crystaldiskinfo/' } catch {}
}
'@)
$Global:Catalog += (T -Id 'tool-everything' -Name 'Everything (busqueda de archivos)' -Desc 'Busqueda instantanea de archivos (voidtools). Si no esta, abre la pagina oficial.' -Icon 'E721' -Cat 'tools' -Run 'term' -Code @'
HR "EVERYTHING"
$exe = Find-WDMTool @('Everything.exe','Everything64.exe')
if (-not $exe) {
    $pf = @(
        "$env:ProgramFiles\Everything\Everything.exe",
        "${env:ProgramFiles(x86)}\Everything\Everything.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($pf) { $exe = $pf }
}
if ($exe) { Start-WDMTool $exe }
else {
    WARN "Everything no instalado"
    INFO "https://www.voidtools.com/"
    try { Start-Process 'https://www.voidtools.com/' } catch {}
}
'@)
$Global:Catalog += (T -Id 'tool-hwinfo' -Name 'HWiNFO (sensores)' -Desc 'Sensores, temperaturas y hardware detallado. Abre descarga si no esta local.' -Icon 'E9D9' -Cat 'tools' -Run 'term' -Code @'
HR "HWINFO"
$exe = Find-WDMTool @('HWiNFO64.exe','HWiNFO32.exe')
if ($exe) { Start-WDMTool $exe }
else {
    WARN "HWiNFO no esta en Documents\DeMente\tools"
    INFO "https://www.hwinfo.com/download/"
    try { Start-Process 'https://www.hwinfo.com/download/' } catch {}
}
'@)
$Global:Catalog += (T -Id 'tool-folder' -Name 'Abrir carpeta de herramientas' -Desc 'Abre Documents\DeMente\tools para copiar Autoruns, NVCleanstall, DDU, etc.' -Icon 'E8B7' -Cat 'tools' -Code @'
$p = Get-WDMToolsDir
OK "Carpeta: $p"
Start-Process explorer.exe $p
'@)
$Global:Catalog += (T -Id 'tool-sysinternals-suite' -Name 'Suite Sysinternals (info)' -Desc 'Paquete completo de Microsoft Sysinternals. Abre la pagina oficial de descarga.' -Icon 'E8A5' -Cat 'tools' -Run 'term' -Code @'
HR "SYSINTERNALS SUITE"
INFO "Paquete completo (Autoruns, ProcExp, ProcMon, TCPView, etc.):"
INFO "https://learn.microsoft.com/sysinternals/downloads/sysinternals-suite"
INFO "O individual desde DeMente > Herramientas."
try { Start-Process 'https://learn.microsoft.com/sysinternals/downloads/sysinternals-suite' } catch {}
'@)

# -- MAS RENDIMIENTO (Lazarus / kernel / red) --------------------------------
$Global:Catalog += (T -Id 'perf-mmcss' -Name 'MMCSS Games (prioridad GPU/CPU)' -Desc 'DEFAULT: Scheduling Category Medium | DeMente: High para juegos en SystemProfile\Games | Mejora scheduling multimedia.' -Icon 'E7F4' -Cat 'perf' -Code @'
$k="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
Set-ItemProperty $k -Name "GPU Priority" -Value 8 -Type DWord -EA 0
Set-ItemProperty $k -Name "Priority" -Value 6 -Type DWord -EA 0
Set-ItemProperty $k -Name "Scheduling Category" -Value "High" -Type String -EA 0
Set-ItemProperty $k -Name "SFIO Priority" -Value "High" -Type String -EA 0
OK "MMCSS Games ajustado (GPU Priority 8, Priority 6, High)"
'@ -Revert @'
$k="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
Remove-ItemProperty $k -Name "GPU Priority" -EA 0
Remove-ItemProperty $k -Name "Priority" -EA 0
Remove-ItemProperty $k -Name "Scheduling Category" -EA 0
Remove-ItemProperty $k -Name "SFIO Priority" -EA 0
OK "MMCSS Games revertido a DEFAULT"
'@)
$Global:Catalog += (T -Id 'perf-fullscreen-opt' -Name 'Optimizaciones de pantalla completa' -Desc 'DEFAULT: a veces activas y causan stutter | DeMente: desactivar Fullscreen Optimizations globales en el shell' -Icon 'E7F4' -Cat 'perf' -Code @'
$k="HKCU:\System\GameConfigStore"
if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
Set-ItemProperty $k -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -EA 0
Set-ItemProperty $k -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord -EA 0
Set-ItemProperty $k -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord -EA 0
OK "Optimizaciones de pantalla completa ajustadas"
'@ -Revert @'
$k="HKCU:\System\GameConfigStore"
Remove-ItemProperty $k -Name "GameDVR_FSEBehaviorMode" -EA 0
Remove-ItemProperty $k -Name "GameDVR_HonorUserFSEBehaviorMode" -EA 0
Remove-ItemProperty $k -Name "GameDVR_FSEBehavior" -EA 0
OK "FSE revertido"
'@)
$Global:Catalog += (T -Id 'perf-mouse-accel' -Name 'Aceleracion del mouse' -Desc 'DEFAULT: aceleracion ON | DeMente: curva 1 a 1 (sin aceleracion) para punteria precisa' -Icon 'E790' -Cat 'perf' -Code @'
$k="HKCU:\Control Panel\Mouse"
Set-ItemProperty $k -Name "MouseSpeed" -Value "0" -EA 0
Set-ItemProperty $k -Name "MouseThreshold1" -Value "0" -EA 0
Set-ItemProperty $k -Name "MouseThreshold2" -Value "0" -EA 0
OK "Aceleracion del mouse desactivada (1:1)"
'@ -Revert @'
$k="HKCU:\Control Panel\Mouse"
Set-ItemProperty $k -Name "MouseSpeed" -Value "1" -EA 0
Set-ItemProperty $k -Name "MouseThreshold1" -Value "6" -EA 0
Set-ItemProperty $k -Name "MouseThreshold2" -Value "10" -EA 0
OK "Aceleracion del mouse DEFAULT restaurada"
'@)
$Global:Catalog += (T -Id 'perf-disable-sticky' -Name 'Teclas pegajosas / filtro' -Desc 'DEFAULT: accesibilidad puede activarse por error | DeMente: desactivar StickyKeys/FilterKeys/ToggleKeys al mantener Shift' -Icon 'E790' -Cat 'perf' -Code @'
$k="HKCU:\Control Panel\Accessibility\StickyKeys"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}; Set-ItemProperty $k -Name "Flags" -Value "506" -EA 0
$k="HKCU:\Control Panel\Accessibility\Keyboard Response"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}; Set-ItemProperty $k -Name "Flags" -Value "122" -EA 0
$k="HKCU:\Control Panel\Accessibility\ToggleKeys"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}; Set-ItemProperty $k -Name "Flags" -Value "58" -EA 0
OK "Sticky/Filter/Toggle Keys desactivados"
'@ -Revert @'
$k="HKCU:\Control Panel\Accessibility\StickyKeys"; if(Test-Path $k){ Set-ItemProperty $k -Name "Flags" -Value "510" -EA 0 }
$k="HKCU:\Control Panel\Accessibility\Keyboard Response"; if(Test-Path $k){ Set-ItemProperty $k -Name "Flags" -Value "126" -EA 0 }
$k="HKCU:\Control Panel\Accessibility\ToggleKeys"; if(Test-Path $k){ Set-ItemProperty $k -Name "Flags" -Value "62" -EA 0 }
OK "Sticky + Filter + Toggle Keys restaurados a valores DEFAULT tipicos de Windows"
'@)
$Global:Catalog += (T -Id 'perf-xbox-services' -Name 'Servicios Xbox en segundo plano' -Desc 'DEFAULT: varios servicios Xbox | DeMente: deshabilitar XblAuthManager/XblGameSave/XboxNetApiSvc/XboxGipSvc si no usas Xbox' -Icon 'E7F4' -Cat 'perf' -Code @'
$snapDir = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\startup-state'
if (-not (Test-Path $snapDir)) { New-Item $snapDir -ItemType Directory -Force | Out-Null }
foreach($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')){
  try{
    $prev = 'Manual'
    try { $prev = [string](Get-Service $s -EA Stop).StartType } catch {}
    Set-Content (Join-Path $snapDir ("svc_{0}.txt" -f $s)) $prev -Encoding UTF8 -Force
    Stop-Service $s -Force -EA 0; Set-Service $s -StartupType Disabled -EA 0
    OK "Deshabilitado: $s (antes: $prev)"
  } catch { INFO "No disponible: $s" }
}
'@ -Revert @'
$snapDir = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\startup-state'
foreach($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')){
  try{
    $restore = 'Manual'
    $sf = Join-Path $snapDir ("svc_{0}.txt" -f $s)
    if (Test-Path $sf) { $restore = (Get-Content $sf -Raw).Trim() }
    if ($restore -notmatch '^(Automatic|AutomaticDelayedStart|Manual|Disabled)$') { $restore = 'Manual' }
    if ($restore -eq 'AutomaticDelayedStart') {
      Set-Service $s -StartupType Automatic -EA 0; sc.exe config $s start= delayed-auto | Out-Null
    } else {
      Set-Service $s -StartupType $restore -EA 0
    }
    OK "Restaurado $s -> $restore"
  } catch { INFO "No disponible: $s" }
}
'@)
$Global:Catalog += (T -Id 'perf-sysmain-hint' -Name 'SysMain segun disco/RAM' -Desc 'DEFAULT: SysMain automatico | DeMente: aplica la logica SSD/poca RAM (misma que Optimize-Superfetch)' -Icon 'E945' -Cat 'perf' -Code 'Optimize-Superfetch' -Revert 'Set-Service SysMain -StartupType Automatic -EA 0; Start-Service SysMain -EA 0')
$Global:Catalog += (T -Id 'perf-large-cache' -Name 'LargeSystemCache (solo HDDs con mucha RAM)' -Desc 'DEFAULT: 0 | DeMente: 1 solo con >=16GB y HDD | En SSD/NVMe suele no aportar' -Icon 'E945' -Cat 'perf' -Code @'
if($script:RAMTotalGB -lt 16){ WARN "Menos de 16 GB RAM: no se aplica LargeSystemCache"; return }
if($script:TieneSSD){ WARN "SSD/NVMe detectado: LargeSystemCache no recomendado"; return }
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord -EA Stop
OK "LargeSystemCache=1"
'@ -Revert 'Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWord -EA 0')


# -- INICIO (optimizacion propia, no solo listar) -----------------------------
$Global:Catalog += (T -Id 'perf-startup-list' -Name 'Auditar programas al inicio' -Desc 'DEFAULT: muchos programas en Run | DeMente: lista HKLM/HKCU Run + carpeta Inicio y marca sospechosos de impacto' -Icon 'E8A5' -Cat 'perf' -Code 'Show-StartupList')
$Global:Catalog += (T -Id 'perf-startup-safe' -Name 'Auditar inicio (seguro, no borra)' -Desc 'DEFAULT: todo lo de Run queda activo | DeMente: SOLO informa entradas con ruta ausente y programas pesados. No borra ni deshabilita nada automaticamente.' -Icon 'E8A5' -Cat 'perf' -Code 'Show-StartupSafeAudit')
$Global:Catalog += (T -Id 'perf-startup-delay' -Name 'Retrasar servicios no criticos' -Desc 'DEFAULT: muchos Automatic | DeMente: pasa a Automatic (Delayed) servicios pesados no esenciales (SysMain en SSD ya se trata aparte)' -Icon 'E8A5' -Cat 'perf' -Code @'
HR "SERVICIOS CON INICIO RETRASADO"
$targets = @('WSearch','MapsBroker','Spooler','Fax','RemoteRegistry','RetailDemo','DiagTrack')
foreach ($s in $targets) {
    try {
        $svc = Get-Service -Name $s -EA Stop
        if ($svc.StartType -eq 'Automatic') {
            # 2 = Automatic, 1 = Automatic Delayed via sc.exe
            sc.exe config $s start= delayed-auto | Out-Null
            OK "Inicio retrasado: $s"
        } else {
            INFO "$s ya no es Automatic ($($svc.StartType))"
        }
    } catch { INFO "No aplica: $s" }
}
OK "Servicios no criticos en inicio retrasado (si estaban en Automatic)."
INFO "Revertir: services.msc o DEFAULT WINDOWS en perfiles no cubre sc.exe; usa services.msc."
'@)

# -- MAS LIMPIEZA (Mundus) ---------------------------------------------------
$Global:Catalog += (T -Id 'clean-windows-old' -Name 'Windows.old / componentes' -Desc 'DEFAULT: conserva Windows.old tras actualizar | DeMente: DISM StartComponentCleanup + intento de borrar Windows.old' -Icon 'E74D' -Cat 'clean' -Risk 'care' -Code 'Clear-WindowsOld')
$Global:Catalog += (T -Id 'clean-delivery' -Name 'Delivery Optimization' -Desc 'DEFAULT: cache de actualizaciones P2P | DeMente: purgar Delivery Optimization' -Icon 'E74D' -Cat 'clean' -Code 'Clear-DeliveryOpt')
$Global:Catalog += (T -Id 'clean-fontcache' -Name 'Cache de fuentes' -Desc 'DEFAULT: regenera sola | DeMente: forzar limpieza de FontCache' -Icon 'E74D' -Cat 'clean' -Code 'Clear-FontCache')
$Global:Catalog += (T -Id 'clean-iconcache' -Name 'Cache de iconos' -Desc 'DEFAULT: iconcache.db del usuario | DeMente: regenerar iconos (puede parpadear el escritorio)' -Icon 'E74D' -Cat 'clean' -Code @'
$exp=$null -ne (Get-Process explorer -EA 0)
if($exp){ Stop-Process -Name explorer -Force -EA 0; Start-Sleep -Milliseconds 600 }
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -EA 0
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -EA 0
if($exp){ Start-Process explorer }
OK "Cache de iconos regenerada"
'@)
$Global:Catalog += (T -Id 'clean-edge-webview' -Name 'Cache WebView2 / Edge extra' -Desc 'DEFAULT: caches de WebView2 de apps | DeMente: limpiar EBWebView caches sin tocar perfiles de login' -Icon 'E74D' -Cat 'clean' -Code @'
$n=0
Get-ChildItem "$env:LOCALAPPDATA" -Directory -Filter "*WebView*" -EA 0 | ForEach-Object {
  Get-ChildItem $_.FullName -Recurse -Directory -Filter "Cache" -EA 0 | ForEach-Object {
    $n += @(Get-ChildItem $_.FullName -Recurse -File -EA 0).Count
    Remove-Item "$($_.FullName)\*" -Recurse -Force -EA 0
  }
}
OK "Caches WebView tocadas ($n archivos aprox.)"
'@)

# -- MAS PRIVACIDAD ----------------------------------------------------------
$Global:Catalog += (T -Id 'privacy-tailored' -Name 'Experiencias personalizadas' -Desc 'DEFAULT: sugerencias segun uso | DeMente: desactivar Tailored Experiences' -Icon 'E72E' -Cat 'privacy' -Code @'
$k="HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
Set-ItemProperty $k -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Type DWord -EA 0
OK "Experiencias personalizadas desactivadas"
'@ -Revert 'Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 1 -Type DWord -EA 0')
$Global:Catalog += (T -Id 'privacy-input-personalization' -Name 'Personalizacion de entrada' -Desc 'DEFAULT: escritura/voz ayudan a Microsoft | DeMente: desactivar input personalization' -Icon 'E72E' -Cat 'privacy' -Code @'
$k="HKCU:\Software\Microsoft\InputPersonalization"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
Set-ItemProperty $k -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -EA 0
Set-ItemProperty $k -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -EA 0
OK "Personalizacion de entrada restringida"
'@ -Revert @'
$k="HKCU:\Software\Microsoft\InputPersonalization"
Set-ItemProperty $k -Name "RestrictImplicitTextCollection" -Value 0 -Type DWord -EA 0
Set-ItemProperty $k -Name "RestrictImplicitInkCollection" -Value 0 -Type DWord -EA 0
'@)
$Global:Catalog += (T -Id 'privacy-feedback' -Name 'Frecuencia de feedback' -Desc 'DEFAULT: feedback periodico | DeMente: nunca (SIUF)' -Icon 'E72E' -Cat 'privacy' -Code @'
$k="HKCU:\Software\Microsoft\Siuf\Rules"; if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
Set-ItemProperty $k -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord -EA 0
OK "Feedback SIUF desactivado"
'@ -Revert 'Remove-ItemProperty "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -EA 0')
$Global:Catalog += (T -Id 'privacy-advertising-id2' -Name 'Publicidad + tracking apps' -Desc 'DEFAULT: ID publicidad y apps sugeridas | DeMente: apagar ID y contenido sugerido del store' -Icon 'E72E' -Cat 'privacy' -Code @'
Privacy-AdvertisingId | Out-Null
$k="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if(-not(Test-Path $k)){New-Item $k -Force|Out-Null}
foreach($n in @('SystemPaneSuggestionsEnabled','SoftLandingEnabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')){
  Set-ItemProperty $k -Name $n -Value 0 -Type DWord -EA 0
}
OK "Publicidad y sugerencias de apps reducidas"
'@)


# -- REGISTRO INTELIGENTE -----------------------------------------------------
$Global:Catalog += (T -Id 'reg-audit' -Name 'Registro: auditar' -Desc 'Solo lectura: Run rotos, App Paths muertos, desinstaladores huerfanos, SharedDLLs. Sin inventar miles de errores.' -Icon 'E8F1' -Cat 'clean' -Code 'Show-WDMRegAudit')
$Global:Catalog += (T -Id 'reg-clean-safe' -Name 'Registro: limpieza segura' -Desc 'Backup .reg automatico + borra solo hallazgos de bajo riesgo y huerfanos claros. Nunca Services/SAM/Classes a ciegas.' -Icon 'E8F1' -Cat 'clean' -Risk 'care' -Code 'Clear-WDMRegSafe')
$Global:Catalog += (T -Id 'reg-restore' -Name 'Registro: restaurar backup' -Desc 'Importa el .reg mas reciente de Documents\DeMente\backups\registry' -Icon 'E72C' -Cat 'clean' -Code 'Restore-WDMRegLastBackup')
$Global:Catalog += (T -Id 'info-full-checkup' -Name 'Revision completa del sistema' -Desc 'Mapa unico estilo SystemWorks: hardware, espacio, inicio, registro, uptime. Honestidad antes que puntaje magico.' -Icon 'E9D9' -Cat 'info' -Code 'Show-WDMFullCheckup')

# -- CATEGORIAS ----------------------------------------------------------------
$Global:Cats = @(
    [pscustomobject]@{Key='salud';    Nombre='Salud';        Sub='¿Cómo está realmente tu PC? Escaneo inicial'; Icon='E95E'}
    [pscustomobject]@{Key='clean';    Nombre='Limpieza';     Sub='Temporales, caches, apps y registro inteligente'; Icon='E74D'}
    [pscustomobject]@{Key='perf';     Nombre='Rendimiento';  Sub='Optimizaciones del núcleo y la red'; Icon='E945'}
    [pscustomobject]@{Key='sec';      Nombre='Seguridad';    Sub='Defender, firewall, YARA y transparencia del sistema'; Icon='EA18'}
    [pscustomobject]@{Key='privacy';  Nombre='Privacidad';   Sub='Windows 10/11: estado y mejora'; Icon='E72E'}
    [pscustomobject]@{Key='repair';   Nombre='Reparación';   Sub='SFC, DISM, CHKDSK, WMI y red'; Icon='E90F'}
    [pscustomobject]@{Key='tools';    Nombre='Herramientas'; Sub='Autoruns, Sysinternals, NVClean y utilidades de terceros'; Icon='E74C'}
    [pscustomobject]@{Key='info';     Nombre='Información';  Sub='Hardware, sistema y revisión completa'; Icon='E946'}
)

# -- CONFIGURACION PERSISTENTE ---------------------------------------------------
# La seleccion de herramientas es temporal y siempre explicita. Solo se conserva la preferencia de punto de restauracion.
$Global:WDMConfigFile = Join-Path $Global:WDMHome 'configuracion.json'
$Global:CargandoConfig = $false
$Global:ConfigCargada = $false

function Save-WDMConfig {
    if ($Global:CargandoConfig) { return }
    try {
        $obj = [pscustomobject]@{
            Version = '1.0.0.1'
            UltimaActualizacion = (Get-Date).ToString('s')
            HerramientasSeleccionadas = @()
            PuntoRestauracion = [bool]$ChkRestore.IsChecked
        }
        $obj | ConvertTo-Json -Depth 4 | Set-Content -Path $Global:WDMConfigFile -Encoding UTF8
    } catch {
        # La persistencia nunca debe impedir el uso de DeMente.
    }
}

function Load-WDMConfig {
    if (-not (Test-Path $Global:WDMConfigFile)) { return $false }
    try {
        $p = Get-Content $Global:WDMConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $ids = @($p.HerramientasSeleccionadas)
        $Global:CargandoConfig = $true
        foreach ($c in $Global:Cards) { $c.IsChecked = ($ids -contains $c.Uid) }
        if ($null -ne $p.PuntoRestauracion) { $ChkRestore.IsChecked = [bool]$p.PuntoRestauracion }
        $Global:CargandoConfig = $false
        $Global:ConfigCargada = $true
        Update-Counter
        return $true
    } catch {
        $Global:CargandoConfig = $false
        return $false
    }
}

function Get-InitialRecommendedIds {
    # En el primer arranque solo marcamos cambios que podemos demostrar como pendientes.
    # Si Windows no expone un valor de registro, lo tratamos como "no comprobado" y no
    # recomendamos tocarlo automáticamente. Así evitamos marcar como pendientes cosas
    # que ya están correctamente configuradas.
    $ids = New-Object System.Collections.Generic.List[string]
    $d = $Global:Diagnostico
    if (-not $d) { return @() }

    $wps = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
    $idealWps = if ($d.CPUCores -le 2) { 18 } elseif ($d.CPUCores -le 4) { 26 } else { 38 }
    if ($null -ne $wps -and -not (Test-RegDwordEq $wps $idealWps)) { [void]$ids.Add('perf-priority') }

    $ntfs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
    if ($null -ne $ntfs -and -not (Test-NtfsOptimized $ntfs)) { [void]$ids.Add('perf-ntfs') }

    $nt = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
    if ($null -ne $nt -and -not (Test-RegDwordEq $nt -1)) { [void]$ids.Add('perf-network-throttle') }

    $vfx = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
    if ($null -ne $vfx -and -not (Test-RegDwordEq $vfx 2)) { [void]$ids.Add('perf-visual') }

    $sr = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
    $idealSr = if ($d.CPUCores -le 4) { 10 } else { 0 }
    if ($null -ne $sr -and -not (Test-RegDwordEq $sr $idealSr)) { [void]$ids.Add('perf-systemresp') }

    if ($d.RAMTotalGB -ge 8) {
        $paging = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive'
        if ($null -ne $paging -and -not (Test-RegDwordEq $paging 1)) { [void]$ids.Add('perf-paging') }
    }

    $prefIdeal = Get-IdealPrefetcher -SSD ([bool]$d.TieneSSD)
    $prefActual = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher'
    if ($null -ne $prefActual -and -not (Test-RegDwordEq $prefActual $prefIdeal)) { [void]$ids.Add('perf-prefetcher') }

    return @($ids | Select-Object -Unique)
}

function Get-WDMAppliedState {
    # Devuelve un hashtable Id -> $true/$false indicando si el valor actual de Windows
    # YA coincide con lo que DeMente propone para ese tweak. Si no podemos comprobarlo
    # con certeza, el Id directamente no aparece en el hashtable (no se toca).
    $ok = @{}
    $d = $Global:Diagnostico
    if ($d) {
        $wps = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
        $idealWps = if ($d.CPUCores -le 2) { 18 } elseif ($d.CPUCores -le 4) { 26 } else { 38 }
        if ($null -ne $wps) { $ok['perf-priority'] = (Test-RegDwordEq $wps $idealWps) }

        $ntfs = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate'
        if ($null -ne $ntfs) { $ok['perf-ntfs'] = (Test-NtfsOptimized $ntfs) }

        $nt = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
        if ($null -ne $nt) { $ok['perf-network-throttle'] = (Test-RegDwordEq $nt -1) }

        $vfx = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
        if ($null -ne $vfx) { $ok['perf-visual'] = (Test-RegDwordEq $vfx 2) }

        $sr = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness'
        $idealSr = if ($d.CPUCores -le 4) { 10 } else { 0 }
        if ($null -ne $sr) { $ok['perf-systemresp'] = (Test-RegDwordEq $sr $idealSr) }

        if ($d.RAMTotalGB -ge 8) {
            $paging = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive'
            if ($null -ne $paging) { $ok['perf-paging'] = (Test-RegDwordEq $paging 1) }
        }

        $prefActual = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher'
        if ($null -ne $prefActual) {
            $prefIdeal = Get-IdealPrefetcher -SSD ([bool]$d.TieneSSD)
            $ok['perf-prefetcher'] = (Test-RegDwordEq $prefActual $prefIdeal)
        }

        $menu = Get-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
        if ($null -ne $menu) { $ok['perf-menu'] = (Test-RegDwordEq $menu 0) }

        $expl = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'SeparateProcess'
        if ($null -ne $expl) { $ok['perf-explorer'] = (Test-RegDwordEq $expl 1) }

        $hib = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
        if ($null -ne $hib) { $ok['perf-hibernacion'] = (Test-RegDwordEq $hib 0) }

        $qos = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' 'NonBestEffortLimit'
        if ($null -ne $qos) { $ok['perf-qos'] = (Test-RegDwordEq $qos 0) }

        try {
            $sysmain = Get-Service -Name 'SysMain' -EA Stop
            if ($d.TieneSSD -or $d.RAMTotalGB -lt 6) { $ok['perf-superfetch'] = ($sysmain.StartType -eq 'Disabled') }
            else { $ok['perf-superfetch'] = $true }
        } catch { }

        try {
            $wsearch = Get-Service -Name 'WSearch' -EA Stop
            if ($d.TieneSSD) { $ok['perf-indexacion'] = $true }
            else { $ok['perf-indexacion'] = ($wsearch.StartType -eq 'Disabled') }
        } catch { }

        $svcTimeout = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout'
        $appTimeout = Get-RegValue 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout'
        $hungTimeout = Get-RegValue 'HKCU:\Control Panel\Desktop' 'HungAppTimeout'
        $autoEnd = Get-RegValue 'HKCU:\Control Panel\Desktop' 'AutoEndTasks'
        if ($null -ne $svcTimeout -and $null -ne $appTimeout -and $null -ne $hungTimeout -and $null -ne $autoEnd) {
            $ok['perf-shutdown'] = ((Test-RegDwordEq $svcTimeout 5000) -and (Test-RegDwordEq $appTimeout 3000) -and (Test-RegDwordEq $hungTimeout 3000) -and (Test-RegDwordEq $autoEnd 1))
        }
    }

    foreach ($p in Get-WDMPrivacyState) { $ok[$p.Id] = [bool]$p.Aplicado }

    return $ok
}

function Sync-SelectionWithDiagnosis {
    # La seleccion guardada representa acciones pendientes, no una lista de preferencias
    # permanentes. Desmarcamos unicamente lo que el diagnostico confirma ya aplicado,
    # para no volver a ejecutar algo que Windows ya tiene en el valor propuesto.
    if (-not $Global:Cards) { return }
    $ok = Get-WDMAppliedState
    $changed = $false
    $Global:CargandoConfig = $true
    try {
        foreach ($c in $Global:Cards) {
            $t = $Global:ToolIndex[$c.Uid]
            if (-not $t) { continue }
            $yaAplicado = ($ok.ContainsKey($c.Uid) -and $ok[$c.Uid])
            if ($c.IsChecked -and $yaAplicado) { $c.IsChecked = $false; $changed = $true }
            if ($yaAplicado) {
                $c.Foreground = Brush 'AccentGreen'
                try {
                    $sp = $c.Content
                    if ($sp -is [System.Windows.Controls.Panel] -and $sp.Children.Count -gt 0) {
                        $sp.Children[0].Text = "✓ $($t.Name)"
                    }
                } catch { }
                try {
                    if ($c.ToolTip -is [System.Windows.Controls.ToolTip]) {
                        $c.ToolTip.Content = "$($t.Desc)`n`nYa aplicado: el valor actual coincide con la propuesta DeMente."
                    } else { $c.ToolTip = "$($t.Desc)`n`nYa aplicado." }
                } catch { }
            }
            elseif ($ok.ContainsKey($c.Uid)) {
                $c.Foreground = Brush 'AccentBlue'
                try {
                    $sp = $c.Content
                    if ($sp -is [System.Windows.Controls.Panel] -and $sp.Children.Count -gt 0) {
                        $sp.Children[0].Text = [string]$t.Name
                    }
                } catch { }
                try {
                    if ($c.ToolTip -is [System.Windows.Controls.ToolTip]) { $c.ToolTip.Content = $t.Desc }
                    else { $c.ToolTip = [string]$t.Desc }
                } catch { }
            }
        }
    }
    finally { $Global:CargandoConfig = $false }
    if ($changed) { Update-Counter; Save-WDMConfig }
}


# -- MODO CONSOLA --------------------------------------------------------------
if ($ListTools) {
    Write-Host ""
    Write-Host "+==============================================================================+" -ForegroundColor Cyan
    Write-Host "|                         DeMente - v1.0.0.1                                     |" -ForegroundColor Cyan
    Write-Host "|                       Ayudarnos es la unica opcion                            |" -ForegroundColor Cyan
    Write-Host "+==============================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  TOTAL DE HERRAMIENTAS: $($Global:Catalog.Count)" -ForegroundColor Green
    foreach ($c in $Global:Cats) {
        $n = ($Global:Catalog | Where-Object Cat -eq $c.Key).Count
        Write-Host ""; Write-Host ("  == {0} ==" -f $c.Nombre.ToUpper()) -ForegroundColor Cyan
        Write-Host ("      {0} herramientas" -f $n) -ForegroundColor Gray
        $Global:Catalog | Where-Object Cat -eq $c.Key | ForEach-Object {
            $marca = if ($_.Risk -eq 'danger') { '!' } elseif ($_.Revert) { '<-' } else { ' ' }
            Write-Host ("    {0,-32} {1} {2}" -f $_.Id, $_.Name, $marca) -ForegroundColor Gray
        }
    }
    Write-Host ""; Write-Host "  Uso:" -ForegroundColor Yellow
    Write-Host "    .\DeMente.ps1 -RunTool <id>[,<id2>]" -ForegroundColor Gray
    Write-Host "    .\DeMente.ps1 -ListTools" -ForegroundColor Gray
    Write-Host "    .\DeMente.ps1 -SelfTest" -ForegroundColor Gray
    exit 0
}

if ($RunTool) {
    $ids = @($RunTool | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($id in $ids) {
        $t = $Global:ToolIndex[$id]
        if (-not $t) { Write-Host "[X] No existe la herramienta '$id'. Usa -ListTools." -ForegroundColor Red; continue }
        Write-Host ""; Write-Host ("=" * 78) -ForegroundColor Cyan
        Write-Host "  $($t.Name)" -ForegroundColor Cyan; Write-Host ("=" * 78) -ForegroundColor Cyan
        $f = Join-Path $Global:WDMTmp ("cli_" + $t.Id + ".ps1")
        ($Global:Prelude + "`r`n`r`n" + $t.Code) | Set-Content $f -Encoding UTF8
        & $Global:PsExe -NoProfile -ExecutionPolicy Bypass -File $f
        Remove-Item $f -Force -EA 0
    }
    exit 0
}

if ($SelfTest) {
    $fail = 0
    function ST-Ok($m) { Write-Host "[OK] $m" -ForegroundColor Green }
    function ST-Fail($m) { Write-Host "[X] $m" -ForegroundColor Red; $script:fail++ }
    Write-Host "DeMente SelfTest v1.0.0.1" -ForegroundColor Cyan
    # Catalogo
    if ($Global:Catalog.Count -lt 50) { ST-Fail "Catalogo demasiado chico: $($Global:Catalog.Count)" } else { ST-Ok "Catalogo: $($Global:Catalog.Count) herramientas" }
    $ids = @($Global:Catalog | ForEach-Object { $_.Id })
    $dup = @($ids | Group-Object | Where-Object Count -gt 1)
    if ($dup.Count -gt 0) { ST-Fail ("IDs duplicados: " + (($dup | Select-Object -First 5).Name -join ', ')) } else { ST-Ok "IDs unicos" }
    $empty = @($Global:Catalog | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Code) })
    if ($empty.Count -gt 0) { ST-Fail "Herramientas sin Code: $($empty.Count)" } else { ST-Ok "Todas tienen Code" }
    # Perfiles
    foreach ($pname in @('ProfileEsencial','ProfileCompleto')) {
        $p = Get-Variable -Name $pname -Scope Global -EA 0
        if (-not $p) { ST-Fail "$pname ausente"; continue }
        $missing = @()
        foreach ($cat in @($p.Value.Keys)) {
            foreach ($id in @($p.Value[$cat])) {
                if ($id -and -not ($ids -contains $id)) { $missing += $id }
            }
        }
        if ($missing.Count -gt 0) { ST-Fail "$pname IDs inexistentes: $($missing -join ', ')" }
        else { ST-Ok "$pname coherente" }
    }
    # Coherencia Defender
    $def = $Global:Catalog | Where-Object Id -eq 'sec-defender-scan' | Select-Object -First 1
    if ($def -and $def.Name -match 'completo|todo el equipo' -and $def.Code -match 'QuickScan') {
        ST-Fail "Defender: nombre promete completo pero codigo es QuickScan"
    } else { ST-Ok "Defender: nombre alineado a QuickScan" }
    # Temp no debe mencionar SoftwareDistribution en Code de clean-temp
    $ct = $Global:Catalog | Where-Object Id -eq 'clean-temp' | Select-Object -First 1
    if ($ct -and $ct.Code -match 'SoftwareDistribution|Logs\\CBS|WER') {
        ST-Fail "clean-temp incluye rutas fuera de TEMP"
    } else { ST-Ok "clean-temp alcance TEMP" }
    # Prelude presente
    if (-not $Global:Prelude -or $Global:Prelude.Length -lt 1000) { ST-Fail "Prelude ausente o corto" } else { ST-Ok "Prelude cargado ($([int]($Global:Prelude.Length/1KB)) KB)" }
    Write-Host ""
    if ($fail -eq 0) {
        Write-Host "[selftest] RESULTADO: $fail fallos  -  OK" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[selftest] RESULTADO: $fail fallo(s)" -ForegroundColor Red
        exit 1
    }
}

if ($NoGUI) {
    Write-Host "DeMente - Modo Consola" -ForegroundColor Cyan
    Write-Host "Usa -ListTools para ver el catalogo" -ForegroundColor Yellow
    Write-Host "Usa -RunTool <id>[,<id2>] para ejecutar herramientas" -ForegroundColor Yellow
    Write-Host "Total: $($Global:Catalog.Count) herramientas" -ForegroundColor Green
    exit 0
}

# -- XAML ----------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="MainWindow" Title="DeMente - v1.0.0.1" Height="820" Width="1340" MinHeight="640" MinWidth="1080"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI">

  <Window.Resources>
    <SolidColorBrush x:Key="Zinc950" Color="#09090b"/>
    <SolidColorBrush x:Key="Zinc900" Color="#18181b"/>
    <SolidColorBrush x:Key="Zinc850" Color="#1f1f22"/>
    <SolidColorBrush x:Key="Zinc800" Color="#27272a"/>
    <SolidColorBrush x:Key="Zinc700" Color="#3f3f46"/>
    <SolidColorBrush x:Key="Zinc500" Color="#71717a"/>
    <SolidColorBrush x:Key="Zinc400" Color="#a1a1aa"/>
    <SolidColorBrush x:Key="Zinc200" Color="#e4e4e7"/>
    <SolidColorBrush x:Key="AccentBlue" Color="#3b82f6"/>
    <SolidColorBrush x:Key="AccentBlueHover" Color="#2563eb"/>
    <SolidColorBrush x:Key="AccentRed" Color="#ef4444"/>
    <SolidColorBrush x:Key="AccentYellow" Color="#eab308"/>
    <SolidColorBrush x:Key="AccentGreen" Color="#10b981"/>
    <SolidColorBrush x:Key="AccentPurple" Color="#a855f7"/>
    <SolidColorBrush x:Key="AccentOrange" Color="#f97316"/>
    <SolidColorBrush x:Key="AccentCyan" Color="#06b6d4"/>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#18181b"/>
      <Setter Property="Foreground" Value="#e4e4e7"/>
      <Setter Property="BorderBrush" Value="#3f3f46"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,9"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="MaxWidth" Value="340"/>
      <Setter Property="HasDropShadow" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToolTip">
            <Border Background="#18181b" BorderBrush="#3f3f46" BorderThickness="1" CornerRadius="8" Padding="12,9" MaxWidth="340">
              <ContentPresenter/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SidebarBtn" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource Zinc400}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height" Value="42"/>
      <Setter Property="Margin" Value="0,1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{StaticResource Zinc850}"/>
                <Setter Property="Foreground" Value="{StaticResource Zinc200}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{StaticResource Zinc800}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostBtn" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{StaticResource Zinc400}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="Background" Value="{StaticResource Zinc900}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Zinc800}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Zinc850}"/>
                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Zinc500}"/>
                <Setter Property="Foreground" Value="{StaticResource Zinc200}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Zinc800}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Width" Value="42"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Foreground" Value="{StaticResource Zinc500}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource Zinc800}"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ToolCard" TargetType="CheckBox">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="Width" Value="320"/>
      <Setter Property="MinHeight" Value="100"/>
      <Setter Property="MaxHeight" Value="130"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="bd" Background="{StaticResource Zinc900}" BorderBrush="{StaticResource Zinc800}" BorderThickness="1" CornerRadius="14" Padding="14,12" ClipToBounds="True">
              <Grid ClipToBounds="True">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*" MinWidth="0"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid Grid.Column="0" Width="42" Height="42" Margin="0,0,12,0" VerticalAlignment="Top">
                  <Border CornerRadius="11" Background="{TemplateBinding Foreground}" Opacity="0.14"/>
                  <TextBlock Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="Segoe MDL2 Assets" FontSize="18"
                             Foreground="{TemplateBinding Foreground}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                </Grid>
                <!-- ContentPresenter: el texto no debe salirse del cuadro (ClipToBounds + MinWidth 0) -->
                <ContentPresenter Grid.Column="1" Content="{TemplateBinding Content}" VerticalAlignment="Top" RecognizesAccessKey="True" ClipToBounds="True"/>
                <Border Grid.Column="2" x:Name="tr" Width="42" Height="24" CornerRadius="12" Background="{StaticResource Zinc800}"
                        BorderBrush="{StaticResource Zinc700}" BorderThickness="1" VerticalAlignment="Top" Margin="10,2,0,0">
                  <Ellipse x:Name="dot" Width="16" Height="16" Fill="{StaticResource Zinc500}" HorizontalAlignment="Left" Margin="3,0,0,0" VerticalAlignment="Center">
                    <Ellipse.RenderTransform><TranslateTransform X="0"/></Ellipse.RenderTransform>
                  </Ellipse>
                </Border>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="{StaticResource Zinc850}"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource Zinc700}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource AccentBlue}"/>
                <Setter TargetName="bd" Property="Background" Value="#142563eb"/>
                <Setter TargetName="tr" Property="Background" Value="{StaticResource AccentBlue}"/>
                <Setter TargetName="tr" Property="BorderThickness" Value="0"/>
                <Setter TargetName="dot" Property="Fill" Value="White"/>
                <Setter TargetName="dot" Property="RenderTransform">
                  <Setter.Value><TranslateTransform X="18"/></Setter.Value>
                </Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- CHECKBOX OSCURO: evita el aspecto nativo blanco/azul de Windows -->
    <Style x:Key="RestoreCheck" TargetType="CheckBox">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{StaticResource Zinc400}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Border x:Name="box" Width="16" Height="16" CornerRadius="4"
                      Background="{StaticResource Zinc900}" BorderBrush="{StaticResource Zinc700}" BorderThickness="1" Margin="0,0,8,0">
                <TextBlock x:Name="mark" Text="✓" FontSize="11" FontWeight="Bold"
                           Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="box" Property="BorderBrush" Value="{StaticResource Zinc500}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="{StaticResource AccentBlue}"/>
                <Setter TargetName="box" Property="BorderBrush" Value="{StaticResource AccentBlue}"/>
                <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="box" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="StatCard" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Zinc900}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Zinc800}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18,15"/>
      <Setter Property="Margin" Value="0,0,12,12"/>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Zinc950}" CornerRadius="12" BorderBrush="{StaticResource Zinc800}" BorderThickness="1">
    <Grid>
      <Border CornerRadius="12" Opacity="0.45">
        <Border.Background>
          <DrawingBrush Viewport="0,0,34,34" ViewportUnits="Absolute" TileMode="Tile">
            <DrawingBrush.Drawing>
              <GeometryDrawing>
                <GeometryDrawing.Pen><Pen Brush="#0AFFFFFF" Thickness="1"/></GeometryDrawing.Pen>
                <GeometryDrawing.Geometry>
                  <GeometryGroup>
                    <LineGeometry StartPoint="0,0" EndPoint="34,0"/>
                    <LineGeometry StartPoint="0,0" EndPoint="0,34"/>
                  </GeometryGroup>
                </GeometryDrawing.Geometry>
              </GeometryDrawing>
            </DrawingBrush.Drawing>
          </DrawingBrush>
        </Border.Background>
      </Border>

      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="252"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- SIDEBAR -->
        <Border Grid.Column="0" Background="#F218181b" CornerRadius="12,0,0,12" BorderBrush="{StaticResource Zinc800}" BorderThickness="0,0,1,0">
          <Grid Margin="0,18,0,16">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="20,0,20,20">
              <Border Width="38" Height="38" Background="{StaticResource Zinc950}" BorderBrush="{StaticResource Zinc800}" BorderThickness="1" CornerRadius="9" Margin="0,0,11,0">
                <TextBlock Text="DM" Foreground="{StaticResource AccentBlue}" FontWeight="Bold" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="DEMENTE" Foreground="White" FontSize="17" FontWeight="Bold"/>
                  <TextBlock Text="v1.0.0.1" Foreground="{StaticResource AccentBlue}" FontSize="14" FontWeight="Bold" Margin="6,0,0,0"/>
                </StackPanel>
                <TextBlock Text="Ayudarnos es la unica opcion" Foreground="{StaticResource Zinc500}" FontSize="9.5" FontWeight="Bold"/>
              </StackPanel>
            </StackPanel>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="10,0">
              <StackPanel x:Name="NavPanel"/>
            </ScrollViewer>

            <StackPanel Grid.Row="2" Margin="14,10,14,0">
              <Border x:Name="AdminBadge" Background="#1410b981" CornerRadius="8" Padding="10,7" Margin="0,0,0,8">
                <StackPanel Orientation="Horizontal">
                  <TextBlock x:Name="AdminIcon" Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource AccentGreen}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="AdminTxt" Text="Modo administrador" Foreground="{StaticResource Zinc400}" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
              </Border>
              <Button x:Name="BtnDocs" Style="{StaticResource SidebarBtn}" Height="36">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE82D;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{StaticResource Zinc500}" Width="28" TextAlignment="Center"/>
                  <TextBlock Text="Documentacion" VerticalAlignment="Center" FontSize="12.5"/>
                </StackPanel>
              </Button>
            </StackPanel>
          </Grid>
        </Border>

        <!-- CONTENIDO -->
        <Grid Grid.Column="1">
          <Grid.RowDefinitions>
            <RowDefinition Height="62"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="76"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" x:Name="TitleBar" Background="#E609090b" BorderBrush="{StaticResource Zinc800}" BorderThickness="0,0,0,1">
            <Grid Margin="26,0,14,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock x:Name="LblTitle" Text="Dashboard" FontSize="19" FontWeight="Bold" Foreground="White"/>
                <TextBlock x:Name="LblSub" Text="Centro de comando" FontSize="12.5" Foreground="{StaticResource Zinc500}" VerticalAlignment="Bottom" Margin="10,0,0,3"/>
              </StackPanel>

              <Border Grid.Column="1" x:Name="SearchBox" Background="{StaticResource Zinc900}" BorderBrush="{StaticResource Zinc800}" BorderThickness="1"
                      CornerRadius="8" Height="34" Margin="28,0,16,0" MaxWidth="420" HorizontalAlignment="Right" Visibility="Collapsed">
                <Grid Margin="10,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource Zinc500}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <Grid Grid.Column="1">
                    <TextBlock x:Name="SearchHint" Text="Buscar en todas las herramientas... (Ctrl+F)" Foreground="{StaticResource Zinc700}" FontSize="12.5" VerticalAlignment="Center" IsHitTestVisible="False"/>
                    <TextBox x:Name="SearchInput" Background="Transparent" Foreground="{StaticResource Zinc200}" BorderThickness="0" FontSize="12.5"
                             VerticalContentAlignment="Center" CaretBrush="{StaticResource AccentBlue}"/>
                  </Grid>
                  <Button Grid.Column="2" x:Name="BtnSearchClear" Style="{StaticResource WinBtn}" Width="24" Height="24" Content="&#xE711;" Visibility="Collapsed"/>
                </Grid>
              </Border>

              <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnMin" Style="{StaticResource WinBtn}" Content="&#xE921;"/>
                <Button x:Name="BtnMax" Style="{StaticResource WinBtn}" Content="&#xE922;"/>
                <Button x:Name="BtnClose" Style="{StaticResource WinBtn}" Content="&#xE8BB;"/>
              </StackPanel>
            </Grid>
          </Border>

          <Grid Grid.Row="1">

            <!-- VISTA: DASHBOARD / DIAGNOSTICO -->
            <ScrollViewer x:Name="ViewDash" VerticalScrollBarVisibility="Auto" Padding="26,20,20,10">
              <StackPanel Margin="0,0,8,20">
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                  <TextBlock Text="&#xE80F;" FontFamily="Segoe MDL2 Assets" FontSize="28" Foreground="{StaticResource AccentBlue}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                  <StackPanel>
                    <TextBlock x:Name="DashHello" Text="Hola" FontSize="28" FontWeight="Bold" Foreground="White"/>
                    <TextBlock x:Name="DashSub" Text="Primero diagnosticamos. Despues vos decidís." FontSize="13" Foreground="{StaticResource Zinc400}" Margin="0,2,0,0"/>
                  </StackPanel>
                </StackPanel>

                <Grid Margin="0,12,0,14" Visibility="Collapsed">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Style="{StaticResource StatCard}" Margin="0,0,12,0" BorderBrush="{StaticResource AccentBlue}" BorderThickness="1">
                    <StackPanel HorizontalAlignment="Center">
                      <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="22" Foreground="{StaticResource AccentBlue}" HorizontalAlignment="Center"/>
                      <TextBlock Text="HALLAZGOS" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}" HorizontalAlignment="Center" Margin="0,6,0,0"/>
                      <TextBlock x:Name="DashScore" Text="--" FontSize="44" FontWeight="Bold" Foreground="{StaticResource AccentBlue}" HorizontalAlignment="Center" Margin="0,2,0,0"/>
                      <TextBlock x:Name="DashGrade" Text="Analizando..." FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Zinc200}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
                    </StackPanel>
                  </Border>
                  <Border Grid.Column="1" Style="{StaticResource StatCard}" Margin="0">
                    <StackPanel>
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE8F1;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{StaticResource Zinc500}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Text="QUE ENCONTRAMOS" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}" VerticalAlignment="Center"/>
                      </StackPanel>
                      <TextBlock x:Name="DashFinding" Text="Analizando el equipo..." FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Zinc200}" Margin="0,7,0,0"/>
                      <TextBlock x:Name="DashFindingSub" Text="Comprobando seguridad, almacenamiento, errores y privacidad." FontSize="11.5" Foreground="{StaticResource Zinc500}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                      <TextBlock x:Name="DashDiagDetail" Text="Preparando..." FontSize="11" Foreground="{StaticResource Zinc400}" Margin="0,7,0,0" TextWrapping="Wrap" MaxHeight="72"/>
                      <ProgressBar x:Name="DashDiagBar" Height="5" Maximum="100" Value="0" Foreground="{StaticResource AccentBlue}" Background="{StaticResource Zinc800}" BorderThickness="0" Margin="0,10,0,0"/>
                      <TextBlock x:Name="DashDiagTime" Text="" FontSize="10" Foreground="{StaticResource Zinc700}" Margin="0,5,0,0"/>
                      <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                        <Button x:Name="BtnDiagNow" Style="{StaticResource GhostBtn}" Content="Analizar ahora" HorizontalAlignment="Left"/>
                        <Button x:Name="BtnPorqueLenta" Style="{StaticResource GhostBtn}" Content="¿Por qué está lenta?" HorizontalAlignment="Left" Margin="8,0,0,0"/>
                      </StackPanel>
                    </StackPanel>
                  </Border>
                </Grid>

                <StackPanel Orientation="Horizontal" Margin="0,4,0,10">
                  <TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{StaticResource AccentBlue}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="CENTRO DE ACCION" FontSize="11" FontWeight="Bold" Foreground="{StaticResource Zinc400}" VerticalAlignment="Center"/>
                </StackPanel>
                <Border x:Name="SaludSection" Style="{StaticResource StatCard}" Margin="0,0,0,12" BorderBrush="{StaticResource AccentBlue}" BorderThickness="2">
                  <StackPanel>
                    <Grid Margin="0,0,0,12">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="0" Text="&#xE95E;" FontFamily="Segoe MDL2 Assets" FontSize="28" Foreground="{StaticResource AccentBlue}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <StackPanel Grid.Column="1">
                        <TextBlock x:Name="SaludTitulo" Text="Salud del sistema" FontSize="21" FontWeight="Bold" Foreground="White"/>
                        <TextBlock x:Name="SaludSubtitulo" Text="El estado real de tu PC, sin puntajes mágicos." FontSize="12" Foreground="{StaticResource Zinc400}" Margin="0,2,0,0"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="BtnRepararSalud" Style="{StaticResource GhostBtn}" Content="Reparar recomendado" Height="36" Padding="14,0"/>
                        <Button x:Name="BtnVerInformeSalud" Style="{StaticResource GhostBtn}" Content="Ver informe completo" Height="36" Padding="14,0" Margin="8,0,0,0"/>
                      </StackPanel>
                    </Grid>
                    <Border Background="#1A2563EB" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
                      <StackPanel>
                        <TextBlock x:Name="SaludEstadoGeneral" Text="Analizando..." FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource AccentBlue}" TextWrapping="Wrap"/>
                        <TextBlock x:Name="SaludHallazgoPrincipal" Text="Preparando el informe de salud..." FontSize="11.5" Foreground="{StaticResource Zinc400}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                      </StackPanel>
                    </Border>
                    <TextBlock Text="DETALLE POR ÁREA" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}" Margin="0,0,0,6"/>
                    <Grid x:Name="SaludGrid">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="145"/><ColumnDefinition Width="92"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    </Grid>
                  </StackPanel>
                </Border> 

                <StackPanel Orientation="Horizontal" Margin="0,10,0,10">
                  <TextBlock Text="&#xE9D2;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{StaticResource Zinc500}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="ESTADO EN VIVO" FontSize="11" FontWeight="Bold" Foreground="{StaticResource Zinc400}" VerticalAlignment="Center"/>
                </StackPanel>
                <UniformGrid x:Name="StatGrid" Columns="4">
                  <Border Style="{StaticResource StatCard}">
                    <StackPanel>
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE950;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource AccentBlue}" Margin="0,0,6,0"/>
                        <TextBlock Text="PROCESADOR" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}"/>
                      </StackPanel>
                      <TextBlock x:Name="StCpu" Text="--%" FontSize="26" FontWeight="Bold" Foreground="{StaticResource AccentBlue}" Margin="0,4,0,0"/>
                      <ProgressBar x:Name="BarCpu" Height="4" Maximum="100" Value="0" Foreground="{StaticResource AccentBlue}" Background="{StaticResource Zinc800}" BorderThickness="0" Margin="0,6,0,0"/>
                      <TextBlock x:Name="StCpuName" Text="" FontSize="10" Foreground="{StaticResource Zinc500}" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource StatCard}">
                    <StackPanel>
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE9F9;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource AccentPurple}" Margin="0,0,6,0"/>
                        <TextBlock Text="MEMORIA" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}"/>
                      </StackPanel>
                      <TextBlock x:Name="StRam" Text="--%" FontSize="26" FontWeight="Bold" Foreground="{StaticResource AccentPurple}" Margin="0,4,0,0"/>
                      <ProgressBar x:Name="BarRam" Height="4" Maximum="100" Value="0" Foreground="{StaticResource AccentPurple}" Background="{StaticResource Zinc800}" BorderThickness="0" Margin="0,6,0,0"/>
                      <TextBlock x:Name="StRamTxt" Text="" FontSize="10" Foreground="{StaticResource Zinc500}" Margin="0,6,0,0"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource StatCard}">
                    <StackPanel>
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xEDA2;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource AccentGreen}" Margin="0,0,6,0"/>
                        <TextBlock Text="DISCO" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}"/>
                      </StackPanel>
                      <TextBlock x:Name="StDisk" Text="--%" FontSize="26" FontWeight="Bold" Foreground="{StaticResource AccentGreen}" Margin="0,4,0,0"/>
                      <ProgressBar x:Name="BarDisk" Height="4" Maximum="100" Value="0" Foreground="{StaticResource AccentGreen}" Background="{StaticResource Zinc800}" BorderThickness="0" Margin="0,6,0,0"/>
                      <TextBlock x:Name="StDiskTxt" Text="" FontSize="10" Foreground="{StaticResource Zinc500}" Margin="0,6,0,0"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource StatCard}">
                    <StackPanel>
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE823;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource AccentOrange}" Margin="0,0,6,0"/>
                        <TextBlock Text="ENCENDIDO" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Zinc500}"/>
                      </StackPanel>
                      <TextBlock x:Name="StUp" Text="--" FontSize="26" FontWeight="Bold" Foreground="{StaticResource AccentOrange}" Margin="0,4,0,0"/>
                      <TextBlock x:Name="StUpTxt" Text="" FontSize="10" Foreground="{StaticResource Zinc500}" Margin="0,12,0,0"/>
                    </StackPanel>
                  </Border>
                </UniformGrid>

                <StackPanel Orientation="Horizontal" Margin="0,16,0,10">
                  <TextBlock Text="&#xE8FB;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{StaticResource AccentGreen}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="MEJORAS SUGERIDAS" FontSize="11" FontWeight="Bold" Foreground="{StaticResource Zinc400}" VerticalAlignment="Center"/>
                </StackPanel>
                <Border Style="{StaticResource StatCard}" Margin="0,0,12,12">
                  <StackPanel>
                    <TextBlock x:Name="DashImproveTitle" Text="Analizando..." FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Zinc200}"/>
                    <TextBlock x:Name="DashImproveSub" Text="" FontSize="11.5" Foreground="{StaticResource Zinc500}" Margin="0,4,0,12" TextWrapping="Wrap"/>
                    <WrapPanel x:Name="ImprovePanel"/>
                  </StackPanel>
                </Border>

                <StackPanel Orientation="Horizontal" Margin="0,4,0,8">
                  <TextBlock Text="&#xE8B7;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{StaticResource Zinc500}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="ATAJOS" FontSize="11" FontWeight="Bold" Foreground="{StaticResource Zinc400}" VerticalAlignment="Center"/>
                </StackPanel>
                <WrapPanel x:Name="QuickPanel" Margin="0,0,0,0"/>
                <TextBlock Text="Las tarjetas grandes resumen el multiescaneo. En cada sección ves DEFAULT Windows vs propuesta DeMente, con reversion cuando existe."
                           FontSize="11" Foreground="{StaticResource Zinc700}" Margin="2,10,0,0" TextWrapping="Wrap"/>
              </StackPanel>
            </ScrollViewer>

            <!-- VISTA: CUADRICULA DE HERRAMIENTAS -->
            <Grid x:Name="ViewGrid" Visibility="Collapsed">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="26,14,26,10">
                <Button x:Name="BtnSelAll" Style="{StaticResource GhostBtn}" Content="Seleccionar todo" Margin="0,0,8,0"/>
                <Button x:Name="BtnSelNone" Style="{StaticResource GhostBtn}" Content="Limpiar seleccion" Margin="0,0,8,0"/>
                <Button x:Name="BtnRevert" Style="{StaticResource GhostBtn}" Content="Revertir seleccionados" Margin="0,0,16,0"/>
                <Border Background="{StaticResource Zinc900}" BorderBrush="{StaticResource Zinc800}" BorderThickness="1" CornerRadius="8" Padding="4,2" Margin="0,0,8,0">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Modo de esta sección:" Foreground="{StaticResource Zinc500}" FontSize="11" VerticalAlignment="Center" Margin="6,0,8,0"/>
                    <Button x:Name="BtnProfRapida" Style="{StaticResource GhostBtn}" Content="⚡ ESENCIAL" Margin="0,0,4,0" ToolTip="Lo seguro y de impacto claro. Ideal la primera vez o para alumnos."/>
                    <Button x:Name="BtnProfProfunda" Style="{StaticResource GhostBtn}" Content="🧠 COMPLETO" Margin="0,0,4,0" ToolTip="Todo lo razonable de esta seccion. Revisá antes de ejecutar."/>
                    <Button x:Name="BtnProfDefault" Style="{StaticResource GhostBtn}" Content="🪟 DEFAULT WINDOWS" Margin="0,0,4,0" ToolTip="Marca las opciones reversibles de esta seccion para restaurar el valor DEFAULT de Windows. Luego pulsa Restaurar DEFAULT / Ejecutar."/>
                  </StackPanel>
                </Border>
                <TextBlock x:Name="LblCount" Text="" Foreground="{StaticResource Zinc500}" FontSize="11.5" VerticalAlignment="Center" Margin="6,0,0,0"/>
              </StackPanel>
              <StackPanel x:Name="CleanSubTabs" Grid.Row="1" Orientation="Horizontal" Margin="26,0,26,10" Visibility="Collapsed">
                <Button x:Name="BtnCleanGeneral" Style="{StaticResource GhostBtn}" Content="🧹 Limpieza general" Margin="0,0,8,0"/>
                <Button x:Name="BtnCleanUninstall" Style="{StaticResource GhostBtn}" Content="🗑️ Desinstalar programas" Margin="0,0,8,0"/>
              </StackPanel>
              <StackPanel x:Name="PerfSubTabs" Grid.Row="1" Orientation="Horizontal" Margin="26,0,26,10" Visibility="Collapsed">
                <Button x:Name="BtnPerfGeneral" Style="{StaticResource GhostBtn}" Content="⚙️ Optimización general" Margin="0,0,8,0"/>
                <Button x:Name="BtnPerfStartup" Style="{StaticResource GhostBtn}" Content="🚀 Apps de inicio" Margin="0,0,8,0"/>
              </StackPanel>
              <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="26,0,18,10">
                <WrapPanel x:Name="CardPanel" Margin="0,0,0,20"/>
              </ScrollViewer>
            </Grid>

            <!-- VISTA: CONSOLA -->
            <Grid x:Name="ViewConsole" Visibility="Collapsed" Margin="26,14,20,10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Border Grid.Row="0" Background="{StaticResource Zinc900}" BorderBrush="{StaticResource Zinc800}" BorderThickness="1" CornerRadius="10" Padding="16,12" Margin="0,0,0,12">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock x:Name="ConTask" Text="Sin tareas en ejecucion" Foreground="White" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock x:Name="ConStatus" Text="La consola muestra la salida de cada herramienta en vivo." Foreground="{StaticResource Zinc500}" FontSize="11.5" Margin="0,3,0,0"/>
                    <ProgressBar x:Name="ConBar" Height="4" Maximum="100" Value="0" Foreground="{StaticResource AccentBlue}" Background="{StaticResource Zinc800}" BorderThickness="0" Margin="0,10,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
                    <Button x:Name="BtnConCancel" Style="{StaticResource GhostBtn}" Content="Detener" Margin="0,0,8,0" IsEnabled="False"/>
                    <Button x:Name="BtnConLog" Style="{StaticResource GhostBtn}" Content="Abrir registro" Margin="0,0,8,0"/>
                    <Button x:Name="BtnConClear" Style="{StaticResource GhostBtn}" Content="Limpiar"/>
                  </StackPanel>
                </Grid>
              </Border>

              <Border Grid.Row="1" Background="#0B0B0E" BorderBrush="{StaticResource Zinc800}" BorderThickness="1" CornerRadius="10" Padding="4">
                <RichTextBox x:Name="Con" IsReadOnly="True" Background="Transparent" Foreground="#d4d4d8" BorderThickness="0"
                             FontFamily="Cascadia Mono, Consolas, monospace" FontSize="12" VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Disabled" Padding="12,10"/>
              </Border>

              <TextBlock Grid.Row="2" x:Name="ConFoot" Text="" Foreground="{StaticResource Zinc500}" FontSize="11" Margin="4,10,0,0"/>
            </Grid>
          </Grid>

          <!-- DOCK INFERIOR -->
          <Border Grid.Row="2" Background="#E609090b" BorderBrush="{StaticResource Zinc800}" BorderThickness="0,1,0,0" Padding="26,0">
            <Grid>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
                <TextBlock Text="SELECCIONADAS" Foreground="{StaticResource Zinc500}" FontSize="10.5" FontWeight="Bold" Margin="0,0,10,0" VerticalAlignment="Center"/>
                <Border x:Name="CounterBadge" Background="{StaticResource Zinc800}" CornerRadius="12" Width="26" Height="24" Margin="0,0,18,0">
                  <TextBlock x:Name="TxtCounter" Text="0" Foreground="{StaticResource Zinc200}" FontWeight="Bold" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <Button x:Name="BtnProfSave" Style="{StaticResource GhostBtn}" Content="Guardar perfil" Margin="0,0,8,0"/>
                <Button x:Name="BtnProfLoad" Style="{StaticResource GhostBtn}" Content="Cargar perfil"/>
              </StackPanel>

              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <CheckBox x:Name="ChkRestore" Style="{StaticResource RestoreCheck}" Content="Punto de restauracion antes" Foreground="{StaticResource Zinc400}" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,18,0"/>
                <Button x:Name="BtnExecute" Width="196" Height="44" IsEnabled="False" Cursor="Hand">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Border x:Name="eb" Background="{StaticResource AccentBlue}" CornerRadius="11">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                          <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" Margin="0,0,10,0" Foreground="White" FontSize="15"/>
                          <TextBlock x:Name="et" Text="Aplicar" FontWeight="Bold" Foreground="White" FontSize="14"/>
                        </StackPanel>
                      </Border>
                      <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                          <Setter TargetName="eb" Property="Background" Value="{StaticResource AccentBlueHover}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                          <Setter TargetName="eb" Property="Background" Value="{StaticResource Zinc800}"/>
                          <Setter TargetName="et" Property="Foreground" Value="{StaticResource Zinc500}"/>
                        </Trigger>
                      </ControlTemplate.Triggers>
                    </ControlTemplate>
                  </Button.Template>
                </Button>
              </StackPanel>
            </Grid>
          </Border>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

# -- CARGAR XAML --------------------------------------------------------------
try {
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Error "Error al cargar la interfaz: $($_.Exception.Message)"
    Read-Host "ENTER para salir"
    exit 1
}

# -- REFERENCIAS A CONTROLES --------------------------------------------------
function UI($n) { return $window.FindName($n) }

$NavPanel = UI 'NavPanel';        $CardPanel = UI 'CardPanel'
$ViewDash = UI 'ViewDash';        $ViewGrid = UI 'ViewGrid';       $ViewConsole = UI 'ViewConsole'
$LblTitle = UI 'LblTitle';        $LblSub = UI 'LblSub';           $LblCount = UI 'LblCount'
$SearchBox = UI 'SearchBox';      $SearchInput = UI 'SearchInput'; $SearchHint = UI 'SearchHint'
$BtnSearchClear = UI 'BtnSearchClear'
$TxtCounter = UI 'TxtCounter';    $CounterBadge = UI 'CounterBadge'
$BtnExecute = UI 'BtnExecute';    $ChkRestore = UI 'ChkRestore'
$Con = UI 'Con';                  $ConTask = UI 'ConTask';         $ConStatus = UI 'ConStatus'
$ConBar = UI 'ConBar';            $ConFoot = UI 'ConFoot'
$CleanSubTabs = UI 'CleanSubTabs'; $BtnCleanGeneral = UI 'BtnCleanGeneral'; $BtnCleanUninstall = UI 'BtnCleanUninstall'
$PerfSubTabs = UI 'PerfSubTabs'; $BtnPerfGeneral = UI 'BtnPerfGeneral'; $BtnPerfStartup = UI 'BtnPerfStartup'
$Global:CleanSubView = 'general'
$Global:PerfSubView = 'general'
  $ImprovePanel = UI 'ImprovePanel';  $QuickPanel = UI 'QuickPanel'; $HeroGrid = UI 'HeroGrid'
  $SaludTitulo = UI 'SaludTitulo'; $SaludSubtitulo = UI 'SaludSubtitulo'
  $SaludEstadoGeneral = UI 'SaludEstadoGeneral'; $SaludHallazgoPrincipal = UI 'SaludHallazgoPrincipal'
  $SaludGrid = UI 'SaludGrid'; $BtnVerInformeSalud = UI 'BtnVerInformeSalud'; $BtnRepararSalud = UI 'BtnRepararSalud'
  $DashHello = UI 'DashHello';      $DashSub = UI 'DashSub'
$DashScore = UI 'DashScore';        $DashGrade = UI 'DashGrade'
$DashFinding = UI 'DashFinding';    $DashFindingSub = UI 'DashFindingSub'
$DashImproveTitle = UI 'DashImproveTitle'; $DashImproveSub = UI 'DashImproveSub'
$DashDiagDetail = UI 'DashDiagDetail'; $DashDiagBar = UI 'DashDiagBar'; $DashDiagTime = UI 'DashDiagTime'; $BtnDiagNow = UI 'BtnDiagNow'

$Global:Cards = @()
$Global:CurCat = 'dash'
$Global:NavBtns = @{}

function Brush($n) { return $window.Resources[$n] }
function Glyph($hex) { try { return [string][char][Convert]::ToInt32($hex, 16) } catch { return [string][char]0xE946 } }

# -- NAVEGACION LATERAL ------------------------------------------------------
function New-NavButton($key, $texto, $sub, $iconHex, $colorKey) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $window.Resources['SidebarBtn']
    $b.Uid = $key
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $ic = New-Object System.Windows.Controls.TextBlock
    $ic.Text = Glyph $iconHex
    $ic.FontFamily = 'Segoe MDL2 Assets'
    $ic.FontSize = 15
    $ic.Width = 28
    $ic.TextAlignment = 'Center'
    $ic.Foreground = Brush $colorKey
    $ic.VerticalAlignment = 'Center'
    $tx = New-Object System.Windows.Controls.TextBlock
    $tx.Text = $texto
    $tx.FontSize = 13
    $tx.FontWeight = 'Medium'
    $tx.VerticalAlignment = 'Center'
    $tx.Foreground = Brush 'Zinc400'
    $cnt = New-Object System.Windows.Controls.TextBlock
    $cnt.FontSize = 10.5
    $cnt.Margin = '8,0,0,0'
    $cnt.VerticalAlignment = 'Center'
    $cnt.Foreground = Brush 'Zinc700'
    if ($sub) { $cnt.Text = $sub }
    $sp.Children.Add($ic) | Out-Null
    $sp.Children.Add($tx) | Out-Null
    $sp.Children.Add($cnt) | Out-Null
    $b.Content = $sp
    $destino = $key
    $b.Add_Click({ Show-View $destino }.GetNewClosure())
    $Global:NavBtns[$key] = $b
    return $b
}

$NavPanel.Children.Add((New-NavButton 'dash' 'Panel' '' 'E80F' 'AccentBlue')) | Out-Null
$NavPanel.Children.Add((New-NavButton 'console' 'Consola' '' 'E756' 'AccentGreen')) | Out-Null

foreach ($c in $Global:Cats) {
    # Salud vive como inicio principal; no duplicarla como sección lateral.
    if ($c.Key -eq 'salud') { continue }
    $n = @($Global:Catalog | Where-Object Cat -eq $c.Key).Count
    $NavPanel.Children.Add((New-NavButton $c.Key $c.Nombre "$n" $c.Icon 'AccentBlue')) | Out-Null
}

# -- TARJETAS DE HERRAMIENTAS --------------------------------------------------

# Estimaciones de limpieza por herramienta (no en el dash inicial: viven en cada tarjeta).
$Global:CleanSizeHints = @{}

function Get-WDMFolderBytes([string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) { return [double]0 }
    try {
        return [double]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum)
    } catch { return [double]0 }
}

function Update-CleanSizeHints {
    # Estimaciones por herramienta de limpieza (seccion Limpieza). Conservador y rapido.
    $hints = @{}
    function _H([double]$b) { if ($b -le 0) { return "0 B" } else { return (Human $b) } }
    try {
        $temp = (Get-WDMFolderBytes $env:TEMP) + (Get-WDMFolderBytes "$env:SystemRoot\Temp") + (Get-WDMFolderBytes "$env:LOCALAPPDATA\Temp")
        $hints['clean-temp'] = _H $temp
    } catch { }
    try { $hints['clean-prefetch'] = _H (Get-WDMFolderBytes "$env:SystemRoot\Prefetch") } catch { }
    try {
        $th = [double]0
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -EA SilentlyContinue | ForEach-Object { $th += $_.Length }
        $hints['clean-thumbnail'] = _H $th
    } catch { }
    try { $hints['clean-wu'] = _H (Get-WDMFolderBytes "$env:SystemRoot\SoftwareDistribution\Download") } catch { }
    try {
        $rb = 0; try { $rb = Get-RecycleBinBytes } catch { $rb = 0 }
        $hints['clean-recycle'] = _H ([double]$rb)
    } catch { }
    # Nota: el tamaño de cache por navegador ya se calcula al armar el
    # catalogo (ver bloque "NAVEGADORES"), directamente en la descripcion de
    # cada tarjeta individual. No hace falta un hint generico aca.
    try {
        $dm = (Get-WDMFolderBytes "$env:SystemRoot\Minidump") + (Get-WDMFolderBytes "$env:LOCALAPPDATA\CrashDumps")
        $hints['clean-dumps'] = _H $dm
    } catch { }
    try {
        $lg = [double]0
        foreach ($pat in @("$env:SystemRoot\Logs\CBS\*.log","$env:SystemRoot\Logs\DISM\*.log","$env:TEMP\*.log")) {
            Get-ChildItem $pat -EA SilentlyContinue | ForEach-Object { $lg += $_.Length }
        }
        $hints['clean-logs'] = _H $lg
    } catch { }
    try { $hints['clean-store'] = _H (Get-WDMFolderBytes "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache") } catch { }
    try { $hints['clean-teams'] = _H ((Get-WDMFolderBytes "$env:APPDATA\Microsoft\Teams\Cache") + (Get-WDMFolderBytes "$env:APPDATA\Microsoft\Teams\blob_storage")) } catch { }
    try { $hints['clean-discord'] = _H (Get-WDMFolderBytes "$env:APPDATA\discord\Cache") } catch { }
    try { $hints['clean-spotify'] = _H (Get-WDMFolderBytes "$env:LOCALAPPDATA\Spotify\Storage") } catch { }
    try { $hints['clean-vscode'] = _H ((Get-WDMFolderBytes "$env:APPDATA\Code\Cache") + (Get-WDMFolderBytes "$env:APPDATA\Code\CachedData")) } catch { }
    try { $hints['clean-office'] = _H (Get-WDMFolderBytes "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache") } catch { }
    try { $hints['clean-bits'] = _H (Get-WDMFolderBytes "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader") } catch { }
    try { $hints['clean-fontcache'] = _H (Get-WDMFolderBytes "$env:LOCALAPPDATA\FontCache") } catch { }
    try {
        $sh = [double]0
        foreach ($p in @(
            "$env:LOCALAPPDATA\D3DSCache",
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:LOCALAPPDATA\AMD\DxCache"
        )) { $sh += Get-WDMFolderBytes $p }
        $hints['clean-shader'] = _H $sh
    } catch { }
    try { $hints['clean-wer'] = _H ((Get-WDMFolderBytes "$env:LOCALAPPDATA\Microsoft\Windows\WER") + (Get-WDMFolderBytes "$env:ProgramData\Microsoft\Windows\WER")) } catch { }
    try { $hints['clean-delivery'] = _H (Get-WDMFolderBytes "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization") } catch { }
    try { $hints['clean-recent'] = _H (Get-WDMFolderBytes "$env:APPDATA\Microsoft\Windows\Recent") } catch { }
    try { $hints['clean-edge-webview'] = _H (Get-WDMFolderBytes "$env:LOCALAPPDATA\EBWebView") } catch { }

    # -- Los que faltaban (agregados a pedido: "cada tarjeta con su MB") --
    try { $hints['clean-cbs'] = _H (Get-WDMFolderBytes "$env:SystemRoot\Logs\CBS") } catch { }
    try {
        $dx = [double]0
        foreach ($p in @("$env:TEMP\DxDiag*.txt", "$env:USERPROFILE\Desktop\DxDiag*.txt")) {
            Get-ChildItem $p -EA SilentlyContinue | ForEach-Object { $dx += $_.Length }
        }
        $hints['clean-dxdiag'] = _H $dx
    } catch { }
    try {
        $ic = [double]0
        if (Test-Path "$env:LOCALAPPDATA\IconCache.db") { $ic += (Get-Item "$env:LOCALAPPDATA\IconCache.db" -EA SilentlyContinue).Length }
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -EA SilentlyContinue | ForEach-Object { $ic += $_.Length }
        $hints['clean-iconcache'] = _H $ic
    } catch { }
    try {
        $ab = [double]0
        foreach ($p in @(
            "$env:APPDATA\discord\Cache", "$env:LOCALAPPDATA\Discord\Cache",
            "$env:LOCALAPPDATA\Spotify\Storage", "$env:APPDATA\Spotify\Cache",
            "$env:APPDATA\Code\Cache", "$env:APPDATA\Code\CachedData",
            "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
            "$env:APPDATA\Microsoft\Teams\Cache", "$env:APPDATA\Microsoft\Teams\blob_storage",
            "$env:LOCALAPPDATA\Steam\htmlcache", "$env:LOCALAPPDATA\Steam\shadercache",
            "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\AMD\DxCache", "$env:LOCALAPPDATA\D3DSCache"
        )) { $ab += Get-WDMFolderBytes $p }
        $hints['clean-apps-deep'] = _H $ab
    } catch { }
    try {
        $carpetaBk = Join-Path $env:USERPROFILE 'Documents\DeMente\backups\registry'
        $hints['clean-dm-backups'] = _H (Get-WDMFolderBytes $carpetaBk)
    } catch { }
    # Estos tres NO llevan MB exacto a proposito, para no frenar el arranque
    # de la app escaneando carpetas potencialmente enormes (Windows.old puede
    # pesar decenas de GB) o de miles de archivos sueltos (Thumbs.db por todo
    # el perfil). El tamaño real se ve al ejecutar la herramienta.
    $hints['clean-windows-old'] = if (Test-Path "$env:SystemDrive\Windows.old") { 'presente, puede ser varios GB' } else { 'no presente ahora' }
    $hints['clean-thumbsdb'] = 'variable, se calcula al ejecutar'
    $hints['clean-cleanmgr'] = 'varios GB posibles (incluye WinSxS)'
    # Registro: sin MB de disco significativos
    $hints['reg-audit'] = "solo claves"
    $hints['reg-clean-safe'] = "solo claves"
    $hints['reg-restore'] = "n/a"
    $hints['clean-dns'] = "cache DNS"
    $hints['clean-clipboard'] = "memoria"
    $hints['clean-standby'] = "RAM (no disco)"
    $Global:CleanSizeHints = $hints
}

function Apply-CleanSizeHintsToCards {
    if (-not $Global:CleanSizeHints -or $Global:CleanSizeHints.Count -eq 0) { return }
    foreach ($c in $Global:Cards) {
        $id = $c.Uid
        $t = $Global:ToolIndex[$id]
        if (-not $t -or $t.Cat -ne 'clean') { continue }
        # Los navegadores y el desinstalador ya calculan su propio dato real
        # (por navegador / por programa) y lo ponen en su descripcion al
        # armar el catalogo. Pisarlo aca con "ver al ejecutar" seria peor
        # info, no mejor.
        if ($id -like 'clean-browser-*' -or $t.Sub -eq 'uninstall') { continue }
        $sz = if ($Global:CleanSizeHints.ContainsKey($id)) { $Global:CleanSizeHints[$id] } else { 'ver al ejecutar' }
        $short = [string]$t.Desc
        if ($short.Length -gt 85) { $short = $short.Substring(0, 82) + '...' }
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.ClipToBounds = $true
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = [string]$t.Name
        $title.FontSize = 13.5
        $title.FontWeight = 'SemiBold'
        $title.Foreground = Brush 'Zinc200'
        $title.TextTrimming = 'CharacterEllipsis'
        $rec = New-Object System.Windows.Controls.TextBlock
        $rec.Text = "Recuperable: ~$sz"
        $rec.FontSize = 11.5
        $rec.FontWeight = 'SemiBold'
        $rec.Foreground = Brush 'AccentGreen'
        $rec.Margin = '0,3,0,0'
        $rec.TextTrimming = 'CharacterEllipsis'
        $sub = New-Object System.Windows.Controls.TextBlock
        $sub.Text = $short
        $sub.FontSize = 11
        $sub.Foreground = Brush 'Zinc400'
        $sub.Margin = '0,3,0,0'
        $sub.TextWrapping = 'Wrap'
        $sub.TextTrimming = 'CharacterEllipsis'
        $sub.MaxHeight = 32
        $sub.LineHeight = 14
        $sub.ClipToBounds = $true
        $sp.Children.Add($title) | Out-Null
        $sp.Children.Add($rec) | Out-Null
        $sp.Children.Add($sub) | Out-Null
        $c.Content = $sp
        $tip = New-Object System.Windows.Controls.ToolTip
        $tip.Content = "$($t.Desc)`n`nEstimado recuperable ahora: $sz"
        $tip.MaxWidth = 340
        $c.ToolTip = $tip
    }
}

function New-ToolCard($t) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style = $window.Resources['ToolCard']
    $cb.Uid = $t.Id

    try { $cb.Tag = [string][char][Convert]::ToInt32($t.Icon, 16) } catch { $cb.Tag = [string][char]0xE946 }

    $accent = switch ($t.Cat) {
        'clean'   { 'AccentGreen' }
        'perf'    { 'AccentBlue' }
        'sec'     { 'AccentGreen' }
        'privacy' { 'AccentPurple' }
        'repair'  { 'AccentOrange' }
        'tools'   { 'AccentPurple' }
        'info'    { 'AccentCyan' }
        default   { 'AccentBlue' }
    }
    if ($t.Risk -eq 'danger') { $accent = 'AccentRed' }
    elseif ($t.Risk -eq 'care') { $accent = 'AccentYellow' }
    # Apps de inicio: el color del icono ES el semaforo (sin escribir Verde/Rojo)
    if ($t.Sub -eq 'startup') {
        $accent = switch ($t.Risk) {
            'danger' { 'AccentRed' }
            'care'   { 'AccentYellow' }
            default  { 'AccentGreen' }
        }
    }
    $cb.Foreground = Brush $accent

    # Contenido visual (UIElement): evita el error de propiedad Content en TextBlock del template
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.ClipToBounds = $true
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = [string]$t.Name
    $title.FontSize = 13.5
    $title.FontWeight = 'SemiBold'
    $title.Foreground = Brush 'Zinc200'
    $title.TextTrimming = 'CharacterEllipsis'
    $title.TextWrapping = 'NoWrap'
    $title.Name = 'CardTitle'
    $sub = New-Object System.Windows.Controls.TextBlock
    $fullDesc = [string]$t.Desc
    if ($t.Sub -eq 'startup') {
        # Primeras 3-4 lineas en la tarjeta (Que es / Windows / DeMente)
        $parts = @($fullDesc -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne '' })
        $short = ($parts | Select-Object -First 4) -join [Environment]::NewLine
        if ($parts.Count -gt 4) { $short = $short + [Environment]::NewLine + '...' }
    } else {
        $short = $fullDesc
        if ($short.Length -gt 110) { $short = $short.Substring(0, 107) + '...' }
    }
    $sub.Text = $short
    $sub.FontSize = 11
    $sub.Foreground = Brush 'Zinc400'
    $sub.Margin = '0,5,0,0'
    $sub.TextWrapping = 'Wrap'
    $sub.TextTrimming = 'CharacterEllipsis'
    $sub.MaxHeight = $(if ($t.Sub -eq 'startup') { 78 } else { 44 })
    $sub.LineHeight = 14.5
    $sub.ClipToBounds = $true
    $sp.Children.Add($title) | Out-Null
    $sp.Children.Add($sub) | Out-Null
    $cb.Content = $sp
    # ToolTip multilinea legible
    $tip = New-Object System.Windows.Controls.ToolTip
    $tipTb = New-Object System.Windows.Controls.TextBlock
    $tipTb.Text = $fullDesc
    $tipTb.TextWrapping = 'Wrap'
    $tipTb.MaxWidth = $(if ($t.Sub -eq 'startup') { 480 } else { 340 })
    $tipTb.FontSize = 12
    $tip.Content = $tipTb
    $cb.ToolTip = $tip

    $menu = New-Object System.Windows.Controls.ContextMenu
    $tid = $t.Id
    $m1 = New-Object System.Windows.Controls.MenuItem
    $m1.Header = 'Ejecutar solo esta'
    $m1.Add_Click({
        $tool = $Global:ToolIndex[$tid]
        if ($tool) { Start-BSRun @($tool) $false }
    }.GetNewClosure())
    $menu.Items.Add($m1) | Out-Null
    $m2i = New-Object System.Windows.Controls.MenuItem
    $m2i.Header = 'Copiar ID'
    $m2i.Add_Click({ try { [System.Windows.Clipboard]::SetText($tid) } catch { } }.GetNewClosure())
    $menu.Items.Add($m2i) | Out-Null
    $m3 = New-Object System.Windows.Controls.MenuItem
    $m3.Header = 'Ver detalle DEFAULT / DeMente'
    $m3.Add_Click({
        $tool = $Global:ToolIndex[$tid]
        if (-not $tool) { return }
        $extra = ''
        if ($Global:CleanSizeHints -and $Global:CleanSizeHints.ContainsKey($tid)) {
            $extra = "`n`nEstimado recuperable: $($Global:CleanSizeHints[$tid])"
        }
        $msg = "{0}`n`n{1}{2}`n`nRiesgo: {3}" -f $tool.Name, $tool.Desc, $extra, $(if($tool.Risk){$tool.Risk}else{'bajo'})
        [System.Windows.MessageBox]::Show($msg, 'DeMente', 'OK', 'Information') | Out-Null
    }.GetNewClosure())
    $menu.Items.Add($m3) | Out-Null
    $cb.ContextMenu = $menu

    $cb.Add_Checked({ Update-Counter; Save-WDMConfig })
    $cb.Add_Unchecked({ Update-Counter; Save-WDMConfig })
    return $cb
}




# Orden alfabetico por nombre dentro de cada categoria (prolijo en la grilla)
# -- DESINSTALADOR: inyectar programas de ESTA PC como entradas de catalogo --
# A diferencia del resto (catalogo fijo escrito a mano), esto se arma leyendo
# lo que hay instalado ahora. Cat='clean' + Sub='uninstall' para que viva
# dentro de Limpieza pero en su propio chip, sin mezclarse con las 35+
# tarjetas fijas de limpieza y sin inundar esa vista.
#
# IMPORTANTE: cada herramienta corre en un proceso de PowerShell nuevo (ver
# nota en $Global:Prelude), asi que el -Code NO puede depender de una
# variable en memoria del proceso de la GUI (como un indice por nombre):
# cada entrada lleva sus propios datos (UninstallString, PackageId, etc.)
# incrustados como texto dentro del propio -Code.
function ConvertTo-DMPsLiteral([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace "'", "''")
}
try {
    $programasWin32 = @(Get-DMInstalledPrograms)
    $programasStore = @(Get-DMInstalledStoreApps)
    foreach ($prog in ($programasWin32 + $programasStore)) {
        $slug = ([System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($prog.Name)
            )
        ) -replace '-', '').Substring(0, 10).ToLower()
        $tag = if ($prog.IsStore) { 'Store' } else { 'Escritorio' }
        $sizeTxt = if ($prog.SizeKB -gt 0) { " (~$(Human ($prog.SizeKB * 1KB)))" } else { '' }
        $descTxt = "$tag$sizeTxt. $(if($prog.Publisher){"Editor: $($prog.Publisher). "})Desinstala con el metodo propio de Windows y despues limpia cache/config residual en AppData."

        $nameL  = ConvertTo-DMPsLiteral $prog.Name
        $pubL   = ConvertTo-DMPsLiteral $prog.Publisher
        $uninL  = ConvertTo-DMPsLiteral $prog.UninstallCmd
        $quietL = ConvertTo-DMPsLiteral $prog.QuietCmd
        $pkgL   = ConvertTo-DMPsLiteral $prog.PackageId
        $isStoreTxt = if ($prog.IsStore) { '$true' } else { '$false' }
        $sizeNum = [int]$prog.SizeKB

        $codeTxt = "Remove-DMProgram -Programa ([pscustomobject]@{ Name='$nameL'; Publisher='$pubL'; UninstallCmd='$uninL'; QuietCmd='$quietL'; PackageId='$pkgL'; IsStore=$isStoreTxt; SizeKB=$sizeNum; RegPath=`$null }) -Confirm:`$false"

        $entry = T -Id "uninstall-$slug" -Name $prog.Name -Desc $descTxt -Icon 'ECC9' -Cat 'clean' -Risk 'care' -Sub 'uninstall' -Code $codeTxt
        $Global:Catalog += $entry
    }
} catch {
    Write-Verbose "No se pudo armar el listado de desinstalacion: $($_.Exception.Message)"
}

# -- APPS DE INICIO: inyectar items de ESTA PC como entradas de catalogo -----
# Semaforo visual: color del icono (verde/amarillo/rojo). Sin palabras [Verde]/[Rojo].
try {
    $itemsInicio = @(Get-DMStartupItems)
    foreach ($it in $itemsInicio) {
        $slugBase = "$($it.Kind)|$($it.RegPath)|$($it.ValueName)|$($it.FilePath)|$($it.TaskPath)|$($it.Name)"
        $slug = ([System.BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($slugBase)
            )
        ) -replace '-', '').Substring(0, 10).ToLower()

        $advice = Get-DMStartupAdvice -Item $it
        $accionTxt = if ($it.IsDisabled) { 'enable' } else { 'disable' }

        # Icono MDL2 segun nivel (el color lo pone New-ToolCard via Risk)
        $iconCode = switch ($advice.Level) {
            'verde'    { 'E73E' }  # CheckMark - se puede apagar
            'amarillo' { 'E7BA' }  # Warning
            'rojo'     { 'E72E' }  # Shield / protected
            default    { 'E7E8' }
        }
        $riskLvl = switch ($advice.Level) {
            'verde'    { 'safe' }
            'amarillo' { 'care' }
            'rojo'     { 'danger' }
            default    { 'care' }
        }

        $verboTxt = if ($it.IsDisabled) { 'Ya apagado · Reactivar' }
                    elseif ($advice.Level -eq 'rojo') { 'Protegido' }
                    else { 'Apagar' }

                $detail = Get-DMStartupDetail -Item $it
        $advice = $advice  # ya calculado arriba

        $titleName = "$verboTxt · $($it.Name)"

        # --- Texto completo (tooltip + subtitulo): maximo detalle util ---
                        # Mensaje humano fijo (4 lineas)  -  nunca el texto "si sabes que es"
        $queEs = [string]$advice.WhatIs
        if ([string]::IsNullOrWhiteSpace($queEs)) { $queEs = "Programa al inicio: $($it.Name)" }

        $winLine = [string]$advice.WinWants
        if ([string]::IsNullOrWhiteSpace($winLine)) { $winLine = 'Windows lo deja activo al iniciar.' }
        $winLine = "Windows: $winLine"
        if ($it.IsDisabled) { $winLine = 'Windows: estaria activo; ahora lo apago DeMente.' }

        $dmLine = [string]$advice.DmSays
        if ([string]::IsNullOrWhiteSpace($dmLine)) {
            $dmLine = switch ($advice.Level) {
                'verde' { 'DeMente: lo podes apagar; no pasa nada grave.' }
                'rojo'  { 'DeMente: no lo toques.' }
                default { 'DeMente: si reconoces el nombre de abajo y no lo necesitas, lo podes apagar.' }
            }
        }
        if ($it.IsDisabled -and $advice.Level -ne 'rojo') {
            $dmLine = 'DeMente: ya esta apagado; podes reactivarlo cuando quieras.'
        }

        $efecto = [string]$advice.Phrase
        if ($efecto -match '^(?i)si (lo )?apagas:\s*') {
            $efecto = $efecto -replace '^(?i)si (lo )?apagas:\s*',''
        }

        $cardLines = [System.Collections.Generic.List[string]]::new()
        [void]$cardLines.Add("Que es: $queEs")
        [void]$cardLines.Add($winLine)
        [void]$cardLines.Add($dmLine)
        if (-not [string]::IsNullOrWhiteSpace($efecto)) {
            [void]$cardLines.Add("Si lo apagas: $efecto")
        }

$tipLines = [System.Collections.Generic.List[string]]::new()
        foreach ($L in $cardLines) { [void]$tipLines.Add($L) }
        [void]$tipLines.Add('')
        [void]$tipLines.Add(('Tipo: {0}' -f $detail.TipoHumano))
        if ($detail.Origen) { [void]$tipLines.Add(('Origen: {0}' -f $detail.Origen)) }
        if ($detail.Path) {
            $ex = if ($detail.Exists) { 'existe' } else { 'NO existe (resto?)' }
            [void]$tipLines.Add(('Ruta: {0} ({1})' -f $detail.Path, $ex))
        }
        if ($detail.Company) { [void]$tipLines.Add(('Empresa: {0}' -f $detail.Company)) }
        if ($detail.Product) { [void]$tipLines.Add(('Producto: {0}' -f $detail.Product)) }
        if ($detail.ServiceName) { [void]$tipLines.Add(('Servicio: {0}' -f $detail.ServiceName)) }
        if ($detail.TaskPath) { [void]$tipLines.Add(('Tarea: {0}' -f $detail.TaskPath)) }
        if ($detail.RegPath) { [void]$tipLines.Add(('Registro: {0}' -f $detail.RegPath)) }

        $descCard = ($cardLines -join [Environment]::NewLine)
        $descTxt = ($tipLines -join [Environment]::NewLine)  # tooltip + fuente de subtitulo
        $lineas = $tipLines


$nameL    = ConvertTo-DMPsLiteral $it.Name
        $cmdL     = ConvertTo-DMPsLiteral $it.Command
        $kindL    = ConvertTo-DMPsLiteral $it.Kind
        $regPathL = ConvertTo-DMPsLiteral $it.RegPath
        $regLblL  = ConvertTo-DMPsLiteral $it.RegLabel
        $valNameL = ConvertTo-DMPsLiteral $it.ValueName
        $fpL      = ConvertTo-DMPsLiteral $it.FilePath
        $tpL      = ConvertTo-DMPsLiteral $it.TaskPath
        $isOffTxt = if ($it.IsDisabled) { '$true' } else { '$false' }
        $phraseL  = ConvertTo-DMPsLiteral $advice.Phrase

        $itemLit = "[pscustomobject]@{ Name='$nameL'; Command='$cmdL'; Kind='$kindL'; RegPath='$regPathL'; RegLabel='$regLblL'; ValueName='$valNameL'; IsDisabled=$isOffTxt; FilePath='$fpL'; TaskPath='$tpL' }"

                $resumenL = ConvertTo-DMPsLiteral ((@(
            "Que es: $queEs"
            $(if ($efecto) { "Si lo apagas: $efecto" } else { $null })
            $dmLine
        ) | Where-Object { $_ }) -join ' | ')
        if ($advice.Level -eq 'rojo' -and -not $it.IsDisabled) {
            $codeTxt = "HR 'INICIO PROTEGIDO: $nameL'; INFO '$resumenL'; INFO '$phraseL'; OK 'Sin cambios (protegido).'"
        } else {
            $codeTxt = "INFO '$resumenL'; Set-DMStartupItemState -Item ($itemLit) -Accion '$accionTxt' -Confirm:`$false"
        }

        $entry = T -Id "startup-$slug" -Name $titleName -Desc $descTxt -Icon $iconCode -Cat 'perf' -Risk $riskLvl -Sub 'startup' -Code $codeTxt
        $Global:Catalog += $entry
    }
} catch {
    Write-Host "[!] Apps de inicio: $($_.Exception.Message)" -ForegroundColor Yellow
}

# -- NAVEGADORES: un boton por navegador presente en esta PC -----------------
$Global:BrowserCleanIds = @()
try {
        $navegadores = [System.Collections.Generic.List[object]]::new()
    foreach ($b in @(Get-DMBrowserDefinitions)) { [void]$navegadores.Add($b) }
    $nombresNav = @($navegadores | ForEach-Object Name)
    if ($nombresNav -notcontains 'Tor Browser') {
        # Ultimo intento: tor-path.txt o busqueda directa
        $torTry = $null
        try { $torTry = Get-DMFindTorBrowser } catch { }
        if (-not $torTry) {
            $tp = Join-Path $env:USERPROFILE 'Documents\DeMente\tor-path.txt'
            if (Test-Path -LiteralPath $tp -ErrorAction SilentlyContinue) {
                $torTry = (Get-Content -LiteralPath $tp -TotalCount 1 -ErrorAction SilentlyContinue)
                if ($torTry) { $torTry = ([string]$torTry).Trim().Trim('"') }
            }
        }
        if ($torTry) {
            $roots = [System.Collections.Generic.List[string]]::new()
            foreach ($c in @(
                (Join-Path $torTry 'Browser\TorBrowser\Data\Browser\profile.default'),
                (Join-Path $torTry 'Browser\TorBrowser\Data\Browser'),
                $torTry
            )) {
                if ($c -and (Test-Path -LiteralPath $c -ErrorAction SilentlyContinue)) { [void]$roots.Add($c) }
            }
            if ($roots.Count -eq 0) { [void]$roots.Add($torTry) }
            [void]$navegadores.Add([pscustomobject]@{
                Name='Tor Browser'; Proc=@('firefox'); Roots=@($roots); Engine='firefox'; TorRoot=$torTry
            })
            $nombresNav = @($navegadores | ForEach-Object Name)
            Write-Host "[i] Tor Browser forzado desde: $torTry" -ForegroundColor Cyan
        } else {
            $tp = Join-Path $env:USERPROFILE 'Documents\DeMente\tor-path.txt'
            Write-Host "[i] Tor no detectado. Crea el archivo $tp con una linea = carpeta de Tor (donde esta Browser\firefox.exe)" -ForegroundColor Yellow
            # Escape hatch: boton para elegir la carpeta a mano cuando ninguna
            # busqueda automatica (procesos, registro, accesos directos,
            # busqueda acotada bajo el perfil) la encontro. Una vez elegida,
            # queda guardada y Tor aparece solo de ahi en adelante.
            $Global:Catalog += (T -Id 'clean-tor-manual' -Name 'Tor Browser: elegir carpeta' -Desc 'No lo encontramos solo. Si lo tenes instalado en un lugar poco comun (pendrive, carpeta propia, etc.), elegi la carpeta una vez y va a aparecer como los demas navegadores de ahi en adelante.' -Icon 'E774' -Cat 'clean' -Code 'Set-DMTorPathManual')
        }
    }
    Write-Host "[i] Navegadores detectados para cache: $($navegadores.Count) -> $($nombresNav -join ', ')" -ForegroundColor Cyan

    foreach ($b in $navegadores) {
        $subs = if ($b.Engine -eq 'firefox') { @('cache2', 'startupCache', 'thumbnails', 'shader-cache') }
                else { @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache', 'ShaderCache', 'Service Worker\CacheStorage', 'blob_storage') }
        $bytesTot = [double]0
        foreach ($root in @($b.Roots)) {
            if (-not $root) { continue }
            foreach ($s in $subs) {
                $p = Join-Path $root $s
                if (Test-Path -LiteralPath $p) {
                    try { $bytesTot += Get-DMFolderSizeSafe $p } catch { }
                }
            }
            # Opera / perfiles anidados
            if ($b.Engine -eq 'chromium' -and (Test-Path -LiteralPath $root)) {
                foreach ($subDir in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
                    foreach ($s in $subs) {
                        $p = Join-Path $subDir.FullName $s
                        if (Test-Path -LiteralPath $p) {
                            try { $bytesTot += Get-DMFolderSizeSafe $p } catch { }
                        }
                    }
                }
            }
        }
        $mb = [math]::Round($bytesTot / 1MB, 0)
        $sizeTxt = if ($mb -gt 0) { "~$mb MB" } else { 'poco o nada ahora' }
        $descTxt = "Solo cache tecnica ($sizeTxt). No toca historial, contraseñas, favoritos ni cookies. Cierra solo $($b.Name)."

        $rootsLit = (@($b.Roots) | ForEach-Object { "'$(ConvertTo-DMPsLiteral $_)'" }) -join ', '
        $procLit  = (@($b.Proc)  | ForEach-Object { "'$(ConvertTo-DMPsLiteral $_)'" }) -join ', '
        $nameL = ConvertTo-DMPsLiteral $b.Name
        $torExtra = ''
        if ($b.PSObject.Properties.Name -contains 'TorRoot' -and $b.TorRoot) {
            $torExtra = " -TorRoot '$(ConvertTo-DMPsLiteral $b.TorRoot)'"
        }
        $codeTxt = "Clear-DMBrowserCache -DisplayName '$nameL' -ProcessNames @($procLit) -ProfileRoots @($rootsLit) -Engine '$($b.Engine)'$torExtra"

        $slug = ($b.Name -replace '[^a-zA-Z0-9]', '').ToLower()
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'browser' }
        $id = "clean-browser-$slug"
        # Evitar IDs duplicados (p.ej. dos Opera)
        $suffix = 1
        $idBase = $id
        while ($Global:Catalog | Where-Object { $_.Id -eq $id }) {
            $suffix++; $id = "$idBase$suffix"
        }
        $entry = T -Id $id -Name "Caché: $($b.Name)" -Desc $descTxt -Icon 'E774' -Cat 'clean' -Code $codeTxt
        $Global:Catalog += $entry
        $Global:BrowserCleanIds += $id
    }
} catch {
    Write-Host "[!] Navegadores/cache: $($_.Exception.Message)" -ForegroundColor Yellow
}

$Global:ToolIndex = @{}
foreach ($t in $Global:Catalog) { $Global:ToolIndex[$t.Id] = $t }

$ordenados = @($Global:Catalog | Sort-Object @{Expression='Cat';Ascending=$true}, @{Expression='Name';Ascending=$true})
foreach ($t in $ordenados) {
    $card = New-ToolCard $t
    $CardPanel.Children.Add($card) | Out-Null
    $Global:Cards += $card
}

# -- FILTRO Y CONTADOR --------------------------------------------------------
function Apply-Filter {
    $q = $SearchInput.Text
    if ($q) { $q = $q.Trim().ToLower() }
    $SearchHint.Visibility = if ($q) { 'Collapsed' } else { 'Visible' }
    $BtnSearchClear.Visibility = if ($q) { 'Visible' } else { 'Collapsed' }
    $vis = 0
    $buscando = ($q -and $q.Length -ge 2)
    foreach ($c in $Global:Cards) {
        $t = $Global:ToolIndex[$c.Uid]
        $okCat = $buscando -or ($t.Cat -eq $Global:CurCat)
        # Dentro de Limpieza, ademas del rubro hay que respetar el chip activo:
        # 'uninstall' (desinstalar programas) vive aparte de la limpieza general,
        # salvo que se este buscando texto (ahi se ve todo, para no esconder
        # resultados de busqueda detras de un chip que el usuario no toco).
        if ($okCat -and -not $buscando -and $Global:CurCat -eq 'clean') {
            $esUninstall = ($t.Sub -eq 'uninstall')
            if ($Global:CleanSubView -eq 'uninstall') { $okCat = $esUninstall }
            else { $okCat = -not $esUninstall }
        }
        if ($okCat -and -not $buscando -and $Global:CurCat -eq 'perf') {
            $esStartup = ($t.Sub -eq 'startup')
            if ($Global:PerfSubView -eq 'startup') { $okCat = $esStartup }
            else { $okCat = -not $esStartup }
        }
        $okTxt = $true
        if ($q -and $q.Length -ge 1) {
            $okTxt = ($t.Name.ToLower().Contains($q)) -or ($t.Desc.ToLower().Contains($q)) -or ($t.Id.ToLower().Contains($q))
        }
        if ($okCat -and $okTxt) { $c.Visibility = 'Visible'; $vis++ } else { $c.Visibility = 'Collapsed' }
    }
    if ($q -and $q.Length -ge 2) { $LblCount.Text = "$vis resultados en todo el catalogo" }
    else { $LblCount.Text = "$vis herramientas" }
}

function Update-CleanSubTabButtons {
    try {
        if ($Global:CleanSubView -eq 'uninstall') {
            $BtnCleanUninstall.Background = Brush 'Zinc850'
            $BtnCleanGeneral.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        } else {
            $BtnCleanGeneral.Background = Brush 'Zinc850'
            $BtnCleanUninstall.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        }
    } catch { }
}
function Update-PerfSubTabButtons {
    try {
        if ($Global:PerfSubView -eq 'startup') {
            $BtnPerfStartup.Background = Brush 'Zinc850'
            $BtnPerfGeneral.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        } else {
            $BtnPerfGeneral.Background = Brush 'Zinc850'
            $BtnPerfStartup.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        }
    } catch { }
}
$BtnCleanGeneral.Add_Click({
    $Global:CleanSubView = 'general'
    Update-CleanSubTabButtons
    Apply-Filter
})
$BtnCleanUninstall.Add_Click({
    $Global:CleanSubView = 'uninstall'
    Update-CleanSubTabButtons
    Apply-Filter
})
$BtnPerfGeneral.Add_Click({
    $Global:PerfSubView = 'general'
    Update-PerfSubTabButtons
    Apply-Filter
})
$BtnPerfStartup.Add_Click({
    $Global:PerfSubView = 'startup'
    Update-PerfSubTabButtons
    Apply-Filter
})

function Update-Counter {
    $n = @($Global:Cards | Where-Object { $_.IsChecked }).Count
    $TxtCounter.Text = "$n"
    if ($n -gt 0) {
        $BtnExecute.IsEnabled = -not $Global:Running
        $CounterBadge.Background = Brush 'AccentBlue'
        $TxtCounter.Foreground = [System.Windows.Media.Brushes]::White
    }
    else {
        $BtnExecute.IsEnabled = $false
        $CounterBadge.Background = Brush 'Zinc800'
        $TxtCounter.Foreground = Brush 'Zinc200'
    }
}

function Show-View($key) {
    $Global:CurCat = $key
    foreach ($k in $Global:NavBtns.Keys) { $Global:NavBtns[$k].ClearValue([System.Windows.Controls.Control]::BackgroundProperty) }
    if ($Global:NavBtns.ContainsKey($key)) { $Global:NavBtns[$key].Background = Brush 'Zinc850' }

    $ViewDash.Visibility = 'Collapsed'; $ViewGrid.Visibility = 'Collapsed'; $ViewConsole.Visibility = 'Collapsed'
    $SearchBox.Visibility = 'Collapsed'

    switch ($key) {
        'dash' {
            $ViewDash.Visibility = 'Visible'
            $LblTitle.Text = 'Panel'; $LblSub.Text = 'Centro de comando'
        }
        'console' {
            $ViewConsole.Visibility = 'Visible'
            $LblTitle.Text = 'Consola'; $LblSub.Text = 'Salida en vivo y registro de la sesion'
        }
        default {
            $c = $Global:Cats | Where-Object Key -eq $key
            $ViewGrid.Visibility = 'Visible'
            $SearchBox.Visibility = 'Visible'
            if ($c) {
                $LblTitle.Text = $c.Nombre; $LblSub.Text = $c.Sub
            }
            if ($key -eq 'salud') {
                $LblTitle.Text = 'Salud'
                $LblSub.Text = '¿Cómo está realmente tu PC?'
            }
            if ($key -eq 'clean') {
                $Global:CleanSubView = 'general'
                try { $CleanSubTabs.Visibility = 'Visible'; $PerfSubTabs.Visibility = 'Collapsed' } catch { }
                try { Update-CleanSubTabButtons } catch { }
                try {
                    if (-not $Global:CleanSizeHints -or $Global:CleanSizeHints.Count -eq 0) {
                        Update-CleanSizeHints
                    }
                    Apply-CleanSizeHintsToCards
                } catch { }
            } elseif ($key -eq 'perf') {
                $Global:PerfSubView = 'general'
                try { $PerfSubTabs.Visibility = 'Visible'; $CleanSubTabs.Visibility = 'Collapsed' } catch { }
                try { Update-PerfSubTabButtons } catch { }
            } else {
                try { $CleanSubTabs.Visibility = 'Collapsed'; $PerfSubTabs.Visibility = 'Collapsed' } catch { }
            }
            Apply-Filter
        }
    }
}

$SearchInput.Add_TextChanged({
        if ($Global:CurCat -in @('dash', 'console')) { return }
        Apply-Filter
    })
$BtnSearchClear.Add_Click({ $SearchInput.Text = '' })


# -- PERFILES POR SECCION (Rapida / Profunda / Default Windows) --------------
# Perfiles por seccion:
#   ESENCIAL  = seguro, impacto claro, ideal primera vez / alumnos
#   COMPLETO  = todo lo razonable de la seccion
#   DEFAULT WINDOWS = sin cambios de DeMente en esta seccion
$Global:ProfileEsencial = @{
    # Confianza: bajo riesgo, efecto claro. Sin repair pesado ni tweaks contextuales.
    'salud' = @('info-salud')
    'clean' = @('clean-temp','clean-recycle','clean-thumbnail','clean-dns','clean-clipboard','reg-audit')
    'perf'  = @('perf-visual','perf-menu','perf-storage-sense')
    'privacy' = @('privacy-advertising','privacy-bing','privacy-searchhighlights','privacy-tips')
    'sec'   = @('sec-yara-status','sec-defender-status')
    'repair'= @()
    'tools' = @('tool-folder')
    'info'  = @('info-porque-lenta','info-system')
}
$Global:ProfileCompleto = @{
    'salud' = @('info-salud','info-salud-run')
    'clean' = @('clean-temp','clean-recycle','clean-thumbnail','clean-prefetch','clean-wu','clean-bits','clean-dumps','clean-logs','clean-store','clean-apps-deep','clean-shader','clean-thumbsdb','clean-standby','clean-cbs','clean-dxdiag','clean-recent','clean-clipboard','clean-wer','clean-dns','clean-windows-old','clean-delivery','clean-fontcache','clean-iconcache','clean-edge-webview','clean-dm-backups','clean-dm-logs','reg-audit','reg-clean-safe','reg-restore')
    'perf'  = @('perf-priority','perf-visual','perf-menu','perf-network-throttle','perf-systemresp','perf-ntfs','perf-paging','perf-prefetcher','perf-explorer','perf-superfetch','perf-indexacion','perf-shutdown','perf-power','perf-ultimate','perf-faststartup','perf-storage-sense','perf-classic-menu','perf-hibernacion','perf-mmcss','perf-fullscreen-opt','perf-mouse-accel','perf-disable-sticky','perf-xbox-services','perf-sysmain-hint','perf-startup-list')
    'privacy' = @('privacy-advertising','privacy-telemetry','privacy-location','privacy-camera','privacy-microphone','privacy-activity','privacy-clipboard','privacy-bing','privacy-gamedvr','privacy-ceip','privacy-searchhighlights','privacy-tips','privacy-copilot','privacy-background','privacy-tailored','privacy-input-personalization','privacy-feedback','privacy-advertising-id2')
    'tools' = @('tool-autoruns','tool-procexp','tool-procmon','tool-tcpview','tool-nvclean','tool-crystal','tool-everything','tool-folder')
    'sec'   = @('sec-yara-status','sec-yara-update','sec-yara-quick','sec-yara-full','sec-defender-status','sec-defender-scan')
    'repair'= @('repair-sequence','repair-sfc','repair-dism')
    'info'  = @('info-full-checkup','info-porque-lenta','info-system','info-disks','info-events','info-startup')
}

# Los navegadores son entradas dinamicas (una por navegador realmente
# presente en esta PC), asi que se suman aca en vez de estar a mano en las
# listas fijas de arriba. Sin esto, ESENCIAL/COMPLETO no limpiarian ningun
# navegador con un solo clic.
if ($Global:BrowserCleanIds) {
    $Global:ProfileEsencial['clean'] = @($Global:ProfileEsencial['clean']) + @($Global:BrowserCleanIds)
    $Global:ProfileCompleto['clean'] = @($Global:ProfileCompleto['clean']) + @($Global:BrowserCleanIds)
}

function Select-SectionProfile([string]$modo) {
    # modo: esencial | completo | default
    # DEFAULT WINDOWS: marca las opciones REVERSIBLES de esta seccion para restaurar
    # el valor de fabrica de Windows (no deja la seleccion vacia).
    if ($Global:CurCat -in @('dash','console')) { return }
    $Global:SectionProfileMode = $modo
    $Global:CargandoConfig = $true
    try {
        foreach ($c in $Global:Cards) {
            $t = $Global:ToolIndex[$c.Uid]
            if ($t -and $t.Cat -eq $Global:CurCat) { $c.IsChecked = $false }
        }
        if ($modo -eq 'default') {
            # Preferimos lo que DeMente ya aplico (si el diagnostico lo confirma).
            # Si no hay diagnostico, marcamos todas las de esta seccion que tengan Revert.
            $ok = @{}
            try { $ok = Get-WDMAppliedState } catch { $ok = @{} }
            $marcadas = 0
            foreach ($c in $Global:Cards) {
                $t = $Global:ToolIndex[$c.Uid]
                if (-not $t -or $t.Cat -ne $Global:CurCat) { continue }
                if (-not $t.Revert) { continue }
                $yaDeMente = ($ok.ContainsKey($c.Uid) -and $ok[$c.Uid])
                # Si sabemos el estado: solo marcar lo que esta en valor DeMente (hay que volver a DEFAULT).
                # Si no sabemos: marcar igual (el usuario elige al ejecutar).
                if ($ok.Count -eq 0 -or $yaDeMente -or -not $ok.ContainsKey($c.Uid)) {
                    $c.IsChecked = $true
                    $marcadas++
                }
            }
            if ($marcadas -eq 0) {
                # Nada reversible o todo ya en DEFAULT: avisar en el contador via tooltip del boton
                try {
                    $msgDefault = if ($Global:CurCat -eq 'clean') {
                        "Limpieza no tiene un 'valor DEFAULT' que restaurar.`n`nWindows conserva temporales y caches hasta que Storage Sense o vos los borren.`n`nDEFAULT aca solo aclara eso: no marca casillas de borrado.`n`nUsa ESENCIAL (conservadora) o COMPLETO (profunda) para estimar y limpiar."
                    } else {
                        "En esta seccion no hay cambios de DeMente para deshacer, o las opciones no tienen reversion definida.`n`nLimpieza e informacion no se 'revierten': solo dejan de aplicarse acciones nuevas."
                    }
                    [System.Windows.MessageBox]::Show($msgDefault, "DEFAULT WINDOWS", 'OK', 'Information') | Out-Null
                } catch { }
            }
        } elseif ($modo -eq 'esencial') {
            $ids = @($Global:ProfileEsencial[$Global:CurCat])
            foreach ($c in $Global:Cards) { if ($ids -contains $c.Uid) { $c.IsChecked = $true } }
        } elseif ($modo -eq 'completo') {
            $ids = @($Global:ProfileCompleto[$Global:CurCat])
            foreach ($c in $Global:Cards) { if ($ids -contains $c.Uid) { $c.IsChecked = $true } }
        }
    } finally { $Global:CargandoConfig = $false }
    Update-Counter
    Save-WDMConfig
    Update-ExecuteButtonLabel
}

function Update-ExecuteButtonLabel {
    try {
        if ($Global:SectionProfileMode -eq 'default') {
            $BtnExecute.Content = 'Restaurar DEFAULT'
            if ($BtnExecute.ToolTip) { } 
            $BtnExecute.ToolTip = 'Ejecuta la reversion al valor DEFAULT de Windows de las opciones marcadas (solo las que tienen reversion).'
        } else {
            $BtnExecute.Content = 'Ejecutar'
            $BtnExecute.ToolTip = 'Aplica las herramientas seleccionadas (propuesta DeMente).'
        }
    } catch { }
}

(UI 'BtnSelAll').Add_Click({
        foreach ($c in $Global:Cards) { if ($c.Visibility -eq 'Visible') { $c.IsChecked = $true } }
    })
(UI 'BtnSelNone').Add_Click({ foreach ($c in $Global:Cards) { $c.IsChecked = $false } })
(UI 'BtnProfRapida').Add_Click({ Select-SectionProfile 'esencial' })
(UI 'BtnProfProfunda').Add_Click({ Select-SectionProfile 'completo' })
(UI 'BtnProfDefault').Add_Click({ Select-SectionProfile 'default' })
(UI 'BtnRevert').Add_Click({
        $sel = @($Global:Cards | Where-Object { $_.IsChecked } | ForEach-Object { $Global:ToolIndex[$_.Uid] } | Where-Object { $_.Revert })
        if ($sel.Count -eq 0) {
            [void](Show-WDMDialog -Title 'DeMente' -Message 'Ninguna de las herramientas seleccionadas tiene accion de reversion.' -Buttons Ok -Tone Info)
            return
        }
        Start-BSRun $sel $true
    })

# -- CONSOLA INTEGRADA --------------------------------------------------------
$Global:ConPara = New-Object System.Windows.Documents.Paragraph
$Global:ConPara.Margin = New-Object System.Windows.Thickness 0
$Global:ConPara.LineHeight = 15
$doc = New-Object System.Windows.Documents.FlowDocument
$doc.Blocks.Add($Global:ConPara)
$Con.Document = $doc

$Global:ConBrushes = @{
    ok   = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(16, 185, 129)))
    err  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(239, 68, 68)))
    warn = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(234, 179, 8)))
    info = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(6, 182, 212)))
    step = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(244, 244, 245)))
    head = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(59, 130, 246)))
    dim  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(113, 113, 122)))
    norm = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(212, 212, 216)))
}

function Write-Con($texto, $tipo) {
    if ($null -eq $texto) { return }
    # No mostramos valores booleanos desnudos devueltos por PowerShell (True/False).
    # El usuario ve el resultado humano de cada herramienta, no la salida interna del motor.
    if (-not $tipo -and $texto -is [string] -and $texto.Trim() -match '^(True|False)$') { return }
    if (-not $tipo) {
        $tipo = 'norm'
        $tt = $texto.TrimStart()
        if ($tt.StartsWith('[OK]')) { $tipo = 'ok' }
        elseif ($tt.StartsWith('[X]')) { $tipo = 'err' }
        elseif ($tt.StartsWith('[!]')) { $tipo = 'warn' }
        elseif ($tt.StartsWith('[i]')) { $tipo = 'info' }
        elseif ($tt.StartsWith('>>')) { $tipo = 'step' }
        elseif ($tt.StartsWith('===')) { $tipo = 'head' }
        elseif ($tt.StartsWith('    ')) { $tipo = 'dim' }
    }
    $r = New-Object System.Windows.Documents.Run $texto
    $r.Foreground = $Global:ConBrushes[$tipo]
    if ($tipo -in @('head', 'step')) { $r.FontWeight = 'Bold' }
    $Global:ConPara.Inlines.Add($r)
    $Global:ConPara.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
    if ($Global:ConPara.Inlines.Count -gt 14000) {
        $viejos = @($Global:ConPara.Inlines | Select-Object -First 6000)
        foreach ($v in $viejos) { $Global:ConPara.Inlines.Remove($v) | Out-Null }
    }
    $Con.ScrollToEnd()
}

(UI 'BtnConClear').Add_Click({ $Global:ConPara.Inlines.Clear() })
(UI 'BtnConLog').Add_Click({
        if ($Global:SesionLog -and (Test-Path $Global:SesionLog)) { Start-Process notepad.exe $Global:SesionLog }
        else { Start-Process explorer.exe $Global:WDMLogs }
    })

# -- MOTOR DE EJECUCION ------------------------------------------------------
$Global:Cola = New-Object System.Collections.Generic.Queue[object]
$Global:Proc = $null
$Global:OutFile = $null
$Global:TailPos = 0
$Global:Pending = ''
$Global:Running = $false
$Global:TotalTareas = 0
$Global:HechasTareas = 0
$Global:TareaActual = $null
$Global:SesionLog = $null
$Global:ModoRevert = $false
$Global:SectionProfileMode = 'esencial'
$Global:PostRunPower = 'none'
$Global:QuietProgress = $false
$Global:Inicio = $null

function Log-Sesion($linea) {
    if ($Global:SesionLog) {
        try { Add-Content -Path $Global:SesionLog -Value $linea -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    }
}

function Emit($texto, $tipo) {
    Write-Con $texto $tipo
    Log-Sesion $texto
}

function Start-BSRun($tools, $revert) {
    if ($Global:Running) {
        [void](Show-WDMDialog -Title 'DeMente' -Message 'Ya hay una ejecucion en curso.' -Buttons Ok -Tone Warn)
        return
    }
    $tools = @($tools | Where-Object { $_ })
    if ($tools.Count -eq 0) {
        [void](Show-WDMDialog -Title 'DeMente' -Message 'No hay herramientas para ejecutar. Marca al menos una opcion (o sali del modo DEFAULT WINDOWS si queres aplicar limpiezas).' -Buttons Ok -Tone Warn)
        return
    }

    if ($revert) {
        $tools = @($tools | Where-Object { $_.Revert })
        if ($tools.Count -eq 0) { return }
    }

    $peligrosas = @($tools | Where-Object { $_.Risk -eq 'danger' -and -not $revert })
    if ($peligrosas.Count -gt 0) {
        $lista = ($peligrosas | ForEach-Object { "   - " + $_.Name }) -join "`n"
        $okRisk = Show-WDMDialog -Title 'Confirmar acciones de riesgo' -Message ("Las siguientes acciones hacen cambios dificiles de deshacer:`n`n$lista`n`nSe recomienda crear un punto de restauracion antes.`n`nContinuar?") -Buttons YesNo -Tone Danger
        if (-not $okRisk) { return }
    }

    # -- PREVISUALIZACION antes de ejecutar --
    $nClean = @($tools | Where-Object { $_.Cat -eq 'clean' }).Count
    $nPerf  = @($tools | Where-Object { $_.Cat -eq 'perf' }).Count
    $nPriv  = @($tools | Where-Object { $_.Cat -eq 'privacy' }).Count
    $nSec   = @($tools | Where-Object { $_.Cat -eq 'sec' }).Count
    $nRep   = @($tools | Where-Object { $_.Cat -eq 'repair' }).Count
    $nInfo  = @($tools | Where-Object { $_.Cat -eq 'info' }).Count
    $nRev   = @($tools | Where-Object { $_.Revert }).Count
    $nDanger= @($tools | Where-Object { $_.Risk -eq 'danger' }).Count
    $modoTxt = if ($revert) { 'RESTAURAR DEFAULT WINDOWS' } else { 'APLICAR PROPUESTA DEMENTE' }
    $lineas = @("VAS A HACER ESTO ($modoTxt)", "")
    if ($nClean -gt 0) { $lineas += "Limpieza: $nClean sector(es)" }
    if ($nPerf  -gt 0) { $lineas += "Rendimiento: $nPerf cambio(s)" }
    if ($nPriv  -gt 0) { $lineas += "Privacidad: $nPriv ajuste(s)" }
    if ($nSec   -gt 0) { $lineas += "Seguridad: $nSec accion(es)" }
    if ($nRep   -gt 0) { $lineas += "Reparacion: $nRep tarea(s)" }
    if ($nInfo  -gt 0) { $lineas += "Informacion: $nInfo consulta(s)" }
    $lineas += ""
    $lineas += "Total: $($tools.Count) tarea(s)"
    $lineas += "Reversibles: $nRev"
    if ($nDanger -gt 0) { $lineas += "Riesgo alto: $nDanger (ya confirmadas)" }
    $lineas += ""
    $lineas += "Cada herramienta registra lo que hace. Podes detener en la Consola."
    $lineas += ""
    $lineas += "Continuar?"
    try {
        $prevOk = Show-WDMDialog -Title 'DeMente - Previsualizacion' -Message ($lineas -join "`n") -Buttons YesNo -Tone Info
    } catch {
        $prevOk = ([System.Windows.MessageBox]::Show(($lineas -join "`n"), 'DeMente - Previsualizacion', 'YesNo', 'Question') -eq 'Yes')
    }
    if (-not $prevOk) {
        try { Emit "[i] Ejecucion cancelada por el usuario." 'info' } catch { }
        return
    }

    $Global:ModoRevert = [bool]$revert
    $Global:SesionLog = Join-Path $Global:WDMLogs ("sesion_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $Global:Inicio = Get-Date
    $Global:Cola.Clear()
    $Global:ExecutedIds = @()

    if ($ChkRestore.IsChecked -and -not $revert) {
        try {
            Emit "[i] Creando punto de restauracion (puede tardar)..." 'info'
            $rpName = "DeMente $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            Checkpoint-Computer -Description $rpName -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Emit "[OK] Punto de restauracion: $rpName" 'ok'
        } catch {
            Emit "[!] No se pudo crear punto de restauracion: $($_.Exception.Message)" 'warn'
            Emit "[i] Activa Proteccion del sistema en el disco C: si esta desactivada." 'info'
        }
    }
    foreach ($t in $tools) {
        $Global:Cola.Enqueue($t)
        $Global:ExecutedIds += $t.Id
    }

    $Global:TotalTareas = $Global:Cola.Count
    $Global:HechasTareas = 0
    $Global:Running = $true
    $BtnExecute.IsEnabled = $false
    (UI 'BtnConCancel').IsEnabled = $true

    Show-View 'console'
    $modo = if ($revert) { "REVERSION" } else { "EJECUCION" }
    Emit ""; Emit ("=" * 78) 'head'
    Emit "  DeMente - v1.0.0.1 - $modo de $($Global:TotalTareas) tarea(s)" 'head'
    Emit "  $(Get-Date -Format 'dddd dd/MM/yyyy HH:mm:ss')  |  $env:COMPUTERNAME  |  $env:USERNAME" 'dim'
    Emit "  Registro: $($Global:SesionLog)" 'dim'
    Emit ("=" * 78) 'head'
    Next-BSTask
}

function Next-BSTask {
    if ($Global:Cola.Count -eq 0) { Finish-BSRun; return }

    $t = $Global:Cola.Dequeue()
    $Global:TareaActual = $t
    $Global:QuietProgress = ($t.Id -in @('repair-sfc','repair-dism','repair-sequence','repair-chkdsk','sec-defender-scan','sec-yara-quick','sec-yara-full'))
    if ($Global:QuietProgress) { $Global:LastQuietLogBeat = Get-Date }
    $Global:LastProgressUpdate = Get-Date
    $Global:SpinnerIdx = 0
    $Global:HechasTareas++
    $pct = [math]::Round(($Global:HechasTareas - 1) / $Global:TotalTareas * 100, 0)
    $ConBar.Value = $pct
    $ConTask.Text = "$($Global:HechasTareas)/$($Global:TotalTareas)  -  $($t.Name)"
    $ConStatus.Text = $t.Desc

    $codigo = if ($Global:ModoRevert -and $t.Revert) { $t.Revert } else { $t.Code }
    Emit ""; Emit ("-" * 78) 'dim'
    Emit ">> [$($Global:HechasTareas)/$($Global:TotalTareas)] $($t.Name)" 'step'
    Emit ("-" * 78) 'dim'

    $script = $Global:Prelude + "`r`n`r`n" + $codigo
    $sf = Join-Path $Global:WDMTmp ("task_" + $t.Id + "_" + [Guid]::NewGuid().ToString("N").Substring(0, 6) + ".ps1")
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($sf, $script, $utf8bom)

    if ($t.Run -eq 'term') {
        Emit "[i] Esta herramienta necesita su propia ventana." 'info'
        $tail = "`r`nWrite-Host ''`r`nWrite-Host '--- Tarea finalizada. Pulsa ENTER para cerrar. ---'`r`nRead-Host | Out-Null"
        Add-Content -Path $sf -Value $tail -Encoding UTF8
        try {
            Start-Process $Global:PsExe -ArgumentList "-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$sf`""
            Emit "[OK] Ventana lanzada." 'ok'
        }
        catch { Emit "[X] No se pudo abrir la ventana." 'err' }
        $window.Dispatcher.BeginInvoke([Action] { Next-BSTask }, 'Background') | Out-Null
        return
    }

    $Global:OutFile = Join-Path $Global:WDMTmp ("out_" + [Guid]::NewGuid().ToString("N").Substring(0, 8) + ".log")
    Set-Content -Path $Global:OutFile -Value "" -Encoding UTF8
    $Global:TailPos = 0
    $Global:Pending = ''

    try {
        if (-not (Test-Path $Global:PsExe)) {
            Emit "[X] No se encuentra powershell.exe: $($Global:PsExe)" 'err'
            $Global:Proc = $null
            $window.Dispatcher.BeginInvoke([Action] { Next-BSTask }, 'Background') | Out-Null
            return
        }
        if (-not (Test-Path $sf)) {
            Emit "[X] No se pudo crear el script temporal de la tarea." 'err'
            $Global:Proc = $null
            $window.Dispatcher.BeginInvoke([Action] { Next-BSTask }, 'Background') | Out-Null
            return
        }
        Emit "[i] Iniciando: $($t.Id) ..." 'info'
        $Global:Proc = Start-Process -FilePath $Global:PsExe `
            -ArgumentList "-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-File", "`"$sf`"" `
            -RedirectStandardOutput $Global:OutFile `
            -RedirectStandardError ($Global:OutFile + ".err") `
            -NoNewWindow -PassThru -ErrorAction Stop
        if (-not $Global:Proc) {
            Emit "[X] Start-Process no devolvio proceso." 'err'
            $window.Dispatcher.BeginInvoke([Action] { Next-BSTask }, 'Background') | Out-Null
        }
    }
    catch {
        Emit ("[X] No se pudo iniciar la tarea: " + $_.Exception.Message) 'err'
        $Global:Proc = $null
        $window.Dispatcher.BeginInvoke([Action] { Next-BSTask }, 'Background') | Out-Null
    }
}

function Read-Tail {
    if (-not $Global:OutFile -or -not (Test-Path $Global:OutFile)) { return '' }
    try {
        $fs = [System.IO.File]::Open($Global:OutFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($fs.Length -le $Global:TailPos) { $fs.Close(); return '' }
        $len = [int]([Math]::Min(262144, $fs.Length - $Global:TailPos))
        $null = $fs.Seek($Global:TailPos, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] $len
        $n = $fs.Read($buf, 0, $len)
        $fs.Close()
        $Global:TailPos += $n
        $texto = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
        # sfc.exe escribe en UTF-16 (cada letra seguida de un byte nulo) aunque
        # se redirija a archivo. Leido como UTF-8, "45%" llega como "4<NUL>5<NUL>%"
        # y no matchea ningun regex: por eso nunca se veia el % de SFC, y la
        # linea "[OK] ..." que escribe PowerShell justo despues quedaba pegada
        # a esa basura y se descartaba. Sacando los nulos, las letras y numeros
        # ASCII vuelven a ser legibles.
        return ($texto -replace "`0", '')
    }
    catch { return '' }
}

<#
.SYNOPSIS
    Traduce lo que esta pasando en una tarea larga (SFC/DISM/etc.) a una frase
    corta y humana, en vez de mostrar el texto crudo de la herramienta.
#>
function Get-DMFraseHumana {
    param([string]$TaskId, [string]$Linea, [int]$Pct)
    switch -Regex ($TaskId) {
        'repair-sfc' {
            if ($Pct -lt 100) { return 'Comparando tus archivos del sistema contra el original de Windows...' }
            return 'Verificacion terminada.'
        }
        'repair-dism' {
            if ($Linea -match 'Comprobando|Checking|Analizando') { return 'Revisando si la imagen de Windows tiene daños...' }
            if ($Pct -lt 100) { return 'Descargando/reparando componentes de Windows...' }
            return 'Reparacion de componentes terminada.'
        }
        'repair-sequence' {
            if ($Pct -lt 100) { return 'Reparando en orden (esto puede tardar varios minutos)...' }
            return 'Secuencia de reparacion terminada.'
        }
        'repair-chkdsk' { return 'Revisando el disco...' }
        'sec-defender-scan' { return 'Escaneo rapido de Defender en curso (sin % es normal)...' }
        'sec-yara-quick' { return 'YARA revisando Descargas y TEMP...' }
        'sec-yara-full' { return 'YARA revisando la carpeta elegida...' }
        default { return 'Trabajando...' }
    }
}

function Drain-Output {
    $txt = Read-Tail
    if (-not $txt) { return }
    $Global:Pending += $txt
    # DISM/SFC animan el % con \r SOLO (sin \n), para reescribir la misma
    # linea en una consola real. Antes esto no se trataba como fin de linea,
    # asi que todo el texto se acumulaba en un unico "pendiente" gigante y
    # el % nunca se extraia hasta que aparecia un \n real (a veces recien al
    # terminar la fase). Por eso se veia "congelado en 0%". Ahora \r solo
    # tambien corta linea, igual que en una consola real.
    $normalizado = $Global:Pending -replace "`r`n", "`n"
    $partes = $normalizado -split '[\r\n]'
    $Global:Pending = $partes[-1]
    for ($i = 0; $i -lt $partes.Count - 1; $i++) {
        $line = $partes[$i]
        if ($Global:QuietProgress) {
            # Una sola linea de estado: extraer % si existe; no inundar el log
            if ($line -match '(\d{1,3})[.,]?\d*\s*%') {
                $pct = [int]$Matches[1]
                if ($pct -ge 0 -and $pct -le 100) {
                    try {
                        $name = if ($Global:TareaActual) { $Global:TareaActual.Name } else { 'Tarea' }
                        $fraseTxt = Get-DMFraseHumana -TaskId $Global:TareaActual.Id -Linea $line -Pct $pct
                        $ConStatus.Text = ("{0}  ·  {1} %  ·  {2}" -f $name, $pct, $fraseTxt)
                        $Global:LastProgressUpdate = Get-Date
                    } catch { }
                }
            } elseif ($line -match '^\[(OK|X|!|i)\]' -or $line -match '^(>>|===)') {
                Emit $line
            }
            # resto de ruido de SFC/DISM: ignorar
        } else {
            Emit $line
        }
    }
}

function Flush-Errors {
    $ef = $Global:OutFile + ".err"
    if ($ef -and (Test-Path $ef)) {
        $c = Get-Content $ef -Raw -ErrorAction SilentlyContinue
        if ($c -and $c.Trim()) {
            foreach ($l in ($c -split "`r?`n")) { if ($l.Trim()) { Emit "[X] $l" 'err' } }
        }
        Remove-Item $ef -Force -ErrorAction SilentlyContinue
    }
}

function Finish-BSRun {
    $Global:Running = $false
    $Global:Proc = $null
    $Global:QuietProgress = $false
    $ConBar.Value = 100
    (UI 'BtnConCancel').IsEnabled = $false
    $dur = if ($Global:Inicio) { (Get-Date) - $Global:Inicio } else { New-TimeSpan }
    $doneIds = @($Global:ExecutedIds)
    Emit ""; Emit ("=" * 78) 'head'
    Emit "  PROCESO COMPLETADO  -  $($Global:HechasTareas) tarea(s) en $([math]::Round($dur.TotalMinutes,1)) min" 'head'
    Emit "  Registro: $($Global:SesionLog)" 'dim'
    if ($doneIds -and $doneIds.Count -gt 0) {
        Emit ("  Ejecutadas: {0}" -f (($doneIds | Select-Object -First 12) -join ', ')) 'dim'
    }
    Emit "  Tip: F5 o Analizar para refrescar el panel (no se reanaliza solo)." 'dim'
    Emit ("=" * 78) 'head'
    $ConTask.Text = "Completado: $($Global:HechasTareas) tarea(s)"
    $ConStatus.Text = "Duracion: $([math]::Round($dur.TotalMinutes,1)) min. F5 para reanalizar."
    $ConFoot.Text = "Ultima ejecucion: $(Get-Date -Format 'HH:mm:ss')  -  reportes en Documents\DeMente"

    if ($doneIds -and $Global:Cards) {
        $Global:CargandoConfig = $true
        try {
            foreach ($c in $Global:Cards) {
                if ($doneIds -contains $c.Uid) { $c.IsChecked = $false }
            }
        } finally { $Global:CargandoConfig = $false }
    }

    # Sin esto, el panel de Salud seguia mostrando "MEJORA DISPONIBLE" para
    # cosas que se acababan de aplicar (ej: NTFS), porque $Global:Diagnostico
    # es una foto vieja que solo se renueva con un escaneo completo. Un
    # rescaneo automatico bloquearia la UI (ver nota en Start-DiagnosticoUI),
    # asi que en cambio corregimos en memoria solo los flags de lo que
    # sabemos que se acaba de aplicar con exito.
    if ($Global:Diagnostico -and $doneIds) {
        $mapaFlags = @{
            'perf-priority' = 'Win32PrioOK'
            'perf-ntfs'     = 'NtfsLastAccessOK'
        }
        foreach ($id in $doneIds) {
            if ($mapaFlags.ContainsKey($id)) {
                try { $Global:Diagnostico.($mapaFlags[$id]) = $true } catch { }
            }
        }
    }
    $Global:ExecutedIds = @()
    Update-Counter
    Save-WDMConfig
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }

    # Cierre de ciclo de energia:
    # - Por defecto NO preguntamos reinicio (PostRunPower = 'none').
    # - Solo los planes automaticos del panel ("Plan + reiniciar", etc.)
    #   dejan PostRunPower en restart/shutdown y se ejecutan sin segunda pregunta.
    # - El boton Reiniciar/Apagar del panel usa Confirm-PowerAction con dialogo.
    try {
        $pwr = $Global:PostRunPower
        if (-not $pwr) { $pwr = 'none' }
        $Global:PostRunPower = 'none'
        if ($pwr -eq 'restart') {
            Emit "[i] Plan con reinicio: programando en 15 s..." 'info'
            Confirm-PowerAction -action 'restart' -Seconds 15 -SkipConfirm
        } elseif ($pwr -eq 'shutdown') {
            Emit "[i] Plan con apagado: programando en 15 s..." 'info'
            Confirm-PowerAction -action 'shutdown' -Seconds 15 -SkipConfirm
        }
    } catch {
        Emit ("[!] No se pudo gestionar reinicio/apagado: {0}" -f $_.Exception.Message) 'warn'
    }

    # Confianza: no rescaneo automatico pesado al terminar (el usuario elige Analizar / F5).
    Emit "[i] Listo. Si queres actualizar el panel: boton Analizar o F5." 'info'
}

(UI 'BtnConCancel').Add_Click({
        if ($Global:Proc -and -not $Global:Proc.HasExited) {
            try {
                Stop-WDMProcessTree -ProcessId $Global:Proc.Id
                Emit "[!] Tarea detenida por el usuario." 'warn'
            } catch {
                Emit "[!] No se pudo detener el proceso: $($_.Exception.Message)" 'warn'
            }
        }
        $Global:Cola.Clear()
    })

# Temporizador
$Global:TimerRun = New-Object System.Windows.Threading.DispatcherTimer
$Global:TimerRun.Interval = [TimeSpan]::FromMilliseconds(180)
$Global:TimerRun.Add_Tick({
        if (-not $Global:Running) { return }
        if ($null -eq $Global:Proc) { return }
        Drain-Output
        # SFC en particular casi no imprime % cuando su salida esta
        # redirigida (limitacion de sfc.exe, no de DeMente). Sin esto la
        # consola se ve trabada varios minutos. Si no hubo novedades en 4s,
        # mostramos que se sigue trabajando, con el tiempo transcurrido.
        if ($Global:QuietProgress -and $Global:Proc -and -not $Global:Proc.HasExited) {
            $segSinUpdate = ((Get-Date) - $Global:LastProgressUpdate).TotalSeconds
            if ($segSinUpdate -ge 4) {
                $Global:SpinnerIdx = ($Global:SpinnerIdx + 1) % 10
                $frames = @('|','/','-','\','|','/','-','\','|','/')
                $secsTotal = [math]::Round(((Get-Date) - $Global:Inicio).TotalSeconds, 0)
                $name = if ($Global:TareaActual) { $Global:TareaActual.Name } else { 'Tarea' }
                $tid = if ($Global:TareaActual) { $Global:TareaActual.Id } else { '' }
                $frase = Get-DMFraseHumana -TaskId $tid -Linea '' -Pct 0
                $ConStatus.Text = ("{0} {1}  ·  {2}  ·  {3}s (sin % un rato es normal: sigue en curso)" -f $frames[$Global:SpinnerIdx], $name, $frase, $secsTotal)
                # Cada ~25 s tambien escribir al LOG de la consola (no solo la barra de estado),
                # para que el usuario vea movimiento en el panel de texto.
                if (-not $Global:LastQuietLogBeat) { $Global:LastQuietLogBeat = $Global:Inicio }
                if (((Get-Date) - $Global:LastQuietLogBeat).TotalSeconds -ge 25) {
                    Emit ("[i] {0}: sigue trabajando ({1} s). No canceles: DISM/SFC tardan y a veces no publican %." -f $name, $secsTotal) 'info'
                    $Global:LastQuietLogBeat = Get-Date
                    $Global:LastProgressUpdate = Get-Date
                }
            }
        }
        if ($Global:Proc.HasExited) {
            Start-Sleep -Milliseconds 60
            Drain-Output
            if ($Global:Pending) { Emit $Global:Pending; $Global:Pending = '' }
            Flush-Errors
            $ec = $Global:Proc.ExitCode
            if ($ec -eq 0) { Emit "[OK] $($Global:TareaActual.Name): finalizada." 'ok' }
            else { Emit "[!] $($Global:TareaActual.Name): finalizo con codigo $ec." 'warn' }
            $Global:Proc = $null
            if ($Global:OutFile) { Remove-Item $Global:OutFile -Force -ErrorAction SilentlyContinue }
            Next-BSTask
        }
    })
$Global:TimerRun.Start()

$BtnExecute.Add_Click({
        $sel = @($Global:Cards | Where-Object { $_.IsChecked } | ForEach-Object { $Global:ToolIndex[$_.Uid] } | Where-Object { $_ })
        if ($sel.Count -eq 0) {
            [void](Show-WDMDialog -Title 'DeMente' -Message 'Marca al menos una herramienta antes de aplicar.' -Buttons Ok -Tone Info)
            return
        }
        $comoRevert = ($Global:SectionProfileMode -eq 'default')
        if ($comoRevert) {
            $sel = @($sel | Where-Object { $_.Revert })
            if ($sel.Count -eq 0) {
                [void](Show-WDMDialog -Title 'DeMente' -Message "Estas en modo DEFAULT WINDOWS: solo se pueden restaurar opciones con reversion.`n`nLas limpiezas (prefetch, papelera, cache) no se revierten: cambia a ESENCIAL/COMPLETO o desmarca DEFAULT WINDOWS y volve a aplicar." -Buttons Ok -Tone Warn)
                return
            }
        }
        Start-BSRun $sel $comoRevert
    })

# -- DASHBOARD ------------------------------------------------------------------
function HumanUI([double]$b) {
    if ($b -lt 1KB) { return "$([math]::Round($b,0)) B" }
    elseif ($b -lt 1MB) { return "{0:N1} KB" -f ($b / 1KB) }
    elseif ($b -lt 1GB) { return "{0:N1} MB" -f ($b / 1MB) }
    elseif ($b -lt 1TB) { return "{0:N2} GB" -f ($b / 1GB) }
    else { return "{0:N2} TB" -f ($b / 1TB) }
}

$DashHello.Text = "Hola, $env:USERNAME"
$DashSub.Text = "$((Get-CimInstance Win32_ComputerSystem -EA 0).Manufacturer) $((Get-CimInstance Win32_ComputerSystem -EA 0).Model)  -  $env:COMPUTERNAME  -  $($Global:Catalog.Count) herramientas disponibles"
(UI 'StCpuName').Text = (Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1).Name

$Global:CpuCounter = $null
try { $Global:CpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total"); $null = $Global:CpuCounter.NextValue() } catch { }

function Update-Stats {
    try {
        $cpu = if ($Global:CpuCounter) { [math]::Round($Global:CpuCounter.NextValue(), 0) }
        else { (Get-CimInstance Win32_Processor -EA 0 | Measure-Object LoadPercentage -Average).Average }
        if ($null -eq $cpu) { $cpu = 0 }
        if ($cpu -gt 100) { $cpu = 100 }
        (UI 'StCpu').Text = "$cpu%"; (UI 'BarCpu').Value = $cpu

        $os = Get-CimInstance Win32_OperatingSystem -EA 0
        if ($os) {
            $tot = $os.TotalVisibleMemorySize * 1KB
            $lib = $os.FreePhysicalMemory * 1KB
            $pc = [math]::Round((($tot - $lib) / $tot) * 100, 0)
            (UI 'StRam').Text = "$pc%"; (UI 'BarRam').Value = $pc
            (UI 'StRamTxt').Text = "$(HumanUI ($tot-$lib)) de $(HumanUI $tot)"
            $up = Get-WDMSessionUptime
            (UI 'StUp').Text = if ($up.TotalDays -ge 1) { "$([int]$up.TotalDays)d $($up.Hours)h" } elseif ($up.TotalHours -ge 1) { "$($up.Hours)h $($up.Minutes)m" } else { "$([int]$up.TotalMinutes)m" }
            (UI 'StUpTxt').Text = "Sesion actual"
        }

        $v = Get-Volume -DriveLetter $env:SystemDrive[0] -EA 0
        if ($v -and $v.Size -gt 0) {
            $pd = [math]::Round((($v.Size - $v.SizeRemaining) / $v.Size) * 100, 0)
            (UI 'StDisk').Text = "$pd%"; (UI 'BarDisk').Value = $pd
            (UI 'StDiskTxt').Text = "$(HumanUI $v.SizeRemaining) libres de $(HumanUI $v.Size)"
            $col = if ($pd -gt 90) { 'AccentRed' } elseif ($pd -gt 78) { 'AccentYellow' } else { 'AccentGreen' }
            (UI 'StDisk').Foreground = Brush $col; (UI 'BarDisk').Foreground = Brush $col
        }
    }
    catch { }
}

function Format-WDMSizeMB([double]$mb) {
    if ($null -eq $mb -or $mb -le 0) { return 'poco o nada' }
    if ($mb -ge 1024) { return ('{0:N1} GB' -f ($mb / 1024)) }
    if ($mb -ge 1) { return ('{0:N0} MB' -f $mb) }
    return 'poco o nada'
}

function Invoke-WDMDashAction([string]$id) {
    if ($id -eq 'dm-quick') {
        $aa = Get-WDMQuickActions
        if (@($aa).Count -eq 0) {
            [void](Show-WDMDialog -Title 'DeMente' -Message 'No hay mejoras rapidas pendientes.' -Buttons Ok -Tone Info)
        } else { Start-BSRun $aa $false }
        return
    }
    if ($id -eq 'dm-auto-rapido')   { Start-WDMAutoMode -Modo 'rapido'   -AlTerminar 'none'; return }
    if ($id -eq 'dm-auto-demente')  { Start-WDMAutoMode -Modo 'demente'  -AlTerminar 'none'; return }
    if ($id -eq 'dm-auto-completo') { Start-WDMAutoMode -Modo 'completo' -AlTerminar 'none'; return }
    if ($id -eq 'dm-auto-default')  { Start-WDMAutoMode -Modo 'default'  -AlTerminar 'none'; return }
    if ($id -eq 'dm-auto-demente-reboot') { Start-WDMAutoMode -Modo 'demente' -AlTerminar 'restart'; return }
    if ($id -eq 'dm-diag') { Start-DiagnosticoUI; return }
    if ($id -eq 'dm-clean-esencial') {
        Show-View 'clean'
        Select-SectionProfile 'esencial'
        return
    }
    if ($id -eq 'dm-clean-completo') {
        Show-View 'clean'
        Select-SectionProfile 'completo'
        return
    }
    if ($id -eq 'dm-sec') { Show-View 'sec'; return }
    if ($id -eq 'dm-perf') { Show-View 'perf'; return }
    if ($id -eq 'power-restart') { Confirm-PowerAction 'restart'; return }
    if ($id -eq 'power-shutdown') { Confirm-PowerAction 'shutdown'; return }
    $t = $Global:ToolIndex[$id]
    if ($t) { Start-BSRun @($t) $false }
}


function Set-WDMFlatButtonTemplate([System.Windows.Controls.Button]$btn) {
    # Mata el chrome nativo de Windows (hover blanco) en botones armados en codigo.
    $btn.OverridesDefaultStyle = $true
    $btn.BorderThickness = New-Object System.Windows.Thickness(0)
    $btn.Background = [System.Windows.Media.Brushes]::Transparent
    $tpl = New-Object System.Windows.Controls.ControlTemplate ([System.Windows.Controls.Button])
    $factory = New-Object System.Windows.FrameworkElementFactory ([System.Windows.Controls.ContentPresenter])
    $factory.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
    $factory.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)
    $tpl.VisualTree = $factory
    $btn.Template = $tpl
}

function New-HeroCard($titulo, $iconHex, $linea1, $linea2, $linea3, $colorKey, $accion) {
    # Tarjeta grande del panel: icono Segoe MDL2 + borde de acento. NO usa GhostBtn (Height fijo 34).
    $b = New-Object System.Windows.Controls.Button
    $b.MinHeight = 128
    $b.Margin = '0,0,12,12'
    $b.Cursor = 'Hand'
    $b.HorizontalContentAlignment = 'Stretch'
    $b.HorizontalAlignment = 'Stretch'
    $b.Padding = '0'
    $b.Focusable = $true
    Set-WDMFlatButtonTemplate $b

    $outer = New-Object System.Windows.Controls.Border
    $outer.Background = Brush 'Zinc900'
    $outer.BorderBrush = Brush 'Zinc800'
    $outer.BorderThickness = New-Object System.Windows.Thickness(1)
    $outer.CornerRadius = New-Object System.Windows.CornerRadius(14)
    $outer.Padding = '14,14,14,14'

    # Franja de color a la izquierda
    $stripGrid = New-Object System.Windows.Controls.Grid
    $sc0 = New-Object System.Windows.Controls.ColumnDefinition
    $sc0.Width = [System.Windows.GridLength]::new(4)
    $sc1 = New-Object System.Windows.Controls.ColumnDefinition
    $sc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $stripGrid.ColumnDefinitions.Add($sc0) | Out-Null
    $stripGrid.ColumnDefinitions.Add($sc1) | Out-Null

    $strip = New-Object System.Windows.Controls.Border
    $strip.Background = Brush $colorKey
    $strip.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $strip.Margin = '0,2,12,2'
    [System.Windows.Controls.Grid]::SetColumn($strip, 0)
    $stripGrid.Children.Add($strip) | Out-Null

    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(58)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $grid.ColumnDefinitions.Add($c0) | Out-Null
    $grid.ColumnDefinitions.Add($c1) | Out-Null

    $iconBox = New-Object System.Windows.Controls.Border
    $iconBox.Width = 52; $iconBox.Height = 52
    $iconBox.CornerRadius = New-Object System.Windows.CornerRadius(12)
    try {
        $base = (Brush $colorKey).Color
        $iconBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, $base.R, $base.G, $base.B))
    } catch { $iconBox.Background = Brush 'Zinc800' }
    $iconBox.VerticalAlignment = 'Top'
    $it = New-Object System.Windows.Controls.TextBlock
    try { $it.Text = Glyph $iconHex } catch { $it.Text = Glyph 'E946' }
    $it.FontFamily = 'Segoe MDL2 Assets'
    $it.FontSize = 22
    $it.Foreground = Brush $colorKey
    $it.HorizontalAlignment = 'Center'
    $it.VerticalAlignment = 'Center'
    $iconBox.Child = $it
    [System.Windows.Controls.Grid]::SetColumn($iconBox, 0)
    $grid.Children.Add($iconBox) | Out-Null

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '12,0,0,0'
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = $titulo; $t1.FontSize = 13; $t1.FontWeight = 'Bold'; $t1.Foreground = Brush 'Zinc400'
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $linea1; $t2.FontSize = 14; $t2.FontWeight = 'SemiBold'; $t2.Foreground = Brush 'Zinc100'; $t2.Margin = '0,5,0,0'; $t2.TextWrapping = 'Wrap'
    $t3 = New-Object System.Windows.Controls.TextBlock
    $t3.Text = $linea2; $t3.FontSize = 12; $t3.Foreground = Brush $colorKey; $t3.Margin = '0,5,0,0'; $t3.TextWrapping = 'Wrap'
    $t4 = New-Object System.Windows.Controls.TextBlock
    $t4.Text = $linea3; $t4.FontSize = 11; $t4.Foreground = Brush 'Zinc500'; $t4.Margin = '0,4,0,0'; $t4.TextWrapping = 'Wrap'
    $sp.Children.Add($t1) | Out-Null
    $sp.Children.Add($t2) | Out-Null
    $sp.Children.Add($t3) | Out-Null
    $sp.Children.Add($t4) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $grid.Children.Add($sp) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($grid, 1)
    $stripGrid.Children.Add($grid) | Out-Null
    $outer.Child = $stripGrid
    $b.Content = $outer
    $b.ToolTip = "$titulo`n$linea1`n$linea2`n$linea3"

    $b.Add_MouseEnter({
        param($s,$e)
        try { $outer.BorderBrush = Brush $colorKey; $outer.Background = Brush 'Zinc850' } catch { }
    }.GetNewClosure())
    $b.Add_MouseLeave({
        param($s,$e)
        try { $outer.BorderBrush = Brush 'Zinc800'; $outer.Background = Brush 'Zinc900' } catch { }
    }.GetNewClosure())

    $id = $accion
    $b.Add_Click({
        param($sender, $e)
        Invoke-WDMDashAction $id
    }.GetNewClosure())
    return $b
}

function New-DashboardActionButton($texto,$sub,$colorKey,$accion,$iconHex='E8B7') {
    # Atajo del panel: sin GhostBtn (Height 34 rompe el layout).
    $b = New-Object System.Windows.Controls.Button
    $b.Width = 250
    $b.Height = 70
    $b.Margin = '0,0,10,10'
    $b.Cursor = 'Hand'
    $b.HorizontalContentAlignment = 'Left'
    $b.Padding = '0'
    Set-WDMFlatButtonTemplate $b

    $bd = New-Object System.Windows.Controls.Border
    $bd.Background = Brush 'Zinc900'
    $bd.BorderBrush = Brush 'Zinc800'
    $bd.BorderThickness = New-Object System.Windows.Thickness(1)
    $bd.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $bd.Padding = '12,10'

    $g = New-Object System.Windows.Controls.Grid
    $gc0 = New-Object System.Windows.Controls.ColumnDefinition; $gc0.Width = [System.Windows.GridLength]::new(36)
    $gc1 = New-Object System.Windows.Controls.ColumnDefinition; $gc1.Width = [System.Windows.GridLength]::new(1, 'Star')
    $g.ColumnDefinitions.Add($gc0) | Out-Null
    $g.ColumnDefinitions.Add($gc1) | Out-Null

    $ic = New-Object System.Windows.Controls.TextBlock
    try { $ic.Text = Glyph $iconHex } catch { $ic.Text = Glyph 'E8B7' }
    $ic.FontFamily = 'Segoe MDL2 Assets'
    $ic.FontSize = 16
    $ic.Foreground = Brush $colorKey
    $ic.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($ic, 0)
    $g.Children.Add($ic) | Out-Null

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '6,0,0,0'
    $tx = New-Object System.Windows.Controls.TextBlock
    $tx.Text = $texto
    $tx.FontSize = 12.5
    $tx.FontWeight = 'SemiBold'
    $tx.Foreground = Brush 'Zinc200'
    $sx = New-Object System.Windows.Controls.TextBlock
    $sx.Text = $sub
    $sx.FontSize = 10.5
    $sx.Foreground = Brush 'Zinc500'
    $sx.Margin = '0,3,0,0'
    $sx.TextWrapping = 'Wrap'
    $sp.Children.Add($tx) | Out-Null
    $sp.Children.Add($sx) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null
    $bd.Child = $g
    $b.Content = $bd
    $b.ToolTip = "$texto`n$sub"

    $b.Add_MouseEnter({ try { $bd.BorderBrush = Brush $colorKey } catch { } }.GetNewClosure())
    $b.Add_MouseLeave({ try { $bd.BorderBrush = Brush 'Zinc800' } catch { } }.GetNewClosure())

    $id = $accion
    $b.Add_Click({
        param($sender, $e)
        Invoke-WDMDashAction $id
    }.GetNewClosure())
    return $b
}

function Update-HeroCards {
    try {
        if (-not $HeroGrid) { return }
        $HeroGrid.Children.Clear()
        $d = $Global:Diagnostico

        $rapid = ' - '
        $deep = ' - '
        $cm = ' - '
        if ($d) {
            $rapid = Format-WDMSizeMB ([double]$d.CleanRapidMB)
            $deep = Format-WDMSizeMB ([double]$d.CleanDeepMB)
            $cm = Format-WDMSizeMB ([double]$d.CleanMgrMB)
        }
        # Iconos Segoe MDL2: E74D delete, E72E shield, E945 speed, E9D9 scan
        $HeroGrid.Children.Add((New-HeroCard 'LIMPIEZA' 'E74D' `
            ("Rapido $rapid  ·  Profundo $deep") `
            ("cleanmgr de Windows: ~$cm") `
            'Perfil ESENCIAL: temp, papelera, navegadores, caches de apps.' `
            'AccentGreen' 'dm-clean-esencial')) | Out-Null

        $defTxt = 'Defender: sin datos'
        $yaraTxt = 'YARA: sin datos'
        $secColor = 'AccentBlue'
        if ($d) {
            if ($d.DefenderOk) { $defTxt = 'Defender: proteccion en tiempo real OK' }
            else { $defTxt = 'Defender: revisar proteccion'; $secColor = 'AccentYellow' }
            $yaraTxt = "YARA: $($d.YaraEstado)"
        }
        $HeroGrid.Children.Add((New-HeroCard 'SEGURIDAD' 'E72E' `
            $defTxt `
            $yaraTxt `
            'Estado de motores. No aplica cambios al tocar la tarjeta.' `
            $secColor 'dm-sec')) | Out-Null

        $perfLine = 'Tweaks: esperando analisis'
        $perfSub = 'Cuenta aplicados vs DEFAULT de Windows'
        $perfColor = 'AccentPurple'
        if ($d -and $d.PerfTotal -gt 0) {
            $perfLine = ("{0} de {1} optimizaciones DeMente activas" -f $d.PerfApplied, $d.PerfTotal)
            $perfSub = ("{0} siguen en valor DEFAULT de Windows" -f $d.PerfDefault)
            if ($d.PerfApplied -lt ($d.PerfTotal / 2)) { $perfColor = 'AccentOrange' }
            elseif ($d.PerfApplied -ge ($d.PerfTotal * 0.8)) { $perfColor = 'AccentGreen' }
        }
        $regLine = if ($d -and $d.RegFindings -gt 0) { "$($d.RegFindings) residuo(s) de registro verificables" } else { 'Registro: sin residuos evidentes en zonas seguras' }
        $HeroGrid.Children.Add((New-HeroCard 'RENDIMIENTO' 'E945' `
            $perfLine `
            $perfSub `
            $regLine `
            $perfColor 'dm-perf')) | Out-Null

        $scanLine = 'Multiescaneo listo'
        $scanSub = 'Hardware · disco · Windows · inicio · privacidad · seguridad · YARA · limpieza'
        if ($d -and $d.DiagnosticoCompleto) {
            $n = @($d.Comprobaciones).Count
            $scanLine = ("Completado en {0}s · {1} comprobaciones" -f $d.DuracionSeg, $n)
            $scanSub = "$(Get-Date -Format 'HH:mm:ss') · F5 o toca para repetir (solo diagnostico)"
        } else {
            $scanLine = 'Todavia no hay un analisis completo'
            $scanSub = 'Toca para escanear el equipo ahora'
        }
        $HeroGrid.Children.Add((New-HeroCard 'MULTIESCANEO' 'E9D9' `
            $scanLine `
            $scanSub `
            'No modifica el sistema: solo lee y resume el estado real.' `
            'AccentBlue' 'dm-diag')) | Out-Null
    } catch {
        Write-Host "[!] Update-HeroCards: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-WDMQuickActions {
    # Hasta 3-5 acciones concretas segun diagnostico (no una lista infinita).
    $a = @()
    $d = $Global:Diagnostico
    if (-not $d) { return @() }

    if ($d.TempCacheMB -gt 200 -or $d.DiscoPocoEspacio) {
        if ($Global:ToolIndex.ContainsKey('clean-temp')) { $a += $Global:ToolIndex['clean-temp'] }
    }
    if (-not $d.Win32PrioOK -and $Global:ToolIndex.ContainsKey('perf-priority')) {
        $a += $Global:ToolIndex['perf-priority']
    }
    if (-not $d.NtfsLastAccessOK -and $Global:ToolIndex.ContainsKey('perf-ntfs')) {
        $a += $Global:ToolIndex['perf-ntfs']
    }
    if (-not $d.SystemResponsivenessOK -and $Global:ToolIndex.ContainsKey('perf-systemresp')) {
        $a += $Global:ToolIndex['perf-systemresp']
    }
    if (-not $d.VisualEffectsOptimized -and $Global:ToolIndex.ContainsKey('perf-visual')) {
        $a += $Global:ToolIndex['perf-visual']
    }
    if ($d.NetworkThrottling -and $Global:ToolIndex.ContainsKey('perf-network-throttle')) {
        $a += $Global:ToolIndex['perf-network-throttle']
    }
    # Hardware limitado: sugerir inicio seguro (no milagros)
    try {
        if ($d.RAMGB -gt 0 -and $d.RAMGB -lt 8 -and $Global:ToolIndex.ContainsKey('perf-startup-safe')) {
            $a += $Global:ToolIndex['perf-startup-safe']
        }
    } catch { }
    if ($d.StartupCount -gt 10 -and $Global:ToolIndex.ContainsKey('perf-startup-list')) {
        $a += $Global:ToolIndex['perf-startup-list']
    }

    return @($a | Where-Object { $_ } | Select-Object -Unique)
}




function Get-WDMAutoToolIds {
    param([ValidateSet('rapido','demente','completo','default')][string]$Modo)
    $ids = [System.Collections.Generic.List[string]]::new()
    switch ($Modo) {
        'rapido' {
            $idsRapido = @('clean-temp','clean-recycle','clean-dns','clean-clipboard','clean-thumbnail','perf-menu','perf-storage-sense') + @($Global:BrowserCleanIds)
            foreach ($x in $idsRapido) {
                if ($Global:ToolIndex.ContainsKey($x)) { [void]$ids.Add($x) }
            }
        }
        'demente' {
            foreach ($cat in @('clean','perf','repair')) {
                foreach ($id in @($Global:ProfileEsencial[$cat])) {
                    if ($id -eq 'repair-network-hard') { continue }
                    if ($Global:ToolIndex.ContainsKey($id)) { [void]$ids.Add($id) }
                }
            }
        }
        'completo' {
            foreach ($cat in @('clean','perf','repair')) {
                foreach ($id in @($Global:ProfileCompleto[$cat])) {
                    $t = $Global:ToolIndex[$id]
                    if (-not $t) { continue }
                    if ($t.Risk -eq 'danger') { continue }
                    if ($id -eq 'repair-network-hard') { continue }
                    [void]$ids.Add($id)
                }
            }
        }
        'default' {
            foreach ($t in $Global:Catalog) {
                if ($t.Cat -in @('perf','privacy') -and $t.Revert) { [void]$ids.Add($t.Id) }
            }
        }
    }
    $order = @{ clean = 0; perf = 1; privacy = 2; sec = 3; repair = 4; reg = 0 }
    return @($ids | Select-Object -Unique | Sort-Object {
        $c = $Global:ToolIndex[$_].Cat
        if ($order.ContainsKey($c)) { $order[$c] } else { 9 }
    }, { $_ })
}

function Start-WDMAutoMode {
    param(
        [ValidateSet('rapido','demente','completo','default')][string]$Modo,
        [ValidateSet('ask','restart','shutdown','none')][string]$AlTerminar = 'none'
    )
    if ($Global:Running) {
        [void](Show-WDMDialog -Title 'DeMente' -Message 'Ya hay una ejecucion en curso.' -Buttons Ok -Tone Warn)
        return
    }
    $ids = @(Get-WDMAutoToolIds -Modo $Modo)
    $tools = @($ids | ForEach-Object { $Global:ToolIndex[$_] } | Where-Object { $_ })
    if ($tools.Count -eq 0) {
        [void](Show-WDMDialog -Title 'DeMente' -Message 'No hay tareas para este modo en este equipo.' -Buttons Ok -Tone Info)
        return
    }
    $modoTxt = switch ($Modo) {
        'rapido'    { 'Mantenimiento corto' }
        'demente'   { 'Plan DeMente (esencial)' }
        'completo'  { 'A fondo (completo)' }
        'default'   { 'Volver a DEFAULT Windows' }
    }
    $nClean = @($tools | Where-Object Cat -eq 'clean').Count
    $nPerf  = @($tools | Where-Object Cat -eq 'perf').Count
    $nRep   = @($tools | Where-Object Cat -eq 'repair').Count
    $nPriv  = @($tools | Where-Object Cat -eq 'privacy').Count
    $msg = @"
$modoTxt

Limpieza: $nClean  |  Rendimiento: $nPerf  |  Reparacion: $nRep  |  Privacidad: $nPriv
Total: $($tools.Count) tarea(s)

NO se toca: IP fija del adaptador, reset agresivo de red, WMI ni acciones de riesgo alto.
La red segura solo limpia DNS.

Continuar?
"@
    if (-not (Show-WDMDialog -Title 'DeMente - Plan' -Message $msg -Buttons YesNo -Tone Info)) { return }
    $Global:PostRunPower = $AlTerminar
    $revert = ($Modo -eq 'default')
    Start-BSRun $tools $revert
}

function Show-WDMDialog {
    param(
        [string]$Title = 'DeMente',
        [string]$Message,
        [ValidateSet('Ok','YesNo')][string]$Buttons = 'Ok',
        [ValidateSet('Info','Warn','Danger')][string]$Tone = 'Info'
    )
    # Dialog modal oscuro alineado al tema DeMente (no MessageBox blanco).
    # Contrato: $true = Continuar / Entendido.
    try {
        $dlg = New-Object System.Windows.Window
        $dlg.Title = $Title
        $dlg.WindowStyle = 'None'
        $dlg.AllowsTransparency = $true
        $dlg.Background = [System.Windows.Media.Brushes]::Transparent
        $dlg.ResizeMode = 'NoResize'
        $dlg.SizeToContent = 'Height'
        $dlg.Width = 440
        $dlg.WindowStartupLocation = 'CenterOwner'
        $dlg.ShowInTaskbar = $false
        try { if ($window) { $dlg.Owner = $window } } catch { }
        $dlg.Tag = $false

        $accentColor = switch ($Tone) {
            'Danger' { [System.Windows.Media.Color]::FromRgb(239, 68, 68) }
            'Warn'   { [System.Windows.Media.Color]::FromRgb(234, 179, 8) }
            default  { [System.Windows.Media.Color]::FromRgb(59, 130, 246) }
        }
        $accent = New-Object System.Windows.Media.SolidColorBrush $accentColor
        $bg900 = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(24, 24, 27))
        $bg800 = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(39, 39, 42))
        $fg200 = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(228, 228, 231))
        $fg400 = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(161, 161, 170))
        $borderC = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(63, 63, 70))

        $outer = New-Object System.Windows.Controls.Border
        $outer.Background = $bg900
        $outer.BorderBrush = $borderC
        $outer.BorderThickness = 1
        $outer.CornerRadius = 14
        $outer.Padding = '22,18,22,18'
        try {
            $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
            $sh.BlurRadius = 28; $sh.ShadowDepth = 0; $sh.Opacity = 0.55
            $sh.Color = [System.Windows.Media.Colors]::Black
            $outer.Effect = $sh
        } catch { }

        $sp = New-Object System.Windows.Controls.StackPanel
        $hdr = New-Object System.Windows.Controls.StackPanel
        $hdr.Orientation = 'Horizontal'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9; $dot.Fill = $accent
        $dot.Margin = '0,2,10,0'; $dot.VerticalAlignment = 'Center'
        $tit = New-Object System.Windows.Controls.TextBlock
        $tit.Text = $Title; $tit.FontSize = 15; $tit.FontWeight = 'SemiBold'
        $tit.Foreground = $fg200; $tit.VerticalAlignment = 'Center'
        $hdr.Children.Add($dot) | Out-Null
        $hdr.Children.Add($tit) | Out-Null
        $sp.Children.Add($hdr) | Out-Null

        $msg = New-Object System.Windows.Controls.TextBlock
        $msg.Text = $Message
        $msg.TextWrapping = 'Wrap'
        $msg.Margin = '0,14,0,18'
        $msg.FontSize = 13
        $msg.Foreground = $fg400
        $msg.LineHeight = 20
        $sp.Children.Add($msg) | Out-Null

        $btns = New-Object System.Windows.Controls.StackPanel
        $btns.Orientation = 'Horizontal'
        $btns.HorizontalAlignment = 'Right'

        function New-WDMDlgButton([string]$text, [bool]$primary, [scriptblock]$click) {
            $b = New-Object System.Windows.Controls.Button
            $b.Height = 36; $b.MinWidth = 112; $b.Margin = '8,0,0,0'
            $b.Cursor = 'Hand'; $b.FontSize = 12.5; $b.FontWeight = 'SemiBold'
            $b.BorderThickness = 0
            $b.Padding = '16,0'
            if ($primary) {
                $b.Background = $accent
                $b.Foreground = [System.Windows.Media.Brushes]::White
            } else {
                $b.Background = $bg800
                $b.Foreground = $fg200
            }
            $b.Content = $text
            $b.Add_Click($click)
            return $b
        }

        if ($Buttons -eq 'YesNo') {
            $btns.Children.Add((New-WDMDlgButton 'Cancelar' $false {
                $dlg.Tag = $false; $dlg.Close()
            }.GetNewClosure())) | Out-Null
            $btns.Children.Add((New-WDMDlgButton 'Continuar' $true {
                $dlg.Tag = $true; $dlg.Close()
            }.GetNewClosure())) | Out-Null
        } else {
            $btns.Children.Add((New-WDMDlgButton 'Entendido' $true {
                $dlg.Tag = $true; $dlg.Close()
            }.GetNewClosure())) | Out-Null
        }
        $sp.Children.Add($btns) | Out-Null
        $outer.Child = $sp
        $dlg.Content = $outer
        $null = $dlg.ShowDialog()
        return [bool]$dlg.Tag
    } catch {
        try {
            if ($Buttons -eq 'YesNo') {
                $r = [System.Windows.MessageBox]::Show($Message, $Title, 'YesNo', 'Warning')
                return ($r -eq 'Yes')
            }
            [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
            return $true
        } catch {
            if ($Buttons -eq 'YesNo') { return $false }
            return $true
        }
    }
}

function Confirm-PowerAction {
    param(
        [ValidateSet('restart','shutdown','continue')][string]$action,
        [int]$Seconds = 15,
        [switch]$SkipConfirm
    )
    if ($action -eq 'continue') { return $false }
    if ($Seconds -lt 5) { $Seconds = 5 }
    if ($Seconds -gt 120) { $Seconds = 120 }
    $msg = switch ($action) {
        'restart'  { "Reiniciar Windows en $Seconds segundos?`n`nSe cerraran las aplicaciones abiertas.`nPara cancelar despues: shutdown /a" }
        'shutdown' { "Apagar Windows en $Seconds segundos?`n`nSe cerraran las aplicaciones abiertas.`nPara cancelar despues: shutdown /a" }
        default    { 'Continuar sin reiniciar.' }
    }
    if (-not $SkipConfirm) {
        if (-not (Show-WDMDialog -Title 'DeMente' -Message $msg -Buttons YesNo -Tone Warn)) { return $false }
    }
    $flag = if ($action -eq 'restart') { '/r' } else { '/s' }
    $cmsg = if ($action -eq 'restart') {
        "DeMente: reinicio en ${Seconds}s. Cancelar: shutdown /a"
    } else {
        "DeMente: apagado en ${Seconds}s. Cancelar: shutdown /a"
    }
    # Comentario sin caracteres raros; shutdown /c admite max ~512 chars
    $cmsg = ($cmsg -replace '[^\w\s:\./\-]', ' ').Trim()
    if ($cmsg.Length -gt 200) { $cmsg = $cmsg.Substring(0, 200) }
    try {
        # Un solo string de ArgumentList: evita que /c con espacios se parta mal
        # y que shutdown.exe imprima la ayuda (exit 1) en vez de programar.
        $argLine = "{0} /t {1} /c `"{2}`"" -f $flag, $Seconds, $cmsg
        $p = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" `
            -ArgumentList $argLine `
            -PassThru -NoNewWindow -Wait -ErrorAction Stop
        if ($p.ExitCode -eq 0) {
            try { Emit ("[OK] {0} programado en {1} s. Cancelar: shutdown /a" -f $(if ($action -eq 'restart') { 'Reinicio' } else { 'Apagado' }), $Seconds) 'ok' } catch {
                Write-Host ("[OK] {0} programado en {1} s. Cancelar: shutdown /a" -f $(if ($action -eq 'restart') { 'Reinicio' } else { 'Apagado' }), $Seconds)
            }
            return $true
        } else {
            # Reintento sin /c (algunas ediciones/políticas rechazan el comentario)
            try {
                $argLine2 = "{0} /t {1}" -f $flag, $Seconds
                $p2 = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" `
                    -ArgumentList $argLine2 `
                    -PassThru -NoNewWindow -Wait -ErrorAction Stop
                if ($p2.ExitCode -eq 0) {
                    try { Emit ("[OK] {0} programado en {1} s (sin comentario). Cancelar: shutdown /a" -f $(if ($action -eq 'restart') { 'Reinicio' } else { 'Apagado' }), $Seconds) 'ok' } catch {
                        Write-Host ("[OK] {0} programado en {1} s. Cancelar: shutdown /a" -f $(if ($action -eq 'restart') { 'Reinicio' } else { 'Apagado' }), $Seconds)
                    }
                    return $true
                }
            } catch { }
            try { Emit ("[X] shutdown.exe devolvio codigo {0}. No se programo el {1}." -f $p.ExitCode, $action) 'err' } catch {
                Write-Host ("[X] shutdown.exe devolvio codigo {0}." -f $p.ExitCode)
            }
            return $false
        }
    } catch {
        try { Emit ("[X] No se pudo programar {0}: {1}" -f $action, $_.Exception.Message) 'err' } catch {
            Write-Host ("[X] No se pudo programar {0}: {1}" -f $action, $_.Exception.Message)
        }
        return $false
    }
}

function Update-DashboardDiagnosis {

    try {
        $d = $Global:Diagnostico
        if (-not $d) { return }

        $crit = @($d.Comprobaciones | Where-Object { $_.Severidad -eq 'critical' })
        # "warn" blando: no poder leer algo o basura recuperable no es un fallo del equipo vivo
        $warnAll = @($d.Comprobaciones | Where-Object { $_.Severidad -eq 'warn' })
        $warn = @($warnAll | Where-Object {
            $n = [string]$_.Nombre
            $e = [string]$_.Estado
            # Excluir avisos blandos (no poder leer / opcionales)  -  la Memoria baja SI cuenta
            $blando = ($e -match 'NO COMPROBADO|PARCIAL|NO DISPONIBLE') -or (
                ($n -match 'YARA|Recuperable estimado|Eventos criticos') -and ($e -match 'REVISAR|NO COMPROBADO|ATENCION')
            )
            -not $blando
        })
        # Si tras filtrar no queda nada real pero habia warns blandos, no asustar
        $mejoras = @($d.Comprobaciones | Where-Object { $_.Severidad -eq 'info' -and $_.Estado -eq 'MEJORA DISPONIBLE' })
        $totalHallazgos = $crit.Count + $warn.Count

        # Numero grande = problemas reales (no un puntaje magico)
        (UI 'DashScore').Text = "$totalHallazgos"
        $detallePrincipal = $null
        if ($crit.Count -gt 0) {
            $first = $crit | Select-Object -First 1
            $detallePrincipal = $first
            $grade = "REQUIERE ATENCION`n$($first.Nombre)"
            $sb = 'AccentRed'
        } elseif ($warn.Count -gt 0) {
            $first = $warn | Select-Object -First 1
            $detallePrincipal = $first
            # El usuario tiene que ver QUE es (ej. Memoria), no solo "1"
            $grade = "PARA REVISAR`n$($first.Nombre)"
            $sb = 'AccentYellow'
        } elseif ($mejoras.Count -gt 0 -or $warnAll.Count -gt 0) {
            $grade = 'OK · MEJORAS OPCIONALES'
            $sb = 'AccentGreen'
            (UI 'DashScore').Text = '0'
            $totalHallazgos = 0
        } else {
            $grade = 'TODO OK'
            $sb = 'AccentGreen'
        }
        (UI 'DashGrade').Text = $grade
        (UI 'DashScore').Foreground = Brush $sb

        # --- LIMPIEZA / OPTIMIZAR / REPARAR (lo que el usuario pide ver) ---
        $mb = 0.0
        try { $mb = [double]$d.TempCacheMB } catch { $mb = 0 }
        if ($mb -ge 1024) { $limpiezaTxt = ("~{0:N1} GB" -f ($mb/1024)) }
        elseif ($mb -gt 0) { $limpiezaTxt = ("~{0:N0} MB" -f $mb) }
        else { $limpiezaTxt = 'poco o nada' }

        $nOpt = 0
        try {
            if ($d.MejorasDisponibles -gt 0) { $nOpt = [int]$d.MejorasDisponibles }
            else { $nOpt = @($mejoras).Count }
        } catch { $nOpt = @($mejoras).Count }

        $nRepairHints = 0
        if ($crit.Count -gt 0) { $nRepairHints += $crit.Count }
        if ($d.ErroresRecientes -gt 5) { $nRepairHints++ }
        if ($d.DiscoPocoEspacio) { $nRepairHints++ }
        $repairTxt = if ($nRepairHints -gt 0) {
            'recomendada (hay problemas prioritarios)'
        } elseif ($warn.Count -gt 0) {
            'opcional (puntos a revisar)'
        } else {
            'no necesaria por ahora'
        }

        $optTxt = if ($nOpt -gt 0) { "$nOpt mejora(s) disponibles" } else { 'sin cambios pendientes' }

        if ($detallePrincipal) {
            (UI 'DashFinding').Text = ("Revisar: {0}  -  {1}" -f $detallePrincipal.Nombre, $detallePrincipal.Detalle)
        } else {
            (UI 'DashFinding').Text = "Optimizar: $optTxt  |  Reparar: $repairTxt"
        }

        $subParts = @()
        if ($crit.Count -gt 0) {
            $subParts += ($crit | ForEach-Object { "$($_.Nombre): $($_.Detalle)" }) -join ' | '
        } elseif ($warn.Count -gt 0) {
            $subParts += ($warn | Select-Object -First 3 | ForEach-Object { "$($_.Nombre): $($_.Detalle)" }) -join ' | '
            if ($warn.Count -gt 1) { $subParts += ("(+{0} mas)" -f ($warn.Count - 1)) }
        } else {
            $subParts += 'Estado en vivo coherente: sin problemas prioritarios.'
            if ($warnAll.Count -gt 0) {
                $soft = ($warnAll | Select-Object -First 2 | ForEach-Object { $_.Nombre }) -join ', '
                $subParts += "Avisos opcionales: $soft"
            }
        }
        $cpuTxt = if ($d.CPUCores) { "$($d.CPUCores) nucleos" } else { 'N/D' }
        $ramTxt = if ($d.RAMTotalGB) { "$($d.RAMTotalGB) GB" } else { 'N/D' }
        $diskTxt = "$(if($d.TieneSSD){'SSD/NVMe'}else{'HDD'}) | $($d.DiscoLibrePct)% libre"
        $subParts += "CPU $cpuTxt | RAM $ramTxt | Disco $diskTxt"
        if ($d.StartupCount -gt 0) { $subParts += "$($d.StartupCount) programas al inicio" }
        if ($d.DefenderOk) { $subParts += 'Defender OK' } else { $subParts += 'Defender: revisar' }
        if ($d.YaraEstado) { $subParts += "YARA: $($d.YaraEstado)" }
        (UI 'DashFindingSub').Text = ($subParts -join '  |  ')

        # Detalle compacto de areas
        $areaLine = "Optimizaciones: $optTxt  |  Reparacion: $repairTxt  |  Detalle de MB: seccion Limpieza"
        if ($d.WinVersion) { $areaLine += "  |  $($d.WinVersion)" }
        (UI 'DashDiagDetail').Text = $areaLine
        (UI 'DashDiagBar').Value = 100
        $nAreas = if ($d.Areas) { @($d.Areas.Keys).Count } else { 0 }
        (UI 'DashDiagTime').Text = "Multiescaneo: $($d.DuracionSeg)s  |  $($d.Comprobaciones.Count) comprobaciones  |  $nAreas areas  |  $(Get-Date -Format 'HH:mm:ss')"

        # Panel de mejoras: limpieza + optimizaciones + reparacion si aplica
        (UI 'ImprovePanel').Children.Clear()
        $actions = @()
        if ($mb -gt 200) {
            $tClean = $Global:ToolIndex['clean-temp']
            if ($tClean) { $actions += $tClean }
        }
        $actions += @(Get-WDMQuickActions)
        if ($nRepairHints -gt 0 -and $Global:ToolIndex.ContainsKey('repair-sequence')) {
            $actions += $Global:ToolIndex['repair-sequence']
        }
        $actions = @($actions | Where-Object { $_ } | Select-Object -Unique)
        # Mostrar como maximo 3 en el dashboard (el resto esta en cada seccion)
        if ($actions.Count -gt 3) { $actions = @($actions | Select-Object -First 3) }

        if ($actions.Count -eq 0) {
            (UI 'DashImproveTitle').Text = 'Nada urgente: limpieza baja, optimizaciones al dia, reparacion no requerida.'
            (UI 'DashImproveSub').Text = 'Igual podes explorar cada seccion o usar los perfiles ESENCIAL / COMPLETO / DEFAULT WINDOWS.'
        } else {
            (UI 'DashImproveTitle').Text = "$($actions.Count) accion(es) sugeridas segun el diagnostico"
            $rapidTxt = Format-WDMSizeMB ([double]$d.CleanRapidMB)
            $deepTxt = Format-WDMSizeMB ([double]$d.CleanDeepMB)
            $cmTxt = Format-WDMSizeMB ([double]$d.CleanMgrMB)
            (UI 'DashImproveSub').Text = "Limpieza rapida $rapidTxt · profunda $deepTxt · cleanmgr ~$cmTxt | Optimizar: $optTxt | Reparar: $repairTxt"
            foreach ($t in $actions) {
                if (-not $t) { continue }
                $desc = $t.Desc
                if ($t.Id -eq 'clean-temp' -and $mb -gt 0) {
                    $desc = "Estimado recuperable: $limpiezaTxt (temporales, caches, papelera). $desc"
                }
                (UI 'ImprovePanel').Children.Add((New-DashboardActionButton $t.Name $desc 'AccentBlue' $t.Id)) | Out-Null
            }
        }
        Update-HeroCards
    
        # --- Salud: priorizar mensaje humano del escaneo inicial ---
        try {
            if ($Global:Salud -and $Global:Salud.Titulo) {
                $sg = [string]$Global:Salud.Titulo
                $sc = switch ([int]$Global:Salud.MaxPeso) {
                    3 { 'AccentRed' }
                    2 { 'AccentOrange' }
                    1 { 'AccentYellow' }
                    default { 'AccentGreen' }
                }
                (UI 'DashGrade').Text = $sg
                try { (UI 'DashScore').Foreground = Brush $sc } catch { }
                if ($Global:Salud.Hallazgos -and @($Global:Salud.Hallazgos).Count -gt 0) {
                    $h0 = @($Global:Salud.Hallazgos)[0]
                    (UI 'DashFinding').Text = [string]$h0.Texto
                    if ($h0.Puente) { (UI 'DashFindingSub').Text = [string]$h0.Puente }
                }
                (UI 'DashDiagDetail').Text = ('Salud: 5 bloques · {0} comprobaciones · {1}s' -f $Global:Salud.CompCount, $Global:Salud.DuracionSeg)
                (UI 'DashDiagTime').Text = ('Salud v1.0.0.1 | {0}' -f (Get-Date -Format 'HH:mm:ss'))
            }
        } catch { }

    } catch { }
}

function Start-DiagnosticoUI {
    # Si la tarea ya termino pero el flag quedo en true, liberar
    if ($Global:Running) {
        try {
            if ($Global:Proc -and $Global:Proc.HasExited) { $Global:Running = $false }
            elseif (-not $Global:Proc) { $Global:Running = $false }
        } catch { $Global:Running = $false }
    }
    if ($Global:Running) {
        Write-Host '[!] Hay una tarea de herramientas en ejecucion; el analisis espera.' -ForegroundColor Yellow
        try { [System.Windows.MessageBox]::Show('Hay una tarea en ejecucion. Espera a que termine antes de analizar.','DeMente','OK','Information') | Out-Null } catch { }
        return
    }
    if ($Global:DiagRunning) {
        $stuckSec = 0
        try {
            if ($Global:DiagStartedAt) {
                $stuckSec = ((Get-Date) - $Global:DiagStartedAt).TotalSeconds
            }
        } catch { $stuckSec = 999 }
        if ($stuckSec -lt 90) {
            Write-Host "[!] Analisis en curso (${stuckSec}s). Espera o volve a pulsar en 90s." -ForegroundColor Yellow
            return
        }
        Write-Host '[!] Analisis anterior superó 90s: se fuerza reintento.' -ForegroundColor Yellow
        $Global:DiagRunning = $false
    }
    $Global:DiagStartedAt = Get-Date
    $Global:DiagRunning = $true
    Write-Host '[i] Start-DiagnosticoUI: comenzando Get-DiagnosticoCompleto...' -ForegroundColor Cyan
    try {
        try { $BtnDiagNow.IsEnabled = $false } catch { }
        try {
            $DashDiagBar.Value = 8
            $DashDiagDetail.Text = 'Iniciando multiescaneo por areas...'
            $DashDiagTime.Text = 'Analizando...'
            $DashFinding.Text = 'Analizando el equipo...'
            $DashFindingSub.Text = 'Hardware, disco, Windows, servicios, red, rendimiento, inicio, privacidad, seguridad, YARA, limpieza y estabilidad.'
            $DashGrade.Text = 'Analizando...'
            $DashImproveTitle.Text = 'Analizando...'
        } catch { }

        # Importante: NO usar Dispatcher.Invoke desde el hilo UI (deadlock).
        # Solo asignar propiedades; el progreso se ve al final de cada bloque.
        $progress = {
            param($msg, $pct)
            try {
                if ($null -ne $pct) { $script:DashDiagBar.Value = [math]::Min(95, [int]$pct) }
                if ($msg) {
                    $script:DashDiagDetail.Text = [string]$msg
                    $script:DashDiagTime.Text = [string]$msg
                }
            } catch {
                try {
                    $DashDiagBar.Value = [math]::Min(95, [int]$pct)
                    $DashDiagDetail.Text = [string]$msg
                } catch { }
            }
        }

        Write-Host '[i] Llamando Get-DiagnosticoCompleto...' -ForegroundColor Cyan
        $Global:Diagnostico = Get-DiagnosticoCompleto -OnProgress $progress
        try {
            if (Get-Command Get-SaludDeMente -EA 0) {
                $Global:Salud = Get-SaludDeMente
                Write-Host "[i] Salud v1.0.0.1: $($Global:Salud.Titulo)" -ForegroundColor Cyan
            }
        } catch { Write-Host "[!] Salud: $($_.Exception.Message)" -ForegroundColor Yellow }
        Write-Host '[i] Get-DiagnosticoCompleto devolvio control al panel.' -ForegroundColor Cyan

        try { Sync-SelectionWithDiagnosis } catch { }
        try { Update-Stats } catch { }
        try { Update-DashboardDiagnosis } catch { }
        try { Update-DashboardHealthSection } catch { }

        # Cierre FORZADO del panel (si Update-Dashboard fallo o dejo textos viejos)
        try {
            $d = $Global:Diagnostico
            $DashDiagBar.Value = 100
            if ($d) {
                $n = 0
                try { $n = @($d.Comprobaciones).Count } catch { $n = 0 }
                $secs = 0
                try { $secs = $d.DuracionSeg } catch { $secs = 0 }
                $DashDiagDetail.Text = "Listo: $n comprobaciones en ${secs}s. Detalle de limpieza en seccion Limpieza."
                $DashDiagTime.Text = "Multiescaneo completado | $(Get-Date -Format 'HH:mm:ss')"
                if ($DashFinding.Text -match 'Analizando') {
                    $DashFinding.Text = 'Analisis completado'
                }
                if ($DashGrade.Text -match 'Analizando') {
                    $DashGrade.Text = 'VER PANEL'
                }
                if ($DashImproveTitle.Text -match 'Analizando') {
                    $DashImproveTitle.Text = 'Revisa cada seccion o usa ESENCIAL / COMPLETO'
                }
            } else {
                $DashDiagDetail.Text = 'Analisis sin datos. Proba F5 o el boton Analizar de nuevo.'
                $DashFinding.Text = 'Sin datos de analisis'
            }
        } catch {
            try { $DashDiagDetail.Text = 'Analisis finalizado.'; $DashDiagBar.Value = 100 } catch { }
        }
    } catch {
        try {
            $DashDiagBar.Value = 100
            $DashDiagDetail.Text = "Error en analisis: $($_.Exception.Message)"
            $DashFinding.Text = 'Analisis incompleto'
            $DashGrade.Text = 'ERROR'
        } catch { }
    } finally {
        try { $BtnDiagNow.IsEnabled = $true } catch { }
        $Global:DiagRunning = $false
    }
}
$BtnDiagNow.Add_Click({
    Write-Host '[i] Clic en Analizar ahora' -ForegroundColor Cyan
    $Global:DiagRunning = $false   # permitir reintento si quedo trabado
    Start-DiagnosticoUI
})

(UI 'BtnPorqueLenta').Add_Click({ Start-BSRun @($Global:ToolIndex['info-porque-lenta']) $false })

  function Update-DashboardHealthSection {
    try {
      $s = $Global:Salud
      if (-not $s -or -not $SaludGrid) { return }
      $SaludTitulo.Text = 'Salud del sistema'
      $SaludSubtitulo.Text = 'El estado real de tu PC, sin puntajes mágicos.'
      $SaludEstadoGeneral.Text = $s.Titulo
      $saludColor = if ([int]$s.MaxPeso -ge 3) { 'AccentRed' } elseif ([int]$s.MaxPeso -eq 2) { 'AccentOrange' } elseif ([int]$s.MaxPeso -eq 1) { 'AccentYellow' } else { 'AccentGreen' }
      $SaludEstadoGeneral.Foreground = Brush $saludColor
      $first = @($s.Hallazgos) | Select-Object -First 1
      $SaludHallazgoPrincipal.Text = if ($first) { "Principal: $($first.Texto)" } else { 'No se encontraron hallazgos que requieran atención inmediata.' }
      $SaludGrid.Children.Clear(); $SaludGrid.RowDefinitions.Clear()
      $SaludGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='Auto'}))
      foreach ($w in @('ÁREA','ESTADO','DETALLE')) { $t=New-Object System.Windows.Controls.TextBlock -Property @{Text=$w;Foreground=(Brush 'Zinc500');FontSize=10;FontWeight='Bold';Margin=(New-Object System.Windows.Thickness(0,0,0,5))}; [System.Windows.Controls.Grid]::SetColumn($t, @('ÁREA','ESTADO','DETALLE').IndexOf($w)); [System.Windows.Controls.Grid]::SetRow($t,0); $SaludGrid.Children.Add($t)|Out-Null }
      $areas=@(@{N='Windows';T=$s.BloqueWindows;P='Windows'},@{N='Rendimiento';T=$s.BloqueRendimiento;P='Rendimiento'},@{N='Almacenamiento';T=$s.BloqueAlmacenamiento;P='Almacenamiento|Limpieza'},@{N='Seguridad/Priv.';T=$s.BloqueSegPriv;P='Seguridad|Privacidad'},@{N='Inicio y estabilidad';T=$s.BloqueConfig;P='Limpieza|Rendimiento|Reparación|Reparacion'})
      $r=0; foreach ($a in $areas) { $r++; $SaludGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height='Auto'})); $p=0; foreach($h in @($s.Hallazgos)){if($h.Puente -match $a.P){$p=[Math]::Max($p,[int]$h.Peso)}}; $st=switch($p){3 {'X Crítico'}; 2 {'! Atención'}; 1 {'i Revisar'}; default {'OK'}}; $bc=switch($p){3 {'AccentRed'}; 2 {'AccentYellow'}; 1 {'AccentOrange'}; default {'AccentGreen'}}; $d=[string]$a.T; foreach($v in @(@($a.N,'Zinc200',12.5,'SemiBold',0),@($st,$bc,12,'SemiBold',1),@($d,'Zinc400',11.5,'Normal',2))) { $t=New-Object System.Windows.Controls.TextBlock -Property @{Text=$v[0];Foreground=(Brush $v[1]);FontSize=$v[2];FontWeight=$v[3];TextWrapping='Wrap';Margin=(New-Object System.Windows.Thickness(0,4,8,4))};[System.Windows.Controls.Grid]::SetColumn($t,$v[4]);[System.Windows.Controls.Grid]::SetRow($t,$r);$SaludGrid.Children.Add($t)|Out-Null } }
    } catch { Write-Host "[!] No se pudo actualizar Salud: $($_.Exception.Message)" -ForegroundColor Yellow }
  }
  function Update-Health { Update-DashboardDiagnosis; Update-DashboardHealthSection }
  $BtnRepararSalud.Add_Click({
      $tRepair = $Global:ToolIndex['repair-sequence']
      if ($tRepair) { Start-BSRun @($tRepair) $false }
      else { [void](Show-WDMDialog -Title 'DeMente' -Message 'La herramienta de reparación no está disponible.' -Buttons Ok -Tone Warn) }
  })
  $BtnVerInformeSalud.Add_Click({ Start-BSRun @($Global:ToolIndex['info-salud']) $false })

  $QuickPanel.Children.Clear()
try { Update-HeroCards } catch { }
$QuickPanel.Children.Add((New-DashboardActionButton 'Mantenimiento corto' 'Basura tipica, sin tocar el sistema a fondo.' 'AccentCyan' 'dm-auto-rapido' 'E8F1'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Plan DeMente' 'Esencial de limpieza + rendimiento + reparacion.' 'AccentBlue' 'dm-auto-demente' 'E8FB'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'A fondo' 'Perfiles completos (sin acciones de riesgo).' 'AccentPurple' 'dm-auto-completo' 'E945'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'DEFAULT Windows' 'Revierte propuestas DeMente (perf/privacidad).' 'AccentOrange' 'dm-auto-default' 'E777'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Plan + reiniciar' 'Plan DeMente y reinicio al terminar.' 'AccentGreen' 'dm-auto-demente-reboot' 'E777'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Mejora rapida' 'Solo lo prioritario del diagnostico.' 'AccentBlue' 'dm-quick' 'E8FB'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Limpieza profunda' 'Perfil COMPLETO de limpieza.' 'AccentGreen' 'dm-clean-completo' 'E74D'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Limpieza profunda' 'Equivale al Liberador de Windows, integrada.' 'AccentGreen' 'clean-cleanmgr' 'EDA2'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Caches de apps' 'Discord, Spotify, Office, GPU...' 'AccentGreen' 'clean-apps-deep' 'E8B7'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Estado YARA' 'Motor y reglas instaladas.' 'AccentBlue' 'sec-yara-status' 'E72E'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Actualizar YARA' 'Baja motor + reglas.' 'AccentOrange' 'sec-yara-update' 'E895'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Reiniciar' 'Reinicia la PC en 5 s.' 'AccentOrange' 'power-restart' 'E777'))|Out-Null
$QuickPanel.Children.Add((New-DashboardActionButton 'Apagar' 'Apaga la PC en 5 s.' 'AccentRed' 'power-shutdown' 'E7E8'))|Out-Null

# -- PERFILES ------------------------------------------------------------------
(UI 'BtnProfSave').Add_Click({
        $sel = @($Global:Cards | Where-Object { $_.IsChecked } | ForEach-Object { $_.Uid })
        if ($sel.Count -eq 0) {
            [void](Show-WDMDialog -Title 'DeMente' -Message 'Selecciona al menos una herramienta.' -Buttons Ok -Tone Info)
            return
        }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.InitialDirectory = $Global:WDMProf
        $dlg.Filter = "Perfil DeMente (*.json)|*.json"
        $dlg.FileName = "perfil_$(Get-Date -Format 'yyyyMMdd_HHmm').json"
        if ($dlg.ShowDialog()) {
            [pscustomobject]@{ Nombre=[System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName); Creado=(Get-Date).ToString('s'); Equipo=$env:COMPUTERNAME; Version='1.0.0.1'; Ids=$sel } | ConvertTo-Json -Depth 4 | Set-Content $dlg.FileName -Encoding UTF8
            Save-WDMConfig
            [void](Show-WDMDialog -Title 'DeMente' -Message ("Perfil guardado con {0} herramientas." -f $sel.Count) -Buttons Ok -Tone Info)
        }
    })

(UI 'BtnProfLoad').Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.InitialDirectory = $Global:WDMProf
        $dlg.Filter = "Perfil DeMente (*.json)|*.json"
        if ($dlg.ShowDialog()) {
            try {
                $p = Get-Content $dlg.FileName -Raw | ConvertFrom-Json
                foreach ($c in $Global:Cards) { $c.IsChecked = ($p.Ids -contains $c.Uid) }
                Update-Counter
                Save-WDMConfig
                $n = @($Global:Cards | Where-Object IsChecked).Count
                $m = "Perfil cargado: $n de $($p.Ids.Count) herramientas."
                [System.Windows.MessageBox]::Show($m, "DeMente", 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.MessageBox]::Show("No se pudo leer el perfil.", "DeMente", 'OK', 'Error') | Out-Null
            }
        }
    })

# -- VENTANA ------------------------------------------------------------------
(UI 'BtnClose').Add_Click({ $window.Close() })
(UI 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })
(UI 'BtnMax').Add_Click({ if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' } })
(UI 'TitleBar').Add_MouseLeftButtonDown({ if ($_.ClickCount -eq 2) { if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' } } else { $window.DragMove() } })
(UI 'BtnDocs').Add_Click({ [System.Windows.MessageBox]::Show('DeMente v1.0.0.1`n`nPrimero diagnosticamos. Despues vos decidis.`n`nCada herramienta muestra el valor DEFAULT de Windows, la propuesta, el riesgo y, cuando corresponde, la reversion.`n`nLos resultados se registran en Documents\DeMente\registros.','Documentacion de DeMente','OK','Information') | Out-Null })

if (-not $Global:IsAdmin) {
    (UI 'AdminTxt').Text = 'Sin privilegios de administrador'
    (UI 'AdminIcon').Foreground = Brush 'AccentRed'
    (UI 'AdminBadge').Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(20, 239, 68, 68)))
}

$window.Add_PreviewKeyDown({
    if ($_.Key -eq 'F5') {
        Write-Host '[i] F5 (Preview): refrescar analisis' -ForegroundColor Cyan
        $Global:DiagRunning = $false
        try { $BtnDiagNow.IsEnabled = $true } catch { }
        Start-DiagnosticoUI
        try { Update-Stats } catch { }
        $_.Handled = $true
    }
})
$window.Add_KeyDown({
        if ($_.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            if ($Global:CurCat -in @('dash', 'console')) { Show-View 'repair' }
            $SearchInput.Focus() | Out-Null; $_.Handled = $true
        }
        elseif ($_.Key -eq 'Escape') { if ($SearchInput.Text) { $SearchInput.Text = ''; $_.Handled = $true } }
        elseif ($_.Key -eq 'F5') {
            Write-Host '[i] F5: refrescar analisis' -ForegroundColor Cyan
            $Global:DiagRunning = $false
            try { $BtnDiagNow.IsEnabled = $true } catch { }
            Start-DiagnosticoUI
            try { Update-Stats } catch { }
            $_.Handled = $true
        }
        elseif ($_.Key -eq 'F1') {
            [System.Windows.MessageBox]::Show(@"
ATAJOS DE TECLADO
  Ctrl + F        Buscar herramientas
  Escape          Limpiar busqueda
  Ctrl + Enter    Ejecutar seleccion
  F5              Refrescar estado
  F1              Esta ayuda

MODO CONSOLA
  DeMente.ps1 -ListTools
  DeMente.ps1 -RunTool clean-temp,perf-priority
  DeMente.ps1 -SelfTest

TOTAL: $($Global:Catalog.Count) herramientas
"@, "Ayuda de DeMente", 'OK', 'Information') | Out-Null
            $_.Handled = $true
        }
        elseif ($_.Key -eq 'Return' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
            if ($BtnExecute.IsEnabled) { $BtnExecute.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
            $_.Handled = $true
        }
    })

$Global:TimerStats = New-Object System.Windows.Threading.DispatcherTimer
$Global:TimerStats.Interval = [TimeSpan]::FromSeconds(2)
$Global:TimerStats.Add_Tick({ if ($ViewDash.Visibility -eq 'Visible') { Update-Stats } })
$Global:TimerStats.Start()

$window.Add_Closing({
        try { $Global:TimerRun.Stop(); $Global:TimerStats.Stop() } catch { }
        if ($Global:Running -and $Global:Proc -and -not $Global:Proc.HasExited) {
            try { Stop-WDMProcessTree -ProcessId $Global:Proc.Id } catch { }
        }
        Get-ChildItem $Global:WDMTmp -Filter "task_*.ps1" -EA 0 | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force -EA 0
        Get-ChildItem $Global:WDMTmp -Filter "out_*.log*" -EA 0 | Remove-Item -Force -EA 0
    })

# -- INICIO --------------------------------------------------------------------
# Las casillas arrancan siempre vacias. El diagnostico determina el estado real del
# equipo, pero NO marca herramientas automaticamente. La seleccion es siempre una
# decision explicita del usuario para esta ejecucion.
$Global:CargandoConfig = $true
try { foreach ($c in $Global:Cards) { $c.IsChecked = $false } }
finally { $Global:CargandoConfig = $false }
$Global:ConfigCargada = $true
Update-Counter
Update-Stats
Show-View 'dash' 

Write-Con "DeMente - v1.0.0.1 cargado." 'head'
Write-Con "Ayudarnos es la unica opcion." 'dim'
Write-Con "$($Global:Catalog.Count) herramientas disponibles." 'dim'

$Global:DiagRunning = $false
Write-Host '[i] Ventana lista. El analisis automatico arranca en 1.5s (o usa el boton Analizar / F5).' -ForegroundColor Cyan
$Global:DiagTimer = New-Object System.Windows.Threading.DispatcherTimer
$Global:DiagTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
$Global:DiagTimer.Add_Tick({
    try { $Global:DiagTimer.Stop() } catch { }
    Write-Host '[i] Arrancando multiescaneo del panel...' -ForegroundColor Cyan
    try {
        Start-DiagnosticoUI
    } catch {
        Write-Host "[X] Fallo Start-DiagnosticoUI: $($_.Exception.Message)" -ForegroundColor Red
        try {
            $DashDiagDetail.Text = "Error: $($_.Exception.Message)"
            $DashDiagBar.Value = 100
            $Global:DiagRunning = $false
            $BtnDiagNow.IsEnabled = $true
        } catch { }
    }
})
$window.Add_ContentRendered({
    try { $Global:DiagTimer.Start() } catch {
        Write-Host '[i] Timer no disponible, analisis directo...' -ForegroundColor Yellow
        Start-DiagnosticoUI
    }
})
try {
    $null = $window.ShowDialog()
} catch {
    Write-Host "[X] Error al mostrar la ventana: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Detalle: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
    Write-Host "Si ves 'Parameter count mismatch', cierra otras instancias de DeMente y vuelve a ejecutar." -ForegroundColor Yellow
    Read-Host "ENTER para salir"
}
