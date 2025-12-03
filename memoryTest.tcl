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
# FUNCIONES MEMORIA (IR = 3)
# ===========================
proc write_mem {addr8 data8} {
    puts "Writing MEM ADDR=$addr8 DATA=$data8"

    open_port
    device_lock -timeout 10000

    # IR = 3  --> MEM
    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr8}${data8}"
    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]

    puts "DR sent:  $dr"
    puts "DR resp:  $resp"

    # IR = 1 --> BYPASS
    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port
}

proc read_mem {addr8} {
    puts "Reading MEM ADDR=$addr8"

    open_port
    device_lock -timeout 10000

    device_virtual_ir_shift -instance_index 0 -ir_value 3 -no_captured_ir_value

    set dr "${addr8}00000000"
    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]

    # Volver a BYPASS
    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port

    # La data viene en bits 8..15
    set data [string range $resp 8 15]

    puts "DATA READ = $data"
    return $data
}

# Helper: convierte valor decimal a cadena binaria de longitud 'bits'
proc to_bin {val bits} {
    set s ""
    for {set i [expr {$bits-1}]} {$i >= 0} {incr i -1} {
        append s [expr {($val >> $i) & 1}]
    }
    return $s
}

# ===========================
# FUNCIONES REGISTROS (IR = 5)
# ===========================
proc write_reg {index data} {
    if { $index < 0 || $index > 15 } {
        puts "ERROR: register index must be 0..15"
        return
    }
    if { $data < 0 || $data > 255 } {
        puts "ERROR: data must be 0..255"
        return
    }

    set opcode_bin [to_bin 1 4]   ;# 0001 = REG_WRITE
    set idx_bin    [to_bin $index 4]
    set data_bin   [to_bin $data 8]

    set dr "${opcode_bin}${idx_bin}${data_bin}"

    puts "WRITE_REG idx=$index data=$data DR=$dr"

    open_port
    device_lock -timeout 10000

    # IR = 5 --> REG
    device_virtual_ir_shift -instance_index 0 -ir_value 5 -no_captured_ir_value
    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]

    puts "DR sent: $dr"
    puts "DR resp: $resp"

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port
}

proc read_reg {index} {
    if { $index < 0 || $index > 15 } {
        puts "ERROR: register index must be 0..15"
        return
    }

    set opcode_bin [to_bin 2 4]   ;# 0010 = REG_READ
    set idx_bin    [to_bin $index 4]
    set dr "${opcode_bin}${idx_bin}00000000"

    puts "READ_REG idx=$index DR=$dr"

    open_port
    device_lock -timeout 10000

    device_virtual_ir_shift -instance_index 0 -ir_value 5 -no_captured_ir_value
    set resp [device_virtual_dr_shift -dr_value $dr -instance_index 0 -length 16]

    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    close_port

    puts "DR resp: $resp"

    # extraer bits 8..15 como antes
    set data_bin [string range $resp 8 15]

    set val 0
    foreach b [split $data_bin ""] {
        set val [expr {$val*2 + $b}]
    }

    puts "REG[$index] = $val (bin=$data_bin)"
    return $val
}

# ===========================
# PRUEBA AUTOMÁTICA
# ===========================
puts "=== TEST MEMORIA ==="
write_mem 00000101 10101010
set r [read_mem 00000101]
puts "Resultado final: $r"

puts "=== TEST REGISTROS ==="
write_reg 3 170
set rr [read_reg 3]
puts "Readback: $rr"
