# ==============================================================================
# SCRIPT DE PRUEBA COMPLETA (CORREGIDO)
# ==============================================================================

if {[catch {package require ::quartus::stp} err]} { puts "Error STP: $err" }

# ------------------------------------------------------------------------------
# 1. CONEXIÓN 
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
} err] } {
    puts "ERROR AL ABRIR: $err"; exit
}
puts "--> Conexión OK.\n"

# ------------------------------------------------------------------------------
# 2. FUNCIONES DE 27 BITS
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
    puts "   Esperando procesamiento..."
    for {set i 0} {$i < 1000} {incr i} { 
        set st [read_status]
        # Check Busy Bit (Index 15)
        if {[string index $st 15] == "0"} { return 1 } 
        after 10
    }
    puts "   TIMEOUT (Hardware pegado/Busy alto)."
    return 0
}

proc read_counter {addr_l} {
    set val_l_bin [read_mem $addr_l]
    set val_h_bin [read_mem [expr {$addr_l + 1}]]
    scan $val_l_bin %b val_l_int
    scan $val_h_bin %b val_h_int
    return [expr {($val_h_int << 8) | $val_l_int}]
}

# ------------------------------------------------------------------------------
# 8. TEST DE STEPPING (CORREGIDO)
# ------------------------------------------------------------------------------
proc test_stepping {} {
    puts "\n== 8. TEST DE STEPPING (Modo Secuencial, 1 paso) =="
    
    # 1. Asegurar MODO SECUENCIAL (Reg 6 = 0x00)
    write_reg 6 0x00 
    
    # 2. Configurar modo Stepping (reg 9, bit 1 = 1) -> 0x02
    write_reg 9 0x02 
    puts "   -> Modo Stepping Activo."
    
    # 3. PRIMER PULSO: Usamos REG 6 (Start) para iniciar, NO Reg 9
    puts "   -> Enviando START (Reg 6)..."
    write_reg 6 0x01
    write_reg 6 0x00
    
    # 4. Esperar que Busy suba (El HW debe pausarse en INIT)
    after 20
    set st [read_status]
    set busy_bit [string index $st 15]

    if {$busy_bit == "1"} {
        puts "   -> EXITOSO: Busy subió (Status: $st). HW en Pausa."
        
        # 5. Enviar un paso (Reg 9 bit 0)
        puts "   -> Enviando un Paso (Reg 9)..."
        write_reg 9 0x03 ;# Bit 1 (Mode) + Bit 0 (Pulse)
        write_reg 9 0x02 ;# Bit 1 (Mode) only
        
        # 6. Liberar ejecución
        puts "   -> Desactivando Stepping (Free Run)..."
        write_reg 9 0x00
        
        if {[wait_busy_low]} {
            puts "   -> Stepping completado correctamente."
            return 1
        }
    } else {
        puts "   -> ERROR: HW no se pausó (Status: $st). Stepping falló."
        write_reg 9 0x00
        return 0
    }
}


# ------------------------------------------------------------------------------
# 3. EJECUCIÓN DE PRUEBAS
# ------------------------------------------------------------------------------

if { [catch {

    # ---------------------------------------------------------
    # CONFIGURACIÓN
    # ---------------------------------------------------------
    set W_IN 8
    set H_IN 4
    
    puts "== 2. CARGANDO IMAGEN DE PRUEBA (${W_IN}x${H_IN}) =="
    for {set y 0} {$y < $H_IN} {incr y} {
        for {set x 0} {$x < $W_IN} {incr x} {
            set addr [expr ($y * $W_IN) + $x]
            set val [expr (($y + 1) * 16) + $x]
            write_mem $addr $val
        }
    }
    puts "   Carga lista."

    puts "== 3. CONFIGURANDO PARAMETROS =="
    write_reg 0 0x08 ;# Width L
    write_reg 1 0x00 ;# Width H
    write_reg 2 0x04 ;# Height L
    write_reg 3 0x00 ;# Height H
    write_reg 4 0x80 ;# Scale L (0.5)
    write_reg 5 0x00 ;# Scale H

    # ---------------------------------------------------------
    # TEST A: MODO SECUENCIAL
    # ---------------------------------------------------------
    puts "\n== 4. EJECUTANDO MODO SECUENCIAL (Mode 0) =="
    write_reg 6 0x00 ;# Mode 0
    write_reg 6 0x01 ;# Start
    write_reg 6 0x00 ;# Stop

    if {[wait_busy_low]} {
        puts "   -> Secuencial Terminado."
        
        puts "\n   DEBUG: LECTURA DE CONTADORES (Post-Secuencial):"
        set flops [read_counter 0x58000]
        puts "   -> FLOPs: $flops"
        set reads [read_counter 0x58002]
        puts "   -> Lecturas: $reads"
        set writes [read_counter 0x58004]
        puts "   -> Escrituras: $writes"

    } else {
        puts "   -> ERROR: Secuencial falló."
    }
    
    set seq_results [list]
    puts "   Leyendo Salida SEQ..."
    for {set y 0} {$y < 2} {incr y} {
        for {set x 0} {$x < 4} {incr x} {
            set addr [expr 0x40000 + ($y * 4) + $x]
            set r [read_mem $addr]
            scan $r %b d
            lappend seq_results $d
        }
    }
    puts "   Resultados SEQ: $seq_results"

    # ---------------------------------------------------------
    # LIMPIEZA
    # ---------------------------------------------------------
    puts "\n== 5. LIMPIANDO SALIDA (Borrando 0x40000...) =="
    for {set k 0} {$k < 32} {incr k} {
        write_mem [expr 0x40000 + $k] 0
    }

    # ---------------------------------------------------------
    # TEST B: MODO SIMD
    # ---------------------------------------------------------
    puts "\n== 6. EJECUTANDO MODO SIMD (Mode 1) =="
    write_reg 6 0x01 ;# Mode 1 (SIMD)
    
    write_reg 6 0x01
    write_reg 6 0x00 
    
    if {[wait_busy_low]} {
        puts "   -> SIMD Terminado."
        
        set f [read_counter 0x58000]
        set last_y [read_counter 0x58008]
        set last_addr [read_counter 0x5800A]
        set final_st [read_mem 0x5800B] ;# Nuevo debug
        
        puts "   -> Stats SIMD: FLOPs=$f"
        puts "   -> DEBUG INFO: Ultima Fila (dst_y)=$last_y, Ultima Direccion Leida=$last_addr, FinalState=$final_st"
        
    } else {
        puts "   -> ERROR: SIMD falló o timeout."
    }

    set simd_results [list]
    puts "   Leyendo Salida SIMD..."
    for {set y 0} {$y < 2} {incr y} {
        for {set x 0} {$x < 4} {incr x} {
            set addr [expr 0x40000 + ($y * 4) + $x]
            set r [read_mem $addr]
            scan $r %b d
            lappend simd_results $d
        }
    }
    puts "   Resultados SIMD: $simd_results"

    # ---------------------------------------------------------
    # COMPARACIÓN
    # ---------------------------------------------------------
    puts "\n== 7. VEREDICTO FINAL =="
    if {$seq_results == $simd_results} {
        puts "   ¡EXITO! Los resultados Secuencial y SIMD coinciden."
        puts "   Valores: $seq_results"
    } else {
        puts "   DIFERENCIA DETECTADA."
        puts "   SEQ : $seq_results"
        puts "   SIMD: $simd_results"
    }

    #==========================================================
    # 8. TEST STEPPING
    #==========================================================
    test_stepping

    #==========================================================
    # 9. LECTURA FINAL
    #==========================================================
    puts "\n== 9. LECTURA FINAL DE CONTADORES =="
    set flops [read_counter 0x58000]
    puts "   -> FLOPs: $flops"
    set writes [read_counter 0x58004]
    puts "   -> Escrituras de Memoria: $writes"
    set debug_y [read_counter 0x58008]
    puts "   -> Debug Row (dst_y final): $debug_y"
    set debug_addr [read_counter 0x5800A]
    puts "   -> Debug Addr (Last Fetch): $debug_addr"
    

} res] } {
    puts "\nERROR CRITICO: $res"
}

puts "\n== Desconectando =="
catch {device_unlock}
catch {close_device}
puts "Fin."