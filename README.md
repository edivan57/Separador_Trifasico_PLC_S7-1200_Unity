# Separador trifásico: plataforma Hardware-in-the-Loop con PLC S7-1200 y Unity
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24069678.svg)](https://doi.org/10.5281/zenodo.24069678)

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
| `Datos/` | Registros de todas las pruebas (ver [Datos](#datos)) |
| `Analisis/` | Scripts que reproducen las tablas y figuras del artículo, conserva además copias de registros y simulaciones de la versión 2.0.2 que usaban versiones anteriores de los scripts |


## Plataforma

```
 MATLAB / Simulink ── PLC Coder ──► SCL ──► TIA Portal ──► CPU 1212C (OB30 MPC · OB31 Fuzzy · OB32 PI, 100 ms)
        (diseño y simulación)                                      ▲ │
                                                       protocolo S7 │ │ (medición, ganancias, eco del contador)
                                                                    │ ▼
                                                  Unity: modelo del separador en C# + visualización
```

- El lazo se cierra entre el PLC y Unity por Ethernet (enlace punto a punto, Sharp7). La planta avanza **un paso de
  0.1 s por cada ciclo del PLC**; el eco del número de medición permite medir latencia, retención y retardo.
- Escenario único de **1000 s** (10 fases de 100 s): siete cambios de referencia y seis de caudal de entrada.
- Unidades: alturas en ft, presión en psi, temperatura en °F y aperturas en % (los registros guardan niveles en m).
- Todas las campañas de la versión 3.0.0 se hicieron con TIA Portal V16 desconectado durante la corrida; los
  diagnósticos se leyeron al terminar.

## Requisitos

| Componente | Versión |
|---|---|
| PLC | Siemens S7-1200, CPU 1212C AC/DC/Rly (6ES7212-1BE40-0XB0), firmware V4.5.2 (configurado como V4.4) |
| Ingeniería del PLC | TIA Portal V16 |
| Simulación de la planta | Unity 2020.3.48f1 (modo *No Throttling*) y la biblioteca Sharp7 (no se incluye; ver su licencia) |
| MATLAB | R2024a (la de Simulink PLC Coder 24.1) con Simulink, Simulink PLC Coder 24.1 y MPC Toolbox (solo para regenerar controladores y correr simulaciones). Los scripts de `analisis/` no necesitan toolboxes y funcionan desde R2016b (las figuras, desde R2018a); `contrastar_qp_cotas*.m` usa `quadprog` (Optimization Toolbox) |


## Versiones

| Versión | Cambios |
|---|---|
| 3.0.0 | Modelo de la planta corregido (`tpsep_v12.m`). Con ese modelo y los mismos controladores: campañas nominal, de robustez, de cortes (C1, C2 y cable) y de fallas C3 a C5 en la CPU 1212C, todas con `Ciclos_Watchdog = 2` y TIA Portal desconectado (`Datos/*_v12/`); simulaciones del efecto del modelo, de las condiciones comunes, del horizonte de predicción y del segundo escenario (`Datos/Modelo_v12/`). Scripts de simulación y de verificación del modelo corregido; scripts de Unity con la secuencia de fallas y la reconexión tras un corte real |
| 2.0.2 | Campañas nominal y de robustez con cinco repeticiones y pausa de 3 s entre repeticiones; sesión alternada con TIA Portal en línea y desconectado; cortes de comunicación con dos lógicas de reconexión (`Ciclos_Watchdog` de 10 y de 2) y cortes con cable; medición del periodo de los OB dentro del PLC (`Medir_OB.scl`); contraste del QP del MPC frente a `quadprog` (https://doi.org/10.5281/zenodo.24069678) |
| 1.0.1 | Versión archivada anteriormente en Zenodo (https://doi.org/10.5281/zenodo.23824492) |

## Licencia

- Código (MATLAB, C#, SCL): MIT
- Datos y modelos: Autor

La biblioteca Sharp7 y los productos de MathWorks, Siemens y Unity tienen sus propias licencias y no se redistribuyen aquí.

## Cómo citar

Para el repositorio, ver `CITATION.cff` (botón «Cite this repository» de GitHub) y el registro en Zenodo. Para el artículo:

> De la Cruz Vaca, E.I.; Chasi Pesántez, P.A. *Gestión de tiempos de respuesta en un separador trifásico mediante automatización basada en Hardware in the Loop para la evaluación de controladores PID, MPC y Fuzzy*. *Processes* **2026**, *[volumen]*, [artículo].

## Autores

- Edgar Iván De la Cruz Vaca (Universidad Politécnica Salesiana, ORCID [0009-0004-1218-8570](https://orcid.org/0009-0004-1218-8570)) — GitHub: [@edivan57](https://github.com/edivan57)
