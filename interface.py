import subprocess
import os
import sys

# =============================================================================
# CONFIGURACIÓN DE RUTAS (CRÍTICO)
# =============================================================================
DIR_QUARTUS_BIN = r"C:\intelFPGA_lite\23.1std\quartus\bin64"
RUTA_QUARTUS_STP = os.path.join(DIR_QUARTUS_BIN, "quartus_stp.exe")

RUTA_PROYECTO   = os.getcwd()
RUTA_TCL_SCRIPT = os.path.join(RUTA_PROYECTO, "run_fpga.tcl")
RUTA_CPP_SOURCE = os.path.join(RUTA_PROYECTO, "modelo_referencia.cpp")
RUTA_CPP_EXE    = os.path.join(RUTA_PROYECTO, "modelo.exe")


def compilar_cpp():
    print(f"Verificando modelo C++...")
    
    exe_existe = os.path.exists(RUTA_CPP_EXE)
    
    try:
        cmd = ["g++", RUTA_CPP_SOURCE, "-o", RUTA_CPP_EXE, "-static"]
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        print("✅ Compilación exitosa (Nueva versión generada).")
        
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        if exe_existe:
            print("⚠️ Advertencia: No se pudo recompilar el C++ (g++ no encontrado o error).")
            print("✅ USANDO 'modelo.exe' PREVIO (Modo Seguro).")
        else:
            print("\n❌ ERROR CRÍTICO: No se puede compilar C++ y no existe 'modelo.exe'.")
            print(f"   g++ {os.path.basename(RUTA_CPP_SOURCE)} -o modelo.exe -static")
            sys.exit(1)

def ejecutar_cpp(w, h, scale):
    """Ejecuta el binario C++ y captura la salida."""
    try:
        if not os.path.exists(RUTA_CPP_EXE):
            print(f"❌ Error: No encuentro {RUTA_CPP_EXE}")
            sys.exit(1)

        cmd = [RUTA_CPP_EXE, str(w), str(h), str(scale)]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        # Convertir salida "16 18 20..." a lista de enteros
        return list(map(int, result.stdout.strip().split()))
        
    except Exception as e:
        print(f"❌ Error ejecutando modelo C++: {e}")
        sys.exit(1)

def ejecutar_tcl(w, h, scale_hex):
    """Ejecuta quartus_stp usando ruta absoluta."""
    print(f"\n🔄 Ejecutando FPGA (Ancho={w}, Alto={h}, ScaleHex={scale_hex})...")
    print("-" * 60)
    
    # Verificación de seguridad
    if not os.path.exists(RUTA_QUARTUS_STP):
        print(f"ERROR: No encuentro Quartus en: {RUTA_QUARTUS_STP}")
        print("   -> Edita la variable DIR_QUARTUS_BIN en interface.py")
        sys.exit(1)

    cmd = [
        RUTA_QUARTUS_STP, 
        "-t", RUTA_TCL_SCRIPT, 
        str(w), str(h), scale_hex
    ]
    
    try:
        # Ejecutamos el proceso manteniendo la consola abierta para ver logs
        process = subprocess.Popen(
            cmd, 
            cwd=DIR_QUARTUS_BIN, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            text=True
        )

        data_fpga = []
        
        # Lectura de logs en tiempo real (Streaming)
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            if line:
                linea_limpia = line.strip()
                print(f"TCL> {linea_limpia}")
                
                # Captura de datos
                if "DATA_SEQ:" in linea_limpia:
                    try:
                        raw = linea_limpia.split("DATA_SEQ:")[1].strip()
                        raw = raw.replace('{', '').replace('}', '') # Limpiar sintaxis TCL
                        data_fpga = list(map(int, raw.split()))
                    except:
                        print("   (Error parseando datos del FPGA)")

        print("-" * 60)
        
        if process.returncode != 0:
            print(f"❌ El script TCL falló (Código {process.returncode})")
            # Imprimir error si hubo
            err_out = process.stderr.read()
            if err_out: print(f"STDERR TCL:\n{err_out}")
            sys.exit(1)
            
        return data_fpga

    except Exception as e:
        print(f"❌ Error lanzando subprocess: {e}")
        sys.exit(1)

# =============================================================================
# MAIN
# =============================================================================
def main():
    print("=== INTERFAZ DE CONTROL FPGA v2.0 ===")
    
    # 1. ENTRADA DE DATOS
    try:
        w_in = int(input("Ancho Imagen (e.g., 8): "))
        h_in = int(input("Alto Imagen  (e.g., 4): "))
        scale = float(input("Escala (0.5 a 1.0): "))
    except ValueError:
        print("Entrada inválida. Usa números.")
        return

    # Cálculo Hexadecimal Q8.8
    scale_int = int(scale * 256)
    scale_hex = f"0x{scale_int:02X}"
    
    print(f"\nConfiguración: {w_in}x{h_in}, Scale: {scale} (Hex: {scale_hex})")

    # 2. MODELO DE REFERENCIA (C++)
    compilar_cpp()
    golden_data = ejecutar_cpp(w_in, h_in, scale)
    print(f"C++ Generó {len(golden_data)} píxeles.")

    # 3. HARDWARE (FPGA)
    fpga_data = ejecutar_tcl(w_in, h_in, scale_hex)
    
    # Recorte de seguridad (por si el FPGA leyó basura extra al final)
    fpga_data = fpga_data[:len(golden_data)]
    print(f"FPGA Retornó {len(fpga_data)} píxeles.")

    # 4. COMPARACIÓN Y REPORTE
    print("\n=== REPORTE DE VALIDACIÓN ===")
    print(f"{'IDX':<5} {'C++':<8} {'FPGA':<8} {'STATUS'}")
    print("-" * 35)
    
    mismatches = 0
    for i, (gold, dut) in enumerate(zip(golden_data, fpga_data)):
        status = "✅" if gold == dut else "❌"
        if gold != dut: mismatches += 1
        
        # Mostrar errores o los primeros 10 datos correctos
        if i < 10 or status == "❌":
            print(f"{i:<5} {gold:<8} {dut:<8} {status}")
            
    if len(golden_data) > 10 and mismatches == 0:
        print("... (resto de datos correctos ocultos) ...")

    print("-" * 35)
    if mismatches == 0:
        print("✅ ÉXITO TOTAL: El Hardware coincide bit a bit con el Modelo C++.")
    else:
        print(f"❌ FALLO: Se encontraron {mismatches} diferencias.")

if __name__ == "__main__":
    main()