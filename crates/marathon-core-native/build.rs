fn main() {
    cxx_build::bridge("src/lib.rs")
        .std("c++17")
        // GCC false positive in cxx's rust::Vec<T> constructor.
        .flag_if_supported("-Wno-maybe-uninitialized")
        .compile("marathon-core-native-bridge");
    println!("cargo:rerun-if-changed=src/lib.rs");
}
