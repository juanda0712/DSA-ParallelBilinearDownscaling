# ==========================================================
# TEST TCL PARA EL MÓDULO CONNECT (Registros 0xF0–0xF6)
# ==========================================================

# ----------------------------------------------------------
# DETECTAR HARDWARE
# ----------------------------------------------------------

proc detect_hardware {} {
    global usbblaster_name test_device

    set usbblaster_name ""
    set test_device ""

    foreach hw [get_hardware_names] {
        if { [string match "USB-Blaster*" $hw] || [string match "*DE-SoC*" $hw] } {
            set usbblaster_name $hw
            break
        }
    }

    if { $usbblaster_name == "" } {
        puts "ERROR: No USB-Blaster detected!"
        exit
    }

    foreach dev [get_device_names -hardware_name $usbblaster_name] {
        if { [string match "@2*" $dev] } {
            set test_device $dev
            break
        }
    }

    if { $test_device == "" } {
        puts "ERROR: No @2 device found!"
        exit
    }

    puts "USB-Blaster = $usbblaster_name"
    puts "FPGA Device = $test_device"
}

# ----------------------------------------------------------
# ABRIR / CERRAR PUERTO
# ----------------------------------------------------------

proc open_port {} {
    global usbblaster_name test_device
    open_device -hardware_name $usbblaster_name -device_name $test_device
    device_lock -timeout 10000
}

proc close_port {} {
    catch {device_unlock}
    catch {close_device}
}

# ----------------------------------------------------------
# FUNCIONES MEM (IR=3)
# ----------------------------------------------------------

proc write_mem {addr8 data8} {
    open_port

    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr8}${data8}"
    device_virtual_dr_shift -instance_index 0 -dr_value $dr -length 16

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value

    close_port
}

proc read_mem {addr8} {
    open_port

    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr8}00000000"
    set resp [device_virtual_dr_shift -instance_index 0 -dr_value $dr -length 16]

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value

    close_port

    return [string range $resp 8 15]
}

# ----------------------------------------------------------
# TEST GENÉRICO
# ----------------------------------------------------------

proc test_reg {addr value} {
    puts "\n--- TEST REG $addr = $value ---"

    set addr_bin [format "%08b" $addr]
    set data_bin [format "%08b" $value]

    write_mem $addr_bin $data_bin

    set r [read_mem $addr_bin]

    puts "WRITE = $data_bin"
    puts "READ  = $r"
}

# ----------------------------------------------------------
# EJECUCIÓN DE PRUEBAS
# ----------------------------------------------------------

detect_hardware

# ===========================
# PRUEBA AUTOMÁTICA
# ===========================

# test_block_write.tcl
# Ejecutar después de cargar el bitstream y conectar el USB-Blaster

# Asume que detect_hardware/open_port/close_port/write_mem/read_mem/test_reg están en tu script base.

# 1) Escribir width = 320 (0x0140)
test_reg 0xF0 0x40
test_reg 0xF1 0x01

# 2) Escribir height = 240 (0x00F0)
test_reg 0xF2 0xF0
test_reg 0xF3 0x00

# 3) Escribir scale Q8.8 = 0.75 -> 0x00C0
test_reg 0xF4 0xC0
test_reg 0xF5 0x00

# 4) Leer de vuelta width/height/scale
puts "\nLeyendo WIDTH, HEIGHT, SCALE..."
set r0 [read_mem 00000111] ;# adapta si tu read_mem usa binario; aquí solo ejemplo
# Mejor: usa test_reg con lectura o imprime directamente usando test_reg y read_mem de tu script

# 5) Hacer start (MODE[0] = 1)
test_reg 0xF6 0x01

# Observa con SignalTap: probea regfile[0xF6], prev_mode_reg (si la expones), start_proc_pulse
puts "Start enviado. Revisa SignalTap para start_proc_pulse y regfile F6."

# Fin

