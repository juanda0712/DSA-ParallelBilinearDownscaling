import subprocess
import os
import sys
import numpy as np
import matplotlib.pyplot as plt

# =============================================================================
# MODELO DE REFERENCIA (PYTHON PURO)
# =============================================================================
Q_SHIFT = 8
Q_ROUND = 0x0080

def to_q8_8(x): return x << Q_SHIFT
def float_to_q8_8(x): return int(x * (1 << Q_SHIFT))
def q8_8_mul(a, b): return (a * b) >> Q_SHIFT
def from_q8_8_sat(x):
    tmp = x + Q_ROUND
    res = tmp >> Q_SHIFT
    if res < 0: return 0
    if res > 255: return 255
    return res
def lerp(a, b, t):
    return a + q8_8_mul(b - a, t)

def generar_referencia(w_in, h_in, scale):
    """Genera la imagen esperada (GOLDEN REFERENCE)."""
    print(f"   [Ref] Generando datos para {w_in}x{h_in}...")
    w_out = int(w_in * scale)
    h_out = int(h_in * scale)
    step_q = float_to_q8_8(1.0 / scale)

    # Patrón IDÉNTICO al TCL
    input_img = []
    for y in range(h_in):
        for x in range(w_in):
            val = ((y + 1) * 16) + x
            input_img.append(val % 256)
    
    output_data = []
    src_acc_y = 0

    for dy in range(h_out):
        src_acc_x = 0
        sy_int = src_acc_y >> Q_SHIFT
        fy = src_acc_y & 0xFF 

        for dx in range(w_out):
            sx_int = src_acc_x >> Q_SHIFT
            fx = src_acc_x & 0xFF

            if sx_int >= w_in - 1: sx_int = w_in - 2
            if sy_int >= h_in - 1: sy_int = h_in - 2

            idx_00 = sy_int * w_in + sx_int
            idx_10 = sy_int * w_in + (sx_int + 1)
            idx_01 = (sy_int + 1) * w_in + sx_int
            idx_11 = (sy_int + 1) * w_in + (sx_int + 1)

            p00 = to_q8_8(input_img[idx_00])
            p10 = to_q8_8(input_img[idx_10])
            p01 = to_q8_8(input_img[idx_01])
            p11 = to_q8_8(input_img[idx_11])
            
            q_fx, q_fy = fx << Q_SHIFT, fy << Q_SHIFT
            top = lerp(p00, p10, q_fx)
            bot = lerp(p01, p11, q_fx)
            res = from_q8_8_sat(lerp(top, bot, q_fy))
            
            output_data.append(res)
            src_acc_x += step_q
        src_acc_y += step_q
    return output_data, input_img

# =============================================================================
# EJECUCIÓN FPGA
# =============================================================================
DIR_QUARTUS_BIN = r"C:\intelFPGA_lite\23.1std\quartus\bin64" 
RUTA_QUARTUS_STP = os.path.join(DIR_QUARTUS_BIN, "quartus_stp.exe")
RUTA_PROYECTO = os.getcwd()
RUTA_TCL_SCRIPT = os.path.join(RUTA_PROYECTO, "run_fpga.tcl")

def ejecutar_fpga(w, h, scale_hex):
    print(f"\n🔄 Ejecutando FPGA (TCL)...")
    if not os.path.exists(RUTA_QUARTUS_STP):
        print(f"❌ Error: No encuentro quartus_stp.exe")
        sys.exit(1)

    cmd = [RUTA_QUARTUS_STP, "-t", RUTA_TCL_SCRIPT, str(w), str(h), scale_hex]
    
    try:
        process = subprocess.Popen(
            cmd, cwd=DIR_QUARTUS_BIN, 
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        data_seq = []
        data_simd = []
        
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None: break
            if line:
                l = line.strip()
                print(f"TCL> {l}")
                
                # CAPTURAR SECUENCIAL
                if "DATA_SEQ:" in l:
                    raw = l.split("DATA_SEQ:")[1].strip().replace('{','').replace('}','')
                    try: data_seq = list(map(int, raw.split()))
                    except: pass
                
                # CAPTURAR SIMD
                if "DATA_SIMD:" in l:
                    raw = l.split("DATA_SIMD:")[1].strip().replace('{','').replace('}','')
                    try: data_simd = list(map(int, raw.split()))
                    except: pass
                    
        return data_seq, data_simd
    except Exception as e:
        print(f"❌ Error TCL: {e}")
        sys.exit(1)

def visualizar(w_in, h_in, scale, img_in, img_ref, img_simd):
    w_out = int(w_in * scale)
    h_out = int(h_in * scale)
    try:
        arr_in  = np.array(img_in, dtype=np.uint8).reshape((h_in, w_in))
        arr_ref = np.array(img_ref, dtype=np.uint8).reshape((h_out, w_out))
        arr_hw  = np.array(img_simd[:len(img_ref)], dtype=np.uint8).reshape((h_out, w_out))
        
        fig, ax = plt.subplots(1, 3, figsize=(10, 4))
        ax[0].imshow(arr_in, cmap='gray', vmin=0, vmax=255); ax[0].set_title("Entrada")
        ax[1].imshow(arr_ref, cmap='gray', vmin=0, vmax=255); ax[1].set_title("Golden (Python/C++)")
        ax[2].imshow(arr_hw, cmap='gray', vmin=0, vmax=255); ax[2].set_title("FPGA (SIMD)")
        plt.show()
    except Exception as e:
        print(f"⚠️ Error visualización: {e}")

# =============================================================================
# MAIN
# =============================================================================
def main():
    print("=== INTERFAZ DE CONTROL FPGA ===")
    try:
        w_in = int(input("Ancho(EJ 64): "))
        h_in = int(input("Alto(Ej 32): "))
        scale = float(input("Escala(0.5 - 1.0): "))
    except: return

    scale_hex = f"0x{int(scale * 256):02X}"
    
    # 1. REFERENCIA
    golden_data, input_img = generar_referencia(w_in, h_in, scale)

    # 2. FPGA
    data_seq, data_simd = ejecutar_fpga(w_in, h_in, scale_hex)
    
    # Recorte
    len_ref = len(golden_data)
    data_seq = data_seq[:len_ref]
    data_simd = data_simd[:len_ref]

    # 3. REPORTE
    print(f"\n📊 RESULTADOS ({len_ref} píxeles)")
    print(f"{'IDX':<5} {'REF':<6} {'SEQ':<6} {'SIMD':<6} {'STATUS'}")
    print("-" * 40)

    err_seq = 0
    err_simd = 0
    
    for i in range(len_ref):

        g = golden_data[i]
        s = data_seq[i] if i < len(data_seq) else None
        p = data_simd[i] if i < len(data_simd) else None

        ok_seq  = (s == g)
        ok_simd = (p == g)

        # Contadores de error
        if not ok_seq:  err_seq  += 1
        if not ok_simd: err_simd += 1

        # Etiquetas
        tag_seq  = "✅" if ok_seq else "❌"
        tag_simd = "✅" if ok_simd else "❌"

        # Mostrar fila (solo las primeras 10 y las que tengan error)
        if i < 10 or not (ok_seq and ok_simd):
            print(f"{i:<5}  {g:<6}  {s:<6} {tag_seq:<3}   {p:<6} {tag_simd:<3}")


    if err_seq == 0 and err_simd == 0:
        print("\n✅ ÉXITO TOTAL: Ambos modos coinciden con la referencia.")
        visualizar(w_in, h_in, scale, input_img, golden_data, data_simd)
    else:
        print(f"\n❌ FALLOS: Seq={err_seq}, SIMD={err_simd}")

if __name__ == "__main__":
    main()