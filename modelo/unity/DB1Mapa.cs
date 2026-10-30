using System;
using Sharp7;

// =====================================================================
// DB1Mapa.cs  -  Mapa de DB1 "Data" (CPU 1511-1 PN, acceso no optimizado)
// Un solo lugar con los offsets, usado por Comunicacion.cs,
// Comunicacion_Sync.cs y Separador_Trifasico.cs.
//
//  Byte  Variable            Tipo            Escribe
//  0.0   Activacion          Bool            Unity
//  0.1   Activacion PID      Bool            Unity
//  0.2   Activacion MPC      Bool            Unity
//  0.3   Activacion FUZZY    Bool            Unity
//  2     Metodo_Sync         Int             Unity  (0 = asincrono, 1 = sincronizado)
//  4/8/12   Sp1 / Pv1 / Cv1  Real            Unity  (Cv1..Cv3 = apertura aplicada por la planta)
//  16/20/24 Sp2 / Pv2 / Cv2  Real            Unity
//  28/32/36 Sp3 / Pv3 / Cv3  Real            Unity
//  40    Sp_[0..2]           Array of Real   Unity
//  52    Pv_[0..2]           Array of Real   Unity
//  64    Perturbacion_[0..2] Array of Real   Unity
//  76    Cv_[0..2]           Array of Real   PLC   <- Unity NUNCA escribe aqui
//  88..120 Kp1 Ti1 Td1 Kp2 Ti2 Td2 Kp3 Ti3 Td3  Real  Unity
//  124   Contador_PLC        DInt            PLC   <- Unity NUNCA escribe aqui
//  128   Seq_Unity           DInt            Unity
//  132   Eco_Seq             DInt            PLC   <- Unity NUNCA escribe aqui
//  136   Falla_Com           Bool            PLC   <- Unity NUNCA escribe aqui
//
// Unity escribe sus 112 bytes de los 124 originales en dos peticiones
// (0-75 y 88-123), y despues Seq_Unity (128). Las zonas del PLC no se tocan.
// =====================================================================
public static class DB1Mapa
{
    public const int DB = 1;

    // Unity -> PLC
    public const int METODO_SYNC = 2;
    public const int SP1 = 4, PV1 = 8, CV1 = 12;
    public const int SP2 = 16, PV2 = 20, CV2 = 24;
    public const int SP3 = 28, PV3 = 32, CV3 = 36;
    public const int SP_ = 40, PV_ = 52, PERTURBACION_ = 64;
    public const int KP1 = 88, TI1 = 92, TD1 = 96, KP2 = 100, TI2 = 104, TD2 = 108, KP3 = 112, TI3 = 116, TD3 = 120;
    public const int SEQ_UNITY = 128;

    // PLC -> Unity
    public const int CV_ = 76;
    public const int CONTADOR_PLC = 124;
    public const int ECO_SEQ = 132;
    public const int FALLA_COM = 136;

    // Bloques de transferencia
    public const int TAM_IMAGEN = 124;                       // bytes 0-123, estructura original
    // DB1 termina en Falla_Com (136.0): su longitud es 138 bytes. Leer mas alla del
    // final hace fallar la peticion completa, por eso se leen 61 bytes (76-136).
    public const int LECTURA_INI = 76, LECTURA_TAM = 61;     // 76-136: Cv_, ganancias, contador, seq, eco, falla

    // Imagen de los 124 bytes con todo lo que escribe Unity (las zonas del PLC quedan en cero y no se envian).
    public static byte[] Imagen(Datos d, bool metodoSync)
    {
        byte[] b = new byte[TAM_IMAGEN];
        S7.SetBitAt(b, 0, 0, d.Activation);
        S7.SetBitAt(b, 0, 1, d.Activation_PID);
        S7.SetBitAt(b, 0, 2, d.Activation_MPC);
        S7.SetBitAt(b, 0, 3, d.Activation_FUZZY);
        S7.SetIntAt(b, METODO_SYNC, (short)(metodoSync ? 1 : 0));

        S7.SetRealAt(b, SP1, (float)d.sp1); S7.SetRealAt(b, PV1, (float)d.pv1); S7.SetRealAt(b, CV1, (float)d.cv1);
        S7.SetRealAt(b, SP2, (float)d.sp2); S7.SetRealAt(b, PV2, (float)d.pv2); S7.SetRealAt(b, CV2, (float)d.cv2);
        S7.SetRealAt(b, SP3, (float)d.sp3); S7.SetRealAt(b, PV3, (float)d.pv3); S7.SetRealAt(b, CV3, (float)d.cv3);

        S7.SetRealAt(b, SP_ + 0, (float)d.sp1); S7.SetRealAt(b, SP_ + 4, (float)d.sp2); S7.SetRealAt(b, SP_ + 8, (float)d.sp3);
        S7.SetRealAt(b, PV_ + 0, (float)d.pv1); S7.SetRealAt(b, PV_ + 4, (float)d.pv2); S7.SetRealAt(b, PV_ + 8, (float)d.pv3);
        S7.SetRealAt(b, PERTURBACION_ + 0, (float)d.qwi);
        S7.SetRealAt(b, PERTURBACION_ + 4, (float)d.qci);
        S7.SetRealAt(b, PERTURBACION_ + 8, (float)d.qgi);

        S7.SetRealAt(b, KP1, (float)d.kp1); S7.SetRealAt(b, TI1, (float)d.ti1); S7.SetRealAt(b, TD1, (float)d.td1);
        S7.SetRealAt(b, KP2, (float)d.kp2); S7.SetRealAt(b, TI2, (float)d.ti2); S7.SetRealAt(b, TD2, (float)d.td2);
        S7.SetRealAt(b, KP3, (float)d.kp3); S7.SetRealAt(b, TI3, (float)d.ti3); S7.SetRealAt(b, TD3, (float)d.td3);
        return b;
    }

    // Escribe la zona de Unity (0-75 y 88-123) sin tocar Cv_ (76-87). Devuelve 0 si todo salio bien.
    public static int EscribirZonaUnity(S7Client cliente, byte[] imagen)
    {
        byte[] a = new byte[76];
        Buffer.BlockCopy(imagen, 0, a, 0, 76);
        int r = cliente.DBWrite(DB, 0, 76, a);
        if (r != 0) return r;
        byte[] g = new byte[36];
        Buffer.BlockCopy(imagen, KP1, g, 0, 36);
        return cliente.DBWrite(DB, KP1, 36, g);
    }

    // Igual que EscribirZonaUnity, pero las ganancias (88-123) solo se escriben si
    // cambiaron: ahorra una peticion S7 por ciclo. ultimas guarda lo ultimo escrito.
    public static int EscribirZonaUnity(S7Client cliente, byte[] imagen, ref byte[] ultimas)
    {
        byte[] a = new byte[76];
        Buffer.BlockCopy(imagen, 0, a, 0, 76);
        int r = cliente.DBWrite(DB, 0, 76, a);
        if (r != 0) return r;
        byte[] g = new byte[36];
        Buffer.BlockCopy(imagen, KP1, g, 0, 36);
        bool iguales = ultimas != null;
        if (iguales) for (int i = 0; i < 36; i++) if (g[i] != ultimas[i]) { iguales = false; break; }
        if (iguales) return 0;
        r = cliente.DBWrite(DB, KP1, 36, g);
        if (r == 0) ultimas = g;
        return r;
    }

    // Escribe Seq_Unity (128). Siempre despues de EscribirZonaUnity.
    public static int EscribirSeq(S7Client cliente, int seq)
    {
        byte[] s = new byte[4];
        S7.SetDIntAt(s, 0, seq);
        return cliente.DBWrite(DB, SEQ_UNITY, 4, s);
    }
}
