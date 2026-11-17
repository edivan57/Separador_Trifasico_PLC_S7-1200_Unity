# Códigos de MATLAB del artículo (versión 3.1.2)

De qué script y de qué registros sale cada resultado del artículo, y el orden para reproducirlos. Las carpetas son las
del repositorio. Desde la versión 3.0.0, la planta de todas las campañas es el modelo corregido `tpsep_v12.m`; el
modelo de referencia (`tpsep_v11.m`) se conserva para la comparación entre modelos.

## 1. Archivos nuevos o cambiados en la versión 3.0.0

| Carpeta | Archivo | Qué hace | Requiere |
|---|---|---|---|
| `Modelo/Matlab/` | `tpsep_v12.m` | Modelo corregido: gas en presión absoluta, caudal estándar convertido, una base de presión, flujo crítico, capa de crudo por diferencia de volúmenes y colector siempre activo. Cada corrección se puede desactivar (con todas desactivadas reproduce `tpsep_v11.m`) | `hemivols.m`, `hemivolt.m`, `hemihead.m` |
| `Modelo/Matlab/` | `tpsep_v12_bloque.m` | El mismo modelo para el bloque *MATLAB Function* de Simulink | Nada |
| `PLC/` | `Simulacion_Trifasico_MPC_v8_M6_reducido_S71200_b.scl` | MPC reducido (fila de la tabla de variantes) | TIA Portal V16 |
| `Modelo/Matlab/` | `Escenario_Trifasico_2.m` | Segundo escenario (sin cambios; SHA-256 `188b1351c4cf315c138b17efb89e6e046ac1a30c38b9bd5e479d5fafc87506f5`, el que cita la sección S7 del suplemento) | Nada |
| `Modelo/Simulink/` | `crear_modelos_v12.m` | Copias `*_v12.slx` de los modelos con la planta corregida | Simulink |
| `Modelo/Simulink/` | `crear_modelos_comun_v12.m` | Variantes del PID y del Fuzzy con condiciones comunes (`arranque`, `limites`, `memoria`, `comun`) | Simulink |
| `Modelo/Simulink/` | `correr_comparacion_v12.m` y `guardar_flat.m` | Corren los escenarios y guardan cada corrida en `Datos/Modelo_v12/` | Simulink y MPC Toolbox |
| `Controladores/MPC/` | `MPC_linealizar_v6_1.m` | Igual que `MPC_linealizar_v6.m`, sin la definición del escenario (está en los `Escenario_*.m`) | MPC Toolbox |
| `Controladores/MPC/` | `punto_operacion_v12.m`, `MPC_linealizar_v12.m` | Punto de operación del modelo corregido y MPC con su linealización (solo para el caso B de la tabla del efecto del modelo) | MPC Toolbox |
| `Controladores/MPC/` | `sintonia_v12.m` | Ganancias $K_w$, $K_o$, $K_g$ de ambos modelos y amortiguamiento y frecuencia natural del PID con la planta corregida | Nada |
| `Controladores/MPC/` | `crear_mpc_horizontes.m` | Copias del MPC de diseño con $P$ = 100 y 50 (`TPSEP_MPC_diseno_P100.mat`, `_P50.mat`) | MPC Toolbox |
| `Modelo/Unity/` | `Separador_Trifasico.cs`, `Comunicacion_Sync.cs` | Planta corregida en Unity, secuencia de fallas C3 a C5, inyección de fallas y reconexión tras un corte real | Unity 2020.3 y Sharp7 |
| `Analisis/` | `calcular_resultados_articulo.m` | Todas las tablas de Resultados. Con `C.modelo_planta = 'v12'` (por omisión) lee `Datos/*_v12` y `Datos/Modelo_v12`; con `'v11'`, las campañas de la versión 2.0.2 | Nada (MATLAB R2016b o posterior, u Octave) |
| `Analisis/` | `reproducir_replicas_v12.m` | Verificación del modelo: réplica en lazo abierto de las corridas HIL (Euler, diez subpasos) y de Simulink (ode3), carga mínima sobre el vertedero y balance de volumen | `tpsep_v12.m`, `hemivols.m` |
| `Analisis/` | `verificar_modelo_v12.m` | Pruebas del modelo corregido: regresión frente a `tpsep_v11.m`, equilibrio, ganancias, efecto de cada corrección y conservación | `tpsep_v11.m`, `tpsep_v12.m` y la geometría |
| `Analisis/` | `comparar_modelos_v12.m` | Modelo de referencia frente al corregido con las mismas sintonías (IAE, $M_p$, $t_s$, saturación y variación total) | Corridas `*_esc1_v11`, `_v12A` y `_v12B` |
| `Analisis/` | `comparar_hil_simulink.m` | Corrida de la CPU frente a la de Simulink con el mismo controlador | Una corrida de cada plataforma |
| `Analisis/` | `cronograma_escenario2.m`, `eventos_escenario2.m`, `probar_escenario2.m` | Cronograma, eventos y pruebas del segundo escenario (tercer argumento `'v12'`) | `Escenario_Trifasico_2.m` y las corridas `*_esc2_v12A*` |
| `Analisis/` | `contrastar_qp_cotas.m`, `contrastar_qp_cotas_todas.m` | QP del SCL de cotas frente a una solución numérica de referencia: `quadprog` de MATLAB (*interior-point-convex*, holgura libre), del que salen las cifras del artículo, o `qp` de GNU Octave (conjunto activo). Informan el código de salida de la referencia, el mayor incumplimiento de cotas, la optimalidad de primer orden (en Octave, el residuo de gradiente proyectado), las iteraciones, la holgura y, en el vector completo de 18 movimientos, la diferencia de solución y de costo. Por omisión usan `Datos/Nominal_v12/MPC` | `quadprog` (Optimization Toolbox) en MATLAB o `qp` en Octave |
| `Analisis/` | `generar_figuras_articulo_n.m` | Figuras con los registros de la versión 3.0.0 | MATLAB R2018a o posterior |
| `Analisis/resultados_v12/` | `*.csv`, `salida_calcular_resultados_v12.txt`, `salida_contrastar_qp_cotas_v12.txt` | Tablas y salidas que dan los scripts, tal como entran en el artículo. `tabla_un_solo_cambio.csv` y `tabla_condiciones_comunes.csv` son la tabla de sensibilidad, toda en Simulink | — |

## 2. Del artículo al código

| En el artículo | Código | Registros |
|---|---|---|
| Ecuaciones y parámetros del modelo | `tpsep_v12.m` | — |
| Ganancias $K_j$ y $\zeta$, $\omega_n$ con la planta corregida (tablas del PID y del Fuzzy) | `sintonia_v12.m` | — |
| Matrices del modelo interno del MPC | `MPC_linealizar_v6_1.m` | — |
| Matrices de la planta corregida (apéndice) | `MPC_linealizar_v12.m` | — |
| Verificación del modelo (Sección 3.1) | `reproducir_replicas_v12.m` | `Nominal_v12`, `Modelo_v12` |
| Temporización, latencia y costo | `calcular_resultados_articulo.m`: `tabla_tiempo_real.csv`, `tabla_tiempo_variabilidad.csv`, `tabla_latencia.csv`; costo: constantes de `Diag_HIL` en `configuracion()` | `Nominal_v12` |
| Efecto del monitoreo de TIA Portal | `calcular_resultados_articulo.m`: `tabla_tia_desconectado.csv` | `TIA Desconectado` (versión 2.0.2) |
| Periodo del OB medido en el PLC | `calcular_ob_plc.m` | `OB_PLC` (versión 2.0.2) |
| Variantes del MPC | `calcular_resultados_articulo.m` | `Modelo_v12`, `Nominal_v12`; filas con †: `Modelo_v12/mpc_esc1_v11_flat.mat` y `mpc_1212C` |
| Contraste del solucionador del MPC | `contrastar_qp_cotas_todas.m` | `Nominal_v12/MPC` |
| Horizonte de predicción | `calcular_resultados_articulo.m`: `tabla_horizonte.csv` | `Modelo_v12/mpc_esc1_v12A*` |
| Integrales, escalones, esfuerzo, perturbaciones, comparación y resumen | `calcular_resultados_articulo.m` | `Nominal_v12` |
| Robustez | `calcular_resultados_articulo.m`: `tabla_robustez_ruido.csv` y peor caso por tramo | `Robustez_v12` |
| Fallas C3 a C5 | `calcular_resultados_articulo.m`: `tabla_fallas.csv` | `Fallas_v12` |
| Cortes C1, C2 y con cable | `calcular_resultados_articulo.m`: `tabla_reconexion.csv` | `Reconexion_v12` |
| Condiciones comunes | `calcular_resultados_articulo.m`: `tabla_condiciones_comunes.csv`, `tabla_un_solo_cambio.csv` | `Modelo_v12/*_esc1_v12A_*` |
| Segundo escenario | `calcular_resultados_articulo.m`: `tabla_escenario2.csv`; `eventos_escenario2.m` (eventos) | `Modelo_v12/*_esc2_v12A*` |
| Efecto de la coherencia física del modelo | `comparar_modelos_v12.m` | `Modelo_v12/*_esc1_v11`, `_v12A`, `_v12B`; `Analisis/pid_run22_flat.mat` y `Analisis/fuzzy_run23_flat.mat` |
| Figuras F01 a F04, F06, F07, F08 y F11 | `generar_figuras_articulo_n.m` | `Nominal_v12`, `Reconexion_v12/Cable_wd2` |

La relación completa figura o tabla → registro → script → ventana está en la Tabla S9 del material suplementario.

## 3. Orden para reproducir

1. (Opcional, Simulink) `crear_modelos_v12`, `crear_modelos_comun_v12` y `correr_comparacion_v12` generan `Datos/Modelo_v12/`.
2. `reproducir_replicas_v12` y `verificar_modelo_v12`, con `Modelo/Matlab` en la ruta.
3. `calcular_resultados_articulo`, desde cualquier carpeta: busca `Datos/` en la raíz del repositorio (la carpeta padre de `Analisis/`) y antes de calcular lista los registros que falten. Escribe `Analisis/resultados_v12/*.csv` y `resultados.mat`.
4. `calcular_ob_plc`, con `Datos/OB_PLC/medir_ob_nominal_20261107.csv`.
5. `contrastar_qp_cotas_todas`, en MATLAB con Optimization Toolbox, con `Datos/Nominal_v12/MPC` y `PLC/Simulacion_Trifasico_MPC_v8_M6_caja_S71200.scl`. Su salida es `Analisis/resultados_v12/salida_contrastar_qp_cotas_v12.txt`.
6. `comparar_modelos_v12` para la tabla del efecto del modelo.
7. `generar_figuras_articulo_n`, en MATLAB.

