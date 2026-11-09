using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices.ComTypes;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using System.IO;
using System.Globalization;
using System.Threading;
using Sharp7;

public class Separador_Trifasico : MonoBehaviour
{
    public bool ready;
    public bool escalones;
    public int val_esc;
    public int num;
    string estadoText;

    //%***** MODELO *****%

    // 0) TIEMPO DE SIMULACIÓN
    // ==========================================================
    [Header("Tiempo de simulación")]
    public bool runSimulation = true;
    public float Ts = 0.1f;

    [Header("Temporización del lazo HIL")]
    [Tooltip("Pasos del modelo que se pueden recuperar en un mismo cuadro si Unity se atrasó")]
    public int maxPasosPorCuadro = 5;
    [Tooltip("No integrar ni registrar hasta que el PLC entregue su primera acción de control")]
    public bool esperarPrimerCV = true;

    [Header("Sincronización con el ciclo del PLC")]
    [Tooltip("true: la planta avanza un Ts por cada ciclo nuevo del PLC (requiere Comunicacion_Sync)")]
    public bool sincronizarConPLC = false;
    public Comunicacion_Sync com;
    private float tSinCiclo;          // tiempo sin ciclos nuevos del PLC (modo sincronizado)
    private volatile int ultimoSeqEnviado = -1;

    private readonly object candadoPlanta = new object();
    private int hiloPrincipalId;
    private volatile bool activoHilo;
    private volatile int pasosHilo;
    private int pasosHiloVistos;
    private volatile bool slidersPendientes;
    private readonly float[] sliderPend = new float[6];
    private volatile bool salirPendiente;
    private bool enHilo;
    private volatile bool escenarioTerminado;   // fin de la última repetición: la planta se detiene

    // ----------------------------------------------------------
    [Header("Repeticiones del escenario de pruebas")]
    public bool repetirEscenario = false;
    [Range(1, 30)] public int numeroRepeticiones = 10;
    public float pausaEntreRepeticiones_s = 3.0f;
    public bool registroPorRepeticion = true;         // Datos_<CTRL>_rep<NN>_<fecha>.txt
    [Tooltip("Registro propio Datos_<CTRL>_<fecha>.txt aunque no haya repeticiones (necesario en modo hilo)")]
    public bool registroPropio = true;
    public bool nuevaSemillaPorRepeticion = true;     // robustez: semilla + (rep - 1)
    [Header("Repeticiones / solo lectura")]
    public int repeticionActual = 1;
    public bool enPausa;
    private float tPausa;
    private bool actGuardada, actPIDGuardada, actMPCGuardada, actFuzzyGuardada;
    private StreamWriter registroRep;
    private bool abrirRegistroPendiente;
    private string sufijoRegistro = "";
    private string rutaProyecto = ".";
    private string etiquetaCtrl = "CTRL";

    // ----------------------------------------------------------
    [Header("Robustez: activación y semilla")]
    public bool aplicarRobustez = false;
    public int semilla = 1;                              // misma semilla = misma secuencia

    [Header("Robustez: variación de parámetros por escalón")]
    public int[] escalonesValvulas = { 4, 8 };
    public int[] escalonesDensidades = { 6 };
    [Range(0f, 0.5f)] public float varKv = 0.10f;       // ±10 % en kvw, kvc, kvg
    [Range(0f, 0.2f)] public float varRho = 0.05f;      // ±5 % en rho_o, rho_w (y SG)
    public bool volverANominal = true;

    [Header("Robustez: ruido por escalón")]
    public int[] escalonesRuidoEstado = { };
    public float ampHw = 0.005f;                         // [m]
    public float ampHb = 0.005f;                         // [m]
    public float ampPg_psi = 0.05f;                      // [psi]
    public int[] escalonesRuidoMedicion = { 5, 9 };
    public float ampMedHw = 0.005f;                      // [m]
    public float ampMedHb = 0.005f;                      // [m]
    public float ampMedPg_psi = 0.05f;                   // [psi]

    [Header("Robustez / tramo vigente (solo lectura)")]
    public int escalonVigente;                           // 0 = tramo inicial
    public bool tramoValvulas, tramoDensidades, tramoRuidoEstado, tramoRuidoMedicion;
    [Header("Robustez / factores vigentes (solo lectura)")]
    public float fKvw = 1f, fKvc = 1f, fKvg = 1f, fRhoc = 1f, fRhow = 1f;
    private System.Random rngParam;                      // factores de parámetros
    private System.Random rngRuido;                      // ruido por paso (secuencia independiente)
    private string rutaRobustez;
    private float nMed1, nMed2, nMed3;

    public enum MetodoIntegracion { Euler, RK4 }

    [Header("Integración de la planta")]
    public MetodoIntegracion integrador = MetodoIntegracion.RK4;
    [Tooltip("Subpasos por periodo Ts cuando se usa Euler")]
    public int subpasosEuler = 10;

    [Header("Diagnóstico de temporización / solo lectura")]
    public double tiempoReal;          // [s] reloj de pared desde el primer paso válido
    public float periodoRealUltimo;    // [s] tiempo real entre los dos últimos pasos
    public int pasosEnEsteCuadro;      // pasos del modelo ejecutados en el último cuadro
    public int pasosDescartados;       // pasos perdidos por congelamientos de Unity
    public bool cvValida;              // el PLC ya entregó su primera acción de control

    // ==========================================================
    // 1) CONDICIONES INICIALES
    // ==========================================================
    [Header("Estado inicial")]
    public float hc0 = 0.4737f;    // [m]
    public float hw0 = 0.80f;      // [m]
    public float hb0 = 0.72f;      // [m]
    public float pg0_psi = 37.0f;  // [psi]

    [Header("Aperturas iniciales")]
    public float vpw0 = 0.6846f;
    public float vpc0 = 0.2532f;
    public float vpg0 = 0.4889f;

    // ==========================================================
    // 2) ENTRADAS DEL MODELO
    // ==========================================================
    [Header("Perturbaciones / caudales de entrada")]
    public float qwi = 0.1374f;    // [m^3/s]
    public float qci = 0.0711f;    // [m^3/s]
    public float qgi = 0.4906f;    // [m^3/s]

    [Header("Válvulas 0 a 1")]
    //[Range(0f, 1f)] public float vpw = 0.6846f;
    //[Range(0f, 1f)] public float vpc = 0.2532f;
    //[Range(0f, 1f)] public float vpg = 0.4889f;

    [Range(0f, 1f)] public float vpw = 0.6561f;
    [Range(0f, 1f)] public float vpc = 0.2379f;
    [Range(0f, 1f)] public float vpg = 0.4743f;

    //[Range(0f, 1f)] public float vpw = 0.47f;
    //[Range(0f, 1f)] public float vpc = 0.14f;
    //[Range(0f, 1f)] public float vpg = 0.85f;

    // ==========================================================
    // 3) SALIDAS VISIBLES EN INSPECTOR
    // ==========================================================
    [Header("Estado integrado")]
    public double simulationTime;
    public float hw;
    public float hc;
    public float hb;
    public float pg_Pa;
    public float pg_psi;

    [Header("Derivadas dx / solo lectura")]
    public float dhw;
    public float dhc;
    public float dhb;
    public float dpg;

    [Header("Salidas data / solo lectura")]
    public float qwo;
    public float qca;
    public float qcb;
    public float qgo;
    public float va;
    public float vb;
    public float ha;

    // ==========================================================
    // 4) CONSTANTES DEL MODELO TPgsep_v11
    // ==========================================================
    private const float PSI_TO_PA = 6894.757f;
    private const float PA_TO_PSI = 1.0f / PSI_TO_PA;

    private const float MT_TO_FT = 3.28084f;
    private const float FT_TO_MT = 1.0f / MT_TO_FT;

    private const float ds = 3.048f;       // Diámetro [m]
    private const float La = 15.1724f;     // Longitud separador [m]
    private const float Lb = 3.1076f;      // Longitud colector [m]
    private const float hs = 1.2192f;      // Altura barrera [m]

    private const float kvw_nom = 5.15e-4f;  // Coef. válvula agua (nominal)
    private float kvw = kvw_nom;
    private const float poa = 101325.0f;   // Presión salida agua [Pa]
    private const float kvc_nom = 7.15e-4f;  // Coef. válvula crudo (nominal)
    private float kvc = kvc_nom;
    private const float pob = 101325.0f;   // Presión salida crudo [Pa]
    private const float kvg_nom = 80.0f;  // Coef. válvula gas [gpm/psi^0.5] (nominal)
    private float kvg = kvg_nom;
    private const float poc = 101325.0f;   // Presión salida gas [Pa]

    private const float rhoc_nom = 802.525f;  // Densidad crudo [kg/m3] (nominal)
    private float rhoc = rhoc_nom;
    private const float sgc_nom = 0.9134f;  // Gravedad específica crudo (nominal)
    private float sgc = sgc_nom;
    private const float rhow_nom = 997.8f;  // Densidad agua [kg/m3] (nominal)
    private float rhow = rhow_nom;
    private const float sgw_nom = 1.00f;  // Gravedad específica agua (nominal)
    private float sgw = sgw_nom;
    private const float mgas = 28.04f;     // Peso molecular gas [g/mol]
    private const float mair = 28.96f;     // Peso molecular aire [g/mol]
    private const float g = 9.81f;         // Gravedad [m/s2]
    private const float T = 355.37f;       // Temperatura [K]

    // ==========================================================
    // 6) VARIABLES INTERNAS (double para no acumular redondeo)
    // ==========================================================
    private double x_hw;
    private double x_hc;
    private double x_pg;
    private double x_hb;

    //%//%Control Nivel y Presion
    public float hws = 0.85f;
    public float hbs = 0.72f;
    public float pgs = 35.0f;

    //%***************************************************************************************************************%

    [Header("Valores maximos")]
    // Limites
    public float maxhw;
    public float maxhc;
    public float maxhb;
    public float maxPg;
    public float maxT;

    float lectura1, lectura2, lectura3;

    float To;
    float tHMI;
    float kp1, ti1, td1, kp2, ti2, td2, kp3, ti3, td3;

    private readonly System.Diagnostics.Stopwatch reloj = new System.Diagnostics.Stopwatch();
    private double tRealAnterior;

    [Header("HMI")]
    //%***************************************************************************************************************%
    public TextMeshProUGUI LIT1;
    public TextMeshProUGUI LIT2;
    public TextMeshProUGUI PIT1;
    public TextMeshProUGUI TIT1;
    public TextMeshProUGUI cLIT1, cLIT2, cPIT1, cTIT1;

    public AudioSource sound_proceso, sound_explosion;
    public AudioClip aproceso, abexplosion;
    int n = 0, l = 0;

    public Slider slider_qwi, slider_qci, slider_qgi;
    public Slider slider_hws, sliderkp1, sliderti1, slidertd1;
    public Slider slider_hbs, sliderkp2, sliderti2, slidertd2;
    public Slider slider_pgs, sliderkp3, sliderti3, slidertd3;

    public TextMeshProUGUI THws, THw, Tvpw, Tkp1, Tti1, Ttd1;
    public TextMeshProUGUI THbs, THb, Tvpc, Tkp2, Tti2, Ttd2;
    public TextMeshProUGUI TPgs, TPg, Tvpg, Tkp3, Tti3, Ttd3;
    public TextMeshProUGUI TQwi, TQci, TQgi;
    public TextMeshProUGUI Title1, Title2, Title3;

    public GameObject agua, explosion;

    public Transform vpwTR, vpcTR, vpgTR;

    public Material liquidA, liquidP;
    public GameObject[] sliders;
    public GameObject[] gas;

    public float acv1, acv2, acv3, apv1, apv2, apv3;

    Datos datos;
    Escribir_Texto escribir_Texto;

    // Estructura local equivalente a data y dx de MATLAB (en double)
    private struct ModeloResult
    {
        public double dhc;
        public double dhw;
        public double dhb;
        public double dpg;
        public double qwo;
        public double qca;
        public double qcb;
        public double qgo;
        public double va;
        public double vb;
        public double ha;
    }

    void Start()
    {
        datos = FindObjectOfType<Datos>();

        hiloPrincipalId = Thread.CurrentThread.ManagedThreadId;
        rutaProyecto = Path.Combine(Application.dataPath, "..");
        Application.runInBackground = true;       // no se detiene al pasar a TIA Portal
        QualitySettings.vSyncCount = 0;           // cuadros sin esperar al monitor
        Application.targetFrameRate = 200;
        if (com != null) com.separador = this;

        IniciarAleatorios(semilla);
        RestablecerParametros();
        repeticionActual = 1;
        enPausa = false;
        AbrirRegistrosRepeticion();
        ConfigurarTramo(0);
        escribir_Texto = FindObjectOfType<Escribir_Texto>();

        x_hc = hc0;
        x_hw = hw0;
        x_hb = hb0;
        x_pg = pg0_psi * (double)PSI_TO_PA;

        vpw = vpw0;
        vpc = vpc0;
        vpg = vpg0;

        simulationTime = 0.0;
        To = 0f;
        cvValida = false;
        reloj.Reset();

        PublicarSalidas(ModeloSeparador());
        ActualizarTexto();
        print(estadoText);

        datos.sp1 = hws;
        datos.sp2 = hbs;
        datos.sp3 = pgs;

        datos.pv1 = hw;
        datos.pv2 = hb;
        datos.pv3 = pg_psi;

        slider_hws.value = hws * MT_TO_FT;
        slider_hbs.value = hbs * MT_TO_FT;
        slider_pgs.value = pgs;

        slider_qwi.value = (float)qwi;
        slider_qci.value = (float)qci;
        slider_qgi.value = (float)qgi;

        ////%% Agua
        //kp1 = 9.25f;
        //ti1 = 2.79f;
        //td1 = 0.00005f;
        ////%% Petroleo
        //kp2 = 9.25f;
        //ti2 = 2.95f;
        //td2 = 0.00005f;
        ////%% Gas
        //kp3 = 2.70f;
        //ti3 = 2.10f;
        //td3 = 0.00005f;

        //%% Agua
        kp1 = 16.44f;
        ti1 = 7.821f;
        td1 = 0.00000f;
        //%% Petroleo
        kp2 = 4.388f;
        ti2 = 2.702f;
        td2 = 0.00000f;
        //%% Gas
        kp3 = 2.673f;
        ti3 = 1.050f;
        td3 = 0.00000f;

        sliderkp1.value = kp1;
        sliderti1.value = ti1;
        slidertd1.value = td1;
        sliderkp2.value = kp2;
        sliderti2.value = ti2;
        slidertd2.value = td2;
        sliderkp3.value = kp3;
        sliderti3.value = ti3;
        slidertd3.value = td3;
    }

    // ==========================================================
    // INTEGRACIÓN DE UN PERIODO Ts (válvulas retenidas, ZOH)
    // ==========================================================
    public void SimularUnPaso()
    {
        // 1) Limitar entradas.
        vpw = Saturar(vpw, 0.0f, 1.0f);
        vpc = Saturar(vpc, 0.0f, 1.0f);
        vpg = Saturar(vpg, 0.0f, 1.0f);

        // 2) Integrar la planta durante Ts.
        if (integrador == MetodoIntegracion.RK4)
        {
            IntegrarRK4(Ts);
        }
        else
        {
            int nSub = Math.Max(subpasosEuler, 1);
            double h = Ts / (double)nSub;
            for (int i = 0; i < nSub; i++)
            {
                IntegrarEuler(h);
            }
        }

        simulationTime += Ts;

        // 3) Derivadas y salidas evaluadas en el estado final.
        ModeloResult r = ModeloSeparador();
        dhc = (float)r.dhc;
        dhw = (float)r.dhw;
        dhb = (float)r.dhb;
        dpg = (float)r.dpg;

        // 4) Publicar salidas.
        PublicarSalidas(r);
    }

    private void IntegrarEuler(double h)
    {
        ModeloResult k1 = ModeloSeparador();
        x_hc += k1.dhc * h;
        x_hw += k1.dhw * h;
        x_hb += k1.dhb * h;
        x_pg += k1.dpg * h;
        LimitarEstados();
    }

    private void IntegrarRK4(double h)
    {
        double c0 = x_hc, w0 = x_hw, b0 = x_hb, p0 = x_pg;

        ModeloResult k1 = ModeloSeparador(c0, w0, b0, p0);
        ModeloResult k2 = ModeloSeparador(c0 + 0.5 * h * k1.dhc, w0 + 0.5 * h * k1.dhw,
                                          b0 + 0.5 * h * k1.dhb, p0 + 0.5 * h * k1.dpg);
        ModeloResult k3 = ModeloSeparador(c0 + 0.5 * h * k2.dhc, w0 + 0.5 * h * k2.dhw,
                                          b0 + 0.5 * h * k2.dhb, p0 + 0.5 * h * k2.dpg);
        ModeloResult k4 = ModeloSeparador(c0 + h * k3.dhc, w0 + h * k3.dhw,
                                          b0 + h * k3.dhb, p0 + h * k3.dpg);

        x_hc = c0 + h / 6.0 * (k1.dhc + 2.0 * k2.dhc + 2.0 * k3.dhc + k4.dhc);
        x_hw = w0 + h / 6.0 * (k1.dhw + 2.0 * k2.dhw + 2.0 * k3.dhw + k4.dhw);
        x_hb = b0 + h / 6.0 * (k1.dhb + 2.0 * k2.dhb + 2.0 * k3.dhb + k4.dhb);
        x_pg = p0 + h / 6.0 * (k1.dpg + 2.0 * k2.dpg + 2.0 * k3.dpg + k4.dpg);

        LimitarEstados();
    }

    private void PublicarSalidas(ModeloResult r)
    {
        hc = (float)x_hc;
        hw = (float)x_hw;
        hb = (float)x_hb;
        pg_Pa = (float)x_pg;
        pg_psi = (float)(x_pg * PA_TO_PSI);

        qwo = (float)r.qwo;
        qca = (float)r.qca;
        qcb = (float)r.qcb;
        qgo = (float)r.qgo;
        va = (float)r.va;
        vb = (float)r.vb;
        ha = (float)r.ha;
    }

    // ==========================================================
    // BUCLE PRINCIPAL
    // ==========================================================
    void Update()
    {
        // Tareas pedidas desde el hilo de comunicación (la interfaz solo se toca aquí).
        if (slidersPendientes)
        {
            slidersPendientes = false;
            slider_hws.value = sliderPend[0]; slider_hbs.value = sliderPend[1]; slider_pgs.value = sliderPend[2];
            slider_qwi.value = sliderPend[3]; slider_qci.value = sliderPend[4]; slider_qgi.value = sliderPend[5];
        }
        if (salirPendiente) { salirPendiente = false; Application.Quit(); }

        // Pausa entre repeticiones: controlador desactivado mientras corre el temporizador.
        if (enPausa)
        {
            tPausa += Time.deltaTime;
            if (tPausa >= pausaEntreRepeticiones_s) TerminarPausa();
        }

        bool activo = (datos.Activation == true) &&
                      (datos.Activation_MPC == true || datos.Activation_PID == true || datos.Activation_FUZZY == true);

        bool modoHilo = activo && sincronizarConPLC && com != null && com.integrarEnHilo;
        activoHilo = modoHilo && !enPausa;

        if (modoHilo)
        {
            // La planta avanza en el hilo de comunicación (PasoDesdeHilo).
            ready = true;
            int p = pasosHilo;
            pasosEnEsteCuadro = p - pasosHiloVistos;
            pasosHiloVistos = p;
            // Mientras no llegan ciclos (arranque), reenviar los bits de activación.
            if (pasosEnEsteCuadro > 0) tSinCiclo = 0f;
            else
            {
                tSinCiclo += Time.deltaTime;
                if (tSinCiclo >= 0.2f)
                {
                    lock (candadoPlanta) com.Enviar(ConstruirBufferSalida(), ultimoSeqEnviado);
                    tSinCiclo = 0f;
                }
            }
        }
        else if (activo && sincronizarConPLC && com != null)
        {
            // La planta avanza exactamente un Ts por cada ciclo nuevo del PLC.
            ready = true;
            int pasosSync = 0;
            Comunicacion_Sync.Ciclo c;
            while (com.TomarCiclo(out c))
            {
                datos.cv1v = c.cv1;
                datos.cv2v = c.cv2;
                datos.cv3v = c.cv3;
                PasoDeControl();
                com.Enviar(ConstruirBufferSalida(), c.contador);
                ultimoSeqEnviado = c.contador;
                pasosSync++;
            }
            pasosEnEsteCuadro = pasosSync;

            if (pasosSync > 0) tSinCiclo = 0f;
            else
            {
                tSinCiclo += Time.deltaTime;
                if (tSinCiclo >= 0.2f)
                {
                    com.Enviar(ConstruirBufferSalida(), ultimoSeqEnviado);
                    tSinCiclo = 0f;
                }
            }
        }
        else if (activo)
        {
            ready = true;
            To += Time.deltaTime;

            int pasos = 0;
            while (To >= Ts && pasos < maxPasosPorCuadro)
            {
                To -= Ts;
                PasoDeControl();
                pasos++;
            }

            if (To >= Ts)
            {
                pasosDescartados += (int)(To / Ts);
                To = To % Ts;
            }
            pasosEnEsteCuadro = pasos;
        }
        else
        {
            ready = false;
            To = 0f;
            cvValida = false;
            if (sincronizarConPLC && com != null)
            {
                Comunicacion_Sync.Ciclo c;
                while (com.TomarCiclo(out c)) { }            // descarta ciclos previos a la activación
                com.Enviar(ConstruirBufferSalida(), -1);      // envía bits de activación y referencias
            }
        }

        if (datos.Activation_MPC == true)
        {
            Title1.text = "MPC CONTROL TRENDS";
            Title2.text = "MPC CONTROL TRENDS";
            Title3.text = "MPC CONTROL TRENDS";

            for (int k = 0; k < 18; k++)
            {
                sliders[k].SetActive(false);
            }
        }
        if (datos.Activation_PID == true)
        {
            Title1.text = "PID CONTROL TRENDS";
            Title2.text = "PID CONTROL TRENDS";
            Title3.text = "PID CONTROL TRENDS";
            for (int k = 0; k < 18; k++)
            {
                sliders[k].SetActive(true);
            }
        }
        else if (datos.Activation_FUZZY == true)
        {
            Title1.text = "FUZZY CONTROL TRENDS";
            Title2.text = "FUZZY CONTROL TRENDS";
            Title3.text = "FUZZY CONTROL TRENDS";
            for (int k = 0; k < 18; k++)
            {
                sliders[k].SetActive(false);
            }
        }

        datos.sp1 = hws;
        datos.sp2 = hbs;
        datos.sp3 = pgs;

        datos.kp1 = kp1;
        datos.ti1 = ti1;
        datos.td1 = td1;
        datos.kp2 = kp2;
        datos.ti2 = ti2;
        datos.td2 = td2;
        datos.kp3 = kp3;
        datos.ti3 = ti3;
        datos.td3 = td3;

        datos.qwi = qwi;
        datos.qci = qci;
        datos.qgi = qgi;

        hws = slider_hws.value * FT_TO_MT;
        hbs = slider_hbs.value * FT_TO_MT;
        pgs = slider_pgs.value;
        kp1 = sliderkp1.value;
        ti1 = sliderti1.value;
        td1 = slidertd1.value;
        kp2 = sliderkp2.value;
        ti2 = sliderti2.value;
        td2 = slidertd2.value;
        kp3 = sliderkp3.value;
        ti3 = sliderti3.value;
        td3 = slidertd3.value;
        qwi = slider_qwi.value;
        qci = slider_qci.value;
        qgi = slider_qgi.value;

        tHMI += Time.deltaTime;
        if (tHMI >= 0.1f)
        {
            tHMI = 0f;
            ActualizarTextosHMI();
        }

        liquidA.SetFloat("_FillAmount", Mathf.Lerp(-2.683f, 1.2f, ((hw - 0.00f) / maxhw)));
        liquidP.SetFloat("_FillAmount", Mathf.Lerp(-2.683f, 1.2f, ((hb - 0.00f) / maxhb)));

        vpwTR.transform.localPosition = new Vector3(0f, Mathf.Lerp(0f, 0.0207f, vpw), 0f);
        vpcTR.transform.localPosition = new Vector3(0f, Mathf.Lerp(0f, 0.0207f, vpc), 0f);
        vpgTR.transform.localPosition = new Vector3(0f, Mathf.Lerp(0.5579f, 0.499f, vpg), 0f);

        for (int k = 0; k < 6; k++)
        {
            gas[k].transform.localPosition = new Vector3(gas[k].transform.localPosition.x, Mathf.Lerp(1.41f, 1.9f, (hb * 1) / maxhb), gas[k].transform.localPosition.z);
        }

        if (hw >= 0.11f)
        {
            agua.SetActive(true);
            if (!sound_proceso.isPlaying)
            {
                sound_proceso.clip = aproceso;
                sound_proceso.loop = true;
                sound_proceso.Play();
            }
        }
        else
        {
            if (sound_proceso.isPlaying) sound_proceso.Stop();
            agua.SetActive(false);
        }

        if (Input.GetKeyDown(KeyCode.E))
        {
            l++;
        }
        if (l == 0)
        {
            explosion.SetActive(false);
        }
        if (l == 1)
        {
            explosion.SetActive(true);
        }
        if (l == 2)
        {
            l = 0;
        }
    }

    // ==========================================================
    // UN PASO DEL LAZO HIL (se ejecuta exactamente cada Ts)
    // ==========================================================
    private void PasoDeControl()
    {
        if (enPausa || escenarioTerminado) return;     // pausa entre repeticiones o fin del escenario

        // 1) Leer la acción de control que entrega el PLC.
        lectura1 = (float)datos.cv1v;
        lectura2 = (float)datos.cv2v;
        lectura3 = (float)datos.cv3v;

        // 2) Arranque sincronizado: la planta no avanza ni se registra
        //    hasta que el controlador entregue su primera salida válida.
        if (!cvValida)
        {
            bool listo = !esperarPrimerCV ||
                         (lectura1 > 0f && lectura2 > 0f && lectura3 > 0f);
            if (!listo) return;

            cvValida = true;
            reloj.Restart();
            tRealAnterior = 0.0;
        }

        // 3) Aplicar la acción de control a las válvulas.
        if (lectura1 != 0f) vpw = Saturar(lectura1, 0f, 1f);
        if (lectura2 != 0f) vpc = Saturar(lectura2, 0f, 1f);
        if (lectura3 != 0f) vpg = Saturar(lectura3, 0f, 1f);

        datos.cv1 = vpw;
        datos.cv2 = vpc;
        datos.cv3 = vpg;

        // 4) Marcas de tiempo real del instante k.
        tiempoReal = reloj.Elapsed.TotalSeconds;
        periodoRealUltimo = (float)(tiempoReal - tRealAnterior);
        tRealAnterior = tiempoReal;

        // 5) Registrar la fila k ANTES de integrar.
        if (!enHilo) escribir_Texto.Escribir();   // Escribir_Texto puede usar la API de Unity
        RegistrarFilaRepeticion();

        // 6) Integrar la planta un periodo Ts con las válvulas retenidas.
        SimularUnPaso();

        // 6b) Robustez: ruido aditivo de amplitud uniforme (si está activo).
        AplicarRuido();

        // 7) Publicar pv_(k+1) hacia el PLC (con ruido de medición y fallas
        float m1 = hw + nMed1, m2 = hb + nMed2, m3 = pg_psi + nMed3;
        if (com != null) com.AplicarFallaSensor(datos.num + 1, ref m1, ref m2, ref m3);
        datos.pv1 = m1;
        datos.pv2 = m2;
        datos.pv3 = m3;

        // 8) Contar el paso y aplicar el cronograma de escalones.
        datos.num++;
        num = datos.num;
        if (escalones == true) AplicarEscalones();
    }

    // ==========================================================
    // CRONOGRAMA DE ESCALONES (valores idénticos a la versión anterior)
    // ==========================================================
    private void AplicarEscalones()
    {
        // Robustez: parámetros y ruido del tramo que empieza en este escalón.
        if (val_esc > 0 && num > 0 && num % val_esc == 0 && num / val_esc <= 9)
            ConfigurarTramo(num / val_esc);

        if (num == val_esc * 1)
        {
            FijarEscenario(0.85f, 0.72f, 35.0f, 0.1374f, 0.0711f, 0.4906f);
            print("2");
        }
        else if (num == val_esc * 2)
        {
            FijarEscenario(0.85f, 0.72f, 35.0f, 0.1374f, 0.0725f, 0.4906f);
            print("3");
        }
        else if (num == val_esc * 3)
        {
            FijarEscenario(0.85f, 0.72f, 35.0f, 0.1374f, 0.0725f, 0.4606f);
            print("4");
        }
        else if (num == val_esc * 4)
        {
            FijarEscenario(0.80f, 0.72f, 40.0f, 0.1874f, 0.0725f, 0.4606f);
            print("5");
        }
        else if (num == val_esc * 5)
        {
            FijarEscenario(0.80f, 0.75f, 40.0f, 0.1874f, 0.0725f, 0.4606f);
            print("6");
        }
        else if (num == val_esc * 6)
        {
            FijarEscenario(0.78f, 0.75f, 45.0f, 0.1874f, 0.0725f, 0.4606f);
            print("7");
        }
        else if (num == val_esc * 7)
        {
            FijarEscenario(0.78f, 0.75f, 45.0f, 0.1074f, 0.0725f, 0.4606f);
            print("8");
        }
        else if (num == val_esc * 8)
        {
            FijarEscenario(0.78f, 0.75f, 35.0f, 0.1074f, 0.0701f, 0.4606f);
            print("9");
        }
        else if (num == val_esc * 9)
        {
            FijarEscenario(0.78f, 0.70f, 35.0f, 0.1074f, 0.0701f, 0.4206f);
            print("10");
        }
        else if (num == val_esc * 10)
        {
            CerrarRegistroRepeticion();
            if (repetirEscenario && repeticionActual < numeroRepeticiones)
            {
                print("Fin de la repetición " + repeticionActual + " de " + numeroRepeticiones);
                IniciarPausa();
                return;
            }
            datos.k = 0;
            escenarioTerminado = true;
            print("Fin escalones.");
            if (Thread.CurrentThread.ManagedThreadId == hiloPrincipalId) Application.Quit();
            else salirPendiente = true;
#if UNITY_EDITOR
            //Application.Quit(); //no hace nada dentro del editor: se detiene
            // el modo Play para que el registro termine exactamente aquí.



            //UnityEditor.EditorApplication.isPlaying = false;
#endif
        }
    }

    // Aplica setpoints y perturbaciones con efecto inmediato: el siguiente
    // paso del modelo ya los usa aunque caiga dentro del mismo cuadro.
    private void FijarEscenario(float hws_m, float hbs_m, float pgs_psi,
                                float qwi_n, float qci_n, float qgi_n)
    {
        if (Thread.CurrentThread.ManagedThreadId == hiloPrincipalId)
        {
            slider_hws.value = hws_m * MT_TO_FT;
            slider_hbs.value = hbs_m * MT_TO_FT;
            slider_pgs.value = pgs_psi;
            slider_qwi.value = qwi_n;
            slider_qci.value = qci_n;
            slider_qgi.value = qgi_n;
        }
        else
        {
            sliderPend[0] = hws_m * MT_TO_FT; sliderPend[1] = hbs_m * MT_TO_FT; sliderPend[2] = pgs_psi;
            sliderPend[3] = qwi_n; sliderPend[4] = qci_n; sliderPend[5] = qgi_n;
            slidersPendientes = true;
        }

        hws = hws_m;
        hbs = hbs_m;
        pgs = pgs_psi;
        qwi = qwi_n;
        qci = qci_n;
        qgi = qgi_n;

        datos.sp1 = hws;
        datos.sp2 = hbs;
        datos.sp3 = pgs;
        datos.qwi = qwi;
        datos.qci = qci;
        datos.qgi = qgi;
    }

    private void ActualizarTextosHMI()
    {
        TQwi.text = qwi.ToString("F3");
        TQci.text = qci.ToString("F3");
        TQgi.text = qgi.ToString("F3");

        THws.text = (hws * MT_TO_FT).ToString("F3");
        THw.text = (hw * MT_TO_FT).ToString("F3");
        Tvpw.text = (vpw * 100).ToString("F3");
        THbs.text = (hbs * MT_TO_FT).ToString("F3");
        THb.text = (hb * MT_TO_FT).ToString("F3");
        Tvpc.text = (vpc * 100).ToString("F3");
        TPgs.text = (pgs).ToString("F2");
        TPg.text = (pg_psi).ToString("F2");
        Tvpg.text = (vpg * 100).ToString("F3");

        Tkp1.text = (kp1).ToString("F2");
        Tti1.text = (ti1).ToString("F2");
        Ttd1.text = (td1).ToString("F2");
        Tkp2.text = (kp2).ToString("F2");
        Tti2.text = (ti2).ToString("F2");
        Ttd2.text = (td2).ToString("F2");
        Tkp3.text = (kp3).ToString("F2");
        Tti3.text = (ti3).ToString("F2");
        Ttd3.text = (td3).ToString("F2");

        LIT1.text = (hw * MT_TO_FT).ToString("F3");
        cLIT1.text = (Mathf.Lerp(4, 20, (hw * 1) / maxhw)).ToString("F2");
        LIT2.text = (hb * MT_TO_FT).ToString("F3");
        cLIT2.text = (Mathf.Lerp(4, 20, (hb * 1) / maxhb)).ToString("F2");
        PIT1.text = (pg_psi).ToString("F3");
        cPIT1.text = (Mathf.Lerp(4, 20, pg_psi / maxPg)).ToString("F2");
        float TempF;
        TempF = (T - 273.15f) * (9.0f / 5.0f) + 32.0f;
        TIT1.text = (TempF).ToString("F2");
        cTIT1.text = (Mathf.Lerp(4, 20, TempF / maxT)).ToString("F2");
    }

    // ==========================================================
    // FUNCIONES PRINCIPALES DE SIMULACIÓN
    // ==========================================================
    private ModeloResult ModeloSeparador()
    {
        return ModeloSeparador(x_hc, x_hw, x_hb, x_pg);
    }

    private ModeloResult ModeloSeparador(double xhc, double xhw, double xhb, double xpg)
    {
        // ------------------------------------------------------
        // Estado con protección para cálculos no lineales
        // ------------------------------------------------------
        double hc_m = SaturarD(xhc, 1e-6, hs - 1e-6);
        double hw_m = SaturarD(xhw, 1e-6, hs - 1e-6);
        double hb_m = SaturarD(xhb, 1e-6, 2.5);
        double pg_m = Math.Max(xpg, 1000.0);

        // ------------------------------------------------------
        // Volumen total y altura ha
        // ------------------------------------------------------
        double vt = HemiVolt(ds, La, Lb);
        double ha_m = hw_m + hc_m;

        // ------------------------------------------------------
        // Flujo qca sobre barrera / vertedero
        // ------------------------------------------------------
        double qca_m = 0.0;
        if (ha_m > hs)
        {
            double H = Math.Max(ha_m - hs, 0.0);
            qca_m = 0.415 * Math.Max(ds - 0.2 * H, 0.0) * Math.Pow(H, 1.5) * Math.Sqrt(2.0 * g);
            if (!EsFinito(qca_m) || qca_m < 0.0) qca_m = 0.0;
        }

        // ------------------------------------------------------
        // Salida de crudo
        // ------------------------------------------------------
        double argcb = (pg_m + rhoc * g * hb_m - pob) / sgc;
        double qcb_m = argcb > 0.0 ? kvc * vpc * Math.Sqrt(argcb) : 0.0;
        if (!EsFinito(qcb_m) || qcb_m < 0.0) qcb_m = 0.0;

        // ------------------------------------------------------
        // Salida de agua
        // ------------------------------------------------------
        double argwo = (pg_m + rhoc * g * hc_m + rhow * g * hw_m - poa) / sgw;
        double qwo_m = argwo > 0.0 ? kvw * vpw * Math.Sqrt(argwo) : 0.0;
        if (!EsFinito(qwo_m) || qwo_m < 0.0) qwo_m = 0.0;

        // ------------------------------------------------------
        // Salida de gas
        // ------------------------------------------------------
        double Tf = ((T - 273.15) * 9.0 / 5.0) + 32.0;
        double pg_psia = pg_m * 1.450377e-4 + 14.7;
        double poc_psia = poc * 1.450377e-4 + 14.7;
        double dp2 = pg_psia * pg_psia - poc_psia * poc_psia;
        double qgden = (mgas / mair) * (Tf + 460.0);

        double qgo_m = 0.0;
        if (dp2 > 0.0 && qgden > 0.0 && vpg > 0.0)
        {
            qgo_m = 962.0 * kvg * vpg * Math.Sqrt(dp2 / qgden) * 7.86579e-6;
        }
        if (!EsFinito(qgo_m) || qgo_m < 0.0) qgo_m = 0.0;

        // ------------------------------------------------------
        // Volúmenes
        // ------------------------------------------------------
        double va_m = HemiVols(SaturarD(ha_m, 0.0, ds), La, ds);
        double vb_m = HemiVols(SaturarD(hb_m, 0.0, ds), Lb, ds);

        // ------------------------------------------------------
        // Derivadas
        // ------------------------------------------------------
        const double eps_h = 1e-4;

        double dhc_m = (qci - qca_m) / HemiHead(Math.Max(hc_m, eps_h), ds, La);
        double dhw_m = (qwi - qwo_m) / HemiHead(Math.Max(hw_m, eps_h), ds, La);
        double dhb_m = ha_m <= hs ? 0.0 : (qca_m - qcb_m) / HemiHead(Math.Max(hb_m, eps_h), ds, Lb);

        double Vgas = Math.Max(vt - va_m - vb_m, 1e-3);
        double dpg_m = pg_m * (qgi - qgo_m + qci + qwi - qwo_m - qcb_m) / Vgas;
        if (!EsFinito(dpg_m)) dpg_m = 0.0;

        return new ModeloResult
        {
            dhc = dhc_m,
            dhw = dhw_m,
            dhb = dhb_m,
            dpg = dpg_m,
            qwo = qwo_m,
            qca = qca_m,
            qcb = qcb_m,
            qgo = qgo_m,
            va = va_m,
            vb = vb_m,
            ha = ha_m
        };
    }

    // ==========================================================
    // GEOMETRÍA DEL RECIPIENTE
    // ==========================================================
    private double HemiHead(double h, double Ds, double L)
    {
        h = SaturarD(h, 1e-6, Ds - 1e-6);

        double A = 1.0 / Math.Sqrt(h * (Ds - h));
        double B = (Ds - 2.0 * h) / (2.0 * Ds * Math.Sqrt(h * Ds - h * h));
        double C = (-4.0 * h * h + 3.0 * Ds * h) / (2.0 * Ds * Math.Sqrt(Ds * h - h * h));
        double D = 2.0 * h / (Ds * Ds);
        double E = 3.0 * h * h / (Ds * Ds * Ds);

        double w1 = (L * Ds * Ds) * ((A / 4.0) - (B / 2.0) + (C / Ds));
        double w2 = (Math.PI * Ds * Ds * Ds / 12.0) * (3.0 * D - 2.0 * E);

        return Math.Max(w1 + w2, 1e-6);
    }

    private double HemiVols(double h, double L, double D)
    {
        h = SaturarD(h, 0.0, D);

        double x = SaturarD(1.0 - 2.0 * h / D, -1.0, 1.0);
        double term = Math.Max((h / D) - Math.Pow(h / D, 2.0), 0.0);

        double vcil = (L * D * D) *
                      ((0.25 * Math.Acos(x)) - ((0.5 - (h / D)) * Math.Sqrt(term)));

        double vcap = (D * D * D * Math.PI / 12.0) *
                      ((3.0 * Math.Pow(h / D, 2.0)) - (2.0 * Math.Pow(h / D, 3.0)));

        return vcil + vcap;
    }

    private double HemiVolt(double Ds, double La_m, double Lb_m)
    {
        return ((Math.PI * Ds * Ds / 4.0) * (La_m + Lb_m)) +
               (Math.PI * Ds * Ds * Ds / 6.0);
    }

    // ==========================================================
    // PASO DESDE EL HILO DE COMUNICACIÓN (modo integrarEnHilo)
    // Devuelve la imagen de DB1 para escribir de inmediato, o null si la
    // planta no debe avanzar (inactiva o en pausa entre repeticiones).
    // ==========================================================
    public byte[] PasoDesdeHilo(Comunicacion_Sync.Ciclo c)
    {
        lock (candadoPlanta)
        {
            if (!activoHilo || enPausa) return null;
            datos.cv1v = c.cv1;
            datos.cv2v = c.cv2;
            datos.cv3v = c.cv3;
            enHilo = true;
            try { PasoDeControl(); }
            finally { enHilo = false; }
            pasosHilo++;
            ultimoSeqEnviado = c.contador;
            return enPausa ? null : DB1Mapa.Imagen(datos, true);
        }
    }

    // ==========================================================
    // REPETICIONES DEL ESCENARIO
    // ==========================================================
    private void IniciarPausa()
    {
        enPausa = true;
        tPausa = 0f;
        actGuardada = datos.Activation;
        actPIDGuardada = datos.Activation_PID;
        actMPCGuardada = datos.Activation_MPC;
        actFuzzyGuardada = datos.Activation_FUZZY;
        // Desactivar: el PLC reinicia el controlador mientras no está activo.
        datos.Activation = false;
        datos.Activation_PID = false;
        datos.Activation_MPC = false;
        datos.Activation_FUZZY = false;
    }

    private void TerminarPausa()
    {
        lock (candadoPlanta) TerminarPausaInterno();
    }

    private void TerminarPausaInterno()
    {
        repeticionActual++;

        // Planta en su estado inicial.
        x_hc = hc0;
        x_hw = hw0;
        x_hb = hb0;
        x_pg = pg0_psi * (double)PSI_TO_PA;
        vpw = vpw0;
        vpc = vpc0;
        vpg = vpg0;
        simulationTime = 0.0;
        To = 0f;
        cvValida = false;
        reloj.Reset();
        PublicarSalidas(ModeloSeparador());

        // Escenario inicial y contadores.
        num = 0;
        datos.num = 0;
        FijarEscenario(0.85f, 0.72f, 35.0f, 0.1374f, 0.0711f, 0.4906f);
        datos.pv1 = hw;
        datos.pv2 = hb;
        datos.pv3 = pg_psi;
        datos.cv1v = 0f;              // se espera la primera acción nueva del PLC
        datos.cv2v = 0f;
        datos.cv3v = 0f;

        // Robustez: parámetros nominales y semilla de esta repetición.
        IniciarAleatorios(nuevaSemillaPorRepeticion ? semilla + repeticionActual - 1 : semilla);
        RestablecerParametros();

        AbrirRegistrosRepeticion();
        ConfigurarTramo(0);

        // Reactivar el mismo controlador.
        datos.Activation = actGuardada;
        datos.Activation_PID = actPIDGuardada;
        datos.Activation_MPC = actMPCGuardada;
        datos.Activation_FUZZY = actFuzzyGuardada;
        enPausa = false;
        print("Inicio de la repetición " + repeticionActual + " de " + numeroRepeticiones);
    }

    private void AbrirRegistrosRepeticion()
    {
        string fecha = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string rep = repetirEscenario ? "_rep" + repeticionActual.ToString("00") : "";
        etiquetaCtrl = datos.Activation_MPC ? "MPC" : datos.Activation_FUZZY ? "FUZZY" : datos.Activation_PID ? "PID" : "CTRL";

        rutaRobustez = Path.Combine(rutaProyecto,
            "Robustez_s" + semilla + rep + "_" + fecha + ".csv");
        if (aplicarRobustez)
        {
            CultureInfo ci = CultureInfo.InvariantCulture;
            File.WriteAllText(rutaRobustez,
                "# valvulas={" + Lista(escalonesValvulas) + "} varKv=" + varKv.ToString(ci) +
                "; densidades={" + Lista(escalonesDensidades) + "} varRho=" + varRho.ToString(ci) +
                "; volverANominal=" + volverANominal +
                "; ruidoEstado={" + Lista(escalonesRuidoEstado) + "} amp=" + ampHw.ToString(ci) + "/" + ampHb.ToString(ci) + "/" + ampPg_psi.ToString(ci) +
                "; ruidoMedicion={" + Lista(escalonesRuidoMedicion) + "} amp=" + ampMedHw.ToString(ci) + "/" + ampMedHb.ToString(ci) + "/" + ampMedPg_psi.ToString(ci) +
                "; semilla=" + (nuevaSemillaPorRepeticion && repetirEscenario ? semilla + repeticionActual - 1 : semilla) + "\n" +
                "evento;t_s;valvulas;densidades;ruido_estado;ruido_medicion;fKvw;fKvc;fKvg;fRhoc;fRhow\n");
        }

        CerrarRegistroRepeticion();
        sufijoRegistro = rep;
        abrirRegistroPendiente = registroPropio || (repetirEscenario && registroPorRepeticion);
    }

    // Misma convención y formato que el registro de Escribir_Texto (fila k antes de integrar).
    private void RegistrarFilaRepeticion()
    {
        if (abrirRegistroPendiente)
        {
            // Se abre con la primera fila: así el nombre lleva el controlador activo.
            abrirRegistroPendiente = false;
            etiquetaCtrl = datos.Activation_MPC ? "MPC" : datos.Activation_FUZZY ? "FUZZY" : datos.Activation_PID ? "PID" : "CTRL";
            string ruta = Path.Combine(rutaProyecto, "Datos_" + etiquetaCtrl + sufijoRegistro + "_" +
                                       DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".txt");
            registroRep = new StreamWriter(ruta);
            registroRep.NewLine = "\r\n";
            registroRep.WriteLine("sp1\tpv1\tcv1\tsp2\tpv2\tcv2\tsp3\tpv3\tcv3\tt_sim\tt_real");
        }
        if (registroRep == null) return;
        CultureInfo ci = CultureInfo.InvariantCulture;
        registroRep.WriteLine(string.Join("\t",
            ((float)datos.sp1).ToString("F6", ci), ((float)datos.pv1).ToString("F6", ci), ((float)datos.cv1).ToString("F6", ci),
            ((float)datos.sp2).ToString("F6", ci), ((float)datos.pv2).ToString("F6", ci), ((float)datos.cv2).ToString("F6", ci),
            ((float)datos.sp3).ToString("F6", ci), ((float)datos.pv3).ToString("F6", ci), ((float)datos.cv3).ToString("F6", ci),
            simulationTime.ToString("F1", ci), tiempoReal.ToString("F4", ci)));
    }

    private void CerrarRegistroRepeticion()
    {
        if (registroRep != null)
        {
            registroRep.Flush();
            registroRep.Close();
            registroRep = null;
        }
    }

    void OnApplicationQuit() { CerrarRegistroRepeticion(); }

    // ==========================================================
    // ROBUSTEZ: PARÁMETROS Y RUIDO
    // ==========================================================
    private void IniciarAleatorios(int s)
    {
        rngParam = new System.Random(s);
        rngRuido = new System.Random(s + 100000);
    }

    private static double U(System.Random r) { return 2.0 * (r.NextDouble() - 0.5); }   // uniforme en [-1, 1]

    private static bool Contiene(int[] lista, int evento)
    {
        if (lista == null) return false;
        foreach (int e in lista) if (e == evento) return true;
        return false;
    }

    private static string Lista(int[] lista)
    {
        return lista == null ? "" : string.Join(" ", lista);
    }

    private void RestablecerParametros()
    {
        fKvw = fKvc = fKvg = fRhoc = fRhow = 1f;
        AplicarFactores();
    }

    private void AplicarFactores()
    {
        kvw = kvw_nom * fKvw;
        kvc = kvc_nom * fKvc;
        kvg = kvg_nom * fKvg;
        rhoc = rhoc_nom * fRhoc; sgc = sgc_nom * fRhoc;   // la SG cambia con la densidad
        rhow = rhow_nom * fRhow; sgw = sgw_nom * fRhow;
    }

    // Define qué efectos actúan en el tramo que empieza en el evento indicado.
    private void ConfigurarTramo(int evento)
    {
        escalonVigente = evento;
        tramoValvulas = aplicarRobustez && Contiene(escalonesValvulas, evento);
        tramoDensidades = aplicarRobustez && Contiene(escalonesDensidades, evento);
        tramoRuidoEstado = aplicarRobustez && Contiene(escalonesRuidoEstado, evento);
        tramoRuidoMedicion = aplicarRobustez && Contiene(escalonesRuidoMedicion, evento);
        if (!aplicarRobustez) { RestablecerParametros(); return; }

        // Se sortean siempre los cinco factores: la secuencia no depende de
        // qué grupos estén seleccionados en cada escalón.
        float aKvw = (float)(1.0 + varKv * U(rngParam));
        float aKvc = (float)(1.0 + varKv * U(rngParam));
        float aKvg = (float)(1.0 + varKv * U(rngParam));
        float aRhoc = (float)(1.0 + varRho * U(rngParam));
        float aRhow = (float)(1.0 + varRho * U(rngParam));

        if (tramoValvulas) { fKvw = aKvw; fKvc = aKvc; fKvg = aKvg; }
        else if (volverANominal) { fKvw = 1f; fKvc = 1f; fKvg = 1f; }

        if (tramoDensidades) { fRhoc = aRhoc; fRhow = aRhow; }
        else if (volverANominal) { fRhoc = 1f; fRhow = 1f; }

        AplicarFactores();

        if (!string.IsNullOrEmpty(rutaRobustez) && File.Exists(rutaRobustez))
        {
            CultureInfo ci = CultureInfo.InvariantCulture;
            File.AppendAllText(rutaRobustez, evento + ";" + simulationTime.ToString("F1", ci) + ";" +
                (tramoValvulas ? 1 : 0) + ";" + (tramoDensidades ? 1 : 0) + ";" +
                (tramoRuidoEstado ? 1 : 0) + ";" + (tramoRuidoMedicion ? 1 : 0) + ";" +
                fKvw.ToString("F4", ci) + ";" + fKvc.ToString("F4", ci) + ";" + fKvg.ToString("F4", ci) + ";" +
                fRhoc.ToString("F4", ci) + ";" + fRhow.ToString("F4", ci) + "\n");
        }
    }

    // Ruido de cada paso, según el tramo vigente. Ambos tipos pueden actuar a la vez.
    private void AplicarRuido()
    {
        nMed1 = nMed2 = nMed3 = 0f;

        if (tramoRuidoEstado)
        {
            // hw(k+1) = hw(k+1) + ampHw*(2*(rand - 0.5)), y lo mismo para hb y pg
            x_hw += ampHw * U(rngRuido);
            x_hb += ampHb * U(rngRuido);
            x_pg += ampPg_psi * U(rngRuido) * PSI_TO_PA;
            LimitarEstados();
            PublicarSalidas(ModeloSeparador());
        }

        if (tramoRuidoMedicion)
        {
            // pv = h + ampMed*(2*(rand - 0.5)): el estado no cambia, solo lo que ve el PLC
            nMed1 = (float)(ampMedHw * U(rngRuido));
            nMed2 = (float)(ampMedHb * U(rngRuido));
            nMed3 = (float)(ampMedPg_psi * U(rngRuido));
        }
    }

    // Imagen de los 124 bytes de DB1 "Data" (ver DB1Mapa.cs) para el modo sincronizado.
    private byte[] ConstruirBufferSalida()
    {
        byte[] b = DB1Mapa.Imagen(datos, true);
        if (enPausa) b[0] = 0;
        return b;
    }

    // ==========================================================
    // FUNCIONES AUXILIARES
    // ==========================================================
    private void LimitarEstados()
    {
        x_hc = SaturarD(x_hc, 1e-6, hs - 1e-6);
        x_hw = SaturarD(x_hw, 1e-6, hs - 1e-6);
        x_hb = SaturarD(x_hb, 1e-6, 2.5);
        x_pg = Math.Max(x_pg, 1000.0);
    }

    private float Saturar(float value, float min, float max)
    {
        if (float.IsNaN(value) || float.IsInfinity(value)) return min;
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private double SaturarD(double value, double min, double max)
    {
        if (double.IsNaN(value) || double.IsInfinity(value)) return min;
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private void ActualizarTexto()
    {
        estadoText =
            $"t = {simulationTime:F1} s\n" +
            $"hc = {hc:F3} m\n" +
            $"hw = {hw:F3} m\n" +
            $"hb = {hb:F3} m\n" +
            $"pg = {pg_psi:F2} psi\n\n" +
            $"qwo = {qwo:F4}\n" +
            $"qca = {qca:F4}\n" +
            $"qcb = {qcb:F4}\n" +
            $"qgo = {qgo:F4}\n" +
            $"va = {va:F4}\n" +
            $"vb = {vb:F4}\n" +
            $"ha = {ha:F4}";
    }

    private bool EsFinito(double value)
    {
        return !(double.IsNaN(value) || double.IsInfinity(value));
    }

    float tanh(float value)
    {
        float result;
        result = (Mathf.Exp(value) - Mathf.Exp(-value)) / (Mathf.Exp(value) + Mathf.Exp(-value));
        return result;
    }

    double sigm(float value)
    {
        float result;
        result = (1 / (1 + Mathf.Exp(-value)));
        return result;
    }
}
