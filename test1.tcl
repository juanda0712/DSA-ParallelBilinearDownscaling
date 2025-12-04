# ==============================================================================
# SCRIPT DE PRUEBA COMPLETA (PROTOCOL ACTUALIZADO 19-BIT ADDRESSING)
# ==============================================================================

if {[catch {package require ::quartus::stp} err]} { puts "Error STP: $err" }

# ------------------------------------------------------------------------------
# 1. CONEXIÓN (Protocolo Fuerza Bruta)
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
# 2. FUNCIONES DE 27 BITS (Protocolo 19-bit Address + 8-bit Data)
# ------------------------------------------------------------------------------

# Escribir Memoria (IR=3) -> Ahora usa 27 bits
proc write_mem {addr19 val8} {
    set a [format "%019b" $addr19]
    set d [format "%08b" $val8]
    device_virtual_ir_shift -instance 0 -ir_value 3 -no_captured_ir_value
    # CAMBIO: Length 27
    device_virtual_dr_shift -instance 0 -dr_value "${a}${d}" -length 27
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
}

# Leer Memoria (IR=2) -> Ahora usa 27 bits
proc read_mem {addr19} {
    set a [format "%019b" $addr19]
    # Set Address
    device_virtual_ir_shift -instance 0 -ir_value 2 -no_captured_ir_value
    # CAMBIO: Length 27
    device_virtual_dr_shift -instance 0 -dr_value "${a}00000000" -length 27
    # Read Data (shift 27 zeros out, read result)
    set resp [device_virtual_dr_shift -instance 0 -dr_value "000000000000000000000000000" -length 27]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    
    # CAMBIO: El dato está en los últimos 8 bits del string de 27 (indices 19 a 26)
    return [string range $resp 19 26]
}

# Escribir Registro (IR=1) -> ESTE NO CAMBIA (Sigue siendo 16 bits para Config)
proc write_reg {idx val} {
    set i [format "%04b" $idx]
    set v [format "%08b" $val]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    device_virtual_dr_shift -instance 0 -dr_value "0000${i}${v}" -length 16
}

# Leer Registro (Status, etc.) -> ESTE NO CAMBIA
proc read_reg {idx} {
    set i [format "%04b" $idx]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    set resp [device_virtual_dr_shift -instance 0 -dr_value "0000${i}00000000" -length 16]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    return [string range $resp 8 15] 
}

# Función auxiliar para leer el registro de estado (Status Reg 7)
proc read_status {} {
    # Usar IR=1 (REG_OP) para forzar la lectura del Status (Reg 7)
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    set st [device_virtual_dr_shift -instance 0 -dr_value "0000000000000000" -length 16]
    device_virtual_ir_shift -instance 0 -ir_value 1 -no_captured_ir_value
    return $st
}

# Esperar Busy=0
proc wait_busy_low {} {
    puts "   Esperando procesamiento..."
    for {set i 0} {$i < 1000} {incr i} { 
        set st [read_status]
        # Busy es el Bit 0 del registro de estado, que es el bit 15 del string 'st'
        if {[string index $st 15] == "0"} { return 1 } 
        after 10
    }
    puts "   TIMEOUT (Hardware pegado/Busy alto)."
    return 0
}

# Leer Contador de 16 bits
proc read_counter {addr_l} {
    # Lee LSB (addr_l)
    set val_l_bin [read_mem $addr_l]
    # Lee MSB (addr_l + 1)
    set val_h_bin [read_mem [expr {$addr_l + 1}]]
    
    scan $val_l_bin %b val_l_int
    scan $val_h_bin %b val_h_int
    
    set val [expr {($val_h_int << 8) | $val_l_int}]
    return $val
}

# ------------------------------------------------------------------------------
# 8. TEST DE STEPPING (Manejo de terminación rápida)
# ------------------------------------------------------------------------------
proc test_stepping {} {
    puts "\n== 8. TEST DE STEPPING (Modo Secuencial, 1 paso) =="
    
    # 1. Asegurar MODO SECUENCIAL (Reg 6 = 0x00)
    write_reg 6 0x00 
    
    # 2. Configurar modo Stepping (reg 9, bit 1 = 1)
    write_reg 9 0x02 
    puts "   -> Modo Stepping Activo."
    
    # 3. PRIMER PULSO: Inicia el proceso (IDLE -> INIT)
    write_reg 9 0x03
    puts "   -> Primer pulso de paso (INICIO) enviado."
    after 5 
    write_reg 9 0x02 ;# Desactiva solo el pulso (Mantiene Step Mode)
    
    # 4. Esperar que Busy suba (Validación de inicio)
    set busy_high 0
    set st ""
    for {set i 0} {$i < 1000} {incr i} {
        set st [read_status]
        set busy_bit [string index $st 15]
        set done_bit [string index $st 14]

        if {$busy_bit == "1"} { 
            set busy_high 1
            break
        }
        if {$done_bit == "1"} {
            puts "   -> Aviso: Proceso terminado instantáneamente (Done=1). Stepping no pudo detener la FSM."
            write_reg 9 0x00 
            return 1 
        }
        after 1
    }

    if {$busy_high == 0} {
        puts "   ERROR: Busy nunca subió (Status: $st)."
        write_reg 9 0x00 
        return 0
    }
    puts "   -> Busy Subió. Estado: $st."

    # 5. Forzar la salida del estado de detención
    write_reg 9 0x03 
    puts "   -> Pulso final de liberación enviado."
    after 5 
    
    # 6. Desactivar Stepping y dejar correr para terminar
    write_reg 9 0x00
    after 50 
    puts "   -> Modo Stepping Desactivado. Corriendo libre."
    
    if {[wait_busy_low]} {
        puts "   -> Proceso terminado. Stepping funcional."
        return 1
    } else {
        puts "   -> ERROR: Stepping: Timeout en modo libre."
        return 0
    }
}


# ------------------------------------------------------------------------------
# 3. EJECUCIÓN DE PRUEBAS
# ------------------------------------------------------------------------------

if { [catch {

    # ---------------------------------------------------------
    # CONFIGURACIÓN DEL ESCENARIO DE PRUEBA
    # Imagen de entrada: 8x4 píxeles (32 bytes)
    # Escala: 0.5
    # Imagen de salida esperada: 4x2 píxeles
    # ---------------------------------------------------------
    
    set W_IN 8
    set H_IN 4
    
    puts "== 2. CARGANDO IMAGEN DE PRUEBA (${W_IN}x${H_IN}) =="
    # Patrón: Fila 0 = 0x10, 0x11... Fila 1 = 0x20, 0x21...
    for {set y 0} {$y < $H_IN} {incr y} {
        for {set x 0} {$x < $W_IN} {incr x} {
            set addr [expr ($y * $W_IN) + $x]
            set val [expr (($y + 1) * 16) + $x]
            write_mem $addr $val
        }
    }
    puts "   Carga lista."

    # Configurar Registros Comunes
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
        
        # --- NUEVO: LEER CONTADORES AQUI (Mientras el HW está en estado DONE exitoso) ---
        puts "\n   DEBUG: LECTURA DE CONTADORES (Post-Secuencial):"
        set flops [read_counter 0x58000]
        puts "   -> FLOPs: $flops"
        set reads [read_counter 0x58002]
        puts "   -> Lecturas: $reads"
        set writes [read_counter 0x58004]
        puts "   -> Escrituras: $writes"
        # -------------------------------------------------------------------------------

    } else {
        puts "   -> ERROR: Secuencial falló."
    }
    
    # Leer Resultados SEQ
    set seq_results [list]
    puts "   Leyendo Salida SEQ..."
    # Salida esperada 4x2.
    for {set y 0} {$y < 2} {incr y} {
        for {set x 0} {$x < 4} {incr x} {
            # CAMBIO: Usar 0x40000 (262144) como base de salida
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
    
    # REINICIO START
    write_reg 6 0x01
    write_reg 6 0x00 
    
    if {[wait_busy_low]} {
        puts "   -> SIMD Terminado."
    } else {
        puts "   -> ERROR: SIMD falló o timeout."
    }

    # Leer Resultados SIMD
    set simd_results [list]
    puts "   Leyendo Salida SIMD..."
    for {set y 0} {$y < 2} {incr y} {
        for {set x 0} {$x < 4} {incr x} {
            # CAMBIO: Usar 0x40000 como base de salida
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
    # 9. LECTURA DE PERFORMANCE COUNTERS
    #==========================================================
    puts "\n== 9. LECTURA DE PERFORMANCE COUNTERS (Base 0x58000) =="
    
    # Flops: L en 0x58000
    set flops [read_counter 0x58000]
    puts "   -> FLOPs: $flops"
    
    # Reads: L en 0x58002
    set reads [read_counter 0x58002]
    puts "   -> Lecturas de Memoria: $reads"
    
    # Writes: L en 0x58004
    set writes [read_counter 0x58004]
    puts "   -> Escrituras de Memoria: $writes"

    # ... despues de leer writes ...
    # Debug Y (0x58008)
    set debug_y [read_counter 0x58008]
    puts "   -> Debug Row (dst_y final): $debug_y"
    

} res] } {
    puts "\nERROR CRITICO: $res"
}

puts "\n== Desconectando =="
catch {device_unlock}
catch {close_device}
puts "Fin."