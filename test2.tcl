# ==============================================================================
# SCRIPT DE PRUEBA COMPLETA (PROTOCOL ACTUALIZADO 19-BIT ADDRESSING)
# ==============================================================================

if {[catch {package require ::quartus::stp} err]} { puts "Error STP: $err" }

# ------------------------------------------------------------------------------
# 1. CONEXIÓN 
# ------------------------------------------------------------------------------
# (Bloque de conexión igual que tu original...)
set hw_name [lindex [get_hardware_names] 0]
set dev_name [lindex [get_device_names -hardware_name $hw_name] 0]
foreach dev [get_device_names -hardware_name $hw_name] {
    if {[string match "@2*" $dev]} { set dev_name $dev; break }
}
if { [catch { open_device -hardware_name $hw_name -device_name $dev_name; device_lock -timeout 10000 } err] } {
    puts "ERROR AL ABRIR: $err"; exit
}

# ------------------------------------------------------------------------------
# 2. FUNCIONES (ACTUALIZADAS A 27 BITS)
# DR_MEM = 19 bits Address + 8 bits Data = 27 bits
# ------------------------------------------------------------------------------

# Escribir Memoria (IR=3)
proc write_mem {addr19 val8} {
    set a [format "%019b" $addr19]
    set d [format "%08b" $val8]
    device_virtual_ir_shift -instance 0 -ir_value 3 -no_captured_ir_value
    # MODIFICADO: Length ahora es 27
    device_virtual_dr_shift -instance 0 -dr_value "${a}${d}" -length 27
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
}

# Leer Memoria (IR=2)
proc read_mem {addr19} {
    set a [format "%019b" $addr19]
    # Set Address
    device_virtual_ir_shift -instance 0 -ir_value 2 -no_captured_ir_value
    # MODIFICADO: Length ahora es 27
    device_virtual_dr_shift -instance 0 -dr_value "${a}00000000" -length 27
    # Read Data (shift 27 zeros out, read result)
    set resp [device_virtual_dr_shift -instance 0 -dr_value "000000000000000000000000000" -length 27]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    
    # La respuesta está en los últimos 8 bits (indices 19 a 26 del string si cuenta de LSB)
    # Tcl bitstring range: LSB is right. 
    # Pero Quartus STP devuelve string binario donde index 0 suele ser MSB o viceversa dependiendo versión.
    # En tu lógica original range 16 23 era Data. Ahora el offset aumenta en 3 bits.
    return [string range $resp 19 26]
}

# Escribir Registro (IR=1) -> NO CAMBIA (16 bits)
proc write_reg {idx val} {
    set i [format "%04b" $idx]
    set v [format "%08b" $val]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    device_virtual_dr_shift -instance 0 -dr_value "0000${i}${v}" -length 16
}

# Leer Registro (Status) -> NO CAMBIA
proc read_status {} {
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    set st [device_virtual_dr_shift -instance 0 -dr_value "0000000000000000" -length 16]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    return $st
}

proc wait_busy_low {} {
    puts "   Esperando procesamiento..."
    for {set i 0} {$i < 1000} {incr i} { 
        set st [read_status]
        if {[string index $st 15] == "0"} { return 1 } 
        after 10
    }
    puts "   TIMEOUT."
    return 0
}

proc read_counter {addr_l} {
    set val_l_bin [read_mem $addr_l]
    set val_h_bin [read_mem [expr {$addr_l + 1}]]
    scan $val_l_bin %b val_l_int
    scan $val_h_bin %b val_h_int
    set val [expr {($val_h_int << 8) | $val_l_int}]
    return $val
}

# ------------------------------------------------------------------------------
# 3. EJECUCIÓN 
# ------------------------------------------------------------------------------

if { [catch {
    
    # TEST CON IMAGEN PEQUEÑA (MISMA LOGICA, DISTINTAS DIRECCIONES)
    set W_IN 8
    set H_IN 4
    puts "== CARGANDO IMAGEN =="
    for {set y 0} {$y < $H_IN} {incr y} {
        for {set x 0} {$x < $W_IN} {incr x} {
            set addr [expr ($y * $W_IN) + $x]
            set val [expr (($y + 1) * 16) + $x]
            write_mem $addr $val
        }
    }

    # Configuración de registros (Igual)
    write_reg 0 0x08 ;# Width L
    write_reg 1 0x00 ;# Width H
    write_reg 2 0x04 ;# Height L
    write_reg 3 0x00 ;# Height H
    write_reg 4 0x80 ;# Scale L (0.5)
    write_reg 5 0x00 ;# Scale H

    # MODO SECUENCIAL
    puts "\n== EJECUTANDO SECUENCIAL =="
    write_reg 6 0x01 ;# Start SIMD (o Seq dependiendo de bit)
    write_reg 6 0x00 
    wait_busy_low

    # MODIFICADO: OFFSET LECTURA RESULTADOS = 0x40000 (262144)
    puts "   Leyendo Salida (Offset 0x40000)..."
    set seq_results [list]
    for {set y 0} {$y < 2} {incr y} {
        for {set x 0} {$x < 4} {incr x} {
            set addr [expr 0x40000 + ($y * 4) + $x] 
            set r [read_mem $addr]
            scan $r %b d
            lappend seq_results $d
        }
    }
    puts "   Resultados: $seq_results"

    # LECTURA DE CONTADORES (Direcciones nuevas 0x7FFF8)
    puts "\n== LECTURA DE PERFORMANCE COUNTERS =="
    set flops [read_counter 0x7FFF8]
    puts "   -> FLOPs: $flops"

} res] } {
    puts "\nERROR CRITICO: $res"
}

catch {device_unlock}
catch {close_device}
puts "Fin."