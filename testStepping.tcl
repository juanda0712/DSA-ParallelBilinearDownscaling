# ==========================================================
# TCL PARA PRUEBAS DEL CONNECT (Fase 2)
# ==========================================================

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

    foreach dev [get_device_names -hardware_name $usbblaster_name] {
        if { [string match "@2*" $dev] } {
            set test_device $dev
            break
        }
    }

    puts "USB-Blaster = $usbblaster_name"
    puts "FPGA Device = $test_device"
}

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
# MEM ACCESS (IR = 3)
# ----------------------------------------------------------

proc write_mem {addr value} {
    # addr = integer (0xF0)
    # value = integer (0x40)

    set addr_bin  [format "%08b" $addr]
    set data_bin  [format "%08b" $value]

    open_port
    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr_bin}${data_bin}"
    device_virtual_dr_shift -instance_index 0 -dr_value $dr -length 16

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port
}

proc read_mem {addr} {
    set addr_bin [format "%08b" $addr]

    open_port
    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr_bin}00000000"
    set resp [device_virtual_dr_shift -instance_index 0 -dr_value $dr -length 16]

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port

    return [string range $resp 8 15]
}

# ----------------------------------------------------------
# TEST para Registros F0–FF
# ----------------------------------------------------------

proc test_reg {addr value} {
    puts "\n--- TEST REG [format 0x%02X $addr] = [format 0x%02X $value] ---"
    write_mem $addr $value
    set r [read_mem $addr]
    puts "WRITE = [format "%08b" $value]"
    puts "READ  = $r"
}

# ----------------------------------------------------------
# EJECUCIÓN
# ----------------------------------------------------------

detect_hardware

puts "\n===== TEST WIDTH ====="
test_reg 0xF0 0x40
test_reg 0xF1 0x01

puts "\n===== TEST HEIGHT ====="
test_reg 0xF2 0xF0
test_reg 0xF3 0x00

puts "\n===== TEST SCALE ====="
test_reg 0xF4 0xC0
test_reg 0xF5 0x00

puts "\n===== TEST MODE ====="
test_reg 0xF6 0x01
puts "Start enviado. Revisa start_proc_pulse en SignalTap."

puts "\n===== TEST STATUS ====="
test_reg 0xF7 0x03   ;# busy=1, done=1 (solo prueba)


puts "\n===== TEST FSM ====="
# Poner step_mode = 1 (F9 bit1)
test_reg 0xF9 0x02

# Iniciar (F6 bit0)
test_reg 0xF6 0x01

# Generar pulso (F9 bit0 = 1) -> pulse + auto-clear
test_reg 0xF9 0x03   ;# set bit0=1 and bit1=1
test_reg 0xF9 0x02   ;# clear bit0 (return to step_mode)
# Repetir el set/clear para más pasos


puts "\n===== FIN ====="
