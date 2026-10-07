<img width="1280" height="720" alt="cuToj" src="https://github.com/user-attachments/assets/1266a35e-966c-4ad4-ad7d-28628341c09e" />

<img width="1280" height="720" alt="5ZG9z" src="https://github.com/user-attachments/assets/50295dee-f0db-4535-ad2a-dc62f5184668" />

<img width="1280" height="720" alt="FLQu2" src="https://github.com/user-attachments/assets/361cd995-a9d9-4bda-b891-a946fd0254dc" />

<img width="1280" height="800" alt="image" src="https://github.com/user-attachments/assets/86c16b4e-7994-4bd6-9d5c-5ac32bd51dba" />

<img width="1280" height="800" alt="image (1)" src="https://github.com/user-attachments/assets/9c01e92e-4f02-4f5f-9c40-2f1ea790317d" />

# DeMente

**Diagnóstico, limpieza y optimización para Windows. Sin humo, sin promesas vacías, sin sorpresas.**

Versión actual: **v1.0.0.1**

---

## El problema con los "optimizadores"

Si alguna vez instalaste un programa que prometía "acelerar tu PC", probablemente viviste esto:

- Te mostró un **puntaje inventado** (95/100, "Salud: Excelente") que no significa nada.
- Detectó **"1.847 errores de registro"** que nunca te mostró, y que en realidad eran entradas normales de Windows.
- Te dijo **"¡Borré 5 GB!"** sin aclarar que la mitad de esa "basura" **se regenera sola en pocos días**.
- Aplicó **cambios agresivos** sin backup, sin explicación, sin forma de volver atrás.
- Escondió las funciones útiles detrás de una **versión Pro** que hay que pagar.
- Te dejó la PC **igual o peor**, y con la sensación de que el problema sos vos.

DeMente existe porque hay otra forma de hacer esto.

---

## Novedades de esta versión

Si ya conocías DeMente, esto es lo que cambió. Si es tu primera vez, esto es lo que te estás perdiendo.

### Gestión completa de apps de inicio

**Antes:** DeMente te mostraba una lista de programas de inicio. Solo lectura.

**Ahora:** DeMente detecta **todo** lo que arranca con Windows — entradas de registro, accesos directos, tareas programadas, entradas WMI que otros no ven, y servicios Automatic de terceros. Cada item tiene un **semáforo visual** (verde / amarillo / rojo) con explicación humana: qué es, qué hace Windows con él, qué opina DeMente, qué pasa si lo apagás.

Y podés **deshabilitar con un clic**, de forma reversible. DeMente guarda el estado original para que puedas reactivarlo cuando quieras. **No borra, deshabilita.**

### Desinstalador de programas integrado

**Antes:** no existía.

**Ahora:** DeMente te da una lista real de lo que tenés instalado (programas de escritorio y apps de Microsoft Store, excluyendo componentes de Windows). Podés desinstalar con el método propio de Windows y DeMente limpia automáticamente los residuos seguros: accesos directos huérfanos, entradas de inicio rotas, caché residual en AppData. Lo que queda en Archivos de programa se reporta pero **no se borra solo** (puede contener datos tuyos).

### Motor de Salud del sistema

**Antes:** el diagnóstico te daba un objeto técnico con decenas de propiedades crudas.

**Ahora:** DeMente traduce eso a un **informe humano en 5 bloques**: Windows, Rendimiento, Almacenamiento, Seguridad y Privacidad, Inicio y Estabilidad. Cada bloque tiene un título honesto, un estado visual, y hallazgos priorizados con un puente directo a la sección donde se resuelve. Sin puntaje inventado.

### Limpieza profunda integrada

**Antes:** DeMente lanzaba el Liberador de espacio de Windows en una ventana separada. La GUI perdía control.

**Ahora:** la limpieza profunda corre **dentro de DeMente**. 8 fases: temporales, Windows Update, Delivery Optimization, informes de error, volcados, miniaturas, historial de Defender, papelera, y DISM StartComponentCleanup. Al final te muestra **cuánto espacio libre ganó el disco**, no cuánto "se liberó" teórico.

### Un botón por navegador detectado

**Antes:** un solo botón que limpiaba todos los navegadores de golpe.

**Ahora:** DeMente detecta qué navegadores tenés realmente instalados (Chrome, Edge, Brave, Firefox, Opera, Vivaldi, Arc, **Tor Browser**) y muestra **un botón por cada uno**, con su caché estimada. Cada limpieza cierra solo ese navegador, no todos.

**Tor Browser** merece mención aparte: es el navegador más difícil de detectar. Es portable, vive donde el usuario lo descomprimió, no se registra como los demás, y su perfil está anidado en subcarpetas. DeMente usa **6 estrategias en cascada** para encontrarlo. Si ninguna funciona, te ofrece un botón **"Tor Browser: elegir carpeta"**: una vez, y queda guardada para siempre.

### Gestión de respaldos propios

**Antes:** DeMente acumulaba backups `.reg` y logs de sesión sin control.

**Ahora:** podés borrar los backups de más de 7 días, o todos. Y los logs de sesión, por antigüedad o todos. Para que la carpeta `Documents\DeMente` no crezca sin control.

### Reparación de red en dos niveles

**Antes:** un único reset de red agresivo (`netsh int ip reset` + `winsock reset`) que podía borrar IP fija, gateway y DNS manuales.

**Ahora:** dos herramientas separadas con riesgos claramente marcados:

- **Reparar DNS (seguro)**: solo limpia la caché DNS y reinicia el servicio. **No toca el adaptador.**
- **Reset agresivo de red**: la opción vieja, marcada como `PELIGRO`. Advierte claramente qué puede pasar.

### Modos automáticos de un clic

**Antes:** no existían.

**Ahora:** 5 planes para el 90% de los usuarios que solo quieren que su PC ande mejor sin pensar en cada ajuste:

| Plan | Qué hace |
|:---|:---|
| **Mantenimiento corto** | Limpieza rápida + cachés de navegadores + 2 tweaks seguros. |
| **Plan DeMente** | Perfil esencial de Limpieza, Rendimiento y Reparación. Sin acciones de riesgo. |
| **A fondo** | Perfil completo. Excluye acciones marcadas como `danger`. |
| **Volver a Windows** | Revierte las propuestas de DeMente en Rendimiento y Privacidad. |
| **Plan + reiniciar** | Ejecuta el Plan DeMente y reinicia la PC en 15 segundos al terminar. |

Antes de ejecutar, DeMente muestra **qué va a hacer** y te pide confirmación.

### YARA completo y gratis

**Antes:** DeMente lo integraba, pero con menos contexto y menos validaciones.

**Ahora:** DeMente integra **YARA**, el motor de reglas de detección más usado en el análisis real de malware. **No es un invento nuestro**: es la misma herramienta que usan analistas de seguridad y equipos de respuesta a incidentes.

- Descarga el motor oficial desde VirusTotal.
- Descarga reglas públicas de YARA Forge (set "Core": curado, baja tasa de falsos positivos).
- **Valida que el paquete descargado no traiga ejecutables inesperados.** Si encuentra un `.exe`, `.dll`, `.bat`, `.ps1` o similar dentro de un paquete de reglas, aborta la instalación.
- **Maneja proxies corporativos**: si el firewall de tu empresa bloquea la descarga del binario (pero permite consultar la API de GitHub), DeMente lo detecta y te explica cómo instalarlo manualmente.
- Escaneo rápido (Descargas + TEMP) y personalizado (carpeta o pendrive que elijas).

**Sin instalación permanente. Sin suscripción. Sin candado. Sin versión Pro.**

### Transparencia del sistema

**Antes:** DeMente ofrecía "borrar rastros" (Amcache, USBSTOR, ShellBags, Wi-Fi).

**Ahora:** DeMente **no borra rastros**. Te muestra qué guarda Windows sobre vos, sin eliminar nada. Esta sección es solo lectura.

La razón: borrar esos artefactos **no mejora tu privacidad real** (hay rastros en muchos otros lugares), **rompe cosas** (Windows deja de recordar tus redes Wi-Fi, por ejemplo), y **puede afectar peritajes** que se necesiten después. DeMente no participa de esa práctica. Si querés gestionar retención de datos real, la vía correcta es la **política de auditoría de Windows**, no borrar el pasado a mano.

---

## Filosofía de DeMente

### Dice cuánto liberó, y cuánto se va a regenerar

Los otros: "¡Liberé 4.2 GB de basura!". Lo que no te dicen es que **3 GB de eso era caché de navegador** que se va a volver a llenar en tres días de uso normal.

DeMente: te dice **cuánto se liberó**, **cuánto se va a regenerar**, y **en cuánto tiempo**.

**Ejemplo real:**
```
Caché: Google Chrome
1.247 archivos, 812 MB liberados.
Perfiles, contraseñas, favoritos, cookies e historial intactos.

⚠ Esta caché se regenera en pocos días de uso normal.
   El espacio "ganado" no es permanente.
```

Y cuando es ahorro real, también lo dice:

```
Papelera vaciada: 147 elementos (3.2 GB). Método: cmdlet Windows.

✓ Este espacio es ahorro real: no se regenera.
```

### Muestra el valor real, no un puntaje inventado

Los otros: "Tu PC está en 78/100."

DeMente: te muestra **el valor que tiene Windows por defecto**, **el valor que propone cambiar**, y **el valor que tenés ahora mismo**. Si no hay nada que mejorar, te lo dice.

### Explica antes de actuar

Los otros: aplican 47 "optimizaciones" en un clic y te muestran una barra verde.

DeMente: te dice **qué va a hacer, por qué, y qué efecto tiene**. Antes de ejecutar cualquier cosa, ves una **previsualización**.

### Revertí todo, siempre

Los otros: "optimizan" y no hay vuelta atrás.

DeMente: **cada cambio tiene reversión**. Cada backup queda guardado. Cada tweak tiene un "volver al valor de Windows" a un clic.

### Separa el riesgo, no lo esconde

Los otros: mezclan limpieza de caché con reseteo de red agresivo en el mismo botón.

DeMente: cada herramienta tiene un **nivel de riesgo visible** (verde / amarillo / rojo). El reset DNS seguro está separado del reset agresivo de pila de red.

### No hay "versión Pro"

DeMente: **todo está disponible**. Sin suscripción, sin licencia, sin activación.

### Explica, no asume

Los otros: "deshabilitá esto para mejorar el rendimiento" sin decirte qué es.

DeMente: te dice **qué es cada cosa en castellano**. Si no sabe qué es un servicio, **no lo toca**.

---

## Qué podés hacer con DeMente

### Panel

El centro de comando. Al abrir DeMente arranca un escaneo automático que devuelve un **informe de salud en 5 bloques**:

- **Windows**: versión, servicios críticos, reparaciones pendientes.
- **Rendimiento**: uso de memoria, paginación, tweaks aplicados.
- **Almacenamiento**: tipo de disco, espacio libre, salud SMART.
- **Seguridad y privacidad**: Defender, firewall, ajustes pendientes.
- **Inicio y estabilidad**: programas de inicio, residuos, apagados inesperados.

No hay puntaje. Hay un **título honesto** y una **lista de hallazgos priorizados**.

Además: estado en vivo (CPU, RAM, disco, uptime), centro de acción con tarjetas grandes, 5 modos automáticos, mejoras sugeridas y atajos.

---

### Limpieza

Dos sub-vistas: **Limpieza general** y **Desinstalar programas**.

#### Limpieza general

**El problema.** Los limpiadores clásicos te dicen "borré 4 GB" sin aclarar que la mitad se regenera en pocos días. O peor: borran cosas que Windows necesita (caché de Update, logs de CBS, archivos de instalación pendientes) y rompen algo.

**Cómo lo hace DeMente.** DeMente te dice **cuánto se liberó** y **cuánto se va a regenerar**. Antes de borrar mide. Borra solo lo que se puede borrar. Después vuelve a medir y te dice **cuánto se liberó de verdad**. Y aclara explícitamente **qué NO toca**: Windows Update, CBS, WER.

**Cada tipo de limpieza dice su verdad:**

**Temporales** (se regeneran rápido):
```
Temporales (solo TEMP): 1.247 elementos tocados, 892 MB liberados (aprox.)
⚠ Esta carpeta se vuelve a llenar en pocos días de uso normal.
```

**Papelera** (no se regenera):
```
Papelera vaciada: 147 elementos (3.2 GB). Método: cmdlet Windows.
✓ Este espacio es ahorro real: no se regenera.
```

**Caché de navegadores** (se regenera en días):
```
Caché: Google Chrome
1.247 archivos, 812 MB liberados.
⚠ Esta caché se regenera en pocos días de uso normal.
```

**Miniaturas** (se regeneran al abrir carpetas):
```
Cache de miniaturas/iconos: 84 archivo(s), 234 MB liberados.
⚠ Windows regenera la cache al volver a abrir carpetas con imágenes.
```

**Windows Update** (no se regenera hasta la próxima actualización):
```
WU Download: 23 elementos, 1.8 GB liberados
✓ Estas actualizaciones ya se instalaron. El espacio es ahorro real.
```

**Logs de sistema** (no se regeneran):
```
Registros: 32 archivos eliminados, 187 MB liberados (aprox.)
✓ Los logs borrados no se regeneran.
```

**Limpieza inteligente del registro** — solo hallazgos verificables:
```
AUDITORIA INTELIGENTE DEL REGISTRO
DeMente no inventa miles de errores. Solo lista lo verificable:
  - Inicio (Run/RunOnce) con .exe inexistente
  - App Paths rotos
  - Desinstaladores huerfanos
  - SharedDLLs huerfanas (solo informe)

NO se toca: servicios criticos, SAM, Classes del sistema, drivers.
Hallazgos: 12 total (9 bajo riesgo, 3 medio).
```

**Qué NO hace.** No borra `MUI Cache`, `UserAssist`, asociaciones de archivos, servicios críticos, SAM, Classes ni drivers. No promete acelerar la PC: *"DeMente no promete milagros de registro: promete no mentirte."*

**Limpieza profunda integrada** — equivalente al Liberador de espacio de Windows, pero dentro de DeMente, sin ventanas externas. 8 fases. Al final te muestra **cuánto espacio libre ganó el disco**.

**Respaldos propios** — podés borrar los backups `.reg` de más de 7 días o todos, y los logs de sesión por antigüedad o todos.

#### Desinstalar programas

**El problema.** Los desinstaladores clásicos se limitan a llamar al método de Windows. No detectan residuos.

**Cómo lo hace DeMente.** Lista completa de programas instalados (escritorio + Store). Desinstalación con el método propio de Windows. **Limpieza automática de residuos seguros**: accesos directos huérfanos, entradas de inicio rotas, caché residual en AppData. Lo que queda en Archivos de programa se **reporta pero no se borra solo**.

**Ejemplo:**
```
DESINSTALAR: Adobe Acrobat Reader DC
Residuos de 'Adobe Acrobat Reader DC':
- 2 accesos directos huerfanos borrados
- 1 entrada de inicio rota borrada
- 45 MB de cache/config liberados

Ademas queda esto en Archivos de programa (no se borra solo):
  C:\Program Files\Adobe\Acrobat Reader DC
```

---

### Rendimiento

Dos sub-vistas: **Optimización general** y **Apps de inicio**.

#### Optimización general

**El problema.** Los "optimizadores de rendimiento" venden humo. "Limpiador de RAM" que empeora el rendimiento. "Boost de red" que rompe la conexión. "100 tweaks en un clic" que se pisan entre sí y no se pueden revertir.

**Cómo lo hace DeMente.**

- **Cada tweak tiene explicación humana.**
- **Cada tweak tiene reversión a un clic.**
- **Cada tweak tiene un nivel de riesgo visible** (verde / amarillo / rojo).
- **Los tweaks contextuales no se aplican por defecto** (IPv6, Nagle, throttling están fuera de los perfiles automáticos).
- **DeMente prefiere 25 tweaks honestos que 100 tweaks mentirosos.**

**Ejemplos concretos:**

```
Mantener el núcleo en RAM
Windows a veces manda partes del núcleo del sistema al disco para 
ahorrar RAM, aunque sobre memoria. Con 8 GB o más, DeMente lo mantiene 
todo en RAM: el sistema responde un poco más rápido y no hay downside 
real con esa cantidad de memoria.
```

```
Explorador en su propio proceso
Cuando el Explorador de archivos se cuelga abriendo una carpeta pesada, 
se arrastra todo el escritorio con él. Este ajuste lo aísla: si se 
cuelga, solo se cuelga esa ventana.
```

**Ejemplo de un tweak que DeMente NO aplica y explica por qué:**
```
Resolución del temporizador
Windows administra este valor dinámicamente. DeMente no fuerza un 
valor permanente. Evita una falsa optimización del temporizador.
```

**Y el caso del "limpiador de RAM":**

DeMente tiene la herramienta `clean-standby`, pero la descripción dice la verdad:
```
Windows guarda en RAM copias de archivos que usaste hace poco, 'por si 
los volvés a abrir' (memoria en espera). Esa RAM se libera sola apenas 
un programa la necesita de verdad, así que no es 'memoria ocupada' en 
el sentido de que te falte: liberarla a mano no mejora el rendimiento 
salvo casos puntuales donde Windows tarda en soltarla.
```

Traducción: otros te venden "¡Liberé 3.2 GB de RAM!" como si eso acelerara tu PC. DeMente te dice que en realidad no sirve para lo que promete.

#### Apps de inicio

**El problema.** Los administradores de inicio clásicos **borran** la entrada cuando querés deshabilitarla. Sin backup. Sin forma de recuperarla.

**Cómo lo hace DeMente.**

- **No borra, deshabilita.** El estado original se guarda con prefijo `DeMente_OFF_` en el registro. Reactivable con un clic.
- **Semáforo visual** (verde / amarillo / rojo) con explicación humana.
- **Detecta lo que otros no ven**: entradas WMI, servicios Automatic de terceros, tareas programadas al logon, accesos directos.

**Ejemplos concretos:**

```
Apagar · Microsoft Edge Update
Que es: Actualizador de Microsoft Edge.
Windows: lo deja activo, pero no es critico del sistema.
DeMente: lo podes apagar; no pasa nada grave.
Si lo apagas: Edge no se actualiza hasta que lo abras.
```

```
🔴 Protegido · SecurityHealth
Que es: Icono de Seguridad de Windows (Defender) en la bandeja.
Windows: lo necesita activo.
DeMente: no lo toques.
Si lo apagas: Perdes los avisos de amenazas en la bandeja.
```

**Servicios de Microsoft**: DeMente tiene una lista curada de ~20 servicios del sistema con explicación humana. **Si un servicio de Microsoft no está en la lista, DeMente no sugiere apagarlo a ciegas**: devuelve un consejo conservador.

**Qué NO hace.** No borra entradas. No sugiere apagar servicios que no reconoce. No toca drivers de video, audio, ni servicios críticos.

---

### Seguridad

**El problema.** La mayoría de los "optimizadores" no incluyen herramientas de seguridad reales. Los pocos que sí, las esconden en la versión paga: te muestran un motor de detección "propio" (cerrado, no auditable, con reglas que en realidad detectan muy poco) y te piden una suscripción mensual.

DeMente integra **herramientas de seguridad reales y abiertas**, todas gratis:

#### Estado de Defender

Muestra el estado real de Microsoft Defender: protección en tiempo real, versión y antigüedad de firmas, amenazas en el historial. **Solo lectura.**

#### Escaneo rápido de Defender

Ejecuta un escaneo rápido del antivirus integrado de Windows, con **feedback visible cada 20 segundos**. Actualiza firmas si puede y te reporta amenazas del historial reciente.

```
ESCANEO DE WINDOWS DEFENDER
1/3 Actualizando firmas...
[OK] Firmas actualizadas
2/3 Escaneo rapido en curso...
[i] Escaneo en curso... 45 s. Segui esperando.
[OK] Escaneo rapido completado en 2.1 min.
3/3 Historial reciente de amenazas...
[OK] Sin amenazas en el historial reciente de Defender.
```

#### Auditar cuentas

Lista cuentas locales y miembros del grupo Administradores. Sirve para detectar cuentas que no reconozcas, activas sin contraseña, o con permisos que no necesitan.

```
CUENTAS LOCALES
    Administrador   [deshabilitada]
    Usuario         [activa]
    Invitado        [deshabilitada]
    CuentaInvitado2 [activa, SIN CONTRASENA]  ← alerta

[X] Cuenta CuentaInvitado2 activa y sin contrasena.
```

#### YARA (motor de reglas de malware)

**El problema.** La mayoría de los "optimizadores" no incluyen detección de malware. Los que sí la incluyen, la esconden detrás de la versión paga: te muestran un botón gris con un candado. Otros la ofrecen "gratis" pero con reglas propias cerradas, que vos no podés ver ni auditar, y que en realidad detectan muy poco (mantener reglas de calidad cuesta plata y nadie las actualiza gratis para siempre).

**Cómo lo hace DeMente.** DeMente integra **YARA**, el motor de reglas de detección más usado en el mundo del análisis real de malware. **No es un invento nuestro**: es la misma herramienta que usan analistas de seguridad, equipos de respuesta a incidentes y empresas de ciberseguridad para detectar patrones de malware conocido.

- **Descarga el motor YARA oficial** desde el repositorio de VirusTotal en GitHub.
- **Descarga reglas públicas** de YARA Forge (set "Core": curado, baja tasa de falsos positivos).
- **Valida que el paquete descargado no traiga ejecutables inesperados.** Si al descomprimir encuentra un `.exe`, `.dll`, `.bat`, `.ps1` o similar dentro de un paquete de reglas, aborta la instalación. Un paquete de reglas legítimo nunca debería traer binarios.
- **Escaneo rápido** de Descargas y TEMP.
- **Escaneo personalizado**: elegís la carpeta, pendrive o unidad.
- **Sin instalación permanente.** YARA vive en `Documents\DeMente\security\yara\`. No se instala como servicio, no se registra en el sistema, no queda corriendo en segundo plano.
- **Sin suscripción.** Motor, reglas y escaneos: todo gratis. Sin versión Pro, sin candado, sin límite de uso.
- **Manejo de proxies corporativos.** Si el firewall de tu empresa bloquea la descarga del binario (pero permite consultar la API de GitHub), DeMente lo detecta y te explica cómo instalarlo manualmente.

**Ejemplo de uso:**
```
ESCANEO YARA RAPIDO
Solo Descargas y TEMP (no todo el disco).
YARA: 47 regla(s), 1.284 archivo(s). Puede tardar; avisos cada ~20 s.
YARA: 320/1284 archivos...
YARA: 640/1284 archivos...
[OK] Escaneo YARA completado: 0 coincidencias.
```

Si encuentra algo:
```
[X] Escaneo YARA: 3 coincidencia(s).
[X] Malware_Win_Emotet_Loader -> C:\Users\...\Downloads\factura.pdf.exe
[X] Suspicious_PowerShell_Downloader -> C:\Users\...\Downloads\script.ps1
[X] Ransomware_LockBit_Stager -> C:\Users\...\Temp\update.exe
```

**Qué NO hace.** No corre como servicio en segundo plano. No escanea todo el disco automáticamente. No reemplaza a Defender: lo complementa. No usa reglas propietarias cerradas.

#### Transparencia del sistema

**El problema.** Muchos "limpiadores de privacidad" ofrecen "borrar historial de USB", "eliminar rastros de programas ejecutados", "limpiar historial de Wi-Fi". Suena bien, pero:

1. **No mejora tu privacidad real.** Si alguien tiene acceso físico o administrativo a tu PC, hay rastros en muchos otros lugares.
2. **Rompe cosas.** Borrar el historial de Wi-Fi hace que Windows no recuerde tus redes.
3. **Es peligroso.** Son exactamente los artefactos que se revisan en un peritaje.

**Cómo lo hace DeMente.** DeMente te **muestra** qué guarda Windows sobre vos, pero **no lo borra**:

- **Amcache**: qué ejecutables corrieron.
- **USBSTOR**: qué dispositivos USB se conectaron.
- **ShellBags**: qué carpetas abriste.
- **Perfiles Wi-Fi**: qué redes tenés guardadas.

**Filosofía**: si querés gestionar retención de datos real, la vía correcta es la **política de auditoría de Windows**, no borrar el pasado a mano.

```
USBSTOR - HISTORIAL DE DISPOSITIVOS USB (SOLO LECTURA)
[OK] 7 dispositivo(s) USB con historial en el registro.
    Dispositivo: Disk&Ven_SanDisk&Prod_Cruzer_Blade
    Dispositivo: Disk&Ven_Kingston&Prod_DataTraveler_3.0
```

---

### Privacidad

Todos los ajustes de privacidad de Windows 10/11 en un solo lugar, cada uno con explicación y reversión:

- ID de publicidad.
- Ubicación.
- Telemetría (incluye deshabilitar DiagTrack).
- Historial de actividad.
- Micrófono y cámara.
- Bing en la búsqueda del menú Inicio.
- GameDVR.
- Portapapeles en la nube.
- Destacados de búsqueda.
- CEIP / SQM.
- Tips y sugerencias.
- Copilot / integración de IA del shell.
- Apps en segundo plano.
- Experiencias personalizadas.
- Personalización de entrada.
- Frecuencia de feedback a Microsoft.
- Publicidad y sugerencias del Store.

Cada uno te explica **qué es** y **qué deja de pasar cuando lo apagás**.

---

### Reparación

- **Reparación completa (recomendada)**: DISM CheckHealth → DISM RestoreHealth → SFC. El orden de Microsoft. Con latido visible cada 30 segundos.
- **SFC /scannow**: revisa y repara archivos del sistema. DeMente lee el resultado real desde `CBS.log` y te da un veredicto humano: *"sistema sano"*, *"se repararon archivos"*, *"hay daños que SFC no pudo arreglar solo"*.
- **DISM /RestoreHealth**: repara la imagen base de Windows.
- **CHKDSK**: programa una revisión del disco para el próximo reinicio.
- **Reconstruir WMI**: para cuando procesos que dependen de WMI fallan.
- **Reparar DNS (seguro)**: solo limpia la caché DNS y reinicia el servicio. **No toca el adaptador.**
- **Reset agresivo de red**: marcado como peligro. Advierte que puede borrar IP fija, gateway y DNS manuales.

---

### Herramientas

Descargador y lanzador de utilidades de terceros desde fuentes oficiales:

- Autoruns, Process Explorer, Process Monitor, TCPView, BGInfo, SDelete (Sysinternals).
- NVCleanstall (instalador limpio de NVIDIA).
- DDU (Display Driver Uninstaller).
- CrystalDiskInfo.
- Everything.
- HWiNFO.
- Suite Sysinternals completa.

Binarios en `Documents\DeMente\tools`. Nada se empaqueta en el script.

---

### Información

- **Salud del sistema**: informe humano en 5 bloques.
- **Información del sistema**: hardware, Windows, disco.
- **Salud de los discos**: SMART, temperatura, desgaste, tendencia histórica.
- **Eventos del sistema**: errores y críticos de 48h agrupados y explicados.
- **Programas al inicio**: auditoría completa en modo lectura.
- **¿Por qué está lenta mi PC?**: diagnóstico explicativo con causas clasificadas.
- **Revisión completa del sistema**: mapa único con todo lo relevante.

---

## Cómo se usa

1. **Abrí DeMente.** El panel arranca el escaneo automático y te da el informe de salud.
2. **Mirá qué encontró.** El título y los hallazgos te dicen si hay algo urgente.
3. **Elegí cómo actuar:**
   - Modo automático (Plan DeMente es el recomendado).
   - Por sección, con los perfiles **ESENCIAL**, **COMPLETO** o **DEFAULT WINDOWS**.
   - Marcando herramientas individuales.
4. **Previsualizá.** DeMente te muestra exactamente qué va a hacer.
5. **Ejecutá.** El progreso se ve en la consola integrada.
6. **Revertí si algo no te gusta.** Cada cambio tiene su reversión.

---

## Dónde guarda las cosas

```
Documents\DeMente\
├── backups\
│   ├── registry\           Respaldos .reg antes de cada cambio
│   └── startup-state\      Estado original de servicios deshabilitados
├── HealthHistory\          Historial de salud de discos
├── perfiles\               Perfiles guardados manualmente
├── registros\              Logs de sesión
├── reportes\               Reportes generados
├── security\yara\          Motor y reglas de YARA
├── tools\                  Herramientas de terceros
├── configuracion.json      Preferencia de punto de restauración
└── tor-path.txt            Ruta de Tor Browser (si se eligió manualmente)
```

DeMente **no modifica nada fuera de esta carpeta** salvo los cambios que vos autorizás, y todo eso queda respaldado.

---

## Modo consola

```powershell
.\DeMente.ps1 -ListTools
.\DeMente.ps1 -RunTool clean-temp,perf-priority
.\DeMente.ps1 -SelfTest
.\DeMente.ps1 -NoGUI
```

`-SelfTest` verifica que el catálogo sea coherente, sin IDs duplicados, con perfiles que apunten a herramientas existentes y descripciones que coincidan con lo que hacen. Exit code: 0 si todo está bien, 1 si hay fallos.

---

## Requisitos

- Windows 10 o Windows 11 (x64).
- PowerShell 5.1 (incluido en Windows).
- Permisos de Administrador (DeMente se relanza automáticamente).
- Internet **solo** para YARA y herramientas de terceros. El resto funciona offline.

---

## Instalación

1. Descargá `DeMente_v1.0.0.1.ps1` (o el `.exe` portable si lo generaste).
2. Clic derecho → **Ejecutar con PowerShell** (o doble clic en el `.exe`).
3. Si no tenés permisos de administrador, DeMente te lo pide y se relanza.
4. La interfaz se abre y arranca el escaneo automático.

Sin instalación, sin desinstalación, sin basura.

---

## Seguridad y reversibilidad

- **Backups automáticos** de cada cambio de registro.
- **Puntos de restauración** opcionales.
- **Reversión para todos los ajustes** de rendimiento y privacidad.
- **Apps de inicio deshabilitadas, no eliminadas.**
- **Separación de riesgos**: verde / amarillo / rojo.
- **Sin telemetría propia.**
- **Sin binarios empaquetados**: todo desde fuentes oficiales.
- **Validación de descargas**: YARA verifica que el paquete no traiga ejecutables inesperados.

---

## Una última cosa

DeMente no va a hacer que una PC de 2010 con 2 GB de RAM corra como una de 2026. No va a hacer milagros. No va a inventar problemas para después venderte la solución.

Lo que sí va a hacer es **decirte la verdad sobre tu PC**, **darte las herramientas para mejorarla**, **decirte cuánto es ahorro real y cuánto se va a regenerar solo**, y **dejarte revertir todo si algo no te gusta**.

Si eso te alcanza, DeMente es para vos.

---

**"Ayudarnos es la única opción."**



- **Novedades de esta versión** al principio, con un bloque grande y claro.
- **Contraste con otros** en cada sección, sin nombrar a nadie.
- **Ej
