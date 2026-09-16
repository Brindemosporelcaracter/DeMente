<img width="1280" height="720" alt="cuToj" src="https://github.com/user-attachments/assets/1266a35e-966c-4ad4-ad7d-28628341c09e" />

<img width="1280" height="720" alt="5ZG9z" src="https://github.com/user-attachments/assets/50295dee-f0db-4535-ad2a-dc62f5184668" />

<img width="1280" height="720" alt="FLQu2" src="https://github.com/user-attachments/assets/361cd995-a9d9-4bda-b891-a946fd0254dc" />

<img width="1280" height="800" alt="image" src="https://github.com/user-attachments/assets/86c16b4e-7994-4bd6-9d5c-5ac32bd51dba" />

<img width="1280" height="800" alt="image (1)" src="https://github.com/user-attachments/assets/9c01e92e-4f02-4f5f-9c40-2f1ea790317d" />





# DeMente v1.0.0 FINAL

**Ayudarnos es la unica opcion.**

---

## Filosofia del proyecto

DeMente nacio de una idea simple y poco frecuente en el mundo de los "optimizadores":

**Windows ya tiene valores de fabrica. Nosotros no los ocultamos.**

La mayoria de las herramientas de limpieza y tuning hacen una de dos cosas: o cambian el sistema a ciegas, o inventan un puntaje magico (78/100, "salud critica") para vender miedo. DeMente hace lo contrario.

### Tres columnas, siempre visibles

```
ACTUAL  |  DEFAULT WINDOWS  |  PROPUESTA DEMENTE
```

- **ACTUAL** — lo que el equipo tiene ahora.
- **DEFAULT WINDOWS** — el valor de fabrica documentado o razonable de Microsoft.
- **PROPUESTA DEMENTE** — lo que sugerimos, con riesgo y, cuando existe, **reversion**.

Asi el usuario (alumno, tecnico, lab) entiende *que* va a cambiar y *por que*, no solo un boton verde que "arregla todo".

### Primero diagnosticar, despues decidir

Al abrir, DeMente corre un **multiescaneo** (hardware, disco, Windows, servicios, red, rendimiento, inicio, privacidad, Defender, YARA, limpieza, estabilidad). El panel principal no inventa un score: muestra **hallazgos reales** o **cero hallazgos**. Si hay algo a revisar, **dice cual es** (por ejemplo memoria, espacio en disco, firmas de Defender).

### Portable con potencia de taller

El mismo `.ps1` o un EXE generado con ps2exe corre en un pendrive o carpeta, pide administrador, deja **logs** y **backups de registro** en el perfil del usuario, y expone **mas de 120 herramientas** organizadas en secciones. No es un "limpiador de un click": es un **laboratorio controlado** de mantenimiento Windows.

### Perfiles honestos

En cada seccion:

| Perfil | Intencion |
|--------|-----------|
| **ESENCIAL** | Seguro, impacto claro. Primera vez o aula. |
| **COMPLETO** | Todo lo razonable de esa seccion. Revisar antes. |
| **DEFAULT WINDOWS** | Volver al valor de fabrica **solo** donde hay reversion. |

La limpieza no "se revierte": borrar temporales no tiene un DEFAULT que restaurar. Por eso en Limpieza el perfil DEFAULT aclara eso y no marca borrados a ciegas.

Esa es la filosofia. Abajo, el detalle de **toda** la potencialidad del portable, seccion por seccion.

---

## Requisitos y arranque rapido

- Windows 10/11, **Administrador**, PowerShell con **-STA** (WPF).
- Script: `DeMente_v1.0.0.ps1`
- Icono: `DeMente.ico` (DM + lentes)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\DeMente_v1.0.0.ps1
```

EXE portable (ps2exe):

```powershell
Invoke-ps2exe -inputFile .\DeMente_v1.0.0.ps1 -outputFile .\DeMente.exe `
  -iconFile .\DeMente.ico -noConsole -sta -requireAdmin -title DeMente -version 1.0.0.0
```

Logs: `Documents\DeMente\registros\`  
Backups de registro: `Documents\DeMente\backups\registry\`

---

## Dashboard (panel principal)

El punto de entrada despues del analisis automatico.

- **Numero grande de hallazgos** — no es un puntaje estetico; es cantidad de problemas prioritarios (0 = TODO OK).
- **Grade legible** — TODO OK / PARA REVISAR (con el **nombre** del hallazgo) / REQUIERE ATENCION.
- **Texto de hallazgo** — que optimizar, si hace falta reparar, y el detalle concreto.
- **Tarjetas hero**
  - **Limpieza** — estimacion rapida / profunda / cleanmgr.
  - **Seguridad** — Defender + estado YARA.
  - **Rendimiento** — cuantas optimizaciones DeMente estan activas vs cuantas siguen en DEFAULT.
  - **Multiescaneo** — duracion, cantidad de comprobaciones, repetir con F5.
- **Stats en vivo** — CPU, RAM, disco, uptime.
- **Centro de accion** — atajos a analizar, limpieza esencial/completa, seguridad.

Ideal para mostrar al usuario *antes* de tocar nada: "tu PC esta bien" o "revisa esto".

---

## Limpieza

**Subtitulo en app:** temporales, caches, apps y registro inteligente.

El fuerte del portable para liberar espacio y basura acumulada. Cada tarjeta puede mostrar estimacion recuperable cuando el analisis la calcula.

### Sistema y Windows

| Herramienta | Que hace |
|-------------|----------|
| Archivos temporales | TEMP de usuario y Windows; reporta elementos y MB |
| Vaciar papelera | Vaciado permanente de la Papelera |
| Prefetch | Limpia pistas de arranque (en SSD el beneficio suele ser bajo) |
| Cache de Windows Update | Cache de descargas de Update |
| Cache BITS | Trabajos terminados/error + carpeta Downloader |
| Delivery Optimization | Cache P2P de actualizaciones |
| Liberador de espacio (cleanmgr) | Invoca el limpiador clasico de Windows |
| Windows.old / componentes | DISM StartComponentCleanup + intento de quitar Windows.old (**cuidado**) |
| Informes de errores (WER) | Reportes tecnicos en cola o ya enviados |
| Volcados de error | Crash dumps |
| Registros del sistema / CBS / DxDiag | Logs de instalacion, componentes y diagnostico grafico |
| Thumbs.db / Cache miniaturas | Miniaturas residuales |
| Cache de fuentes / iconos | FontCache e iconcache (puede parpadear el escritorio) |
| Documentos recientes | Accesos recientes del shell |
| Portapapeles | Limpia contenido del clipboard |
| Cache DNS | Flush DNS |
| Memoria en espera | Libera standby list (RAM, no disco) |

### Navegadores y apps

| Herramienta | Que hace |
|-------------|----------|
| Cache de navegadores | Chrome / Edge / Firefox (solo cache; no contraseñas ni favoritos) |
| Cache WebView2 / Edge extra | Caches EBWebView de apps embebidas |
| Cache de Microsoft Store | LocalCache de la Store |
| Cache de Teams / Discord / Spotify / VS Code / Office | Caches tipicas de esas apps |
| Cache de sombreadores | D3D / NVIDIA / AMD shader cache |
| Caches de apps (base ampliada) | Rutas seguras ampliadas (GPU, Adobe, OneDrive logs, etc.) |

### Registro inteligente (dentro de Limpieza)

| Herramienta | Que hace |
|-------------|----------|
| Registro: auditar | Solo lectura: Run rotos, App Paths muertos, desinstaladores huerfanos, SharedDLLs |
| Registro: limpieza segura | Backup `.reg` automatico + borra solo hallazgos de bajo riesgo |
| Registro: restaurar backup | Importa el `.reg` mas reciente de backups |

**Perfiles:** ESENCIAL (temp, papelera, navegadores, caches de apps) · COMPLETO (casi todo lo de la lista, incluido registro seguro y cleanmgr) · DEFAULT (no marca borrados).

---

## Rendimiento

**Subtitulo:** optimizaciones del nucleo y la red.

Aqui se nota la filosofia DEFAULT vs DeMente: muchos items tienen **reversion** al valor de fabrica.

### Procesador, memoria y disco

| Herramienta | Idea |
|-------------|------|
| Prioridad del procesador | Win32PrioritySeparation segun nucleos |
| Mantener el nucleo en RAM | DisablePagingExecutive con RAM suficiente |
| LargeSystemCache | Solo escenario HDD + mucha RAM |
| Superfetch (SysMain) / SysMain segun disco | Ajuste consciente SSD vs HDD |
| Ultimo acceso de NTFS | Reduce escrituras de timestamp |
| Hibernacion / Inicio rapido | Control de hiberfil e hybrid boot |
| Storage Sense | Politica de limpieza automatica de Windows |

### Interfaz y escritorio

| Herramienta | Idea |
|-------------|------|
| Menus mas rapidos | MenuShowDelay bajo |
| Efectos visuales | Preferir rendimiento |
| Menu contextual clasico | Estilo clasico en Win11 |
| Explorador en proceso separado | Estabilidad del shell |
| Teclas pegajosas / filtro | Desactivar atajos molestos |
| Aceleracion del mouse | Curva de puntero |

### Red y juegos

| Herramienta | Idea |
|-------------|------|
| Algoritmo de Nagle | Latencia en algunos juegos/apps |
| Limitacion de red | Network throttling |
| IPv6 | Deshabilitar si el entorno lo requiere |
| MMCSS Games | Prioridad GPU/CPU en juegos |
| Optimizaciones de pantalla completa | Fullscreen optimizations |
| Servicios Xbox en segundo plano | Reducir ruido de servicios Xbox |

### Inicio

| Herramienta | Idea |
|-------------|------|
| Auditar programas al inicio | Lista Run HKLM/HKCU |
| Optimizar inicio (seguro) | Ajuste conservador |
| Retraso de apps de inicio | Startup delay |

**Perfiles:** ESENCIAL (cambios seguros de impacto claro) · COMPLETO (paquete amplio de tweaks) · DEFAULT WINDOWS (marca lo reversible para restaurar fabrica).

---

## Seguridad

**Subtitulo:** Defender, YARA, cuentas y analisis forense.

### Microsoft Defender

| Herramienta | Que hace |
|-------------|----------|
| Estado de Defender | Tiempo real, edad de firmas, ultimo scan |
| Escaneo Defender | Dispara analisis (segun opciones de la herramienta) |

### YARA (motor de reglas de malware)

| Herramienta | Que hace |
|-------------|----------|
| Estado del motor YARA | Instalado / reglas / version |
| Actualizar motor YARA | Descarga/actualiza el binario |
| Actualizar reglas YARA | Set de reglas orientado a precision |
| Escaneo YARA rapido | Pasada acotada |
| Escaneo YARA personalizado / completo | Analisis mas amplio |

### Cuentas y forense ligero

| Herramienta | Que hace |
|-------------|----------|
| Auditar cuentas | Revision de cuentas locales relevantes |
| Forense: Amcache | Evidencia de ejecucion de programas |
| Forense: ShellBags | Rastros de carpetas visitadas |
| Forense: USBSTOR | Historial de dispositivos USB |
| Forense: redes Wi-Fi guardadas | Perfiles Wi-Fi conocidos |

Pensado para tecnico o docente: no solo "antivirus on/off", sino **estado + reglas + rastros**.

---

## Privacidad

**Subtitulo:** Windows 10/11 — estado y mejora.

Cada item se puede contrastar con DEFAULT. Varios son reversibles.

| Herramienta | Ambito |
|-------------|--------|
| Telemetria | Nivel de datos enviados a Microsoft |
| ID de Publicidad / Publicidad + tracking apps | Identificador y sugerencias |
| Ubicacion / Camara / Microfono | Capacidades sensibles |
| Historial de actividad | Timeline / activity feed |
| Bing en busqueda / Destacados de busqueda | Busqueda y highlights |
| GameDVR | Captura y DVR de juegos |
| Portapapeles en nube | Sincronizacion de clipboard |
| CEIP / datos de uso | Programa de mejora de experiencia |
| Tips y sugerencias | Sugerencias del sistema |
| Apps en segundo plano | Apps UWP en background |
| Experiencias personalizadas | Tailored experiences |
| Personalizacion de entrada | Texto/tinta hacia Microsoft |
| Frecuencia de feedback | SIUF / feedback |
| Copilot / IA del shell | Experiencias de IA del shell (segun edicion) |

**DEFAULT WINDOWS** en esta seccion es especialmente util: permite endurecer y despues volver atras en bloque.

---

## Reparacion

**Subtitulo:** SFC, DISM, CHKDSK, WMI y red.

| Herramienta | Que hace |
|-------------|----------|
| SFC /scannow | Integridad de archivos de sistema |
| DISM /RestoreHealth | Imagen del sistema / component store |
| CHKDSK | Sistema de archivos del volumen |
| Reconstruir WMI | Repositorio WMI danado |
| Reset de red | Winsock/stack (segun implementacion) |
| Reparar segun diagnostico | Secuencia guiada por hallazgos previos |

Operaciones pesadas: la consola muestra progreso; no conviene interrumpir a mitad de SFC/DISM.

---

## Herramientas

**Subtitulo:** Autoruns, Sysinternals, NVClean y utilidades de terceros.

No sustituyen a DeMente: las **lanzan o preparan** en el entorno del tecnico.

| Herramienta | Uso tipico |
|-------------|------------|
| Autoruns | Todo lo que arranca con Windows |
| Process Explorer / Process Monitor | Procesos y actividad en tiempo real |
| TCPView | Conexiones de red |
| BGInfo | Info del sistema en el fondo de escritorio |
| Suite Sysinternals (info) | Referencia / acceso al set |
| CrystalDiskInfo | Salud SMART del disco |
| HWiNFO | Sensores y hardware detallado |
| Everything | Busqueda instantanea de archivos |
| DDU | Desinstalacion limpia de drivers GPU |
| NVCleanstall | Instalacion controlada de drivers NVIDIA |
| SDelete | Borrado seguro |
| Abrir carpeta de herramientas | Acceso rapido a binarios descargados |

Varias descargan o esperan el binario en una carpeta de herramientas del usuario; la propia app indica el camino si falta el ejecutable.

---

## Informacion

**Subtitulo:** hardware, sistema y revision completa.

| Herramienta | Que hace |
|-------------|----------|
| Informacion del sistema | Resumen de equipo, SO, recursos |
| Salud de los discos | Modelo, tipo, salud Windows |
| Programas al inicio | Entradas de arranque |
| Eventos del sistema | Eventos relevantes recientes |
| ¿Por que esta lenta mi PC? | Narrativa orientada a causas frecuentes |
| Revision completa del sistema | Mapa unico: hardware, espacio, inicio, registro, uptime — honestidad antes que puntaje |

Complementa el Dashboard: informes legibles para dejar constancia o explicar al usuario.

---

## Consola de ejecucion

No es un detalle menor: es el **registro en vivo** de lo que el portable hace.

- Cola de tareas con progreso `n/total`.
- Cada herramienta corre en un **proceso PowerShell aislado** (preludio comun: OK/INFO/WARN, deteccion de CPU/RAM/SSD).
- Previsualizacion antes de aplicar.
- Confirmacion extra en acciones de riesgo alto.
- Sesion guardada en `Documents\DeMente\registros\sesion_*.log`.
- Codigo de salida vacio en portable/EXE se trata como **exito** si el proceso termino sin error numerico (evita el falso "finalizo con codigo .").

---

## Perfiles, riesgo y reversion (resumen operativo)

1. Elegi seccion → perfil **ESENCIAL** o **COMPLETO**.
2. Revisa tarjetas (DEFAULT vs DeMente).
3. **Aplicar** → lee la previsualizacion → confirma.
4. Mira la **Consola**; guarda el log si es un trabajo para un cliente o alumno.
5. Si algo de rendimiento/privacidad no convence: perfil **DEFAULT WINDOWS** + solo items reversibles → aplicar restauracion.

Riesgos marcados en catalogo (`care` / `danger`): Windows.old, vaciado de papelera, limpiezas profundas, reparaciones de disco. Ante la duda, punto de restauracion de Windows antes.


## Cierre

DeMente no promete "dejar el PC como nuevo" de un click. Promete algo mas util en el aula y en el taller:

**transparencia (DEFAULT vs propuesta), diagnostico real, limpieza amplia, optimizacion reversible, seguridad con Defender y YARA, privacidad explicada, reparacion clasica, y herramientas de tecnico — en un portable.**

**DeMente v1.0.0 FINAL**  
*Ayudarnos es la unica opcion.*

## Autor

Proyecto desarrollado por Vic.
