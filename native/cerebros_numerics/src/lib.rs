use half::f16;
use rayon::prelude::*;
use rustler::{Atom, Binary, Env, OwnedBinary, Term, Encoder};

rustler::init!("Elixir.Thunderline.Thunderbolt.Numerics.Native");

mod atoms {
    rustler::atoms! {
        error,
        badarg,
        overflow,
        alloc_failed
    }
}

fn error<'a>(env: Env<'a>, reason: &str) -> Term<'a> {
    use atoms::*;
    match reason {
        "badarg" => (error(), badarg()).encode(env),
        "overflow" => (error(), overflow()).encode(env),
        "alloc_failed" => (error(), alloc_failed()).encode(env),
        other => (error(), other.to_string()).encode(env),
    }
}

#[inline]
fn read_fp16_le_slice(bytes: &[u8]) -> Vec<f16> {
    // Interpret little-endian u16 pairs as f16
    bytes
        .chunks_exact(2)
        .map(|c| {
            let u = u16::from_le_bytes([c[0], c[1]]);
            f16::from_bits(u)
        })
        .collect()
}

#[inline]
fn write_fp16_le_slice(buf: &mut [u8], data: &[f16]) {
    for (i, &h) in data.iter().enumerate() {
        let u = h.to_bits();
        let [b0, b1] = u.to_le_bytes();
        let o = i * 2;
        buf[o] = b0;
        buf[o + 1] = b1;
    }
}

/// gemm_fp16_acc32(a_bin, b_bin, m, n, k) -> c_bin
/// A: (m×k) FP16 row-major, B: (k×n) FP16 row-major, C: (m×n) FP16 row-major
#[rustler::nif(schedule = "DirtyCpu")]
pub fn gemm_fp16_acc32<'a>(env: Env<'a>, a: Binary<'a>, b: Binary<'a>, m: usize, n: usize, k: usize) -> Term<'a> {
    // Validate shapes vs. buffers
    let expected_a = m.checked_mul(k).and_then(|x| x.checked_mul(2)).unwrap_or(usize::MAX);
    let expected_b = k.checked_mul(n).and_then(|x| x.checked_mul(2)).unwrap_or(usize::MAX);
    if a.as_slice().len() != expected_a || b.as_slice().len() != expected_b {
        return error(env, "badarg");
    }

    // Decode to f32 accum types
    let a_half = read_fp16_le_slice(a.as_slice());
    let b_half = read_fp16_le_slice(b.as_slice());
    let a_f32: Vec<f32> = a_half.iter().map(|h| f32::from(*h)).collect();
    let b_f32: Vec<f32> = b_half.iter().map(|h| f32::from(*h)).collect();

    // Compute C = A(m×k) * B(k×n) in f32
    let mn = match m.checked_mul(n) {
        Some(v) => v,
        None => return error(env, "overflow"),
    };
    let mut c_f32 = vec![0f32; mn];

    // Parallelize by rows for cache-friendliness
    c_f32
        .par_chunks_mut(n)
        .enumerate()
        .for_each(|(i, row)| {
            let a_row = &a_f32[i * k..(i + 1) * k];
            for j in 0..n {
                let mut acc: f32 = 0.0;
                // micro-tile along k
                let mut p = 0;
                while p + 7 < k {
                    acc += a_row[p + 0] * b_f32[(p + 0) * n + j];
                    acc += a_row[p + 1] * b_f32[(p + 1) * n + j];
                    acc += a_row[p + 2] * b_f32[(p + 2) * n + j];
                    acc += a_row[p + 3] * b_f32[(p + 3) * n + j];
                    acc += a_row[p + 4] * b_f32[(p + 4) * n + j];
                    acc += a_row[p + 5] * b_f32[(p + 5) * n + j];
                    acc += a_row[p + 6] * b_f32[(p + 6) * n + j];
                    acc += a_row[p + 7] * b_f32[(p + 7) * n + j];
                    p += 8;
                }
                while p < k {
                    acc += a_row[p] * b_f32[p * n + j];
                    p += 1;
                }
                row[j] = acc;
            }
        });

    // Cast to f16 and return as little-endian bytes
    let c_half: Vec<f16> = c_f32.into_iter().map(|x| f16::from_f32(x)).collect();

    let out_len = mn.checked_mul(2).unwrap_or(usize::MAX);
    let mut out = match OwnedBinary::new(out_len) {
        Some(b) => b,
        None => return error(env, "alloc_failed"),
    };

    write_fp16_le_slice(out.as_mut_slice(), &c_half);
    out.release(env).encode(env)
}
