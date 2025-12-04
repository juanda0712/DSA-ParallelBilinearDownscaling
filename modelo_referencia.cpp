#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>
#include <cstdint>
#include <cstdlib>

// =========================================================
// BIBLIOTECA PUNTO FIJO Q8.8 (ASCII ONLY)
// =========================================================

// Tipo: 16 bits (8 entero, 8 fraccional)
typedef int16_t q8_8_t;

// Conversion: Int -> Q8.8
q8_8_t to_q8_8(int x) {
    return (q8_8_t)(x << 8);
}

// Conversion: Float -> Q8.8
q8_8_t float_to_q8_8(float x) {
    return (q8_8_t)(x * 256.0f);
}

// Conversion: Q8.8 -> Int 8 bits (Con redondeo y saturacion)
uint8_t from_q8_8_sat(q8_8_t x) {
    // Sumar 0.5 (0x0080) para redondeo
    int32_t tmp = x + 0x0080;
    
    // Quitar parte fraccional
    int32_t res = tmp >> 8;

    // Saturacion
    if (res < 0) return 0;
    if (res > 255) return 255;
    return (uint8_t)res;
}

// Multiplicacion Q8.8
q8_8_t q8_8_mul(q8_8_t a, q8_8_t b) {
    int32_t prod = (int32_t)a * (int32_t)b;
    return (q8_8_t)(prod >> 8);
}

// Interpolacion Lineal (Lerp)
q8_8_t lerp(q8_8_t a, q8_8_t b, q8_8_t t) {
    // a + t*(b-a)
    q8_8_t diff = b - a;
    q8_8_t term = q8_8_mul(diff, t);
    return a + term;
}

// =========================================================
// MAIN
// =========================================================

int main(int argc, char* argv[]) {
    // Argumentos: <W> <H> <Scale>
    if (argc < 4) {
        return 1;
    }

    const int W_IN = std::atoi(argv[1]);
    const int H_IN = std::atoi(argv[2]);
    const float SCALE_FLOAT = std::atof(argv[3]);
    
    // Dimensiones Salida
    const int W_OUT = W_IN * SCALE_FLOAT;
    const int H_OUT = H_IN * SCALE_FLOAT;

    // Generar Imagen (Patron Determinista)
    // Val = ((y + 1) * 16) + x
    std::vector<uint8_t> input_img(W_IN * H_IN);
    for (int y = 0; y < H_IN; y++) {
        for (int x = 0; x < W_IN; x++) {
            int val = ((y + 1) * 16) + x;
            input_img[y * W_IN + x] = (uint8_t)(val % 256);
        }
    }

    // Procesamiento
    q8_8_t step_q = float_to_q8_8(1.0f / SCALE_FLOAT);
    int32_t src_acc_y = 0;

    // Imprimir solo numeros para Python
    for (int dy = 0; dy < H_OUT; dy++) {
        int32_t src_acc_x = 0;
        for (int dx = 0; dx < W_OUT; dx++) {
            int sy_int = (src_acc_y >> 8);
            q8_8_t fy = (src_acc_y & 0xFF) << 8;
            
            int sx_int = (src_acc_x >> 8);
            q8_8_t fx = (src_acc_x & 0xFF) << 8;

            // Clamping
            if (sx_int >= W_IN - 1) sx_int = W_IN - 2;
            if (sy_int >= H_IN - 1) sy_int = H_IN - 2;

            uint8_t p00 = input_img[sy_int * W_IN + sx_int];
            uint8_t p10 = input_img[sy_int * W_IN + (sx_int + 1)];
            uint8_t p01 = input_img[(sy_int + 1) * W_IN + sx_int];
            uint8_t p11 = input_img[(sy_int + 1) * W_IN + (sx_int + 1)];

            q8_8_t q_p00 = to_q8_8(p00);
            q8_8_t q_p10 = to_q8_8(p10);
            q8_8_t q_p01 = to_q8_8(p01);
            q8_8_t q_p11 = to_q8_8(p11);

            q8_8_t top = lerp(q_p00, q_p10, fx);
            q8_8_t bot = lerp(q_p01, q_p11, fx);
            uint8_t out = from_q8_8_sat(lerp(top, bot, fy));

            std::cout << (int)out << " ";
            src_acc_x += step_q;
        }
        src_acc_y += step_q;
    }
    std::cout << std::endl;

    return 0;
}