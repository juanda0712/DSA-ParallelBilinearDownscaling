# ==============================================================================
# SCRIPT DINAMICO DEFINITIVO (run_fpga.tcl)
# ==============================================================================

# 1. LEER ARGUMENTOS
if { $argc < 3 } {
    puts "ERROR: Faltan argumentos. Uso: quartus_stp -t run_fpga.tcl W H SCALE"
    exit 1
}
set W_IN  [lindex $argv 0]
set H_IN  [lindex $argv 1]
set S_HEX [lindex $argv 2]

# Calcular limite de lectura seguro (aprox W*H)
set OUT_LIMIT [expr ($W_IN * $H_IN)]

if {[catch {package require ::quartus::stp} err]} { puts "Error STP: $err" }

# ------------------------------------------------------------------------------
# 2. CONEXIÓN (Lógica Robusta de test3.tcl)
# ------------------------------------------------------------------------------
puts "\n== 1. CONECTANDO HARDWARE =="
set hw_name [lindex [get_hardware_names] 0]
if {$hw_name == ""} { puts "ERROR: No hay cables."; exit }

set dev_name [lindex [get_device_names -hardware_name $hw_name] 0]
foreach dev [get_device_names -hardware_name $hw_name] {
    if {[string match "@2*" $dev]} { set dev_name $dev; break }
}
puts "--> Cable: $hw_name"
puts "--> Device: $dev_name"

if { [catch {
    open_device -hardware_name $hw_name -device_name $dev_name
    device_lock -timeout 10000
} err] } { puts "ERROR AL ABRIR: $err"; exit }
puts "--> Conexión OK.\n"

# ------------------------------------------------------------------------------
# 3. FUNCIONES (27 Bits)
# ------------------------------------------------------------------------------
proc write_mem {addr19 val8} {
    set a [format "%019b" $addr19]
    set d [format "%08b" $val8]
    device_virtual_ir_shift -instance 0 -ir_value 3 -no_captured_ir_value
    device_virtual_dr_shift -instance 0 -dr_value "${a}${d}" -length 27
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
}
proc read_mem {addr19} {
    set a [format "%019b" $addr19]
    device_virtual_ir_shift -instance 0 -ir_value 2 -no_captured_ir_value
    device_virtual_dr_shift -instance 0 -dr_value "${a}00000000" -length 27
    set resp [device_virtual_dr_shift -instance 0 -dr_value "000000000000000000000000000" -length 27]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    return [string range $resp 19 26]
}
proc write_reg {idx val} {
    set i [format "%04b" $idx]
    set v [format "%08b" $val]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    device_virtual_dr_shift -instance 0 -dr_value "0000${i}${v}" -length 16
}
proc read_status {} {
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    set st [device_virtual_dr_shift -instance 0 -dr_value "0000000000000000" -length 16]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    return $st
}
proc wait_busy_low {} {
    for {set i 0} {$i < 1000} {incr i} { 
        set st [read_status]
        if {[string index $st 15] == "0"} { return 1 } 
        after 10
    }
    return 0
}
proc read_counter {addr_l} {
    set val_l_bin [read_mem $addr_l]
    set val_h_bin [read_mem [expr {$addr_l + 1}]]
    scan $val_l_bin %b val_l_int; scan $val_h_bin %b val_h_int
    return [expr {($val_h_int << 8) | $val_l_int}]
}

# ------------------------------------------------------------------------------
# 4. EJECUCIÓN
# ------------------------------------------------------------------------------
proc test_stepping {} {
    puts "\n== 8. TEST STEPPING =="
    write_reg 6 0x00 ; write_reg 9 0x02 
    puts "   -> Step Mode ON. Start..."
    write_reg 6 0x01 ; write_reg 6 0x00
    after 20
    set st [read_status]
    if {[string index $st 15] == "1"} {
        puts "   -> EXITO: HW Pausado. Enviando paso..."
        write_reg 9 0x03 ; write_reg 9 0x02 
        puts "   -> Liberando..."
        write_reg 9 0x00
        if {[wait_busy_low]} { puts "   -> Stepping OK." }
    } else {
        puts "   -> ERROR: No pausó."
        write_reg 9 0x00
    }
}

if { [catch {
    # 1. CARGA
    puts "== 2. CARGA (${W_IN}x${H_IN}) =="
    for {set y 0} {$y < $H_IN} {incr y} {
        for {set x 0} {$x < $W_IN} {incr x} {
            set addr [expr ($y * $W_IN) + $x]
            set val [expr ((($y + 1) * 16) + $x) % 256]
            write_mem $addr $val
        }
    }
    puts "   Carga lista.\n"

    # 2. CONFIGURACION CON LOGS

    puts "== 3. CONFIGURANDO PARAMETROS =="
    
    # Configurar Ancho (Registros 0 y 1)
    puts "   -> Escribiendo Ancho (W): $W_IN"
    write_reg 0 [expr $W_IN & 0xFF]
    write_reg 1 [expr ($W_IN >> 8) & 0xFF]

    # Configurar Alto (Registros 2 y 3)
    puts "   -> Escribiendo Alto (H): $H_IN"
    write_reg 2 [expr $H_IN & 0xFF]
    write_reg 3 [expr ($H_IN >> 8) & 0xFF]

    # Configurar Escala (Registros 4 y 5)
    puts "   -> Escribiendo Escala (Hex): $S_HEX"
    write_reg 4 $S_HEX 
    write_reg 5 0x00

    # 3. SECUENCIAL
    puts "\n== 4. EJECUTANDO SECUENCIAL =="
    write_reg 6 0x00 ;# Mode 0
    write_reg 6 0x01 ;# Start
    write_reg 6 0x00
    wait_busy_low
    
    # LEER Y ENVIAR DATOS SECUENCIALES
    set seq_res [list]
    for {set k 0} {$k < $OUT_LIMIT} {incr k} {
         set r [read_mem [expr 0x40000 + $k]]
         scan $r %b d; lappend seq_res $d
    }
    puts "\n   DEBUG: LECTURA DE CONTADORES (Post-Secuencial):"
        set flops [read_counter 0x58000]
        puts "   -> FLOPs: $flops"
        set reads [read_counter 0x58002]
        puts "   -> Lecturas: $reads"
        set writes [read_counter 0x58004]
        puts "   -> Escrituras: $writes"
    puts "DATA_SEQ: $seq_res"

    # 4. LIMPIEZA
    puts "\n== 5. LIMPIANDO SALIDA =="
    set clr_lim [expr ($W_IN * $H_IN)]
    for {set k 0} {$k < $clr_lim} {incr k} { write_mem [expr 0x40000 + $k] 0 }

    # 5. SIMD
    puts "\n== 6. EJECUTANDO SIMD =="
    write_reg 6 0x01 ;# Mode 1
    write_reg 6 0x01 ;# Start
    write_reg 6 0x00
    if {[wait_busy_low]} {
        set f [read_counter 0x58000]
        set ly [read_counter 0x58008]
        set la [read_counter 0x5800A]
        set st [read_mem 0x5800B]
        puts "   -> INFO: FLOPs=$f, LastY=$ly, LastAddr=$la, State=$st"
    }

    # LEER Y ENVIAR DATOS SIMD
    set simd_res [list]
    for {set k 0} {$k < $OUT_LIMIT} {incr k} {
         set r [read_mem [expr 0x40000 + $k]]
         scan $r %b d; lappend simd_res $d
    }
    puts "DATA_SIMD: $simd_res"

    # 6. EXTRAS
    test_stepping
    
    set flops [read_counter 0x58000]
    set reads [read_counter 0x58002]
    set writes [read_counter 0x58004]
    puts "\n== 9. CONTADORES FINALES: F=$flops, R=$reads, W=$writes =="

} res] } { puts "\nERROR CRITICO: $res" }

puts "\n== Desconectando =="
catch {device_unlock}
catch {close_device}
puts "Fin."