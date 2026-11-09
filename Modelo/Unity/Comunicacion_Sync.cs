using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Threading;
using UnityEngine;
using Sharp7;
using Debug = UnityEngine.Debug;

// =====================================================================

// =====================================================================
public class Comunicacion_Sync : MonoBehaviour
{
    public string ip = "192.168.0.1";
    [Tooltip("Periodo de sondeo del hilo de comunicacion [ms]")]
    public int periodoSondeoMs = 2;
    [Tooltip("Ts del lazo [s]; se usa solo durante un corte simulado")]
    public float Ts = 0.1f;
    [Tooltip("true: el paso de la planta se calcula en este hilo apenas llega el ciclo del PLC (recomendado)")]
    public bool integrarEnHilo = true;
    [Tooltip("true: si se pierde la lectura de un ciclo del PLC, la planta avanza igual (con la accion anterior)")]
    public bool rellenarSaltados = true;
    [Tooltip("true: medicion, ganancias (si cambian) y Seq_Unity en UNA sola peticion S7. false: dos peticiones, como antes")]
    public bool escrituraUnica = true;
    [HideInInspector] public Separador_Trifasico separador;

    [Header("Desconexion real del cable (pruebas fisicas)")]
    [Tooltip("true: si se cae la conexion S7 (p. ej. se retira el cable Ethernet), la planta sigue con las valvulas retenidas y el hilo se reconecta solo. false: comportamiento anterior")]
    public bool reconectar = true;
    [Tooltip("Tiempo entre intentos de reconexion [ms]")]
    public int intervaloReconexionMs = 200;
    [Tooltip("true: muestra en pantalla la cuenta regresiva para retirar y reponer el cable a mano (usar con Falla = Ninguna)")]
    public bool avisosCorteReal = false;
    public int corteRealInicioCiclo = 4500;       // paso de la planta en que se debe retirar el cable (t = paso*Ts)
    public int corteRealDuracionCiclos = 50;      // 50 ciclos = 5 s

    public enum TipoFalla { Ninguna, PerdidaPaquetes, RetardoExtra, Corte, SesgoSensor, SensorCongelado, Combinada }

    [Header("Inyeccion de fallas de comunicacion (pruebas)")]
    public TipoFalla falla = TipoFalla.Ninguna;
    public int semillaFallas = 1;
    [Range(0f, 0.5f)] public float probPerdidaEscritura = 0.05f; // la medicion no llega al PLC
    [Range(0f, 0.5f)] public float probPerdidaLectura = 0.05f;   // Unity no recibe la accion nueva
    public int retardoExtraMuestras = 2;                          // FIFO sobre la accion de control
    public int corteInicioCiclo = 4500;                           // paso de la planta de inicio (t = paso*Ts)
    public int corteDuracionCiclos = 50;                          // 50 ciclos = 5 s
    public int sensor = 1;                                        // 1 = H_w, 2 = H_o, 3 = P_g
    public float sesgo = 0.01f;                                   // [m] o [psi]
    public int sensorInicioCiclo = 4500;
    public int sensorDuracionCiclos = 100;

    [Header("Diagnostico (solo lectura)")]
    public int contadorPLC;
    public int ciclosRetenidos;
    public int ciclosSaltados;
    public int ciclosEnCorte;
    public float latenciaLazoUltimaMs;
    public bool fallaComPLC;
    public int erroresLectura;
    public int erroresEscritura;
    public string ultimoError = "";
    public bool conectado = true;                 // false mientras el enlace S7 esta caido (cable retirado)
    public int reconexiones;
    public float ultimaDesconexionS;              // duracion de la ultima desconexion [s]

    // ---------------- Interfaz con Separador_Trifasico ----------------
    public struct Ciclo { public int contador, eco; public float cv1, cv2, cv3; public bool sintetico; }
    private readonly ConcurrentQueue<Ciclo> colaCiclos = new ConcurrentQueue<Ciclo>();
    private readonly object candado = new object();
    private byte[] bufferSalida = new byte[DB1Mapa.TAM_IMAGEN];
    private int seqSalida = -1;
    private bool hayEscritura;

    // ---------------- Escritura en una sola peticion (escrituraUnica) ----------------
    private const int ZONA_INI = 0, ZONA_TAM = 76;
    private const int GAN_INI = 88, GAN_TAM = 36;
    private const int SEQ_OFS = 128;
    private readonly byte[] bufSeq = new byte[4];
    private byte[] ultimasGananciasMulti;

    private int EscribirMedicionYSeq(byte[] img, int seq)
    {
        var mv = new S7MultiVar(cliente);
        mv.Add<byte>(S7Consts.S7AreaDB, S7Consts.S7WLByte, DB1Mapa.DB, ZONA_INI, ZONA_TAM, ref img, ZONA_INI);
        bool ganCambio = ultimasGananciasMulti == null;
        if (!ganCambio)
            for (int i = 0; i < GAN_TAM; i++)
                if (img[GAN_INI + i] != ultimasGananciasMulti[i]) { ganCambio = true; break; }
        if (ganCambio)
            mv.Add<byte>(S7Consts.S7AreaDB, S7Consts.S7WLByte, DB1Mapa.DB, GAN_INI, GAN_TAM, ref img, GAN_INI);
        S7.SetDIntAt(bufSeq, 0, seq);
        byte[] bs = bufSeq;
        mv.Add<byte>(S7Consts.S7AreaDB, S7Consts.S7WLByte, DB1Mapa.DB, SEQ_OFS, 4, ref bs, 0);
        int r = mv.Write();
        if (r != 0) return r;
        int n = ganCambio ? 3 : 2;
        for (int i = 0; i < n; i++) if (mv.Results[i] != 0) return mv.Results[i];
        if (ganCambio)
        {
            if (ultimasGananciasMulti == null) ultimasGananciasMulti = new byte[GAN_TAM];
            Buffer.BlockCopy(img, GAN_INI, ultimasGananciasMulti, 0, GAN_TAM);
        }
        return 0;
    }

    // ---------------- Hilo ----------------
    private Thread hilo;
    private volatile bool corriendo;
    private readonly S7Client cliente = new S7Client();
    private readonly Stopwatch reloj = new Stopwatch();
    private System.Random rng;
    private StreamWriter log;
    private string rutaLog;
    private readonly System.Collections.Generic.Dictionary<int, double> tEscritura =
        new System.Collections.Generic.Dictionary<int, double>();
    private readonly System.Collections.Generic.Queue<float[]> fifoCv =
        new System.Collections.Generic.Queue<float[]>();
    private float[] ultimoCv = { 0f, 0f, 0f };
    private float[] ultimoCvPrevio = { 0f, 0f, 0f };
    private int ultimoContador = int.MinValue;
    private byte[] ultimasGanancias;
    private int ciclosDesdeInicio;
    private bool estabaEnCorte;     // tras un corte, el salto del contador no se rellena (la planta ya avanzo)
    private double tUltimoCiclo;
    private volatile bool enlaceActivo = true;
    private int erroresSeguidos;                  // peticiones S7 fallidas consecutivas
    private double tUltimoIntento, tDesconexion, tCorteUltimo, tUltimoPaso;
    private volatile string avisoPantalla = "";
    private GUIStyle estiloAviso;

    void Start()
    {
        rng = new System.Random(semillaFallas);
        string etiqueta = avisosCorteReal ? "CorteReal" : falla.ToString();
        rutaLog = Path.Combine(Application.dataPath, "..",
            "Diag_Com_" + etiqueta + "_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".csv");
        if (cliente.ConnectTo(ip, 0, 1) != 0) { Debug.LogError("Comunicacion_Sync: no se pudo conectar"); return; }
        log = new StreamWriter(rutaLog);
        log.WriteLine("ciclo;contador_plc;eco_seq;t_s;dt_ciclo_ms;lectura_ms;escritura_ms;latencia_lazo_ms;" +
                      "retenido;retardo_muestras;saltados;sintetico;falla_com_plc");
        corriendo = true;
        reloj.Start();
        hilo = new Thread(Bucle) { IsBackground = true, Priority = System.Threading.ThreadPriority.AboveNormal };
        hilo.Start();
    }

    // Llamado por Separador_Trifasico en el hilo principal.
    public bool TomarCiclo(out Ciclo c) { return colaCiclos.TryDequeue(out c); }

    // Llamado por Separador_Trifasico despues de integrar: imagen de 124 bytes (DB1Mapa.Imagen) y numero de ciclo.
    public void Enviar(byte[] imagen124, int seq)
    {
        lock (candado)
        {
            Buffer.BlockCopy(imagen124, 0, bufferSalida, 0, DB1Mapa.TAM_IMAGEN);
            seqSalida = seq;
            hayEscritura = true;
        }
    }

    // Fallas de sensor: se aplican a la medicion antes de enviarla.
    private float[] congelado;
    public void AplicarFallaSensor(int ciclo, ref float pv1, ref float pv2, ref float pv3)
    {
        bool activa = (falla == TipoFalla.SesgoSensor || falla == TipoFalla.SensorCongelado || falla == TipoFalla.Combinada)
                      && ciclo >= sensorInicioCiclo && ciclo < sensorInicioCiclo + sensorDuracionCiclos;
        if (!activa) { congelado = null; return; }
        if (falla == TipoFalla.SensorCongelado || falla == TipoFalla.Combinada)
        {
            if (congelado == null) congelado = new[] { pv1, pv2, pv3 };
            if (sensor == 1) pv1 = congelado[0]; else if (sensor == 2) pv2 = congelado[1]; else pv3 = congelado[2];
        }
        if (falla == TipoFalla.SesgoSensor || falla == TipoFalla.Combinada)
        {
            if (sensor == 1) pv1 += sesgo; else if (sensor == 2) pv2 += sesgo; else pv3 += sesgo;
        }
    }

    private bool EnCorte()
    {
        return (falla == TipoFalla.Corte || falla == TipoFalla.Combinada) &&
               PasoPlanta() >= corteInicioCiclo && PasoPlanta() < corteInicioCiclo + corteDuracionCiclos;
    }

    private int PasoPlanta()
    {
        return separador != null ? separador.num : ciclosDesdeInicio;
    }

    private void Bucle()
    {
        byte[] rd = new byte[DB1Mapa.LECTURA_TAM];   // bytes 76-136
        while (corriendo)
        {
            double ahora = reloj.Elapsed.TotalMilliseconds;
            if (avisosCorteReal) ActualizarAviso();

            // ---------- Reconexion tras una desconexion real (cable retirado) ----------
            bool corteProgramado = EnCorte();
            if (!enlaceActivo && !corteProgramado && reconectar && ahora - tUltimoIntento >= intervaloReconexionMs)
            {
                tUltimoIntento = ahora;
                Reconectar();
                ahora = reloj.Elapsed.TotalMilliseconds;   // el intento pudo bloquear el hilo
            }

            // ---------- Corte (simulado o real): la planta sigue con las valvulas retenidas ----------
            if (corteProgramado || !enlaceActivo)
            {
                if (corteProgramado)
                {
                    if (ahora - tCorteUltimo >= Ts * 1000.0)
                    {
                        tCorteUltimo = ahora;
                        PasoSintetico(ahora);
                    }
                }
                else
                {
                    // Desconexion real: un paso por cada Ts de reloj. Si una peticion S7 bloqueo el hilo
                    // (timeout), se recuperan los pasos que la planta debio dar durante la espera.
                    int n = 0;
                    while (ahora - tCorteUltimo >= Ts * 1000.0 && n < 200)
                    {
                        tCorteUltimo += Ts * 1000.0;
                        PasoSintetico(ahora);
                        n++;
                    }
                }
                Thread.Sleep(periodoSondeoMs);
                continue;
            }
            tCorteUltimo = ahora;

            // ---------- Escritura: zona de Unity (0-75 y 88-123), luego Seq_Unity ----------
            double tEsc = 0.0;
            bool escribir; byte[] copia = new byte[DB1Mapa.TAM_IMAGEN]; int seq;
            lock (candado) { escribir = hayEscritura; Buffer.BlockCopy(bufferSalida, 0, copia, 0, DB1Mapa.TAM_IMAGEN); seq = seqSalida; hayEscritura = false; }
            if (escribir)
            {
                bool perder = (falla == TipoFalla.PerdidaPaquetes || falla == TipoFalla.Combinada) &&
                              rng.NextDouble() < probPerdidaEscritura;
                if (!perder)
                {
                    double t0 = reloj.Elapsed.TotalMilliseconds;
                    int r1, r2 = 0;
                    if (escrituraUnica) r1 = EscribirMedicionYSeq(copia, seq);   // una peticion; nunca toca Cv_
                    else
                    {
                        r1 = DB1Mapa.EscribirZonaUnity(cliente, copia, ref ultimasGanancias);  // nunca toca Cv_
                        r2 = DB1Mapa.EscribirSeq(cliente, seq);           // Seq despues de la medicion
                    }
                    tEsc = reloj.Elapsed.TotalMilliseconds - t0;
                    if (r1 == 0 && r2 == 0) lock (tEscritura) tEscritura[seq] = reloj.Elapsed.TotalMilliseconds;
                    else ReportarError("escritura", r1 != 0 ? r1 : r2, ref erroresEscritura);
                }
            }

            // ---------- Lectura de la accion de control y del contador ----------
            double tl0 = reloj.Elapsed.TotalMilliseconds;
            int rr = cliente.DBRead(DB1Mapa.DB, DB1Mapa.LECTURA_INI, rd.Length, rd);
            double tLec = reloj.Elapsed.TotalMilliseconds - tl0;
            if (rr != 0) ReportarError("lectura", rr, ref erroresLectura);
            if (rr == 0)
            {
                erroresSeguidos = 0;
                int contador = S7.GetDIntAt(rd, DB1Mapa.CONTADOR_PLC - DB1Mapa.LECTURA_INI);
                int eco = S7.GetDIntAt(rd, DB1Mapa.ECO_SEQ - DB1Mapa.LECTURA_INI);
                fallaComPLC = S7.GetBitAt(rd, DB1Mapa.FALLA_COM - DB1Mapa.LECTURA_INI, 0);
                if (contador != ultimoContador)
                {
                    int saltados = (ultimoContador == int.MinValue) ? 0 : Math.Max(0, contador - ultimoContador - 1);
                    if (estabaEnCorte) { saltados = 0; estabaEnCorte = false; }   // ciclos ya simulados durante el corte
                    int o = DB1Mapa.CV_ - DB1Mapa.LECTURA_INI;
                    float[] cv = { S7.GetRealAt(rd, o), S7.GetRealAt(rd, o + 4), S7.GetRealAt(rd, o + 8) };

                    if ((falla == TipoFalla.PerdidaPaquetes || falla == TipoFalla.Combinada) &&
                        rng.NextDouble() < probPerdidaLectura)
                        cv = (float[])ultimoCv.Clone();                   // accion nueva perdida
                    if (falla == TipoFalla.RetardoExtra || falla == TipoFalla.Combinada)
                    {
                        fifoCv.Enqueue(cv);
                        cv = fifoCv.Count > retardoExtraMuestras ? fifoCv.Dequeue() : (float[])ultimoCv.Clone();
                    }

                    double lat = double.NaN;
                    lock (tEscritura)
                        if (tEscritura.TryGetValue(eco, out double tw)) { lat = reloj.Elapsed.TotalMilliseconds - tw; tEscritura.Remove(eco); }
                    // Lo ideal es que el PLC haya calculado con la medicion del ciclo anterior.
                    int retardo = (contador - 1) - eco;                  // muestras de atraso de la medicion
                    int retenido = (ultimoContador != int.MinValue && retardo != 0) ? 1 : 0;
                    lock (tEscritura)
                    {
                        var viejas = new System.Collections.Generic.List<int>();
                        foreach (var k in tEscritura.Keys) if (k < eco - 50) viejas.Add(k);
                        foreach (var k in viejas) tEscritura.Remove(k);
                    }

                    ultimoCv = cv;
                    ultimoContador = contador;
                    ciclosDesdeInicio++;
                    tUltimoPaso = reloj.Elapsed.TotalMilliseconds;
                    contadorPLC = contador;
                    ciclosRetenidos += retenido;
                    ciclosSaltados += saltados;
                    if (!double.IsNaN(lat)) latenciaLazoUltimaMs = (float)lat;

                    float[] cvAnterior = ultimoCvPrevio;
                    ultimoCvPrevio = cv;
                    var nuevo = new Ciclo { contador = contador, eco = eco, cv1 = cv[0], cv2 = cv[1], cv3 = cv[2] };
                    double tEscHilo = 0.0;
                    if (integrarEnHilo && separador != null)
                    {
                        // Ciclos que no se alcanzaron a leer: la planta avanza con la accion anterior.
                        byte[] img = null;
                        if (rellenarSaltados)
                            for (int k = 0; k < saltados && k < 50; k++)
                                img = separador.PasoDesdeHilo(new Ciclo
                                {
                                    contador = contador,
                                    eco = eco,
                                    cv1 = cvAnterior[0],
                                    cv2 = cvAnterior[1],
                                    cv3 = cvAnterior[2],
                                    sintetico = true
                                }) ?? img;
                        byte[] imgN = separador.PasoDesdeHilo(nuevo);
                        if (imgN != null) img = imgN;
                        if (img != null && !((falla == TipoFalla.PerdidaPaquetes || falla == TipoFalla.Combinada) &&
                                             rng.NextDouble() < probPerdidaEscritura))
                        {
                            double t0 = reloj.Elapsed.TotalMilliseconds;
                            int w1, w2 = 0;
                            if (escrituraUnica) w1 = EscribirMedicionYSeq(img, contador);   // una peticion
                            else
                            {
                                w1 = DB1Mapa.EscribirZonaUnity(cliente, img, ref ultimasGanancias);
                                w2 = DB1Mapa.EscribirSeq(cliente, contador);
                            }
                            tEscHilo = reloj.Elapsed.TotalMilliseconds - t0;
                            if (w1 == 0 && w2 == 0) lock (tEscritura) tEscritura[contador] = reloj.Elapsed.TotalMilliseconds;
                            else ReportarError("escritura", w1 != 0 ? w1 : w2, ref erroresEscritura);
                        }
                    }
                    else
                    {
                        if (rellenarSaltados)
                            for (int k = 0; k < saltados && k < 50; k++)
                                colaCiclos.Enqueue(new Ciclo
                                {
                                    contador = contador,
                                    eco = eco,
                                    cv1 = cvAnterior[0],
                                    cv2 = cvAnterior[1],
                                    cv3 = cvAnterior[2],
                                    sintetico = true
                                });
                        colaCiclos.Enqueue(nuevo);
                    }
                    double tc = reloj.Elapsed.TotalMilliseconds;
                    Registrar(ciclosDesdeInicio, contador, eco, tc, tc - tUltimoCiclo, tLec, tEsc + tEscHilo, lat, retenido, saltados, false, retardo);
                    tUltimoCiclo = tc;
                }
            }
            Thread.Sleep(periodoSondeoMs);
        }
    }

    // Errores S7: se informan en la consola de Unity (el primero y luego uno de cada 100).
    private void ReportarError(string que, int codigo, ref int contador)
    {
        contador++;
        ultimoError = que + ": " + cliente.ErrorText(codigo);
        if (contador == 1 || contador % 100 == 0)
            Debug.LogError("Comunicacion_Sync, error de " + ultimoError + " (" + contador + " veces)");
        erroresSeguidos++;
        if (reconectar && enlaceActivo && erroresSeguidos >= 2) MarcarDesconexion();
    }

    // Enlace S7 caido: la planta sigue con las valvulas retenidas y se reintenta la conexion.
    private void MarcarDesconexion()
    {
        enlaceActivo = false;
        conectado = false;
        tDesconexion = reloj.Elapsed.TotalMilliseconds;
        tUltimoIntento = tDesconexion;
        tCorteUltimo = tUltimoPaso;               // la planta sigue desde el ultimo paso dado (incluye el tiempo bloqueado por el timeout)
        Debug.LogWarning("Comunicacion_Sync: enlace S7 perdido (" + ultimoError +
                         "). La planta sigue con las valvulas retenidas y se intentara reconectar.");
    }

    private bool Reconectar()
    {
        try { cliente.Disconnect(); } catch (Exception) { }
        int r = cliente.ConnectTo(ip, 0, 1);
        if (r != 0) { ultimoError = "reconexion: " + cliente.ErrorText(r); return false; }
        reconexiones++;
        ultimaDesconexionS = (float)((reloj.Elapsed.TotalMilliseconds - tDesconexion) / 1000.0);
        ultimasGananciasMulti = null;             // la proxima escritura vuelve a enviar las ganancias
        ultimasGanancias = null;
        erroresSeguidos = 0;
        enlaceActivo = true;
        conectado = true;
        Debug.Log("Comunicacion_Sync: enlace S7 restablecido tras " + ultimaDesconexionS.ToString("F1") + " s");
        return true;
    }

    // Un ciclo del PLC que Unity no puede leer: la planta avanza con la ultima accion recibida.
    private void PasoSintetico(double ahora)
    {
        estabaEnCorte = true;
        ciclosEnCorte++;
        ciclosDesdeInicio++;
        var cs = new Ciclo
        {
            contador = ultimoContador,
            eco = -1,
            cv1 = ultimoCv[0],
            cv2 = ultimoCv[1],
            cv3 = ultimoCv[2],
            sintetico = true
        };
        if (integrarEnHilo && separador != null) separador.PasoDesdeHilo(cs);   // sin escribir: corte
        else colaCiclos.Enqueue(cs);
        Registrar(ciclosDesdeInicio, ultimoContador, -1, ahora, 0, 0, 0, double.NaN, 0, 0, true, 0);
    }

    // Cuenta regresiva en pantalla para retirar y reponer el cable a mano.
    private void ActualizarAviso()
    {
        int p = PasoPlanta();
        int ini = corteRealInicioCiclo, fin = corteRealInicioCiclo + corteRealDuracionCiclos;
        string a = "";
        if (p >= ini - 100 && p < ini)
            a = "Retire el cable en " + Math.Ceiling((ini - p) * Ts).ToString("F0") + " s";
        else if (p >= ini && p < ini + 10)
            a = "RETIRE EL CABLE AHORA";
        else if (p >= ini + 10 && p < fin)
            a = "Cable fuera. Reponer en " + Math.Ceiling((fin - p) * Ts).ToString("F0") + " s";
        else if (p >= fin && p < fin + 20)
            a = "REPONGA EL CABLE AHORA";
        avisoPantalla = a;
    }

    void OnGUI()
    {
        string a = avisoPantalla;
        if (!avisosCorteReal || string.IsNullOrEmpty(a)) return;
        if (estiloAviso == null)
        {
            estiloAviso = new GUIStyle(GUI.skin.label) { fontSize = 44, fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperLeft };
            estiloAviso.normal.textColor = Color.red;
        }
        GUI.Label(new Rect(24, 24, Screen.width - 48, 90), a, estiloAviso);
    }

    private void Registrar(int ciclo, int contador, int eco, double tms, double dt, double lec, double esc,
                           double lat, int ret, int salt, bool sint, int retardo)
    {
        if (log == null) return;
        log.WriteLine(string.Join(";", ciclo, contador, eco, (tms / 1000.0).ToString("F4"), dt.ToString("F3"),
            lec.ToString("F3"), esc.ToString("F3"), double.IsNaN(lat) ? "" : lat.ToString("F3"),
            ret, retardo, salt, sint ? 1 : 0, fallaComPLC ? 1 : 0));
    }

    void OnApplicationQuit() { Detener(); }
    void OnDestroy() { Detener(); }

    private void Detener()
    {
        corriendo = false;
        if (hilo != null && hilo.IsAlive) hilo.Join(500);
        if (log != null) { log.Flush(); log.Close(); log = null; }
        cliente.Disconnect();
    }
}
