# Separador trifásico: plataforma Hardware-in-the-Loop con PLC S7-1200 y Unity
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24295183.svg)](https://doi.org/10.5281/zenodo.24295183)

Código, modelos, registros de pruebas y scripts de análisis del artículo **«Gestión de tiempos de respuesta en un separador trifásico mediante automatización basada en Hardware in the Loop para la evaluación de controladores PID, MPC y Fuzzy»** (MDPI *Processes*, en
preparación). El trabajo compara controladores **PID** (estructura incremental ejecutada con $T_d=0$), **Fuzzy (Mamdani)** y **MPC** sobre un separador trifásico
horizontal simulado en Unity, con los controladores ejecutándose en un **PLC Siemens S7-1200 (CPU 1212C)**.

| Carpeta | Contenido |
|---|---|
| `Modelo/Matlab/` | Modelo corregido del separador (`tpsep_v12.m`, el de la versión 3.0.0, y `tpsep_v12_bloque.m`, su versión para el bloque *MATLAB Function* de Simulink), modelo de referencia (`tpsep_v11.m`), geometría (`hemivols.m`, `hemivolt.m`, `hemihead.m`), escenario de 1000 s (`Escenario_Trifasico.m`), segundo escenario (`Escenario_Trifasico_2.m`), punto de operación (`TPSEP_OperatingPoint.mat`) y sesión de MPC Toolbox (`TPSEP_MPC_v8_.mat`) |
| `Modelo/Simulink/` | Modelos de Simulink del PID, el Fuzzy y el MPC, e inicialización del Fuzzy (`Fuzzy_init.m`).|
| `Modelo/Unity/` | Scripts de C# de Unity: modelo de la planta (`Separador_Trifasico.cs`, comunicación S7 sincronizada (`Comunicacion_Sync.cs`: inyección de fallas y reconexión tras un corte real del cable) y mapa de DB1 (`DB1Mapa.cs`). `Comunicacion.cs` |
| `Controladores/Fuzzy/` | Base de reglas del Fuzzy (`fis_tpsep_1block.fis`, 147 reglas) |
| `Controladores/MPC/` | Parámetros del MPC (`Parametros_MPC_v8.m`), construcción (`MPC_linealizar_v6.m`) y verificación del estimador (`verificar_estimador.m`). Con el modelo corregido: punto de operación (`punto_operacion_v12.m`), MPC con la linealización corregida `MPC_linealizar_v12.m` |
| `PLC/` | Código SCL de los controladores con la instrumentación de tiempo (`RUNTIME`), `HIL_Sync.scl`, `Diag_HIL.scl`, `Medir_OB.scl` (mide el intervalo entre arranques de un OB cíclico) y el proyecto de TIA Portal V16 (`Separador_Trifasico_v3.ap16`) |
| `Datos/` | Registros de todas las pruebas. Cada carpeta corresponde a un modelo de planta: ver [Datos por modelo de planta](#datos-por-modelo-de-planta) |
| `Analisis/` | Scripts que reproducen las tablas y figuras del artículo (`calcular_resultados_articulo.m`, `generar_figuras_articulo_n.m` y los que lista [`LISTADO_CODIGOS_MATLAB.md`](LISTADO_CODIGOS_MATLAB.md), en la raíz del repositorio) y, en `resultados_v12/`, las tablas que dan. Conserva además copias de registros y simulaciones de la versión 2.0.2 (`pid_run22_flat.mat` y `fuzzy_run23_flat.mat` son las corridas de Simulink con el modelo de referencia que usa la comparación entre modelos) |


## Plataforma

```
 MATLAB / Simulink ── PLC Coder ──► SCL ──► TIA Portal ──► CPU 1212C (OB30 MPC · OB31 Fuzzy · OB32 PID, 100 ms)
        (diseño y simulación)                                      ▲ │
                                                       protocolo S7 │ │ (medición, ganancias, eco del contador)
                                                                    │ ▼
                                                  Unity: modelo del separador en C# + visualización
```

- El lazo se cierra entre el PLC y Unity por Ethernet (enlace punto a punto, Sharp7). La planta avanza **un paso de
  0.1 s por cada ciclo del PLC**; el eco del número de medición permite medir latencia, retención y retardo.
- Escenario de ajuste de **1000 s** (10 fases de 100 s): siete cambios de referencia y seis de caudal de entrada. Un segundo escenario de 1000 s (`Escenario_Trifasico_2.m`) se evalúa solo en simulación.
- Unidades: alturas en ft, presión en psi, temperatura en °F y aperturas en % (los registros guardan niveles en m).
- Todas las campañas de la versión 3.0.0 se hicieron con TIA Portal V16 desconectado durante la corrida; los
  diagnósticos se leyeron al terminar.

## Datos por modelo de planta

Los nombres de los archivos no indican el modelo de la planta; lo indica la carpeta. Hay dos modelos:

- **Modelo corregido** (`Modelo/Matlab/tpsep_v12.m` y `Separador_Trifasico.cs` con `modeloCorregidoV12 = true`): balance de gas en presión absoluta, caudal estándar convertido, una sola base de presión, límite de flujo crítico, capa de crudo por diferencia de volúmenes y colector siempre activo. Es la planta de todas las campañas HIL del artículo.
- **Modelo de referencia** (`Modelo/Matlab/tpsep_v11.m`): el de la tesis de partida, sin esas correcciones. Con él se sintonizaron los tres controladores.

### Modelo corregido: respaldan las cifras del artículo

| Carpeta | Plataforma | Contenido | Dónde se usa en el artículo |
|---|---|---|---|
| `Datos/Nominal_v12/<Ctrl>/` | CPU 1212C y Unity | Cinco repeticiones del escenario de ajuste por controlador (`Datos_<CTRL>_rep01` a `rep05`) y un `Diag_Com_Ninguna_*.csv` | Respuestas, integrales del error, escalones, perturbaciones, esfuerzo de control, temporización, latencia y contraste del QP; Tablas S3, S10 y S11 |
| `Datos/Robustez_v12/<Ctrl>/` | CPU 1212C y Unity | Cinco realizaciones con variación de parámetros y ruido de medición | Tabla del ruido; Tabla S4 |
| `Datos/Reconexion_v12/C1b_wd2/`, `C2b_wd2/` | CPU 1212C y Unity | Cortes emulados de 5 s (C1 en régimen, C2 en un transitorio), tres repeticiones por controlador, `Ciclos_Watchdog = 2` | Tabla del corte C2; Tabla S5 |
| `Datos/Reconexion_v12/Cable_wd2/` | CPU 1212C y Unity | Corte con retiro del cable, una corrida por controlador | Tabla S6 y Figura S2 |
| `Datos/Fallas_v12/<Ctrl>/` | CPU 1212C y Unity | Fallas C3 a C5 (pérdida de paquetes, retardo y sesgo del sensor), una corrida por caso | Tabla S5 |
| `Datos/Modelo_v12/` | Simulink (ode3, paso de 0.01 s) | Corridas de diseño: `esc1` es el escenario de ajuste y `esc2` el segundo escenario; `v12A`, sintonías sin reajuste; `v12B`, MPC con el modelo interno del modelo corregido; `_arranque`, `_limites`, `_memoria` y `_comun`, condiciones de implementación; `_P50` y `_P100`, horizonte de predicción | Tablas de condiciones comunes, segundo escenario, horizonte, efecto del modelo y variantes del MPC; Tabla S10 |

Todas las campañas en la CPU de esta tabla se hicieron con TIA Portal desconectado durante la corrida.

### Modelo de referencia: el artículo las usa con esa salvedad

| Carpeta o archivo | Plataforma | Contenido | Dónde se usa en el artículo |
|---|---|---|---|
| `Datos/mpc_1212C/` | CPU 1212C y Unity | MPC completo en la CPU, que excede el periodo de 100 ms | Tablas de costo y de variantes del MPC |
| `Datos/TIA Desconectado/MPC/` | CPU 1212C y Unity | Cuatro repeticiones del MPC: 1 y 3 con TIA Portal en línea, 2 y 4 desconectado | Tabla del efecto de TIA Portal |
| `Datos/OB_PLC/` | CPU 1212C (`Medir_OB.scl`) | Acumuladores leídos en TIA Portal (`medir_ob_nominal_20261107.csv`) y sus capturas | Tabla del periodo del OB |
| `Datos/Modelo_v12/mpc_esc1_v11_flat.mat`, `Analisis/pid_run22_flat.mat`, `Analisis/fuzzy_run23_flat.mat` | Simulink | MPC, PID y Fuzzy con el modelo de referencia | Tabla del efecto del modelo (filas «De referencia») y filas con † de la tabla de variantes |

El periodo del OB lo fija el PLC y no depende del modelo de la planta. El artículo indica en cada caso qué mediciones se hicieron con el modelo de referencia.

### Versión 2.0.2: no respaldan las cifras del artículo

`Datos/Nominal/`, `Datos/Robustez/`, `Datos/Fallas/`, `Datos/Reconexion/`, `Datos/Corte real/` y `Datos/Simulink_diseño/` son las campañas anteriores a la corrección del modelo, hechas con el modelo de referencia. Se conservan como registro histórico. Sus cifras no coinciden con las del artículo: por ejemplo, el IAE de presión del PID nominal es de unos 345 psi·s con el modelo de referencia y de 755.5 psi·s con el corregido.

## Cómo reproducir las tablas

1. Clonar el repositorio o descargar la versión de Zenodo.
2. En MATLAB (R2016b o posterior) o GNU Octave, desde cualquier carpeta:
   ```matlab
   addpath('<ruta del repositorio>/Analisis')
   calcular_resultados_articulo
   ```
   El script encuentra `Datos/` por sí solo, avisa si falta algún registro y guarda las tablas en `Analisis/resultados_v12/`.
3. Desde la raíz del repositorio, `contrastar_qp_cotas_todas` reproduce el contraste del QP (en MATLAB necesita Optimization Toolbox) y `calcular_ob_plc`, el periodo del OB.

[`LISTADO_CODIGOS_MATLAB.md`](LISTADO_CODIGOS_MATLAB.md) relaciona cada resultado del artículo con su script y sus registros, y da el orden completo para reproducirlos, incluidas las corridas de Simulink. La Tabla S9 del material suplementario hace lo mismo para cada figura y tabla.

## Requisitos

| Componente | Versión |
|---|---|
| PLC | Siemens S7-1200, CPU 1212C AC/DC/Rly (6ES7212-1BE40-0XB0), firmware V4.5.2 (configurado como V4.4) |
| Ingeniería del PLC | TIA Portal V16 |
| Simulación de la planta | Unity 2020.3.48f1 (modo *No Throttling*) y la biblioteca Sharp7 (no se incluye; ver su licencia) |
| MATLAB | R2024a (la de Simulink PLC Coder 24.1) con Simulink, Simulink PLC Coder 24.1 y MPC Toolbox (solo para regenerar controladores y correr simulaciones). Los scripts de `Analisis/` funcionan desde R2016b (las figuras, desde R2018a) y no necesitan toolboxes, salvo `contrastar_qp_cotas*.m`, que en MATLAB usa `quadprog` (Optimization Toolbox). Las cifras del contraste del QP que da el artículo salen de MATLAB con `quadprog`; en GNU Octave el mismo script usa `qp` |


## Versiones

| Versión | Cambios |
|---|---|
| 3.1.2 | Versión que cita el artículo. El contraste del QP del MPC usa como referencia `quadprog` de MATLAB (*interior-point-convex*, holgura libre) e informa el código de salida, la optimalidad de primer orden y las iteraciones de la referencia; `Analisis/resultados_v12/salida_contrastar_qp_cotas_v12.txt` sale de MATLAB.|
| 3.1.1 | Añade las corridas de Simulink del PID y del Fuzzy con la planta corregida y la configuración de la CPU, las tablas de sensibilidad que salen de ellas, `LISTADO_CODIGOS_MATLAB.md` (https://doi.org/10.5281/zenodo.24295183) |
| 3.1.0 | Script de las tablas (`calcular_resultados_articulo.m`, corridas de simulación de `Datos/Modelo_v12/`, MPC completo en la CPU (`Datos/MPC_1212C/`), SCL del MPC reducido, scripts de simulación, del segundo escenario y de verificación (https://doi.org/10.5281/zenodo.24290553) |
| 3.0.0 | Modelo de la planta corregido (`tpsep_v12.m`). Con ese modelo y los mismos controladores: campañas nominal, de robustez, de cortes (C1, C2 y cable) y de fallas C3 a C5 en la CPU 1212C, todas con `Ciclos_Watchdog = 2` y TIA Portal desconectado (`Datos/*_v12/`); simulaciones del efecto del modelo, de las condiciones comunes, del horizonte de predicción y del segundo escenario (`Datos/Modelo_v12/`). Scripts de simulación y de verificación del modelo corregido; scripts de Unity con la secuencia de fallas y la reconexión tras un corte real (https://doi.org/10.5281/zenodo.24284441) |
| 2.0.2 | Campañas nominal y de robustez con cinco repeticiones y pausa de 3 s entre repeticiones; sesión alternada con TIA Portal en línea y desconectado; cortes de comunicación con dos lógicas de reconexión (`Ciclos_Watchdog` de 10 y de 2) y cortes con cable; medición del periodo de los OB dentro del PLC (`Medir_OB.scl`); contraste del QP del MPC frente a `quadprog` (https://doi.org/10.5281/zenodo.24069678) |
| 1.0.1 | Versión archivada anteriormente en Zenodo (https://doi.org/10.5281/zenodo.23824492) |

## Licencia

- Código (MATLAB, C#, SCL): MIT
- Datos y modelos: se pueden copiar, redistribuir y adaptar citando la fuente (ver `LICENSE.md`)

La biblioteca Sharp7 y los productos de MathWorks, Siemens y Unity tienen sus propias licencias y no se redistribuyen aquí.

## Cómo citar

Para el repositorio, ver `CITATION.cff` (botón «Cite this repository» de GitHub) y el registro en Zenodo. Para el artículo:

> De la Cruz Vaca, E.I.; Chasi Pesántez, P.A. *Gestión de tiempos de respuesta en un separador trifásico mediante automatización basada en Hardware in the Loop para la evaluación de controladores PID, MPC y Fuzzy*. *Processes* **2026**, *[volumen]*, [artículo].

## Autores

- Edgar Iván De la Cruz Vaca (Universidad Politécnica Salesiana, ORCID [0009-0004-1218-8570](https://orcid.org/0009-0004-1218-8570)) — GitHub: [@edivan57](https://github.com/edivan57)
