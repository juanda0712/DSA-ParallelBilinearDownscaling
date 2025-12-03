# ===========================
# DETECTAR Y CONECTAR JTAG
# ===========================

global usbblaster_name
global test_device

set usbblaster_name ""
set test_device ""

# Detectar hardware USB-Blaster
foreach hw [get_hardware_names] {
    if { [string match "USB-Blaster*" $hw] || [string match "*DE-SoC*" $hw] } {
        set usbblaster_name $hw
        break
    }
}

if { $usbblaster_name == "" } {
    puts "ERROR: No USB-Blaster found!"
    return
}

# Detectar device @2
foreach dev [get_device_names -hardware_name $usbblaster_name] {
    if { [string match "@2*" $dev] } {
        set test_device $dev
        break
    }
}

if { $test_device == "" } {
    puts "ERROR: No @2 device found!"
    return
}

puts "Connected to:"
puts "  Hardware: $usbblaster_name"
puts "  Device:   $test_device"


# ===========================
# FUNCIONES open/close
# ===========================

proc open_port {} {
    global usbblaster_name
    global test_device
    open_device -hardware_name $usbblaster_name -device_name $test_device
}

proc close_port {} {
    catch {device_unlock}
    catch {close_device}
}

# ===========================
# FUNCIONES MEMORIA
# ===========================

proc write_mem {addr8 data8} {
    puts "Writing ADDR=$addr8 DATA=$data8"

    open_port
    device_lock -timeout 10000

    # IR=3 = MEM
    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "$addr8$data8"
    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]
    puts "DR sent: $dr"
    puts "DR resp: $resp"

    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    close_port
}

proc read_mem {addr8} {
    puts "Reading ADDR=$addr8"

    open_port
    device_lock -timeout 10000

    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    # DR = addr + 8bits de relleno
    set dr "${addr8}00000000"

    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]

    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    close_port

    # extraer bits 8..15
    set data [string range $resp 8 15]
    puts "DATA READ = $data"
    return $data
}



# ===========================
# PRUEBA AUTOMÁTICA
# ===========================

puts ""
puts "=== TEST MEMORIA ==="

write_mem 00000101 10101010
set r [read_mem 00000101]

puts "Resultado final: $r"
