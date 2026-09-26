# hotbar — la barra flotante

> Widget de Windows independiente: siempre encima, forma de media luna, celdas
> configurables y el estado de OmniRoute a un clic. No es un pane de Herdr y no
> necesita que Herdr esté corriendo.

## Qué es y qué no es

**Es** una ventana WPF de 72 x 400 px anclada al borde derecho del monitor
primario, centrada verticalmente, sin marco, sin entrada en la barra de tareas y
con fondo transparente. Al expandirse dibuja una media luna alargada; al
colapsarse queda una pestaña semicircular de 46 px.

**No es** un pane de Herdr. Esa distinción es deliberada y explica tres
decisiones:

| Necesidad | Consecuencia |
| --- | --- |
| Sobrevivir a la sesión | Un pane lo abre y cierra Herdr; la barra es un elemento del escritorio |
| No costar espacio | `placement = "popup"` no reserva nada; una ventana encima no reserva nada |
| No depender de una terminal | Un popup es un modal de sesión que se traga el input; una ventana WPF no |

## Arrancar

```powershell
.\hotbar\launch-hotbar.ps1
```

El lanzador es el único punto de entrada que una persona ejecuta. Se encarga de
lo que es del host —apartamento STA, consola oculta, rechazo de una segunda
instancia— para que `hotbar.ps1` solo tenga que asumir que ya corre sobre un
hilo STA bombeado.

Para probarlo sin dejar nada abierto:

```powershell
.\hotbar\launch-hotbar.ps1 -SelfTest
```

## Configuración: `hotbar/config.json`

El archivo entero es la configuración. Cada ítem lleva glifo, etiqueta, tooltip y
acción:

```json
{
  "margin": 8,
  "items": [
    { "id": "claude",    "label": "Claude",    "glyph": "0x2733", "action": "none" },
    { "id": "omniroute", "label": "OmniRoute", "glyph": "0x25A3", "action": "omniroute-status" }
  ]
}
```

### Glifos como puntos de código

Los glifos se escriben como `0xNNNN`, nunca como carácter literal. Todo el árbol
queda en ASCII puro y un glifo equivocado es un error de parseo en vez de un
caracterismo raro:

| Código | Glifo | Uso |
| --- | --- | --- |
| `0x2733` | ✳ | Claude |
| `0x25CE` | ◎ | Codex |
| `0x25C8` | ◈ | OpenCode |
| `0x25A3` | ▣ | OmniRoute |
| `0x2699` | ⚙ | Ajustes |

### Acciones

| `action` | Efecto |
| --- | --- |
| `none` | La celda se dibuja y no hace nada. Es un hueco honesto, no un error |
| `omniroute-status` | Expande el panel inline con la foto del gateway |
| `edit-config` | Abre `config.json` en el editor por defecto |
| `run: <comando>` | Ejecuta un comando. Un objetivo `.cmd`/`.bat` pasa por `cmd.exe /d /c`; admite `cwd` opcional |

### Recargar sin reiniciar

Clic derecho → **Reload config**. Releer el JSON y reconstruye las celdas sin
tocar el proceso. Si el archivo está roto, el panel lo dice y la barra sigue en
pie con las celdas anteriores: una configuración inválida no puede tumbar el
widget.

## Interacción

| Gesto | Resultado |
| --- | --- |
| Clic en el chevron superior | Colapsa a la pestaña de 46 px |
| Clic en la pestaña | Expande de nuevo |
| Clic en la celda OmniRoute | Abre/cierra el panel inline |
| Clic derecho | Menú: abrir config, recargar, colapsar, salir |
| `Escape` | Salir |

El menú contextual y `Escape` existen porque un widget sin marco no tiene barra
de título: sin ellos no habría forma fiable de cerrarlo.

## La media luna no es decorativa

La barra es `72 x 400` con `CornerRadius="200,0,0,200"`, que WPF **no** recorta al
ancho: produce una media elipse real. En la fila `y` el ancho usable es:

```text
72 * sqrt(1 - ((y - 200) / 200)^2)
```

Medido en pantalla, el borde izquierdo llega a `x = 0` exactamente en `y = 200` y
se cierra simétricamente hacia los dos extremos. Por eso la columna de celdas va
**alineada a la derecha** (contra el borde recto) y mide 44 px: el contenido
ocupa `dy 68..332`, donde la curva deja 54 px. Dimensionar las celdas a ojo
cortaba las de arriba y abajo con el bulbo.

La ventana mantiene su borde **derecho** anclado al área de trabajo del monitor y
se desplaza a la izquierda lo que mida el panel al abrirlo, de modo que la luna
nunca sale de la pantalla. Por eso la barra es la última columna del grid y por
eso `BarBorder` no lleva `Width`: fijarlo a 72 lo centraría dentro de la ventana
ancha del modo panel.

## El panel inline

Al pulsar la celda OmniRoute se abre un panel de 320 px a la **izquierda** de la
barra con la foto del gateway: UP/DOWN en `:20128`, combo activo y combos
configurados, leídos del `storage.sqlite` del propio gateway en modo solo
lectura. Mismo camino de datos que el popup del plugin, sin terminal y sin modal.

Igual que el popup, nunca invoca la CLI de OmniRoute: la lectura directa cuesta
33–57 ms frente a 3–9 s por frame de la CLI. Ver
[Where the data comes from](../README.md#where-the-data-comes-from).

## El self test

```powershell
.\hotbar\launch-hotbar.ps1 -SelfTest
```

Imprime una línea `HOTBAR_SELFTEST` por comprobación y devuelve un código de
salida real:

| Comprobación | Qué falla si se rompe |
| --- | --- |
| `config=` / `items=` | JSON ilegible o sin ítems |
| Glifos y acciones por ítem | `0xZZZZ` o una acción no soportada |
| `xaml=ok buttons=N` | XAML mal formado o celdas no creadas |
| `geometry` | Posición o tamaño contra el monitor real |
| `data gateway=/combos=/provider=` | Gateway caído o SQLite ilegible |
| `panel_lines=N` | Panel con menos de 4 líneas o texto que desborda el ancho |
| `shown_ms=` | La ventana no cerró sola |

Un self test que solo puede pasar no vale nada, así que el camino de fallo también
se ejercita: con una acción no soportada o un glifo inválido reporta el ítem
concreto y sale con 1.

La ventana se cierra con un `DispatcherTimer` y un watchdog de hilo detrás, así
que **nada puede dejar colgada a quien la llama** ni dejar una ventana abierta.

## Sustituir la lógica por datos

`hotbar/lib/` contiene copias independientes de los lectores del plugin, no
referencias: el widget tiene que funcionar aunque el plugin no esté enlazado en
Herdr, y una copia de 200 líneas sale más barato que un esquema de resolución que
fallaría justo en el caso para el que existe el widget.

| Fichero | Responsabilidad |
| --- | --- |
| `hotbar/lib/Invoke-Native.ps1` | Helper de proceso sin ventana (`CreateNoWindow`) |
| `hotbar/lib/Get-OmniRouteStatus.ps1` | Sonda de `:20128` en escucha |
| `hotbar/lib/Read-SqliteQuery.ps1` | SQLite de solo lectura: `sqlite3.exe` primero, P/Invoke a `winsqlite3.dll` como reserva |
| `hotbar/lib/Get-OmniRouteCombos.ps1` | Resuelve `storage.sqlite` y mapea la tabla de combos |

## Problemas frecuentes

| Síntoma | Causa | Arreglo |
| --- | --- | --- |
| `HOTBAR_SELFTEST FAIL: current thread is MTA` | Se invocó sin STA | Usa `launch-hotbar.ps1`; él se encarga |
| `hotbar: already running` | Ya hay una barra | Correcto. `Exit 3` en la invocación directa significa lo mismo |
| La barra no aparece | Se cerró con `Escape` o con el menú | Vuelve a lanzarla; el mutex no la bloquea |
| La barra sale de la pantalla | Se movió el monitor o cambió la resolución | Recolócala: se ancla al área de trabajo del primario en cada arranque |
| El panel no muestra combos | Sin `sqlite3.exe` y sin `winsqlite3.dll`, o la build de OmniRoute sin JSON | El panel lo dice explícitamente; nunca muestra una lista vacía |
| Parpadeo de consola al lanzar | — | El lanzador usa `-WindowStyle Hidden`; si aparece, no se está lanzando por el lanzador |
| Celdas vacías | `action: "none"` | Es un hueco declarado. Pon una acción real o quita el ítem |

## Restricciones

- El widget **solo lee**. Nunca toca la API key, ni
  `~/.omniroute/omni-route.env`, ni la config de Herdr. La escritura en
  `config.json` ocurre únicamente cuando el usuario elige **Edit config** desde
  el menú, y es su propio editor quien la hace.
- Nada se escribe en el directorio de instalación de ninguna herramienta, así que
  una actualización de Herdr, pi u OmniRoute no puede romperlo.
- Todo el árbol (`hotbar/*.ps1`, `scripts/*.ps1`, manifest, config) se mantiene en
  **ASCII puro**: los caracteres no imprimibles van como entidad XML o como
  `[char]0xNNNN`.
