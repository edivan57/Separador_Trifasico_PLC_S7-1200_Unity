# Separador trifásico: plataforma Hardware-in-the-Loop con PLC S7-1200 y Unity
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24069678.svg)](https://doi.org/10.5281/zenodo.24069678)

Código, modelos, registros de pruebas y scripts de análisis del artículo **«Gestión de tiempos de respuesta en un separador trifásico mediante automatización basada en Hardware in the Loop para la evaluación de controladores PID, MPC y Fuzzy»** (MDPI *Processes*, en
preparación). El trabajo compara controladores **PI**, **Fuzzy (Mamdani)** y **MPC** sobre un separador trifásico
horizontal simulado en Unity, con los controladores ejecutándose en un **PLC Siemens S7-1200 (CPU 1212C)**.

## Qué contiene este repositorio

| Carpeta | Contenido |
|---|---|
| `Modelo/Matlab/` | Modelo no lineal del separador (`tpsep_v11.m`, `hemivols.m`, `hemivolt.m`, `hemihead.m`), escenario de 1000 s (`Escenario_Trifasico.m`), segundo escenario (`Escenario_Trifasico_2.m`) y punto de operación (`TPSEP_OperatingPoint.mat`) |
| `Modelo/Simulink/` | Modelos de Simulink del PI, el Fuzzy y el MPC, e inicialización del Fuzzy (`Fuzzy_init.m`) |
| `Modelo/Unity/` | Scripts de C# de Unity: modelo de la planta (`Separador_Trifasico.cs`), comunicación S7 sincronizada con reconexión (`Comunicacion_Sync.cs`) y mapa de DB1 (`DB1Mapa.cs`). `Comunicacion.cs` es una versión anterior, sin sincronización, que no se usó para los resultados |
| `Controladores/Fuzzy/` | Base de reglas del Fuzzy (`fis_tpsep_1block.fis`, 147 reglas) |
| `Controladores/MPC/` | Parámetros del MPC (`Parametros_MPC_v8.m`), construcción (`MPC_linealizar_v6_1.m`), sesión de MPC Toolbox (`TPSEP_MPC_v8_.mat`) y verificación del estimador (`verificar_estimador.m`) |
| `PLC/` | Código SCL de los controladores con la instrumentación de tiempo (`RUNTIME`), `HIL_Sync.scl`, `Diag_HIL.scl` y `Medir_OB.scl` (mide el intervalo entre arranques de un OB cíclico; se llama como primera instrucción de OB30, OB31 y OB32, cada uno con su DB de instancia) |
| `Datos/` | Registros de todas las pruebas del artículo |
| `Analisis/` | `calcular_ob_plc.m` (periodo de los OB medido en el PLC), `contrastar_qp_cotas.m` y `contrastar_qp_cotas_todas.m` (QP del SCL frente a `quadprog`), `generar_figuras_articulo_n.m` (figuras). |


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

## Requisitos

| Componente | Versión |
|---|---|
| PLC | Siemens S7-1200, CPU 1212C AC/DC/Rly (6ES7212-1BE40-0XB0), firmware V4.5.2 (configurado como V4.4) |
| Ingeniería del PLC | TIA Portal V16 |
| Simulación de la planta | Unity 2020.3.48f1 (modo *No Throttling*) y la biblioteca Sharp7 (no se incluye; ver su licencia) |
| MATLAB | R2024a (la de Simulink PLC Coder 24.1) con Simulink, Simulink PLC Coder 24.1 y MPC Toolbox (solo para regenerar controladores y para `verificar_estimador.m`). Los scripts de `analisis/` no necesitan toolboxes y funcionan desde R2016b (las figuras, desde R2018a); `contrastar_qp_cotas*.m` usa `quadprog` (Optimization Toolbox) |


## Versiones

| Versión | Cambios |
|---|---|
| 2.0.0 | Campañas nominal y de robustez con cinco repeticiones y pausa de 3 s entre repeticiones; sesión alternada con TIA Portal en línea y desconectado; cortes de comunicación con dos lógicas de reconexión (`Ciclos_Watchdog` de 10 y de 2) y cortes con cable; medición del periodo de los OB dentro del PLC (`Medir_OB.scl`); contraste del QP del MPC frente a `quadprog`; scripts de análisis actualizados (https://doi.org/10.5281/zenodo.24069678)|
| 1.0.1 | Versión archivada anteriormente en Zenodo (https://doi.org/10.5281/zenodo.23824492) |

## Licencia

- Código (MATLAB, C#, SCL)
- Datos y modelos: Autor

La biblioteca Sharp7 y los productos de MathWorks, Siemens y Unity tienen sus propias licencias y no se redistribuyen aquí.

## Cómo citar

Ver `CITATION.cff`. Registro en Zenodo: https://doi.org/10.5281/zenodo.24069678

> De la Cruz Vaca, E.I.; Chasi Pesántez, P.A. *Gestión de tiempos de respuesta en un separador trifásico mediante automatización basada en Hardware in the Loop para la evaluación de controladores PID, MPC y Fuzzy*. *Processes* **2026**, *[volumen]*, [artículo].

## Autores

- Edgar Iván De la Cruz Vaca — GitHub: [@edivan57](https://github.com/edivan57)
